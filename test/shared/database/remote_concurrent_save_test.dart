import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/external_change.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/remote_storage.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';
import '../../helpers/fake_secure_storage.dart';
import '../../helpers/webdav_test_server.dart';

DatabaseEdit _renameRoot(String name) => (database) {
  database.root.name = name;
};

class _NativeHttp extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'modifica concorrente durante la KDF: server e sessione non sovrascritti',
    () => HttpOverrides.runWithHttpOverrides(() async {
      FakeSecureStorage.install();
      final server = await WebDavTestServer.start();
      addTearDown(server.close);
      final container = await newTestContainer(
        overrides: [
          remoteCredentialsPromptProvider.overrideWithValue(
            (_, {previous, failed = false}) async => RemoteCredentialsAnswer(
              credentials: server.credentials,
              remember: false,
            ),
          ),
          certificateTrustPromptProvider.overrideWithValue(
            (_, _) async => true,
          ),
        ],
      );
      final database = newTestDatabase();
      final original = Uint8List.fromList(await database.save());
      server.files['/demo.kdbx'] = original;
      final file = FileRef(
        uri: server.uri('/demo.kdbx').toString(),
        name: 'demo.kdbx',
      );
      final notifier = container.read(databaseSessionProvider.notifier);
      notifier.open(
        DatabaseSession(
          file: file,
          database: database,
          fileHash: fileHashOf(original),
        ),
      );
      final remoteDatabase = await KdbxDatabase.fromBytes(
        data: original,
        credentials: testCredentials(),
      );
      remoteDatabase.root.name = 'modifica esterna';
      final remoteBytes = Uint8List.fromList(await remoteDatabase.save());
      server.beforeWrite = () {
        server.files['/demo.kdbx'] = remoteBytes;
      };

      await expectLater(
        notifier.apply(_renameRoot('modifica locale')),
        throwsA(isA<RemoteConflictException>()),
      );
      expect(server.files['/demo.kdbx'], remoteBytes);
      expect(
        container.read(databaseSessionProvider)?.database.root.name,
        'Prova',
      );
    }, _NativeHttp()),
  );
}
