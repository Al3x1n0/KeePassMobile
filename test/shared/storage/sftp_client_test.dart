import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/storage/sftp_client.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';

// Come SftpStorage.java: upload temporaneo e rinomina; l'originale non va
// cancellato se la rinomina non riesce.
class MemorySftp extends Fake implements SftpClient {
  final files = <String, Uint8List>{
    '/demo.kdbx': Uint8List.fromList([1, 2]),
  };
  final removed = <String>[];
  bool failRename = false;
  bool failWrite = false;
  bool closed = false;

  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) async {
    if (mode == SftpFileOpenMode.read && !files.containsKey(path)) {
      throw SftpStatusError(SftpStatusCode.noSuchFile, 'synthetic');
    }
    return MemorySftpFile(this, path);
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    if (failRename) throw SftpStatusError(SftpStatusCode.failure, 'synthetic');
    files[newPath] = files.remove(oldPath)!;
  }

  @override
  Future<void> remove(String filename) async {
    removed.add(filename);
    files.remove(filename);
  }

  @override
  Future<List<SftpName>> listdir(String path) async => [
    for (final name in [
      '.',
      '..',
      'demo.kdbx',
      'a b#%.kdbx',
      'folder',
      '../bad',
    ])
      SftpName(
        filename: name,
        longname: '',
        attr: SftpFileAttrs(
          size: 2,
          mode: SftpFileMode.value(name == 'folder' ? 0x4000 : 0x8000),
        ),
      ),
  ];
}

class MemorySftpFile extends Fake implements SftpFile {
  MemorySftpFile(this.server, this.path);
  final MemorySftp server;
  final String path;

  @override
  Future<void> close() async {}

  @override
  Stream<Uint8List> read({
    int? length,
    int offset = 0,
    void Function(int)? onProgress,
    int chunkSize = 32768,
    int maxPendingRequests = 64,
  }) async* {
    yield server.files[path]!;
  }

  @override
  Future<void> writeBytes(
    Uint8List bytes, {
    int offset = 0,
    int chunkSize = 16 * 1024,
    int maxPendingRequests = 64,
  }) async {
    server.files[path] = Uint8List.fromList(bytes);
    if (server.failWrite) {
      throw SftpStatusError(SftpStatusCode.failure, 'synthetic');
    }
  }
}

void main() {
  final uri = Uri.parse('sftp://example.test/demo.kdbx');
  const credentials = RemoteCredentials(
    userName: 'demo',
    password: 'synthetic',
  );
  late MemorySftp server;
  late SftpStorageClient client;
  setUp(() {
    server = MemorySftp();
    client = SftpStorageClient(
      connector: (_, _, verify) async {
        if (!await verify('ssh-ed25519', 'SHA256:synthetic')) {
          throw const RemoteCanceledException();
        }
        return (
          files: server,
          close: () async {
            server.closed = true;
          },
        );
      },
    );
  });

  test('scrive il temporaneo e rinomina, poi rilegge il contenuto', () async {
    await client.put(
      uri,
      Uint8List.fromList([3, 4]),
      credentials: credentials,
      verifyHost: (_, _) async => true,
    );
    expect(server.files.keys, ['/demo.kdbx']);
    expect(
      (await client.get(
        uri,
        credentials: credentials,
        verifyHost: (_, _) async => true,
      )).bytes,
      [3, 4],
    );
    expect(server.removed, isEmpty);
    expect(server.closed, isTrue);
  });

  for (final writeFailure in [false, true]) {
    test(
      'errore ${writeFailure ? 'upload' : 'rinomina'}: originale intatto',
      () async {
        server.failRename = !writeFailure;
        server.failWrite = writeFailure;
        await expectLater(
          client.put(
            uri,
            Uint8List.fromList([9]),
            credentials: credentials,
            verifyHost: (_, _) async => true,
          ),
          throwsA(isA<RemoteSftpException>()),
        );
        expect(server.files, {
          '/demo.kdbx': [1, 2],
        });
        expect(server.removed.single, endsWith('.tmp'));
        expect(server.closed, isTrue);
      },
    );
  }

  test('elenca cartelle prima dei file e codifica i nomi speciali', () async {
    final entries = await client.list(
      Uri.parse('sftp://example.test/'),
      credentials: credentials,
      verifyHost: (_, _) async => true,
    );
    expect(entries.map((e) => e.name), ['folder', 'a b#%.kdbx', 'demo.kdbx']);
    expect(entries[1].uri.pathSegments.last, 'a b#%.kdbx');
    expect(entries[1].uri.hasFragment, isFalse);
    expect(entries.first.uri.path, '/folder/');
  });

  test('file assente: errore dedicato, trasporto chiuso', () async {
    await expectLater(
      client.get(
        uri.replace(path: '/absent'),
        credentials: credentials,
        verifyHost: (_, _) async => true,
      ),
      throwsA(isA<RemoteNotFoundException>()),
    );
    expect(server.closed, isTrue);
  });

  test('fiducia rifiutata: nessuna lettura', () async {
    await expectLater(
      client.get(
        uri,
        credentials: credentials,
        verifyHost: (_, _) async => false,
      ),
      throwsA(isA<RemoteCanceledException>()),
    );
  });

  test('timeout: chiude il trasporto', () async {
    client = SftpStorageClient(
      timeout: const Duration(milliseconds: 10),
      connector: (_, _, _) async => (
        files: SlowSftp(),
        close: () async {
          server.closed = true;
        },
      ),
    );
    await expectLater(
      client.get(
        uri,
        credentials: credentials,
        verifyHost: (_, _) async => true,
      ),
      throwsA(isA<RemoteUnreachableException>()),
    );
    expect(server.closed, isTrue);
  });

  test('URL con credenziali, schema errato e porta errata rifiutati', () {
    for (final url in [
      'sftp://demo:secret@example.test/a',
      'http://example.test/a',
      'sftp://example.test:65536/a',
      'sftp://example.test/a?key=value',
    ]) {
      expect(
        () => SftpStorageClient.validate(Uri.parse(url)),
        throwsA(isA<InvalidRemoteAddressException>()),
      );
    }
  });
  test(
    'decifratura chiave non cattura callback non trasferibili fra isolate',
    () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final unsendable = ReceivePort();
      addTearDown(unsendable.close);
      final pem = await File('test/fixtures/ssh/client_ed25519.pem')
          .readAsString();
      await expectLater(
        const SftpStorageClient().get(
          Uri.parse('sftp://127.0.0.1:$port/demo.kdbx'),
          credentials: RemoteCredentials(
            userName: 'demo',
            password: 'synthetic-passphrase',
            privateKey: pem,
          ),
          verifyHost: (_, _) async {
            unsendable.sendPort.send(null);
            return true;
          },
        ),
        throwsA(isA<RemoteUnreachableException>()),
      );
    },
  );

  test('passphrase errata distinta dagli errori di rete', () async {
    final pem = await File('test/fixtures/ssh/client_ed25519.pem')
        .readAsString();
    await expectLater(
      const SftpStorageClient().get(
        Uri.parse('sftp://127.0.0.1:9/demo.kdbx'),
        credentials: RemoteCredentials(
          userName: 'demo',
          password: 'wrong',
          privateKey: pem,
        ),
        verifyHost: (_, _) async => true,
      ),
      throwsA(isA<InvalidSshKeyException>()),
    );
  });
}

class SlowSftp extends Fake implements SftpClient {
  @override
  Future<SftpFile> open(
    String path, {
    SftpFileOpenMode mode = SftpFileOpenMode.read,
  }) => Completer<SftpFile>().future;
}
