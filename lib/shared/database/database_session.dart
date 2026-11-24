import 'dart:async';
import 'dart:collection';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../clipboard/clipboard_service.dart';
import '../crypto/app_crypto_engine.dart';
import 'external_change.dart';
import '../security/biometric_key_store.dart';
import '../storage/file_storage.dart';
import '../storage/recent_passwords_store.dart';
import '../storage/remote_cache.dart';
import '../storage/remote_storage.dart';

/// Database aperto. Esiste solo in memoria (SEC-02).
@immutable
class DatabaseSession {
  DatabaseSession({
    required this.file,
    required this.database,
    this.keyFile,
    this.fileHash,
    this.cacheStatus = const RemoteCacheStatus(),
    this.restrictRedirects = false,
    Iterable<String> recentPasswordIds = const [],
  }) : _recentPasswordIds = recentPasswordIds.toList();

  const DatabaseSession._({
    required this.file,
    required this.database,
    required this.keyFile,
    required this.fileHash,
    required this.cacheStatus,
    required this.restrictRedirects,
    required this._recentPasswordIds,
  });

  final FileRef file;
  final FileRef? keyFile;
  final KdbxDatabase database;

  /// [fileHashOf] del file come letto all'apertura o scritto dall'ultimo
  /// salvataggio; `null`: nessun controllo delle modifiche fatte altrove.
  final String? fileHash;
  final RemoteCacheStatus cacheStatus;
  final bool restrictRedirects;
  final List<String> _recentPasswordIds;

  /// Identificatori precaricati per la sessione; vengono svuotati al blocco.
  List<String> get recentPasswordIds =>
      UnmodifiableListView(_recentPasswordIds);

  /// `false` quando la sessione ha solo la chiave derivata (sblocco
  /// biometrico, ADR-008): i salvataggi non ruotano il salt e la KDF non si
  /// può cambiare.
  bool get hasRawKey => database.header.credentials.hasRawKey;

  DatabaseSession copyWith({
    KdbxDatabase? database,
    Object? keyFile = _unchanged,
    String? fileHash,
    RemoteCacheStatus? cacheStatus,
  }) => DatabaseSession._(
    file: file,
    database: database ?? this.database,
    keyFile: identical(keyFile, _unchanged)
        ? this.keyFile
        : keyFile as FileRef?,
    fileHash: fileHash ?? this.fileHash,
    cacheStatus: cacheStatus ?? this.cacheStatus,
    restrictRedirects: restrictRedirects,
    recentPasswordIds: _recentPasswordIds,
  );
}

/// Modifica da applicare al database prima del salvataggio.
///
/// Viene eseguita in un isolate su una copia del database: deve essere creata
/// da una funzione top-level e catturare solo valori semplici (UUID, testi),
/// mai widget, `ref` o ViewModel.
typedef DatabaseEdit = void Function(KdbxDatabase database);

/// Valore "invariato" di `keyFile`.
const _unchanged = Object();

/// Nessun database aperto.
final class DatabaseLockedException implements Exception {
  const DatabaseLockedException();
}

/// Un salvataggio è già in corso.
final class DatabaseBusyException implements Exception {
  const DatabaseBusyException();
}

/// Sessione del database aperto; `null` quando nessun database è sbloccato.
final databaseSessionProvider =
    NotifierProvider<DatabaseSessionNotifier, DatabaseSession?>(
      DatabaseSessionNotifier.new,
    );

class DatabaseSessionNotifier extends Notifier<DatabaseSession?> {
  bool _saving = false;
  _DatabaseSaveWorker? _saveWorker;
  KdbxDatabase? _stagedDatabase;
  final _openingDatabases = <KdbxDatabase>{};
  final _otherSessions = <DatabaseSession>[];
  final _retired = <FileRef, List<WeakReference<KdbxDatabase>>>{};
  int _lockGeneration = 0;
  List<FileRef> _closedFiles = const [];
  List<FileRef> takeClosedFiles() {
    final result = _closedFiles;
    _closedFiles = const [];
    return result;
  }

  int get lockGeneration => _lockGeneration;
  List<DatabaseSession> get openSessions => [?state, ..._otherSessions];

  void openAdditional(DatabaseSession session, int generation) {
    if (_saving) throw const DatabaseBusyException();
    if (state == null || generation != _lockGeneration) {
      throw const DatabaseLockedException();
    }
    final previous = state!;
    if (previous.file == session.file) {
      _retire(previous, session.database);
      if (!identical(previous._recentPasswordIds, session._recentPasswordIds)) {
        previous._recentPasswordIds.clear();
      }
    } else {
      _otherSessions.add(previous);
    }
    _otherSessions.removeWhere((other) {
      if (other.file != session.file) return false;
      _retire(other, session.database);
      if (!identical(other._recentPasswordIds, session._recentPasswordIds)) {
        other._recentPasswordIds.clear();
      }
      return true;
    });
    state = session;
  }

