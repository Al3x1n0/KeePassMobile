import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// Conferma la rimozione definitiva della copia dimostrativa privata.
Future<bool> showDemoDatabaseRemovalDialog(
  BuildContext context, {
  bool clearingRecents = false,
}) async {
  final l10n = AppLocalizations.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.demoDatabaseRemoveTitle),
          content: Text(
            clearingRecents
                ? l10n.demoDatabaseRemoveWithRecents
                : l10n.demoDatabaseRemoveMessage,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.demoDatabaseRemoveConfirm),
            ),
          ],
        ),
      ) ??
      false;
}
