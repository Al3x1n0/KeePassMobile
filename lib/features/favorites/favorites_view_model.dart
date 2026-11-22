import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/database/database_session.dart';
import '../../shared/database/field_references.dart';
import '../../shared/database/item_edits.dart';
import '../../shared/database/kdbx_items.dart';

const _favoriteTag = 'Favorite';

bool _isFavoriteTag(String tag) =>
    tag.toLowerCase() == _favoriteTag.toLowerCase();

bool isEntryFavorite(KdbxEntry entry) =>
    entry.tags?.any(_isFavoriteTag) ?? false;

/// Imposta il tag dei preferiti preservando gli altri tag della voce.
DatabaseEdit setEntryFavoriteEdit(KdbxUuid uuid, bool favorite) => (database) {
  final entry = findEntryByUuid(database, uuid);
  if (entry == null || isInRecycleBin(database, entry)) {
    throw const InvalidItemEditException();
  }
  if (isEntryFavorite(entry) == favorite) return;
  final tags = entry.tags ?? const <String>[];
  entry.tags = favorite
      ? [...tags, _favoriteTag]
      : tags.where((tag) => !_isFavoriteTag(tag)).toList();
  entry.times.modification = KdbxTime.now();
};

/// Preferiti del database attivo, oppure `null` a database chiuso.
final favoriteEntriesProvider = Provider.autoDispose<List<KdbxEntry>?>((ref) {
  final database = ref.watch(databaseSessionProvider)?.database;
  if (database == null) return null;

  final entries = [
    for (final entry in database.root.allEntries)
      if (isEntryFavorite(entry) && !isInRecycleBin(database, entry))
        (entry: entry, title: visibleEntryTitle(database, entry).toLowerCase()),
  ]..sort((a, b) => a.title.compareTo(b.title));
  return List.unmodifiable(entries.map((item) => item.entry));
});
