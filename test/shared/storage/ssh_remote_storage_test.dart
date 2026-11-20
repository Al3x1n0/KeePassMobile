import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/remote_open/remote_open_view_model.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/remote_storage.dart';
import 'package:keepass_mobile/shared/storage/sftp_client.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_secure_storage.dart';

class VerifiedSftp extends SftpStorageClient {
  String hostKey = 'SHA256:synthetic';
  final used = <RemoteCredentials>[];
  @override
  Future<RemoteFile> get(
    Uri uri, {
    required RemoteCredentials credentials,
    required SshHostVerifier verifyHost,
  }) async {
    if (!await verifyHost('ssh-ed25519', hostKey)) {
      throw const RemoteCanceledException();
    }
    used.add(credentials);
    return RemoteFile(bytes: Uint8List.fromList([1]));
  }
}

void main() {
  const file = FileRef(uri: 'sftp://example.test/demo.kdbx', name: 'demo.kdbx');
  const credentials = RemoteCredentials(
    userName: 'demo',
    password: 'passphrase',
    privateKey: 'synthetic-key',
  );
  late SharedPreferences prefs;
  late VerifiedSftp client;
  late RemoteStorage remote;
  late int prompts;
  late bool accept;

  setUp(() async {
    FakeSecureStorage.install();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    client = VerifiedSftp();
    prompts = 0;
    accept = true;
    remote = RemoteStorage(
      client: const WebDavClient(),
      sftp: client,
      store: RemoteCredentialStore(),
      session: RemoteSession(),
      trust: RemoteTrustRepository(prefs),
      askCredentials: (_, {previous, failed = false}) async =>
          const RemoteCredentialsAnswer(
            credentials: credentials,
            remember: true,
          ),
      askTrust: (_, _) async =>
          throw StateError('HTTPS trust must not be used'),
      askSshTrust: (_, _) async {
        prompts++;
        return accept;
      },
    );
  });

  test(
    'prima connessione: conferma, impronta ricordata anche dopo il blocco',
    () async {
      await remote.read(file);
      remote.session.clear();
      await remote.read(file);
      expect(prompts, 1);
      expect(
        remote.trust.sshHost('example.test:22'),
        'ssh-ed25519 SHA256:synthetic',
      );
      expect(remote.trust.fingerprints('example.test:22'), isEmpty);
    },
  );

  test(
    'chiave cambiata: blocca prima delle credenziali, senza nuova conferma',
    () async {
      await remote.read(file);
      client.hostKey = 'SHA256:changed';
      await expectLater(
        remote.read(file),
        throwsA(isA<SshHostKeyChangedException>()),
      );
      expect(client.used, hasLength(1));
      expect(prompts, 1);
    },
  );

  test('prima impronta rifiutata: non ricordata e nessuna lettura', () async {
    accept = false;
    await expectLater(
      remote.read(file),
      throwsA(isA<RemoteCanceledException>()),
    );
    expect(remote.trust.sshHost('example.test:22'), isNull);
    expect(client.used, isEmpty);
  });

  test(
    'archivio impronte corrotto: errore senza confermare una nuova identità',
    () async {
      await prefs.setString('remote.trusted_ssh_hosts', 'corrupt');
      await expectLater(
        remote.read(file),
        throwsA(isA<SshHostKeyChangedException>()),
      );
      expect(prompts, 0);
    },
  );

  test(
    'chiave e passphrase solo nello store, rimozione con il recente',
    () async {
      await remote.read(file);
      await remote.commit(file);
      final stored = await remote.store.read(file);
      expect(stored?.privateKey, credentials.privateKey);
      expect(stored?.password, credentials.password);
      expect(prefs.getKeys(), {'remote.trusted_ssh_hosts'});
      await remote.release(file);
      expect(await remote.store.read(file), isNull);
    },
  );

  test('non ricordare: chiave non persistita', () async {
    remote.session.put(file, credentials, remember: false);
    await remote.read(file);
    await remote.commit(file);
    expect(await remote.store.read(file), isNull);
    remote.session.clear();
    expect(remote.session.credentialsOf(file), isNull);
  });

  test('credenziali WebDAV esistenti restano leggibili', () async {
    const dav = FileRef(
      uri: 'https://example.test/demo.kdbx',
      name: 'demo.kdbx',
    );
    await remote.store.write(
      dav,
      const RemoteCredentials(userName: 'demo', password: 'synthetic'),
    );
    expect((await remote.store.read(dav))?.privateKey, isNull);
  });

  test('indirizzo SFTP senza userinfo e con porta esplicita', () {
    final uri = remoteStartUri(
      RemoteServerType.sftp,
      'example.test:2222/a b',
      'demo',
    );
    expect(uri.scheme, 'sftp');
    expect(uri.port, 2222);
    expect(Uri.decodeComponent(uri.path), '/a b/');
    expect(uri.userInfo, isEmpty);
    expect(
      () => remoteStartUri(
        RemoteServerType.sftp,
        'sftp://demo:secret@example.test/',
        'demo',
      ),
      throwsA(isA<InvalidRemoteAddressException>()),
    );
  });
  test(
    'non ricordare rimuove anche le credenziali conservate in precedenza',
    () async {
      await remote.store.write(file, credentials);
      remote.session.put(file, credentials, remember: false);
      await remote.read(file);
      await remote.commit(file);
      expect(await remote.store.read(file), isNull);
    },
  );
}
