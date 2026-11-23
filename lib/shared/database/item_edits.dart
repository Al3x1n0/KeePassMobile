import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import 'database_session.dart';
import 'entry_templates.dart';
import 'kdbx_items.dart';

/// Operazione non ammessa, senza identificatori o contenuto nei messaggi.
final class InvalidItemEditException implements Exception {
  const InvalidItemEditException();
}

/// Nome e icona modificabili di un gruppo; le altre proprietà si conservano.
class IconChoice {
  const IconChoice({required this.icon, this.customId, this.data});
  final KdbxIcon icon;
  final KdbxUuid? customId;
  final List<int>? data;
}

void applyIconChoice(KdbxDatabase database, KdbxItem item, IconChoice choice) {
  final id = choice.customId;
  if (id != null) {
    if (choice.data case final bytes?) {
      if (bytes.isEmpty ||
          bytes.length > 1024 * 1024 ||
          database.meta.customIcons.containsKey(id)) {
        throw const InvalidItemEditException();
      }
      database.meta.customIcons[id] = KdbxCustomIcon(data: bytes);
    } else if (!database.meta.customIcons.containsKey(id)) {
      throw const InvalidItemEditException();
    }
  }
  item.icon = choice.icon;
  item.customIcon = id;
}

class GroupDraft {
  const GroupDraft({required this.name, required this.icon, this.iconChoice});
  final String name;
  final KdbxIcon icon;
  final IconChoice? iconChoice;
}

KdbxItem? _item(KdbxDatabase database, String id) =>
    database.root.allItems.where((i) => itemIdOf(i) == id).firstOrNull;

/// Destinazione valida per MoveElements: niente radice/cestino come sorgente,
/// cicli, gruppi nel cestino o spostamenti nella cartella corrente.
bool canMoveItem(KdbxDatabase database, KdbxItem item, KdbxGroup target) {
  if (item == database.root ||
      item == existingRecycleBin(database) ||
      isInRecycleBin(database, target) ||
      item.parent == target) {
    return false;
  }
  for (KdbxGroup? group = target; group != null; group = group.parent) {
    if (group == item) return false;
  }
  return true;
}

DatabaseEdit createGroupEdit(
  String parentId,
  KdbxUuid uuid,
  GroupDraft draft,
) => (database) {
  final parent = findGroup(database, parentId);
  if (parent == null ||
      isInRecycleBin(database, parent) ||
      draft.name.trim().isEmpty ||
      database.root.allItems.any((i) => i.uuid == uuid)) {
    throw const InvalidItemEditException();
  }
  final group = database.createGroup(
    parent: parent,
    name: draft.name.trim(),
    icon: draft.icon,
  )..uuid = uuid;
  if (draft.iconChoice case final choice?) {
    applyIconChoice(database, group, choice);
  }
};

DatabaseEdit updateGroupEdit(String id, GroupDraft draft) => (database) {
  final group = findGroup(database, id);
  if (group == null ||
      isInRecycleBin(database, group) ||
      draft.name.trim().isEmpty) {
    throw const InvalidItemEditException();
  }
  group.name = draft.name.trim();
  if (draft.iconChoice case final choice?) {
    applyIconChoice(database, group, choice);
  } else if (group.icon != draft.icon) {
    group.icon = draft.icon;
    group.customIcon = null;
  }
  group.times.touch();
};

DatabaseEdit moveItemEdit(String id, String targetId) => (database) {
  final item = _item(database, id);
  final target = findGroup(database, targetId);
  if (item == null || target == null || !canMoveItem(database, item, target)) {
    throw const InvalidItemEditException();
  }
  database.move(item: item, target: target);
};

DatabaseEdit moveItemsEdit(
  List<String> ids,
  String parentId,
  String targetId,
) => (database) {
  final parent = findGroup(database, parentId);
  final target = findGroup(database, targetId);
  final items = ids.map((id) => _item(database, id)).toList();
  if (parent == null ||
      target == null ||
      ids.isEmpty ||
      ids.toSet().length != ids.length ||
      items.any(
        (item) =>
            item == null ||
            item.parent != parent ||
            !canMoveItem(database, item, target),
      )) {
    throw const InvalidItemEditException();
  }
  for (final item in items) {
    database.move(item: item!, target: target);
  }
};

