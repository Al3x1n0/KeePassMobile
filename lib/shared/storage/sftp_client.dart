import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'webdav_client.dart';

/// Impronta SSH da verificare prima dell'autenticazione (ADR-015).
typedef SshHostVerifier = Future<bool> Function(
  String keyType,
  String fingerprint,
);

/// Connessione SFTP e chiusura del trasporto che la contiene.
typedef SftpConnection = ({SftpClient files, Future<void> Function() close});

/// Apertura iniettabile per verificare anche gli errori delle transazioni.
typedef SftpConnector = Future<SftpConnection> Function(
  Uri uri,
  RemoteCredentials credentials,
  SshHostVerifier verifyHost,
);

/// Chiave SSH del server diversa da quella ricordata: nessuna connessione.
final class SshHostKeyChangedException implements Exception {
  const SshHostKeyChangedException();
}

/// Chiave privata non valida o passphrase errata.
final class InvalidSshKeyException implements Exception {
  const InvalidSshKeyException();
}

/// Operazione SFTP rifiutata, senza dettagli o percorsi del server.
final class RemoteSftpException implements Exception {
  const RemoteSftpException();
}

/// Client SFTP con verifica obbligatoria del server e scrittura transazionale.
/// Non cancella mai la destinazione prima della rinomina (ADR-015).
class SftpStorageClient {
  const SftpStorageClient({
    this.connectTimeout = const Duration(seconds: 15),
    this.timeout = const Duration(seconds: 90),
    this.connector,
  });

  final Duration connectTimeout;
  final Duration timeout;
  final SftpConnector? connector;

  /// Indirizzo esplicito e senza credenziali, query o frammento.
  static void validate(Uri uri) {
    if (uri.scheme != 'sftp' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535)) ||
        Uri.decodeComponent(uri.path).contains('\u0000')) {
      throw const InvalidRemoteAddressException();
    }
  }

  Future<RemoteFile> get(
    Uri uri, {
    required RemoteCredentials credentials,
    required SshHostVerifier verifyHost,
  }) => _run(uri, credentials, verifyHost, (files) async {
    final file = await files.open(Uri.decodeComponent(uri.path));
    try {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in file.read()) {
        if (bytes.length + chunk.length > WebDavClient.maxBytes) {
          throw const RemoteSftpException();
        }
        bytes.add(chunk);
      }
      return RemoteFile(bytes: bytes.takeBytes());
    } finally {
      await file.close();
    }
  });

  Future<void> put(
    Uri uri,
    Uint8List bytes, {
    required RemoteCredentials credentials,
    required SshHostVerifier verifyHost,
  }) => _run(uri, credentials, verifyHost, (files) async {
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final destination = Uri.decodeComponent(uri.path);
    final temp = '$destination.$suffix.tmp';
    var created = false;
    try {
      final file = await files.open(
        temp,
        mode:
            SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.exclusive,
      );
      created = true;
      try {
        await file.writeBytes(bytes);
      } finally {
        await file.close();
      }
      // dartssh2 usa posix-rename quando disponibile; altrimenti il server
      // può rifiutare una destinazione esistente. Nessun rm di ripiego.
      await files.rename(temp, destination);
      created = false;
    } finally {
      if (created) {
        try {
          await files.remove(temp);
        } on Object {
          // La destinazione resta intatta; un temporaneo cifrato può restare.
        }
      }
    }
  });

  Future<List<RemoteEntry>> list(
    Uri uri, {
    required RemoteCredentials credentials,
    required SshHostVerifier verifyHost,
  }) => _run(uri, credentials, verifyHost, (files) async {
    final entries = <RemoteEntry>[];
    for (final item in await files.listdir(Uri.decodeComponent(uri.path))) {
      final name = item.filename;
      if (name == '.' ||
          name == '..' ||
          name.contains('/') ||
          name.contains('\u0000')) {
        continue;
      }
      final child = uri.replace(
        pathSegments: [...uri.pathSegments.where((s) => s.isNotEmpty), name],
      );
      var attrs = item.attr;
      if (attrs.isSymbolicLink) {
        attrs = await files.stat(Uri.decodeComponent(child.path));
      }
      entries.add(
        RemoteEntry(
          name: name,
          uri: attrs.isDirectory
              ? child.replace(path: '${child.path}/')
              : child,
          isDirectory: attrs.isDirectory,
          size: attrs.size,
        ),
      );
    }
    entries.sort(
      (a, b) => a.isDirectory != b.isDirectory
          ? (a.isDirectory ? -1 : 1)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return List.unmodifiable(entries);
  });

  Future<SftpConnection> _connect(
    Uri uri,
    RemoteCredentials credentials,
    SshHostVerifier verifyHost,
  ) async {
    final pem = credentials.privateKey;
    final identities = pem == null
        ? null
        : await _decodePrivateKey(pem, credentials.password);
    final socket = await SSHSocket.connect(
      uri.host,
      uri.hasPort ? uri.port : 22,
      timeout: connectTimeout,
    );
    Object? trustError;
    final client = SSHClient(
      socket,
      username: credentials.userName,
      identities: identities,
      onPasswordRequest: identities == null ? () => credentials.password : null,
      onVerifyHostKey: (type, fingerprint) async {
        try {
          final accepted = await verifyHost(type, utf8.decode(fingerprint));
          if (!accepted) trustError = const RemoteCanceledException();
          return accepted;
        } on Object catch (e) {
          trustError = e;
          return false;
        }
      },
      authTimeout: timeout,
    );
    try {
      final files = await client.sftp();
      return (files: files, close: client.close);
    } on Object {
      await client.close();
      if (trustError case final error?) throw error;
      rethrow;
    }
  }

  Future<T> _run<T>(
    Uri uri,
    RemoteCredentials credentials,
    SshHostVerifier verifyHost,
    Future<T> Function(SftpClient) operation,
  ) async {
    validate(uri);
    SftpConnection? connection;
    // Ferma il trasporto alla scadenza: nessuna scrittura continua dopo
    // l'errore mostrato all'utente.
    var expired = false;
    final pending = () async {
      final opened = await (connector ?? _connect)(
        uri,
        credentials,
        verifyHost,
      );
      connection = opened;
      if (expired) {
        await opened.close();
        throw const RemoteUnreachableException();
      }
      return operation(opened.files);
    }();
    try {
      return await pending.timeout(
        timeout,
        onTimeout: () {
          expired = true;
          final close = connection?.close;
          if (close != null) unawaited(close().catchError((Object _) {}));
          throw const RemoteUnreachableException();
        },
      );
    } on SSHAuthFailError {
      throw const RemoteAuthException();
    } on SftpStatusError catch (e) {
      if (e.code == SftpStatusCode.noSuchFile) {
        throw const RemoteNotFoundException();
      }
      throw const RemoteSftpException();
    } on SftpError {
      throw const RemoteSftpException();
    } on SSHError {
      throw const RemoteUnreachableException();
    } on SocketException {
      throw const RemoteUnreachableException();
    } on TimeoutException {
      throw const RemoteUnreachableException();
    } finally {
      try {
        await connection?.close();
      } on Object {
        // La chiusura non sostituisce l'esito dell'operazione.
      }
    }
  }
}

// Contesto isolato contenente soltanto stringhe: una closure creata nel
// metodo di connessione può trascinare callback e riferimenti al framework.
Future<List<SSHKeyPair>> _decodePrivateKey(String pem, String passphrase) =>
    Isolate.run(() {
      try {
        return SSHKeyPair.fromPem(pem, passphrase);
      } on Object {
        throw const InvalidSshKeyException();
      }
    });
