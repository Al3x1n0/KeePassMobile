import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/database_settings/change_master_key_view_model.dart';
import 'package:keepass_mobile/features/entry/entry_view_model.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'nuova password: il file si apre con la nuova, la vecchia è rifiutata',
    () async {
      // given
      final db = newTestDatabase();
      db.header.kdfSettings = const AesKdfSettings(rounds: 1000);
      addTestEntry(db, db.root, {EntryFields.title: 'voce'});
      db.meta.keyChanged = KdbxTime(DateTime.utc(2020));
      final (file, reopened) = await saveToTempFile(db);
      final container = await newTestContainer(file: file, database: reopened);
      addTearDown(container.dispose);
      container.listen(changeMasterKeyViewModelProvider, (_, _) {});

      // when
      final changed = await container
          .read(changeMasterKeyViewModelProvider.notifier)
          .change(password: 'nuova');

      // then
      expect(changed, isTrue);
      final bytes = bytesOf(file);
      final withNew = await openDatabase(data: bytes, password: 'nuova');
      expect(withNew.root.allEntries.single.fields['Title']?.text, 'voce');
      // SetPassword.cs: MasterKeyChanged = adesso.
      expect(
        withNew.meta.keyChanged.isAfter(KdbxTime(DateTime.utc(2021))),
        isTrue,
      );
      await expectLater(
        openDatabase(data: bytes, password: testMasterKey),
        throwsA(isA<InvalidCredentialsError>()),
      );
    },
  );

  test('dopo il cambio le modifiche si salvano con la nuova chiave', () async {
    final db = newTestDatabase();
    db.header.kdfSettings = const AesKdfSettings(rounds: 1000);
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'voce'});
    final (file, reopened) = await saveToTempFile(db);
    final container = await newTestContainer(file: file, database: reopened);
    addTearDown(container.dispose);
    container.listen(changeMasterKeyViewModelProvider, (_, _) {});
    await container
        .read(changeMasterKeyViewModelProvider.notifier)
        .change(password: 'nuova');

    await container
        .read(databaseSessionProvider.notifier)
        .apply(deleteEntryEdit(entry.uuid));

    final again = await openDatabase(data: bytesOf(file), password: 'nuova');
    // Il cestino è attivo: la voce non è più nel gruppo radice.
    expect(again.root.entries, isEmpty);
  });

  test('nuovo file chiave: sessione e file recenti lo usano', () async {
    final db = newTestDatabase();
    db.header.kdfSettings = const AesKdfSettings(rounds: 1000);
    final (file, reopened) = await saveToTempFile(db);
    final container = await newTestContainer(file: file, database: reopened);
    addTearDown(container.dispose);
    container.listen(changeMasterKeyViewModelProvider, (_, _) {});
    await container
        .read(recentFilesRepositoryProvider)
        .remember(RecentFile(database: fileRefOf(file)));
    final key = Uint8List.fromList(List.generate(64, (i) => 255 - i));
    const keyRef = FileRef(uri: 'content://docs/nuova.key', name: 'nuova.key');

    await container
        .read(changeMasterKeyViewModelProvider.notifier)
        .change(
          password: '',
          keyFile: PickedFile(ref: keyRef, bytes: key),
        );

    expect(container.read(databaseSessionProvider)?.keyFile, keyRef);
    expect(
      container.read(recentFilesRepositoryProvider).load().single.keyFile,
      keyRef,
    );
    final withKey = await openDatabase(
      data: bytesOf(file),
      password: '',
      keyFile: key,
    );
    expect(withKey.meta.name, 'Prova');
  });
}
