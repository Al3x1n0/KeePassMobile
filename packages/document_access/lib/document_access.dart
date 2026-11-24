/// Accesso ai documenti scelti dall'utente, nel file originale.
///
/// - Android: Storage Access Framework (`ACTION_OPEN_DOCUMENT`, e
///   `ACTION_CREATE_DOCUMENT` per i documenti nuovi) con permesso
///   persistente in lettura e scrittura, come `AndroidContentStorage` di
///   Keepass2Android. L'URI restituito è un `content://` riutilizzabile anche
///   dopo il riavvio dell'app.
/// - iOS: `UIDocumentPickerViewController` senza copia e security-scoped
///   bookmark. L'URI restituito è `bookmark:<base64>`.
/// - Su entrambe le piattaforme sono accettati anche gli URI `file://`.
///
/// Gli errori non contengono mai nomi o percorsi dei file (SEC-01).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Documento appena scelto, con il contenuto già letto.
@immutable
class PickedDocument {
  const PickedDocument({
    required this.uri,
    required this.name,
    required this.bytes,
    required this.persistent,
  });

  /// Riferimento persistente al documento, da passare a [DocumentAccess.read]
  /// e [DocumentAccess.write].
  final String uri;

  /// Nome da mostrare all'utente.
  final String name;

  final Uint8List bytes;

  /// `false` se il provider non concede un accesso che sopravvive al riavvio
  /// dell'app (Android): il documento andrà scelto di nuovo.
  final bool persistent;
}

/// Documento appena creato dall'utente con [DocumentAccess.create].
@immutable
class CreatedDocument {
  const CreatedDocument({
    required this.uri,
    required this.name,
    required this.persistent,
  });

  /// Riferimento persistente, come per [PickedDocument.uri].
  final String uri;

  /// Nome scelto dall'utente (può differire da quello proposto).
  final String name;

  /// `false` se l'accesso non sopravvive al riavvio dell'app (Android).
  final bool persistent;
}

/// Contenuto letto da un documento.
@immutable
class DocumentData {
  const DocumentData({required this.bytes, this.refreshedUri});

  final Uint8List bytes;

  /// Nuovo riferimento da salvare al posto del precedente, quando il sistema
  /// lo ha aggiornato (bookmark iOS obsoleto, ad esempio dopo uno spostamento).
  final String? refreshedUri;
}

/// Il documento non è più raggiungibile: rimosso, spostato fuori dal
/// provider, permesso revocato o riferimento non valido.
final class DocumentUnavailableException implements Exception {
  const DocumentUnavailableException();

  @override
  String toString() => 'DocumentUnavailableException';
}

/// Errore di accesso al documento diverso da [DocumentUnavailableException].
final class DocumentAccessException implements Exception {
  const DocumentAccessException(this.code);

  /// `io`, `busy` (una scelta è già in corso), `no_activity` o `too_large`.
  final String code;

  @override
  String toString() => 'DocumentAccessException: $code';
}

/// Scelta, lettura e scrittura di documenti tramite il codice nativo.
class DocumentAccess {
  const DocumentAccess();

  /// Riferimento stabile alla copia privata del database dimostrativo.
  static const demoDatabaseUri = 'app-private:demo';

  @visibleForTesting
  static const channel = MethodChannel(
    'io.github.al3x1n0.keepassmobile/document_access',
  );

  /// Apre il selettore di documenti del sistema.
  ///
  /// `null` se l'utente annulla.
  Future<PickedDocument?> pick() async {
    final result = await _invoke<Map<Object?, Object?>>('pick');
    if (result == null) return null;
    return switch (result) {
      {
        'uri': final String uri,
        'name': final String name,
        'bytes': final Uint8List bytes,
        'persistent': final bool persistent,
      } =>
        PickedDocument(
          uri: uri,
          name: name,
          bytes: bytes,
          persistent: persistent,
        ),
      _ => throw const DocumentAccessException('io'),
    };
  }

