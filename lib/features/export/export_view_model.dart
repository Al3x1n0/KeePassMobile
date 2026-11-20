import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/database/database_session.dart';
import '../../shared/storage/file_storage.dart';

/// Nome proposto per la copia: `<nome>-copia.kdbx`.
String exportFileName(String databaseName) {
  final dot = databaseName.lastIndexOf('.');
  final stem = dot > 0 ? databaseName.substring(0, dot) : databaseName;
  return '${stem.isEmpty ? 'database' : stem}-copia.kdbx';
}

/// Export del database aperto (ExportDatabaseActivity di Keepass2Android,
/// formato KeePassKdb2x). Solo la copia KDBX cifrata con la stessa chiave:
/// XML e CSV in chiaro sono esclusi (decisione D7, SEC-02).
///
/// Lo stato è il nome del file esportato, `null` se l'utente ha annullato o
/// non ha ancora esportato, oppure l'errore.
final exportDatabaseViewModelProvider =
    AsyncNotifierProvider.autoDispose<ExportDatabaseViewModel, String?>(
      ExportDatabaseViewModel.new,
    );

class ExportDatabaseViewModel extends AsyncNotifier<String?> {
  @override
  FutureOr<String?> build() => null;

  /// Esporta e restituisce il nome del file creato; `null` se annullato o in
  /// caso di errore (nello stato).
  Future<String?> export() async {
    if (state.isLoading) return null;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(_export);
    if (ref.mounted) state = result;
    return result.value;
  }

  Future<String?> _export() async {
    final session = ref.read(databaseSessionProvider);
    if (session == null) throw const DatabaseLockedException();
    final storage = ref.read(fileStorageProvider);
    // Salvataggio di una copia in un isolate, verificato come ogni
    // salvataggio; il database aperto non cambia.
    final (_, bytes) = await saveDatabase(session.database, (_) {});
    if (!ref.mounted) return null;
    final file = await storage.create(
      suggestedName: exportFileName(session.file.name),
      bytes: bytes,
    );
    if (file == null) return null;
    // La copia non si riapre dall'app: niente permesso persistente inutile.
    await storage.release(file);
    return file.name;
  }
}
