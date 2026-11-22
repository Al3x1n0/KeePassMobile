import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/clipboard/clipboard_service.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/entry_templates.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/database/field_references.dart';
import '../../shared/storage/file_storage.dart';
import '../../shared/storage/recent_passwords_store.dart';
import '../entry_edit/entry_edit_view_model.dart';
import '../favorites/favorites_view_model.dart';
import '../recent_passwords/recent_passwords_view_model.dart';
import '../totp/totp.dart';

/// Campo di una voce da mostrare nel dettaglio.
@immutable
class EntryFieldView {
  const EntryFieldView({
    required this.key,
    required this.protected,
    this.value = '',
    this.issue,
  });

  final String value;
  final FieldReferenceIssue? issue;

  /// Nome del campo (`UserName`, `Password`, ... o nome personalizzato).
  final String key;

  /// Valore da nascondere finché l'utente non lo rivela.
  final bool protected;

  bool get isStandard => EntryFields.standard.contains(key);
}

/// Voce [entryId] del database aperto; `null` se chiuso o voce inesistente.
final entryProvider = Provider.autoDispose.family<KdbxEntry?, String>((
  ref,
  entryId,
) {
  final session = ref.watch(databaseSessionProvider);
  if (session == null) return null;
  return findEntry(session.database, entryId);
});

/// Campi da mostrare: nome utente, password, URL, note (se non vuoti) e poi i
/// campi personalizzati secondo il modello collegato o in ordine alfabetico.
/// La password e i campi con il segreto TOTP (anche se non
/// protetti nel file) si possono nascondere; se lo sono all'apertura lo
/// decidono le impostazioni (maskpass, masktotp).
List<EntryFieldView> visibleFields(KdbxEntry entry, {KdbxDatabase? database}) {
  const order = [
    EntryFields.userName,
    EntryFields.password,
    EntryFields.url,
    EntryFields.notes,
  ];
  final template = structuredTemplateOf(database, entry);
  final custom =
      entry.fields.keys
          .where(
            (k) =>
                !EntryFields.standard.contains(k) &&
                !(k == structuredTemplateReference && template != null),
          )
          .toList()
        ..sort((a, b) => compareTemplateFields(template, a, b));
  return [
    for (final key in [...order, ...custom])
      if (entry.fields[key] case final field? when field.text.isNotEmpty)
        _fieldView(database, entry, key, field),
  ];
}

EntryFieldView _fieldView(
  KdbxDatabase? database,
  KdbxEntry entry,
  String key,
  KdbxTextField field,
) {
  final resolved = database == null
      ? null
      : resolveEntryField(database, entry, key);
  return EntryFieldView(
    key: key,
    value: resolved?.text ?? field.text,
    issue: resolved?.issue,
    protected:
        (resolved?.protected ?? (field is ProtectedTextField)) ||
        key == EntryFields.password ||
        isTotpField(key),
  );
}

/// TOTP della voce: [config] se valido, `null` con [invalid] se i campi ci
/// sono ma non sono utilizzabili.
@immutable
class EntryTotp {
  const EntryTotp.valid(TotpConfig this.config);
  const EntryTotp.invalid() : config = null;

  final TotpConfig? config;

  bool get invalid => config == null;
}

/// TOTP della voce [entryId]; `null` se la voce non ne ha.
final entryTotpProvider = Provider.autoDispose.family<EntryTotp?, String>((
  ref,
  entryId,
) {
  final entry = ref.watch(entryProvider(entryId));
  return entry == null ? null : entryTotpOf(entry);
});

/// Voce [index] della cronologia della voce [entryId]; `null` se non esiste.
final historyEntryProvider = Provider.autoDispose
    .family<KdbxEntry?, (String, int)>((ref, key) {
      final (entryId, index) = key;
      final entry = ref.watch(entryProvider(entryId));
      if (entry == null || index < 0 || index >= entry.history.length) {
        return null;
      }
      return entry.history[index];
    });

/// TOTP di [entry]; `null` se non ne ha.
EntryTotp? entryTotpOf(KdbxEntry entry) {
  try {
    final config = parseTotp({
      for (final MapEntry(:key, :value) in entry.fields.entries)
        key: value.text,
    });
    return config == null ? null : EntryTotp.valid(config);
  } on InvalidTotpConfig {
    return const EntryTotp.invalid();
  }
}

/// Allegato di una voce, con la dimensione.
@immutable
class EntryAttachment {
  const EntryAttachment({required this.name, required this.size});

  final String name;
  final int size;
}

