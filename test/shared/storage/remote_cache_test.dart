import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/external_change.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/remote_cache.dart';
import 'package:keepass_mobile/shared/storage/sftp_client.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/memory_cache_documents.dart';
import '../../helpers/test_database.dart';

class RemoteBytes extends FileStorage {
  RemoteBytes(this.bytes);
  Uint8List bytes;
  bool online = true;
  bool failUpload = false;
  Object? readError;
  int writes = 0;

  @override
  Future<StoredFile> read(FileRef ref) async {
    if (readError case final error?) throw error;
    if (!online) throw const RemoteUnreachableException();
    return StoredFile(
      ref: ref,
      bytes: Uint8List.fromList(bytes),
      version: '"${fileHashOf(bytes)}"',
    );
  }

  @override
  Future<void> write(
    FileRef ref,
    Uint8List value, {
    String? expectedVersion,
  }) async {
    if (!online || failUpload) throw const RemoteUnreachableException();
    if (expectedVersion != null &&
        expectedVersion != '"${fileHashOf(bytes)}"') {
      throw const RemoteConflictException();
    }
    writes++;
    bytes = Uint8List.fromList(value);
  }
}

DatabaseEdit _add(String title) => (db) {
  db.createEntry(parent: db.root).fields[EntryFields.title] =
      KdbxTextField.fromText(text: title);
};

