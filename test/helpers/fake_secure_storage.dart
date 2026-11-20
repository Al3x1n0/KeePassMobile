import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/test/test_flutter_secure_storage_platform.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// Archivio sicuro in memoria al posto di Keystore e Keychain: registra le
/// opzioni di ogni lettura e scrittura e può fallire come il plugin.
class FakeSecureStorage extends TestFlutterSecureStoragePlatform {
  FakeSecureStorage() : super({});

  /// Installa un archivio vuoto come piattaforma di `flutter_secure_storage`.
  static FakeSecureStorage install() {
    final fake = FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = fake;
    return fake;
  }

  /// Errore di Android quando l'utente annulla la richiesta biometrica.
  static PlatformException canceled() => PlatformException(
    code: 'Exception encountered',
    message: 'Biometric authentication error [10]: Annullato',
  );

  /// Errore restituito da letture e scritture finché non torna `null`.
  PlatformException? failure;
  final options = <Map<String, String>>[];

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) {
    this.options.add(options);
    if (failure case final f?) throw f;
    return super.read(key: key, options: options);
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) {
    this.options.add(options);
    if (failure case final f?) throw f;
    return super.write(key: key, value: value, options: options);
  }
}
