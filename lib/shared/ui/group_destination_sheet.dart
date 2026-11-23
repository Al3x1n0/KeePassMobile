import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../database/database_session.dart';
import '../database/item_edits.dart';
import 'selection_sheet.dart';

/// Mostra i gruppi in cui è possibile spostare tutti gli elementi indicati.
Future<String?> showGroupDestinationSheet(
  BuildContext context,
  List<String> itemIds,
) {
  final l10n = AppLocalizations.of(context);
  return showListSheet<String>(
    context: context,
    title: l10n.itemMoveTitle,
    buildItems: (_) => [
      Consumer(
        builder: (context, ref, _) {
          final database = ref.watch(
            databaseSessionProvider.select((session) => session?.database),
          );
          final destinations = database == null
              ? const <GroupDestination>[]
              : moveDestinations(database, itemIds);
          if (destinations.isEmpty) {
            return ListTile(title: Text(l10n.itemNoDestination));
          }
          return Column(
            children: [
              for (final target in destinations)
                ListTile(
                  title: Text(target.label),
                  onTap: () => Navigator.pop(context, target.id),
                ),
            ],
          );
        },
      ),
    ],
  );
}
