import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/external_change.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/database/linked_databases.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
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

void main() {
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
