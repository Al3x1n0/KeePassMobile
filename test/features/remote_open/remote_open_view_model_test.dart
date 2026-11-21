import 'dart:typed_data';

import 'package:document_access/document_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/remote_open/remote_open_view_model.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/remote_storage.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_webdav_client.dart';

void main() {
  test('può selezionare solo elementi della cartella corrente', () async {
    // given
    const root = 'https://dav.example/dav/';
    const offered = '${root}prova.kdbx';
    const credentials = RemoteCredentials(userName: 'mario', password: 'prova');
    final client = FakeWebDavClient(accepted: credentials)
      ..files[offered] = Uint8List.fromList([1, 2, 3]);
    final session = RemoteSession();
    SharedPreferences.setMockInitialValues({});
    final remote = RemoteStorage(
      client: client,
      store: RemoteCredentialStore(),
      session: session,
      trust: RemoteTrustRepository(await SharedPreferences.getInstance()),
      askCredentials: (_, {previous, failed = false}) async => null,
      askTrust: (_, _) async => false,
    );
    final container = ProviderContainer.test(
      overrides: [
        remoteStorageProvider.overrideWithValue(remote),
        remoteSessionProvider.overrideWithValue(session),
        fileStorageProvider.overrideWithValue(
          FileStorage(const DocumentAccess(), remote),
        ),
      ],
    );
    final browser = container.listen(remoteOpenViewModelProvider, (_, _) {});
    final model = container.read(remoteOpenViewModelProvider.notifier);
    await model.connect(
      type: RemoteServerType.webDav,
      address: root,
      credentials: credentials,
      remember: false,
    );

    // when
    await model.open(
      RemoteEntry(
        name: 'cartella',
        uri: Uri.parse('${root}cartella/'),
        isDirectory: true,
      ),
    );
    final missing = await model.pick(
      RemoteEntry(
        name: 'altro.kdbx',
        uri: Uri.parse('${root}altro.kdbx'),
        isDirectory: false,
      ),
    );
    final picked = await model.pick(browser.read().entries.single);

    // then
    expect(missing, isNull);
    expect(picked?.bytes, [1, 2, 3]);
    expect(client.calls, ['PROPFIND $root', 'GET $offered']);
  });
}
