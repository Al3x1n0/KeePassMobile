import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/crypto/app_crypto_engine.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:kpasslib/kpasslib.dart';

void _addLocal(KdbxDatabase db) =>
    db.createEntry(parent: db.root).fields['Title'] = KdbxTextField.fromText(
      text: 'Locale',
    );

/// Compatibilità con database creati da altri client KeePass
/// (file di test di pykeepass, GPLv3: test/fixtures/kdbx/README.md).
void main() {
  const dir = 'test/fixtures/kdbx/';
  const pw = 'password';

  // file -> (password, file chiave, cifrario atteso, voci attese)
  final cases = <String, (String?, String?, String, int)>{
    'test3.kdbx': (pw, 'test3.key', CipherId.aes, 15),
    'test4.kdbx': (pw, 'test4.key', CipherId.chaCha20, 15),
    'test4_aes.kdbx': (pw, 'test4.key', CipherId.aes, 2),
    'test4_aeskdf.kdbx': (pw, 'test4.key', CipherId.aes, 2),
    'test4_chacha20.kdbx': (pw, 'test4.key', CipherId.chaCha20, 2),
    'test4_twofish.kdbx': (pw, 'test4.key', CipherId.twofish, 2),
    'test4_hex.kdbx': (pw, 'test4_hex.key', CipherId.chaCha20, 3),
    'test4_aes_uncompressed.kdbx': (pw, null, CipherId.aes, 1),
    'test4_chacha20_uncompressed.kdbx': (pw, null, CipherId.chaCha20, 1),
    'test4_argon2id.kdbx': (pw, null, CipherId.aes, 0),
    'test4_blankpass.kdbx': ('', 'test4.key', CipherId.aes, 0),
    'test4_keyx.kdbx': (pw, 'test4_keyx.keyx', CipherId.chaCha20, 1),
  };

  KdbxCredentials credsFor(String? password, String? keyFile) =>
      KdbxCredentials(
        password: password == null ? null : ProtectedData.fromString(password),
        keyData: keyFile == null ? null : File(dir + keyFile).readAsBytesSync(),
      );

  for (final MapEntry(key: file, value: c) in cases.entries) {
    final (password, keyFile, cipher, entries) = c;

    test('$file: apre, salva e riapre (Argon2 nativo)', () async {
      final previous = Crypto.engine;
      addTearDown(() => Crypto.engine = previous);
      expect(AppCryptoEngine.install().useNativeArgon2, isTrue);

      final creds = credsFor(password, keyFile);
      final db = await KdbxDatabase.fromBytes(
        data: File(dir + file).readAsBytesSync(),
        credentials: creds,
      );
      expect(db.header.dataCipherUuid?.string, cipher);
      expect(db.root.allEntries.length, entries);

      final saved = await db.save();
      final reopened = await KdbxDatabase.fromBytes(
        data: saved,
        credentials: credsFor(password, keyFile),
      );
      expect(reopened.header.dataCipherUuid?.string, cipher);
      expect(reopened.root.allEntries.length, entries);
    });
  }

  test('password errata: InvalidCredentialsError', () async {
    expect(
      () => KdbxDatabase.fromBytes(
        data: File('${dir}test4_aes_uncompressed.kdbx').readAsBytesSync(),
        credentials: credsFor('sbagliata', null),
      ),
      throwsA(isA<InvalidCredentialsError>()),
    );
  });

  // Sincronizzazione: modifiche da entrambe le parti su database
  // creati da altri client.
  for (final (file, keyFile, entries) in [
    ('test3.kdbx', 'test3.key', 15),
    ('test4.kdbx', 'test4.key', 15),
  ]) {
    test('$file: merge con il file cambiato altrove', () async {
      final data = File(dir + file).readAsBytesSync();
      final local = await KdbxDatabase.fromBytes(
        data: data,
        credentials: credsFor(pw, keyFile),
      );
      final other = await KdbxDatabase.fromBytes(
        data: data,
        credentials: credsFor(pw, keyFile),
      );
      other.createEntry(parent: other.root).fields['Title'] =
          KdbxTextField.fromText(text: 'Altrove');
      final external = Uint8List.fromList(await other.save());

      final (merged, bytes) = await saveDatabase(
        local,
        _addLocal,
        mergeWith: external,
      );

      final reopened = await KdbxDatabase.fromBytes(
        data: bytes,
        credentials: credsFor(pw, keyFile),
      );
      final titles = reopened.root.allEntries
          .map((e) => e.fields['Title']?.text)
          .toList();
      expect(reopened.root.allEntries.length, entries + 2);
      expect(titles, containsAll(['Altrove', 'Locale']));
      expect(merged.root.allEntries.length, entries + 2);
    });
  }
}
