import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/crypto/app_crypto_engine.dart';
import 'package:kpasslib/kpasslib.dart';

void main() {
  final native = AppCryptoEngine();
  final dart = AppCryptoEngine(useNativeArgon2: false);

  test('Argon2 nativo disponibile su questa piattaforma', () {
    expect(native.useNativeArgon2, isTrue);
  });

  for (final type in Argon2Type.values) {
    for (final version in Argon2Version.values) {
      test('nativo e Dart coincidono: ${type.name} v${version.value}', () {
        final salt = List<int>.generate(32, (i) => i * 3);
        final password = List<int>.generate(32, (i) => 255 - i);
        List<int> run(AppCryptoEngine e) => e
            .createArgon2(
              type: type,
              version: version,
              parallelism: 2,
              memorySizeKB: 1024,
              iterations: 3,
              salt: salt,
            )
            .convert(password);
        expect(run(native), run(dart));
      });
    }
  }

  test('install imposta il motore globale di kpasslib', () {
    final previous = Crypto.engine;
    addTearDown(() => Crypto.engine = previous);
    final engine = AppCryptoEngine.install();
    expect(Crypto.engine, same(engine));
  });
}
