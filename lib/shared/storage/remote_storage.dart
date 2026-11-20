import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_storage.dart';
import 'preferences.dart';
import 'sftp_client.dart';
import 'webdav_client.dart';

/// Credenziali degli storage remoti nel Keystore (Android) e nel Keychain
/// (iOS), senza biometria (D30, ADR-014), in un archivio separato da quello
/// delle chiavi biometriche. Una voce per file, indicata dall'hash del
/// riferimento: nessun indirizzo o nome nell'archivio (SEC-01).
class RemoteCredentialStore {
  RemoteCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _namespace = 'kpm_remote_credentials';

  final FlutterSecureStorage _storage;

  static const _android = AndroidOptions(
    storageNamespace: _namespace,
    migrateOnAlgorithmChange: false,
  );

  static const _ios = IOSOptions(
    accountName: _namespace,
    accessibility: KeychainAccessibility.unlocked_this_device,
  );

  static String keyOf(FileRef file) =>
      'remote:${sha256.convert(utf8.encode(file.uri))}';

  /// `null` se non ci sono o non si leggono (archivio non disponibile).
  Future<RemoteCredentials?> read(FileRef file) async {
    try {
      final raw = await _storage.read(
        key: keyOf(file),
        aOptions: _android,
        iOptions: _ios,
      );
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json case {'u': final String user, 'p': final String secret}) {
        return RemoteCredentials(
          userName: user,
          password: secret,
          privateKey: json['k'] is String ? json['k'] as String : null,
        );
      }
    } on PlatformException {
      // Archivio illeggibile: le credenziali si chiedono di nuovo.
    } on FormatException {
      // Valore illeggibile: come se non ci fosse.
    }
    return null;
  }

  /// `false` se l'archivio non le accetta: si chiederanno di nuovo.
  Future<bool> write(FileRef file, RemoteCredentials credentials) async {
    try {
      await _storage.write(
        key: keyOf(file),
        value: jsonEncode({
          'u': credentials.userName,
          'p': credentials.password,
          'k': ?credentials.privateKey,
        }),
        aOptions: _android,
        iOptions: _ios,
      );
      return true;
    } on PlatformException {
      return false;
    }
  }

  Future<void> remove(FileRef file) async {
    try {
      await _storage.delete(
        key: keyOf(file),
        aOptions: _android,
        iOptions: _ios,
      );
    } on PlatformException {
      // Già assenti o archivio non disponibile.
    }
  }
}

/// Certificati non validi per il sistema accettati dall'utente (D31): impronte
/// SHA-256 per `host:porta`. Non sono segreti.
class RemoteTrustRepository {
  RemoteTrustRepository(this._prefs);

  static const storageKey = 'remote.trusted_certificates';

  final SharedPreferences _prefs;

  Set<String> fingerprints(String server) => {
    ...?(_all()[server] as List?)?.whereType<String>(),
  };

  Future<void> trust(String server, String fingerprint) => _prefs.setString(
    storageKey,
    jsonEncode(
      _all()..[server] = {...fingerprints(server), fingerprint}.toList(),
    ),
  );

  /// Chiave SSH confermata per host e porta; archivio separato da HTTPS.
  String? sshHost(String server) => _sshHosts()[server];

  Map<String, String> _sshHosts() {
    final raw = _prefs.getString('remote.trusted_ssh_hosts');
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic> ||
          json.values.any((v) => v is! String)) {
        throw const SshHostKeyChangedException();
      }
      return json.cast<String, String>();
    } on FormatException {
      throw const SshHostKeyChangedException();
    }
  }

  /// Non sostituisce mai una chiave già conosciuta con una diversa.
  Future<void> trustSshHost(String server, String key) async {
    final all = _sshHosts();
    if (all[server] != null && all[server] != key) {
      throw const SshHostKeyChangedException();
    }
    all[server] = key;
    if (!await _prefs.setString('remote.trusted_ssh_hosts', jsonEncode(all))) {
      throw const RemoteSftpException();
    }
  }

  Map<String, Object?> _all() {
    try {
      final json = jsonDecode(_prefs.getString(storageKey) ?? '{}');
      return json is Map<String, Object?> ? {...json} : {};
    } on FormatException {
      return {};
    }
  }
}

