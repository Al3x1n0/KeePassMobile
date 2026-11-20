import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view_model.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/database/item_edits.dart';
import 'package:keepass_mobile/shared/ui/entry_icon.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  Future<KdbxDatabase> saveAndReopen(KdbxDatabase db) async =>
      KdbxDatabase.fromBytes(
        data: await db.save(),
        credentials: testCredentials(),
      );

  group('parseTags (StrUtil.StringToTags)', () {
    test(
      'separatori , e ;, spazi tolti, niente vuoti né duplicati, ordinati',
      () {
        expect(parseTags(' web ; Banca,, banca ;web,  '), [
          'Banca',
          'banca',
          'web',
        ]);
        expect(parseTags(''), isEmpty);
        expect(parseTags('a:b'), ['a:b']);
      },
    );

    test('tagsText: separati da virgola', () {
      expect(tagsText(['a', 'b']), 'a, b');
    });
  });

  group('isExpired', () {
    final now = DateTime.utc(2026, 11, 4, 12);

    test('scade nel passato: scaduta', () {
      final entry = newTestDatabase().createEntry(
        parent: newTestDatabase().root,
      );
      entry.times
        ..expires = true
        ..expiry = KdbxTime(DateTime.utc(2026, 11, 4, 11));
      expect(isExpired(entry, now), isTrue);
    });

    test('scade nel futuro o non scade: non scaduta', () {
      final db = newTestDatabase();
      final entry = db.createEntry(parent: db.root);
      entry.times
        ..expires = true
        ..expiry = KdbxTime(DateTime.utc(2026, 11, 5));
      expect(isExpired(entry, now), isFalse);
      entry.times
        ..expires = false
        ..expiry = KdbxTime(DateTime.utc(2000));
      expect(isExpired(entry, now), isFalse);
    });
  });

  test('icona, scadenza e tag salvati nel file e riletti', () async {
    // given
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
    final expiry = DateTime(2030, 1, 2, 3, 4);
    final draft = EntryDraft.fromEntry(entry);
    final changed = EntryDraft(
      title: draft.title,
      icon: KdbxIcon.homebanking,
      expires: true,
      expiry: expiry,
      tags: parseTags('banca, lavoro'),
    );

    // when
    updateEntryEdit(entry.uuid, changed)(db);
    final reopened = await saveAndReopen(db);

    // then
    final saved = findEntryByUuid(reopened, entry.uuid)!;
    expect(saved.icon, KdbxIcon.homebanking);
    expect(saved.times.expires, isTrue);
    expect(
      saved.times.expiry.time?.millisecondsSinceEpoch,
      expiry.millisecondsSinceEpoch,
    );
    expect(saved.tags, ['banca', 'lavoro']);
    expect(EntryDraft.fromEntry(saved), changed);
  });

  test('icona cambiata: l\'icona personalizzata viene tolta', () {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
    final custom = KdbxUuid.random();
    entry.customIcon = custom;

    updateEntryEdit(entry.uuid, EntryDraft(title: 'Voce', icon: entry.icon))(
      db,
    );
    expect(entry.customIcon, custom);

    updateEntryEdit(
      entry.uuid,
      const EntryDraft(title: 'Voce', icon: KdbxIcon.star),
    )(db);
    expect(entry.customIcon, isNull);
  });

  test('selezione e importazione icona persistono nel database', () async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
    final id = KdbxUuid.random();
    final data = <int>[1, 2, 3];
    updateEntryEdit(
      entry.uuid,
      EntryDraft(
        title: 'Voce',
        iconChoice: IconChoice(icon: entry.icon, customId: id, data: data),
      ),
    )(db);
    final reopened = await saveAndReopen(db);
    expect(reopened.root.entries.single.customIcon, id);
    expect(reopened.meta.customIcons[id]?.data, data);
    updateEntryEdit(
      entry.uuid,
      EntryDraft(
        title: 'Voce',
        iconChoice: IconChoice(icon: entry.icon),
      ),
    )(db);
    expect(entry.customIcon, isNull);
    updateEntryEdit(
      entry.uuid,
      EntryDraft(
        title: 'Voce',
        iconChoice: IconChoice(icon: entry.icon, customId: id),
      ),
    )(db);
    expect(entry.customIcon, id);
  });

  test('senza tag la voce non riceve un elenco vuoto', () {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
    expect(entry.tags, isNull);

    updateEntryEdit(entry.uuid, const EntryDraft(title: 'Altro'))(db);

    expect(entry.tags, isNull);
  });

  test('ogni icona KeePass ha un\'icona Material distinta', () {
    final icons = {for (final icon in KdbxIcon.values) kdbxIconData(icon)};
    expect(KdbxIcon.values, hasLength(69));
    expect(icons, hasLength(69));
  });
}
