import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../../shared/security/biometric_key_store.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/storage/file_storage.dart';
import '../file_select/recent_files.dart';

/// Nuova chiave principale, come SetPassword.cs di Keepass2Android: chiave
/// composta con la chiave grezza (il salvataggio rifà la KDF con un salt
/// nuovo) e `MasterKeyChanged` adesso. [password] vuota: solo [keyFile].
DatabaseEdit changeMasterKeyEdit({
  required String password,
  Uint8List? keyFile,
}) => (database) {
  database.header.credentials = KdbxCredentials(
    password: password.isEmpty ? null : ProtectedData.fromString(password),
    keyData: keyFile,
  );
  database.meta.keyChanged = KdbxTime.now();
};

/// Cambio della chiave principale (SetPasswordDialog di Keepass2Android).
final changeMasterKeyViewModelProvider =
    AsyncNotifierProvider.autoDispose<ChangeMasterKeyViewModel, void>(
      ChangeMasterKeyViewModel.new,
    );

class ChangeMasterKeyViewModel extends AsyncNotifier<void> {
  bool _biometricDisabled = false;

  @override
  FutureOr<void> build() {}

  /// `true` se l'ultimo cambio ha disattivato lo sblocco biometrico: la
  /// chiave derivata salvata non apre più il file (ADR-008).
  bool get biometricDisabled => _biometricDisabled;

  /// Cambia la chiave e salva. `true` se riuscito; l'errore resta nello stato.
  Future<bool> change({required String password, PickedFile? keyFile}) async {
    if (state.isLoading) return false;
    _biometricDisabled = false;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() => _change(password, keyFile));
    if (ref.mounted) state = result;
    return !result.hasError;
  }

  Future<void> _change(String password, PickedFile? keyFile) async {
    final storage = ref.read(fileStorageProvider);
    final session = ref.read(databaseSessionProvider);
    if (session == null) throw const DatabaseLockedException();
    Uint8List? keyBytes;
    if (keyFile != null) {
      try {
        keyBytes = keyFile.bytes ?? (await storage.read(keyFile.ref)).bytes;
      } on FileUnavailableException {
        throw const KeyFileUnavailableException();
      }
    }
    final recents = ref.read(recentFilesRepositoryProvider);
    final settings = ref.read(appSettingsProvider);

    await ref
        .read(databaseSessionProvider.notifier)
        .apply(
          changeMasterKeyEdit(password: password, keyFile: keyBytes),
          keyFile: keyFile?.ref,
        );

    final biometrics = ref.read(biometricKeyStoreProvider);
    if (biometrics.isEnabled(session.file)) {
      await biometrics.remove(session.file);
      _biometricDisabled = true;
    }

    // Il file chiave ricordato per questo database diventa quello nuovo.
    if (settings.rememberRecentFiles &&
        recents.load().any((f) => f.database == session.file)) {
      await recents.remember(
        RecentFile(
          database: session.file,
          keyFile: settings.rememberKeyFile ? keyFile?.ref : null,
        ),
      );
    }
  }
}
