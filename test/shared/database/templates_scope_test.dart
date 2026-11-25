import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/autofill/autofill_matcher.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view_model.dart';
import 'package:keepass_mobile/features/favorites/favorites_view_model.dart';
import 'package:keepass_mobile/features/search/search_view_model.dart';
import 'package:keepass_mobile/features/password_check/password_audit.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/cross_database_transfer.dart';
import 'package:keepass_mobile/shared/database/item_edits.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

class _FailingStorage extends FileStorage {
  @override
  Future<void> write(
    FileRef ref,
    Uint8List bytes, {
    String? expectedVersion,
  }) async {
    throw StateError('scrittura simulata fallita');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('gruppo modelli: UUID assente, zero, inesistente, radice e cestino', () {
    final db = newTestDatabase();
    expect(existingTemplatesGroup(db), isNull);
    for (final uuid in [KdbxUuid.zero, KdbxUuid.random(), db.root.uuid]) {
      db.meta.entryTemplatesGroup = uuid;
      expect(existingTemplatesGroup(db), isNull);
      expect(isInTemplatesGroup(db, db.root), isFalse);
    }
    final group = db.createGroup(parent: db.root, name: 'Modelli');
    final nested = db.createGroup(parent: group, name: 'Importati');
    final entry = db.createEntry(parent: nested);
    db.meta.entryTemplatesGroup = group.uuid;
    expect(existingTemplatesGroup(db), same(group));
    expect(isInTemplatesGroup(db, group), isTrue);
    expect(isInTemplatesGroup(db, entry), isTrue);
    expect(isInTemplatesGroup(db, db.root), isFalse);
    db.move(item: group, target: db.recycleBin!);
    expect(existingTemplatesGroup(db), isNull);
    expect(isInTemplatesGroup(db, entry), isFalse);
  });

  test('ricerca, Autofill, preferiti, audit e destinazioni escludono i discendenti', () async {
    final db = newTestDatabase();
    final normal = db.createGroup(parent: db.root, name: 'Credenziali');
    final templates = db.createGroup(parent: db.root, name: 'Modelli');
    db.meta.entryTemplatesGroup = templates.uuid;
    final nested = db.createGroup(parent: templates, name: 'Importati');
    final real = addTestEntry(
      db,
      normal,
      {
        EntryFields.title: 'Reale',
        EntryFields.url: 'https://example.test',
        EntryFields.password: '123',
      },
      protectedKeys: {EntryFields.password},
    )..tags = ['Favorite'];
    for (final group in [templates, nested, db.recycleBin!]) {
      addTestEntry(
        db,
        group,
        {
          EntryFields.title: 'Rumore',
          EntryFields.url: 'https://example.test',
          EntryFields.password: '123',
        },
        protectedKeys: {EntryFields.password},
      ).tags = [
        'Favorite',
      ];
    }
    expect(searchableEntries(db).map((r) => r.entry), [real]);
    expect(autofillMatches(db, 'https://example.test'), [real]);
    final container = await newTestContainer();
    container
        .read(databaseSessionProvider.notifier)
        .open(
          DatabaseSession(
            file: const FileRef(
              uri: 'file:///synthetic.kdbx',
              name: 'synthetic.kdbx',
            ),
            database: db,
          ),
        );
    expect(container.read(favoriteEntriesProvider), [real]);
    expect(auditPasswords(db).analyzedPasswordEntriesCount, 1);
    final forbidden = [templates, nested, db.recycleBin!].map(itemIdOf);
    expect(
      entryCreationDestinations(db).map((g) => g.id),
      isNot(anyElement(isIn(forbidden))),
    );
    expect(
      moveDestinations(db, [itemIdOf(real)]).map((g) => g.id),
      isNot(anyElement(isIn(forbidden))),
    );
    expect(canMoveItem(db, real, nested), isFalse);
    final source = newTestDatabase();
    addTestEntry(source, source.root, {EntryFields.title: 'Copia sintetica'});
    expect(
      () => copySnapshotEdit(source, itemIdOf(nested))(db),
      throwsA(isA<InvalidItemEditException>()),
    );
    expect(
      () => setEntriesFavoriteEdit([itemIdOf(nested.entries.single)], true)(db),
      throwsA(isA<InvalidItemEditException>()),
    );
    expect(
      () => moveItemEdit(itemIdOf(real), itemIdOf(nested))(db),
      throwsA(isA<InvalidItemEditException>()),
    );
  });

  test(
    'primo modello: apertura senza scrittura, salvataggio atomico e riapertura',
    () async {
      final (file, db) = await saveToTempFile(newTestDatabase());
      addTearDown(() => file.parent.deleteSync(recursive: true));
      final before = file.readAsBytesSync();
      final container = await newTestContainer(file: file, database: db);
      const target = EntryEditTarget.createTemplate();
      expect(
        container.read(entryInitialDraftProvider(target)),
        const EntryDraft(),
      );
      expect(existingTemplatesGroup(db), isNull);
      expect(file.readAsBytesSync(), before);
      final subscription = container.listen(
        entryEditViewModelProvider(target),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final notifier = container.read(
        entryEditViewModelProvider(target).notifier,
      );
      await container.read(entryEditViewModelProvider(target).future);
      final id = await notifier.save(
        const EntryDraft(title: 'Personalizzato'),
        templateGroupName: 'Modelli',
      );
      expect(container.read(entryEditViewModelProvider(target)).error, isNull);
      expect(id, isNotNull);
      final reopened = await reopenFile(file);
      final group = existingTemplatesGroup(reopened)!;
      expect(group.name, 'Modelli');
      expect(group.parent, reopened.root);
      expect(reopened.meta.entryTemplatesGroup, group.uuid);
      expect(group.entries.single.uuid, findEntry(reopened, id!)!.uuid);
      expect(entryTitle(group.entries.single), 'Personalizzato');
    },
  );
  test('salvataggio fallito: nessun gruppo o UUID creato nella sessione o nel file', () async {
    final (file, db) = await saveToTempFile(newTestDatabase());
    addTearDown(() => file.parent.deleteSync(recursive: true));
    final before = file.readAsBytesSync();
    final container = await newTestContainer(
      file: file,
      database: db,
      overrides: [fileStorageProvider.overrideWithValue(_FailingStorage())],
    );
    const target = EntryEditTarget.createTemplate();
    container.listen(entryEditViewModelProvider(target), (_, _) {});
    final id = await container
        .read(entryEditViewModelProvider(target).notifier)
        .save(const EntryDraft(title: 'Fallito'), templateGroupName: 'Modelli');
    expect(id, isNull);
    expect(container.read(entryEditViewModelProvider(target)).hasError, isTrue);
    expect(
      existingTemplatesGroup(container.read(databaseSessionProvider)!.database),
      isNull,
    );
    expect(file.readAsBytesSync(), before);
  });

  test('radice configurata come modelli: credenziali visibili e nuovo gruppo separato al salvataggio', () {
    final db = newTestDatabase();
    final real = addTestEntry(db, db.root, {EntryFields.title: 'Credenziale'});
    db.meta.entryTemplatesGroup = db.root.uuid;
    expect(searchableEntries(db).map((r) => r.entry), [real]);
    expect(
      entryCreationDestinations(db).map((g) => g.id),
      contains(itemIdOf(db.root)),
    );
    createCustomTemplateEdit(
      KdbxUuid.random(),
      const EntryDraft(title: 'Primo modello'),
      'Modelli',
    )(db);
    final group = existingTemplatesGroup(db)!;
    expect(group, isNot(db.root));
    expect(db.root.entries, [real]);
    final groupUuid = group.uuid;
    createCustomTemplateEdit(
      KdbxUuid.random(),
      const EntryDraft(title: 'Secondo modello'),
      'Templates',
    )(db);
    expect(existingTemplatesGroup(db)!.uuid, groupUuid);
    expect(group.entries, hasLength(2));
    expect(group.name, 'Modelli');
  });
}