/// Allegati di [entry] in ordine di nome (EntryActivity.PopulateBinaries).
List<EntryAttachment> entryAttachments(KdbxDatabase database, KdbxEntry entry) {
  final list = [
    for (final MapEntry(:key, :value) in entry.binaries.entries)
      EntryAttachment(
        name: key,
        size: database.binaries.getByRef(value)?.data.length ?? 0,
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return List.unmodifiable(list);
}

/// Contenuto dell'allegato [name] di [entry]; `null` se non esiste.
Uint8List? attachmentData(KdbxDatabase database, KdbxEntry entry, String name) {
  final ref = entry.binaries[name];
  final data = ref == null ? null : database.binaries.getByRef(ref)?.data;
  return data == null ? null : Uint8List.fromList(data);
}

/// Esito del salvataggio di un allegato su file.
enum AttachmentSaveResult { saved, cancelled, failed }

/// `true` se eliminare la voce la cancella definitivamente.
final entryDeletesPermanentlyProvider = Provider.autoDispose
    .family<bool, String>((ref, entryId) {
      final session = ref.watch(databaseSessionProvider);
      final entry = ref.watch(entryProvider(entryId));
      if (session == null || entry == null) return false;
      return deletesPermanently(session.database, entry);
    });

/// Elimina la voce: nel cestino se attivo, altrimenti (o se già nel cestino)
/// definitivamente.
DatabaseEdit deleteEntryEdit(KdbxUuid uuid) => (database) {
  final entry = findEntryByUuid(database, uuid);
  if (entry == null) throw StateError('voce non trovata');
  database.remove(entry);
};

/// Scade un TAN aperto, conservando la versione precedente nella cronologia.
DatabaseEdit expireTanEdit(KdbxUuid uuid, DateTime now) => (database) {
  final entry = findEntryByUuid(database, uuid);
  if (entry == null || entryTitle(entry) != '<TAN>' || isExpired(entry, now)) {
    return;
  }
  entry.pushHistory();
  entry.times.expires = true;
  entry.times.expiry = KdbxTime(now.toUtc());
  entry.times.touch();
  trimHistory(database, entry);
};

/// Azioni sulla voce: copia negli appunti ed eliminazione.
final entryActionsProvider = AsyncNotifierProvider.autoDispose
    .family<EntryActions, void, String>(EntryActions.new);

class EntryActions extends AsyncNotifier<void> {
  EntryActions(this.entryId);

  final String entryId;

  @override
  FutureOr<void> build() {}

  /// Copia il valore del campo [key] e programma la pulizia degli appunti.
  /// Restituisce il tempo dopo cui gli appunti verranno svuotati.
  Future<Duration?> copy(String key) async {
    final entry = ref.read(entryProvider(entryId));
    final database = ref.read(databaseSessionProvider)?.database;
    if (entry == null || database == null) return null;
    final value = resolveEntryField(database, entry, key);
    if (!value.valid) throw FieldReferenceException(value.issue!);
    if (value.text.isEmpty) return null;
    return copyText(
      value.text,
      recordRecentUse: !isInRecycleBin(database, entry),
    );
  }

  /// Copia il valore di una voce e lo rimuove dagli appunti dopo il timeout.
  /// Con [recordRecentUse] la copia riuscita registra la voce tra le recenti.
  Future<Duration> copyText(
    String value, {
    bool recordRecentUse = false,
  }) async {
    final clipboard = ref.read(clipboardServiceProvider);
    final key = recordRecentUse && value.isNotEmpty
        ? ref.read(recentPasswordDatabaseKeyProvider)
        : null;
    final generation = key == null
        ? null
        : ref.read(databaseSessionProvider.notifier).lockGeneration;
    await clipboard.copy(value);
    if (key != null &&
        ref.mounted &&
        generation ==
            ref.read(databaseSessionProvider.notifier).lockGeneration &&
        ref.read(recentPasswordDatabaseKeyProvider) == key) {
      unawaited(ref.read(recentPasswordsStoreProvider).record(key, entryId));
      ref.invalidate(recentPasswordIdsProvider(key));
    }
    return clipboard.clearAfter;
  }

  /// Salva l'allegato [name] in un file scelto dall'utente (decisione D11:
  /// il file è in chiaro, la conferma la chiede la View). La copia
  /// non si riapre dall'app: il permesso persistente si rilascia subito.
  Future<AttachmentSaveResult> saveAttachment(
    String name, {
    int? historyIndex,
  }) async {
    final session = ref.read(databaseSessionProvider);
    final entry = historyIndex == null
        ? ref.read(entryProvider(entryId))
        : ref.read(historyEntryProvider((entryId, historyIndex)));
    if (session == null || entry == null) return AttachmentSaveResult.failed;
    final data = attachmentData(session.database, entry, name);
    if (data == null) return AttachmentSaveResult.failed;
    final storage = ref.read(fileStorageProvider);
    try {
      final file = await storage.create(suggestedName: name, bytes: data);
      if (file == null) return AttachmentSaveResult.cancelled;
      await storage.release(file);
      return AttachmentSaveResult.saved;
    } on FileUnavailableException {
      return AttachmentSaveResult.failed;
    } on FileWriteException {
      return AttachmentSaveResult.failed;
    }
  }

  /// Segna come utilizzato un TAN non ancora scaduto.
  Future<bool> expireTan() async {
    final entry = ref.read(entryProvider(entryId));
    final now = DateTime.now();
    if (entry == null ||
        entryTitle(entry) != '<TAN>' ||
        isExpired(entry, now)) {
      return false;
    }
    return _apply((uuid) => expireTanEdit(uuid, now));
  }

  /// Elimina la voce e salva. `true` se riuscito; l'errore resta nello stato.
  Future<bool> delete() => _apply((uuid) => deleteEntryEdit(uuid));

  Future<bool> setFavorite(bool favorite) =>
      _apply((uuid) => setEntryFavoriteEdit(uuid, favorite));

  /// Ripristina la versione [index] della cronologia e salva.
  Future<bool> restoreHistory(int index) =>
      _apply((uuid) => restoreHistoryEdit(uuid, index));

  /// Elimina la versione [index] della cronologia e salva.
  Future<bool> deleteHistory(int index) =>
      _apply((uuid) => deleteHistoryEdit(uuid, index));

  Future<bool> _apply(DatabaseEdit Function(KdbxUuid uuid) edit) async {
    if (state.isLoading) return false;
    final entry = ref.read(entryProvider(entryId));
    if (entry == null) return false;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(databaseSessionProvider.notifier).apply(edit(entry.uuid)),
    );
    if (ref.mounted) state = result;
    return !result.hasError;
  }
}
