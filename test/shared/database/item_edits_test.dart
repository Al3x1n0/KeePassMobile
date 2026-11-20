import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/features/entry/entry_view_model.dart';
import 'package:keepass_mobile/shared/database/item_edits.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';

import '../../helpers/test_database.dart';

class _FailingStorage extends FileStorage {
  @override
  Future<void> write(
    FileRef ref,
    Uint8List bytes, {
    String? expectedVersion,
  }) async => throw const FileWriteException();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late File file;
  late String rootId, groupId, childId, otherId, entryId;
  late KdbxUuid groupUuid, entryUuid;

  setUp(() async {
    final database = newTestDatabase();
    final group = database.createGroup(parent: database.root, name: 'A');
    group.notes = 'note conservate';
    final child = database.createGroup(parent: group, name: 'Figlio');
    final other = database.createGroup(parent: database.root, name: 'B');
    final entry = addTestEntry(
      database,
      group,
      {EntryFields.title: 'Originale', EntryFields.password: 'sintetica'},
      protectedKeys: {EntryFields.password},
    );
    entry.tags = ['tag'];
    entry.qualityCheck = false;
    entry.customData = KdbxCustomData()
      ..map['plugin'] = KdbxCustomItem(value: 'metadato sintetico');
    entry.binaries['allegato.bin'] = database.binaries.add(
      PlainBinary(data: Uint8List.fromList([7, 8]), compressed: false),
    );
    entry.pushHistory();
    rootId = itemIdOf(database.root);
    groupId = itemIdOf(group);
    childId = itemIdOf(child);
    otherId = itemIdOf(other);
    entryId = itemIdOf(entry);
    groupUuid = group.uuid;
    entryUuid = entry.uuid;
    final saved = await saveToTempFile(database);
    file = saved.$1;
    addTearDown(() => file.parent.deleteSync(recursive: true));
    container = await newTestContainer(file: file, database: saved.$2);
  });

  Future<void> apply(DatabaseEdit edit) =>
      container.read(databaseSessionProvider.notifier).apply(edit);

  test(
    'eliminazione multipla rifiuta selezione mista senza modifiche',
    () async {
      final before = file.readAsBytesSync();
      await expectLater(
        apply(deleteItemsEdit([childId, otherId], groupId)),
        throwsA(isA<InvalidItemEditException>()),
      );
      expect(file.readAsBytesSync(), before);
      await expectLater(
        apply(deleteItemsEdit([childId, childId], groupId)),
        throwsA(isA<InvalidItemEditException>()),
      );
      expect(file.readAsBytesSync(), before);
    },
  );

  test('eliminazione multipla dal cestino è definitiva', () async {
    await apply(deleteItemsEdit([childId, entryId], groupId));
    var reopened = await reopenFile(file);
    final binId = itemIdOf(existingRecycleBin(reopened)!);
    expect(isInRecycleBin(reopened, findEntry(reopened, entryId)!), isTrue);
    await apply(deleteItemsEdit([childId, entryId], binId));
    reopened = await reopenFile(file);
    expect(findEntry(reopened, entryId), isNull);
    expect(findGroup(reopened, childId), isNull);
  });

  test(
    'spostamento risultati rifiuta interamente una selezione non valida',
    () async {
      final before = file.readAsBytesSync();
      await expectLater(
        apply(moveSearchEntriesEdit([entryId, 'inesistente'], otherId)),
        throwsA(isA<InvalidItemEditException>()),
      );
      expect(file.readAsBytesSync(), before);
    },
  );

  test('ripristino multiplo recupera i gruppi precedenti', () async {
    await apply(deleteItemsEdit([childId, entryId], groupId));
    final deleted = await reopenFile(file);
    final binId = itemIdOf(existingRecycleBin(deleted)!);
    await apply(restoreItemsEdit([childId, entryId], binId));
    final reopened = await reopenFile(file);
    final parent = findGroup(reopened, groupId)!;
    expect(parent.groups.map(itemIdOf), contains(childId));
    expect(parent.entries.map(itemIdOf), contains(entryId));
  });

  test(
    'eliminazione risultati rifiuta interamente una selezione non valida',
    () async {
      final before = file.readAsBytesSync();
      await expectLater(
        apply(deleteSearchEntriesEdit([entryId, 'inesistente'])),
        throwsA(isA<InvalidItemEditException>()),
      );
      expect(file.readAsBytesSync(), before);
    },
  );

  test(
    'spostamento multiplo valida tutti gli elementi prima di salvare',
    () async {
      final before = file.readAsBytesSync();
      await expectLater(
        apply(moveItemsEdit([childId, otherId], groupId, rootId)),
        throwsA(isA<InvalidItemEditException>()),
      );
      expect(file.readAsBytesSync(), before);
      await apply(moveItemsEdit([childId, entryId], groupId, otherId));
      final reopened = await reopenFile(file);
      final target = findGroup(reopened, otherId)!;
      expect(target.groups.map(itemIdOf), contains(childId));
      expect(target.entries.map(itemIdOf), contains(entryId));
    },
  );

  test(
    'gruppo creato e modificato conserva UUID e proprietà non editate',
    () async {
      final uuid = KdbxUuid.random();
      await apply(
        createGroupEdit(
          rootId,
          uuid,
          const GroupDraft(name: ' Nuovo ', icon: KdbxIcon.world),
        ),
      );
      var reopened = await reopenFile(file);
      expect(reopened.getGroup(uuid: uuid)?.name, 'Nuovo');
      expect(reopened.getGroup(uuid: uuid)?.icon, KdbxIcon.world);
      await apply(
        updateGroupEdit(
          groupId,
          const GroupDraft(name: 'Rinominato', icon: KdbxIcon.eMail),
        ),
      );
      reopened = await reopenFile(file);
      final group = reopened.getGroup(uuid: groupUuid)!;
      expect(group.name, 'Rinominato');
      expect(group.notes, 'note conservate');
      expect(group.icon, KdbxIcon.eMail);
      expect(group.groups.single.name, 'Figlio');
    },
  );

