import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

/// Scrittura sempre fallita (file in sola lettura, provider offline).
class _FailingStorage extends FileStorage {
  @override
  Future<void> write(
    FileRef ref,
    Uint8List bytes, {
    String? expectedVersion,
  }) async => throw const FileWriteException();
}

DatabaseEdit _renameFirstEntry(String title) => (db) {
  db.root.allEntries.first.fields[EntryFields.title] = KdbxTextField.fromText(
    text: title,
  );
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, KdbxDatabase, File)> setUpSession({
    FileStorage? storage,
  }) async {
    final db = newTestDatabase();
    addTestEntry(db, db.root, {EntryFields.title: 'prima'});
    final (file, opened) = await saveToTempFile(db);
    final container = await newTestContainer(
      file: file,
      database: opened,
      overrides: [
        if (storage != null) fileStorageProvider.overrideWithValue(storage),
      ],
    );
    return (container, opened, file);
  }

  test('apply: salva nel file e sostituisce il database in memoria', () async {
    final (container, opened, file) = await setUpSession();

    await container
        .read(databaseSessionProvider.notifier)
        .apply(_renameFirstEntry('dopo'));

    final session = container.read(databaseSessionProvider)!;
    expect(entryTitle(session.database.root.allEntries.single), 'dopo');
    // La modifica è avvenuta su una copia: l'oggetto precedente è intatto.
    expect(entryTitle(opened.root.allEntries.single), 'prima');
    final reopened = await reopenFile(file);
    expect(entryTitle(reopened.root.allEntries.single), 'dopo');
  });

  test(
    'salvataggi successivi: il file resta apribile con la password',
    () async {
      final (container, _, file) = await setUpSession();
      final notifier = container.read(databaseSessionProvider.notifier);

      await notifier.apply(_renameFirstEntry('uno'));
      await notifier.apply(_renameFirstEntry('due'));

      final reopened = await reopenFile(file);
      expect(entryTitle(reopened.root.allEntries.single), 'due');
    },
  );

  test('scrittura fallita: errore e database in memoria invariato', () async {
    final (container, opened, file) = await setUpSession(
      storage: _FailingStorage(),
    );
    final before = bytesOf(file);

    await expectLater(
      container
          .read(databaseSessionProvider.notifier)
          .apply(_renameFirstEntry('dopo')),
      throwsA(isA<FileWriteException>()),
    );

    final session = container.read(databaseSessionProvider)!;
    expect(session.database, same(opened));
    expect(entryTitle(session.database.root.allEntries.single), 'prima');
    expect(bytesOf(file), before);
  });

  test(
    'modifica che fallisce: nessun salvataggio, database invariato',
    () async {
      final (container, opened, file) = await setUpSession();
      final before = bytesOf(file);

      await expectLater(
        container
            .read(databaseSessionProvider.notifier)
            .apply((db) => throw StateError('voce non trovata')),
        throwsA(anything),
      );

      expect(container.read(databaseSessionProvider)!.database, same(opened));
      expect(bytesOf(file), before);
    },
  );

  test('un solo salvataggio alla volta', () async {
    final (container, _, _) = await setUpSession();
    final notifier = container.read(databaseSessionProvider.notifier);

    final first = notifier.apply(_renameFirstEntry('uno'));
    await expectLater(
      notifier.apply(_renameFirstEntry('due')),
      throwsA(isA<DatabaseBusyException>()),
    );
    await first;

    expect(
      entryTitle(
        container
            .read(databaseSessionProvider)!
            .database
            .root
            .allEntries
            .single,
      ),
      'uno',
    );
  });

  test('database chiuso: DatabaseLockedException', () async {
    final container = await newTestContainer();
    expect(
      container
          .read(databaseSessionProvider.notifier)
          .apply(_renameFirstEntry('x')),
      throwsA(isA<DatabaseLockedException>()),
    );
  });
}
