import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'passa fra database aperti, salva sul file attivo e blocca tutti',
    () async {
      final first = newTestDatabase();
      final second = newTestDatabase();
      addTestEntry(first, first.root, {EntryFields.title: 'Primo'});
      addTestEntry(second, second.root, {EntryFields.title: 'Secondo'});
      final (firstFile, firstDb) = await saveToTempFile(first);
      final (secondFile, secondDb) = await saveToTempFile(second);
      addTearDown(() {
        firstFile.parent.deleteSync(recursive: true);
        secondFile.parent.deleteSync(recursive: true);
      });
      final container = await newTestContainer(
        file: firstFile,
        database: firstDb,
      );
      final sessions = container.read(databaseSessionProvider.notifier);
      final generation = sessions.lockGeneration;
      sessions.openAdditional(
        DatabaseSession(file: fileRefOf(secondFile), database: secondDb),
        generation,
      );
      expect(sessions.openSessions, hasLength(2));
      sessions.switchTo(fileRefOf(firstFile));
      await sessions.apply((db) => db.root.name = 'Primo modificato');
      expect((await reopenFile(firstFile)).root.name, 'Primo modificato');
      expect((await reopenFile(secondFile)).root.name, 'Prova');
      expect(
        sessions.closeSession(fileRefOf(firstFile)).file,
        fileRefOf(firstFile),
      );
      expect(
        container.read(databaseSessionProvider)!.file,
        fileRefOf(secondFile),
      );
      expect(sessions.openSessions, hasLength(1));
      sessions.lock();
      expect(container.read(databaseSessionProvider), isNull);
      expect(sessions.openSessions, isEmpty);
      expect(
        () => sessions.openAdditional(
          DatabaseSession(file: fileRefOf(secondFile), database: secondDb),
          generation,
        ),
        throwsA(isA<DatabaseLockedException>()),
      );
    },
  );
}
