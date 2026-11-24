import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../storage/file_storage.dart';
import '../storage/preferences.dart';
import 'external_activity.dart';

/// Perché la chiave salvata non è stata letta o scritta.
enum BiometricKeyError {
  /// L'utente ha annullato la richiesta biometrica.
  canceled,

  /// Biometria non configurata o dispositivo senza blocco schermo.
  unavailable,

  /// Autenticazione non riuscita o errore del sistema.
  failed,

  /// La chiave salvata non c'è più (biometria del dispositivo cambiata): la
  /// biometria è stata disattivata per il file.
  invalidated,

  /// La chiave salvata non apre più il file (modificato altrove con un salt
  /// nuovo o con un'altra chiave): si aggiorna al prossimo sblocco con password.
  stale,
}

final class BiometricKeyException implements Exception {
  const BiometricKeyException(this.reason);

  final BiometricKeyError reason;

  @override
  String toString() => 'BiometricKeyException: ${reason.name}';
}

/// Testi della richiesta biometrica (Android; su iOS il testo è
/// `NSFaceIDUsageDescription`).
@immutable
class BiometricPromptTexts {
  const BiometricPromptTexts({
    required this.title,
    required this.subtitle,
    required this.cancel,
  });

  final String title;
  final String subtitle;
  final String cancel;
}

/// Chiavi derivate dei database per lo sblocco biometrico (SEC-03, decisioni
/// D16 e D17), con `flutter_secure_storage`:
/// - Android: chiave AES nel Keystore con autenticazione biometrica forte a
///   ogni lettura e scrittura, invalidata quando si aggiunge un'impronta;
/// - iOS: Keychain con `biometryCurrentSet`, solo con codice di sblocco
///   impostato e solo su questo dispositivo.
///
/// Si salva la chiave derivata (`KdbxTransformedKey`), mai la password. Le voci
/// sono indicate dall'hash del riferimento al file: nessun nome o percorso
/// nell'archivio o nei log (SEC-01). Le preferenze ricordano per quali file la
/// biometria è attiva e con quale impronta della KDF, senza la chiave.
class BiometricKeyStore {
  BiometricKeyStore(
    this._prefs, {
    FlutterSecureStorage? storage,
    this._externalActivity,
  }) : _storage = storage ?? const FlutterSecureStorage();

  static const _prefsKey = 'biometric_unlock';
  static const _declinedKey = 'biometric_unlock_declined';
  static const _namespace = 'kpm_biometric_keys';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _storage;
  final ExternalActivity? _externalActivity;

  /// `true` se la biometria è attiva per [file].
  bool isEnabled(FileRef file) => _markers().containsKey(keyIdOf(file));

  /// Impronta della KDF della chiave salvata per [file] (non segreta: deriva
  /// dai parametri in chiaro dell'intestazione del file).
  List<int>? fingerprintOf(FileRef file) => switch (_markers()[keyIdOf(file)]) {
    final String hex => _fromHex(hex),
    _ => null,
  };

  /// Salva [key] per [file]; chiede la biometria.
  Future<void> store(
    FileRef file,
    KdbxTransformedKey key, {
    required BiometricPromptTexts texts,
  }) async {
    final id = keyIdOf(file);
    final clearKey = key.key.bytes;
    final String encodedKey;
    try {
      encodedKey = base64.encode(clearKey);
    } finally {
      clearKey.fillRange(0, clearKey.length, 0);
    }
    final value = jsonEncode({
      'k': encodedKey,
      'f': base64.encode(key.fingerprint),
    });
    await _guard(
      () => _storage.write(
        key: id,
        value: value,
        aOptions: _android(texts),
        iOptions: _ios,
      ),
    );
    await _setMarker(id, _toHex(key.fingerprint));
  }

  /// Chiave salvata per [file], dopo la richiesta biometrica; `null` se non
  /// c'è più (chiave invalidata da una nuova impronta, dati rimossi): in quel
  /// caso la biometria viene disattivata per il file.
  Future<KdbxTransformedKey?> read(
    FileRef file, {
    required BiometricPromptTexts texts,
  }) async {
    final id = keyIdOf(file);
    final raw = await _guard(
      () => _storage.read(key: id, aOptions: _android(texts), iOptions: _ios),
    );
    final key = raw == null ? null : _decode(raw);
    if (key == null) await remove(file);
    return key;
  }

  /// `true` se per [file] l'utente ha chiesto di non proporre più lo
  /// sblocco biometrico (D23).
  bool isOfferDeclined(FileRef file) =>
      (_prefs.getStringList(_declinedKey) ?? const []).contains(keyIdOf(file));

  /// Non proporre più lo sblocco biometrico per [file]; resta attivabile
  /// dalle impostazioni del database.
  Future<void> declineOffer(FileRef file) => _prefs.setStringList(
    _declinedKey,
    {...?_prefs.getStringList(_declinedKey), keyIdOf(file)}.toList(),
  );

  /// Disattiva la biometria per [file] e azzera il rifiuto della proposta.
  /// Non chiede la biometria.
  Future<void> remove(FileRef file) async {
    final id = keyIdOf(file);
    try {
      await _storage.delete(key: id, aOptions: _android(null), iOptions: _ios);
    } on PlatformException {
      // Voce già assente o archivio illeggibile: basta togliere il segno.
    }
    final markers = _markers()..remove(id);
    await _prefs.setString(_prefsKey, jsonEncode(markers));
    final declined = _prefs.getStringList(_declinedKey);
    if (declined != null && declined.contains(id)) {
      await _prefs.setStringList(_declinedKey, declined..remove(id));
    }
  }

