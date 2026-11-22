import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/database/database_session.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/storage/recent_passwords_store.dart';

/// Chiave della cronologia del database attivo con l'opzione abilitata.
final recentPasswordDatabaseKeyProvider = Provider.autoDispose<String?>((ref) {
  if (!ref.watch(appSettingsProvider.select((s) => s.showRecentPasswords))) {
    return null;
  }
  final session = ref.watch(databaseSessionProvider);
  if (session == null) return null;
  return RecentPasswordsStore.databaseKey(
    session.file,
    idOfUuid(session.database.root.uuid),
  );
});

final recentPasswordIdsProvider = FutureProvider.autoDispose
    .family<List<String>, String>(
      (ref, key) => ref.watch(recentPasswordsStoreProvider).read(key),
    );

/// Voci recenti del database attivo, entro il limite scelto dall'utente.
final recentPasswordEntriesProvider = Provider.autoDispose<List<KdbxEntry>>((
  ref,
) {
  final key = ref.watch(recentPasswordDatabaseKeyProvider);
  if (key == null) return const [];
  final database = ref.watch(databaseSessionProvider)?.database;
  if (database == null) return const [];

  final ids = ref.watch(recentPasswordIdsProvider(key)).value;
  if (ids == null || ids.isEmpty) return const [];
  final limit = ref.watch(
    appSettingsProvider.select((s) => s.recentPasswordLimit),
  );
  final entriesById = {
    for (final entry in database.root.allEntries) itemIdOf(entry): entry,
  };
  return List.unmodifiable(
    ids
        .map((id) => entriesById[id])
        .whereType<KdbxEntry>()
        .where((entry) => !isInRecycleBin(database, entry))
        .take(limit),
  );
});
