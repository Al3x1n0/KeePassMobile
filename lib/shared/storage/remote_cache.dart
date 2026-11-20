import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:document_access/document_access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/app_settings.dart';
import 'file_storage.dart';
import 'remote_storage.dart';
import 'webdav_client.dart';

/// Cache non disponibile o record incompleto: non è una copia utilizzabile.
final class RemoteCacheUnavailableException implements Exception {
  const RemoteCacheUnavailableException();
}

/// Un altro motore ha aggiornato la copia locale dopo la lettura.
final class RemoteCacheChangedException implements Exception {
  const RemoteCacheChangedException();
}

/// Stato visibile della copia cifrata, senza contenuto del database.
class RemoteCacheStatus {
  const RemoteCacheStatus({
    this.offline = false,
    this.pending = false,
    this.available = true,
    this.error,
    this.synchronizing = false,
  });
  final bool offline;
  final bool pending;
  final bool available;
  final Object? error;
  final bool synchronizing;

  RemoteCacheStatus duringSync() => RemoteCacheStatus(
    offline: offline,
    pending: pending,
    available: available,
    synchronizing: true,
  );

  RemoteCacheStatus withError(Object error) => RemoteCacheStatus(
    offline: offline,
    pending: pending,
    available: available,
    error: error,
  );
}

/// Unico record atomico: versione remota di base e ultima copia cifrata.
class RemoteCacheRecord {
  const RemoteCacheRecord({
    required this.token,
    required this.bytes,
    required this.baseHash,
    required this.pending,
  });
  final Uint8List token;
  final Uint8List bytes;
  final String baseHash;
  final bool pending;
}

String _hash(Uint8List bytes) => sha256.convert(bytes).toString();

/// Cache privata esclusa dai backup; il canale nativo riceve solo hash e
/// contenuto cifrato. Token CAS e file atomico proteggono gli aggiornamenti
/// fra motori Flutter e i riavvii nel mezzo di una scrittura (ADR-017).
class RemoteCacheStore {
  const RemoteCacheStore({this.documents = const DocumentAccess()});
  final DocumentAccess documents;

  static String idOf(FileRef file) =>
      sha256.convert(utf8.encode(file.uri)).toString();

  Future<RemoteCacheRecord?> read(FileRef file) async {
    try {
      final raw = await documents.readRemoteCache(idOf(file));
      if (raw == null) return null;
      if (raw.length < 36) throw const RemoteCacheUnavailableException();
      final length = ByteData.sublistView(raw).getUint32(32);
      if (length > 1024 || raw.length < 36 + length) {
        throw const RemoteCacheUnavailableException();
      }
      final meta = jsonDecode(utf8.decode(raw.sublist(36, 36 + length)));
      final bytes = Uint8List.sublistView(raw, 36 + length);
      if (meta
          case {
            'v': 1,
            'base': final String base,
            'pending': final bool pending,
            'hash': final String hash,
          }
          when RegExp(r'^[a-f0-9]{64}$').hasMatch(base) &&
              hash == _hash(bytes)) {
        _checkKdbx(bytes);
        return RemoteCacheRecord(
          token: Uint8List.sublistView(raw, 0, 32),
          bytes: bytes,
          baseHash: base,
          pending: pending,
        );
      }
      throw const RemoteCacheUnavailableException();
    } on DocumentAccessException {
      throw const RemoteCacheUnavailableException();
    } on DocumentUnavailableException {
      throw const RemoteCacheUnavailableException();
    } on FormatException {
      throw const RemoteCacheUnavailableException();
    }
  }

  /// Solo byte KDBX già validati all'apertura o dopo la serializzazione.
  Future<RemoteCacheRecord> write(
    FileRef file,
    Uint8List bytes, {
    required RemoteCacheRecord? previous,
    required String baseHash,
    required bool pending,
  }) async {
    _checkKdbx(bytes);
    final random = Random.secure();
    final token = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    final metadata = utf8.encode(
      jsonEncode({
        'v': 1,
        'base': baseHash,
        'pending': pending,
        'hash': _hash(bytes),
      }),
    );
    final raw = Uint8List(36 + metadata.length + bytes.length);
    raw.setAll(0, token);
    ByteData.sublistView(raw).setUint32(32, metadata.length);
    raw.setAll(36, metadata);
    raw.setAll(36 + metadata.length, bytes);
    try {
      if (!await documents.writeRemoteCache(
        idOf(file),
        raw,
        expectedToken: previous?.token,
      )) {
        throw const RemoteCacheChangedException();
      }
      return RemoteCacheRecord(
        token: token,
        bytes: bytes,
        baseHash: baseHash,
        pending: pending,
      );
    } on DocumentAccessException {
      throw const RemoteCacheUnavailableException();
    } on DocumentUnavailableException {
      throw const RemoteCacheUnavailableException();
    }
  }

