import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keepass_mobile/features/group/group_view_model.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('conserva l’ordinamento scelto e gestisce valori sconosciuti', () async {
    SharedPreferences.setMockInitialValues({'group.sort_order': 'unknown'});
    final prefs = await SharedPreferences.getInstance();
    ProviderContainer container() => ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    final first = container();
    expect(first.read(groupSortOrderProvider), GroupSortOrder.ascending);
    for (final order in GroupSortOrder.values) {
      await first.read(groupSortOrderProvider.notifier).select(order);
      final reopened = container();
      expect(reopened.read(groupSortOrderProvider), order);
      reopened.dispose();
    }
    first.dispose();
  });

  test(
    'ordina gruppi e voci per modifica e creazione senza alterare il database',
    () async {
      final db = newTestDatabase();
      for (final (name, created, modified) in [
        ('A', 2021, 2022),
        ('B', 2020, 2023),
        ('C', 2022, 2024),
      ]) {
        final group = db.createGroup(parent: db.root, name: name);
        final entry = addTestEntry(db, db.root, {EntryFields.title: name});
        for (final times in [group.times, entry.times]) {
          times.creation = KdbxTime(DateTime.utc(created));
          times.modification = KdbxTime(DateTime.utc(modified));
        }
      }
      final (file, reopened) = await saveToTempFile(db);
      addTearDown(() => file.parent.deleteSync(recursive: true));
      final container = await newTestContainer(file: file, database: reopened);
      final subscription = container.listen(
        groupContentProvider(null),
        (_, _) {},
      );
      addTearDown(subscription.close);
      void expectOrder(List<String> expected) {
        final content = subscription.read()!;
        expect(
          content.groups
              .where((group) => group != content.recycleBin)
              .map((group) => group.name),
          expected,
        );
        expect(subscription.read()!.entries.map(entryTitle), expected);
      }

      container
          .read(groupSortOrderProvider.notifier)
          .select(GroupSortOrder.modification);
      expectOrder(['C', 'B', 'A']);
      container
          .read(groupSortOrderProvider.notifier)
          .select(GroupSortOrder.creation);
      expectOrder(['B', 'A', 'C']);
      container
          .read(groupSortOrderProvider.notifier)
          .select(GroupSortOrder.database);
      expectOrder(['A', 'B', 'C']);
    },
  );

  test(
    'ordina gli indici TAN senza modificare l’ordine nel database',
    () async {
      final db = newTestDatabase();
      for (final index in ['10', '2', 'beta', 'Alpha', '1']) {
        addTestEntry(db, db.root, {
          EntryFields.title: '<TAN>',
          EntryFields.userName: index,
        });
      }
      final (file, reopened) = await saveToTempFile(db);
      addTearDown(() => file.parent.deleteSync(recursive: true));
      final container = await newTestContainer(file: file, database: reopened);
      final subscription = container.listen(
        groupContentProvider(null),
        (_, _) {},
      );
      addTearDown(subscription.close);
      List<String> indices() =>
          subscription.read()!.entries.map(entryUserName).toList();

      expect(indices(), ['1', '2', '10', 'Alpha', 'beta']);
      container
          .read(groupSortOrderProvider.notifier)
          .select(GroupSortOrder.descending);
      expect(indices(), ['beta', 'Alpha', '10', '2', '1']);
      container
          .read(groupSortOrderProvider.notifier)
          .select(GroupSortOrder.database);
      expect(indices(), ['10', '2', 'beta', 'Alpha', '1']);
    },
  );
}
