import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/database/database_session.dart';
import '../../shared/database/entry_templates.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/database/item_edits.dart';
import '../totp/totp.dart';

/// Campo personalizzato in modifica.
@immutable
class CustomFieldDraft {
  const CustomFieldDraft({
    required this.key,
    required this.value,
    required this.protected,
  });

  final String key;
  final String value;
  final bool protected;

  @override
  bool operator ==(Object other) =>
      other is CustomFieldDraft &&
      other.key == key &&
      other.value == value &&
      other.protected == protected;

  @override
  int get hashCode => Object.hash(key, value, protected);
}

/// Allegato in modifica: già nel database ([existingId]) o appena scelto
/// ([data]).
@immutable
class AttachmentDraft {
  const AttachmentDraft.existing({
    required this.name,
    required int this.existingId,
  }) : data = null;
  const AttachmentDraft.added({
    required this.name,
    required Uint8List this.data,
  }) : existingId = null;

  final String name;
  final int? existingId;
  final Uint8List? data;

  AttachmentDraft renamed(String name) => switch (data) {
    final d? => AttachmentDraft.added(name: name, data: d),
    null => AttachmentDraft.existing(name: name, existingId: existingId!),
  };

  @override
  bool operator ==(Object other) =>
      other is AttachmentDraft &&
      other.name == name &&
      other.existingId == existingId &&
      identical(other.data, data);

  @override
  int get hashCode => Object.hash(name, existingId, data);
}

