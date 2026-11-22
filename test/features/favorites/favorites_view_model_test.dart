import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/favorites/favorites_view_model.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

Future<KdbxDatabase> _roundTrip(KdbxDatabase database) async =>
    KdbxDatabase.fromBytes(
      data: Uint8List.fromList(await database.save()),
      credentials: testCredentials(),
    );

void main() {
  for (final (major, minor) in [(3, 1), (4, 0), (4, 1)]) {
    test('KDBX $major.$minor conserva gli altri tag dei preferiti', () async {
      final database = newTestDatabase()..version = (major, minor);
      database.header.kdfSettings = const AesKdfSettings(rounds: 1000);
      final entry = addTestEntry(database, database.root, {
        EntryFields.title: 'Esempio',
      })..tags = ['Lavoro'];
      expect(isEntryFavorite(entry), isFalse);

      setEntryFavoriteEdit(entry.uuid, true)(database);
      final reopened = await _roundTrip(database);
      final saved = findEntryByUuid(reopened, entry.uuid)!;
      expect(isEntryFavorite(saved), isTrue);
      expect(saved.tags, ['Lavoro', 'Favorite']);

      saved.tags = ['Lavoro', 'favorite', 'FAVORITE', 'Archivio'];
      final modification = saved.times.modification;
      expect(isEntryFavorite(saved), isTrue);
      setEntryFavoriteEdit(saved.uuid, true)(reopened);
      expect(saved.tags, ['Lavoro', 'favorite', 'FAVORITE', 'Archivio']);
      expect(saved.times.modification, modification);

      setEntryFavoriteEdit(saved.uuid, false)(reopened);
      final unfavorited = findEntryByUuid(
        await _roundTrip(reopened),
        saved.uuid,
      )!;
      expect(isEntryFavorite(unfavorited), isFalse);
      expect(unfavorited.tags, ['Lavoro', 'Archivio']);
      expect(unfavorited.history, isEmpty);
    });
  }
}
