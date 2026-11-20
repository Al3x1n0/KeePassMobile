import 'package:kpasslib/kpasslib.dart';
import 'package:test/test.dart';

void main() {
  KdbxCredentials creds() =>
      KdbxCredentials(password: ProtectedData.fromString('secret'));

  Future<KdbxDatabase> newDb({(int, int) version = (4, 1)}) async {
    final db = KdbxDatabase.create(credentials: creds(), name: 'test');
    db.header.version = version;
    if (version.$1 < 4) {
      db.header.keyEncryptionRounds = 1000;
    } else {
      db.header.kdf = KdfId.aes; // fast in tests
    }
    db.createEntry(parent: db.root).fields['Title'] =
        KdbxTextField.fromText(text: 'entry');
    return db;
  }

  for (final version in [(3, 1), (4, 1)]) {
    group('transformed key, KDBX ${version.$1}', () {
      test('reopens the file without the password', () async {
        final db = await newDb(version: version);
        final bytes = await db.save();
        final key = db.header.transformedKey;
        expect(key, isNotNull);
        expect(key!.fingerprint, db.header.kdfFingerprint);

        final reopened = await KdbxDatabase.fromBytes(
          data: bytes,
          credentials: KdbxCredentials.fromTransformedKey(key),
        );
        expect(reopened.root.allEntries.length, 1);
      });

      test('saves with the transformed key only, without rotating the KDF',
          () async {
        final db = await newDb(version: version);
        final bytes = await db.save();
        final key = db.header.transformedKey!;

        final reopened = await KdbxDatabase.fromBytes(
          data: bytes,
          credentials: KdbxCredentials.fromTransformedKey(key),
        );
        reopened.createEntry(parent: reopened.root);
        final saved = await reopened.save();
        expect(reopened.header.kdfFingerprint, key.fingerprint);

        final again = await KdbxDatabase.fromBytes(
          data: saved,
          credentials: creds(),
        );
        expect(again.root.allEntries.length, 2);
      });

      test('stale key: dedicated error, not a wrong password', () async {
        final db = await newDb(version: version);
        await db.save();
        final oldKey = db.header.transformedKey!;
        final newer = await db.save(); // new KDF salt
        expect(db.header.kdfFingerprint, isNot(oldKey.fingerprint));

        expect(
          () => KdbxDatabase.fromBytes(
            data: newer,
            credentials: KdbxCredentials.fromTransformedKey(oldKey),
          ),
          throwsA(isA<TransformedKeyStaleError>()),
        );
      });

      test('a valid transformed key skips the KDF even with a wrong password',
          () async {
        final db = await newDb(version: version);
        final bytes = await db.save();
        final key = db.header.transformedKey!;
        // The transformed key takes precedence: the caller must keep it in
        // secure storage only.
        final reopened = await KdbxDatabase.fromBytes(
          data: bytes,
          credentials: KdbxCredentials(
            password: ProtectedData.fromString('wrong'),
            transformedKey: key,
          ),
        );
        expect(reopened.root.allEntries.length, 1);
      });
    });
  }

  test('unknown cipher: dedicated error, not a wrong password', () async {
    final db = await newDb();
    db.header.dataCipherUuid = KdbxUuid.fromString('AAAAAAAAAAAAAAAAAAAAAA==');
    expect(() => db.save(), throwsA(isA<UnsupportedValueError>()));
  });

  group('kdfSettings', () {
    test('KDBX 4: Argon2id parameters are written and read back', () async {
      final db = KdbxDatabase.create(credentials: creds(), name: 'test');
      const settings = Argon2KdfSettings(
        id: true,
        memory: 1024 * 1024,
        iterations: 2,
        parallelism: 2,
      );

      db.header.kdfSettings = settings;
      final bytes = await db.save();
      final reopened =
          await KdbxDatabase.fromBytes(data: bytes, credentials: creds());

      expect(reopened.header.kdfSettings, settings);
      expect(reopened.header.kdfSettings.kdfId, KdfId.argon2id);
    });

    test('KDBX 4: AES-KDF rounds are written and read back', () async {
      final db = KdbxDatabase.create(credentials: creds(), name: 'test');

      db.header.kdfSettings = const AesKdfSettings(rounds: 1234);
      final bytes = await db.save();
      final reopened =
          await KdbxDatabase.fromBytes(data: bytes, credentials: creds());

      expect(reopened.header.kdfSettings, const AesKdfSettings(rounds: 1234));
    });

    test('a new setting gets a new salt', () async {
      final db = KdbxDatabase.create(credentials: creds(), name: 'test');
      db.header.kdfSettings = const AesKdfSettings(rounds: 1000);
      final before = db.header.kdfFingerprint;

      db.header.kdfSettings = const AesKdfSettings(rounds: 1000);

      expect(db.header.kdfFingerprint, isNot(before));
    });

    test('KDBX 3: only AES-KDF, stored as transform rounds', () async {
      final db = await newDb(version: (3, 1));

      db.header.kdfSettings = const AesKdfSettings(rounds: 2000);
      final reopened = await KdbxDatabase.fromBytes(
          data: await db.save(), credentials: creds());

      expect(reopened.header.kdfSettings, const AesKdfSettings(rounds: 2000));
      expect(
        () => db.header.kdfSettings = const Argon2KdfSettings(
            id: true, memory: 1024 * 1024, iterations: 1, parallelism: 1),
        throwsA(isA<UnsupportedValueError>()),
      );
    });
  });

  test('restoreFromHistory: copies the record, keeps the current state', () async {
    final db = await newDb();
    final entry = db.root.allEntries.single;
    entry.pushHistory();
    entry.fields['Title'] = KdbxTextField.fromText(text: 'changed');
    entry.tags = ['new'];

    entry.restoreFromHistory(0);
    final reopened = await KdbxDatabase.fromBytes(
        data: await db.save(), credentials: creds());

    final restored = reopened.root.allEntries.single;
    expect(restored.fields['Title']?.text, 'entry');
    expect(restored.tags, isNull);
    expect(restored.history.map((h) => h.fields['Title']?.text),
        ['entry', 'changed']);
    expect(restored.history.every((h) => h.uuid == restored.uuid), isTrue);
  });

  test('creates and reopens a Twofish database', () async {
    final db = await newDb();
    db.header.dataCipherUuid = KdbxUuid.fromString(CipherId.twofish);
    final bytes = await db.save();
    final reopened =
        await KdbxDatabase.fromBytes(data: bytes, credentials: creds());
    expect(reopened.header.dataCipherUuid?.string, CipherId.twofish);
    expect(reopened.root.allEntries.single.fields['Title']?.text, 'entry');
  });
}