  void switchTo(FileRef file) {
    if (_saving) throw const DatabaseBusyException();
    final index = _otherSessions.indexWhere((session) => session.file == file);
    if (index < 0 || state == null) throw const DatabaseLockedException();
    final next = _otherSessions.removeAt(index);
    _otherSessions.add(state!);
    state = next;
  }

  ({FileRef file, FileRef? keyFile}) closeSession(FileRef file) {
    if (_saving) throw const DatabaseBusyException();
    final current = state;
    if (current == null || _otherSessions.isEmpty) {
      throw const DatabaseLockedException();
    }
    final DatabaseSession closed;
    if (current.file == file) {
      closed = current;
      state = _otherSessions.removeAt(0);
    } else {
      final index = _otherSessions.indexWhere(
        (session) => session.file == file,
      );
      if (index < 0) throw const DatabaseLockedException();
      closed = _otherSessions.removeAt(index);
      state = current.copyWith();
    }
    _clearDatabase(closed);
    return (file: closed.file, keyFile: closed.keyFile);
  }

  @override
  DatabaseSession? build() {
    DatabaseSession? active;
    listenSelf((_, next) => active = next);
    ref.onDispose(() {
      _saveWorker?.cancel();
      _stagedDatabase?.clearSensitiveData();
      _clearOpeningDatabases();
      if (active case final session?) _clearDatabase(session);
      active = null;
      for (final session in _otherSessions) {
        _clearDatabase(session);
      }
      _otherSessions.clear();
      for (final reference in _retired.values.expand((values) => values)) {
        reference.target?.clearSensitiveData();
      }
      _retired.clear();
    });
    return null;
  }

  void open(DatabaseSession session) {
    for (final previous in openSessions) {
      if (previous.database != session.database) _clearDatabase(previous);
    }
    _otherSessions.clear();
    state = session;
  }

  void _retire(DatabaseSession session, KdbxDatabase replacement) {
    if (session.database == replacement) return;
    final versions = _retired.putIfAbsent(session.file, () => []);
    versions
      ..removeWhere((reference) => reference.target == null)
      ..add(WeakReference(session.database));
  }

  void _clearDatabase(DatabaseSession session) {
    session._recentPasswordIds.clear();
    session.database.clearSensitiveData();
    for (final reference in _retired.remove(session.file) ?? const []) {
      reference.target?.clearSensitiveData();
    }
  }

  /// `true` mentre un salvataggio è in corso.
  bool get isSaving => _saving;

  /// Include un database in apertura nella pulizia immediata al blocco.
  void trackOpeningDatabase(KdbxDatabase database) =>
      _openingDatabases.add(database);

  /// Termina la custodia del database dopo l'apertura o l'annullamento.
  void untrackOpeningDatabase(KdbxDatabase database) =>
      _openingDatabases.remove(database);

  void _clearOpeningDatabases() {
    for (final database in _openingDatabases) {
      database.clearSensitiveData();
    }
    _openingDatabases.clear();
  }

  /// Aggiorna la cronologia in memoria dopo una copia riuscita.
  void recordRecentPassword(String entryId) {
    final session = state;
    if (session == null) return;
    final ids = session._recentPasswordIds;
    ids
      ..remove(entryId)
      ..insert(0, entryId);
    if (ids.length > RecentPasswordsStore.limit) {
      ids.removeRange(RecentPasswordsStore.limit, ids.length);
    }
    state = session.copyWith();
  }

  /// Da qui al blocco il database si salva con la sola chiave derivata, senza
  /// ruotare il salt della KDF: la chiave biometrica salvata resta valida
  /// (variante di D16, ADR-008).
  void useTransformedKeyOnly() {
    final session = state;
    if (session == null) throw const DatabaseLockedException();
    if (_saving) throw const DatabaseBusyException();
    withTransformedKeyOnly(session.database);
    // Nuova istanza: chi osserva la sessione rilegge `hasRawKey`.
    state = session.copyWith();
  }

