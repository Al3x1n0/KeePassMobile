import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/external_change.dart';
import '../../shared/security/biometric_key_store.dart';
import '../../shared/security/device_security.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/storage/file_storage.dart';
import '../../shared/storage/remote_cache.dart';
import '../../shared/storage/remote_storage.dart';
import '../file_select/recent_files.dart';

/// Database da sbloccare e file chiave proposto (dai file recenti).
@immutable
class UnlockArgs {
  const UnlockArgs({
    required this.database,
    this.keyFile,
    this.offline = false,
    this.replacing,
    this.additional = false,
    this.lockGeneration,
  });

  final PickedFile database;
  final PickedFile? keyFile;
  final bool offline;

  /// Riferimento perso da sostituire soltanto dopo uno sblocco riuscito.
  final FileRef? replacing;
  final bool additional;
  final int? lockGeneration;
}

/// Sblocco del database (PasswordActivity di Keepass2Android).
///
/// Lo stato è `AsyncLoading` durante la KDF e `AsyncError` con l'errore
/// tipizzato se lo sblocco fallisce; in caso di successo apre la sessione e il
/// router passa all'elenco dei gruppi. Nessun retry automatico.
final unlockViewModelProvider =
    AsyncNotifierProvider.autoDispose<UnlockViewModel, void>(
      UnlockViewModel.new,
    );

