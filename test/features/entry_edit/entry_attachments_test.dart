import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/entry/entry_view_model.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view_model.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/fake_create_storage.dart';
import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  Future<KdbxDatabase> reopen(KdbxDatabase db) async => KdbxDatabase.fromBytes(
    data: await db.save(),
    credentials: testCredentials(),
  );

  test(
    'uniqueAttachmentName come AddBinaryFromBytes: nome0.ext, nome1.ext',
    () {
      expect(uniqueAttachmentName('a.txt', ['b.txt']), 'a.txt');
      expect(uniqueAttachmentName('a.txt', ['a.txt']), 'a0.txt');
      expect(uniqueAttachmentName('a.txt', ['a.txt', 'a0.txt']), 'a1.txt');
      expect(uniqueAttachmentName('nota', ['nota']), 'nota0');
      expect(uniqueAttachmentName('.env', ['.env']), '.env0');
    },
  );

  test('allegato aggiunto, sostituito e rimosso, salvato nel file', () async {
    // given
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});

    // when: aggiunta
    final draft = EntryDraft.fromEntry(entry);
    updateEntryEdit(
      entry.uuid,
      EntryDraft(
        title: draft.title,
        attachments: [AttachmentDraft.added(name: 'a.txt', data: bytes('uno'))],
      ),
    )(db);
    var saved = findEntryByUuid(await reopen(db), entry.uuid)!;

    // then
    expect(saved.binaries.keys, ['a.txt']);
    var reopened = await reopen(db);
    saved = findEntryByUuid(reopened, entry.uuid)!;
    expect(utf8.decode(attachmentData(reopened, saved, 'a.txt')!), 'uno');
    expect(entryAttachments(reopened, saved).single.size, 3);

    // when: sostituzione, poi rimozione
    updateEntryEdit(
      entry.uuid,
      EntryDraft(
        title: 'Voce',
        attachments: [
          AttachmentDraft.added(name: 'a.txt', data: bytes('due!')),
        ],
      ),
    )(db);
    reopened = await reopen(db);
    saved = findEntryByUuid(reopened, entry.uuid)!;
    expect(utf8.decode(attachmentData(reopened, saved, 'a.txt')!), 'due!');

    updateEntryEdit(entry.uuid, const EntryDraft(title: 'Voce'))(db);
    reopened = await reopen(db);
    saved = findEntryByUuid(reopened, entry.uuid)!;
    expect(saved.binaries, isEmpty);
    // Le versioni precedenti nella cronologia conservano i loro allegati.
    expect(
      [for (final h in saved.history) ...h.binaries.keys],
      ['a.txt', 'a.txt'],
    );
    expect(
      utf8.decode(attachmentData(reopened, saved.history.last, 'a.txt')!),
      'due!',
    );
  });

  test(
    'allegato non più usato da voci né cronologia: tolto dal database',
    () async {
      final db = newTestDatabase();
      db.meta.historyMaxItems = 0;
      final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
      updateEntryEdit(
        entry.uuid,
        EntryDraft(
          title: 'Voce',
          attachments: [AttachmentDraft.added(name: 'a.bin', data: bytes('x'))],
        ),
      )(db);
      expect(db.binaries.all, hasLength(1));

      updateEntryEdit(entry.uuid, const EntryDraft(title: 'Voce'))(db);

      expect(db.binaries.all, isEmpty);
    },
  );

  test('allegati esistenti non toccati: la bozza resta uguale', () async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
    entry.binaries['a.txt'] = db.binaries.add(
      PlainBinary(data: bytes('uno'), compressed: false),
    );

    expect(EntryDraft.fromEntry(entry), EntryDraft.fromEntry(entry));
    expect(EntryDraft.fromEntry(entry).attachments.single.name, 'a.txt');
  });

  test(
    'salvataggio su file: copia in chiaro dell\'allegato, permesso rilasciato',
    () async {
      final db = newTestDatabase();
      final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
      entry.binaries['nota.txt'] = db.binaries.add(
        PlainBinary(data: bytes('contenuto'), compressed: false),
      );
      final (file, reopened) = await saveToTempFile(db);
      final storage = FakeCreateStorage();
      final container = await newTestContainer(
        file: file,
        database: reopened,
        overrides: [fileStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      final id = itemIdOf(entry);
      container.listen(entryActionsProvider(id), (_, _) {});

      final result = await container
          .read(entryActionsProvider(id).notifier)
          .saveAttachment('nota.txt');

      expect(result, AttachmentSaveResult.saved);
      expect(storage.suggestedName, 'nota.txt');
      expect(
        utf8.decode(File('${storage.dir.path}/nota.txt').readAsBytesSync()),
        'contenuto',
      );
      expect(
        await container
            .read(entryActionsProvider(id).notifier)
            .saveAttachment('manca.txt'),
        AttachmentSaveResult.failed,
      );
    },
  );
}
