import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view_model.dart';
import 'package:keepass_mobile/features/totp/totp.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  const draft = EntryDraft(
    title: 'Banca',
    userName: 'cliente',
    password: 'pin-123',
    url: 'https://banca.example',
    notes: 'note',
    custom: [
      CustomFieldDraft(key: 'PIN', value: '9999', protected: true),
      CustomFieldDraft(key: 'Codice', value: 'ABC', protected: false),
    ],
  );

  group('applyDraft', () {
    test('scrive campi standard e personalizzati con la protezione', () {
      final db = newTestDatabase();
      final entry = db.createEntry(parent: db.root);

      applyDraft(db, entry, draft);

      expect(EntryDraft.fromEntry(entry), draft);
      expect(entry.fields[EntryFields.password], isA<ProtectedTextField>());
      expect(entry.fields['PIN'], isA<ProtectedTextField>());
      expect(entry.fields['Codice'], isA<PlainTextField>());
    });

    test('rimuove i campi personalizzati tolti dalla bozza', () {
      final db = newTestDatabase();
      final entry = db.createEntry(parent: db.root);
      applyDraft(db, entry, draft);

      applyDraft(db, entry, const EntryDraft(title: 'Banca'));

      expect(entry.fields.keys, containsAll(EntryFields.standard));
      expect(entry.fields.containsKey('PIN'), isFalse);
      expect(entry.fields.containsKey('Codice'), isFalse);
    });

    test('mantiene la protezione già presente sui campi standard', () {
      final db = newTestDatabase();
      final entry = addTestEntry(
        db,
        db.root,
        {EntryFields.userName: 'x'},
        protectedKeys: {EntryFields.userName},
      );

      applyDraft(db, entry, const EntryDraft(userName: 'y'));

      expect(entry.fields[EntryFields.userName], isA<ProtectedTextField>());
      expect(entry.fields[EntryFields.userName]?.text, 'y');
    });
  });

  group('updateEntryEdit', () {
    test('la versione precedente va nella cronologia', () {
      final db = newTestDatabase();
      final entry = addTestEntry(db, db.root, {EntryFields.title: 'vecchio'});

      updateEntryEdit(entry.uuid, draft)(db);

      expect(entryTitle(entry), 'Banca');
      expect(entry.history.map(entryTitle), ['vecchio']);
    });

    test('la cronologia non supera HistoryMaxItems (10)', () {
      final db = newTestDatabase();
      final entry = addTestEntry(db, db.root, {EntryFields.title: 'v0'});

      for (var i = 1; i <= 12; i++) {
        updateEntryEdit(entry.uuid, EntryDraft(title: 'v$i'))(db);
      }

      expect(entry.history, hasLength(10));
      expect(entryTitle(entry.history.first), 'v2');
      expect(entryTitle(entry.history.last), 'v11');
      expect(entryTitle(entry), 'v12');
    });

    test('voce inesistente: errore, nessuna modifica', () {
      final db = newTestDatabase();
      expect(
        () => updateEntryEdit(KdbxUuid.random(), draft)(db),
        throwsStateError,
      );
    });
  });

  test('createEntryEdit: nuova voce con l\'UUID scelto e senza cronologia', () {
    final db = newTestDatabase();
    final group = db.createGroup(parent: db.root, name: 'Banca');
    final uuid = KdbxUuid.random();

    createEntryEdit(group.uuid, uuid, draft)(db);

    final entry = group.entries.single;
    expect(entry.uuid, uuid);
    expect(EntryDraft.fromEntry(entry), draft);
    expect(entry.history, isEmpty);
  });

  test('validateFieldName', () {
    final names = ['PIN', '', 'Title', 'PIN', ' Altro '];
    expect(validateFieldName(names, 0), isNull);
    expect(validateFieldName(names, 1), FieldNameError.empty);
    expect(validateFieldName(names, 2), FieldNameError.reserved);
    expect(validateFieldName(names, 3), FieldNameError.duplicate);
    expect(validateFieldName(names, 4), isNull);
  });

  group('EntryEditViewModel', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test(
      'nuova voce: salvata nel file e raggiungibile con l\'id restituito',
      () async {
        final db = newTestDatabase();
        final (file, opened) = await saveToTempFile(db);
        final container = await newTestContainer(file: file, database: opened);
        final target = EntryEditTarget.create(itemIdOf(opened.root));
        container.listen(entryEditViewModelProvider(target), (_, _) {});

        final id = await container
            .read(entryEditViewModelProvider(target).notifier)
            .save(draft);

        expect(id, isNotNull);
        final session = container.read(databaseSessionProvider)!;
        expect(entryTitle(findEntry(session.database, id!)!), 'Banca');
        final reopened = await reopenFile(file);
        expect(entryTitle(findEntry(reopened, id)!), 'Banca');
      },
    );

    test('nessuna modifica: nessun salvataggio e nessuna cronologia', () async {
      final db = newTestDatabase();
      final entry = addTestEntry(db, db.root, {EntryFields.title: 'x'});
      final (file, opened) = await saveToTempFile(db);
      final before = bytesOf(file);
      final container = await newTestContainer(file: file, database: opened);
      final target = EntryEditTarget.edit(itemIdOf(entry));
      container.listen(entryEditViewModelProvider(target), (_, _) {});
      final unchanged = EntryDraft.fromEntry(
        findEntry(opened, itemIdOf(entry))!,
      );

      await container
          .read(entryEditViewModelProvider(target).notifier)
          .save(unchanged);

      expect(bytesOf(file), before);
      expect(findEntry(opened, itemIdOf(entry))!.history, isEmpty);
    });
  });

  group('withTotpUri', () {
    const uri =
        'otpauth://totp/Servizio:alex?secret=JBSWY3DPEHPK3PXP&period=30';

    test(
      'sostituisce i campi TOTP di ogni formato con il campo otp protetto',
      () {
        final custom = [
          const CustomFieldDraft(key: 'PIN', value: '9999', protected: true),
          const CustomFieldDraft(
            key: 'TOTP Seed',
            value: 'AAAA',
            protected: true,
          ),
          const CustomFieldDraft(
            key: 'TOTP Settings',
            value: '30;6',
            protected: false,
          ),
          const CustomFieldDraft(
            key: 'TimeOtp-Secret-Base32',
            value: 'BBBB',
            protected: true,
          ),
        ];

        final result = withTotpUri(custom, '  $uri ');

        expect(result, [
          const CustomFieldDraft(key: 'PIN', value: '9999', protected: true),
          const CustomFieldDraft(key: 'otp', value: uri, protected: true),
        ]);
      },
    );

    test('URI non valido o di altro formato: InvalidTotpConfig', () {
      for (final bad in [
        '',
        'https://example.org',
        'otpauth://totp/x',
        'key=JBSWY3DPEHPK3PXP',
      ]) {
        expect(
          () => withTotpUri(const [], bad),
          throwsA(isA<InvalidTotpConfig>()),
          reason: bad,
        );
      }
    });
  });
}
