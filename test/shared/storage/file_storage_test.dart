import 'dart:io';
import 'dart:typed_data';

import 'package:document_access/document_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';

/// Documenti in memoria al posto del plugin nativo.
class _FakeDocuments extends DocumentAccess {
  final files = <String, Uint8List>{};
  final released = <String>[];
  String? refreshTo;
  Exception? failWith;

  @override
  Future<DocumentData> read(String uri) async {
    if (failWith case final e?) throw e;
    final bytes = files[uri];
    if (bytes == null) throw const DocumentUnavailableException();
    return DocumentData(bytes: bytes, refreshedUri: refreshTo);
  }

  @override
  Future<void> write(String uri, Uint8List bytes) async {
    if (failWith case final e?) throw e;
    files[uri] = bytes;
  }

  @override
  Future<void> release(String uri) async {
    if (failWith case final e?) throw e;
    released.add(uri);
  }
}

void main() {
  late Directory dir;
  late _FakeDocuments documents;
  late FileStorage storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('file_storage_test');
    documents = _FakeDocuments();
    storage = FileStorage(documents);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  FileRef local(String name) =>
      FileRef(uri: File('${dir.path}/$name').uri.toString(), name: name);

  group('file locali', () {
    test(
      'scrittura e rilettura, contenuto più corto senza byte residui',
      () async {
        final ref = local('db.kdbx');
        await storage.write(ref, Uint8List.fromList(List.filled(100, 7)));
        await storage.write(ref, Uint8List.fromList([1, 2, 3]));

        final stored = await storage.read(ref);

        expect(stored.bytes, [1, 2, 3]);
        expect(stored.ref, ref);
        expect(dir.listSync(), hasLength(1), reason: 'nessun file temporaneo');
      },
    );

    test('file inesistente: FileUnavailableException', () {
      expect(
        storage.read(local('manca.kdbx')),
        throwsA(isA<FileUnavailableException>()),
      );
    });

    test('cartella inesistente in scrittura: FileUnavailableException', () {
      final ref = FileRef(
        uri: File('${dir.path}/manca/db.kdbx').uri.toString(),
        name: 'db.kdbx',
      );
      expect(
        storage.write(ref, Uint8List(1)),
        throwsA(isA<FileUnavailableException>()),
      );
    });

    test('release non tocca il plugin', () async {
      await storage.release(local('db.kdbx'));
      expect(documents.released, isEmpty);
    });
  });

  group('documenti del sistema', () {
    const ref = FileRef(uri: 'content://docs/1', name: 'db.kdbx');

    test('lettura e scrittura tramite il plugin', () async {
      await storage.write(ref, Uint8List.fromList([5]));
      expect((await storage.read(ref)).bytes, [5]);
    });

    test(
      'riferimento aggiornato dal sistema: nuovo FileRef con lo stesso nome',
      () async {
        documents.files[ref.uri] = Uint8List(1);
        documents.refreshTo = 'bookmark:nuovo';

        final stored = await storage.read(ref);

        expect(stored.ref.uri, 'bookmark:nuovo');
        expect(stored.ref.name, 'db.kdbx');
      },
    );

    test('documento non raggiungibile: FileUnavailableException', () {
      expect(storage.read(ref), throwsA(isA<FileUnavailableException>()));
    });

    test('errore di scrittura: FileWriteException', () {
      documents.failWith = const DocumentAccessException('io');
      expect(
        storage.write(ref, Uint8List(1)),
        throwsA(isA<FileWriteException>()),
      );
    });

    test('release: inoltrato al plugin, gli errori sono ignorati', () async {
      await storage.release(ref);
      expect(documents.released, [ref.uri]);

      documents.failWith = const DocumentUnavailableException();
      await storage.release(ref);
    });
  });
}