/// Nome libero per un allegato che ha lo stesso nome di uno già presente,
/// come AddBinaryFromBytes di Keepass2Android: `nome0.ext`, `nome1.ext`, ...
String uniqueAttachmentName(String name, Iterable<String> existing) {
  final taken = existing.toSet();
  if (!taken.contains(name)) return name;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var n = 0; ; n++) {
    final candidate = '$base$n$ext';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// Contenuto modificabile di una voce.
@immutable
class EntryDraft {
  const EntryDraft({
    this.title = '',
    this.userName = '',
    this.password = '',
    this.url = '',
    this.overrideUrl = '',
    this.notes = '',
    this.custom = const [],
    this.icon = KdbxIcon.key,
    this.iconChoice,
    this.expires = false,
    this.expiry,
    this.tags = const [],
    this.attachments = const [],
  });

  factory EntryDraft.fromEntry(KdbxEntry entry, {KdbxDatabase? database}) {
    final template = structuredTemplateOf(database, entry);
    final customKeys = entry.fields.keys
        .where((key) => !EntryFields.standard.contains(key))
        .toList();
    if (template != null) {
      customKeys.sort((a, b) => compareTemplateFields(template, a, b));
    }
    return EntryDraft(
      title: entryField(entry, EntryFields.title),
      userName: entryField(entry, EntryFields.userName),
      password: entryField(entry, EntryFields.password),
      url: entryField(entry, EntryFields.url),
      overrideUrl: entry.overrideUrl ?? '',
      notes: entryField(entry, EntryFields.notes),
      icon: entry.icon,
      expires: entry.times.expires,
      expiry: entry.times.expiry.time?.toLocal(),
      tags: List.unmodifiable([...?entry.tags]),
      attachments: List.unmodifiable([
        for (final MapEntry(:key, :value) in entry.binaries.entries)
          AttachmentDraft.existing(name: key, existingId: value.id),
      ]),
      custom: List.unmodifiable([
        for (final key in customKeys)
          if (entry.fields[key] case final value?)
            CustomFieldDraft(
              key: key,
              value: value.text,
              protected: value is ProtectedTextField,
            ),
      ]),
    );
  }

  final String title;
  final String userName;
  final String password;
  final String url;
  final String overrideUrl;
  final String notes;
  final List<CustomFieldDraft> custom;

  /// Icona standard (le icone personalizzate restano finché non si cambia).
  final KdbxIcon icon;
  final IconChoice? iconChoice;

  /// La voce scade a [expiry] (EntryEditActivity di Keepass2Android).
  final bool expires;
  final DateTime? expiry;

  /// Tag normalizzati con [parseTags].
  final List<String> tags;

  /// Allegati, con nomi distinti.
  final List<AttachmentDraft> attachments;

  @override
  bool operator ==(Object other) =>
      other is EntryDraft &&
      other.title == title &&
      other.userName == userName &&
      other.password == password &&
      other.url == url &&
      other.overrideUrl == overrideUrl &&
      other.notes == notes &&
      listEquals(other.custom, custom) &&
      other.icon == icon &&
      other.iconChoice == iconChoice &&
      other.expires == expires &&
      other.expiry?.millisecondsSinceEpoch == expiry?.millisecondsSinceEpoch &&
      listEquals(other.tags, tags) &&
      listEquals(other.attachments, attachments);

  @override
  int get hashCode => Object.hash(
    title,
    userName,
    password,
    url,
    overrideUrl,
    notes,
    Object.hashAll(custom),
    icon,
    iconChoice,
    expires,
    expiry?.millisecondsSinceEpoch,
    Object.hashAll(tags),
    Object.hashAll(attachments),
  );
}

/// Errore di validazione del nome di un campo personalizzato.
enum FieldNameError { empty, reserved, duplicate }

/// Valida il nome del campo personalizzato in posizione [index] di [names].
FieldNameError? validateFieldName(List<String> names, int index) {
  final name = names[index].trim();
  if (name.isEmpty) return FieldNameError.empty;
  if (EntryFields.standard.contains(name)) return FieldNameError.reserved;
  for (var i = 0; i < index; i++) {
    if (names[i].trim() == name) return FieldNameError.duplicate;
  }
  return null;
}

/// Scrive [draft] nei campi di [entry]. Un campo standard è protetto se lo era
/// già o se lo chiede l'impostazione del database (MemoryProtection); se il
/// database non dice nulla la password è protetta, come in KeePass.
void applyDraft(KdbxDatabase database, KdbxEntry entry, EntryDraft draft) {
  final protection = database.meta.memoryProtection;
  void setStandard(String key, String value, bool protectedByDatabase) {
    entry.fields[key] = KdbxTextField.fromText(
      text: value,
      protected: entry.fields[key] is ProtectedTextField || protectedByDatabase,
    );
  }

  setStandard(EntryFields.title, draft.title, protection.title ?? false);
  setStandard(
    EntryFields.userName,
    draft.userName,
    protection.userName ?? false,
  );
  setStandard(
    EntryFields.password,
    draft.password,
    protection.password ?? true,
  );
  setStandard(EntryFields.url, draft.url, protection.url ?? false);
  entry.overrideUrl = draft.overrideUrl;
  setStandard(EntryFields.notes, draft.notes, protection.notes ?? false);

  // Come KeePass: scegliere un'icona standard toglie quella personalizzata.
  if (draft.iconChoice case final choice?) {
    applyIconChoice(database, entry, choice);
  } else if (entry.icon != draft.icon) {
    entry
      ..icon = draft.icon
      ..customIcon = null;
  }
  entry.times.expires = draft.expires;
  if (draft.expiry case final expiry?) {
    entry.times.expiry = KdbxTime(expiry.toUtc());
  }
  if (draft.tags.isNotEmpty || entry.tags != null) {
    entry.tags = [...draft.tags];
  }

  entry.binaries = {
    for (final attachment in draft.attachments)
      attachment.name: switch (attachment.data) {
        final data? => database.binaries.add(
          PlainBinary(data: data, compressed: false),
        ),
        null => BinaryReference(attachment.existingId!),
      },
  };

  entry.fields.removeWhere((key, _) => !EntryFields.standard.contains(key));
  for (final field in draft.custom) {
    entry.fields[field.key.trim()] = KdbxTextField.fromText(
      text: field.value,
      protected: field.protected,
    );
  }
}

/// Configurazione TOTP guidata (decisione D4: solo URI
/// `otpauth://` incollato): toglie i campi TOTP esistenti, in qualunque
/// formato, e scrive [uri] nel campo `otp` protetto (formato di KeePassXC e
/// KeeWeb, letto da Keepass2Android). [InvalidTotpConfig] se l'URI non è
/// valido.
List<CustomFieldDraft> withTotpUri(List<CustomFieldDraft> custom, String uri) {
  final value = uri.trim();
  if (!value.toLowerCase().startsWith('otpauth://') ||
      parseTotp({TotpFields.otp: value}) == null) {
    throw const InvalidTotpConfig();
  }
  return List.unmodifiable([
    for (final field in custom)
      if (!isTotpField(field.key.trim())) field,
    CustomFieldDraft(key: TotpFields.otp, value: value, protected: true),
  ]);
}

/// Dimensione stimata di una versione in byte, come `PwEntry.GetSize` di
/// KeePass (2 byte per carattere, costi fissi per campo, allegato e tag).
int entrySize(KdbxDatabase database, KdbxEntry entry) {
  var bytes = 276 + entry.fields.length * 40 + entry.binaries.length * 65;
  var chars = (entry.overrideUrl ?? '').length;
  for (final MapEntry(:key, :value) in entry.fields.entries) {
    chars += key.length + value.text.length;
  }
  for (final MapEntry(:key, :value) in entry.binaries.entries) {
    chars += key.length;
    bytes += database.binaries.getByRef(value)?.data.length ?? 0;
  }
  for (final tag in entry.tags ?? const <String>[]) {
    bytes += 8;
    chars += tag.length;
  }
  return bytes + chars * 2;
}

/// Limita la cronologia come `PwEntry.MaintainBackups` di KeePass: al massimo
/// `HistoryMaxItems` versioni e `HistoryMaxSize` byte in tutto (valori
/// negativi o assenti: nessun limite), eliminando ogni volta la versione con
/// la modifica più vecchia.
void trimHistory(KdbxDatabase database, KdbxEntry entry) {
  int oldest() {
    var index = 0;
    for (var i = 1; i < entry.history.length; i++) {
      final time = entry.history[i].times.modification;
      if (time.isBefore(entry.history[index].times.modification)) index = i;
    }
    return index;
  }

  final maxItems = database.meta.historyMaxItems;
  if (maxItems != null && maxItems >= 0) {
    while (entry.history.length > maxItems) {
      entry.removeFromHistory(start: oldest());
    }
  }
  final maxSize = database.meta.historyMaxSize;
  if (maxSize != null && maxSize >= 0) {
    int total() => entry.history.fold(0, (s, h) => s + entrySize(database, h));
    while (entry.history.isNotEmpty && total() > maxSize) {
      entry.removeFromHistory(start: oldest());
    }
  }
}

/// Ripristina la versione [index] della cronologia (RestoreFromHistory di
/// EntryActivity): la versione attuale va nella cronologia.
DatabaseEdit restoreHistoryEdit(KdbxUuid uuid, int index) => (database) {
  final entry = findEntryByUuid(database, uuid);
  if (entry == null || index >= entry.history.length) {
    throw StateError('versione non trovata');
  }
  entry.restoreFromHistory(index);
  trimHistory(database, entry);
  database.cleanup(binaries: true);
};

/// Elimina la versione [index] della cronologia (RemoveFromHistory).
DatabaseEdit deleteHistoryEdit(KdbxUuid uuid, int index) => (database) {
  final entry = findEntryByUuid(database, uuid);
  if (entry == null || index >= entry.history.length) {
    throw StateError('versione non trovata');
  }
  entry.removeFromHistory(start: index);
  entry.times.touch();
  database.cleanup(binaries: true);
};

/// Modifica di una voce esistente: la versione attuale va nella cronologia
/// (UpdateEntry di Keepass2Android).
DatabaseEdit updateEntryEdit(KdbxUuid uuid, EntryDraft draft) => (database) {
  final entry = findEntryByUuid(database, uuid);
  if (entry == null) throw StateError('voce non trovata');
  entry.pushHistory();
  applyDraft(database, entry, draft);
  entry.times.touch();
  trimHistory(database, entry);
  // Allegati non più usati da voci e cronologie.
  database.cleanup(binaries: true);
};

/// Nuova voce nel gruppo [groupUuid] con UUID [uuid] scelto dal chiamante.
DatabaseEdit createEntryEdit(
  KdbxUuid groupUuid,
  KdbxUuid uuid,
  EntryDraft draft,
) => (database) {
  final group = database.getGroup(uuid: groupUuid);
  if (group == null) throw StateError('gruppo non trovato');
  final entry = database.createEntry(parent: group, icon: KdbxIcon.key);
  entry.uuid = uuid;
  applyDraft(database, entry, draft);
};

/// Modelli KeePass standard nel gruppo configurato nel database.
List<KdbxEntry> standardEntryTemplates(KdbxDatabase database) {
  return entryTemplates(database)
      .where((e) => !isStructuredTemplate(e))
      .toList();
}

/// Inizializza i campi dichiarati da un modello strutturato.
EntryDraft draftFromStructuredTemplate(KdbxEntry template) {
  final fields = <CustomFieldDraft>[];
  final names =
      template.fields.keys
          .where((key) => key.startsWith('_etm_title_'))
          .map((key) => key.substring('_etm_title_'.length))
          .toList()
        ..sort((a, b) {
          int position(String key) =>
              int.tryParse(entryField(template, '_etm_position_$key')) ??
              0x7fffffff;
          final order = position(a).compareTo(position(b));
          return order == 0 ? a.compareTo(b) : order;
        });
  bool allowed(String key) {
    final type = entryField(template, '_etm_type_$key');
    return type != 'Divider' && type != '@confirm';
  }

  for (final name in names) {
    if (name.startsWith('@') ||
        EntryFields.standard.contains(name) ||
        !allowed(name)) {
      continue;
    }
    fields.add(
      CustomFieldDraft(
        key: name,
        value: entryField(template, name),
        protected: entryField(
          template,
          '_etm_type_$name',
        ).startsWith('Protected'),
      ),
    );
  }
  fields.add(
    CustomFieldDraft(
      key: structuredTemplateReference,
      value: itemIdOf(template).toUpperCase(),
      protected: false,
    ),
  );
  String standard(String key) =>
      names.contains(key) && allowed(key) ? entryField(template, key) : '';
  final hasExpiry =
      names.contains('@exp_date') &&
      template.times.expires &&
      template.times.expiry.time != null;
  return EntryDraft(
    title: standard(EntryFields.title),
    userName: standard(EntryFields.userName),
    password: standard(EntryFields.password),
    url: standard(EntryFields.url),
    overrideUrl: names.contains('@override') ? template.overrideUrl ?? '' : '',
    notes: standard(EntryFields.notes),
    custom: fields,
    icon: template.icon,
    expires: hasExpiry,
    expiry: hasExpiry ? template.times.expiry.time?.toLocal() : null,
    tags: names.contains('@tags') ? [...?template.tags] : const [],
    attachments: EntryDraft.fromEntry(template).attachments,
  );
}

DatabaseEdit createFromTemplateEdit(
  KdbxUuid groupUuid,
  KdbxUuid uuid,
  String templateId,
  EntryDraft draft,
) => (database) {
  final group = database.getGroup(uuid: groupUuid);
  final template = entryTemplates(database)
      .where((e) => itemIdOf(e) == templateId)
      .firstOrNull;
  if (group == null ||
      template == null ||
      isInRecycleBin(database, group) ||
      database.root.allItems.any((e) => e.uuid == uuid)) {
    throw StateError('modello non disponibile');
  }
  KdbxEntry copyVersion(KdbxEntry source) {
    final copy = KdbxEntry.copyFrom(source, uuid)
      ..qualityCheck = source.qualityCheck;
    if (source.customData case final custom?) {
      copy.customData = KdbxCustomData()
        ..map = {
          for (final MapEntry(:key, :value) in custom.map.entries)
            key: KdbxCustomItem(
              value: value.value,
              modification: KdbxTime(value.modification.time),
            ),
        };
    }
    return copy;
  }

  final entry = copyVersion(template)..parent = group;
  if (isStructuredTemplate(template)) {
    entry.fields.clear();
    for (final key in EntryFields.standard) {
      entry.fields[key] = KdbxTextField.fromText(
        text: '',
        protected: entryField(
          template,
          '_etm_type_$key',
        ).startsWith('Protected'),
      );
    }
    if (!template.fields.containsKey('_etm_title_@override')) {
      entry.overrideUrl = '';
    }
    entry.history = [];
  } else {
    entry.history = [
      for (final version in template.history) copyVersion(version),
    ];
  }
  final now = KdbxTime.now();
  entry.times
    ..creation = now
    ..modification = now
    ..access = now
    ..locationChange = now
    ..usageCount = 0;
  applyDraft(database, entry, draft);
  group.entries.add(entry);
};

/// Voce da modificare ([entryId]) o gruppo in cui crearne una ([groupId]).
@immutable
class EntryEditTarget {
  const EntryEditTarget.edit(String this.entryId)
    : groupId = null,
      templateId = null;
  const EntryEditTarget.create(String this.groupId, {this.templateId})
    : entryId = null;

  final String? entryId;
  final String? groupId;
  final String? templateId;

  @override
  bool operator ==(Object other) =>
      other is EntryEditTarget &&
      other.entryId == entryId &&
      other.groupId == groupId &&
      other.templateId == templateId;

  @override
  int get hashCode => Object.hash(entryId, groupId, templateId);
}

/// Contenuto iniziale del form; `null` se voce o gruppo non esistono più.
final entryInitialDraftProvider = Provider.autoDispose
    .family<EntryDraft?, EntryEditTarget>((ref, target) {
      final session = ref.watch(databaseSessionProvider);
      if (session == null) return null;
      final db = session.database;
      if (target.entryId case final id?) {
        final entry = findEntry(db, id);
        return entry == null ? null : EntryDraft.fromEntry(entry, database: db);
      }
      if (findGroup(db, target.groupId) == null) return null;
      if (target.templateId case final id?) {
        final template = entryTemplates(db)
            .where((e) => itemIdOf(e) == id)
            .firstOrNull;
        return template == null
            ? null
            : isStructuredTemplate(template)
            ? draftFromStructuredTemplate(template)
            : EntryDraft.fromEntry(template);
      }
      return EntryDraft(userName: db.meta.defaultUser ?? '');
    });

/// Salvataggio della voce. Lo stato contiene l'identificatore della voce
/// salvata (`null` finché non si salva); in caso di errore il database in
/// memoria è rimasto com'era.
final entryEditViewModelProvider = AsyncNotifierProvider.autoDispose
    .family<EntryEditViewModel, String?, EntryEditTarget>(
      EntryEditViewModel.new,
    );

class EntryEditViewModel extends AsyncNotifier<String?> {
  EntryEditViewModel(this.target);

  final EntryEditTarget target;

  @override
  FutureOr<String?> build() => null;

  /// Salva [draft]. Restituisce l'identificatore della voce o `null` se il
  /// salvataggio non è riuscito.
  Future<String?> save(EntryDraft draft) async {
    if (state.isLoading) return null;
    final session = ref.read(databaseSessionProvider);
    if (session == null) return null;
    final db = session.database;

    String entryId;
    DatabaseEdit edit;
    if (target.entryId case final id?) {
      final entry = findEntry(db, id);
      if (entry == null) return null;
      entryId = id;
      // Nessuna modifica: niente nuova versione nella cronologia.
      if (EntryDraft.fromEntry(entry, database: db) == draft) return id;
      edit = updateEntryEdit(entry.uuid, draft);
    } else {
      final group = findGroup(db, target.groupId);
      if (group == null) return null;
      final uuid = KdbxUuid.random(
        prohibited: db.root.allItems.map((i) => i.uuid).toSet(),
      );
      entryId = idOfUuid(uuid);
      edit = target.templateId == null
          ? createEntryEdit(group.uuid, uuid, draft)
          : createFromTemplateEdit(group.uuid, uuid, target.templateId!, draft);
    }

    state = const AsyncLoading();
    final result = await AsyncValue.guard(() async {
      await ref.read(databaseSessionProvider.notifier).apply(edit);
      return entryId;
    });
    if (ref.mounted) state = result;
    return result.value;
  }
}
