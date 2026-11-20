import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/export/export_view_model.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/fake_create_storage.dart';
import '../../helpers/test_database.dart';

class _ExportStorage extends FakeCreateStorage {
  _ExportStorage({super.cancel});

  final released = <FileRef>[];

  @override
  Future<void> release(FileRef ref) async => released.add(ref);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, File, KdbxDatabase)> open(
    _ExportStorage storage,
  ) async {
    final db = newTestDatabase();
    db.header.kdfSettings = const AesKdfSettings(rounds: 1000);
    addTestEntry(
      db,
      db.root,
      {EntryFields.title: 'voce', EntryFields.password: 'segreto'},
      protectedKeys: {EntryFields.password},
    );
    final (file, reopened) = await saveToTempFile(db);
    final container = await newTestContainer(
      file: file,
      database: reopened,
      overrides: [fileStorageProvider.overrideWithValue(storage)],
    );
    addTearDown(container.dispose);
    container.listen(exportDatabaseViewModelProvider, (_, _) {});
    return (container, file, reopened);
  }

  test(
    'copia KDBX cifrata con la stessa chiave, permesso rilasciato',
    () async {
      final storage = _ExportStorage();
      final (container, _, session) = await open(storage);

      final name = await container
          .read(exportDatabaseViewModelProvider.notifier)
          .export();

      expect(storage.suggestedName, 'prova-copia.kdbx');
      expect(name, 'prova-copia.kdbx');
      final copy = File('${storage.dir.path}/prova-copia.kdbx');
      final reopened = await KdbxDatabase.fromBytes(
        data: copy.readAsBytesSync(),
        credentials: testCredentials(),
      );
      final entry = reopened.root.allEntries.single;
      expect(entry.fields[EntryFields.password]?.text, 'segreto');
      // Il file è cifrato: il valore protetto non compare in chiaro.
      expect(
        String.fromCharCodes(copy.readAsBytesSync()).contains('segreto'),
        isFalse,
      );
      expect(storage.released.single.name, 'prova-copia.kdbx');
      // Il database aperto e il suo file non cambiano.
      expect(container.read(databaseSessionProvider)?.database, same(session));
    },
  );

  test(
    'scelta della posizione annullata: nessun file e nessun messaggio',
    () async {
      final storage = _ExportStorage(cancel: true);
      final (container, _, _) = await open(storage);

      final name = await container
          .read(exportDatabaseViewModelProvider.notifier)
          .export();

      expect(name, isNull);
      expect(container.read(exportDatabaseViewModelProvider).hasError, isFalse);
      expect(storage.dir.listSync(), isEmpty);
    },
  );

  test('exportFileName: nome del database con "-copia"', () {
    expect(exportFileName('keepass.kdbx'), 'keepass-copia.kdbx');
    expect(exportFileName('senza estensione'), 'senza estensione-copia.kdbx');
    expect(exportFileName(''), 'database-copia.kdbx');
  });
}