/// Risposta alla richiesta delle credenziali.
@immutable
class RemoteCredentialsAnswer {
  const RemoteCredentialsAnswer({
    required this.credentials,
    required this.remember,
  });

  final RemoteCredentials credentials;

  /// "Ricorda le credenziali": si salvano quando il file entra tra i recenti.
  final bool remember;
}

/// Chiede all'utente le credenziali per [file]; con [failed] quelle di prima
/// ([previous]) sono state rifiutate. `null` se annulla.
typedef RemoteCredentialsPrompt = Future<RemoteCredentialsAnswer?> Function(
  FileRef file, {
  RemoteCredentials? previous,
  bool failed,
});

/// Chiede se accettare il certificato di [server] con impronta [fingerprint].
typedef CertificateTrustPrompt = Future<bool> Function(
  String server,
  String fingerprint,
);

/// L'app le sostituisce con le finestre di dialogo; senza, nessuna credenziale
/// e nessun certificato non valido.
final remoteCredentialsPromptProvider = Provider<RemoteCredentialsPrompt>(
  (_) =>
      (_, {previous, failed = false}) async => null,
);

final sshHostTrustPromptProvider = Provider<CertificateTrustPrompt>(
  (_) =>
      (_, _) async => false,
);

final certificateTrustPromptProvider = Provider<CertificateTrustPrompt>(
  (_) =>
      (_, _) async => false,
);

/// Credenziali in uso per i file remoti aperti in questa sessione. Si
/// svuotano alla chiusura del database: con "non ricordare" si chiedono alla
/// prossima apertura.
class RemoteSession {
  final _entries = <String, RemoteSessionEntry>{};

  RemoteCredentials? credentialsOf(FileRef file) =>
      _entries[file.uri]?.credentials;

  void put(
    FileRef file,
    RemoteCredentials credentials, {
    required bool remember,
    bool stored = false,
    bool persistOnSuccess = false,
  }) => _entries[file.uri] = RemoteSessionEntry(
    credentials,
    remember: remember,
    stored: stored,
    persistOnSuccess: persistOnSuccess,
  );

  RemoteSessionEntry? entryOf(FileRef file) => _entries[file.uri];

  void remove(FileRef file) => _entries.remove(file.uri);

  void clear() => _entries.clear();
}

/// Credenziali di un file nella sessione.
class RemoteSessionEntry {
  RemoteSessionEntry(
    this.credentials, {
    required this.remember,
    required this.stored,
    required this.persistOnSuccess,
  });

  final RemoteCredentials credentials;
  final bool remember;

  /// Già nell'archivio (lette da lì o salvate con [RemoteStorage.commit]).
  bool stored;

  /// Credenziali nuove per un file già ricordato: si salvano appena il server
  /// le accetta.
  bool persistOnSuccess;
}

/// File su server remoti (WebDAV su `https://` e SFTP, ADR-014/015): credenziali
/// dalla sessione, dall'archivio o dall'utente; certificati non validi solo se
/// accettati (D31).
class RemoteStorage {
  RemoteStorage({
    required this.client,
    this.sftp = const SftpStorageClient(),
    this.askSshTrust,
    required this.store,
    required this.session,
    required this.trust,
    required this.askCredentials,
    required this.askTrust,
  });

  final WebDavClient client;
  final SftpStorageClient sftp;
  final CertificateTrustPrompt? askSshTrust;
  final RemoteCredentialStore store;
  final RemoteSession session;
  final RemoteTrustRepository trust;
  final RemoteCredentialsPrompt askCredentials;
  final CertificateTrustPrompt askTrust;

