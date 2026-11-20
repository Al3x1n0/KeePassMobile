import 'dart:typed_data';

import 'package:argon2_native/argon2_native.dart';
import 'package:kpasslib/kpasslib.dart';

/// Motore crittografico dell'app: Argon2 nativo (C di riferimento PHC),
/// il resto in Dart puro da kpasslib.
///
/// Va installato una volta all'avvio con [install], prima di aprire database.
class AppCryptoEngine extends CryptoEngine {
  AppCryptoEngine({bool? useNativeArgon2})
    : useNativeArgon2 = useNativeArgon2 ?? isArgon2NativeAvailable;

  /// `false` se la libreria nativa manca: si usa Argon2 in Dart puro.
  final bool useNativeArgon2;

  final CryptoDart _dart = CryptoDart();

  /// Imposta il motore globale di kpasslib.
  static AppCryptoEngine install() {
    final engine = AppCryptoEngine();
    Crypto.engine = engine;
    return engine;
  }

  @override
  Aes256 createAes256({required Uint8List key}) => _dart.createAes256(key: key);

  @override
  ChaCha20 createChaCha20({required Uint8List key}) =>
      _dart.createChaCha20(key: key);

  @override
  Salsa20 createSalsa20({required Uint8List key}) =>
      _dart.createSalsa20(key: key);

  @override
  Argon2 createArgon2({
    Argon2Type type = Argon2Type.argon2id,
    Argon2Version version = Argon2Version.v13,
    required int parallelism,
    required int memorySizeKB,
    required int iterations,
    required List<int> salt,
  }) {
    if (!useNativeArgon2) {
      return _dart.createArgon2(
        type: type,
        version: version,
        parallelism: parallelism,
        memorySizeKB: memorySizeKB,
        iterations: iterations,
        salt: salt,
      );
    }
    return _NativeArgon2(
      type: switch (type) {
        Argon2Type.argon2d => Argon2NativeType.d,
        Argon2Type.argon2id => Argon2NativeType.id,
      },
      version: version.value,
      parallelism: parallelism,
      memoryKiB: memorySizeKB,
      iterations: iterations,
      salt: List.unmodifiable(salt),
    );
  }
}

class _NativeArgon2 implements Argon2 {
  _NativeArgon2({
    required this.type,
    required this.version,
    required this.parallelism,
    required this.memoryKiB,
    required this.iterations,
    required this.salt,
  });

  final Argon2NativeType type;
  final int version;
  final int parallelism;
  final int memoryKiB;
  final int iterations;
  final List<int> salt;

  @override
  Uint8List convert(List<int> password) => argon2Hash(
    password: password,
    salt: salt,
    iterations: iterations,
    memoryKiB: memoryKiB,
    parallelism: parallelism,
    type: type,
    version: version,
  );
}
