import 'dart:typed_data';

import 'package:document_access/document_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/remote_storage.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/webdav_test_server.dart';

void main() {
  test('la lettura remota autorizzata rifiuta i reindirizzamenti', () async {
    final server = await WebDavTestServer.start();
    addTearDown(server.close);
    server.files['/target'] = Uint8List.fromList([1, 2, 3]);
    server.redirects['/link'] = server.uri('/target');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final trust = RemoteTrustRepository(prefs);
    await trust.trust(
      serverOf(server.uri('/target')),
      WebDavTestServer.fingerprint,
    );
    final session = RemoteSession();
    final target = FileRef(
      uri: server.uri('/target').toString(),
      name: 'target',
    );
    final link = FileRef(uri: server.uri('/link').toString(), name: 'link');
    session.put(target, server.credentials, remember: false);
    session.put(link, server.credentials, remember: false);
    final remote = RemoteStorage(
      client: const WebDavClient(),
      store: RemoteCredentialStore(),
      session: session,
      trust: trust,
      askCredentials: (_, {previous, failed = false}) async => null,
      askTrust: (_, _) async => false,
    );
    final storage = FileStorage(const DocumentAccess(), remote);
    expect((await RestrictedFileRead(storage, target).run()).bytes, [1, 2, 3]);
    await expectLater(
      RestrictedFileRead(storage, link).run(),
      throwsA(isA<FileUnavailableException>()),
    );
    expect(server.requests, ['GET /target', 'GET /link']);
  });
}