DatabaseEdit moveSearchEntriesEdit(List<String> ids, String targetId) =>
    (database) {
      final target = findGroup(database, targetId);
      final entries = ids.map((id) => findEntry(database, id)).toList();
      if (target == null ||
          ids.isEmpty ||
          ids.toSet().length != ids.length ||
          entries.any(
            (entry) =>
                entry == null ||
                isInRecycleBin(database, entry) ||
                !canMoveItem(database, entry, target),
          )) {
        throw const InvalidItemEditException();
      }
      for (final entry in entries) {
        database.move(item: entry!, target: target);
      }
    };

DatabaseEdit deleteGroupEdit(String id) => (database) {
  final group = findGroup(database, id);
  if (group == null ||
      group == database.root ||
      group == existingRecycleBin(database)) {
    throw const InvalidItemEditException();
  }
  database.remove(group);
  database.cleanup(binaries: true);
};

/// Elimina insieme elementi dello stesso gruppo dopo averli validati tutti.
DatabaseEdit deleteItemsEdit(List<String> ids, String parentId) => (database) {
  final parent = findGroup(database, parentId);
  final items = ids.map((id) => _item(database, id)).toList();
  if (parent == null ||
      ids.isEmpty ||
      ids.toSet().length != ids.length ||
      items.any(
        (item) =>
            item == null ||
            item.parent != parent ||
            item == existingRecycleBin(database),
      )) {
    throw const InvalidItemEditException();
  }
  for (final item in items) {
    database.remove(item!);
  }
  database.cleanup(binaries: true);
};

DatabaseEdit deleteSearchEntriesEdit(List<String> ids) => (database) {
  final entries = ids.map((id) => findEntry(database, id)).toList();
  if (ids.isEmpty ||
      ids.toSet().length != ids.length ||
      entries.any(
        (entry) => entry == null || isInRecycleBin(database, entry),
      )) {
    throw const InvalidItemEditException();
  }
  for (final entry in entries) {
    database.remove(entry!);
  }
  database.cleanup(binaries: true);
};

/// Ripristino nel gruppo precedente quando esiste ancora, altrimenti radice.
DatabaseEdit restoreItemEdit(String id) => (database) {
  final item = _item(database, id);
  if (item == null ||
      item == existingRecycleBin(database) ||
      !isInRecycleBin(database, item)) {
    throw const InvalidItemEditException();
  }
  final previous = database.getGroup(uuid: item.previousParent);
  final target = previous != null && canMoveItem(database, item, previous)
      ? previous
      : database.root;
  if (!canMoveItem(database, item, target)) {
    throw const InvalidItemEditException();
  }
  database.move(item: item, target: target);
};

DatabaseEdit restoreItemsEdit(List<String> ids, String parentId) => (database) {
  final parent = findGroup(database, parentId);
  final items = ids.map((id) => _item(database, id)).toList();
  if (parent == null ||
      !isInRecycleBin(database, parent) ||
      ids.isEmpty ||
      ids.toSet().length != ids.length ||
      items.any(
        (item) =>
            item == null ||
            item.parent != parent ||
            !isInRecycleBin(database, item),
      )) {
    throw const InvalidItemEditException();
  }
  final targets = <KdbxGroup>[];
  for (final item in items) {
    final previous = database.getGroup(uuid: item!.previousParent);
    final target = previous != null && canMoveItem(database, item, previous)
        ? previous
        : database.root;
    if (!canMoveItem(database, item, target)) {
      throw const InvalidItemEditException();
    }
    targets.add(target);
  }
  for (var index = 0; index < items.length; index++) {
    database.move(item: items[index]!, target: targets[index]);
  }
};

DatabaseEdit emptyRecycleBinEdit() => (database) {
  final bin = existingRecycleBin(database);
  if (bin == null) return;
  for (final item in [...bin.groups, ...bin.entries]) {
    database.move(item: item, target: null);
  }
  bin.times.touch();
  database.cleanup(binaries: true);
};