  /// Chiude il database: il router torna alla scelta del file e i provider
  /// derivati (gruppi, voci) vengono ricalcolati senza dati. Svuota anche gli
  /// appunti, se contengono ancora un valore copiato dall'app.
  void lock({bool preserveGeneratedClipboard = false}) {
    _lockGeneration++;
    _saveWorker?.cancel();
    _stagedDatabase?.clearSensitiveData();
    _clearOpeningDatabases();
    _closedFiles = [
      for (final session in openSessions) ...[session.file, ?session.keyFile],
    ];
    for (final session in openSessions) {
      _clearDatabase(session);
    }
    _otherSessions.clear();
    state = null;
    ref.read(biometricOfferProvider.notifier).clear();
    unawaited(
      ref
          .read(clipboardServiceProvider)
          .clear(preserveGenerated: preserveGeneratedClipboard),
    );
  }

  /// Applica [edit], salva e scrive il file; solo se tutto riesce il
  /// database in memoria viene sostituito con quello salvato. In caso di
  /// errore resta com'era: nessuna modifica parziale.
  ///
  /// Prima di scrivere rilegge il file (`CheckForFileChangesOnSave` di
  /// Keepass2Android): se è cambiato dopo l'apertura chiede all'utente
  /// ([externalChangeResolverProvider]) se sincronizzare, sovrascrivere o
  /// annullare ([ExternalChangeCanceledException]).
  ///
  /// [keyFile] sostituisce il file chiave della sessione (cambio della chiave
  /// principale); se omesso resta quello attuale.
  Future<void> apply(DatabaseEdit edit, {Object? keyFile = _unchanged}) =>
      _save(edit, keyFile: keyFile);

  /// "Sincronizza ora": se il file è cambiato altrove unisce le modifiche e lo
  /// scrive, senza chiedere.
  Future<SyncResult> synchronize() async {
    final changed = await _save(_noEdit, syncOnly: true);
    final status = state?.cacheStatus;
    if (status?.pending ?? false) return SyncResult.pendingUpload;
    if (status?.offline ?? false) return SyncResult.offline;
    return changed ? SyncResult.synchronized : SyncResult.unchanged;
  }

  /// `false` se non ha scritto nulla ([syncOnly] con il file invariato).
  Future<bool> _save(
    DatabaseEdit edit, {
    Object? keyFile = _unchanged,
    bool syncOnly = false,
  }) async {
    final session = state;
    if (session == null) throw const DatabaseLockedException();
    if (_saving) throw const DatabaseBusyException();
    final lockGeneration = _lockGeneration;
    void requireCurrentSession() {
      if (!ref.mounted ||
          lockGeneration != _lockGeneration ||
          state?.database != session.database) {
        throw const DatabaseLockedException();
      }
    }

    _saving = true;
    try {
      final storage = ref.read(
        session.restrictRedirects
            ? fileStorageProvider
            : databaseFileStorageProvider,
      );
      if (storage is CachedDatabaseStorage &&
          RemoteStorage.handles(session.file)) {
        state = session.copyWith(cacheStatus: session.cacheStatus.duringSync());
      }
      final external = await _externalChanges(session, storage, syncOnly);
      requireCurrentSession();
      final mergeWith = external.bytes;
      final current = external.current;
      final cachedRead = current is CachedDatabaseRead ? current : null;
      if (syncOnly &&
          mergeWith == null &&
          (cachedRead == null ||
              cachedRead.status.offline ||
              !(cachedRead.record?.pending ?? false))) {
        if (cachedRead != null && state?.database == session.database) {
          state = session.copyWith(cacheStatus: cachedRead.status);
        }
        return false;
      }
      final worker = _saveWorker = _DatabaseSaveWorker();
      final (database, bytes) = await worker.run(
        session.database,
        edit,
        mergeWith,
      );
      _saveWorker = null;
      _stagedDatabase = database;
      requireCurrentSession();
      RemoteCacheStatus cacheStatus = const RemoteCacheStatus();
      if (storage is CachedDatabaseStorage) {
        cacheStatus = await storage.writeAfterRead(
          session.file,
          bytes,
          current,
          checkBeforeUpload: requireCurrentSession,
        );
      } else {
        await storage.write(
          session.file,
          bytes,
          expectedVersion: current?.version,
        );
      }
      if (!ref.mounted) return true;
      // Bloccato durante il salvataggio: il file è scritto, la sessione resta
      // chiusa.
      if (lockGeneration != _lockGeneration ||
          state?.database != session.database) {
        return true;
      }
      _retire(session, database);
      state = session.copyWith(
        database: database,
        keyFile: keyFile,
        fileHash: fileHashOf(bytes),
        cacheStatus: cacheStatus,
      );
      _stagedDatabase = null;
      return true;
    } on Object catch (error) {
      if (ref.mounted &&
          state?.database == session.database &&
          RemoteStorage.handles(session.file)) {
        state = session.copyWith(
          cacheStatus: session.cacheStatus.withError(error),
        );
      }
      rethrow;
    } finally {
      _saveWorker = null;
      _stagedDatabase?.clearSensitiveData();
      _stagedDatabase = null;
      if (ref.mounted &&
          state?.database == session.database &&
          (state?.cacheStatus.synchronizing ?? false)) {
        state = session.copyWith();
      }
      _saving = false;
    }
  }

