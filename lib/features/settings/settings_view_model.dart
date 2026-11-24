import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/database/database_session.dart';
import '../../shared/security/biometric_key_store.dart';
import '../../shared/security/device_security.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/storage/file_storage.dart';
import '../../shared/storage/remote_cache.dart';
import '../file_select/recent_files.dart';

/// Impostazioni dell'app (AppPreferenceActivity di Keepass2Android).
final settingsViewModelProvider =
    NotifierProvider.autoDispose<SettingsViewModel, AppSettings>(
      SettingsViewModel.new,
    );

/// Versione pubblica dell'app, senza numero di build, letta dal sistema.
final settingsAppVersionProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(appSecurityProvider).getAppVersion(),
);

class SettingsViewModel extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(appSettingsProvider);

  /// Rimuove le sole copie locali già sincronizzate.
  Future<bool> clearSynchronizedRemoteCache() async {
    final running = ref.keepAlive();
    try {
      return await ref.read(remoteCacheStoreProvider).clearSynchronized();
    } finally {
      if (ref.mounted) ref.invalidate(remoteCacheAvailableProvider);
      running.close();
    }
  }

  /// Applica e salva [next]. Se "Ricorda file recenti" o "Ricorda file
  /// chiave" viene disattivato, l'elenco perde i file (o i file chiave) e i
  /// loro permessi; quelli del database aperto restano finché è aperto. Senza
  /// file recenti si disattiva anche lo sblocco biometrico di tutti i file.
  Future<void> update(AppSettings next) async {
    final previous = state;
    final recents = ref.read(recentFilesRepositoryProvider);
    final keep = <FileRef>{
      for (final session
          in ref.read(databaseSessionProvider.notifier).openSessions) ...[
        session.file,
        ?session.keyFile,
      ],
    };
    final settings = ref.read(appSettingsProvider.notifier);

    await settings.update(next);
    if (previous.rememberRecentFiles && !next.rememberRecentFiles) {
      await recents.clear(keep: keep);
      await ref.read(biometricKeyStoreProvider).removeAll();
    } else if (previous.rememberKeyFile && !next.rememberKeyFile) {
      await recents.forgetKeyFiles(keep: keep);
    } else {
      return;
    }
    if (ref.mounted) ref.invalidate(recentFilesProvider);
  }
}
