import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/external_change.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/database/linked_databases.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/recent_passwords_store.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

class _NoRedirectStorage extends FileStorage {
  int guardedReads = 0;
  @override
  Future<StoredFile> readWithoutRedirects(FileRef ref) {
    guardedReads++;
    return super.read(ref);
  }
}

class _MemoryStorage extends FileStorage {
  _MemoryStorage(this.files);
  final Map<FileRef, Uint8List> files;
  final reads = <FileRef>[];

  @override
  Future<StoredFile> readWithoutRedirects(FileRef ref) async {
    reads.add(ref);
    return StoredFile(ref: ref, bytes: files[ref]!);
  }
}

class _DelayedRecentPasswordsStore extends RecentPasswordsStore {
  final started = Completer<void>();
  final result = Completer<List<String>>();
  String? databaseKey;

  @override
  Future<List<String>> read(String databaseKey) {
    this.databaseKey = databaseKey;
    started.complete();
    return result.future;
  }
}

Future<
  ({
    DatabaseSession parent,
    LinkedDatabase link,
    _MemoryStorage storage,
    String entryId,
    Uint8List keyBytes,
  })
>
_linkedFixture() async {
  const parentFile = FileRef(uri: 'file:///parent.kdbx', name: 'parent.kdbx');
  const childFile = FileRef(uri: 'file:///child.kdbx', name: 'child.kdbx');
  const keyFile = FileRef(uri: 'file:///child.key', name: 'child.key');
  final keyBytes = Uint8List.fromList(List.generate(32, (index) => index + 1));
  final child = KdbxDatabase.create(
    credentials: KdbxCredentials(
      password: ProtectedData.fromString(testMasterKey),
      keyData: keyBytes,
    ),
    name: 'Collegato',
  );
  child.header.kdf = KdfId.aes;
  final entry = addTestEntry(
    child,
    child.root,
    {EntryFields.title: 'Voce collegata', EntryFields.password: 'sintetica'},
    protectedKeys: {EntryFields.password},
  );
  final bytes = Uint8List.fromList(await child.save());
  final entryId = itemIdOf(entry);
  child.clearSensitiveData();
  final parentDatabase = newTestDatabase();
  addLinkedDatabaseEdit(
    parent: parentFile,
    child: childFile,
    keyFile: keyFile,
    password: testMasterKey,
  )(parentDatabase);
  final parent = DatabaseSession(file: parentFile, database: parentDatabase);
  addTearDown(() {
    parentDatabase.clearSensitiveData();
    keyBytes.fillRange(0, keyBytes.length, 0);
  });
  return (
    parent: parent,
    link: linkedDatabases(parent).single,
    storage: _MemoryStorage({childFile: bytes, keyFile: keyBytes}),
    entryId: entryId,
    keyBytes: keyBytes,
  );
}

void main() {
  group('LinkedOpenOperation', () {
    test(
      'restituisce la sessione solo con la cronologia già precaricata',
      () async {
        // given
        final fixture = await _linkedFixture();
        final store = _DelayedRecentPasswordsStore();
        final operation = LinkedOpenOperation(
          fixture.storage,
          () => fixture.parent,
          fixture.link,
          recentPasswordsStore: store,
        );
        var completed = false;
        final opening = operation.run().then((session) {
          completed = true;
          return session;
        });

        // when
        await store.started.future;
        expect(completed, isFalse);
        store.result.complete([fixture.entryId]);
        final session = await opening;
        addTearDown(session.database.clearSensitiveData);

        // then
        expect(session.file, fixture.link.file);
        expect(session.keyFile, fixture.link.keyFile);
        expect(session.recentPasswordIds, [fixture.entryId]);
        expect(
          store.databaseKey,
          RecentPasswordsStore.databaseKey(
            fixture.link.file,
            idOfUuid(session.database.root.uuid),
          ),
        );
        expect(fixture.storage.reads, [
          fixture.link.file,
          fixture.link.keyFile,
        ]);
        expect(session.restrictRedirects, isTrue);
        expect(fixture.keyBytes, everyElement(0));
      },
    );

    test('annullamento durante la cronologia azzera subito la chiave e impedisce aperture tardive', () async {
      // given
      final fixture = await _linkedFixture();
      final store = _DelayedRecentPasswordsStore();
      final operation = LinkedOpenOperation(
        fixture.storage,
        () => fixture.parent,
        fixture.link,
        recentPasswordsStore: store,
      );
      var returnedSession = false;
      final opening = operation.run().then((session) {
        returnedSession = true;
        return session;
      });
      final canceled = expectLater(
        opening,
        throwsA(isA<DatabaseLockedException>()),
      );
      await store.started.future;
      expect(fixture.keyBytes, isNot(everyElement(0)));

      // when
      operation.cancel();

      // then: il buffer è pulito prima di sbloccare la lettura pendente.
      expect(fixture.keyBytes, everyElement(0));
      expect(store.result.isCompleted, isFalse);
      expect(returnedSession, isFalse);
      store.result.complete([fixture.entryId]);
      await canceled;
      expect(returnedSession, isFalse);
    });
  });

  test(
    'riconosce collegamenti validi e l’approvazione cambia con la destinazione',
    () {
      final db = newTestDatabase();
      final group = db.createGroup(parent: db.root, name: 'AutoOpen');
      final entry = addTestEntry(db, group, {
        EntryFields.url: 'https://example.org/one.kdbx',
      });
      final parent = DatabaseSession(
        file: const FileRef(uri: 'file:///tmp/parent.kdbx', name: 'parent'),
        database: db,
      );
      final original = linkedDatabases(parent).single;
      final approval = linkedDatabaseApprovalId(parent.file, original);
      entry.fields['IfDevice'] = KdbxTextField.fromText(
        text: 'Altro dispositivo',
      );
      final restricted = linkedDatabases(parent).single;
      expect(restricted.deviceRule, 'Altro dispositivo');
      expect(
        linkedDatabaseApprovalId(parent.file, restricted),
        isNot(approval),
      );
      entry.fields[EntryFields.url] = KdbxTextField.fromText(
        text: 'https://example.org/two.kdbx',
      );
      expect(
        linkedDatabaseApprovalId(parent.file, linkedDatabases(parent).single),
        isNot(approval),
      );
      entry.fields[EntryFields.url] = KdbxTextField.fromText(
        text: 'http://example.org/plain.kdbx',
      );
      expect(linkedDatabases(parent), isEmpty);
      entry.fields[EntryFields.url] = KdbxTextField.fromText(
        text: 'https://user:password@example.org/file.kdbx',
      );
      expect(linkedDatabases(parent), isEmpty);
    },
  );
  test(
    'anche i controlli prima del salvataggio non seguono redirect',
    () async {
      final db = newTestDatabase();
      final (file, reopened) = await saveToTempFile(db);
      addTearDown(() => file.parent.deleteSync(recursive: true));
      final storage = _NoRedirectStorage();
      final container = await newTestContainer(
        overrides: [fileStorageProvider.overrideWithValue(storage)],
      );
      final notifier = container.read(databaseSessionProvider.notifier);
      notifier.open(
        DatabaseSession(
          file: fileRefOf(file),
          database: reopened,
          fileHash: fileHashOf(file.readAsBytesSync()),
          restrictRedirects: true,
        ),
      );
      await notifier.apply((db) => db.root.name = 'Modificato');
      expect(storage.guardedReads, 1);
      expect((await reopenFile(file)).root.name, 'Modificato');
      expect(
        container.read(databaseSessionProvider)!.restrictRedirects,
        isTrue,
      );
    },
  );
}