  test('spostamento fallito conserva parent e file originali', () async {
    final before = file.readAsBytesSync();
    final original = container.read(databaseSessionProvider)!.database;
    final failing = await newTestContainer(
      file: file,
      database: original,
      overrides: [fileStorageProvider.overrideWithValue(_FailingStorage())],
    );
    await expectLater(
      failing
          .read(databaseSessionProvider.notifier)
          .apply(moveItemEdit(entryId, otherId)),
      throwsA(isA<FileWriteException>()),
    );
    expect(failing.read(databaseSessionProvider)!.database, same(original));
    expect(itemIdOf(findEntryByUuid(original, entryUuid)!.parent!), groupId);
    expect(file.readAsBytesSync(), before);
  });

  test('sposta una voce senza cambiarne UUID o campi protetti', () async {
    await apply(moveItemEdit(entryId, otherId));
    final reopened = await reopenFile(file);
    final entry = findEntryByUuid(reopened, entryUuid)!;
    expect(itemIdOf(entry.parent!), otherId);
    expect(entry.fields[EntryFields.password], isA<ProtectedTextField>());
    expect(entry.history, hasLength(1));
    expect(findGroup(reopened, groupId)!.entries, isEmpty);
  });

  test('radice, cestino e cicli rifiutati senza scrittura', () async {
    await apply(
      createGroupEdit(
        rootId,
        KdbxUuid.random(),
        const GroupDraft(name: 'Altro', icon: KdbxIcon.folder),
      ),
    );
    await apply(deleteEntryEdit(entryUuid));
    final binId = itemIdOf(
      existingRecycleBin(container.read(databaseSessionProvider)!.database)!,
    );
    for (final edit in [
      moveItemEdit(rootId, groupId),
      moveItemEdit(groupId, groupId),
      moveItemEdit(groupId, childId),
      moveItemEdit(groupId, binId),
      deleteGroupEdit(rootId),
    ]) {
      final before = file.readAsBytesSync();
      await expectLater(apply(edit), throwsA(isA<InvalidItemEditException>()));
      expect(file.readAsBytesSync(), before);
    }
  });

  test('elimina e ripristina un gruppo completo dal cestino', () async {
    await apply(deleteGroupEdit(groupId));
    var reopened = await reopenFile(file);
    expect(
      isInRecycleBin(reopened, reopened.getGroup(uuid: groupUuid)!),
      isTrue,
    );
    expect(findEntryByUuid(reopened, entryUuid)!.parent!.uuid, groupUuid);
    await apply(restoreItemEdit(groupId));
    reopened = await reopenFile(file);
    expect(reopened.getGroup(uuid: groupUuid)!.parent, reopened.root);
    expect(
      isInRecycleBin(reopened, findEntryByUuid(reopened, entryUuid)!),
      isFalse,
    );
  });

  test(
    'ripristina una voce nella radice se il vecchio gruppo non esiste più',
    () async {
      await apply(deleteEntryEdit(entryUuid));
      await apply(deleteGroupEdit(groupId));
      await apply(deleteGroupEdit(groupId));
      await apply(restoreItemEdit(entryId));
      final reopened = await reopenFile(file);
      expect(findEntryByUuid(reopened, entryUuid)!.parent, reopened.root);
    },
  );

  test(
    'svuota cestino conserva il gruppo e registra tombstone ricorsive',
    () async {
      await apply(deleteGroupEdit(groupId));
      final binUuid = (await reopenFile(file)).meta.recycleBinUuid;
      await apply(emptyRecycleBinEdit());
      final reopened = await reopenFile(file);
      expect(reopened.meta.recycleBinUuid, binUuid);
      expect(existingRecycleBin(reopened)!.children, isEmpty);
      expect(reopened.deletedObjects.keys, containsAll([groupUuid, entryUuid]));
      expect(reopened.getGroup(uuid: groupUuid), isNull);
    },
  );

  test('duplica voce: nuovi UUID, cronologia coerente, metadati e allegati conservati', () async {
    final uuid = KdbxUuid.random();
    await apply(duplicateEntryEdit(entryId, uuid, 'copia'));
    final reopened = await reopenFile(file);
    final original = findEntryByUuid(reopened, entryUuid)!;
    final copy = findEntryByUuid(reopened, uuid)!;
    expect(entryTitle(copy), 'Originale - copia');
    expect(entryTitle(original), 'Originale');
    expect(copy.fields[EntryFields.password], isA<ProtectedTextField>());
    expect(copy.history.single.uuid, uuid);
    expect(
      copy.history.single.fields[EntryFields.password],
      isA<ProtectedTextField>(),
    );
    expect(copy.tags, ['tag']);
    expect(copy.qualityCheck, isFalse);
    expect(copy.customData!.map['plugin']!.value, 'metadato sintetico');
    expect(reopened.binaries.getByRef(copy.binaries['allegato.bin']!)!.data, [
      7,
      8,
    ]);
    final working = container.read(databaseSessionProvider)!.database;
    expect(
      identical(
        findEntryByUuid(working, uuid)!.customData,
        findEntryByUuid(working, entryUuid)!.customData,
      ),
      isFalse,
    );
  });
}
