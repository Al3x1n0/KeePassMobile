import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';

/// Server WebDAV HTTPS minimo per i test del client: certificato autofirmato
/// di `test/fixtures/tls`, autenticazione Basic, `GET`, `PUT`, `PROPFIND`.
class WebDavTestServer {
  WebDavTestServer._(this._server, this.userName, this.secret);

  static const certificatePath = 'test/fixtures/tls/test_cert.pem';
  static const keyPath = 'test/fixtures/tls/test_key.pem';

  static Future<WebDavTestServer> start({
    String userName = 'mario',
    String secret = 'segreto-server',
  }) async {
    final context = SecurityContext()
      ..useCertificateChain(certificatePath)
      ..usePrivateKey(keyPath);
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final test = WebDavTestServer._(server, userName, secret);
    server.listen(test._handle);
    return test;
  }

  final HttpServer _server;
  final String userName;
  final String secret;

  /// Contenuto dei file per percorso (`/dav/prova.kdbx`).
  final files = <String, Uint8List>{};
  final redirects = <String, Uri>{};

  /// Cartelle esplicite, oltre a quelle dei file.
  final directories = <String>{'/'};

  /// `METODO percorso` delle richieste autenticate.
  final requests = <String>[];

  /// Modifica concorrente iniettata immediatamente prima della precondizione.
  void Function()? beforeWrite;

  int get port => _server.port;

  Uri uri(String path) => Uri.parse('https://127.0.0.1:$port$path');

  RemoteCredentials get credentials =>
      RemoteCredentials(userName: userName, password: secret);

  /// Impronta SHA-256 del certificato del server, come la calcola il client.
  static String get fingerprint {
    final pem = File(certificatePath).readAsStringSync();
    final body = pem
        .split('\n')
        .where((l) => l.isNotEmpty && !l.startsWith('-----'))
        .join();
    return certificateFingerprint(base64.decode(body));
  }

  Future<void> close() => _server.close(force: true);

  static String etagOf(Uint8List bytes) => '"${sha1.convert(bytes)}"';

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final expected = 'Basic ${base64.encode(utf8.encode('$userName:$secret'))}';
    if (request.headers.value(HttpHeaders.authorizationHeader) != expected) {
      await request.drain<void>();
      response
        ..statusCode = HttpStatus.unauthorized
        ..headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="test"');
      await response.close();
      return;
    }
    final path = Uri.decodeComponent(request.uri.path);
    requests.add('${request.method} $path');
    switch (request.method) {
      case 'GET':
        if (redirects[path] case final target?) {
          response.statusCode = HttpStatus.found;
          response.headers.set(HttpHeaders.locationHeader, target.toString());
          break;
        }
        final bytes = files[path];
        if (bytes == null) {
          response.statusCode = HttpStatus.notFound;
        } else {
          response.headers.set(HttpHeaders.etagHeader, etagOf(bytes));
          response.add(bytes);
        }
      case 'PUT':
        final builder = BytesBuilder();
        await request.forEach(builder.add);
        beforeWrite?.call();
        final expectedTag = request.headers.value(HttpHeaders.ifMatchHeader);
        if (expectedTag != null &&
            (files[path] == null || expectedTag != etagOf(files[path]!))) {
          response.statusCode = HttpStatus.preconditionFailed;
          break;
        }
        final existed = files.containsKey(path);
        files[path] = builder.takeBytes();
        response.statusCode = existed
            ? HttpStatus.noContent
            : HttpStatus.created;
      case 'PROPFIND':
        await request.drain<void>();
        final dir = path.endsWith('/') ? path : '$path/';
        if (!_isDirectory(dir)) {
          response.statusCode = HttpStatus.notFound;
          break;
        }
        response
          ..statusCode = 207
          ..headers.contentType = ContentType(
            'application',
            'xml',
            charset: 'utf-8',
          )
          ..write(_multistatus(dir));
      default:
        response.statusCode = HttpStatus.methodNotAllowed;
    }
    await response.close();
  }

  bool _isDirectory(String dir) =>
      directories.contains(dir) || files.keys.any((f) => f.startsWith(dir));

  String _multistatus(String dir) {
    final children = <String, bool>{};
    for (final d in directories) {
      if (d != dir && d.startsWith(dir)) {
        children['$dir${d.substring(dir.length).split('/').first}/'] = true;
      }
    }
    for (final f in files.keys) {
      if (!f.startsWith(dir)) continue;
      final rest = f.substring(dir.length).split('/');
      if (rest.length == 1) {
        children[f] = false;
      } else {
        children['$dir${rest.first}/'] = true;
      }
    }
    String response(String href, bool collection, [int? length]) =>
        '<d:response><d:href>${Uri.encodeFull(href)}</d:href><d:propstat><d:prop>'
        '<d:resourcetype>${collection ? '<d:collection/>' : ''}</d:resourcetype>'
        '${length == null ? '' : '<d:getcontentlength>$length</d:getcontentlength>'}'
        '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';
    return '<?xml version="1.0" encoding="utf-8"?><d:multistatus xmlns:d="DAV:">'
        '${response(dir, true)}'
        '${children.entries.map((e) => response(e.key, e.value, e.value ? null : files[e.key]!.length)).join()}'
        '</d:multistatus>';
  }
}
