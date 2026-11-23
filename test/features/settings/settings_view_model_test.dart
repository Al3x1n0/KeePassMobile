import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/entry/entry_view_model.dart';
import 'package:keepass_mobile/features/recent_passwords/recent_passwords_view_model.dart';
import 'package:keepass_mobile/features/settings/settings_view_model.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/recent_passwords_store.dart';

import '../../helpers/fake_secure_storage.dart';
import '../../helpers/test_database.dart';

String _id(int value) => value.toRadixString(16).padLeft(32, '0');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const file = FileRef(uri: 'file:///first.kdbx', name: 'first.kdbx');
  const otherFile = FileRef(uri: 'file:///second.kdbx', name: 'second.kdbx');

  group('SettingsViewModel', () {
    test(
      'disattivare le password recenti conserva tutti gli archivi sicuri',
      () async {
        // given
        final platform = FakeSecureStorage.install();
        final store = RecentPasswordsStore();
        final firstKey = RecentPasswordsStore.databaseKey(file, _id(100));
        final secondKey = RecentPasswordsStore.databaseKey(otherFile, _id(100));
        await store.record(firstKey, _id(1));
        await store.record(secondKey, _id(2));
        final saved = Map<String, String>.of(platform.data);
        platform.options.clear();
        final container = await newTestContainer(
          overrides: [recentPasswordsStoreProvider.overrideWithValue(store)],
        );
        container.listen(settingsViewModelProvider, (_, _) {});

        // when
        await container
            .read(settingsViewModelProvider.notifier)
            .update(
              container
                  .read(settingsViewModelProvider)
                  .copyWith(showRecentPasswords: false),
            );

        // then
        expect(
          container.read(settingsViewModelProvider).showRecentPasswords,
          isFalse,
        );
        expect(platform.data, saved);
        expect(platform.options, isEmpty);

        await container
            .read(settingsViewModelProvider.notifier)
            .update(
              container
                  .read(settingsViewModelProvider)
                  .copyWith(showRecentPasswords: true),
            );
        expect(platform.data, saved);
        expect(platform.options, isEmpty);
        expect(await store.read(firstKey), [_id(1)]);
        expect(await store.read(secondKey), [_id(2)]);
      },
    );

    test(
      'le copie con opzione spenta non cambiano lo storico ripristinato',
      () async {
        // given
        final platform = FakeSecureStorage.install();
        final clipboard = FakeClipboard(
          TestDefaultBinaryMessengerBinding.instance,
        );
        final db = newTestDatabase();
        final previous = addTestEntry(db, db.root, {
          EntryFields.title: 'Precedente',
          EntryFields.password: 'password-precedente',
        });
        final copied = addTestEntry(db, db.root, {
          EntryFields.title: 'Nuova',
          EntryFields.password: 'password-nuova',
        });
        final previousId = itemIdOf(previous);
        final copiedId = itemIdOf(copied);
        final key = RecentPasswordsStore.databaseKey(file, itemIdOf(db.root));
        final otherKey = RecentPasswordsStore.databaseKey(otherFile, _id(100));
        final store = RecentPasswordsStore();
        await store.record(key, previousId);
        await store.record(otherKey, _id(2));
        final saved = Map<String, String>.of(platform.data);
        final container = await newTestContainer(
          overrides: [recentPasswordsStoreProvider.overrideWithValue(store)],
        );
        container
            .read(databaseSessionProvider.notifier)
            .open(
              DatabaseSession(
                file: file,
                database: db,
                recentPasswordIds: [previousId],
              ),
            );
        container.listen(settingsViewModelProvider, (_, _) {});
        container.listen(recentPasswordEntriesProvider, (_, _) {});
        container.listen(entryActionsProvider(copiedId), (_, _) {});
        expect(container.read(recentPasswordEntriesProvider).map(itemIdOf), [
          previousId,
        ]);

        // when
        await container
            .read(settingsViewModelProvider.notifier)
            .update(
              container
                  .read(settingsViewModelProvider)
                  .copyWith(showRecentPasswords: false),
            );
        expect(container.read(recentPasswordEntriesProvider), isEmpty);
        await container
            .read(entryActionsProvider(copiedId).notifier)
            .copy(EntryFields.password);

        // then: gli appunti funzionano, la cronologia rimane identica.
        expect(clipboard.text, 'password-nuova');
        expect(await store.read(key), [previousId]);
        expect(container.read(databaseSessionProvider)!.recentPasswordIds, [
          previousId,
        ]);
        expect(platform.data, saved);
        await container
            .read(settingsViewModelProvider.notifier)
            .update(
              container
                  .read(settingsViewModelProvider)
                  .copyWith(showRecentPasswords: true),
            );
        expect(container.read(recentPasswordEntriesProvider).map(itemIdOf), [
          previousId,
        ]);

        await container
            .read(entryActionsProvider(copiedId).notifier)
            .copy(EntryFields.password);
        expect(container.read(recentPasswordEntriesProvider).map(itemIdOf), [
          copiedId,
          previousId,
        ]);
        expect(await store.read(key), [copiedId, previousId]);
        expect(await store.read(otherKey), [_id(2)]);
      },
    );
  });
}
