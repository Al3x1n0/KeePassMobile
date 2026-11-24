import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/database/database_session.dart';
import '../../shared/security/biometric_key_store.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/storage/file_storage.dart';
import '../../shared/storage/preferences.dart';
import 'recent_files.dart';

/// Accesso nativo che mantiene disponibile la copia durante uno sblocco.
class DemoDatabaseAccess {
  DemoDatabaseAccess(this._storage);

  final FileStorage _storage;
  bool _released = false;

  /// Rilascia una sola volta l'accesso della sessione o dello sblocco fallito.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _storage.releaseDemoDatabase();
  }
}

/// Installazione una tantum e rimozione della copia privata del database demo.
class DemoDatabaseRepository {
  DemoDatabaseRepository(
    this._prefs,
    this._storage,
    this._recents,
    this._biometrics,
  );

  static const file = FileRef(
    uri: 'app-private:demo',
    name: 'Rifugio-Aurora.kdbx',
  );
  static const stateKey = 'demo_database.state';

  final SharedPreferences _prefs;
  final FileStorage _storage;
  final RecentFilesRepository _recents;
  final BiometricKeyStore _biometrics;
  Future<void>? _initializing;
  bool _disposed = false;
  bool _sessionOpen = false;
  DemoDatabaseAccess? _sessionAccess;

  /// Identifica solo la copia gestita dall'app, anche dopo la rimozione.
  bool isDemo(FileRef reference) => reference == file;

  /// Presenza della demo nell'elenco dei file recenti.
  bool get isPresent => _recents.load().any((f) => isDemo(f.database));

  /// Rimozione definitiva già richiesta dall'utente.
  bool get isRemoved => _prefs.getString(stateKey) == 'removed';

  /// Mantiene il file disponibile anche se un altro motore lo rimuove.
  Future<DemoDatabaseAccess> acquireForUnlock() async {
    if (!await _storage.retainDemoDatabase()) {
      await refreshRemovalState();
      throw const FileUnavailableException();
    }
    return DemoDatabaseAccess(_storage);
  }

  /// Trasferisce l'accesso alla sessione aperta o lo rilascia dopo l'errore.
  Future<void> finishOpening(DemoDatabaseAccess access) async {
    if (!_disposed && _sessionOpen && _sessionAccess == null) {
      _sessionAccess = access;
    } else {
      await access.release();
    }
  }

  /// Aggiorna le sessioni di questo motore e rilascia il file alla chiusura.
  void sessionsChanged(Set<FileRef> keep) {
    _sessionOpen = keep.contains(file);
    if (!_sessionOpen) unawaited(_releaseSession());
    unawaited(_cleanup(this, keep));
  }

  /// Rilascia l'accesso quando il contenitore dei provider viene chiuso.
  void dispose() {
    _disposed = true;
    _sessionOpen = false;
    unawaited(_releaseSession());
  }

  Future<void> _releaseSession() async {
    final access = _sessionAccess;
    _sessionAccess = null;
    try {
      await access?.release();
    } on Object {
      // Il distacco del motore nativo rilascia anche gli accessi residui.
    }
  }

  /// Rilegge la rimozione condivisa anche con il motore Android Autofill.
  Future<bool> refreshRemovalState({Set<FileRef> keep = const {}}) async {
    if (!await _storage.isDemoDatabaseRemoved()) return isRemoved;
    await _prefs.reload();
    await _setState('removed');
    if (!AppSettingsRepository(_prefs).load().rememberRecentFiles) {
      await _recents.clear(keep: keep);
      await _biometrics.removeAll();
    } else {
      await _recents.forget(file, keep: keep);
      await _biometrics.remove(file);
    }
    return true;
  }

  /// Prepara la demo prima di mostrare la scelta dei database nell'app.
  ///
  /// Lo stato viene completato dopo l'inserimento nei recenti. La copia
  /// nativa non sovrascrive mai un file esistente, anche dopo un'interruzione.
  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    await _prefs.reload();
    if (isRemoved) {
      await remove();
      return;
    }
    if (_prefs.getString(stateKey) == 'ready') return;
    // Un aggiornamento rispetta anche la scelta precedente di non ricordare
    // file: la demo non riattiva questa impostazione.
    if (!AppSettingsRepository(_prefs).load().rememberRecentFiles) {
      await remove();
      return;
    }
    final asset = await rootBundle.load('assets/demo/${file.name}');
    final installed = await _storage.ensureDemoDatabase(
      Uint8List.sublistView(asset),
    );
    if (installed == null) {
      await remove();
      return;
    }
    if (!isPresent) {
      await _recents.remember(RecentFile(database: installed));
    }
    await _setState('ready');
  }

  /// Dimentica definitivamente la demo e la sua chiave biometrica.
  ///
  /// I file in [keep] appartengono a sessioni ancora aperte: la cancellazione
  /// fisica viene completata alla chiusura o al prossimo avvio.
  Future<void> remove({Set<FileRef> keep = const {}}) async {
    await _setState('removed');
    await _storage.deleteDemoDatabase(keepFile: true);
    await _recents.forget(file, keep: keep);
    await _biometrics.remove(file);
    await cleanup(keep: keep);
  }

  /// Completa la cancellazione richiesta quando la demo non è più aperta.
  Future<void> cleanup({Set<FileRef> keep = const {}}) async {
    if (isRemoved && !keep.contains(file)) {
      await _storage.deleteDemoDatabase();
    }
  }

  Future<void> _setState(String value) async {
    if (!await _prefs.setString(stateKey, value)) {
      throw const RecentFilesWriteException();
    }
  }
}

final demoDatabaseRepositoryProvider = Provider<DemoDatabaseRepository>((ref) {
  final repository = DemoDatabaseRepository(
    ref.watch(sharedPreferencesProvider),
    ref.watch(fileStorageProvider),
    ref.watch(recentFilesRepositoryProvider),
    ref.watch(biometricKeyStoreProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Pulizia della demo rimossa dopo chiusura, cambio o blocco delle sessioni.
final demoDatabaseCleanupProvider = Provider<void>((ref) {
  final demo = ref.watch(demoDatabaseRepositoryProvider);
  ref.listen(databaseSessionProvider, (_, _) {
    final keep = {
      for (final session
          in ref.read(databaseSessionProvider.notifier).openSessions)
        session.file,
    };
    demo.sessionsChanged(keep);
  }, fireImmediately: true);
});

Future<void> _cleanup(DemoDatabaseRepository demo, Set<FileRef> keep) async {
  try {
    await demo.cleanup(keep: keep);
  } on Object {
    // La rimozione resta persistente; il prossimo avvio completa la pulizia.
  }
}

/// Esegue il bootstrap senza impedire l'apertura dei database dell'utente.
Future<void> initializeDemoDatabase(SharedPreferences preferences) async {
  const storage = FileStorage();
  try {
    await DemoDatabaseRepository(
      preferences,
      storage,
      RecentFilesRepository(preferences, storage),
      BiometricKeyStore(preferences),
    ).initialize();
  } on Object {
    // Nessun dato dell'utente viene sovrascritto in caso di errore. Lo stato
    // incompleto consente di riprendere il bootstrap al prossimo avvio.
  }
}