  /// Tentativi con credenziali nuove dopo un rifiuto del server.
  static const maxCredentialAttempts = 3;

  /// `true` per i riferimenti remoti HTTPS o SFTP.
  static bool handles(FileRef file) => const {
    'https',
    'sftp',
  }.contains(Uri.tryParse(file.uri)?.scheme.toLowerCase());

  Future<Uint8List> read(FileRef file) async => (await readFile(file)).bytes;

  /// Contenuto e versione della stessa lettura, per il salvataggio condizionato.
  Future<RemoteFile> readFile(FileRef file) => _withCredentials(
    file,
    (credentials) => Uri.parse(file.uri).scheme == 'sftp'
        ? sftp.get(
            Uri.parse(file.uri),
            credentials: credentials,
            verifyHost: (type, fp) => _verifySsh(Uri.parse(file.uri), type, fp),
          )
        : client.get(
            Uri.parse(file.uri),
            credentials: credentials,
            trusted: _trusted(file),
          ),
  );

  Future<RemoteFile> readFileWithoutRedirects(FileRef file) => _withCredentials(
    file,
    (credentials) => Uri.parse(file.uri).scheme == 'sftp'
        ? sftp.get(
            Uri.parse(file.uri),
            credentials: credentials,
            verifyHost: (type, fp) => _verifySsh(Uri.parse(file.uri), type, fp),
          )
        : client.getWithoutRedirects(
            Uri.parse(file.uri),
            credentials: credentials,
            trusted: _trusted(file),
          ),
  );

  Future<void> write(
    FileRef file,
    Uint8List bytes, {
    String? expectedVersion,
  }) => _withCredentials(
    file,
    (credentials) => Uri.parse(file.uri).scheme == 'sftp'
        ? sftp.put(
            Uri.parse(file.uri),
            bytes,
            credentials: credentials,
            verifyHost: (type, fp) => _verifySsh(Uri.parse(file.uri), type, fp),
          )
        : client.put(
            Uri.parse(file.uri),
            bytes,
            credentials: credentials,
            trusted: _trusted(file),
            ifMatch: expectedVersion,
          ),
  );

  /// Contenuto di [directory] con le credenziali del modulo "Apri da server".
  Future<List<RemoteEntry>> list(
    Uri directory,
    RemoteCredentials credentials,
  ) => directory.scheme == 'sftp'
      ? sftp.list(
          directory,
          credentials: credentials,
          verifyHost: (type, fp) => _verifySsh(directory, type, fp),
        )
      : _withTrust(
          directory,
          () => client.list(
            directory,
            credentials: credentials,
            trusted: trust.fingerprints(serverOf(directory)),
          ),
        );

  Future<bool> _verifySsh(Uri uri, String type, String fingerprint) async {
    final server = serverOf(uri);
    final key = '$type $fingerprint';
    final known = trust.sshHost(server);
    if (known != null) {
      if (known != key) throw const SshHostKeyChangedException();
      return true;
    }
    if (!await (askSshTrust?.call(server, key) ?? Future.value(false))) {
      return false;
    }
    await trust.trustSshHost(server, key);
    return true;
  }

  /// Il file è entrato tra i recenti: se l'utente ha scelto "ricorda", le
  /// credenziali in uso vanno nell'archivio.
  Future<void> commit(FileRef file) async {
    final entry = session.entryOf(file);
    if (entry == null) return;
    if (!entry.remember) {
      await store.remove(file);
      entry.stored = false;
      return;
    }
    if (entry.stored) return;
    entry.stored = await store.write(file, entry.credentials);
  }

  /// Il file non è più tra i recenti: credenziali dimenticate.
  Future<void> release(FileRef file) async {
    session.remove(file);
    await store.remove(file);
  }

  Set<String> _trusted(FileRef file) =>
      trust.fingerprints(serverOf(Uri.parse(file.uri)));

