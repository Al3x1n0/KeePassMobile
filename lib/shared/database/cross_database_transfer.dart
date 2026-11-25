import 'package:kpasslib/kpasslib.dart';

import 'database_session.dart';
import 'item_edits.dart';
import 'kdbx_items.dart';

/// Copies an item tree with its metadata and attachments into [destination].
void copyItemBetweenDatabases(
  KdbxDatabase source,
  KdbxDatabase destination,
  KdbxItem item,
  KdbxGroup target,
) {
  if (item is KdbxEntry) {
    destination.importEntry(entry: item, target: target, other: source);
    return;
  }
  if (item is! KdbxGroup) throw const InvalidItemEditException();
  final copy = KdbxGroup.copyFrom(
    item,
    KdbxUuid.random(
      prohibited: destination.root.allItems.map((e) => e.uuid).toSet(),
    ),
  )..parent = target;
  copy.previousParent = null;
  copy.lastTopVisibleEntry = null;
  if (item.customData case final custom?) {
    copy.customData = KdbxCustomData()
      ..map = {
        for (final e in custom.map.entries)
          e.key: KdbxCustomItem(
            value: e.value.value,
            modification: KdbxTime(e.value.modification.time),
          ),
      };
  }
  if (item.customIcon case final id?) {
    final icon = source.meta.customIcons[id];
    if (icon == null) throw const InvalidItemEditException();
    final targetId = destination.meta.customIcons.containsKey(id)
        ? KdbxUuid.random(prohibited: destination.meta.customIcons.keys.toSet())
        : id;
    destination.meta.customIcons[targetId] = KdbxCustomIcon(
      data: List.of(icon.data),
      name: icon.name,
      modified: KdbxTime(icon.modified.time),
    );
    copy.customIcon = targetId;
  }
  target.groups.add(copy);
  for (final child in item.groups) {
    copyItemBetweenDatabases(source, destination, child, copy);
  }
  for (final entry in item.entries) {
    copyItemBetweenDatabases(source, destination, entry, copy);
  }
}

/// A detached in-memory snapshot without the source database's credentials.
KdbxDatabase snapshotItems(KdbxDatabase source, List<String> ids) {
  if (ids.isEmpty || ids.toSet().length != ids.length) {
    throw const InvalidItemEditException();
  }
  final items = ids
      .map(
        (id) => source.root.allItems
            .where((item) => itemIdOf(item) == id)
            .firstOrNull,
      )
      .toList();
  if (items.any(
    (item) =>
        item == null || item == source.root || isInRecycleBin(source, item),
  )) {
    throw const InvalidItemEditException();
  }
  for (final item in items) {
    for (var parent = item!.parent; parent != null; parent = parent.parent) {
      if (items.contains(parent)) throw const InvalidItemEditException();
    }
  }
  final snapshot = KdbxDatabase.create(
    credentials: KdbxCredentials(password: ProtectedData.fromString('')),
    name: '',
  );
  snapshot.root.groups.clear();
  for (final item in items) {
    copyItemBetweenDatabases(source, snapshot, item!, snapshot.root);
  }
  return snapshot;
}

DatabaseEdit copySnapshotEdit(KdbxDatabase snapshot, String targetId) => (db) {
  final target = findGroup(db, targetId);
  if (target == null ||
      isInRecycleBin(db, target) ||
      isInTemplatesGroup(db, target)) {
    throw const InvalidItemEditException();
  }
  for (final item in snapshot.root.children) {
    copyItemBetweenDatabases(snapshot, db, item, target);
  }
};

DatabaseEdit removeTransferredItemsEdit(List<String> ids) => (db) {
  final items = ids
      .map(
        (id) =>
            db.root.allItems.where((item) => itemIdOf(item) == id).firstOrNull,
      )
      .toList();
  if (items.isEmpty ||
      ids.toSet().length != ids.length ||
      items.any(
        (item) => item == null || item == db.root || isInRecycleBin(db, item),
      )) {
    throw const InvalidItemEditException();
  }
  for (final item in items) {
    db.move(item: item!);
  }
  db.cleanup(binaries: true);
};
