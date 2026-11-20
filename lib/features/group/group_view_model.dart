import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/database/database_session.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/storage/preferences.dart';

/// Ordine visualizzato per gruppi e voci, senza modificare il database.
enum GroupSortOrder { ascending, descending, database, modification, creation }

final groupSortOrderProvider =
    NotifierProvider<GroupSortOrderNotifier, GroupSortOrder>(
      GroupSortOrderNotifier.new,
    );

class GroupSortOrderNotifier extends Notifier<GroupSortOrder> {
  static const _preferenceKey = 'group.sort_order';

  @override
  GroupSortOrder build() {
    final value = ref
        .watch(sharedPreferencesProvider)
        .getString(_preferenceKey);
    return GroupSortOrder.values
            .where((order) => order.name == value)
            .firstOrNull ??
        GroupSortOrder.ascending;
  }

  Future<void> select(GroupSortOrder order) async {
    state = order;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_preferenceKey, order.name);
  }
}

/// Contenuto di un gruppo: sottogruppi e voci ordinati per nome, senza
/// distinzione tra maiuscole e minuscole.
@immutable
class GroupContent {
  const GroupContent({
    required this.group,
    required this.groups,
    required this.entries,
    required this.recycleBin,
  });

  final KdbxGroup group;
  final List<KdbxGroup> groups;
  final List<KdbxEntry> entries;

  /// Il cestino del database, se esiste (per distinguerlo nell'elenco).
  final KdbxGroup? recycleBin;

  bool get isEmpty => groups.isEmpty && entries.isEmpty;
}

/// Contenuto del gruppo [groupId] (`null` = gruppo radice).
///
/// `null` se il database è chiuso o il gruppo non esiste più.
final groupContentProvider = Provider.autoDispose
    .family<GroupContent?, String?>((ref, groupId) {
      final session = ref.watch(databaseSessionProvider);
      if (session == null) return null;
      final group = findGroup(session.database, groupId);
      if (group == null) return null;
      final order = ref.watch(groupSortOrderProvider);

      int byText(String a, String b) => order == GroupSortOrder.descending
          ? b.toLowerCase().compareTo(a.toLowerCase())
          : a.toLowerCase().compareTo(b.toLowerCase());
      final groups = [...group.groups];
      final entries = [...group.entries];
      if (order == GroupSortOrder.modification) {
        groups.sort(
          (a, b) => b.times.modification.compareTo(a.times.modification),
        );
        entries.sort(
          (a, b) => b.times.modification.compareTo(a.times.modification),
        );
      } else if (order == GroupSortOrder.creation) {
        groups.sort((a, b) => a.times.creation.compareTo(b.times.creation));
        entries.sort((a, b) => a.times.creation.compareTo(b.times.creation));
      } else if (order != GroupSortOrder.database) {
        groups.sort((a, b) => byText(a.name, b.name));
        entries.sort((a, b) {
          final titleA = entryTitle(a);
          final titleB = entryTitle(b);
          final titleOrder = byText(titleA, titleB);
          if (titleOrder != 0) return titleOrder;
          if (titleA == '<TAN>' && titleB == '<TAN>') {
            final indexA = entryUserName(a);
            final indexB = entryUserName(b);
            final numberA = int.tryParse(indexA);
            final numberB = int.tryParse(indexB);
            int indexOrder;
            if (numberA != null && numberB != null) {
              indexOrder = numberA.compareTo(numberB);
              if (order == GroupSortOrder.descending) indexOrder = -indexOrder;
            } else if (numberA != null || numberB != null) {
              indexOrder = numberA != null ? -1 : 1;
              if (order == GroupSortOrder.descending) indexOrder = -indexOrder;
            } else {
              indexOrder = byText(indexA, indexB);
            }
            if (indexOrder != 0) return indexOrder;
          }
          return a.times.creation.compareTo(b.times.creation);
        });
      }
      return GroupContent(
        group: group,
        groups: List.unmodifiable(groups),
        entries: List.unmodifiable(entries),
        recycleBin: existingRecycleBin(session.database),
      );
    });
