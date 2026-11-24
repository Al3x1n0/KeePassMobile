import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/password_generator/password_generator.dart';
import 'package:keepass_mobile/features/password_generator/pending_generated_password.dart';
import 'package:keepass_mobile/features/unlock/relock.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const file = FileRef(uri: 'content://test/generated', name: 'test.kdbx');
  const other = FileRef(uri: 'content://test/other', name: 'other.kdbx');
  const generated = 'Sintetica-Generata-42';

  Future<ProviderContainer> start() async {
    final container = await newTestContainer();
    container
        .read(databaseSessionProvider.notifier)
        .open(DatabaseSession(file: file, database: newTestDatabase()));
    container
        .read(pendingGeneratedPasswordProvider.notifier)
        .replace(file, defaultGeneratorOptions, generated);
    return container;
  }

  test(
    'generata associata a FileRef e solo RAM, mai nelle preferenze',
    () async {
      final container = await start();
      addTearDown(container.dispose);
      final pending = container.read(pendingGeneratedPasswordProvider.notifier);

      expect(pending.valueFor(file)?.text, generated);
      expect(pending.valueFor(other), isNull);
      expect(container.read(sharedPreferencesProvider).getKeys(), isEmpty);
    },
  );

  test('blocco automatico conserva solo generata e ripristino consumabile una volta', () async {
    final container = await start();
    addTearDown(container.dispose);
    final database = container.read(databaseSessionProvider)!.database;
    final credentialHash = database.header.credentials.hash;
    final pending = container.read(pendingGeneratedPasswordProvider.notifier);

    container.read(relockProvider.notifier).lockAndReturn(automatic: true);

    expect(container.read(databaseSessionProvider), isNull);
    expect(database.root.allEntries, isEmpty);
    expect(database.header.credentials.hash, isNot(credentialHash));
    expect(pending.valueFor(file)?.text, generated);
    expect(pending.takeRestoreDestination(other), isFalse);
    container
        .read(databaseSessionProvider.notifier)
        .open(DatabaseSession(file: file, database: newTestDatabase()));
    expect(pending.takeRestoreDestination(file), isTrue);
    expect(pending.takeRestoreDestination(file), isFalse);
    expect(pending.valueFor(file)?.text, generated);
  });

  test(
    'blocco manuale azzera il buffer anche dopo uno sblocco automatico',
    () async {
      final container = await start();
      addTearDown(container.dispose);
      final pending = container.read(pendingGeneratedPasswordProvider.notifier);
      final protected = pending.valueFor(file)!;
      container.read(relockProvider.notifier).lockAndReturn(automatic: true);
      container
          .read(databaseSessionProvider.notifier)
          .open(DatabaseSession(file: file, database: newTestDatabase()));

      container.read(relockProvider.notifier).lockAndReturn();

      expect(container.read(pendingGeneratedPasswordProvider), isNull);
      expect(protected.bytes.every((byte) => byte == 0), isTrue);
    },
  );

  test(
    'chiusura diretta non riutilizza la precedente autorizzazione automatica',
    () async {
      final container = await start();
      addTearDown(container.dispose);
      container.read(relockProvider.notifier).lockAndReturn(automatic: true);
      container
          .read(databaseSessionProvider.notifier)
          .open(DatabaseSession(file: file, database: newTestDatabase()));

      container.read(databaseSessionProvider.notifier).lock();

      expect(container.read(pendingGeneratedPasswordProvider), isNull);
    },
  );

  test(
    'salvataggio effettivo azzera il buffer, sostituzione azzera il precedente',
    () async {
      final container = await start();
      addTearDown(container.dispose);
      final pending = container.read(pendingGeneratedPasswordProvider.notifier);
      final previous = pending.valueFor(file)!;
      pending.replace(file, defaultGeneratorOptions, 'Altra-sintetica-7');
      final current = pending.valueFor(file)!;
      expect(previous.bytes.every((byte) => byte == 0), isTrue);

      pending.clear();

      expect(container.read(pendingGeneratedPasswordProvider), isNull);
      expect(current.bytes.every((byte) => byte == 0), isTrue);
    },
  );

  test(
    'sblocco di altro database cancella la password sospesa e il rientro',
    () async {
      final container = await start();
      addTearDown(container.dispose);
      final pending = container.read(pendingGeneratedPasswordProvider.notifier);
      final protected = pending.valueFor(file)!;
      container.read(relockProvider.notifier).lockAndReturn(automatic: true);

      container
          .read(databaseSessionProvider.notifier)
          .open(DatabaseSession(file: other, database: newTestDatabase()));

      expect(container.read(pendingGeneratedPasswordProvider), isNull);
      expect(pending.takeRestoreDestination(file), isFalse);
      expect(protected.bytes.every((byte) => byte == 0), isTrue);
    },
  );

  test(
    'cambio database aperto e chiusura volontaria non mantengono la generata',
    () async {
      final container = await start();
      addTearDown(container.dispose);
      final sessions = container.read(databaseSessionProvider.notifier);
      sessions.openAdditional(
        DatabaseSession(file: other, database: newTestDatabase()),
        sessions.lockGeneration,
      );
      expect(container.read(pendingGeneratedPasswordProvider), isNull);
      sessions.switchTo(file);
      container
          .read(pendingGeneratedPasswordProvider.notifier)
          .replace(file, defaultGeneratorOptions, generated);

      sessions.closeSession(file);

      expect(container.read(pendingGeneratedPasswordProvider), isNull);
    },
  );

  test(
    'valore non valido o database non attivo non viene trattenuto',
    () async {
      final container = await start();
      addTearDown(container.dispose);
      final pending = container.read(pendingGeneratedPasswordProvider.notifier);
      pending.replace(other, defaultGeneratorOptions, generated);
      expect(container.read(pendingGeneratedPasswordProvider), isNull);
      pending.replace(file, defaultGeneratorOptions, '');
      expect(container.read(pendingGeneratedPasswordProvider), isNull);
    },
  );

  test(
    'fine processo azzera il buffer e un nuovo container non ripristina nulla',
    () async {
      final container = await start();
      final protected = container
          .read(pendingGeneratedPasswordProvider)!
          .protectedValue;

      container.dispose();
      final next = await newTestContainer();
      addTearDown(next.dispose);

      expect(protected.bytes.every((byte) => byte == 0), isTrue);
      expect(next.read(pendingGeneratedPasswordProvider), isNull);
    },
  );
}
