import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:app_security/app_security.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/file_select/recent_files.dart';
import '../features/file_select/demo_database.dart';
import '../features/unlock/relock.dart';
import '../l10n/app_localizations.dart';
import '../shared/database/database_session.dart';
import '../shared/security/device_security.dart';
import '../shared/security/external_activity.dart';
import '../shared/settings/app_settings.dart';
import '../shared/storage/remote_storage.dart';
import 'device_integrity.dart';
import 'screen_protection.dart';

/// Orologio del blocco per inattività (sovrascrivibile nei test).
final sessionClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Testi della notifica del database aperto nella lingua del sistema, scelta
/// come fa `MaterialApp`: la notifica vive fuori dai widget.
final openNotificationTextsProvider = Provider<OpenNotificationTexts>((_) {
  final l10n = lookupAppLocalizations(
    basicLocaleListResolution(
      PlatformDispatcher.instance.locales,
      AppLocalizations.supportedLocales,
    ),
  );
  return OpenNotificationTexts(
    channel: l10n.openNotificationChannel,
    title: l10n.appTitle,
    text: l10n.openNotificationText,
    lock: l10n.openNotificationLock,
  );
});

/// `false` nei motori Flutter senza notifica del database aperto (compilazione
/// automatica, ADR-013): la notifica resta quella dell'app.
final openNotificationAllowedProvider = Provider<bool>((_) => true);

/// Protezione della sessione per tutta la vita dell'app, come `App.cs` di
/// Keepass2Android:
/// - blocco dopo [AppSettings.lockTimeout] senza interazioni, controllato
///   anche al ritorno in primo piano (con l'app sospesa il timer può non
///   scattare), con ritorno allo sblocco dello stesso database
///   ([RelockNotifier.lockAndReturn]);
/// - blocco a schermo spento se [AppSettings.lockOnScreenOff];
/// - blocco al passaggio in background se [AppSettings.lockInBackground],
///   esclusi gli stati transitori e le attività di sistema avviate dall'app;
/// - schermo protetto secondo [AppSettings.secureScreen];
/// - notifica del database aperto con "Blocca" se
///   [AppSettings.openNotification] (Android, ADR-012); il permesso per le
///   notifiche si chiede alla prima apertura di un database;
/// - alla chiusura, rilascio dei permessi dei file non ricordati nei recenti.
final sessionGuardProvider = Provider<SessionGuard>((ref) {
  ref.watch(demoDatabaseCleanupProvider);
  final guard = SessionGuard._(ref);
  ref.onDispose(guard._dispose);
  guard._start();
  return guard;
});

class SessionGuard {
  SessionGuard._(this._ref);

  final Ref _ref;
  DateTime? _lastActivity;
  Timer? _timer;
  StreamSubscription<void>? _screenOff;
  StreamSubscription<void>? _notificationLock;

  /// La notifica del database aperto deve essere visibile.
  bool _notificationWanted = false;

  /// Richiesta del permesso per le notifiche in corso.
  Future<void>? _permissionRequest;

  bool get _isOpen => _ref.read(databaseSessionProvider) != null;

  AppSettings get _settings => _ref.read(appSettingsProvider);

  AppSecurity get _security => _ref.read(appSecurityProvider);

  DateTime _now() => _ref.read(sessionClockProvider)();

  void _start() {
    _ref
      ..listen<DatabaseSession?>(databaseSessionProvider, _onSession)
      ..listen<AppSettings>(
        appSettingsProvider,
        _onSettings,
        fireImmediately: true,
      );
  }

  /// Interazione dell'utente: il tempo del blocco per inattività riparte.
  void userActivity() {
    if (!_isOpen) return;
    _lastActivity = _now();
    _schedule();
  }

  /// App tornata in primo piano: blocca se il tempo è già scaduto.
  void appResumed() {
    _ref
        .read(externalActivityProvider)
        .appLifecycleChanged(AppLifecycleState.resumed);
    final timeout = _settings.lockTimeout;
    final last = _lastActivity;
    if (timeout != null &&
        last != null &&
        _isOpen &&
        _now().difference(last) >= timeout) {
      _lock(automatic: true);
    }
    unawaited(_resumeWork());
  }

