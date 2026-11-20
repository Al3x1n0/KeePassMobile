import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/security/biometric_key_store.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const texts = BiometricPromptTexts(title: 't', subtitle: 's', cancel: 'c');
  const file = FileRef(uri: 'content://docs/a', name: 'a.kdbx');
  late FakeSecureStorage platform;
  late BiometricKeyStore store;

  KdbxTransformedKey key() => KdbxTransformedKey(
    key: ProtectedData.fromBytes(List.generate(32, (i) => i)),
    fingerprint: [1, 2, 254],
  );

  setUp(() async {
    platform = FakeSecureStorage.install();
    SharedPreferences.setMockInitialValues({});
    store = BiometricKeyStore(await SharedPreferences.getInstance());
  });

  test(
    'salva e rilegge la chiave derivata; la voce è indicata da un hash',
    () async {
      expect(store.isEnabled(file), isFalse);

      await store.store(file, key(), texts: texts);

      expect(store.isEnabled(file), isTrue);
      expect(store.fingerprintOf(file), [1, 2, 254]);
      final id = BiometricKeyStore.keyIdOf(file);
      expect(platform.data.keys.single, contains(id));
      expect(platform.data.keys.single, isNot(contains('a.kdbx')));
      final read = await store.read(file, texts: texts);
      expect(read?.key.bytes, List.generate(32, (i) => i));
      expect(read?.fingerprint, [1, 2, 254]);
    },
  );

  test('Android: biometria forte a ogni lettura e scrittura', () async {
    await store.store(file, key(), texts: texts);

    final options = platform.options.single;
    expect(options['enforceBiometrics'], 'true');
    expect(options['requireBiometricsPerOperation'], 'true');
    expect(options['migrateOnAlgorithmChange'], 'false');
    expect(options.values, contains('strongBiometricOnly'));
    expect(options['biometricPromptTitle'], 't');
  });

  test(
    'iOS: Keychain con biometryCurrentSet, solo con codice di sblocco',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await store.store(file, key(), texts: texts);

      final options = platform.options.single;
      expect(options['accessibility'], 'passcode');
      expect(options['accessControlFlags'], contains('biometryCurrentSet'));
      expect(options['synchronizable'], 'false');
    },
  );

  test('voce sparita (nuova impronta): null e biometria disattivata', () async {
    await store.store(file, key(), texts: texts);
    platform.data.clear();

    expect(await store.read(file, texts: texts), isNull);
    expect(store.isEnabled(file), isFalse);
  });

  test(
    'annullato dall\'utente: errore dedicato, biometria ancora attiva',
    () async {
      await store.store(file, key(), texts: texts);
      platform.failure = PlatformException(
        code: 'Exception encountered',
        message: 'Biometric authentication error [10]: Annullato',
      );

      await expectLater(
        store.read(file, texts: texts),
        throwsA(
          isA<BiometricKeyException>().having(
            (e) => e.reason,
            'reason',
            BiometricKeyError.canceled,
          ),
        ),
      );
      expect(store.isEnabled(file), isTrue);
    },
  );

  test('errori del plugin tradotti in motivi', () {
    BiometricKeyError of(String? message, [Object? details]) =>
        BiometricKeyStore.errorOf(
          PlatformException(code: 'x', message: message, details: details),
        );

    expect(
      of('BIOMETRIC_UNAVAILABLE: Device has no PIN'),
      BiometricKeyError.unavailable,
    );
    expect(
      of('Biometric authentication error [13]: Annulla'),
      BiometricKeyError.canceled,
    );
    expect(
      of('Biometric authentication error [11]: none'),
      BiometricKeyError.unavailable,
    );
    expect(
      of('Biometric authentication error [7]: lockout'),
      BiometricKeyError.failed,
    );
    expect(
      of('Unexpected security result code', -128),
      BiometricKeyError.canceled,
    );
    expect(
      of('Unexpected security result code', -25300),
      BiometricKeyError.failed,
    );
  });

  test('rimozione di un file e di tutti', () async {
    const other = FileRef(uri: 'content://docs/b', name: 'b.kdbx');
    await store.store(file, key(), texts: texts);
    await store.store(other, key(), texts: texts);

    await store.remove(file);
    expect(store.isEnabled(file), isFalse);
    expect(store.isEnabled(other), isTrue);

    await store.removeAll();
    expect(store.isEnabled(other), isFalse);
    expect(platform.data, isEmpty);
  });
}
