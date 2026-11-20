import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/storage/file_storage.dart';
import '../../shared/storage/remote_storage.dart';
import '../../shared/storage/webdav_client.dart';

/// Tipo di server: indirizzo della cartella iniziale come Keepass2Android
/// (`owncloud:` e `nextcloud:` di `WebDavFileStorage`).
enum RemoteServerType { webDav, nextcloud, ownCloud, sftp }

/// Cartella iniziale per [address] (`https://` se manca lo schema).
/// [InsecureRemoteException] per `http://`.
Uri remoteStartUri(RemoteServerType type, String address, String userName) {
  var text = address.trim();
  if (!text.contains('://')) {
    text = '${type == RemoteServerType.sftp ? 'sftp' : 'https'}://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
    throw const InvalidRemoteAddressException();
  }
  if (uri.scheme.toLowerCase() !=
      (type == RemoteServerType.sftp ? 'sftp' : 'https')) {
    throw const InsecureRemoteException();
  }
  final clean = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path.endsWith('/') ? uri.path : '${uri.path}/',
  );
  return switch (type) {
    RemoteServerType.webDav || RemoteServerType.sftp => clean,
    RemoteServerType.nextcloud => clean.resolve(
      'remote.php/dav/files/${Uri.encodeComponent(userName)}/',
    ),
    RemoteServerType.ownCloud => clean.resolve('remote.php/webdav/'),
  };
}

/// Stato di "Apri da server".
@immutable
class RemoteBrowserState {
  const RemoteBrowserState({
    this.root,
    this.directory,
    this.entries = const [],
    this.busy = false,
    this.error,
  });

  /// Cartella iniziale; `null` prima della connessione.
  final Uri? root;
  final Uri? directory;
  final List<RemoteEntry> entries;
  final bool busy;

  /// Ultimo errore, da mostrare con `describeRemoteError`.
  final Object? error;

  bool get connected => directory != null;

  bool get canGoUp =>
      directory != null && root != null && directory!.path != root!.path;

  RemoteBrowserState copyWith({
    Uri? root,
    Uri? directory,
    List<RemoteEntry>? entries,
    bool? busy,
    Object? error,
  }) => RemoteBrowserState(
    root: root ?? this.root,
    directory: directory ?? this.directory,
    entries: entries ?? this.entries,
    busy: busy ?? this.busy,
    error: error,
  );
}

/// Connessione a un server WebDAV, navigazione delle cartelle e scelta del
/// database (ADR-014).
final remoteOpenViewModelProvider =
    NotifierProvider.autoDispose<RemoteOpenViewModel, RemoteBrowserState>(
      RemoteOpenViewModel.new,
    );

class RemoteOpenViewModel extends Notifier<RemoteBrowserState> {
  RemoteCredentials? _credentials;
  bool _remember = true;

  @override
  RemoteBrowserState build() => const RemoteBrowserState();

  Future<void> connect({
    required RemoteServerType type,
    required String address,
    required RemoteCredentials credentials,
    required bool remember,
  }) async {
    if (state.busy) return;
    final Uri root;
    try {
      root = remoteStartUri(type, address, credentials.userName);
    } on Exception catch (e) {
      state = state.copyWith(error: e);
      return;
    }
    _credentials = credentials;
    _remember = remember;
    await _show(root, root: root);
  }

  Future<void> open(RemoteEntry entry) => _show(entry.uri);

  Future<void> up() async {
    final directory = state.directory;
    if (!state.canGoUp || directory == null) return;
    await _show(directory.resolve('..'));
  }

  /// Torna al modulo di connessione.
  void disconnect() {
    _credentials = null;
    state = const RemoteBrowserState();
  }

  /// Legge il file scelto per lo sblocco; `null` se non riesce (errore nello
  /// stato). Le credenziali restano nella sessione e si salvano solo se il
  /// file entra tra i recenti e l'utente ha scelto "ricorda".
  Future<PickedFile?> pick(RemoteEntry entry) async {
    final credentials = _credentials;
    if (credentials == null || state.busy) return null;
    final file = FileRef(uri: entry.uri.toString(), name: entry.name);
    ref.read(remoteSessionProvider).put(file, credentials, remember: _remember);
    state = state.copyWith(busy: true);
    try {
      final stored = await ref.read(fileStorageProvider).read(file);
      _credentials = null;
      if (ref.mounted) state = const RemoteBrowserState();
      return PickedFile(ref: file, bytes: stored.bytes);
    } on Exception catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, error: e);
      return null;
    }
  }

  Future<void> _show(Uri directory, {Uri? root}) async {
    final credentials = _credentials;
    if (credentials == null) return;
    state = state.copyWith(busy: true);
    try {
      final entries = await ref
          .read(remoteStorageProvider)
          .list(directory, credentials);
      if (!ref.mounted) return;
      state = state.copyWith(
        root: root,
        directory: directory,
        entries: entries,
        busy: false,
      );
    } on Exception catch (e) {
      if (ref.mounted) state = state.copyWith(busy: false, error: e);
    }
  }
}
