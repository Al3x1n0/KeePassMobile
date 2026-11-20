import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../database/item_edits.dart';

/// Selettore dei soli gruppi in cui lo spostamento è valido.
class GroupDestinationDialog extends ConsumerWidget {
  const GroupDestinationDialog({super.key, required this.itemId});
  final String itemId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = ref.watch(moveDestinationsProvider(itemId));
    return GroupDestinationsDialog(destinations: destinations);
  }
}

class GroupDestinationsDialog extends StatelessWidget {
  const GroupDestinationsDialog({super.key, required this.destinations});
  final List<GroupDestination> destinations;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.itemMoveTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (destinations.isEmpty) Text(l10n.itemNoDestination),
            for (final target in destinations)
              ListTile(
                title: Text(target.label),
                onTap: () => Navigator.of(context).pop(target.id),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