  Future<T> _withCredentials<T>(
    FileRef file,
    Future<T> Function(RemoteCredentials credentials) operation,
  ) async {
    var credentials = session.credentialsOf(file);
    if (credentials == null) {
      final stored = await store.read(file);
      if (stored != null) {
        session.put(file, stored, remember: true, stored: true);
        credentials = stored;
      } else {
        credentials = await _ask(file);
      }
    }
    for (var attempt = 1; ; attempt++) {
      try {
        final result = await _withTrust(
          Uri.parse(file.uri),
          () => operation(credentials!),
        );
        final entry = session.entryOf(file);
        if (entry != null && entry.persistOnSuccess) {
          entry
            ..persistOnSuccess = false
            ..stored = await store.write(file, entry.credentials);
        }
        return result;
      } on RemoteAuthException {
        final wasStored = session.entryOf(file)?.stored ?? false;
        session.remove(file);
        if (wasStored) await store.remove(file);
        if (attempt >= maxCredentialAttempts) rethrow;
        credentials = await _ask(
          file,
          previous: credentials,
          failed: true,
          stored: wasStored,
        );
      }
    }
  }

  Future<RemoteCredentials> _ask(
    FileRef file, {
    RemoteCredentials? previous,
    bool failed = false,
    bool stored = false,
  }) async {
    final answer = await askCredentials(
      file,
      previous: previous,
      failed: failed,
    );
    if (answer == null) throw const RemoteCanceledException();
    // Un file che era già ricordato resta ricordato con le credenziali nuove.
    session.put(
      file,
      answer.credentials,
      remember: answer.remember,
      persistOnSuccess: stored && answer.remember,
    );
    return answer.credentials;
  }

  /// Ripete [operation] una volta se l'utente accetta il certificato.
  Future<T> _withTrust<T>(Uri uri, Future<T> Function() operation) async {
    try {
      return await operation();
    } on UntrustedCertificateException catch (e) {
      if (!await askTrust(e.server, e.fingerprint)) {
        throw const RemoteCanceledException();
      }
      await trust.trust(e.server, e.fingerprint);
      return operation();
    }
  }
}

final sftpClientProvider = Provider<SftpStorageClient>(
  (_) => const SftpStorageClient(),
);

final webDavClientProvider = Provider<WebDavClient>(
  (_) => const WebDavClient(),
);

final remoteCredentialStoreProvider = Provider<RemoteCredentialStore>(
  (_) => RemoteCredentialStore(),
);

final remoteSessionProvider = Provider<RemoteSession>((_) => RemoteSession());

final remoteTrustRepositoryProvider = Provider<RemoteTrustRepository>(
  (ref) => RemoteTrustRepository(ref.watch(sharedPreferencesProvider)),
);

final remoteStorageProvider = Provider<RemoteStorage>(
  (ref) => RemoteStorage(
    client: ref.watch(webDavClientProvider),
    sftp: ref.watch(sftpClientProvider),
    askSshTrust: (server, fp) =>
        ref.read(sshHostTrustPromptProvider)(server, fp),
    store: ref.watch(remoteCredentialStoreProvider),
    session: ref.watch(remoteSessionProvider),
    trust: ref.watch(remoteTrustRepositoryProvider),
    askCredentials: (file, {previous, failed = false}) => ref.read(
      remoteCredentialsPromptProvider,
    )(file, previous: previous, failed: failed),
    askTrust: (server, fingerprint) =>
        ref.read(certificateTrustPromptProvider)(server, fingerprint),
  ),
);

/// Chiave privata letta tramite il selettore, senza conservare il permesso.
final sshKeyPickerProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final picked = await ref.read(filePickerServiceProvider).pick();
    if (picked == null) return null;
    final storage = ref.read(fileStorageProvider);
    try {
      final bytes = picked.bytes ?? (await storage.read(picked.ref)).bytes;
      if (bytes.length > 65536) throw const InvalidSshKeyException();
      return utf8.decode(bytes);
    } finally {
      await storage.release(picked.ref);
    }
  },
);
