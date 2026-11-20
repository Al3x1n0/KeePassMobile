import 'dart:typed_data';

import 'package:document_access/document_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/remote_storage.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/fake_webdav_client.dart';

void main() {
  const good = RemoteCredentials(userName: 'mario', password: 'giusta');
  const wrong = RemoteCredentials(userName: 'mario', password: 'vecchia');
  const file = FileRef(
    uri: 'https://dav.example/files/prova.kdbx',
    name: 'prova.kdbx',
  );
  late FakeSecureStorage secure;
  late SharedPreferences prefs;
  late List<({bool failed, RemoteCredentials? previous})> prompts;
  late List<RemoteCredentialsAnswer?> answers;
  late List<String> trustAsked;
  late bool acceptCertificate;

  setUp(() async {
    secure = FakeSecureStorage.install();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    prompts = [];
    answers = [];
    trustAsked = [];
    acceptCertificate = true;
  });

  RemoteStorage storage(FakeWebDavClient client) => RemoteStorage(
    client: client,
    store: RemoteCredentialStore(),
    session: RemoteSession(),
    trust: RemoteTrustRepository(prefs),
    askCredentials: (file, {previous, failed = false}) async {
      prompts.add((failed: failed, previous: previous));
      return answers.isEmpty ? null : answers.removeAt(0);
    },
    askTrust: (server, fingerprint) async {
      trustAsked.add('$server $fingerprint');
      return acceptCertificate;
    },
  );

  FakeWebDavClient client({String? untrusted}) =>
      FakeWebDavClient(accepted: good, untrustedFingerprint: untrusted)
        ..files[file.uri] = Uint8List.fromList([1, 2, 3]);

  test('credenziali salvate: nessuna richiesta', () async {
    await RemoteCredentialStore().write(file, good);
    final remote = storage(client());

    expect(await remote.read(file), [1, 2, 3]);
    expect(prompts, isEmpty);
  });

  test(
    '"ricorda": chieste una volta, salvate quando il file entra tra i recenti',
    () async {
      answers.add(
        const RemoteCredentialsAnswer(credentials: good, remember: true),
      );
      final remote = storage(client());

      await remote.read(file);
      await remote.read(file);
      expect(prompts, hasLength(1));
      expect(await RemoteCredentialStore().read(file), isNull);

      await remote.commit(file);

      expect((await RemoteCredentialStore().read(file))?.userName, 'mario');
      expect(secure.data.keys, [RemoteCredentialStore.keyOf(file)]);
    },
  );

  test(
    '"non ricordare": mai salvate, chieste di nuovo dopo la chiusura',
    () async {
      answers.addAll(const [
        RemoteCredentialsAnswer(credentials: good, remember: false),
        RemoteCredentialsAnswer(credentials: good, remember: false),
      ]);
      final remote = storage(client());

      await remote.read(file);
      await remote.commit(file);
      remote.session.clear();
      await remote.read(file);

      expect(prompts, hasLength(2));
      expect(secure.data, isEmpty);
    },
  );

  test(
    'credenziali salvate rifiutate: tolte, richiesta con errore, nuove salvate',
    () async {
      await RemoteCredentialStore().write(file, wrong);
      answers.add(
        const RemoteCredentialsAnswer(credentials: good, remember: true),
      );
      final remote = storage(client());

      expect(await remote.read(file), [1, 2, 3]);

      expect(prompts.single.failed, isTrue);
      expect(prompts.single.previous?.userName, 'mario');
      expect((await RemoteCredentialStore().read(file))?.password, 'giusta');
    },
  );

  test('richiesta annullata: RemoteCanceledException', () async {
    final remote = storage(client());

    await expectLater(
      remote.read(file),
      throwsA(isA<RemoteCanceledException>()),
    );
  });

  test('troppi rifiuti: RemoteAuthException', () async {
    answers.addAll(
      List.filled(
        RemoteStorage.maxCredentialAttempts,
        const RemoteCredentialsAnswer(credentials: wrong, remember: true),
      ),
    );
    final remote = storage(client());

    await expectLater(remote.read(file), throwsA(isA<RemoteAuthException>()));
    expect(prompts, hasLength(RemoteStorage.maxCredentialAttempts));
  });

  test(
    'certificato accettato: ricordato per il server, nessuna seconda domanda',
    () async {
      answers.add(
        const RemoteCredentialsAnswer(credentials: good, remember: true),
      );
      final remote = storage(client(untrusted: 'AA:BB'));

      await remote.read(file);
      await remote.write(file, Uint8List(1));

      expect(trustAsked, ['dav.example:443 AA:BB']);
      expect(RemoteTrustRepository(prefs).fingerprints('dav.example:443'), {
        'AA:BB',
      });
    },
  );

  test('certificato rifiutato: annullato e non ricordato', () async {
    acceptCertificate = false;
    answers.add(
      const RemoteCredentialsAnswer(credentials: good, remember: true),
    );
    final remote = storage(client(untrusted: 'AA:BB'));

    await expectLater(
      remote.read(file),
      throwsA(isA<RemoteCanceledException>()),
    );
    expect(
      RemoteTrustRepository(prefs).fingerprints('dav.example:443'),
      isEmpty,
    );
  });

  test('file tolto dai recenti: credenziali dimenticate', () async {
    await RemoteCredentialStore().write(file, good);
    final remote = storage(client());

    await FileStorage(const DocumentAccess(), remote).release(file);

    expect(secure.data, isEmpty);
  });

  test(
    'FileStorage: https al server, file assente = FileUnavailableException',
    () async {
      const missing = FileRef(
        uri: 'https://dav.example/files/manca.kdbx',
        name: 'manca.kdbx',
      );
      await RemoteCredentialStore().write(file, good);
      await RemoteCredentialStore().write(missing, good);
      final files = FileStorage(const DocumentAccess(), storage(client()));

      expect((await files.read(file)).bytes, [1, 2, 3]);
      await files.write(file, Uint8List.fromList([7]));
      expect((await files.read(file)).bytes, [7]);
      await expectLater(
        files.read(missing),
        throwsA(isA<FileUnavailableException>()),
      );
    },
  );
}
