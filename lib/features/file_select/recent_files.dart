import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/security/biometric_key_store.dart';
import '../../shared/storage/file_storage.dart';
import '../../shared/storage/preferences.dart';
import '../../shared/database/database_session.dart';
import 'demo_database.dart';

/// Database aperto di recente, con il file chiave usato (come
/// Keepass2Android, opzione "ricorda file chiave" attiva di default).
@immutable
class RecentFile {
  const RecentFile({required this.database, this.keyFile});

  final FileRef database;
  final FileRef? keyFile;

  Map<String, Object> toJson() => {
    'database': database.toJson(),
    if (keyFile case final key?) 'keyFile': key.toJson(),
  };

  /// `null` se [json] non ha la forma attesa.
  static RecentFile? fromJson(Object? json) {
    if (json is! Map) return null;
    final database = FileRef.fromJson(json['database']);
    if (database == null) return null;
    return RecentFile(
      database: database,
      keyFile: FileRef.fromJson(json['keyFile']),
    );
  }
}

/// Le preferenze non hanno conservato i nuovi riferimenti: permessi invariati.
final class RecentFilesWriteException implements Exception {
  const RecentFilesWriteException();
}

/// Elenco dei file recenti, dal più recente, senza duplicati.
///
/// Contiene solo riferimenti ai file, mai password o chiavi (SEC-03). Quando
/// un file non è più citato da nessuna voce, rilascia il permesso persistente
/// (Android ne concede un numero limitato).
class RecentFilesRepository {
  RecentFilesRepository(this._prefs, this._storage);

  static const storageKey = 'recent_files';

  final SharedPreferences _prefs;
  final FileStorage _storage;

  List<RecentFile> load() => List.unmodifiable([
    for (final raw in _prefs.getStringList(storageKey) ?? const <String>[])
      ?_decode(raw),
  ]);

  /// Mette [file] in cima. [replacing] è il riferimento precedente dello
  /// stesso database, quando il sistema lo ha aggiornato.
  Future<List<RecentFile>> remember(
    RecentFile file, {
    FileRef? replacing,
    Set<FileRef> keep = const {},
  }) {
    // Uno sblocco iniziato prima della conferma non deve reinserire la demo.
    if (file.database == DemoDatabaseRepository.file &&
        _prefs.getString(DemoDatabaseRepository.stateKey) == 'removed') {
      return Future.value(load());
    }
    return _save([
      file,
      ...load().where(
        (f) => f.database != file.database && f.database != replacing,
      ),
    ], keep: keep);
  }

  Future<List<RecentFile>> forget(
    FileRef database, {
    Set<FileRef> keep = const {},
  }) => _save(load().where((f) => f.database != database).toList(), keep: keep);

  /// Svuota l'elenco ("Ricorda file recenti" disattivato). I file in [keep]
  /// (quelli del database aperto) conservano il permesso.
  Future<List<RecentFile>> clear({Set<FileRef> keep = const {}}) =>
      _save(const [], keep: keep);

  /// Toglie i file chiave da tutte le voci ("Ricorda file chiave"
  /// disattivato). I file in [keep] conservano il permesso.
  Future<List<RecentFile>> forgetKeyFiles({Set<FileRef> keep = const {}}) =>
      _save([
        for (final f in load()) RecentFile(database: f.database),
      ], keep: keep);

  /// Rilascia il permesso dei [files] che l'elenco non cita (database chiuso
  /// senza essere stato ricordato).
  Future<void> releaseUnused(Iterable<FileRef> files) async {
    final used = _refs(load());
    for (final file in files.toSet().difference(used)) {
      await _storage.release(file);
    }
  }

  Future<List<RecentFile>> _save(
    List<RecentFile> files, {
    Set<FileRef> keep = const {},
  }) async {
    final before = _refs(load());
    if (!await _prefs.setStringList(storageKey, [
      for (final f in files) jsonEncode(f.toJson()),
    ])) {
      throw const RecentFilesWriteException();
    }
    for (final unused in before.difference(_refs(files)).difference(keep)) {
      await _storage.release(unused);
    }
    return List.unmodifiable(files);
  }

  static Set<FileRef> _refs(List<RecentFile> files) => {
    for (final f in files) ...[f.database, ?f.keyFile],
  };

  static RecentFile? _decode(String raw) {
    try {
      return RecentFile.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }
}

final recentFilesRepositoryProvider = Provider<RecentFilesRepository>(
  (ref) => RecentFilesRepository(
    ref.watch(sharedPreferencesProvider),
    ref.watch(fileStorageProvider),
  ),
);

/// File recenti mostrati nella schermata di apertura.
final recentFilesProvider =
    NotifierProvider.autoDispose<RecentFilesViewModel, List<RecentFile>>(
      RecentFilesViewModel.new,
    );

class RecentFilesViewModel extends Notifier<List<RecentFile>> {
  @override
  List<RecentFile> build() => ref.watch(recentFilesRepositoryProvider).load();

  /// Toglie [file] dall'elenco e ne disattiva lo sblocco biometrico.
  Future<void> forget(RecentFile file) async {
    final demo = ref.read(demoDatabaseRepositoryProvider);
    final recents = ref.read(recentFilesRepositoryProvider);
    final biometrics = ref.read(biometricKeyStoreProvider);
    if (demo.isDemo(file.database)) {
      final keep = {
        for (final session
            in ref.read(databaseSessionProvider.notifier).openSessions) ...[
          session.file,
          ?session.keyFile,
        ],
      };
      await demo.remove(keep: keep);
      if (ref.mounted) state = recents.load();
      return;
    }
    final files = await recents.forget(file.database);
    await biometrics.remove(file.database);
    if (ref.mounted) state = files;
  }
}
