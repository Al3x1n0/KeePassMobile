import 'dart:typed_data';

import 'package:keepass_mobile/shared/storage/webdav_client.dart';

/// Client WebDAV in memoria: file per URL, credenziali accettate e un
/// certificato non riconosciuto finché non è tra quelli accettati.
class FakeWebDavClient extends WebDavClient {
  FakeWebDavClient({required this.accepted, this.untrustedFingerprint});

  final RemoteCredentials accepted;

  /// Se impostato, ogni richiesta fallisce finché l'impronta non è accettata.
  final String? untrustedFingerprint;

  final files = <String, Uint8List>{};

  /// Metodo e URL di ogni richiesta, e le credenziali usate.
  final calls = <String>[];
  final usedUsers = <String>[];

  void _check(Uri uri, RemoteCredentials credentials, Set<String> trusted) {
    if (uri.scheme != 'https') throw const InsecureRemoteException();
    if (untrustedFingerprint case final fingerprint?
        when !trusted.contains(fingerprint)) {
      throw UntrustedCertificateException(
        server: serverOf(uri),
        fingerprint: fingerprint,
      );
    }
    usedUsers.add(credentials.userName);
    if (credentials.userName != accepted.userName ||
        credentials.password != accepted.password) {
      throw const RemoteAuthException();
    }
  }

  @override
  Future<RemoteFile> get(
    Uri uri, {
    required RemoteCredentials credentials,
    Set<String> trusted = const {},
  }) async {
    calls.add('GET $uri');
    _check(uri, credentials, trusted);
    final bytes = files[uri.toString()];
    if (bytes == null) throw const RemoteNotFoundException();
    return RemoteFile(bytes: Uint8List.fromList(bytes));
  }

  @override
  Future<void> put(
    Uri uri,
    Uint8List bytes, {
    required RemoteCredentials credentials,
    Set<String> trusted = const {},
    String? ifMatch,
  }) async {
    calls.add('PUT $uri');
    _check(uri, credentials, trusted);
    files[uri.toString()] = Uint8List.fromList(bytes);
  }

  @override
  Future<List<RemoteEntry>> list(
    Uri directory, {
    required RemoteCredentials credentials,
    Set<String> trusted = const {},
  }) async {
    calls.add('PROPFIND $directory');
    _check(directory, credentials, trusted);
    final prefix = directory.toString();
    return [
      for (final url in files.keys)
        if (url.startsWith(prefix) &&
            !url.substring(prefix.length).contains('/'))
          RemoteEntry(
            name: Uri.parse(url).pathSegments.last,
            uri: Uri.parse(url),
            isDirectory: false,
            size: files[url]!.length,
          ),
    ];
  }
}