void main() {
  const file = FileRef(
    uri: 'https://example.test/demo.kdbx',
    name: 'demo.kdbx',
  );
  late MemoryCacheDocuments documents;
  late RemoteCacheStore cache;
  late RemoteBytes base;
  late CachedDatabaseStorage storage;
  late KdbxDatabase database;
  late Uint8List original;

  setUp(() async {
    documents = MemoryCacheDocuments();
    cache = RemoteCacheStore(documents: documents);
    database = newTestDatabase();
    original = Uint8List.fromList(await database.save());
    base = RemoteBytes(original);
    storage = CachedDatabaseStorage(base, cache);
    await cache.write(
      file,
      original,
      previous: null,
      baseHash: fileHashOf(original),
      pending: false,
    );
  });

  Future<KdbxDatabase> open(Uint8List bytes) =>
      KdbxDatabase.fromBytes(data: bytes, credentials: testCredentials());

  test('record cifrato, hash del riferimento e checksum verificato', () async {
    final record = await cache.read(file);
    expect(record!.bytes, original);
    expect(record.pending, isFalse);
    expect(documents.records.keys.single, hasLength(64));
    final raw = documents.records.values.single;
    expect(utf8.decode(raw, allowMalformed: true), isNot(contains('https://')));
    raw[raw.length - 1] ^= 1;
    await expectLater(
      cache.read(file),
      throwsA(isA<RemoteCacheUnavailableException>()),
    );
  });

  test('file chiave non è un KDBX: non viene persistito', () async {
    await expectLater(
      cache.write(
        file,
        Uint8List.fromList([1, 2, 3]),
        previous: await cache.read(file),
        baseHash: fileHashOf(original),
        pending: true,
      ),
      throwsA(isA<RemoteCacheUnavailableException>()),
    );
    expect((await cache.read(file))!.bytes, original);
  });

  test('offline apre la copia cifrata con avviso', () async {
    base.online = false;
    final read = await storage.readForUnlock(const PickedFile(ref: file));
    expect(read, isA<CachedDatabaseRead>());
    expect((read as CachedDatabaseRead).status.offline, isTrue);
    expect((await open(read.bytes)).meta.name, database.meta.name);
  });

  test('offline senza copia: errore senza inventare un database', () async {
    documents.records.clear();
    base.online = false;
    await expectLater(
      storage.readForUnlock(const PickedFile(ref: file)),
      throwsA(isA<RemoteUnreachableException>()),
    );
  });

  for (final error in [
    const RemoteAuthException(),
    const SshHostKeyChangedException(),
  ]) {
    test('errore ${error.runtimeType}: mai mascherato dalla cache', () async {
      base.readError = error;
      await expectLater(
        storage.readForUnlock(const PickedFile(ref: file)),
        throwsA(same(error)),
      );
    });
  }

  test(
    'salva offline, riapre dopo il blocco e carica al ritorno della rete',
    () async {
      final container = await newTestContainer(
        overrides: [
          fileStorageProvider.overrideWithValue(base),
          remoteCacheStoreProvider.overrideWithValue(cache),
        ],
      );
      final session = container.read(databaseSessionProvider.notifier);
      session.open(
        DatabaseSession(
          file: file,
          database: database,
          fileHash: fileHashOf(original),
        ),
      );
      base.online = false;
      await session.apply(_add('modifica locale sintetica'));
      expect(
        container.read(databaseSessionProvider)!.cacheStatus.pending,
        isTrue,
      );
      expect(base.bytes, original);
      final pending = (await cache.read(file))!;
      expect(pending.pending, isTrue);
      expect(pending.baseHash, fileHashOf(original));
      expect((await open(pending.bytes)).root.allEntries, hasLength(1));
      final read = await storage.readForUnlock(const PickedFile(ref: file));
      final reopened = await open(read.bytes);
      session.open(
        DatabaseSession(
          file: file,
          database: reopened,
          fileHash: fileHashOf(read.bytes),
          cacheStatus: (read as CachedDatabaseRead).status,
        ),
      );
      base.online = true;
      expect(await session.synchronize(), SyncResult.synchronized);
      expect((await cache.read(file))!.pending, isFalse);
      expect(
        (await open(base.bytes))
            .root
            .allEntries
            .first
            .fields[EntryFields.title]!
            .text,
        'modifica locale sintetica',
      );
    },
  );

  test('modifiche offline e remote entrambe conservate dopo merge', () async {
    final container = await newTestContainer(
      overrides: [
        fileStorageProvider.overrideWithValue(base),
        remoteCacheStoreProvider.overrideWithValue(cache),
      ],
    );
    final session = container.read(databaseSessionProvider.notifier);
    session.open(
      DatabaseSession(
        file: file,
        database: database,
        fileHash: fileHashOf(original),
      ),
    );
    base.online = false;
    await session.apply(_add('locale'));
    final external = await open(original);
    _add('remota')(external);
    base.bytes = Uint8List.fromList(await external.save());
    base.online = true;
    await session.synchronize();
    final titles = (await open(base.bytes)).root.allEntries
        .map((e) => e.fields[EntryFields.title]!.text);
    expect(titles, unorderedEquals(['locale', 'remota']));
  });

  test(
    'upload fallisce dopo staging: modifica durevole e stato pending',
    () async {
      final container = await newTestContainer(
        overrides: [
          fileStorageProvider.overrideWithValue(base),
          remoteCacheStoreProvider.overrideWithValue(cache),
        ],
      );
      final session = container.read(databaseSessionProvider.notifier);
      session.open(
        DatabaseSession(
          file: file,
          database: database,
          fileHash: fileHashOf(original),
        ),
      );
      base.failUpload = true;
      await session.apply(_add('non caricata'));
      final status = container.read(databaseSessionProvider)!.cacheStatus;
      expect(status.pending, isTrue);
      expect(status.error, isA<RemoteUnreachableException>());
      expect((await cache.read(file))!.pending, isTrue);
      expect(
        (await open((await cache.read(file))!.bytes)).root.allEntries,
        hasLength(1),
      );
      expect(base.bytes, original);
    },
  );

  test('CAS: un altro motore aggiorna la cache, nessun upload cieco', () async {
    final read = await storage.readForSave(file, fileHashOf(original));
    final before = (await cache.read(file))!;
    final other = await cache.write(
      file,
      original,
      previous: before,
      baseHash: before.baseHash,
      pending: true,
    );
    await expectLater(
      storage.writeAfterRead(file, original, read),
      throwsA(isA<RemoteCacheChangedException>()),
    );
    expect((await cache.read(file))!.token, other.token);
    expect(base.writes, 0);
  });

  test('cache disattivata non cancella le copie pending', () async {
    final before = (await cache.read(file))!;
    await cache.write(
      file,
      original,
      previous: before,
      baseHash: before.baseHash,
      pending: true,
    );
    final container = await newTestContainer(
      overrides: [
        fileStorageProvider.overrideWithValue(base),
        remoteCacheStoreProvider.overrideWithValue(cache),
      ],
    );
    await container
        .read(appSettingsProvider.notifier)
        .update(const AppSettings(cacheRemoteFiles: false));
    expect(container.read(databaseFileStorageProvider), same(base));
    expect((await cache.read(file))!.pending, isTrue);
  });
  test(
    'apertura locale esplicita non chiede credenziali né contatta il server',
    () async {
      base.readError = const RemoteAuthException();
      final read = await storage.readForUnlock(
        const PickedFile(ref: file),
        offlineOnly: true,
      );
      expect((read as CachedDatabaseRead).status.offline, isTrue);
      expect(read.bytes, original);
    },
  );

  test(
    'chiave remota diversa: conserva la modifica offline e non carica',
    () async {
      final container = await newTestContainer(
        overrides: [
          fileStorageProvider.overrideWithValue(base),
          remoteCacheStoreProvider.overrideWithValue(cache),
        ],
      );
      final session = container.read(databaseSessionProvider.notifier);
      session.open(
        DatabaseSession(
          file: file,
          database: database,
          fileHash: fileHashOf(original),
        ),
      );
      base.online = false;
      await session.apply(_add('locale'));
      final pendingBytes = (await cache.read(file))!.bytes;
      final external = await open(original);
      external.header.credentials = KdbxCredentials(
        password: ProtectedData.fromString('altra'),
      );
      base.bytes = Uint8List.fromList(await external.save());
      final remoteBytes = Uint8List.fromList(base.bytes);
      base.online = true;
      await expectLater(
        session.synchronize(),
        throwsA(isA<SyncKeyMismatchException>()),
      );
      expect((await cache.read(file))!.bytes, pendingBytes);
      expect((await cache.read(file))!.pending, isTrue);
      expect(base.bytes, remoteBytes);
      expect(base.writes, 0);
    },
  );

  test('cache non disponibile: online funziona, offline non dichiara un salvataggio riuscito', () async {
    final container = await newTestContainer(
      overrides: [
        fileStorageProvider.overrideWithValue(base),
        remoteCacheStoreProvider.overrideWithValue(cache),
      ],
    );
    final session = container.read(databaseSessionProvider.notifier);
    session.open(
      DatabaseSession(
        file: file,
        database: database,
        fileHash: fileHashOf(original),
      ),
    );
    documents.unavailable = true;
    await session.apply(_add('online'));
    expect(
      container.read(databaseSessionProvider)!.cacheStatus.available,
      isFalse,
    );
    expect(base.writes, 1);
    base.online = false;
    final before = container.read(databaseSessionProvider)!.database;
    await expectLater(
      session.apply(_add('non salvata')),
      throwsA(isA<RemoteCacheUnavailableException>()),
    );
    expect(container.read(databaseSessionProvider)!.database, same(before));
  });
}
