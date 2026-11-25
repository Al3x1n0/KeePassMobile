import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/features/unlock/relock.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const file = FileRef(uri: 'content://test/resume-tab', name: 'test.kdbx');
  const other = FileRef(uri: 'content://test/other-tab', name: 'other.kdbx');

  for (final tab in [
    AppRoutes.database,
    AppRoutes.appSettingsInDatabase,
    AppRoutes.generate,
    AppRoutes.check,
  ]) {
    test(
      'blocco automatico: ripristina $tab una sola volta, senza password',
      () async {
        final container = await newTestContainer();
        final sessions = container.read(databaseSessionProvider.notifier);
        sessions.open(DatabaseSession(file: file, database: newTestDatabase()));
        final relock = container.read(relockProvider.notifier);
        relock.rememberTab(tab);

        relock.lockAndReturn(automatic: true);
        sessions.open(DatabaseSession(file: file, database: newTestDatabase()));

        expect(relock.takeRestoreDestination(file), tab);
        expect(relock.takeRestoreDestination(file), isNull);
        expect(container.read(sharedPreferencesProvider).getKeys(), isEmpty);
      },
    );
  }

  test(
    'destinazione limitata alle tab, senza riferimenti a voci o gruppi',
    () async {
      final container = await newTestContainer();
      final sessions = container.read(databaseSessionProvider.notifier);
      sessions.open(DatabaseSession(file: file, database: newTestDatabase()));
      final relock = container.read(relockProvider.notifier);
      relock.rememberTab(AppRoutes.appSettingsInDatabase);
      relock.rememberTab(AppRoutes.newEntry('gruppo-sintetico'));

      relock.lockAndReturn(automatic: true);
      sessions.open(DatabaseSession(file: file, database: newTestDatabase()));

      expect(
        relock.takeRestoreDestination(file),
        AppRoutes.appSettingsInDatabase,
      );
    },
  );

  test('un altro database elimina la tab di ripresa precedente', () async {
    final container = await newTestContainer();
    final sessions = container.read(databaseSessionProvider.notifier);
    sessions.open(DatabaseSession(file: file, database: newTestDatabase()));
    final relock = container.read(relockProvider.notifier);
    relock.rememberTab(AppRoutes.appSettingsInDatabase);
    relock.lockAndReturn(automatic: true);

    sessions.open(DatabaseSession(file: other, database: newTestDatabase()));

    expect(relock.takeRestoreDestination(other), isNull);
    sessions.open(DatabaseSession(file: file, database: newTestDatabase()));
    expect(relock.takeRestoreDestination(file), isNull);
  });

  test(
    'blocco manuale elimina anche una precedente ripresa automatica',
    () async {
      final container = await newTestContainer();
      final sessions = container.read(databaseSessionProvider.notifier);
      sessions.open(DatabaseSession(file: file, database: newTestDatabase()));
      final relock = container.read(relockProvider.notifier);
      relock.rememberTab(AppRoutes.generate);
      relock.lockAndReturn(automatic: true);
      sessions.open(DatabaseSession(file: file, database: newTestDatabase()));

      relock.rememberTab(AppRoutes.appSettingsInDatabase);
      relock.lockAndReturn();
      sessions.open(DatabaseSession(file: file, database: newTestDatabase()));

      expect(relock.takeRestoreDestination(file), isNull);
    },
  );

  test(
    'chiusura diretta non riutilizza una precedente ripresa automatica',
    () async {
      final container = await newTestContainer();
      final sessions = container.read(databaseSessionProvider.notifier);
      sessions.open(DatabaseSession(file: file, database: newTestDatabase()));
      final relock = container.read(relockProvider.notifier);
      relock.rememberTab(AppRoutes.generate);
      relock.lockAndReturn(automatic: true);
      sessions.open(DatabaseSession(file: file, database: newTestDatabase()));

      sessions.lock();
      sessions.open(DatabaseSession(file: file, database: newTestDatabase()));

      expect(relock.takeRestoreDestination(file), isNull);
    },
  );
}
