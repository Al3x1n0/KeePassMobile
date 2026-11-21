import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

/// Credenziali di un server di storage (D30). Mai nei log o nei riferimenti ai
/// file (SEC-01).
@immutable
class RemoteCredentials {
  const RemoteCredentials({
    required this.userName,
    required this.password,
    this.privateKey,
  });

  final String userName;

  /// Password del server o passphrase della chiave privata SSH.
  final String password;

  /// Chiave OpenSSH in memoria; persistita solo nello store credenziali.
  final String? privateKey;
}

/// Server raggiunto ma credenziali rifiutate (HTTP 401 o autenticazione SSH).
final class RemoteAuthException implements Exception {
  const RemoteAuthException();
}

/// Server non raggiungibile: rete assente, nome sconosciuto, tempo scaduto.
final class RemoteUnreachableException implements Exception {
  const RemoteUnreachableException();
}

/// Il file o la cartella non esiste sul server (404).
final class RemoteNotFoundException implements Exception {
  const RemoteNotFoundException();
}

/// Il server ha una versione diversa da quella verificata per il salvataggio.
final class RemoteConflictException implements Exception {
  const RemoteConflictException();
}

/// Risposta del server non prevista (stato HTTP).
final class RemoteHttpException implements Exception {
  const RemoteHttpException(this.status);

  final int status;
}

/// Indirizzo non `https://`: password e database non viaggiano in chiaro.
final class InsecureRemoteException implements Exception {
  const InsecureRemoteException();
}

/// L'indirizzo scritto non è un URL utilizzabile.
final class InvalidRemoteAddressException implements Exception {
  const InvalidRemoteAddressException();
}

/// L'utente non ha fornito le credenziali o non ha accettato il certificato.
final class RemoteCanceledException implements Exception {
  const RemoteCanceledException();
}

/// Certificato del server non valido per il sistema e non ancora accettato
/// dall'utente (D31). [fingerprint]: SHA-256 del certificato, `AA:BB:…`.
final class UntrustedCertificateException implements Exception {
  const UntrustedCertificateException({
    required this.server,
    required this.fingerprint,
  });

  /// `host:porta`.
  final String server;
  final String fingerprint;
}

/// Contenuto di un file letto dal server, con la versione (`ETag`) se il
/// server la fornisce.
@immutable
class RemoteFile {
  const RemoteFile({required this.bytes, this.etag});

  final Uint8List bytes;
  final String? etag;
}

/// Elemento di una cartella del server.
@immutable
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.uri,
    required this.isDirectory,
    this.size,
  });

  final String name;
  final Uri uri;
  final bool isDirectory;
  final int? size;
}

/// `host:porta` di [uri], chiave dei certificati accettati.
String serverOf(Uri uri) =>
    '${uri.host}:${uri.hasPort
        ? uri.port
        : uri.scheme == 'sftp'
        ? 22
        : uri.port}';

/// Impronta SHA-256 di un certificato in DER, nel formato mostrato all'utente.
String certificateFingerprint(Uint8List der) => sha256
    .convert(der)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

/// Client WebDAV minimo su `HttpClient` di Dart (`WebDavStorage` di
/// Keepass2Android): `GET`, `PUT`, `PROPFIND` con profondità 1.
///
/// Solo `https://`. Autenticazione Basic inviata subito; Digest se il server
/// la chiede. Un certificato non valido per il sistema si accetta solo se la sua
/// impronta è tra [trusted] (D31), altrimenti [UntrustedCertificateException].
class WebDavClient {
  const WebDavClient({
    this.connectTimeout = const Duration(seconds: 15),
    this.timeout = const Duration(seconds: 90),
  });

  final Duration connectTimeout;
  final Duration timeout;

  /// Dimensione massima di un file letto (il database sta tutto in memoria).
  static const maxBytes = 128 * 1024 * 1024;

  Future<RemoteFile> get(
    Uri uri, {
    required RemoteCredentials credentials,
    Set<String> trusted = const {},
  }) => _send(uri, 'GET', credentials, trusted, (response) async {
    _expect(response, const {200});
    return RemoteFile(
      bytes: await _readAll(response),
      etag: response.headers.value(HttpHeaders.etagHeader),
    );
  });

  Future<RemoteFile> getWithoutRedirects(
    Uri uri, {
    required RemoteCredentials credentials,
    Set<String> trusted = const {},
  }) => _send(uri, 'GET', credentials, trusted, (response) async {
    _expect(response, const {200});
    return RemoteFile(
      bytes: await _readAll(response),
      etag: response.headers.value(HttpHeaders.etagHeader),
    );
  }, followRedirects: false);

