import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/routes.dart';
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
  String _activeTab = AppRoutes.database;
  FileRef? _resumeFile;
  String? _resumeTab;
  bool _automaticLockPrepared = false;

  @override
  UnlockArgs? build() {
    ref.listen(databaseSessionProvider, (previous, next) {
      if (next == null) {
        if (!_automaticLockPrepared) _clearResume();
        _automaticLockPrepared = false;
        _activeTab = AppRoutes.database;
      } else if (previous?.file != next.file && _resumeFile != next.file) {
        _clearResume();
      }
    });
    return null;
  }

  /// Ricorda solo le quattro tab principali, senza URL di voci o gruppi.
  void rememberTab(String location) {
    if (location == AppRoutes.database ||
        location == AppRoutes.generate ||
        location == AppRoutes.check ||
        location == AppRoutes.appSettingsInDatabase) {
      _activeTab = location;
    }
  }

  /// Consuma il ritorno alla tab lasciata, solo per lo stesso database.
  String? takeRestoreDestination(FileRef file) {
    final destination = _resumeFile == file ? _resumeTab : null;
    _clearResume();
    return destination;
  }

  void _clearResume() {
    _resumeFile = null;
    _resumeTab = null;
    _automaticLockPrepared = false;
  }

  /// Blocca il database aperto. Se è tra i file recenti, dopo il blocco si
  /// torna al suo sblocco; altrimenti alla scelta del file (il permesso sul
  /// file non ricordato viene rilasciato).
  void lockAndReturn({bool automatic = false}) {
    final session = ref.read(databaseSessionProvider);
    if (session == null) return;
    final pending = ref.read(pendingGeneratedPasswordProvider.notifier);
    if (automatic) {
      _resumeFile = session.file;
      _resumeTab = _activeTab;
      _automaticLockPrepared = true;
      pending.prepareAutomaticLock(session.file);
    } else {
      _clearResume();
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

  void clear() {
    _clearResume();
    state = null;
  }
}