  static void _checkKdbx(Uint8List bytes) {
    if (bytes.length < 12 ||
        bytes.length > WebDavClient.maxBytes ||
        ByteData.sublistView(bytes).getUint32(0, Endian.little) != 0x9AA2D903 ||
        ByteData.sublistView(bytes).getUint32(4, Endian.little) != 0xB54BFB67) {
      throw const RemoteCacheUnavailableException();
    }
  }
}

/// La lettura locale e quella remota restano distinte: un ETag non deve
/// riferirsi accidentalmente a byte diversi dalla risposta del server.
class CachedDatabaseRead extends StoredFile {
  const CachedDatabaseRead({
    required super.ref,
    required super.bytes,
    required this.record,
    required this.remote,
    required this.status,
  });
  final RemoteCacheRecord? record;
  final StoredFile? remote;
  final RemoteCacheStatus status;
}

/// Cache riservata ai database. I file chiave continuano a usare FileStorage
/// direttamente, senza questo decoratore (SEC-02/03, ADR-017).
class CachedDatabaseStorage extends FileStorage {
  const CachedDatabaseStorage(this.base, this.cache);
  final FileStorage base;
  final RemoteCacheStore cache;

  @override
  Future<void> write(FileRef ref, Uint8List bytes, {String? expectedVersion}) =>
      base.write(ref, bytes, expectedVersion: expectedVersion);

  @override
  Future<FileRef?> create({
    required String suggestedName,
    required Uint8List bytes,
  }) => base.create(suggestedName: suggestedName, bytes: bytes);

  @override
  Future<void> release(FileRef ref) => base.release(ref);

  /// All'apertura una copia con modifiche non caricate ha la precedenza.
  /// Il merge avviene solo dopo lo sblocco riuscito.
  Future<StoredFile> readForUnlock(
    PickedFile file, {
    bool offlineOnly = false,
  }) async {
    if (!RemoteStorage.handles(file.ref)) {
      return file.bytes == null
          ? base.read(file.ref)
          : StoredFile(ref: file.ref, bytes: file.bytes!);
    }
    if (offlineOnly) {
      final record = await cache.read(file.ref);
      if (record == null) throw const RemoteCacheUnavailableException();
      return CachedDatabaseRead(
        ref: file.ref,
        bytes: record.bytes,
        record: record,
        remote: null,
        status: RemoteCacheStatus(offline: true, pending: record.pending),
      );
    }
    final read = await _read(
      file.ref,
      alreadyRead: file.bytes == null
          ? null
          : StoredFile(ref: file.ref, bytes: file.bytes!),
    );
    final record = read.record;
    if (record?.pending ?? false) {
      return CachedDatabaseRead(
        ref: file.ref,
        bytes: record!.bytes,
        record: record,
        remote: read.remote,
        status: RemoteCacheStatus(
          offline: read.status.offline,
          pending: true,
          available: read.status.available,
          error: read.status.error,
        ),
      );
    }
    return read;
  }

  /// Aggiornamento della cache soltanto dopo aver validato e sbloccato KDBX.
  Future<RemoteCacheStatus> opened(StoredFile file) async {
    if (file is! CachedDatabaseRead) return const RemoteCacheStatus();
    if (!file.status.available ||
        file.status.offline ||
        (file.record?.pending ?? false)) {
      return file.status;
    }
    try {
      await cache.write(
        file.ref,
        file.bytes,
        previous: file.record,
        baseHash: _hash(file.bytes),
        pending: false,
      );
      return const RemoteCacheStatus();
    } on RemoteCacheUnavailableException catch (error) {
      return RemoteCacheStatus(available: false, error: error);
    } on RemoteCacheChangedException catch (error) {
      return RemoteCacheStatus(pending: true, error: error);
    }
  }

  @override
  Future<StoredFile> read(FileRef ref) =>
      RemoteStorage.handles(ref) ? _read(ref) : base.read(ref);

