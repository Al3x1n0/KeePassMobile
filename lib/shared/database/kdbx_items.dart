import 'package:kpasslib/kpasslib.dart';

/// Nomi dei campi standard di una voce KeePass.
abstract final class EntryFields {
  static const title = 'Title';
  static const userName = 'UserName';
  static const password = 'Password';
  static const url = 'URL';
  static const notes = 'Notes';

  static const standard = {title, userName, password, url, notes};
}

/// Identificatore di un gruppo o di una voce adatto agli URL: UUID in
/// esadecimale (l'UUID KeePass in base64 contiene `/` e `+`).
String itemIdOf(KdbxItem item) => idOfUuid(item.uuid);

String idOfUuid(KdbxUuid uuid) =>
    uuid.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Gruppo con identificatore [groupId] (`null` = radice); `null` se non esiste.
KdbxGroup? findGroup(KdbxDatabase db, String? groupId) {
  final root = db.root;
  if (groupId == null) return root;
  return [
    root,
    ...root.allGroups,
  ].where((g) => itemIdOf(g) == groupId).firstOrNull;
}

/// Voce con identificatore [entryId]; `null` se non esiste più.
KdbxEntry? findEntry(KdbxDatabase db, String entryId) =>
    db.root.allEntries.where((e) => itemIdOf(e) == entryId).firstOrNull;

/// Voce con UUID [uuid]; `null` se non esiste più.
KdbxEntry? findEntryByUuid(KdbxDatabase db, KdbxUuid uuid) =>
    db.root.allEntries.where((e) => e.uuid == uuid).firstOrNull;

String entryField(KdbxEntry entry, String key) => entry.fields[key]?.text ?? '';

String entryTitle(KdbxEntry entry) => entryField(entry, EntryFields.title);

String entryUserName(KdbxEntry entry) =>
    entryField(entry, EntryFields.userName);

/// Percorso KeePass con separatore punto e radice esclusa, salvo la radice stessa.
String groupFullPath(KdbxGroup group) {
  final names = <String>[group.name];
  var parent = group.parent;
  while (parent != null && parent.parent != null) {
    names.add(parent.name);
    parent = parent.parent;
  }
  return names.reversed.join('.');
}

/// `true` se la voce scade e la scadenza è passata (PwEntryView di
/// Keepass2Android).
bool isExpired(KdbxEntry entry, DateTime now) {
  final expiry = entry.times.expiry.time;
  return entry.times.expires && expiry != null && expiry.isBefore(now);
}

/// Tag da un testo libero, come `StrUtil.StringToTags` di KeePass: separati da
/// `,` o `;`, senza spazi ai lati, senza vuoti né duplicati, in ordine
/// alfabetico.
List<String> parseTags(String text) {
  final tags = {
    for (final part in text.split(RegExp('[,;]')))
      if (part.trim() case final tag when tag.isNotEmpty) tag,
  }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return List.unmodifiable(tags);
}

/// Testo dei tag per la modifica e la visualizzazione (`TagsToString`).
String tagsText(List<String> tags) => tags.join(', ');

/// Il cestino del database, senza crearlo (a differenza di
/// [KdbxDatabase.recycleBin], che lo crea se manca).
KdbxGroup? existingRecycleBin(KdbxDatabase db) {
  if (!db.meta.recycleBinEnabled) return null;
  final uuid = db.meta.recycleBinUuid;
  if (uuid == null || uuid == KdbxUuid.zero) return null;
  return db.getGroup(uuid: uuid);
}

/// `true` se [item] è il cestino o si trova al suo interno.
bool isInRecycleBin(KdbxDatabase db, KdbxItem item) {
  final bin = existingRecycleBin(db);
  if (bin == null) return false;
  for (KdbxItem? i = item; i != null; i = i.parent) {
    if (i == bin) return true;
  }
  return false;
}

/// `true` se eliminare [item] lo cancella definitivamente invece di spostarlo
/// nel cestino (cestino disattivato o voce già nel cestino), come
/// DeleteRunnable di Keepass2Android.
bool deletesPermanently(KdbxDatabase db, KdbxItem item) =>
    !db.meta.recycleBinEnabled || isInRecycleBin(db, item);