class UnlockViewModel extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  /// Sblocco con password e file chiave.
  ///
  /// Se la biometria è attiva per il file, la sessione usa poi la sola chiave
  /// derivata (ADR-008); se il file è cambiato altrove (salt nuovo), la chiave
  /// salvata si aggiorna con la richiesta [biometricTexts]. Senza testi, o se
  /// l'aggiornamento non riesce, la biometria si disattiva per il file.
  Future<void> unlock({
    required UnlockArgs args,
    required String password,
    BiometricPromptTexts? biometricTexts,
  }) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => _open(args, password, biometricTexts),
    );
    if (ref.mounted) state = result;
  }

  /// Sblocco biometrico (FullUnlock di Keepass2Android, con la chiave
  /// derivata al posto della password). Se l'utente annulla non c'è errore: resta
  /// lo sblocco con password.
  Future<void> unlockWithBiometrics({
    required UnlockArgs args,
    required BiometricPromptTexts texts,
  }) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => _openWithBiometrics(args, texts),
    );
    if (!ref.mounted) return;
    state = switch (result) {
      AsyncError(
        error: BiometricKeyException(reason: BiometricKeyError.canceled),
      ) =>
        const AsyncData(null),
      _ => result,
    };
  }

  Future<void> _open(
    UnlockArgs args,
    String password,
    BiometricPromptTexts? biometricTexts,
  ) async {
    final storage = ref.read(fileStorageProvider);
    final databaseStorage = ref.read(databaseFileStorageProvider);
    final database = databaseStorage is CachedDatabaseStorage
        ? await databaseStorage.readForUnlock(
            args.database,
            offlineOnly: args.offline,
          )
        : await _load(databaseStorage, args.database);

    StoredFile? keyFile;
    if (args.keyFile case final picked?) {
      try {
        keyFile = await _load(storage, picked);
      } on FileUnavailableException {
        throw const KeyFileUnavailableException();
      }
    }

    final kdbx = await openDatabase(
      data: database.bytes,
      password: password,
      keyFile: keyFile?.bytes,
    );
    // L'utente ha lasciato la schermata durante la KDF: niente sessione.
    if (!ref.mounted) return;
    final hadBiometrics = ref
        .read(biometricKeyStoreProvider)
        .isEnabled(database.ref);
    await _syncBiometricKey(database.ref, kdbx, biometricTexts);
    if (!ref.mounted) return;
    final offer = !hadBiometrics && await _canOfferBiometrics(database.ref);
    if (!ref.mounted) return;
    if (offer) ref.read(biometricOfferProvider.notifier).offer(database.ref);
    await _start(
      args,
      database.ref,
      keyFile?.ref,
      kdbx,
      fileHash: fileHashOf(database.bytes),
      cacheStatus: databaseStorage is CachedDatabaseStorage
          ? await databaseStorage.opened(database)
          : const RemoteCacheStatus(),
    );
  }

  Future<void> _openWithBiometrics(
    UnlockArgs args,
    BiometricPromptTexts texts,
  ) async {
    final databaseStorage = ref.read(databaseFileStorageProvider);
    final database = databaseStorage is CachedDatabaseStorage
        ? await databaseStorage.readForUnlock(
            args.database,
            offlineOnly: args.offline,
          )
        : await _load(databaseStorage, args.database);
    final key = await ref
        .read(biometricKeyStoreProvider)
        .read(args.database.ref, texts: texts);
    if (key == null) {
      throw const BiometricKeyException(BiometricKeyError.invalidated);
    }
    final KdbxDatabase kdbx;
    try {
      kdbx = await openDatabaseWithKey(data: database.bytes, key: key);
    } on TransformedKeyStaleError {
      throw const BiometricKeyException(BiometricKeyError.stale);
    } on InvalidCredentialsError {
      throw const BiometricKeyException(BiometricKeyError.stale);
    }
    if (!ref.mounted) return;
    // Il file chiave non serve: la chiave derivata lo comprende già.
    await _start(
      args,
      database.ref,
      args.keyFile?.ref,
      kdbx,
      fileHash: fileHashOf(database.bytes),
      cacheStatus: databaseStorage is CachedDatabaseStorage
          ? await databaseStorage.opened(database)
          : const RemoteCacheStatus(),
    );
  }

  /// Proposta dello sblocco biometrico (D23): file ricordato tra i recenti,
  /// biometria non attiva e mai rifiutata per il file, biometria forte
  /// registrata sul dispositivo.
  Future<bool> _canOfferBiometrics(FileRef file) async {
    final store = ref.read(biometricKeyStoreProvider);
    if (!ref.read(appSettingsProvider).rememberRecentFiles ||
        store.isEnabled(file) ||
        store.isOfferDeclined(file)) {
      return false;
    }
    return ref.read(appSecurityProvider).hasStrongBiometrics();
  }

  /// Variante di D16 (ADR-008): con la biometria attiva la sessione usa solo
  /// la chiave derivata e, se il salt del file è cambiato, quella salvata si
  /// aggiorna.
  Future<void> _syncBiometricKey(
    FileRef file,
    KdbxDatabase kdbx,
    BiometricPromptTexts? texts,
  ) async {
    final store = ref.read(biometricKeyStoreProvider);
    final key = kdbx.header.transformedKey;
    if (key == null || !store.isEnabled(file)) return;
    withTransformedKeyOnly(kdbx);
    if (listEquals(store.fingerprintOf(file), key.fingerprint)) return;
    try {
      if (texts == null) {
        throw const BiometricKeyException(BiometricKeyError.unavailable);
      }
      await store.store(file, key, texts: texts);
    } on BiometricKeyException {
      await store.remove(file);
    }
  }

  Future<void> _start(
    UnlockArgs args,
    FileRef database,
    FileRef? keyFile,
    KdbxDatabase kdbx, {
    required String fileHash,
    required RemoteCacheStatus cacheStatus,
  }) async {
    if (!ref.mounted) return;
    final settings = ref.read(appSettingsProvider);
    if (settings.rememberRecentFiles) {
      await ref
          .read(recentFilesRepositoryProvider)
          .remember(
            RecentFile(
              database: database,
              keyFile: settings.rememberKeyFile ? keyFile : null,
            ),
            replacing: args.replacing ?? args.database.ref,
            keep: {
              for (final session
                  in ref
                      .read(databaseSessionProvider.notifier)
                      .openSessions) ...[session.file, ?session.keyFile],
            },
          );
      if (!ref.mounted) return;
      final previous = args.replacing ?? args.database.ref;
      final biometrics = ref.read(biometricKeyStoreProvider);
      if (previous != database &&
          (biometrics.isEnabled(previous) ||
              biometrics.isOfferDeclined(previous))) {
        await biometrics.remove(previous);
        if (!ref.mounted) return;
      }
      // File remoto ricordato: con "ricorda" le credenziali vanno nell'archivio.
      await ref.read(remoteStorageProvider).commit(database);
      if (!ref.mounted) return;
    }

    final session = DatabaseSession(
      file: database,
      keyFile: keyFile,
      database: kdbx,
      fileHash: fileHash,
      cacheStatus: cacheStatus,
    );
    final sessions = ref.read(databaseSessionProvider.notifier);
    if (args.additional) {
      sessions.openAdditional(session, args.lockGeneration ?? -1);
    } else {
      sessions.open(session);
    }
    if (cacheStatus.pending && !cacheStatus.offline && ref.mounted) {
      try {
        await ref.read(databaseSessionProvider.notifier).synchronize();
      } on Object {
        // Il database resta aperto dalla copia locale; lo stato visibile
        // conserva l'errore e le modifiche non caricate (ADR-017).
      }
    }
  }

  static Future<StoredFile> _load(FileStorage storage, PickedFile file) async =>
      switch (file.bytes) {
        final bytes? => StoredFile(ref: file.ref, bytes: bytes),
        null => await storage.read(file.ref),
      };
}