  /// Disattiva la biometria per tutti i file ("Ricorda file recenti" spento).
  Future<void> removeAll() async {
    for (final id in _markers().keys) {
      try {
        await _storage.delete(
          key: id,
          aOptions: _android(null),
          iOptions: _ios,
        );
      } on PlatformException {
        // Come in remove.
      }
    }
    await _prefs.remove(_prefsKey);
    await _prefs.remove(_declinedKey);
  }

  /// Identificatore della voce: SHA-256 del riferimento al file.
  @visibleForTesting
  static String keyIdOf(FileRef file) =>
      sha256.convert(utf8.encode(file.uri)).toString();

  static AndroidOptions _android(BiometricPromptTexts? texts) =>
      AndroidOptions.biometric(
        // Archivio dedicato e nuovo: niente migrazione dall'algoritmo
        // predefinito, che chiederebbe una seconda richiesta biometrica alla
        // prima scrittura. Se un aggiornamento del pacchetto cambiasse
        // algoritmo, le chiavi verrebbero cancellate (resetOnError) e la
        // biometria andrebbe riattivata.
        migrateOnAlgorithmChange: false,
        enforceBiometrics: true,
        requireBiometricsPerOperation: true,
        biometricType: AndroidBiometricType.strongBiometricOnly,
        storageNamespace: _namespace,
        biometricPromptTitle: texts?.title,
        biometricPromptSubtitle: texts?.subtitle,
        biometricPromptNegativeButton: texts?.cancel,
      );

  static const _ios = IOSOptions(
    accountName: _namespace,
    accessibility: KeychainAccessibility.passcode,
    accessControlFlags: [AccessControlFlag.biometryCurrentSet],
  );

  Map<String, Object?> _markers() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? {...decoded} : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _setMarker(String id, String fingerprint) =>
      _prefs.setString(_prefsKey, jsonEncode(_markers()..[id] = fingerprint));

  static KdbxTransformedKey? _decode(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json case {'k': final String k, 'f': final String f}) {
        final fingerprint = base64.decode(f);
        final clearKey = base64.decode(k);
        try {
          return KdbxTransformedKey(
            key: ProtectedData.fromBytes(clearKey),
            fingerprint: fingerprint,
          );
        } finally {
          clearKey.fillRange(0, clearKey.length, 0);
        }
      }
    } on FormatException {
      // Valore illeggibile: come se non ci fosse.
    }
    return null;
  }

  Future<T> _guard<T>(Future<T> Function() operation) async {
    try {
      return await (_externalActivity?.run(operation) ?? operation());
    } on PlatformException catch (e) {
      throw BiometricKeyException(errorOf(e));
    } on MissingPluginException {
      throw const BiometricKeyException(BiometricKeyError.unavailable);
    }
  }

  /// Motivo dell'errore del plugin. Android lo riporta solo nel messaggio
  /// (codici di `BiometricPrompt`), iOS nel codice di stato del Keychain.
  @visibleForTesting
  static BiometricKeyError errorOf(PlatformException e) {
    final message = e.message ?? '';
    if (message.contains('BIOMETRIC_UNAVAILABLE')) {
      return BiometricKeyError.unavailable;
    }
    final android = RegExp(r'Biometric authentication error \[(\d+)\]')
        .firstMatch(message);
    if (android != null) {
      return switch (int.parse(android.group(1)!)) {
        // ERROR_CANCELED, ERROR_USER_CANCELED, ERROR_NEGATIVE_BUTTON.
        5 || 10 || 13 => BiometricKeyError.canceled,
        // ERROR_HW_UNAVAILABLE, ERROR_NO_BIOMETRICS, ERROR_HW_NOT_PRESENT,
        // ERROR_NO_DEVICE_CREDENTIAL.
        1 || 11 || 12 || 14 => BiometricKeyError.unavailable,
        _ => BiometricKeyError.failed,
      };
    }
    return switch (e.details) {
      -128 => BiometricKeyError.canceled, // errSecUserCanceled
      -25291 || -25308 =>
        BiometricKeyError.unavailable, // NotAvailable, InteractionNotAllowed
      _ => BiometricKeyError.failed,
    };
  }

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _fromHex(String hex) => [
    for (var i = 0; i + 1 < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
}

final biometricKeyStoreProvider = Provider<BiometricKeyStore>(
  (ref) => BiometricKeyStore(
    ref.watch(sharedPreferencesProvider),
    externalActivity: ref.watch(externalActivityProvider),
  ),
);

/// Database per cui proporre lo sblocco biometrico, dopo uno sblocco con
/// password (D23); `null` se non c'è nulla da proporre.
final biometricOfferProvider =
    NotifierProvider<BiometricOfferNotifier, FileRef?>(
      BiometricOfferNotifier.new,
    );

class BiometricOfferNotifier extends Notifier<FileRef?> {
  @override
  FileRef? build() => null;

  void offer(FileRef file) => state = file;

  void clear() => state = null;
}
