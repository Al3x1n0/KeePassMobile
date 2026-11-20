import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/entry/entry_view_model.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view_model.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Voce con tre versioni precedenti (A, B, C dalla più vecchia).
  (KdbxDatabase, KdbxEntry) withHistory() {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'A'});
    var minute = 0;
    for (final title in ['B', 'C', 'D']) {
      entry.times.modification = KdbxTime(
        DateTime.utc(2026, 1, 1, 0, minute++),
      );
      entry.pushHistory();
      entry.fields[EntryFields.title] = KdbxTextField.fromText(text: title);
    }
    entry.times.modification = KdbxTime(DateTime.utc(2026, 1, 1, 0, minute));
    return (db, entry);
  }

  List<String> titles(KdbxEntry entry) => [
    for (final h in entry.history) entryTitle(h),
  ];

  test('ripristino: voce come la versione, l\'attuale va nella cronologia', () {
    final (db, entry) = withHistory();

    restoreHistoryEdit(entry.uuid, 1)(db);

    expect(entryTitle(entry), 'B');
    expect(titles(entry), ['A', 'B', 'C', 'D']);
  });

  test(
    'ripristino rispetta HistoryMaxItems: tolta la versione più vecchia',
    () {
      final (db, entry) = withHistory();
      db.meta.historyMaxItems = 3;

      restoreHistoryEdit(entry.uuid, 0)(db);

      expect(entryTitle(entry), 'A');
      expect(titles(entry), ['B', 'C', 'D']);
    },
  );

  test('eliminazione di una versione', () {
    final (db, entry) = withHistory();

    deleteHistoryEdit(entry.uuid, 1)(db);

    expect(titles(entry), ['A', 'C']);
    expect(entryTitle(entry), 'D');
  });

  test('versione inesistente: errore, voce invariata', () {
    final (db, entry) = withHistory();

    expect(() => restoreHistoryEdit(entry.uuid, 9)(db), throwsStateError);
    expect(() => deleteHistoryEdit(entry.uuid, 9)(db), throwsStateError);
    expect(titles(entry), ['A', 'B', 'C']);
  });

  group('HistoryMaxSize (MaintainBackups)', () {
    test(
      'elimina le versioni più vecchie finché la dimensione è nel limite',
      () {
        final (db, entry) = withHistory();
        final one = entrySize(db, entry.history.first);
        db.meta
          ..historyMaxItems = -1
          ..historyMaxSize = one * 2;

        trimHistory(db, entry);

        expect(titles(entry), ['B', 'C']);
      },
    );

    test('limite 0: nessuna versione; -1: nessun limite', () {
      final (db, entry) = withHistory();
      db.meta
        ..historyMaxItems = -1
        ..historyMaxSize = -1;
      trimHistory(db, entry);
      expect(entry.history, hasLength(3));

      db.meta.historyMaxSize = 0;
      trimHistory(db, entry);
      expect(entry.history, isEmpty);
    });

    test('la dimensione segue PwEntry.GetSize: testo, tag e allegati', () {
      final db = newTestDatabase();
      final entry = db.createEntry(parent: db.root);
      entry.fields.clear();
      expect(entrySize(db, entry), 276);

      entry.fields['Title'] = KdbxTextField.fromText(text: 'abc');
      expect(entrySize(db, entry), 276 + 40 + (5 + 3) * 2);

      entry.tags = ['web'];
      expect(entrySize(db, entry), 276 + 40 + 8 + (5 + 3 + 3) * 2);

      entry.binaries['a.txt'] = db.binaries.add(
        PlainBinary(data: List.filled(100, 1), compressed: false),
      );
      expect(
        entrySize(db, entry),
        276 + 40 + 8 + 65 + 100 + (5 + 3 + 3 + 5) * 2,
      );
    });
  });

  test('ripristino salvato e riaperto dal file', () async {
    final (db, entry) = withHistory();
    final (file, reopened) = await saveToTempFile(db);
    final container = await newTestContainer(file: file, database: reopened);
    addTearDown(container.dispose);
    final id = itemIdOf(entry);
    container.listen(entryActionsProvider(id), (_, _) {});

    expect(
      await container.read(entryActionsProvider(id).notifier).restoreHistory(0),
      isTrue,
    );

    final onDisk = findEntryByUuid(await reopenFile(file), entry.uuid)!;
    expect(entryTitle(onDisk), 'A');
    expect(titles(onDisk), ['A', 'B', 'C', 'D']);
    expect(container.read(historyEntryProvider((id, 3))), isNotNull);
    expect(container.read(historyEntryProvider((id, 4))), isNull);
  });
}
