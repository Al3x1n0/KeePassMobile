import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/crypto/app_crypto_engine.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/kdbx_items.dart';

/// Impostazioni del database aperto (`pref_database.xml` e
/// `pref_database_key_deriv_func.xml` di Keepass2Android).
@immutable
class DatabaseSettings {
  const DatabaseSettings({
    required this.name,
    required this.defaultUserName,
    required this.recycleBinEnabled,
    required this.templatesGroupId,
    required this.historyMaxItems,
    required this.historyMaxSize,
    required this.cipher,
    required this.kdf,
    required this.kdbxVersion,
  });

  factory DatabaseSettings.of(KdbxDatabase database) => DatabaseSettings(
    name: database.meta.name,
    defaultUserName: database.meta.defaultUser ?? '',
    recycleBinEnabled: database.meta.recycleBinEnabled,
    templatesGroupId:
        database.meta.entryTemplatesGroup == null ||
            database.meta.entryTemplatesGroup == KdbxUuid.zero
        ? ''
        : idOfUuid(database.meta.entryTemplatesGroup!),
    historyMaxItems: database.meta.historyMaxItems ?? Defaults.historyMaxItems,
    historyMaxSize: database.meta.historyMaxSize ?? Defaults.historyMaxSize,
    cipher: database.header.dataCipherUuid?.string ?? CipherId.aes,
    kdf: database.header.kdfSettings,
    kdbxVersion: database.header.version.$1,
  );

  /// Valore di [historyMaxItems] e [historyMaxSize] senza limite (KeePass).
  static const unlimited = -1;

  final String name;
  final String defaultUserName;
  final bool recycleBinEnabled;
  final String templatesGroupId;

  /// Versioni conservate per voce; [unlimited] senza limite.
  final int historyMaxItems;

  /// Dimensione massima della cronologia di una voce in byte; [unlimited]
  /// senza limite.
  final int historyMaxSize;

  /// [CipherId] del cifrario.
  final String cipher;
  final KdfSettings kdf;

  /// Versione principale del formato (3 o 4): da essa dipendono cifrari e KDF
  /// disponibili. Non si cambia da qui.
  final int kdbxVersion;

  /// Cifrari ammessi: ChaCha20 richiede KDBX 4.
  List<String> get allowedCiphers => kdbxVersion >= 4
      ? const [CipherId.aes, CipherId.chaCha20, CipherId.twofish]
      : const [CipherId.aes, CipherId.twofish];

  /// KDF ammesse: KDBX 3 ha solo AES-KDF.
  List<String> get allowedKdfs => kdbxVersion >= 4
      ? const [KdfId.aes, KdfId.argon2d, KdfId.argon2id]
      : const [KdfId.aes];

  DatabaseSettings copyWith({
    String? name,
    String? defaultUserName,
    bool? recycleBinEnabled,
    String? templatesGroupId,
    int? historyMaxItems,
    int? historyMaxSize,
    String? cipher,
    KdfSettings? kdf,
  }) => DatabaseSettings(
    name: name ?? this.name,
    defaultUserName: defaultUserName ?? this.defaultUserName,
    recycleBinEnabled: recycleBinEnabled ?? this.recycleBinEnabled,
    templatesGroupId: templatesGroupId ?? this.templatesGroupId,
    historyMaxItems: historyMaxItems ?? this.historyMaxItems,
    historyMaxSize: historyMaxSize ?? this.historyMaxSize,
    cipher: cipher ?? this.cipher,
    kdf: kdf ?? this.kdf,
    kdbxVersion: kdbxVersion,
  );
}

/// Applica [settings] al database. La KDF si sostituisce solo se cambia,
/// perché ogni cambio la rende più lenta da verificare.
DatabaseEdit databaseSettingsEdit(DatabaseSettings settings) => (database) {
  if (!settings.allowedCiphers.contains(settings.cipher) ||
      !settings.allowedKdfs.contains(settings.kdf.kdfId)) {
    throw UnsupportedValueError('cifrario o KDF non ammessi');
  }
  final currentGroup = database.meta.entryTemplatesGroup;
  final currentGroupId = currentGroup == null || currentGroup == KdbxUuid.zero
      ? ''
      : idOfUuid(currentGroup);
  if (settings.templatesGroupId != currentGroupId) {
    final group = settings.templatesGroupId.isEmpty
        ? null
        : findGroup(database, settings.templatesGroupId);
    if (settings.templatesGroupId.isNotEmpty &&
        (group == null || isInRecycleBin(database, group))) {
      throw StateError('gruppo dei modelli non disponibile');
    }
    database.meta.entryTemplatesGroup = group?.uuid ?? KdbxUuid.zero;
  }
  database.meta
    ..name = settings.name
    ..defaultUser = settings.defaultUserName.isEmpty
        ? null
        : settings.defaultUserName
    ..recycleBinEnabled = settings.recycleBinEnabled
    ..historyMaxItems = settings.historyMaxItems
    ..historyMaxSize = settings.historyMaxSize
    ..settingsChanged = KdbxTime.now();
  database.header.dataCipherUuid = KdbxUuid.fromString(settings.cipher);
  if (database.header.kdfSettings != settings.kdf) {
    database.header.kdfSettings = settings.kdf;
  }
};

/// Durata di una derivazione della chiave con [kdf] su questo dispositivo
/// (stima del tempo di apertura), misurata in un isolate su un database vuoto.
Future<Duration> measureKdf(KdfSettings kdf, {required int kdbxVersion}) {
  return Isolate.run(() async {
    AppCryptoEngine.install();
    final database = KdbxDatabase.create(
      credentials: KdbxCredentials(
        // Valore fittizio: serve solo a far lavorare la KDF.
        password: ProtectedData.fromString('misura'),
      ),
      name: 'misura',
    );
    database.header.version = (kdbxVersion, 1);
    database.header.kdfSettings = kdf;
    final watch = Stopwatch()..start();
    await database.save();
    return watch.elapsed;
  });
}

/// Impostazioni del database aperto; `null` se il database è chiuso.
final databaseSettingsProvider = Provider.autoDispose<DatabaseSettings?>((ref) {
  final session = ref.watch(databaseSessionProvider);
  return session == null ? null : DatabaseSettings.of(session.database);
});

/// Salvataggio delle impostazioni del database e misura della KDF.
final databaseSettingsViewModelProvider =
    AsyncNotifierProvider.autoDispose<DatabaseSettingsViewModel, Duration?>(
      DatabaseSettingsViewModel.new,
    );

/// Lo stato è l'ultima misura della KDF (`null` se non ancora misurata) o
/// l'errore dell'ultimo salvataggio.
class DatabaseSettingsViewModel extends AsyncNotifier<Duration?> {
  @override
  FutureOr<Duration?> build() => null;

  /// Salva [settings]. `true` se riuscito; l'errore resta nello stato.
  Future<bool> save(DatabaseSettings settings) async {
    if (state.isLoading) return false;
    final previous = state.value;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref
          .read(databaseSessionProvider.notifier)
          .apply(databaseSettingsEdit(settings)),
    );
    if (!ref.mounted) return !result.hasError;
    state = result.hasError
        ? AsyncError(result.error!, result.stackTrace ?? StackTrace.current)
        : AsyncData(previous);
    return !result.hasError;
  }

  /// Misura il tempo di derivazione con [kdf].
  Future<void> measure(KdfSettings kdf, {required int kdbxVersion}) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => measureKdf(kdf, kdbxVersion: kdbxVersion),
    );
    if (ref.mounted) state = result;
  }
}