  /// Sostituisce il contenuto del file (o lo crea).
  Future<void> put(
    Uri uri,
    Uint8List bytes, {
    required RemoteCredentials credentials,
    Set<String> trusted = const {},
    String? ifMatch,
  }) => _send(
    uri,
    'PUT',
    credentials,
    trusted,
    (response) async {
      _expect(response, const {200, 201, 204});
      await response.drain<void>();
    },
    headers: {HttpHeaders.ifMatchHeader: ?ifMatch},
    body: bytes,
    contentType: 'application/octet-stream',
  );

  /// Cartelle e file contenuti in [directory], senza la cartella stessa;
  /// prima le cartelle, poi i file, in ordine alfabetico.
  Future<List<RemoteEntry>> list(
    Uri directory, {
    required RemoteCredentials credentials,
    Set<String> trusted = const {},
  }) {
    final dir = _asDirectory(directory);
    return _send(
      dir,
      'PROPFIND',
      credentials,
      trusted,
      (response) async {
        _expect(response, const {207});
        final body = utf8.decode(
          await _readAll(response),
          allowMalformed: true,
        );
        return parseMultistatus(dir, body);
      },
      body: utf8.encode(_propfindBody),
      contentType: 'application/xml; charset=utf-8',
      headers: const {'Depth': '1'},
    );
  }

  static const _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/><d:getcontentlength/>'
      '</d:prop></d:propfind>';

