import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/crypto/app_crypto_engine.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/external_change.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/storage/file_storage.dart';
import '../file_select/recent_files.dart';

/// Nome proposto per il file, come CreateDatabaseActivity di Keepass2Android.
const suggestedDatabaseFileName = 'keepass.kdbx';

/// Nome dei database nuovi (Keepass2Android: "Keepass2Android Password
/// Database").
const newDatabaseName = 'KeePassMobile Password Database';

/// KDF dei database nuovi (decisione D1): Argon2id con i valori
/// di Keepass2Android per Argon2, al posto dell'AES-KDF di CreateDB.cs.
const newDatabaseKdf = Argon2KdfSettings(
  id: true,
  memory: 64 * DataSize.mebi,
  iterations: 2,
  parallelism: 2,
);

/// KDF usata per i database nuovi (una più veloce nei test).
final newDatabaseKdfProvider = Provider<KdfSettings>((_) => newDatabaseKdf);

/// Crea in un isolate un database KDBX 4 con AES-256 e [kdf], come CreateDB.cs
/// di Keepass2Android: gruppo radice con il nome del file, gruppi `Internet`
/// ed `eMail` (decisione D2: niente voci modello), cestino attivo.
///
/// [password] vuota con [keyFile]: database protetto dal solo file chiave.
Future<(KdbxDatabase, Uint8List)> buildNewDatabase({
  required String password,
  Uint8List? keyFile,
  required String rootName,
  KdfSettings kdf = newDatabaseKdf,
}) {
  return Isolate.run(() async {
    AppCryptoEngine.install();
    final database = KdbxDatabase.create(
      credentials: KdbxCredentials(
        password: password.isEmpty ? null : ProtectedData.fromString(password),
        keyData: keyFile,
      ),
      name: rootName,
    );
    database.meta.name = newDatabaseName;
    database.header
      ..dataCipherUuid = KdbxUuid.fromString(CipherId.aes)
      ..kdfSettings = kdf;
    database
      ..createGroup(
        parent: database.root,
        name: 'Internet',
        icon: KdbxIcon.world,
      )
      ..createGroup(parent: database.root, name: 'eMail', icon: KdbxIcon.eMail);
    final bytes = Uint8List.fromList(await database.save());
    return (database, bytes);
  });
}

/// Nome del gruppo radice: il nome del file senza estensione.
String rootGroupName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
  return stem.isEmpty ? 'KeePassMobile' : stem;
}

/// Creazione di un database (CreateDatabaseActivity di Keepass2Android).
///
/// Lo stato è `AsyncLoading` durante la KDF, la scelta della posizione e la
/// verifica del file; `AsyncError` con l'errore tipizzato se qualcosa fallisce.
/// In caso di successo apre la sessione e il router passa all'elenco dei
/// gruppi. Nessun retry automatico.
final createDatabaseViewModelProvider =
    AsyncNotifierProvider.autoDispose<CreateDatabaseViewModel, void>(
      CreateDatabaseViewModel.new,
    );

class CreateDatabaseViewModel extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> create({required String password, PickedFile? keyFile}) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() => _create(password, keyFile));
    if (ref.mounted) state = result;
  }

  Future<void> _create(String password, PickedFile? keyFile) async {
    final storage = ref.read(fileStorageProvider);
    Uint8List? keyBytes;
    if (keyFile != null) {
      try {
        keyBytes = keyFile.bytes ?? (await storage.read(keyFile.ref)).bytes;
      } on FileUnavailableException {
        throw const KeyFileUnavailableException();
      }
    }

    final (database, bytes) = await buildNewDatabase(
      password: password,
      keyFile: keyBytes,
      rootName: rootGroupName(suggestedDatabaseFileName),
      kdf: ref.read(newDatabaseKdfProvider),
    );
    if (!ref.mounted) return;

    final file = await storage.create(
      suggestedName: suggestedDatabaseFileName,
      bytes: bytes,
    );
    // Scelta della posizione annullata: si resta sulla schermata.
    if (file == null || !ref.mounted) return;

    // Come FileTransactionEx di Keepass2Android: il file scritto deve
    // riaprirsi prima di usarlo.
    final written = await storage.read(file);
    await verifyWrittenDatabase(written.bytes, database);
    if (!ref.mounted) return;

    final settings = ref.read(appSettingsProvider);
    if (settings.rememberRecentFiles) {
      await ref
          .read(recentFilesRepositoryProvider)
          .remember(
            RecentFile(
              database: written.ref,
              keyFile: settings.rememberKeyFile ? keyFile?.ref : null,
            ),
          );
      if (!ref.mounted) return;
    }

    ref
        .read(databaseSessionProvider.notifier)
        .open(
          DatabaseSession(
            file: written.ref,
            keyFile: keyFile?.ref,
            database: database,
            fileHash: fileHashOf(written.bytes),
          ),
        );
  }
}
