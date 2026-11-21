import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Schema delle app Android nei campi delle voci (`androidapp://`, come
/// Keepass2Android).
const androidAppScheme = 'androidapp://';

final _hostnameLabel = RegExp(
  r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
);

/// Canonical ASCII hostname for display and signer-bound trust.
String? canonicalAutofillDomain(String? value) {
  if (value == null) return null;
  final hostname = value.endsWith('.')
      ? value.substring(0, value.length - 1)
      : value;
  if (hostname.length > 253 || !hostname.contains('.')) return null;
  if (!hostname.split('.').every(_hostnameLabel.hasMatch)) return null;
  return hostname.toLowerCase();
}

/// Richiesta di compilazione automatica: app che chiede i valori e dominio che
/// dichiara (solo Android, `AutofillActivity`).
@immutable
class AutofillRequest {
  const AutofillRequest({
    required this.packageName,
    this._webDomain,
    this.signingIds = const [],
    this.hasUserName = true,
    this.hasPassword = true,
    this.save = false,
    this.userName,
  });

  final String packageName;

  final String? _webDomain;

  /// Dominio dichiarato dalla pagina, dopo la validazione della sintassi.
  String? get webDomain => canonicalAutofillDomain(_webDomain);

  /// Identità di firma verificate da Android, con la corrente in coda.
  final List<String> signingIds;

  final bool hasUserName;
  final bool hasPassword;
  final bool save;
  final String? userName;

  /// Richiesta per l'app: `androidapp://<pacchetto>`.
  String get appQuery => '$androidAppScheme$packageName';

  /// Conferme valide anche dopo una rotazione verificata da Android.
  Iterable<String> get trustLinks {
    final domain = webDomain;
    if (domain == null) return const [];
    return signingIds.map(
      (id) => jsonEncode(['site', domain, packageName, id]),
    );
  }

  /// Conferme per le associazioni KDBX a un'app, indipendenti dai siti.
  Iterable<String> get appTrustLinks =>
      signingIds.map((id) => jsonEncode(['app', packageName, id]));

  bool get canRememberDomain => webDomain != null && signingIds.isNotEmpty;
  bool get canRememberApp => signingIds.isNotEmpty;
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
        webDomain: map['webDomain'] is String
            ? map['webDomain'] as String
            : null,
        signingIds: List.unmodifiable(
          (map['signingIds'] as List<Object?>? ?? const []).whereType<String>(),
        ),
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