  /// Elementi di una risposta `207 Multi-Status` per la cartella [dir].
  @visibleForTesting
  static List<RemoteEntry> parseMultistatus(Uri dir, String body) {
    dir = _asDirectory(dir);
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException {
      throw const RemoteHttpException(207);
    }
    final entries = <RemoteEntry>[];
    for (final response in document.findAllElements(
      'response',
      namespace: 'DAV:',
    )) {
      final href = response
          .findElements('href', namespace: 'DAV:')
          .firstOrNull
          ?.innerText
          .trim();
      if (href == null || href.isEmpty) continue;
      final uri = _resolveServerUri(dir, href);
      if (uri == null || uri.hasQuery) continue;
      final name = _directChildName(dir, uri);
      if (name == null) continue;
      final isDirectory = response
          .findAllElements('collection', namespace: 'DAV:')
          .isNotEmpty;
      final length = response
          .findAllElements('getcontentlength', namespace: 'DAV:')
          .firstOrNull
          ?.innerText
          .trim();
      entries.add(
        RemoteEntry(
          name: name,
          uri: isDirectory ? _asDirectory(uri) : uri,
          isDirectory: isDirectory,
          size: int.tryParse(length ?? ''),
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return List.unmodifiable(entries);
  }

  static Uri _asDirectory(Uri uri) =>
      uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');

  static bool _sameHttpsOrigin(Uri base, Uri uri) =>
      base.scheme == 'https' &&
      uri.scheme == 'https' &&
      uri.host == base.host &&
      uri.port == base.port;

  static Uri? _resolveServerUri(Uri base, String reference) {
    // Dart normalizza i backslash negli URL HTTP. Rifiutare i riferimenti
    // ambigui prima che vengano interpretati come separatori.
    if (reference.isEmpty || reference.contains(r'\')) return null;
    final relative = Uri.tryParse(reference);
    if (relative == null || relative.authority.contains('@')) return null;
    final uri = base.resolveUri(relative);
    if (!_sameHttpsOrigin(base, uri) || uri.hasFragment) return null;
    return uri;
  }

  static final _invalidChildName = RegExp(r'[/\\\x00-\x1f\x7f]');

  static String? _directChildName(Uri dir, Uri uri) {
    final directoryPath = dir.path;
    final path = uri.path;
    if (!path.startsWith(directoryPath) ||
        path.length == directoryPath.length) {
      return null;
    }
    final segment = path.substring(
      directoryPath.length,
      path.endsWith('/') ? path.length - 1 : path.length,
    );
    final String name;
    try {
      name = Uri.decodeComponent(segment);
    } on FormatException {
      return null;
    }
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        _invalidChildName.hasMatch(name)) {
      return null;
    }
    return name;
  }

  Future<T> _send<T>(
    Uri uri,
    String method,
    RemoteCredentials credentials,
    Set<String> trusted,
    Future<T> Function(HttpClientResponse response) handle, {
    List<int>? body,
    String? contentType,
    Map<String, String> headers = const {},
    bool followRedirects = true,
  }) async {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw const InsecureRemoteException();
    }
    if (uri.authority.contains('@') || uri.hasFragment) {
      throw const InvalidRemoteAddressException();
    }
    String? rejected;
    // Basic inviata subito (la connessione è cifrata). Digest solo se il
    // server la chiede: HttpClient ripete la richiesta da sé, ma senza il
    // contenuto, quindi le scritture passano prima da un HEAD.
    var digest = false;
    var digestAdded = false;
    var allowRetry = true;
    final client = HttpClient();
    client
      ..connectionTimeout = connectTimeout
      ..autoUncompress = true
      ..badCertificateCallback = (certificate, host, port) {
        if (host != uri.host || port != uri.port) return false;
        final fingerprint = certificateFingerprint(certificate.der);
        if (trusted.contains(fingerprint)) return true;
        rejected = fingerprint;
        return false;
      }
      ..authenticate = (url, scheme, realm) async {
        if (!_sameHttpsOrigin(uri, url) ||
            scheme.toLowerCase() != 'digest' ||
            digestAdded ||
            !allowRetry) {
          return false;
        }
        digest = digestAdded = true;
        client.addCredentials(
          url,
          realm ?? '',
          HttpClientDigestCredentials(
            credentials.userName,
            credentials.password,
          ),
        );
        return true;
      };
    final basic =
        'Basic ${base64.encode(utf8.encode('${credentials.userName}:${credentials.password}'))}';

    Future<HttpClientResponse> attempt(
      String verb, {
      List<int>? content,
    }) async {
      allowRetry = content == null;
      final request = await client.openUrl(verb, uri);
      request.followRedirects = false;
      if (!digest) {
        request.headers.set(HttpHeaders.authorizationHeader, basic);
      }
      headers.forEach(request.headers.set);
      if (content != null) {
        if (contentType != null) {
          request.headers.set(HttpHeaders.contentTypeHeader, contentType);
        }
        request.contentLength = content.length;
        request.add(content);
      }
      return request.close();
    }

    try {
      return await () async {
        var response = await attempt(method, content: body);
        if (method == 'GET' && followRedirects) {
          var current = uri;
          while (response.isRedirect) {
            final locations = response.headers[HttpHeaders.locationHeader];
            final target = locations != null && locations.length == 1
                ? _resolveServerUri(current, locations.single)
                : null;
            if (target == null ||
                target == current ||
                response.redirects.length >= 5) {
              throw RemoteHttpException(response.statusCode);
            }
            await response.drain<void>();
            response = await response.redirect('GET', target);
            current = target;
          }
        }
        if (response.statusCode == HttpStatus.unauthorized && body != null) {
          final challenge =
              response.headers.value(HttpHeaders.wwwAuthenticateHeader) ?? '';
          await response.drain<void>();
          if (!digestAdded && challenge.toLowerCase().startsWith('digest')) {
            final probe = await attempt('HEAD');
            await probe.drain<void>();
            if (digestAdded) response = await attempt(method, content: body);
          }
        }
        if (response.statusCode == HttpStatus.unauthorized) {
          await response.drain<void>();
          throw const RemoteAuthException();
        }
        return handle(response);
      }().timeout(timeout);
    } on HandshakeException {
      if (rejected case final fingerprint?) {
        throw UntrustedCertificateException(
          server: serverOf(uri),
          fingerprint: fingerprint,
        );
      }
      throw const RemoteUnreachableException();
    } on TlsException {
      throw const RemoteUnreachableException();
    } on SocketException {
      throw const RemoteUnreachableException();
    } on TimeoutException {
      throw const RemoteUnreachableException();
    } on HttpException {
      throw const RemoteUnreachableException();
    } finally {
      client.close(force: true);
    }
  }

  static void _expect(HttpClientResponse response, Set<int> accepted) {
    final status = response.statusCode;
    if (accepted.contains(status)) return;
    response.drain<void>().ignore();
    if (status == HttpStatus.preconditionFailed) {
      throw const RemoteConflictException();
    }
    if (status == HttpStatus.notFound) throw const RemoteNotFoundException();
    throw RemoteHttpException(status);
  }

  static Future<Uint8List> _readAll(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > maxBytes) throw const RemoteHttpException(413);
    }
    return builder.takeBytes();
  }
}