  Future<CachedDatabaseRead> _read(
    FileRef file, {
    StoredFile? alreadyRead,
  }) async {
    RemoteCacheRecord? record;
    Object? cacheError;
    try {
      record = await cache.read(file);
    } on RemoteCacheUnavailableException catch (error) {
      cacheError = error;
    }
    try {
      final remote = alreadyRead ?? await base.read(file);
      return CachedDatabaseRead(
        ref: file,
        bytes: remote.bytes,
        record: record,
        remote: remote,
        status: RemoteCacheStatus(
          available: cacheError == null,
          pending: record?.pending ?? false,
          error: cacheError,
        ),
      );
    } on RemoteUnreachableException {
      if (record == null) {
        if (cacheError != null) throw const RemoteCacheUnavailableException();
        rethrow;
      }
      return CachedDatabaseRead(
        ref: file,
        bytes: record.bytes,
        record: record,
        remote: null,
        status: RemoteCacheStatus(offline: true, pending: record.pending),
      );
    }
  }

  /// Rilettura per il salvataggio, con controllo di una terza versione locale
  /// eventualmente prodotta da un altro motore nel frattempo.
  Future<StoredFile> readForSave(FileRef file, String? knownHash) async {
    if (!RemoteStorage.handles(file)) return base.read(file);
    final read = await _read(file);
    final record = read.record;
    final remote = read.remote;
    if (record != null && record.pending && remote != null) {
      final localHash = _hash(record.bytes);
      final remoteHash = _hash(remote.bytes);
      if (remoteHash != record.baseHash &&
          remoteHash != localHash &&
          knownHash != localHash) {
        // Nessuna delle tre versioni viene persa. Riaprire dalla copia pending
        // prima di unire una modifica ulteriore fatta da un altro motore.
        throw const RemoteCacheChangedException();
      }
      if (remoteHash == record.baseHash) {
        return CachedDatabaseRead(
          ref: file,
          bytes: record.bytes,
          record: record,
          remote: remote,
          status: read.status,
        );
      }
    }
    return read;
  }

  /// Prima si rende durevole la nuova copia cifrata; soltanto dopo si tenta
  /// l'upload. Ogni errore remoto lascia una copia pending esplicita.
  Future<RemoteCacheStatus> writeAfterRead(
    FileRef file,
    Uint8List bytes,
    StoredFile? previous,
  ) async {
    if (previous is! CachedDatabaseRead) {
      await base.write(file, bytes, expectedVersion: previous?.version);
      return const RemoteCacheStatus();
    }
    final remote = previous.remote;
    final old = previous.record;
    if (!previous.status.available) {
      if (remote == null) throw const RemoteCacheUnavailableException();
      await base.write(file, bytes, expectedVersion: remote.version);
      return previous.status;
    }
    final baseHash = remote == null ? old!.baseHash : _hash(remote.bytes);
    RemoteCacheRecord pending;
    try {
      pending = await cache.write(
        file,
        bytes,
        previous: old,
        baseHash: baseHash,
        pending: true,
      );
    } on RemoteCacheUnavailableException catch (error) {
      if (remote == null) rethrow;
      await base.write(file, bytes, expectedVersion: remote.version);
      return RemoteCacheStatus(available: false, error: error);
    }
    if (remote == null) {
      return const RemoteCacheStatus(offline: true, pending: true);
    }
    try {
      await base.write(file, bytes, expectedVersion: remote.version);
    } on Object catch (error) {
      return RemoteCacheStatus(pending: true, error: error);
    }
    try {
      await cache.write(
        file,
        bytes,
        previous: pending,
        baseHash: _hash(bytes),
        pending: false,
      );
      return const RemoteCacheStatus();
    } on RemoteCacheChangedException catch (error) {
      return RemoteCacheStatus(pending: true, error: error);
    } on RemoteCacheUnavailableException catch (error) {
      return RemoteCacheStatus(pending: true, available: false, error: error);
    }
  }
}

final remoteCacheStoreProvider = Provider<RemoteCacheStore>(
  (_) => const RemoteCacheStore(),
);

/// Usato solo per i database, mai per importazioni, allegati o file chiave.
final databaseFileStorageProvider = Provider<FileStorage>((ref) {
  final base = ref.watch(fileStorageProvider);
  return ref.watch(appSettingsProvider.select((s) => s.cacheRemoteFiles))
      ? CachedDatabaseStorage(base, ref.watch(remoteCacheStoreProvider))
      : base;
});

/// Disponibilità della copia locale; non apre connessioni di rete.
final remoteCacheAvailableProvider = FutureProvider.autoDispose
    .family<bool, FileRef>((ref, file) async {
      if (!ref.watch(appSettingsProvider.select((s) => s.cacheRemoteFiles)) ||
          !RemoteStorage.handles(file)) {
        return false;
      }
      try {
        return await ref.read(remoteCacheStoreProvider).read(file) != null;
      } on RemoteCacheUnavailableException {
        return false;
      }
    });
