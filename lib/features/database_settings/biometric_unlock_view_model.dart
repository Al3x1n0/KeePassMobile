import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/database/database_session.dart';
import '../../shared/security/biometric_key_store.dart';

/// "Sblocco biometrico" del database aperto (FingerprintSetupActivity di
/// Keepass2Android). Lo stato dice se è attivo.
final biometricUnlockViewModelProvider =
    AsyncNotifierProvider.autoDispose<BiometricUnlockViewModel, bool>(
      BiometricUnlockViewModel.new,
    );

class BiometricUnlockViewModel extends AsyncNotifier<bool> {
  @override
  FutureOr<bool> build() {
    final file = ref.watch(databaseSessionProvider.select((s) => s?.file));
    return file != null && ref.read(biometricKeyStoreProvider).isEnabled(file);
  }

  /// Salva la chiave derivata della sessione, dopo la richiesta biometrica
  /// [texts]; da qui la sessione usa solo quella (ADR-008). Se l'utente
  /// annulla resta disattivo, senza errore.
  Future<void> enable(BiometricPromptTexts texts) async {
    final session = ref.read(databaseSessionProvider);
    final key = session?.database.header.transformedKey;
    if (state.isLoading || session == null || key == null) return;
    state = const AsyncLoading();
    final notifier = ref.read(databaseSessionProvider.notifier);
    final store = ref.read(biometricKeyStoreProvider);
    final result = await AsyncValue.guard(() async {
      // Un salvataggio in corso renderebbe vecchia la chiave.
      if (notifier.isSaving) throw const DatabaseBusyException();
      await store.store(session.file, key, texts: texts);
      // Solo dopo la conferma: se l'utente annulla, la sessione conserva la
      // chiave completa e la KDF resta modificabile.
      try {
        notifier.useTransformedKeyOnly();
      } on Exception {
        // Database bloccato durante la richiesta biometrica.
        await store.remove(session.file);
        rethrow;
      }
      return true;
    });
    if (!ref.mounted) return;
    state = switch (result) {
      AsyncError(
        error: BiometricKeyException(reason: BiometricKeyError.canceled),
      ) =>
        const AsyncData(false),
      _ => result,
    };
  }

  /// Toglie la chiave salvata. La sessione resta con la sola chiave derivata
  /// fino al blocco.
  Future<void> disable() async {
    final session = ref.read(databaseSessionProvider);
    if (state.isLoading || session == null) return;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      final store = ref.read(biometricKeyStoreProvider);
      await store.remove(session.file);
      // Scelta esplicita: non riproporla dopo il prossimo sblocco.
      await store.declineOffer(session.file);
      return false;
    });
    if (ref.mounted) state = result;
  }
}
