import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/device_blocked/device_blocked_view.dart';
import '../l10n/app_localizations.dart';
import '../shared/settings/app_locale.dart';
import '../shared/settings/app_settings.dart';
import 'device_integrity.dart';
import 'linked_database_host.dart';
import 'router.dart';
import 'screen_protection.dart';
import 'screen_protection_warning.dart';
import 'session_guard.dart';
import 'theme.dart';

class KeePassMobileApp extends ConsumerWidget {
  const KeePassMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Blocco per inattività e a schermo spento, schermo protetto.
    ref.watch(sessionGuardProvider);
    final locale = ref.watch(appLocaleProvider);
    final themeMode = ref.watch(appSettingsProvider.select((s) => s.themeMode));
    final integrity = ref.watch(integrityStatusProvider);
    final protection = ref.watch(screenProtectionStatusProvider);
    // Dispositivo non ancora verificato o non affidabile (D9): niente router,
    // file recenti, impostazioni o database.
    if (integrity != IntegrityStatus.trusted ||
        protection == ScreenProtectionStatus.checking ||
        protection == ScreenProtectionStatus.warning) {
      return MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: themeMode,
        localizationsDelegates: [
          ...GlobalMaterialLocalizations.delegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        home: switch (integrity) {
          IntegrityStatus.compromised => const DeviceBlockedView(),
          IntegrityStatus.trusted
              when protection == ScreenProtectionStatus.warning =>
            const ScreenProtectionWarning(),
          _ => const Scaffold(),
        },
      );
    }
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      builder: (context, child) => SessionActivity(
        child: LinkedDatabaseHost(child: child ?? const SizedBox.shrink()),
      ),
      localizationsDelegates: [
        ...GlobalMaterialLocalizations.delegates,
        ...AppLocalizations.localizationsDelegates,
      ],
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      routerDelegate: ref.watch(routerProvider).routerDelegate,
      routeInformationParser: ref.watch(routerProvider).routeInformationParser,
      routeInformationProvider: ref
          .watch(routerProvider)
          .routeInformationProvider,
      backButtonDispatcher: ref.watch(appBackButtonDispatcherProvider),
    );
  }
}

final appBackButtonDispatcherProvider = Provider((ref) {
  final dispatcher = _AppBackButtonDispatcher(
    ref.watch(routerProvider),
    ref.watch(rootOverlayObserverProvider),
    ref.watch(shellNavigatorKeyProvider),
  );
  ref.onDispose(dispatcher.dispose);
  return dispatcher;
});

class _AppBackButtonDispatcher extends RootBackButtonDispatcher {
  _AppBackButtonDispatcher(
    this._router,
    this._overlayObserver,
    this._shellNavigatorKey,
  );
  final GoRouter _router;
  final RootOverlayObserver _overlayObserver;
  final GlobalKey<NavigatorState> _shellNavigatorKey;

  bool _handlingOverlayBack = false;
  final List<ModalRoute<dynamic>> _guardedRoutes = [];
  final _overlayBackGuard = _OverlayBackPopEntry();

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    _releaseOverlayBack();
    final rootNavigator = _router.routerDelegate.navigatorKey.currentState;
    if (!_overlayObserver.hasOverlay || rootNavigator == null) return false;
    _handlingOverlayBack = true;
    // Flutter notifies every observer. Veto both navigators' predictive pops
    // before their gesture detectors receive the same event.
    for (final navigator in [rootNavigator, _shellNavigatorKey.currentState]) {
      navigator?.popUntil((route) {
        if (route is ModalRoute<dynamic>) {
          _guardedRoutes.add(route);
          route.registerPopEntry(_overlayBackGuard);
        }
        return true;
      });
    }
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {}

  @override
  void handleCommitBackGesture() {
    if (!_handlingOverlayBack) return;
    _releaseOverlayBack();
    final rootNavigator = _router.routerDelegate.navigatorKey.currentState;
    if (_overlayObserver.hasOverlay && rootNavigator != null) {
      unawaited(rootNavigator.maybePop());
    }
  }

  @override
  void handleCancelBackGesture() => _releaseOverlayBack();

  void _releaseOverlayBack() {
    _handlingOverlayBack = false;
    for (final route in _guardedRoutes) {
      route.unregisterPopEntry(_overlayBackGuard);
    }
    _guardedRoutes.clear();
  }

  void dispose() {
    _releaseOverlayBack();
    _overlayBackGuard.canPopNotifier.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    final rootNavigator = _router.routerDelegate.navigatorKey.currentState;
    if (_overlayObserver.hasOverlay && rootNavigator != null) {
      return rootNavigator.maybePop();
    }
    if (await super.didPopRoute()) return true;
    final shellNavigator = _shellNavigatorKey.currentState;
    if (shellNavigator != null && await shellNavigator.maybePop()) return true;
    return false;
  }
}

class _OverlayBackPopEntry extends PopEntry<dynamic> {
  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier(false);
}
