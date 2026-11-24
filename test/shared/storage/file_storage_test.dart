import 'dart:io';
import 'dart:typed_data';

import 'package:document_access/document_access.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:kpasslib/kpasslib.dart';

/// Documenti in memoria al posto del plugin nativo.
class _FakeDocuments extends DocumentAccess {
  final files = <String, Uint8List>{};
  final released = <String>[];
  String? refreshTo;
  Exception? failWith;
  bool demoRemoved = false;
  bool? keepDemoFile;
  int demoLeases = 0;

  @override
  Future<bool> ensureDemoDatabase(Uint8List bytes) async {
    if (failWith case final e?) throw e;
    if (demoRemoved) return false;
    files.putIfAbsent(DocumentAccess.demoDatabaseUri, () => bytes);
    return true;
  }

  @override
  Future<void> deleteDemoDatabase({bool keepFile = false}) async {
    if (failWith case final e?) throw e;
    demoRemoved = true;
    keepDemoFile = keepFile;
    if (!keepFile && demoLeases == 0) {
      files.remove(DocumentAccess.demoDatabaseUri);
    }
  }

  @override
  Future<bool> retainDemoDatabase() async {
    if (failWith case final e?) throw e;
    if (demoRemoved || !files.containsKey(DocumentAccess.demoDatabaseUri)) {
      return false;
    }
    demoLeases++;
    return true;
  }

  @override
  Future<void> releaseDemoDatabase() async {
    if (failWith case final e?) throw e;
    if (demoLeases == 0) return;
    demoLeases--;
    if (demoLeases == 0 && demoRemoved) {
      files.remove(DocumentAccess.demoDatabaseUri);
    }
  }

  @override
  Future<bool> isDemoDatabaseRemoved() async {
    if (failWith case final e?) throw e;
    return demoRemoved;
  }

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

  group('demo privata', () {
    test(
      'riferimento stabile, modifica e rilettura come database locale',
      () async {
        final ref = await storage.ensureDemoDatabase(Uint8List.fromList([1]));
        expect(ref, await storage.demoDatabaseRef());
        expect(ref?.uri, DocumentAccess.demoDatabaseUri);

        await storage.write(ref!, Uint8List.fromList([2, 3]));

        expect((await storage.read(ref)).bytes, [2, 3]);
      },
    );

    test(
      'la seconda installazione conserva le modifiche già salvate',
      () async {
        final ref = await storage.ensureDemoDatabase(Uint8List.fromList([1]));
        await storage.write(ref!, Uint8List.fromList([9]));

        await storage.ensureDemoDatabase(Uint8List.fromList([1]));

        expect((await storage.read(ref)).bytes, [9]);
      },
    );

    test(
      'rimozione rinviata conserva il file e impedisce la reinstallazione',
      () async {
        final ref = await storage.ensureDemoDatabase(Uint8List.fromList([1]));

        await storage.deleteDemoDatabase(keepFile: true);

        expect(documents.keepDemoFile, isTrue);
        expect((await storage.read(ref!)).bytes, [1]);
        expect(await storage.ensureDemoDatabase(Uint8List(1)), isNull);

        await storage.deleteDemoDatabase();
        expect(storage.read(ref), throwsA(isA<FileUnavailableException>()));
      },
    );

    test('gli errori del canale restano errori storage tipizzati', () async {
      documents.failWith = const DocumentAccessException('io');
      await expectLater(
        storage.ensureDemoDatabase(Uint8List(1)),
        throwsA(isA<FileWriteException>()),
      );
      await expectLater(
        storage.deleteDemoDatabase(),
        throwsA(isA<FileWriteException>()),
      );
      await expectLater(
        storage.retainDemoDatabase(),
        throwsA(isA<FileWriteException>()),
      );
      await expectLater(
        storage.releaseDemoDatabase(),
        throwsA(isA<FileWriteException>()),
      );
      await expectLater(
        storage.isDemoDatabaseRemoved(),
        throwsA(isA<FileUnavailableException>()),
      );
    });

    test(
      'la rimozione attende tutti gli accessi di sessione e ne rifiuta altri',
      () async {
        final ref = await storage.ensureDemoDatabase(Uint8List.fromList([1]));
        expect(await storage.retainDemoDatabase(), isTrue);
        expect(await storage.retainDemoDatabase(), isTrue);
        expect(await storage.isDemoDatabaseRemoved(), isFalse);

        await storage.deleteDemoDatabase();

        expect(await storage.isDemoDatabaseRemoved(), isTrue);
        expect(await storage.retainDemoDatabase(), isFalse);
        await storage.write(ref!, Uint8List.fromList([2]));
        await storage.releaseDemoDatabase();
        expect((await storage.read(ref)).bytes, [2]);
        await storage.releaseDemoDatabase();
        expect(storage.read(ref), throwsA(isA<FileUnavailableException>()));
      },
    );
  });

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

    test(
      'rifiuta un file locale oltre il limite prima della lettura',
      () async {
        final ref = local('db.kdbx');
        final file = await File.fromUri(Uri.parse(ref.uri))
            .open(mode: FileMode.write);
        await file.truncate(KdbxResourceLimits.maxFileBytes + 1);
        await file.close();

        await expectLater(
          storage.read(ref),
          throwsA(isA<KdbxResourceLimitError>()),
        );
      },
    );

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

    test('propaga il limite di lettura del plugin', () {
      documents.failWith = const DocumentAccessException('too_large');
      expect(storage.read(ref), throwsA(isA<KdbxResourceLimitError>()));
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
