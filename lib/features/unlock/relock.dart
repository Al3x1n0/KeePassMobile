import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/database/database_session.dart';
import '../../shared/storage/file_storage.dart';
import '../file_select/recent_files.dart';
import '../password_generator/pending_generated_password.dart';
import 'unlock_view_model.dart';

/// Sblocco da mostrare dopo un blocco ("Blocca database", inattività, schermo
/// spento): lo stesso database dei file recenti, con il file chiave ricordato
/// (decisione D22, ADR-011, al posto di QuickUnlock). La schermata di scelta
/// del file lo apre subito; con la biometria attiva la richiesta parte da sola.
///
/// Il blocco elimina tutte le chiavi. Solo nel blocco automatico può restare
/// la password della tab Genera, separata dalle credenziali del database.
final relockProvider = NotifierProvider<RelockNotifier, UnlockArgs?>(
  RelockNotifier.new,
);

class RelockNotifier extends Notifier<UnlockArgs?> {
  @override
  UnlockArgs? build() => null;

  /// Blocca il database aperto. Se è tra i file recenti, dopo il blocco si
  /// torna al suo sblocco; altrimenti alla scelta del file (il permesso sul
  /// file non ricordato viene rilasciato).
  void lockAndReturn({bool automatic = false}) {
    final session = ref.read(databaseSessionProvider);
    if (session == null) return;
    final pending = ref.read(pendingGeneratedPasswordProvider.notifier);
    if (automatic) {
      pending.prepareAutomaticLock(session.file);
    } else {
      pending.clear();
    }
    final recent = ref
        .read(recentFilesRepositoryProvider)
        .load()
        .where((f) => f.database == session.file)
        .firstOrNull;
    // Prima del blocco: la scelta del file lo trova appena il router la apre.
    state = switch (recent) {
      final r? => UnlockArgs(
        database: PickedFile(ref: r.database),
        keyFile: switch (r.keyFile) {
          final key? => PickedFile(ref: key),
          null => null,
        },
      ),
      null => null,
    };
    ref
        .read(databaseSessionProvider.notifier)
        .lock(
          preserveGeneratedClipboard:
              automatic && pending.valueFor(session.file) != null,
        );
  }

  /// Sblocco da mostrare, una volta sola.
  UnlockArgs? take() {
    final args = state;
    state = null;
    return args;
  }

  void clear() => state = null;
}
