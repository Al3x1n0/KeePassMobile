import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'screen_protection.dart';

class ScreenProtectionWarning extends ConsumerWidget {
  const ScreenProtectionWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSecureScreen)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l10n.screenProtectionWarning),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: ref
                  .read(screenProtectionStatusProvider.notifier)
                  .acknowledge,
              child: Text(l10n.screenProtectionContinue),
            ),
          ],
        ),
      ),
    );
  }
}
