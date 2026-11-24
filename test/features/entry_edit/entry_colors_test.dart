import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view_model.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/entry_templates.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('colori KDBX in modifica', () {
    test('conserva colori personalizzati se cambia un altro campo', () async {
      final db = newTestDatabase();
      final entry = addTestEntry(db, db.root, {EntryFields.title: 'Esempio'})
        ..background = '#b4e7cD'
        ..foreground = '#123aBc';
      final (file, opened) = await saveToTempFile(db);
      final container = await newTestContainer(file: file, database: opened);
      final target = EntryEditTarget.edit(itemIdOf(entry));
      container.listen(entryEditViewModelProvider(target), (_, _) {});
      final initial = container.read(entryInitialDraftProvider(target))!;
      expect(initial.background, '#b4e7cD');
      expect(initial.backgroundChanged, isFalse);

      await container
          .read(entryEditViewModelProvider(target).notifier)
          .save(
            EntryDraft(
              title: 'Titolo aggiornato',
              background: initial.background,
            ),
          );

      final saved = findEntry(await reopenFile(file), itemIdOf(entry))!;
      expect(entryTitle(saved), 'Titolo aggiornato');
      expect(saved.background, '#b4e7cD');
      expect(saved.foreground, '#123aBc');
      expect(saved.history.single.background, '#b4e7cD');
      expect(saved.history.single.foreground, '#123aBc');
    });

    test('conserva anche valori vuoti o non validi senza una scelta', () {
      for (final original in [null, '', '#123', 'red']) {
        final db = newTestDatabase();
        final entry = db.createEntry(parent: db.root)
          ..background = original
          ..foreground = '#123456';

        updateEntryEdit(entry.uuid, const EntryDraft(title: 'Aggiornato'))(db);

        expect(entry.background, original);
        expect(entry.foreground, '#123456');
      }
    });

    for (final choice in ['#39854A', null]) {
      test(
        'scelta esplicita $choice aggiorna solo lo sfondo e riapre il KDBX',
        () async {
          final db = newTestDatabase();
          final entry =
              addTestEntry(db, db.root, {EntryFields.title: 'Esempio'})
                ..background = '#b4e7cD'
                ..foreground = '#123aBc';
          final (file, opened) = await saveToTempFile(db);
          final container = await newTestContainer(
            file: file,
            database: opened,
          );
          final target = EntryEditTarget.edit(itemIdOf(entry));
          container.listen(entryEditViewModelProvider(target), (_, _) {});

          await container
              .read(entryEditViewModelProvider(target).notifier)
              .save(
                EntryDraft(
                  title: 'Esempio',
                  background: choice,
                  backgroundChanged: true,
                ),
              );

          final current = findEntry(
            container.read(databaseSessionProvider)!.database,
            itemIdOf(entry),
          )!;
          expect(current.background, choice);
          final saved = findEntry(await reopenFile(file), itemIdOf(entry))!;
          expect(saved.background ?? '', choice ?? '');
          expect(saved.foreground, '#123aBc');
          expect(saved.history.single.background, '#b4e7cD');
        },
      );
    }

    test(
      'bozza invariata con colori personalizzati non riscrive il file',
      () async {
        final db = newTestDatabase();
        final entry = db.createEntry(parent: db.root)
          ..background = '#b4e7cD'
          ..foreground = '#123aBc';
        final (file, opened) = await saveToTempFile(db);
        final container = await newTestContainer(file: file, database: opened);
        final target = EntryEditTarget.edit(itemIdOf(entry));
        container.listen(entryEditViewModelProvider(target), (_, _) {});
        final before = bytesOf(file);

        await container
            .read(entryEditViewModelProvider(target).notifier)
            .save(container.read(entryInitialDraftProvider(target))!);

        expect(bytesOf(file), before);
        expect(findEntry(opened, itemIdOf(entry))!.history, isEmpty);
      },
    );
  });

  test('nuova voce propaga il colore dalla bozza nel KDBX salvato', () async {
    final db = newTestDatabase();
    final id = KdbxUuid.random();

    createEntryEdit(
      db.root.uuid,
      id,
      const EntryDraft(
        title: 'Nuova',
        background: '#39854A',
        backgroundChanged: true,
      ),
    )(db);

    final reopened = (await saveToTempFile(db)).$2;
    expect(findEntryByUuid(reopened, id)!.background, '#39854A');
  });

  for (final structured in [false, true]) {
    test(
      'modello ${structured ? 'strutturato' : 'standard'} propaga colori originali o scelta esplicita',
      () async {
        final db = newTestDatabase();
        final group = db.createGroup(parent: db.root, name: 'Modelli');
        db.meta.entryTemplatesGroup = group.uuid;
        final template =
            addTestEntry(db, group, {
                EntryFields.title: 'Modello',
                if (structured) structuredTemplateMarker: '1',
              })
              ..background = '#b4e7cD'
              ..foreground = '#123aBc';
        final original = structured
            ? draftFromStructuredTemplate(template)
            : EntryDraft.fromEntry(template);
        expect(original.background, '#b4e7cD');
        final ids = <KdbxUuid>[];
        for (final choice in [
          original,
          const EntryDraft(background: '#39854A', backgroundChanged: true),
          const EntryDraft(backgroundChanged: true),
        ]) {
          final id = KdbxUuid.random();
          ids.add(id);
          createFromTemplateEdit(db.root.uuid, id, itemIdOf(template), choice)(
            db,
          );
        }

        final reopened = (await saveToTempFile(db)).$2;
        final saved = [for (final id in ids) findEntryByUuid(reopened, id)!];
        expect(saved.map((entry) => entry.background ?? ''), [
          '#b4e7cD',
          '#39854A',
          '',
        ]);
        expect(saved.map((entry) => entry.foreground), everyElement('#123aBc'));
        expect(template.background, '#b4e7cD');
        expect(template.foreground, '#123aBc');
      },
    );
  }
}
