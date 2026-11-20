import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Schema delle app Android nei campi delle voci (`androidapp://`, come
/// Keepass2Android).
const androidAppScheme = 'androidapp://';

/// Richiesta di compilazione automatica: app che chiede i valori e dominio che
/// dichiara (solo Android, `AutofillActivity`).
@immutable
class AutofillRequest {
  const AutofillRequest({
    required this.packageName,
    this.webDomain,
    this.isBrowser = false,
    this.hasUserName = true,
    this.hasPassword = true,
    this.save = false,
    this.userName,
  });

  final String packageName;

  /// Dominio dichiarato dalla pagina; un'app qualsiasi può dichiararne uno.
  final String? webDomain;

  /// L'app è un browser noto: il dominio si usa senza conferma (D27).
  final bool isBrowser;

  final bool hasUserName;
  final bool hasPassword;
  final bool save;
  final String? userName;

  /// Richiesta per l'app: `androidapp://<pacchetto>`.
  String get appQuery => '$androidAppScheme$packageName';

  /// Coppia dominio-app ricordata dopo la conferma (`AutoFillTrustedLinks` di
  /// Keepass2Android); `null` senza dominio.
  String? get trustLink => switch (webDomain) {
    final domain? => '$domain + $packageName',
    null => null,
  };
}

/// Canale con `AutofillActivity`: la richiesta e la risposta, una volta sola.
class AutofillChannel {
  const AutofillChannel();

  @visibleForTesting
  static const channel = MethodChannel(
    'io.github.al3x1n0.keepassmobile/autofill',
  );

  /// `null` se la schermata non è stata aperta dal servizio.
  Future<AutofillRequest?> request() async {
    try {
      final map = await channel.invokeMapMethod<String, Object?>('request');
      final app = map?['packageName'];
      if (map == null || app is! String || app.isEmpty) return null;
      return AutofillRequest(
        packageName: app,
        webDomain: switch (map['webDomain']) {
          final String domain when domain.trim().isNotEmpty =>
            domain.trim().toLowerCase(),
          _ => null,
        },
        isBrowser: map['isBrowser'] == true,
        hasUserName: map['hasUserName'] == true,
        hasPassword: map['hasPassword'] == true,
        save: map['save'] == true,
        userName: map['userName'] as String?,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Restituisce i valori al sistema, che compila i campi; la schermata si
  /// chiude. I valori `null` non si compilano. Mai nei log (SEC-01).
  Future<void> fill({String? userName, String? password}) => channel
      .invokeMethod<void>('fill', {'userName': userName, 'password': password});

  Future<String?> takeSavePassword() =>
      channel.invokeMethod<String>('takeSavePassword');

  /// Chiude la schermata senza compilare.
  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('cancel');
    } on PlatformException {
      // La schermata si chiude comunque con il tasto indietro.
    } on MissingPluginException {
      // Fuori da AutofillActivity: niente da chiudere.
    }
  }
}

final autofillChannelProvider = Provider<AutofillChannel>(
  (_) => const AutofillChannel(),
);

/// Richiesta della schermata di compilazione automatica, impostata da
/// `autofillMain`.
final autofillRequestProvider = Provider<AutofillRequest>(
  (_) => throw StateError('nessuna richiesta di compilazione automatica'),
);

/// Stato del servizio di compilazione automatica del sistema.
@immutable
class AutofillServiceStatus {
  const AutofillServiceStatus({required this.supported, required this.enabled});

  static const unsupported = AutofillServiceStatus(
    supported: false,
    enabled: false,
  );

  /// Il dispositivo ha la compilazione automatica (Android 8+).
  final bool supported;

  /// KeePassMobile è il servizio scelto.
  final bool enabled;
}

/// Impostazione "Compilazione automatica" (canale di `MainActivity`).
class AutofillSettings {
  const AutofillSettings();

  @visibleForTesting
  static const channel = MethodChannel(
    'io.github.al3x1n0.keepassmobile/autofill_settings',
  );

  Future<AutofillServiceStatus> status() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AutofillServiceStatus.unsupported;
    }
    try {
      final map = await channel.invokeMapMethod<String, Object?>('status');
      return AutofillServiceStatus(
        supported: map?['supported'] == true,
        enabled: map?['enabled'] == true,
      );
    } on PlatformException {
      return AutofillServiceStatus.unsupported;
    } on MissingPluginException {
      return AutofillServiceStatus.unsupported;
    }
  }

  /// Apre la scelta del servizio nelle impostazioni di sistema; `false` se non
  /// è stato possibile.
  Future<bool> openSystemSettings() async {
    try {
      return await channel.invokeMethod<bool>('openSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final autofillSettingsProvider = Provider<AutofillSettings>(
  (_) => const AutofillSettings(),
);

final autofillServiceStatusProvider =
    FutureProvider.autoDispose<AutofillServiceStatus>(
      (ref) => ref.watch(autofillSettingsProvider).status(),
    );