  /// Contenuto del file da unire, se è cambiato dopo l'apertura e l'utente
  /// sceglie di sincronizzare (sempre con [syncOnly]); `null` se è invariato
  /// o se l'utente sceglie di sovrascrivere. La versione è quella della
  /// stessa rilettura, anche quando non serve il merge (ADR-016).
  Future<({Uint8List? bytes, StoredFile? current})> _externalChanges(
    DatabaseSession session,
    FileStorage storage,
    bool syncOnly,
  ) async {
    final known = session.fileHash;
    if (known == null && !syncOnly) return (bytes: null, current: null);
    final current = session.restrictRedirects
        ? await storage.readWithoutRedirects(session.file)
        : storage is CachedDatabaseStorage
        ? await storage.readForSave(session.file, known)
        : await storage.read(session.file);
    if (fileHashOf(current.bytes) == known) {
      return (bytes: null, current: current);
    }
    if (syncOnly) return (bytes: current.bytes, current: current);
    final choice = await ref.read(externalChangeResolverProvider)(session.file);
    // Bloccato mentre l'utente decideva: niente scrittura.
    if (!ref.mounted || state?.database != session.database) {
      throw const DatabaseLockedException();
    }
    final merge = switch (choice) {
      ExternalChangeChoice.synchronize => current.bytes,
      ExternalChangeChoice.overwrite => null,
      ExternalChangeChoice.cancel =>
        throw const ExternalChangeCanceledException(),
    };
    return (bytes: merge, current: current);
  }
}

/// Apre un database KDBX in un isolate, perché la KDF (Argon2) dura secondi.
///
/// Password vuota con file chiave: come KeePass si prova prima la password
/// vuota e poi la sola chiave (database creati senza password).
Future<KdbxDatabase> openDatabase({
  required Uint8List data,
  required String password,
  Uint8List? keyFile,
}) {
  return Isolate.run(() async {
    // I campi statici non sono condivisi tra isolate: va reinstallato il
    // motore con Argon2 nativo anche qui.
    AppCryptoEngine.install();

    Future<KdbxDatabase> attempt(String? pw) async {
      final secret = pw == null ? null : ProtectedData.fromString(pw);
      final KdbxCredentials credentials;
      try {
        credentials = KdbxCredentials(password: secret, keyData: keyFile);
      } finally {
        secret?.clear();
      }
      try {
        return await KdbxDatabase.fromBytes(
          data: data,
          credentials: credentials,
        );
      } on Object {
        credentials.clearRawKey();
        rethrow;
      }
    }

    if (password.isEmpty && keyFile != null) {
      try {
        return await attempt('');
      } on InvalidCredentialsError {
        return attempt(null);
      }
    }
    return attempt(password);
  });
}

/// Sostituisce le credenziali di [database] con la sola chiave derivata
/// dell'ultima apertura o dell'ultimo salvataggio (ADR-008).
void withTransformedKeyOnly(KdbxDatabase database) {
  final key = database.header.transformedKey;
  if (key == null) throw StateError('chiave derivata assente');
  database.header.credentials.clearRawKey();
  database.header.credentials = KdbxCredentials.fromTransformedKey(key);
}

/// Apre [data] in un isolate con la chiave derivata [key] (sblocco
/// biometrico), senza KDF. `TransformedKeyStaleError` se i parametri della
/// KDF del file sono cambiati, `InvalidCredentialsError` se la chiave non è
/// quella del file.
Future<KdbxDatabase> openDatabaseWithKey({
  required Uint8List data,
  required KdbxTransformedKey key,
}) {
  return Isolate.run(() async {
    AppCryptoEngine.install();
    return KdbxDatabase.fromBytes(
      data: data,
      credentials: KdbxCredentials.fromTransformedKey(key),
    );
  });
}

