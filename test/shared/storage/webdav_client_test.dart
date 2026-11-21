import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';

import '../../helpers/webdav_test_server.dart';

void main() {
  late WebDavTestServer server;
  const client = WebDavClient(
    connectTimeout: Duration(seconds: 5),
    timeout: Duration(seconds: 10),
  );
  final trusted = {WebDavTestServer.fingerprint};

  setUp(() async {
    server = await WebDavTestServer.start();
    server.files['/dav/prova.kdbx'] = Uint8List.fromList([1, 2, 3]);
  });

  tearDown(() => server.close());

  test('certificato non riconosciuto: impronta SHA-256 e server', () async {
    await expectLater(
      client.get(
        server.uri('/dav/prova.kdbx'),
        credentials: server.credentials,
      ),
      throwsA(
        isA<UntrustedCertificateException>()
            .having(
              (e) => e.fingerprint,
              'fingerprint',
              WebDavTestServer.fingerprint,
            )
            .having((e) => e.server, 'server', '127.0.0.1:${server.port}'),
      ),
    );
    expect(server.requests, isEmpty);
  });

  test('certificato accettato: contenuto ed ETag', () async {
    final file = await client.get(
      server.uri('/dav/prova.kdbx'),
      credentials: server.credentials,
      trusted: trusted,
    );

    expect(file.bytes, [1, 2, 3]);
    expect(file.etag, WebDavTestServer.etagOf(Uint8List.fromList([1, 2, 3])));
  });

  test('il download segue un redirect relativo della stessa origine', () async {
    // given
    server.redirects['/dav/link.kdbx'] = Uri.parse('prova.kdbx');

    // when
    final file = await client.get(
      server.uri('/dav/link.kdbx'),
      credentials: server.credentials,
      trusted: trusted,
    );

    // then
    expect(file.bytes, [1, 2, 3]);
    expect(server.requests, ['GET /dav/link.kdbx', 'GET /dav/prova.kdbx']);
  });

  test('il download senza redirect non contatta la destinazione', () async {
    server.redirects['/dav/link.kdbx'] = server.uri('/dav/prova.kdbx');
    await expectLater(
      client.getWithoutRedirects(
        server.uri('/dav/link.kdbx'),
        credentials: server.credentials,
        trusted: trusted,
      ),
      throwsA(isA<RemoteHttpException>()),
    );
    expect(server.requests, ['GET /dav/link.kdbx']);
  });

  test('credenziali rifiutate: RemoteAuthException', () async {
    await expectLater(
      client.get(
        server.uri('/dav/prova.kdbx'),
        credentials: const RemoteCredentials(userName: 'mario', password: 'no'),
        trusted: trusted,
      ),
      throwsA(isA<RemoteAuthException>()),
    );
  });

  test('scrittura e rilettura', () async {
    await client.put(
      server.uri('/dav/prova.kdbx'),
      Uint8List.fromList([9, 8]),
      credentials: server.credentials,
      trusted: trusted,
    );

    final file = await client.get(
      server.uri('/dav/prova.kdbx'),
      credentials: server.credentials,
      trusted: trusted,
    );
    expect(file.bytes, [9, 8]);
    expect(server.requests, ['PUT /dav/prova.kdbx', 'GET /dav/prova.kdbx']);
  });

  test(
    'cartella: prima le cartelle, poi i file, senza la cartella stessa',
    () async {
      server.files['/dav/Sotto cartella/altro.kdbx'] = Uint8List(4);
      server.files['/dav/b.txt'] = Uint8List(1);

      final entries = await client.list(
        server.uri('/dav'),
        credentials: server.credentials,
        trusted: trusted,
      );

      expect(entries.map((e) => (e.name, e.isDirectory)), [
        ('Sotto cartella', true),
        ('b.txt', false),
        ('prova.kdbx', false),
      ]);
      expect(entries.last.size, 3);
      expect(
        Uri.decodeComponent(entries.first.uri.path),
        '/dav/Sotto cartella/',
      );
    },
  );

  test('file inesistente: RemoteNotFoundException', () async {
    await expectLater(
      client.get(
        server.uri('/dav/manca.kdbx'),
        credentials: server.credentials,
        trusted: trusted,
      ),
      throwsA(isA<RemoteNotFoundException>()),
    );
  });

  test('http://: rifiutato senza connettersi', () async {
    await expectLater(
      client.get(
        Uri.parse('http://127.0.0.1:${server.port}/dav/prova.kdbx'),
        credentials: server.credentials,
      ),
      throwsA(isA<InsecureRemoteException>()),
    );
    expect(server.requests, isEmpty);
  });

  test('server non raggiungibile: RemoteUnreachableException', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();

    await expectLater(
      client.get(
        Uri.parse('https://127.0.0.1:$port/x.kdbx'),
        credentials: server.credentials,
      ),
      throwsA(isA<RemoteUnreachableException>()),
    );
  });

  test('risposta di Nextcloud: href assoluti e codificati', () {
    final dir = Uri.parse('https://cloud.example/remote.php/dav/files/mario/');
    const body = """<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
 <d:response><d:href>/remote.php/dav/files/mario/</d:href>
  <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
 <d:response><d:href>/remote.php/dav/files/mario/Archivio%20casa.kdbx</d:href>
  <d:propstat><d:prop><d:resourcetype/><d:getcontentlength>2048</d:getcontentlength></d:prop></d:propstat></d:response>
 <d:response><d:href>https://cloud.example/remote.php/dav/files/mario/Documenti</d:href>
  <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
</d:multistatus>""";

    final entries = WebDavClient.parseMultistatus(dir, body);

    expect(entries.map((e) => e.name), ['Documenti', 'Archivio casa.kdbx']);
    expect(entries.first.uri.path, '/remote.php/dav/files/mario/Documenti/');
    expect(entries.last.size, 2048);
    expect(
      entries.last.uri.toString(),
      'https://cloud.example/remote.php/dav/files/mario/Archivio%20casa.kdbx',
    );
  });

  test('l’elenco accetta solo figli diretti della stessa origine', () {
    // given
    final directory = Uri.parse('https://cloud.example/dav/');
    const body = '''
<d:multistatus xmlns:d="DAV:">
 <d:response><d:href>Note%20locali.kdbx</d:href></d:response>
 <d:response><d:href>https://cloud.example:443/dav/prova.kdbx</d:href></d:response>
 <d:response><d:href>https://altro.example/dav/prova.kdbx</d:href></d:response>
 <d:response><d:href>https://cloud.example:8443/dav/prova.kdbx</d:href></d:response>
 <d:response><d:href>http://cloud.example/dav/prova.kdbx</d:href></d:response>
 <d:response><d:href>https://utente@cloud.example/dav/altro.kdbx</d:href></d:response>
 <d:response><d:href>/dav/</d:href></d:response>
 <d:response><d:href>/dav-altra/prova.kdbx</d:href></d:response>
 <d:response><d:href>/dav/cartella/prova.kdbx</d:href></d:response>
 <d:response><d:href>/dav/cartella%2Fprova.kdbx</d:href></d:response>
 <d:response><d:href>/dav/cartella%5Cprova.kdbx</d:href></d:response>
 <d:response><d:href>/dav/prova.kdbx?v=1</d:href></d:response>
 <d:response><d:href>/dav/prova.kdbx#nome</d:href></d:response>
</d:multistatus>''';

    // when
    final entries = WebDavClient.parseMultistatus(directory, body);

    // then
    expect(entries.map((entry) => (entry.name, entry.uri.path)), [
      ('Note locali.kdbx', '/dav/Note%20locali.kdbx'),
      ('prova.kdbx', '/dav/prova.kdbx'),
    ]);
  });

  test('ETag cambiato fra GET e PUT: nessuna sovrascrittura', () async {
    final uri = server.uri('/dav/prova.kdbx');
    final original = await client.get(
      uri,
      credentials: server.credentials,
      trusted: trusted,
    );
    final other = Uint8List.fromList([7, 7, 7]);
    server.files['/dav/prova.kdbx'] = other;
    await expectLater(
      client.put(
        uri,
        Uint8List.fromList([9]),
        credentials: server.credentials,
        trusted: trusted,
        ifMatch: original.etag,
      ),
      throwsA(isA<RemoteConflictException>()),
    );
    expect(server.files['/dav/prova.kdbx'], other);
  });

  test('ETag corrispondente: scrittura consentita', () async {
    final uri = server.uri('/dav/prova.kdbx');
    final original = await client.get(
      uri,
      credentials: server.credentials,
      trusted: trusted,
    );
    await client.put(
      uri,
      Uint8List.fromList([9]),
      credentials: server.credentials,
      trusted: trusted,
      ifMatch: original.etag,
    );
    expect(server.files['/dav/prova.kdbx'], [9]);
  });
}
