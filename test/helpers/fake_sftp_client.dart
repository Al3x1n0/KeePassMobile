import 'dart:typed_data';

import 'package:keepass_mobile/shared/storage/sftp_client.dart';
import 'package:keepass_mobile/shared/storage/webdav_client.dart';

/// Server SFTP in memoria con verifica dell'impronta prima delle credenziali.
class FakeSftpClient extends SftpStorageClient {
  FakeSftpClient({required this.accepted});
  final RemoteCredentials accepted;
  final files = <String, Uint8List>{};
  String fingerprint = 'SHA256:synthetic';

  Future<void> _check(
    RemoteCredentials credentials,
    SshHostVerifier verify,
  ) async {
    if (!await verify('ssh-ed25519', fingerprint)) {
      throw const RemoteCanceledException();
    }
    if (credentials.userName != accepted.userName ||
        credentials.password != accepted.password ||
        credentials.privateKey != accepted.privateKey) {
      throw const RemoteAuthException();
    }
  }

  @override
  Future<RemoteFile> get(
    Uri uri, {
    required RemoteCredentials credentials,
    required SshHostVerifier verifyHost,
  }) async {
    await _check(credentials, verifyHost);
    final data = files[uri.toString()];
    if (data == null) throw const RemoteNotFoundException();
    return RemoteFile(bytes: Uint8List.fromList(data));
  }

  @override
  Future<void> put(
    Uri uri,
    Uint8List bytes, {
    required RemoteCredentials credentials,
    required SshHostVerifier verifyHost,
  }) async {
    await _check(credentials, verifyHost);
    files[uri.toString()] = Uint8List.fromList(bytes);
  }

  @override
  Future<List<RemoteEntry>> list(
    Uri uri, {
    required RemoteCredentials credentials,
    required SshHostVerifier verifyHost,
  }) async {
    await _check(credentials, verifyHost);
    return [
      for (final url in files.keys)
        RemoteEntry(
          name: Uri.parse(url).pathSegments.last,
          uri: Uri.parse(url),
          isDirectory: false,
        ),
    ];
  }
}
