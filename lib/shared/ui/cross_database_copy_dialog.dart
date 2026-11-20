import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../l10n/app_localizations.dart';
import '../database/cross_database_transfer.dart';
import '../database/database_session.dart';
import '../database/kdbx_items.dart';
import '../storage/file_storage.dart';

class _Target {
  const _Target(this.file, this.group, this.label);
  final FileRef file;
  final String group;
  final String label;
}

Future<bool> copyToAnotherDatabase(
  BuildContext context,
  WidgetRef ref,
  List<String> ids, {
  bool move = false,
}) async {
  final notifier = ref.read(databaseSessionProvider.notifier);
  final source = ref.read(databaseSessionProvider);
  if (source == null || notifier.isSaving) return false;
  final targets = <_Target>[];
  for (final session in notifier.openSessions) {
    if (session.file == source.file) continue;
    void visit(KdbxGroup group, String prefix) {
      final path = prefix.isEmpty ? group.name : '$prefix / ${group.name}';
      targets.add(
        _Target(session.file, itemIdOf(group), '${session.file.name} / $path'),
      );
      for (final child in group.groups) {
        if (!isInRecycleBin(session.database, child)) visit(child, path);
      }
    }

    visit(session.database.root, '');
  }
  final l10n = AppLocalizations.of(context);
  final target = await showDialog<_Target>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(move ? l10n.databasesMove : l10n.databasesCopy),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final target in targets)
              ListTile(
                title: Text(target.label),
                onTap: () => Navigator.pop(context, target),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    ),
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
