import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/ui/app_dialog.dart';
import '../l10n/app_localizations.dart';
import '../shared/database/external_change.dart';
import 'router.dart';

/// Domanda "Sincronizzare?" di Keepass2Android (`SaveDb.cs`) sopra la
/// schermata in cui si sta salvando. Senza scelta: annulla.
ExternalChangeResolver externalChangeDialog(Ref ref) => (file) async {
  final context = ref
      .read(routerProvider)
      .routerDelegate
      .navigatorKey
      .currentContext;
  if (context == null || !context.mounted) return ExternalChangeChoice.cancel;
  final l10n = AppLocalizations.of(context);
  final choice = await showDialog<ExternalChangeChoice>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AppDialog(
      icon: const Icon(Icons.sync_problem_outlined),
      title: Text(l10n.externalChangeTitle),
      body: Text(l10n.externalChangeBody(file.name)),
      actions: [
        AppDialogAction(
          onPressed: () =>
              Navigator.of(context).pop(ExternalChangeChoice.cancel),
          child: Text(l10n.externalChangeCancel),
        ),
        AppDialogAction(
          onPressed: () =>
              Navigator.of(context).pop(ExternalChangeChoice.overwrite),
          child: Text(l10n.externalChangeOverwrite),
        ),
        AppDialogAction(
          onPressed: () =>
              Navigator.of(context).pop(ExternalChangeChoice.synchronize),
          child: Text(l10n.externalChangeSynchronize),
        ),
      ],
    ),
  );
  return choice ?? ExternalChangeChoice.cancel;
};
