import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../l10n/app_localizations.dart';
import '../database/cross_database_transfer.dart';
import '../database/database_session.dart';
import '../database/kdbx_items.dart';
import '../storage/file_storage.dart';
import 'selection_sheet.dart';

class _Target {
  const _Target(this.file, this.group);
  final FileRef file;
  final String group;
}

/// Seleziona un gruppo di un altro database e trasferisce gli elementi.
Future<bool> copyToAnotherDatabase(
  BuildContext context,
  WidgetRef ref,
  List<String> ids, {
  bool move = false,
}) async {
  final notifier = ref.read(databaseSessionProvider.notifier);
  final source = ref.read(databaseSessionProvider);
  if (source == null || notifier.isSaving) return false;
  final targets = <_Target, String>{};
  for (final session in notifier.openSessions) {
    if (session.file == source.file) continue;
    void visit(KdbxGroup group, String prefix) {
      final path = prefix.isEmpty ? group.name : '$prefix / ${group.name}';
      targets[_Target(session.file, itemIdOf(group))] =
          '${session.file.name} / $path';
      for (final child in group.groups) {
        if (!isInRecycleBin(session.database, child)) visit(child, path);
      }
    }

    visit(session.database.root, '');
  }
  final l10n = AppLocalizations.of(context);
  final target = await showSelectionSheet<_Target>(
    context: context,
    title: move ? l10n.databasesMove : l10n.databasesCopy,
    options: targets,
  );
  if (target == null || !context.mounted) return false;
  final generation = notifier.lockGeneration;
  if (ref.read(databaseSessionProvider)?.database != source.database) {
    return false;
  }
  var copied = false;
  try {
    final snapshot = snapshotItems(source.database, ids);
    notifier.switchTo(target.file);
    await notifier.apply(copySnapshotEdit(snapshot, target.group));
    copied = true;
    if (move) {
      final active = context.mounted ? ref.read(databaseSessionProvider) : null;
      if (active == null ||
          notifier.lockGeneration != generation ||
          active.file != target.file ||
          active.cacheStatus.pending ||
          active.cacheStatus.offline ||
          !notifier.openSessions.any(
            (s) => s.file == source.file && s.database == source.database,
          )) {
        throw const DatabaseLockedException();
      }
      notifier.switchTo(source.file);
      await notifier.apply(removeTransferredItemsEdit(ids));
    }
    return true;
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            copied && move ? l10n.databasesMoveIncomplete : l10n.errorGeneric,
          ),
        ),
      );
    }
    return false;
  } finally {
    if (context.mounted &&
        notifier.lockGeneration == generation &&
        ref.read(databaseSessionProvider)?.file == target.file &&
        notifier.openSessions.any((session) => session.file == source.file)) {
      notifier.switchTo(source.file);
    }
  }
}
