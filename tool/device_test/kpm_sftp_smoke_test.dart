// Prova con server OpenSSH locale e chiavi sintetiche esterne al repository.
// fvm flutter test tool/device_test/kpm_sftp_smoke_test.dart \
//   --dart-define=KPM_SFTP_TEST_ROOT=/percorso/temporaneo
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/crypto/app_crypto_engine.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:keepass_mobile/shared/storage/sftp_client.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';

void main() {
  test(
    'OpenSSH reale: chiave cifrata, impronta, browsing e sostituzione file',
    () async {
      const root = String.fromEnvironment('KPM_SFTP_TEST_ROOT');
      expect(
        root,
        isNotEmpty,
        reason: 'Serve un server di prova locale esplicito',
      );
      final credentials = RemoteCredentials(
        userName: Platform.environment['USER']!,
        password: 'synthetic-passphrase',
        privateKey: await File('$root/client_key').readAsString(),
      );
      final uri = Uri(
        scheme: 'sftp',
        host: '127.0.0.1',
        port: 18444,
        path: '$root/demo a#%.kdbx',
      );
      const client = SftpStorageClient();
      final fingerprints = <String>[];
      final unsendable = ReceivePort();
      addTearDown(unsendable.close);
      Future<bool> verify(String type, String fingerprint) async {
        unsendable.sendPort.send(null);
        expect(type, 'ssh-ed25519');
        expect(fingerprint, startsWith('SHA256:'));
        fingerprints.add(fingerprint);
        return true;
      }

      await client.put(
        uri,
        Uint8List.fromList([1, 2, 3]),
        credentials: credentials,
        verifyHost: verify,
      );
      await client.put(
        uri,
        Uint8List.fromList([4, 5, 6]),
        credentials: credentials,
        verifyHost: verify,
      );
      expect(
        (await client.get(
          uri,
          credentials: credentials,
          verifyHost: verify,
        )).bytes,
        [4, 5, 6],
      );
      final entries = await client.list(
        uri.replace(path: '$root/'),
        credentials: credentials,
        verifyHost: verify,
      );
      expect(entries.map((e) => e.name), contains('demo a#%.kdbx'));
      expect(fingerprints.toSet(), hasLength(1));
      await expectLater(
        client.get(
          uri,
          credentials: credentials,
          verifyHost: (_, _) async => false,
        ),
        throwsA(isA<RemoteCanceledException>()),
      );
      await expectLater(
        client.get(
          uri,
          credentials: RemoteCredentials(
            userName: credentials.userName,
            password: 'wrong',
            privateKey: credentials.privateKey,
          ),
          verifyHost: verify,
        ),
        throwsA(isA<InvalidSshKeyException>()),
      );
      expect(
        Directory(root).listSync().where((f) => f.path.endsWith('.tmp')),
        isEmpty,
      );
    },
  );
  test(
    'password sintetica: verifica il database salvato dal dispositivo',
    () async {
      AppCryptoEngine.install();
      const expectedFingerprint = String.fromEnvironment(
        'KPM_SFTP_TEST_FINGERPRINT',
      );
      const expectedName = String.fromEnvironment(
        'KPM_SFTP_EXPECTED_NAME',
        defaultValue: 'Prova SFTP',
      );
      expect(expectedFingerprint, isNotEmpty);
      final file = await const SftpStorageClient().get(
        Uri.parse('sftp://127.0.0.1:18445/demo.kdbx'),
        credentials: const RemoteCredentials(
          userName: 'demo',
          password: 'sftp-demo',
        ),
        verifyHost: (_, fp) async => fp == expectedFingerprint,
      );
      final database = await KdbxDatabase.fromBytes(
        data: file.bytes,
        credentials: KdbxCredentials(
          password: ProtectedData.fromString('demo1234'),
        ),
      );
      expect(database.meta.name, expectedName);
      const expectedEntry = String.fromEnvironment('KPM_SFTP_EXPECTED_ENTRY');
      if (expectedEntry.isNotEmpty) {
        expect(
          database.root.allEntries.map(
            (entry) => entry.fields[EntryFields.title]?.text,
          ),
          contains(expectedEntry),
        );
      }
    },
  );
}
