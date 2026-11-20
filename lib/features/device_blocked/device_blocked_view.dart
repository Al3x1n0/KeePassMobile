import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';

/// Schermata unica dell'app su un dispositivo con root, jailbreak o
/// configurazione non sicura (decisione D9): nessuna azione possibile, nessun
/// dettaglio sul controllo che ha bloccato l'app.
class DeviceBlockedView extends StatelessWidget {
  const DeviceBlockedView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: appFormMaxWidth),
              child: Column(
                children: [
                  Icon(
                    Icons.gpp_bad_outlined,
                    size: AppSpacing.l * 3,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: AppSpacing.l),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.deviceBlockedTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  Text(
                    l10n.deviceBlockedBody,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
