import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/file_storage.dart';

/// Impronta del contenuto di un file database: si confronta prima di ogni
/// salvataggio per accorgersi delle modifiche fatte altrove
/// (`HashOfFileOnDisk` di Keepass2Android).
String fileHashOf(Uint8List bytes) => sha256.convert(bytes).toString();

/// Scelta dell'utente quando il file è cambiato dopo l'apertura (domanda
/// "Sincronizzare?" di `SaveDb.cs`).
enum ExternalChangeChoice {
  /// Unisce le modifiche fatte altrove a quelle di questa app, poi salva.
  synchronize,

  /// Scrive la versione di questa app: le modifiche fatte altrove si perdono.
  overwrite,

  /// Non salva.
  cancel,
}

/// Chiede all'utente cosa fare con [file] cambiato altrove.
typedef ExternalChangeResolver = Future<ExternalChangeChoice> Function(
  FileRef file,
);

/// Domanda all'utente; l'app la sostituisce con la finestra di dialogo. Senza,
/// non si salva mai sopra le modifiche fatte altrove.
final externalChangeResolverProvider = Provider<ExternalChangeResolver>(
  (_) =>
      (_) async => ExternalChangeChoice.cancel,
);

/// Esito di "Sincronizza ora".
enum SyncResult {
  /// Il file non era cambiato: niente scritto.
  unchanged,

  /// Modifiche fatte altrove unite e file scritto.
  synchronized,

  /// Copia locale salvata, upload ancora da completare.
  pendingUpload,

  /// Rete non disponibile, copia locale invariata.
  offline,
}

/// Salvataggio annullato dall'utente davanti al file cambiato altrove.
final class ExternalChangeCanceledException implements Exception {
  const ExternalChangeCanceledException();
}

/// Il file cambiato altrove ha un'altra chiave principale.
final class SyncKeyMismatchException implements Exception {
  const SyncKeyMismatchException();
}

/// La sessione ha solo la chiave derivata (sblocco biometrico) e il file
/// è stato salvato altrove con un salt nuovo: serve la password.
final class SyncNeedsPasswordException implements Exception {
  const SyncNeedsPasswordException();
}

/// Il file è stato sostituito con un altro database (gruppo radice diverso).
final class SyncDifferentDatabaseException implements Exception {
  const SyncDifferentDatabaseException();
}
