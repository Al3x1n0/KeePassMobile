import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view_model.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('modifica ordinata dal modello e salvataggio invariato', () async {
    final db = newTestDatabase();
    final model = addTestEntry(db, db.root, {
      '_etm_template': '1',
      '_etm_position_Zeta': '1',
      '_etm_position_Alfa': '2',
      '_etm_position_Beta': 'non valido',
    });
    final entry = addTestEntry(
      db,
      db.root,
      {
        '_etm_template_uuid': itemIdOf(model),
        'Alfa': 'a',
        'Gamma': 'g',
        'Zeta': 'z',
        'Beta': 'b',
      },
      protectedKeys: {'Zeta'},
    );
    final id = itemIdOf(entry);
    final (file, opened) = await saveToTempFile(db);
    final container = await newTestContainer(file: file, database: opened);
    final target = EntryEditTarget.edit(id);
    container.listen(entryEditViewModelProvider(target), (_, _) {});
    final draft = container.read(entryInitialDraftProvider(target))!;
    expect(draft.custom.map((f) => f.key), [
      'Zeta',
      'Alfa',
      '_etm_template_uuid',
      'Beta',
      'Gamma',
    ]);
    expect(draft.custom.first.protected, isTrue);
    expect(
      await container
          .read(entryEditViewModelProvider(target).notifier)
          .save(draft),
      id,
    );
    final saved = container.read(entryInitialDraftProvider(target))!;
    expect(saved, draft);
    final reopened = await reopenFile(file);
    expect(
      reopened.root.allEntries.singleWhere((e) => itemIdOf(e) == id).history,
      isEmpty,
    );
  });

  test(
    'copia un modello standard nel gruppo scelto e riapre il KDBX',
    () async {
      final db = newTestDatabase();
      final templates = db.createGroup(parent: db.root, name: 'Templates');
      final target = db.createGroup(parent: db.root, name: 'Destination');
      db.meta.entryTemplatesGroup = templates.uuid;
      final source = addTestEntry(
        db,
        templates,
        {
          EntryFields.title: 'Sample',
          EntryFields.password: 'example-password',
          'PIN': '1234',
        },
        protectedKeys: {EntryFields.password, 'PIN'},
      );
      source.overrideUrl = 'https://example.org';
      source.customData = KdbxCustomData()
        ..map['sample'] = KdbxCustomItem(value: 'metadata');
      source.pushHistory();
      source.history.single.customData = KdbxCustomData()
        ..map['previous'] = KdbxCustomItem(value: 'history');
      final structured = addTestEntry(db, templates, {'_etm_template': 'true'});
      expect(standardEntryTemplates(db), [source]);
      final newId = KdbxUuid.random();
      createFromTemplateEdit(
        target.uuid,
        newId,
        itemIdOf(source),
        EntryDraft.fromEntry(source),
      )(db);
      final result = target.entries.single;
      expect(result.uuid, newId);
      expect(result.fields['PIN'], isA<ProtectedTextField>());
      expect(result.overrideUrl, 'https://example.org');
      expect(result.customData?.map['sample']?.value, 'metadata');
      expect(
        result.history.single.customData?.map['previous']?.value,
        'history',
      );
      expect(templates.entries, [source, structured]);
      final reopened = (await saveToTempFile(db)).$2;
      final saved = reopened.root.allEntries.singleWhere(
        (e) => e.uuid == newId,
      );
      expect(saved.fields[EntryFields.password]?.text, 'example-password');
      expect(saved.fields['PIN'], isA<ProtectedTextField>());
      expect(saved.overrideUrl, 'https://example.org');
    },
  );

  test('rifiuta un modello rimosso o esterno al gruppo configurato', () {
    final db = newTestDatabase();
    final model = addTestEntry(db, db.root, {EntryFields.title: 'Sample'});
    expect(standardEntryTemplates(db), isEmpty);
    expect(
      () => createFromTemplateEdit(
        db.root.uuid,
        KdbxUuid.random(),
        itemIdOf(model),
        EntryDraft.fromEntry(model),
      )(db),
      throwsStateError,
    );
  });
}