  /// Solo `hidden` e `paused` rappresentano un'uscita reale dall'app.
  /// `inactive` comprende anche biometria, permessi e pannelli di sistema.
  void appLifecycleChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      appResumed();
      return;
    }
    final external = _ref.read(externalActivityProvider);
    external.appLifecycleChanged(state);
    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        _settings.lockInBackground &&
        !external.isActive) {
      _lock(automatic: true);
    }
  }

  Future<void> _resumeWork() async {
    await _ref.read(integrityStatusProvider.notifier).recheck();
    if (!_ref.mounted ||
        _ref.read(integrityStatusProvider) != IntegrityStatus.trusted) {
      return;
    }
    if (_ref.read(screenProtectionProvider).availableInBuild) {
      await _applyScreenProtection(_settings.secureScreen);
    }
    if (!_ref.mounted || !_isOpen || !_settings.cacheRemoteFiles) {
      return;
    }
    final session = _ref.read(databaseSessionProvider);
    if (session == null || !RemoteStorage.handles(session.file)) return;
    final notifier = _ref.read(databaseSessionProvider.notifier);
    if (notifier.isSaving) return;
    try {
      await notifier.synchronize();
    } on Object {
      // Lo stato della sessione rende visibile l'errore; nessun retry o log.
    }
  }

  void _onSession(DatabaseSession? previous, DatabaseSession? next) {
    if (next == null) {
      _cancelTimer();
      _lastActivity = null;
      // Credenziali non ricordate dei server: si chiedono alla prossima
      // apertura (D30).
      _ref.read(remoteSessionProvider).clear();
      if (previous != null) {
        unawaited(
          _ref
              .read(recentFilesRepositoryProvider)
              .releaseUnused(
                _ref.read(databaseSessionProvider.notifier).takeClosedFiles(),
              ),
        );
      }
    } else if (previous == null) {
      userActivity();
    }
    _updateScreenOff();
    _updateNotification();
  }

  void _onSettings(AppSettings? previous, AppSettings next) {
    if (previous?.secureScreen != next.secureScreen) {
      unawaited(_applyScreenProtection(next.secureScreen));
    }
    if (previous != null && previous.lockTimeout != next.lockTimeout) {
      _schedule();
    }
    // Notifica attivata dalle impostazioni: il permesso si chiede di nuovo.
    if (previous != null &&
        !previous.openNotification &&
        next.openNotification) {
      unawaited(_askNotificationPermission(again: true));
    }
    _updateScreenOff();
    _updateNotification();
  }

  Future<void> _applyScreenProtection(bool enabled) async {
    final canContinue = await _ref
        .read(screenProtectionStatusProvider.notifier)
        .apply(enabled: enabled);
    if (!canContinue && _ref.mounted && _isOpen) _lock();
  }

  void _schedule() {
    _cancelTimer();
    final timeout = _settings.lockTimeout;
    final last = _lastActivity;
    if (timeout == null || last == null || !_isOpen) return;
    final remaining = timeout - _now().difference(last);
    _timer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      () => _lock(automatic: true),
    );
  }

  void _updateScreenOff() {
    final wanted = _isOpen && _settings.lockOnScreenOff;
    if (wanted == (_screenOff != null)) return;
    if (wanted) {
      _screenOff = _ref
          .read(appSecurityProvider)
          .screenOff()
          .listen((_) => _lock(), onError: (Object _) {});
    } else {
      unawaited(_screenOff?.cancel());
      _screenOff = null;
    }
  }

  /// Notifica con "Blocca" mentre il database è aperto (D19, ADR-012). Senza
  /// servizio in primo piano: se il sistema chiude l'app la toglie il codice
  /// nativo.
  void _updateNotification() {
    final wanted =
        _isOpen &&
        _settings.openNotification &&
        _security.supportsOpenNotification &&
        _ref.read(openNotificationAllowedProvider);
    if (wanted == _notificationWanted) return;
    _notificationWanted = wanted;
    if (wanted) {
      unawaited(_showNotification());
    } else {
      unawaited(_notificationLock?.cancel());
      _notificationLock = null;
      unawaited(_security.hideOpenNotification());
    }
  }

  Future<void> _showNotification() async {
    final security = _security;
    final texts = _ref.read(openNotificationTextsProvider);
    await _askNotificationPermission();
    // Bloccato o impostazione spenta mentre l'utente rispondeva.
    if (!_notificationWanted) return;
    // Notifiche negate o disattivate: l'app funziona senza.
    if (!await security.showOpenNotification(texts)) return;
    if (!_notificationWanted) {
      await security.hideOpenNotification();
      return;
    }
    _notificationLock ??= security.notificationLock().listen(
      (_) => _lock(),
      onError: (Object _) {},
    );
  }

  /// Chiede il permesso per le notifiche alla prima apertura di un database;
  /// con [again] (impostazione appena attivata) anche se è già stato chiesto.
  Future<void> _askNotificationPermission({bool again = false}) {
    final pending = _permissionRequest;
    if (pending != null) return pending;
    final security = _security;
    final repository = _ref.read(appSettingsRepositoryProvider);
    if (!security.supportsOpenNotification ||
        !_ref.read(openNotificationAllowedProvider) ||
        (!again && repository.notificationPermissionRequested)) {
      return Future.value();
    }
    final request = () async {
      await repository.markNotificationPermissionRequested();
      await security.requestNotificationPermission();
    }();
    _permissionRequest = request;
    return request.whenComplete(() => _permissionRequest = null);
  }

  void _lock({bool automatic = false}) {
    if (_isOpen) {
      _ref.read(relockProvider.notifier).lockAndReturn(automatic: automatic);
    }
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _dispose() {
    _cancelTimer();
    unawaited(_screenOff?.cancel());
    _screenOff = null;
    _notificationWanted = false;
    unawaited(_notificationLock?.cancel());
    _notificationLock = null;
  }
}

/// Inoltra a [SessionGuard] i tocchi dell'utente e il ritorno in primo piano
/// (`onUserInteraction` e `OnResume` delle activity di Keepass2Android).
class SessionActivity extends ConsumerStatefulWidget {
  const SessionActivity({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SessionActivity> createState() => _SessionActivityState();
}

class _SessionActivityState extends ConsumerState<SessionActivity> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        ref.read(sessionGuardProvider).appLifecycleChanged(state);
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ref.read(sessionGuardProvider).userActivity(),
      child: widget.child,
    );
  }
}