KdbxEntry _cloneEntry(KdbxEntry source, KdbxUuid uuid) {
  final copy = KdbxEntry.copyFrom(source, uuid)
    ..qualityCheck = source.qualityCheck
    ..previousParent = source.previousParent;
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

/// CopyEntry: nuova identità e cronologia con lo stesso nuovo UUID. Binari
/// condivisi tramite riferimenti KDBX, campi protetti e metadati conservati.
DatabaseEdit duplicateEntryEdit(String id, KdbxUuid uuid, String suffix) =>
    (database) {
      final entry = findEntry(database, id);
      final parent = entry?.parent;
      if (entry == null ||
          parent == null ||
          isInRecycleBin(database, entry) ||
          database.root.allItems.any((i) => i.uuid == uuid)) {
        throw const InvalidItemEditException();
      }
      final copy = _cloneEntry(entry, uuid)..parent = parent;
      copy.history = [
        for (final version in entry.history) _cloneEntry(version, uuid),
      ];
      final title = entry.fields[EntryFields.title];
      copy.fields[EntryFields.title] = KdbxTextField.fromText(
        text: '${title?.text ?? ''} - $suffix',
        protected: title is ProtectedTextField,
      );
      copy.times.touch();
      parent.entries.add(copy);
    };

/// Destinazione mostrata dalla UI, identificata solo dall'UUID.
class GroupDestination {
  const GroupDestination(this.id, this.label);
  final String id;
  final String label;
}

List<GroupDestination> moveDestinations(
  KdbxDatabase database,
  List<String> ids,
) {
  final items = ids.map((id) => _item(database, id)).toList();
  if (items.isEmpty || items.any((item) => item == null)) return const [];
  final result = <GroupDestination>[];
  void visit(KdbxGroup group, String parentPath) {
    final path = parentPath.isEmpty
        ? group.name
        : '$parentPath / ${group.name}';
    if (items.every((item) => canMoveItem(database, item!, group))) {
      result.add(GroupDestination(itemIdOf(group), path));
    }
    for (final child in group.groups) {
      if (!isInRecycleBin(database, child)) visit(child, path);
    }
  }

  visit(database.root, '');
  return List.unmodifiable(result);
}

/// Azioni strutturali salvate con la stessa transazione delle modifiche voci.
final itemActionsProvider = AsyncNotifierProvider.autoDispose
    .family<ItemActions, void, String>(ItemActions.new);

class ItemActions extends AsyncNotifier<void> {
  ItemActions(this.id);
  final String id;
  @override
  FutureOr<void> build() {}

  KdbxUuid? _newUuid() {
    final database = ref.read(databaseSessionProvider)?.database;
    return database == null
        ? null
        : KdbxUuid.random(
            prohibited: database.root.allItems.map((i) => i.uuid).toSet(),
          );
  }

  Future<String?> create(GroupDraft draft) async {
    final uuid = _newUuid();
    if (uuid == null) return null;
    return await _apply(createGroupEdit(id, uuid, draft))
        ? idOfUuid(uuid)
        : null;
  }

  Future<bool> editGroup(GroupDraft draft) =>
      _apply(updateGroupEdit(id, draft));
  Future<bool> move(String target) => _apply(moveItemEdit(id, target));
  Future<bool> moveItems(List<String> ids, String target) =>
      _apply(moveItemsEdit(ids, id, target));
  Future<bool> moveSearchEntries(List<String> ids, String target) =>
      _apply(moveSearchEntriesEdit(ids, target));
  Future<bool> deleteGroup() => _apply(deleteGroupEdit(id));
  Future<bool> deleteItems(List<String> ids) =>
      _apply(deleteItemsEdit(ids, id));
  Future<bool> deleteSearchEntries(List<String> ids) =>
      _apply(deleteSearchEntriesEdit(ids));
  Future<bool> addBuiltInTemplates(BuiltInTemplateLabels labels) =>
      _apply(addBuiltInTemplatesEdit(labels));
  Future<bool> restore() => _apply(restoreItemEdit(id));
  Future<bool> restoreItems(List<String> ids) =>
      _apply(restoreItemsEdit(ids, id));
  Future<bool> emptyBin() => _apply(emptyRecycleBinEdit());
  Future<String?> duplicate(String suffix) async {
    final uuid = _newUuid();
    if (uuid == null) return null;
    return await _apply(duplicateEntryEdit(id, uuid, suffix))
        ? idOfUuid(uuid)
        : null;
  }

  Future<bool> _apply(DatabaseEdit edit) async {
    if (state.isLoading) return false;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(databaseSessionProvider.notifier).apply(edit),
    );
    if (ref.mounted) state = result;
    return !result.hasError;
  }
}