  /// Apre il selettore del sistema per scegliere dove creare un documento
  /// nuovo, con il nome proposto [suggestedName], e vi scrive [bytes].
  ///
  /// - Android: `ACTION_CREATE_DOCUMENT` con permesso persistente.
  /// - iOS: `UIDocumentPickerViewController(forExporting:)` e bookmark.
  ///
  /// `null` se l'utente annulla.
  Future<CreatedDocument?> create({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    final result = await _invoke<Map<Object?, Object?>>('create', {
      'name': suggestedName,
      'bytes': bytes,
    });
    if (result == null) return null;
    return switch (result) {
      {
        'uri': final String uri,
        'name': final String name,
        'persistent': final bool persistent,
      } =>
        CreatedDocument(uri: uri, name: name, persistent: persistent),
      _ => throw const DocumentAccessException('io'),
    };
  }

  Future<DocumentData> read(String uri) async {
    final result = await _invoke<Map<Object?, Object?>>('read', {'uri': uri});
    return switch (result) {
      {'bytes': final Uint8List bytes} => DocumentData(
        bytes: bytes,
        refreshedUri: result['refreshedUri'] as String?,
      ),
      _ => throw const DocumentAccessException('io'),
    };
  }

  /// Sostituisce l'intero contenuto del documento con [bytes].
  Future<void> write(String uri, Uint8List bytes) =>
      _invoke<void>('write', {'uri': uri, 'bytes': bytes});

  /// Rinuncia al permesso persistente sul documento (solo Android; su iOS il
  /// bookmark va semplicemente dimenticato).
  Future<void> release(String uri) => _invoke<void>('release', {'uri': uri});

  /// Installa [bytes] soltanto se la demo non esiste e non è stata rimossa.
  ///
  /// Il confronto e la copia atomica sono serializzati fra i motori Flutter.
  /// Restituisce `false` se la rimozione definitiva è già stata registrata.
  Future<bool> ensureDemoDatabase(Uint8List bytes) async {
    final installed = await _invoke<bool>('ensureDemoDatabase', {
      'bytes': bytes,
    });
    if (installed == null) throw const DocumentAccessException('io');
    return installed;
  }

  /// Registra la rimozione definitiva della demo e ne elimina la copia.
  ///
  /// Con [keepFile] conserva il file per una sessione ancora aperta. Una
  /// chiamata successiva senza [keepFile] completa la cancellazione dopo
  /// l'ultimo [releaseDemoDatabase], anche fra motori Flutter diversi.
  /// Le sessioni che hanno già trattenuto la demo continuano a leggere e
  /// scrivere finché rilasciano il proprio accesso.
  Future<void> deleteDemoDatabase({bool keepFile = false}) =>
      _invoke<void>('deleteDemoDatabase', {'keepFile': keepFile});

  /// Trattiene la copia privata per una sessione del motore corrente.
  ///
  /// Restituisce `false` se la copia è assente o rimossa. Ogni risultato
  /// `true` richiede un [releaseDemoDatabase] alla chiusura della sessione.
  Future<bool> retainDemoDatabase() async {
    final retained = await _invoke<bool>('retainDemoDatabase');
    if (retained == null) throw const DocumentAccessException('io');
    return retained;
  }

  /// Rilascia un accesso del motore corrente e completa la rimozione pendente.
  ///
  /// Non rilascia gli accessi acquisiti da altri motori Flutter.
  Future<void> releaseDemoDatabase() => _invoke<void>('releaseDemoDatabase');

  /// Verifica lo stato nativo di rimozione condiviso fra i motori Flutter.
  Future<bool> isDemoDatabaseRemoved() async {
    final removed = await _invoke<bool>('isDemoDatabaseRemoved');
    if (removed == null) throw const DocumentAccessException('io');
    return removed;
  }

  /// Record cifrato della cache remota, identificato da un hash (ADR-017).
  /// Nessun nome o riferimento al file remoto attraversa il canale.
  Future<Uint8List?> readRemoteCache(String id) =>
      _invoke<Uint8List>('readRemoteCache', {'id': id});

  /// Identificativi dei record, compresi quelli senza un file recente.
  Future<List<String>> listRemoteCacheIds() async {
    final ids = await _invoke<List<Object?>>('listRemoteCacheIds');
    if (ids == null || ids.any((id) => id is! String)) {
      throw const DocumentAccessException('io');
    }
    return ids.cast<String>();
  }

  /// Rimuove il record soltanto se corrisponde al token già letto.
  Future<bool> deleteRemoteCache(String id, Uint8List expectedToken) async =>
      await _invoke<bool>('deleteRemoteCache', {
        'id': id,
        'expected': expectedToken,
      }) ??
      false;

  /// Sostituzione atomica con confronto del token iniziale di 32 byte.
  /// `null` richiede un record assente; `false` indica una modifica concorrente.
  Future<bool> writeRemoteCache(
    String id,
    Uint8List record, {
    Uint8List? expectedToken,
  }) async =>
      await _invoke<bool>('writeRemoteCache', {
        'id': id,
        'bytes': record,
        'expected': expectedToken,
      }) ??
      false;

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') throw const DocumentUnavailableException();
      throw DocumentAccessException(e.code);
    } on MissingPluginException {
      throw const DocumentAccessException('no_plugin');
    }
  }
}
