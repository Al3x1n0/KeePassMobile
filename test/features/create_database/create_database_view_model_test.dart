import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/create_database/create_database_view_model.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/key_file.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/fake_create_storage.dart';
import '../../helpers/test_database.dart';

void main() {
  // Il canale degli appunti si usa al blocco.
  TestWidgetsFlutterBinding.ensureInitialized();
  const fastKdf = AesKdfSettings(rounds: 1000);

  Future<ProviderContainer> container(FileStorage storage) async {
    final container = await newTestContainer(
      overrides: [
        fileStorageProvider.overrideWithValue(storage),
        newDatabaseKdfProvider.overrideWithValue(fastKdf),
      ],
    );
    container.listen(createDatabaseViewModelProvider, (_, _) {});
    return container;
  }

  File fileOf(FakeCreateStorage storage) =>
      File('${storage.dir.path}/$suggestedDatabaseFileName');

  test(
    'crea il database come Keepass2Android, apre la sessione e ricorda il file',
    () async {
      final storage = FakeCreateStorage();
      final c = await container(storage);

      await c
          .read(createDatabaseViewModelProvider.notifier)
          .create(password: 'nuova');

      expect(c.read(createDatabaseViewModelProvider), isA<AsyncData<void>>());
      expect(storage.suggestedName, 'keepass.kdbx');
      final session = c.read(databaseSessionProvider);
      expect(session, isNotNull);
      // CreateDB.cs: radice con il nome del file, Internet ed eMail (D2).
      final db = await KdbxDatabase.fromBytes(
        data: fileOf(storage).readAsBytesSync(),
        credentials: KdbxCredentials(
          password: ProtectedData.fromString('nuova'),
        ),
      );
      expect(db.root.name, 'keepass');
      expect(db.meta.name, newDatabaseName);
      expect(
        db.root.groups.map((g) => (g.name, g.icon)),
        containsAll([('Internet', KdbxIcon.world), ('eMail', KdbxIcon.eMail)]),
      );
      expect(db.root.allEntries, isEmpty);
      expect(db.header.version.$1, 4);
      expect(db.header.dataCipherUuid?.string, CipherId.aes);
      final recent = c.read(recentFilesRepositoryProvider).load().single;
      expect(recent.database, session?.file);
    },
  );

  test(
    'scelta della posizione annullata: nessuna sessione e nessun file',
    () async {
      final storage = FakeCreateStorage(cancel: true);
      final c = await container(storage);

      await c
          .read(createDatabaseViewModelProvider.notifier)
          .create(password: 'nuova');

      expect(c.read(createDatabaseViewModelProvider), isA<AsyncData<void>>());
      expect(c.read(databaseSessionProvider), isNull);
      expect(c.read(recentFilesRepositoryProvider).load(), isEmpty);
      expect(fileOf(storage).existsSync(), isFalse);
    },
  );

  test(
    'file chiave XML generato: riapertura con il materiale salvato',
    () async {
      final storage = FakeCreateStorage();
      addTearDown(() => storage.dir.deleteSync(recursive: true));
      final c = await container(storage);
      final picked = (await createKeyFile(storage))!;
      final saved = (await storage.read(picked.ref)).bytes;
      final data = RegExp(r'<Data>([^<]+)</Data>')
          .firstMatch(utf8.decode(saved))!;
      final raw = base64.decode(data.group(1)!);
      expect(raw, hasLength(32));
      await c
          .read(createDatabaseViewModelProvider.notifier)
          .create(password: '', keyFile: picked);
      final reopened = await openDatabase(
        data: fileOf(storage).readAsBytesSync(),
        password: '',
        keyFile: raw,
      );
      expect(reopened.root.name, 'keepass');
    },
  );

  test('generazione annullata: nessun file selezionato', () async {
    final storage = FakeCreateStorage(cancel: true);
    addTearDown(() => storage.dir.deleteSync(recursive: true));
    expect(await createKeyFile(storage), isNull);
    expect(storage.dir.listSync(), isEmpty);
  });

  test(
    'solo file chiave: si riapre con il file chiave e senza password',
    () async {
      final storage = FakeCreateStorage();
      final c = await container(storage);
      final key = Uint8List.fromList(List.generate(64, (i) => i));
      const keyRef = FileRef(uri: 'content://docs/k.key', name: 'k.key');

      await c
          .read(createDatabaseViewModelProvider.notifier)
          .create(
            password: '',
            keyFile: PickedFile(ref: keyRef, bytes: key),
          );

      final bytes = fileOf(storage).readAsBytesSync();
      final reopened = await openDatabase(
        data: bytes,
        password: '',
        keyFile: key,
      );
      expect(reopened.root.name, 'keepass');
      expect(c.read(databaseSessionProvider)?.keyFile, keyRef);
      expect(
        c.read(recentFilesRepositoryProvider).load().single.keyFile,
        keyRef,
      );
    },
  );

  test(
    'KDF dei database nuovi (D1): Argon2id 64 MiB, 2 iterazioni, 2 thread',
    () async {
      final (db, bytes) = await buildNewDatabase(
        password: 'nuova',
        rootName: 'r',
      );

      expect(
        db.header.kdfSettings,
        const Argon2KdfSettings(
          id: true,
          memory: 64 * 1024 * 1024,
          iterations: 2,
          parallelism: 2,
        ),
      );
      // Il file si riapre con la chiave appena derivata.
      await verifyWrittenDatabase(bytes, db);
    },
  );

  test('rootGroupName: il nome del file senza estensione', () {
    expect(rootGroupName('keepass.kdbx'), 'keepass');
    expect(rootGroupName('archivio.v2.kdbx'), 'archivio.v2');
    expect(rootGroupName('.kdbx'), '.kdbx');
    expect(rootGroupName(''), 'KeePassMobile');
  });
}
