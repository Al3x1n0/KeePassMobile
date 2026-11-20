import 'dart:io';
import 'dart:isolate';

import 'package:document_access/document_access.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'remote_storage.dart';
import 'sftp_client.dart';
import 'webdav_client.dart';

/// Riferimento a un file scelto dall'utente (database o file chiave).
@immutable
class FileRef {
  const FileRef({required this.uri, required this.name});

  /// `file://`, `content://` (Android), `bookmark:` (iOS) o `https://` / `sftp://` (file
  /// su un server WebDAV, ADR-014: mai credenziali nel riferimento).
  final String uri;

  /// Nome da mostrare.
  final String name;

  Map<String, Object> toJson() => {'uri': uri, 'name': name};

  /// `null` se [json] non ha la forma attesa.
  static FileRef? fromJson(Object? json) {
    if (json case {'uri': final String uri, 'name': final String name}) {
      return FileRef(uri: uri, name: name);
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is FileRef && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

/// File appena scelto, con il contenuto già letto, oppure riferimento da
/// leggere (file recenti) se [bytes] è `null`.
@immutable
class PickedFile {
  const PickedFile({required this.ref, this.bytes, this.persistent = true});

  final FileRef ref;
  final Uint8List? bytes;

  /// `false` se il sistema non concede un accesso che sopravvive al riavvio
  /// dell'app: il file andrà scelto di nuovo.
  final bool persistent;
}

/// Contenuto letto e riferimento da usare d'ora in poi: può differire da
/// quello richiesto se il sistema lo ha aggiornato (bookmark iOS obsoleto).
@immutable
class StoredFile {
  const StoredFile({required this.ref, required this.bytes, this.version});

  final FileRef ref;
  final Uint8List bytes;

  /// ETag forte della stessa lettura remota; assente per gli altri storage.
  final String? version;
}

/// Il file non è più raggiungibile (spostato, permesso revocato, riferimento
/// non valido).
final class FileUnavailableException implements Exception {
  const FileUnavailableException();
}

/// Scrittura non riuscita su un file raggiungibile.
final class FileWriteException implements Exception {
  const FileWriteException();
}

/// Lettura e scrittura dei file scelti dall'utente, nel file originale.
///
/// `file://` con `dart:io` (scrittura atomica: file temporaneo e rinomina, come
/// `FileTransactionEx` di Keepass2Android); `https://` e `sftp://` con [RemoteStorage]
/// (WebDAV e SFTP); gli altri riferimenti con il plugin nativo `document_access`.
///
/// Per i file remoti gli errori del server restano tipizzati
/// ([RemoteAuthException], [RemoteUnreachableException], …); un file che non
/// c'è più è [FileUnavailableException].
class FileStorage {
  const FileStorage([this._documents = const DocumentAccess(), this._remote]);

  final DocumentAccess _documents;
  final RemoteStorage? _remote;

  Future<StoredFile> read(FileRef ref) async {
    if (RemoteStorage.handles(ref)) {
      final remote = _remote;
      if (remote == null) throw const FileUnavailableException();
      try {
        final data = await remote.readFile(ref);
        final tag = data.etag;
        return StoredFile(
          ref: ref,
          bytes: data.bytes,
          version: tag != null && tag.startsWith('"') && tag.endsWith('"')
              ? tag
              : null,
        );
      } on RemoteNotFoundException {
        throw const FileUnavailableException();
      }
    }
    if (_localFile(ref) case final file?) {
      try {
        return StoredFile(ref: ref, bytes: await file.readAsBytes());
      } on FileSystemException {
        throw const FileUnavailableException();
      }
    }
    try {
      final data = await _documents.read(ref.uri);
      final refreshed = switch (data.refreshedUri) {
        final uri? => FileRef(uri: uri, name: ref.name),
        null => ref,
      };
      return StoredFile(ref: refreshed, bytes: data.bytes);
    } on DocumentUnavailableException {
      throw const FileUnavailableException();
    } on DocumentAccessException {
      throw const FileUnavailableException();
    }
  }

  Future<StoredFile> readWithoutRedirects(FileRef ref) async {
    if (!RemoteStorage.handles(ref)) return read(ref);
    final remote = _remote;
    if (remote == null) throw const FileUnavailableException();
    try {
      final data = await remote.readFileWithoutRedirects(ref);
      final tag = data.etag;
      return StoredFile(
        ref: ref,
        bytes: data.bytes,
        version: tag != null && tag.startsWith('"') && tag.endsWith('"')
            ? tag
            : null,
      );
    } on RemoteNotFoundException {
      throw const FileUnavailableException();
    }
  }

  /// Sostituisce l'intero contenuto del file con [bytes].
  Future<void> write(
    FileRef ref,
    Uint8List bytes, {
    String? expectedVersion,
  }) async {
    if (RemoteStorage.handles(ref)) {
      final remote = _remote;
      if (remote == null) throw const FileUnavailableException();
      try {
        await remote.write(ref, bytes, expectedVersion: expectedVersion);
      } on RemoteNotFoundException {
        throw const FileUnavailableException();
      }
      return;
    }
    if (_localFile(ref) case final file?) {
      final temp = File('${file.path}.tmp');
      try {
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(file.path);
      } on FileSystemException {
        if (await temp.exists()) await temp.delete();
        if (!await file.parent.exists()) throw const FileUnavailableException();
        throw const FileWriteException();
      }
      return;
    }
    try {
      await _documents.write(ref.uri, bytes);
    } on DocumentUnavailableException {
      throw const FileUnavailableException();
    } on DocumentAccessException {
      throw const FileWriteException();
    }
  }

  /// Fa scegliere all'utente dove creare un file nuovo con il nome proposto
  /// [suggestedName] e vi scrive [bytes]. `null` se l'utente annulla.
  Future<FileRef?> create({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    try {
      final created = await _documents.create(
        suggestedName: suggestedName,
        bytes: bytes,
      );
      if (created == null) return null;
      return FileRef(uri: created.uri, name: created.name);
    } on DocumentUnavailableException {
      throw const FileUnavailableException();
    } on DocumentAccessException {
      throw const FileWriteException();
    }
  }

  /// Rinuncia al permesso persistente sul file, se esiste. Non fallisce mai:
  /// un permesso già perso non è un errore.
  Future<void> release(FileRef ref) async {
    if (RemoteStorage.handles(ref)) {
      await _remote?.release(ref);
      return;
    }
    if (_localFile(ref) != null) return;
    try {
      await _documents.release(ref.uri);
    } on DocumentUnavailableException {
      // Già rilasciato.
    } on DocumentAccessException {
      // Ignorato: al massimo resta un permesso inutilizzato.
    }
  }

  static File? _localFile(FileRef ref) {
    final uri = Uri.tryParse(ref.uri);
    return uri != null && uri.scheme == 'file' ? File.fromUri(uri) : null;
  }
}

final fileStorageProvider = Provider<FileStorage>(
  (ref) =>
      FileStorage(const DocumentAccess(), ref.watch(remoteStorageProvider)),
);

/// Lettura annullabile che usa solo credenziali e chiavi server già autorizzate.
class RestrictedFileRead {
  RestrictedFileRead(this.storage, this.file);
  final FileStorage storage;
  final FileRef file;
  bool _canceled = false;
  Isolate? _isolate;
  ReceivePort? _port;

  void cancel() {
    _canceled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _port?.close();
  }

  Future<StoredFile> run() async {
    if (!RemoteStorage.handles(file)) {
      final result = await storage.readWithoutRedirects(file);
      if (_canceled) throw const FileUnavailableException();
      return result;
    }
    final remote = storage._remote;
    if (remote == null) throw const FileUnavailableException();
    var credentials =
        remote.session.credentialsOf(file) ?? await remote.store.read(file);
    if (_canceled) throw const FileUnavailableException();
    if (credentials == null) throw const RemoteCanceledException();
    final uri = Uri.parse(file.uri);
    final trusted = remote.trust.fingerprints(serverOf(uri));
    final sshHost = remote.trust.sshHost(serverOf(uri));
    if (uri.scheme == 'sftp' && sshHost == null) {
      throw const RemoteCanceledException();
    }
    final port = ReceivePort();
    _port = port;
    final spawning = Isolate.spawn(_restrictedReadWorker, (
      port.sendPort,
      file.uri,
      credentials,
      trusted,
      sshHost,
    ));
    credentials = null;
    final isolate = await spawning;
    _isolate = isolate;
    try {
      if (_canceled) throw const FileUnavailableException();
      final result = await port.first;
      if (_canceled || result is! RemoteFile) {
        throw const FileUnavailableException();
      }
      final tag = result.etag;
      return StoredFile(
        ref: file,
        bytes: result.bytes,
        version: tag != null && tag.startsWith('"') && tag.endsWith('"')
            ? tag
            : null,
      );
    } finally {
      isolate.kill(priority: Isolate.immediate);
      _isolate = null;
      port.close();
      _port = null;
    }
  }
}

Future<void> _restrictedReadWorker(
  (SendPort, String, RemoteCredentials, Set<String>, String?) args,
) async {
  final (port, address, credentials, trusted, sshHost) = args;
  try {
    final uri = Uri.parse(address);
    final result = uri.scheme == 'sftp'
        ? await const SftpStorageClient().get(
            uri,
            credentials: credentials,
            verifyHost: (type, fingerprint) async =>
                '$type $fingerprint' == sshHost,
          )
        : await const WebDavClient().getWithoutRedirects(
            uri,
            credentials: credentials,
            trusted: trusted,
          );
    port.send(result);
  } catch (_) {
    port.send(null);
  }
}

/// Selettore di documenti del sistema, con accesso persistente al file scelto.
class FilePickerService {
  const FilePickerService([this._documents = const DocumentAccess()]);

  final DocumentAccess _documents;

  /// `null` se l'utente annulla.
  Future<PickedFile?> pick() async {
    final picked = await _documents.pick();
    if (picked == null) return null;
    return PickedFile(
      ref: FileRef(uri: picked.uri, name: picked.name),
      bytes: picked.bytes,
      persistent: picked.persistent,
    );
  }
}

final filePickerServiceProvider = Provider<FilePickerService>(
  (ref) => const FilePickerService(),
);
