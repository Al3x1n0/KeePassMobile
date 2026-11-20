import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/field_references.dart';
import 'package:keepass_mobile/features/entry/entry_view_model.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('campi visibili: standard non vuoti, poi personalizzati in ordine', () {
    final db = newTestDatabase();
    final entry = addTestEntry(
      db,
      db.root,
      {
        EntryFields.title: 'Banca',
        EntryFields.userName: 'cliente',
        EntryFields.password: 'pin',
        EntryFields.url: '',
        'zeta': 'z',
        'PIN': '9999',
        'otp': 'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP',
      },
      protectedKeys: {'PIN'},
    );

    final fields = visibleFields(entry);

    expect(fields.map((f) => f.key), [
      EntryFields.userName,
      EntryFields.password,
      'otp',
      'PIN',
      'zeta',
    ]);
    // Il segreto TOTP resta nascosto anche se il campo non è protetto.
    expect(fields.where((f) => f.protected).map((f) => f.key), [
      EntryFields.password,
      'otp',
      'PIN',
    ]);
  });

  test('campi personalizzati seguono le posizioni del modello collegato', () {
    final db = newTestDatabase();
    final template = addTestEntry(db, db.root, {
      '_etm_template': '1',
      '_etm_position_Zeta': '1',
      '_etm_position_Alfa': '2',
      '_etm_position_Beta': 'non valido',
    });
    final entry = addTestEntry(db, db.root, {
      '_etm_template_uuid': itemIdOf(template),
      'Alfa': 'a',
      'Beta': 'b',
      'Zeta': 'z',
      'Gamma': 'g',
    });

    expect(visibleFields(entry, database: db).map((f) => f.key), [
      'Zeta',
      'Alfa',
      'Beta',
      'Gamma',
    ]);
    expect(visibleFields(entry).map((f) => f.key), [
      '_etm_template_uuid',
      'Alfa',
      'Beta',
      'Gamma',
      'Zeta',
    ]);
  });

  test('eliminazione: prima nel cestino, poi definitiva', () async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Banca'});
    final id = itemIdOf(entry);
    final (file, opened) = await saveToTempFile(db);
    final container = await newTestContainer(file: file, database: opened);
    container.listen(entryActionsProvider(id), (_, _) {});
    final actions = container.read(entryActionsProvider(id).notifier);

    expect(container.read(entryDeletesPermanentlyProvider(id)), isFalse);
    expect(await actions.delete(), isTrue);

    var session = container.read(databaseSessionProvider)!;
    final moved = findEntry(session.database, id)!;
    expect(isInRecycleBin(session.database, moved), isTrue);
    expect(container.read(entryDeletesPermanentlyProvider(id)), isTrue);
    final reopened = await reopenFile(file);
    expect(isInRecycleBin(reopened, findEntry(reopened, id)!), isTrue);

    expect(await actions.delete(), isTrue);

    session = container.read(databaseSessionProvider)!;
    expect(findEntry(session.database, id), isNull);
    expect(findEntry(await reopenFile(file), id), isNull);
  });

  test('copia: valore negli appunti e durata della pulizia', () async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.password: 'pin-123'});
    final id = itemIdOf(entry);
    final (file, opened) = await saveToTempFile(db);
    final clipboard = FakeClipboard(TestDefaultBinaryMessengerBinding.instance);
    final container = await newTestContainer(file: file, database: opened);
    container.listen(entryActionsProvider(id), (_, _) {});

    final clearAfter = await container
        .read(entryActionsProvider(id).notifier)
        .copy(EntryFields.password);

    expect(clipboard.text, 'pin-123');
    expect(clearAfter, const Duration(seconds: 30));
    container.dispose();
  });

  test(
    'copia risolve riferimenti, propaga protezione e rifiuta cicli',
    () async {
      final db = newTestDatabase();
      final entry = addTestEntry(
        db,
        db.root,
        {
          EntryFields.title: 'Riferimenti',
          EntryFields.password: 'segreto-test',
          'alias': '{PASSWORD}',
          'ciclo': '{S:ciclo}',
        },
        protectedKeys: {EntryFields.password},
      );
      final id = itemIdOf(entry);
      final fields = visibleFields(entry, database: db);
      expect(fields.singleWhere((f) => f.key == 'alias').protected, isTrue);
      expect(fields.singleWhere((f) => f.key == 'alias').value, 'segreto-test');
      expect(
        fields.singleWhere((f) => f.key == 'ciclo').issue,
        FieldReferenceIssue.cycle,
      );
      final (file, opened) = await saveToTempFile(db);
      final clipboard = FakeClipboard(
        TestDefaultBinaryMessengerBinding.instance,
      );
      final container = await newTestContainer(file: file, database: opened);
      container.listen(entryActionsProvider(id), (_, _) {});
      final actions = container.read(entryActionsProvider(id).notifier);
      await actions.copy('alias');
      expect(clipboard.text, 'segreto-test');
      await expectLater(
        actions.copy('ciclo'),
        throwsA(isA<FieldReferenceException>()),
      );
      expect(clipboard.text, 'segreto-test');
      expect(findEntry(opened, id)!.fields['alias']!.text, '{PASSWORD}');
      container.dispose();
    },
  );
}
