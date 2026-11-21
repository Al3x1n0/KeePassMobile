import 'package:document_access/document_access.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const access = DocumentAccess();
  final calls = <MethodCall>[];

  void reply(Object? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(DocumentAccess.channel, (call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);
  tearDown(
    () => messenger.setMockMethodCallHandler(DocumentAccess.channel, null),
  );

  test('pick: restituisce uri, nome e contenuto', () async {
    reply(
      (_) => {
        'uri': 'content://provider/doc/1',
        'name': 'prova.kdbx',
        'bytes': Uint8List.fromList([1, 2, 3]),
        'persistent': true,
      },
    );

    final picked = await access.pick();

    expect(picked?.uri, 'content://provider/doc/1');
    expect(picked?.name, 'prova.kdbx');
    expect(picked?.bytes, [1, 2, 3]);
    expect(picked?.persistent, isTrue);
    expect(calls.single.method, 'pick');
  });

  test('pick annullato: null', () async {
    reply((_) => null);
    expect(await access.pick(), isNull);
  });

  test('read: contenuto e riferimento aggiornato', () async {
    reply(
      (_) => {
        'bytes': Uint8List.fromList([9]),
        'refreshedUri': 'bookmark:nuovo',
      },
    );

    final data = await access.read('bookmark:vecchio');

    expect(data.bytes, [9]);
    expect(data.refreshedUri, 'bookmark:nuovo');
    expect(calls.single.arguments, {'uri': 'bookmark:vecchio'});
  });

  test('read senza riferimento aggiornato', () async {
    reply((_) => {'bytes': Uint8List(0)});
    expect((await access.read('content://x')).refreshedUri, isNull);
  });

  test('write: inoltra uri e contenuto', () async {
    reply((_) => null);

    await access.write('content://x', Uint8List.fromList([4, 5]));

    expect(calls.single.method, 'write');
    expect(calls.single.arguments, {
      'uri': 'content://x',
      'bytes': [4, 5],
    });
  });

  test(
    'create: inoltra nome proposto e contenuto, restituisce il documento',
    () async {
      reply(
        (_) => {
          'uri': 'content://provider/doc/2',
          'name': 'keepass (1).kdbx',
          'persistent': true,
        },
      );

      final created = await access.create(
        suggestedName: 'keepass.kdbx',
        bytes: Uint8List.fromList([7, 8]),
      );

      expect(calls.single.method, 'create');
      expect(calls.single.arguments, {
        'name': 'keepass.kdbx',
        'bytes': [7, 8],
      });
      expect(created?.uri, 'content://provider/doc/2');
      expect(created?.name, 'keepass (1).kdbx');
      expect(created?.persistent, isTrue);
    },
  );

  test('create annullato: null', () async {
    reply((_) => null);
    expect(
      await access.create(suggestedName: 'a.kdbx', bytes: Uint8List(0)),
      isNull,
    );
  });

  test('release: inoltra uri', () async {
    reply((_) => null);
    await access.release('content://x');
    expect(calls.single.method, 'release');
  });

  test('errore "unavailable": DocumentUnavailableException', () {
    reply((_) => throw PlatformException(code: 'unavailable'));
    expect(
      access.read('content://x'),
      throwsA(isA<DocumentUnavailableException>()),
    );
  });

  test('altri errori: DocumentAccessException con il codice', () {
    reply((_) => throw PlatformException(code: 'busy'));
    expect(
      access.pick(),
      throwsA(
        isA<DocumentAccessException>().having((e) => e.code, 'code', 'busy'),
      ),
    );
  });

  test('risposta inattesa: DocumentAccessException io', () {
    reply((_) => {'altro': 1});
    expect(access.read('content://x'), throwsA(isA<DocumentAccessException>()));
  });

  test('plugin assente: DocumentAccessException no_plugin', () {
    expect(
      access.read('content://x'),
      throwsA(
        isA<DocumentAccessException>().having(
          (e) => e.code,
          'code',
          'no_plugin',
        ),
      ),
    );
  });
  test('cache: lettura opaca identificata solo dall’hash', () async {
    reply((_) => Uint8List.fromList([1, 2, 3]));
    expect(await access.readRemoteCache('synthetic-hash'), [1, 2, 3]);
    expect(calls.single.method, 'readRemoteCache');
    expect(calls.single.arguments, {'id': 'synthetic-hash'});
  });

  test(
    'cache: elenco degli identificativi senza riferimenti ai file',
    () async {
      final ids = ['a' * 64, 'b' * 64];
      reply((_) => ids);
      expect(await access.listRemoteCacheIds(), ids);
      expect(calls.single.method, 'listRemoteCacheIds');
      expect(calls.single.arguments, isNull);
    },
  );

  test('cache: cancellazione con il solo identificativo e token CAS', () async {
    reply((_) => false);
    final token = Uint8List(32);
    final id = 'a' * 64;
    expect(await access.deleteRemoteCache(id, token), isFalse);
    expect(calls.single.method, 'deleteRemoteCache');
    expect(calls.single.arguments, {'id': id, 'expected': token});
  });

  test(
    'cache: scrittura atomica porta il token CAS al codice nativo',
    () async {
      reply((_) => false);
      final token = Uint8List(32);
      final record = Uint8List(40);
      expect(
        await access.writeRemoteCache(
          'synthetic-hash',
          record,
          expectedToken: token,
        ),
        isFalse,
      );
      expect(calls.single.method, 'writeRemoteCache');
      expect(calls.single.arguments, {
        'id': 'synthetic-hash',
        'bytes': record,
        'expected': token,
      });
    },
  );
}