/// Riapre in un isolate [bytes] appena scritti con la chiave già derivata di
/// [database] (nessuna KDF): un file che non si riapre è un errore.
Future<void> verifyWrittenDatabase(Uint8List bytes, KdbxDatabase database) {
  final key = database.header.transformedKey;
  if (key == null) throw StateError('database mai salvato');
  return Isolate.run(() async {
    AppCryptoEngine.install();
    await KdbxDatabase.fromBytes(
      data: bytes,
      credentials: KdbxCredentials.fromTransformedKey(key),
    );
  });
}

void _noEdit(KdbxDatabase _) {}

/// Apre [bytes], il file cambiato altrove, con la chiave di [local]: la chiave
/// derivata se i parametri della KDF sono gli stessi, altrimenti la chiave
/// completa (KDF), se la sessione l'ha.
Future<KdbxDatabase> _openExternal(Uint8List bytes, KdbxDatabase local) async {
  final key = local.header.transformedKey;
  final credentials = local.header.credentials;
  try {
    if (key != null) {
      try {
        return await KdbxDatabase.fromBytes(
          data: bytes,
          credentials: KdbxCredentials.fromTransformedKey(key),
        );
      } on TransformedKeyStaleError {
        if (!credentials.hasRawKey) throw const SyncNeedsPasswordException();
      }
    }
    return await KdbxDatabase.fromBytes(data: bytes, credentials: credentials);
  } on InvalidCredentialsError {
    throw const SyncKeyMismatchException();
  }
}

/// Applica [edit] a una copia di [database] e la salva, in un isolate.
///
/// Con [mergeWith] (file cambiato altrove) apre quel contenuto con la chiave
/// attuale prima di [edit] (che può cambiare la chiave), applica [edit] e
/// poi unisce le modifiche fatte altrove (`MergeIn` di `SaveDb.cs`).
///
/// Prima di restituire i byte li riapre, come FileTransactionEx di
/// Keepass2Android: un file che non si riapre non deve sostituire quello
/// buono. La riapertura usa la chiave appena derivata, quindi non ripete la
/// KDF. [database] non viene modificato.
Future<(KdbxDatabase, Uint8List)> saveDatabase(
  KdbxDatabase database,
  DatabaseEdit edit, {
  Uint8List? mergeWith,
}) {
  return Isolate.run(() => _saveInWorker(database, edit, mergeWith));
}

Future<(KdbxDatabase, Uint8List)> _saveInWorker(
  KdbxDatabase database,
  DatabaseEdit edit,
  Uint8List? mergeWith,
) async {
  AppCryptoEngine.install();
  final external = mergeWith == null
      ? null
      : await _openExternal(mergeWith, database);
  edit(database);
  if (external != null) {
    try {
      database.merge(external);
    } on MergeError {
      throw const SyncDifferentDatabaseException();
    }
  }
  final bytes = Uint8List.fromList(await database.save());
  final key = database.header.transformedKey!;
  await KdbxDatabase.fromBytes(
    data: bytes,
    credentials: KdbxCredentials.fromTransformedKey(key),
  );
  return (database, bytes);
}

class _DatabaseSaveWorker {
  Isolate? _isolate;
  bool _canceled = false;

  void cancel() {
    _canceled = true;
    _isolate?.kill(priority: Isolate.immediate);
  }

  Future<(KdbxDatabase, Uint8List)> run(
    KdbxDatabase database,
    DatabaseEdit edit,
    Uint8List? mergeWith,
  ) async {
    final reply = ReceivePort();
    try {
      final isolate = _isolate = await Isolate.spawn(
        _execute,
        (reply.sendPort, database, edit, mergeWith),
        onExit: reply.sendPort,
        onError: reply.sendPort,
        paused: true,
      );
      if (_canceled) {
        isolate.kill(priority: Isolate.immediate);
      } else {
        isolate.resume(isolate.pauseCapability!);
      }
      final response = await reply.first;
      if (_canceled) {
        if (response case (final KdbxDatabase db, _)) db.clearSensitiveData();
        throw const DatabaseLockedException();
      }
      return switch (response) {
        (final KdbxDatabase db, final Uint8List bytes) => (db, bytes),
        (final Object error, final StackTrace stack) =>
          Error.throwWithStackTrace(error, stack),
        _ => throw StateError('salvataggio interrotto'),
      };
    } finally {
      reply.close();
      _isolate = null;
    }
  }

  static Future<void> _execute(
    (SendPort, KdbxDatabase, DatabaseEdit, Uint8List?) request,
  ) async {
    final (reply, database, edit, mergeWith) = request;
    try {
      final result = await _saveInWorker(database, edit, mergeWith);
      Isolate.exit(reply, result);
    } on Object catch (error, stack) {
      Isolate.exit(reply, (error, stack));
    }
  }
}
