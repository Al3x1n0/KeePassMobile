import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'routes.dart';

/// Destinazioni principali durante la consultazione del database.
class DatabaseNavigationBar extends StatelessWidget {
  const DatabaseNavigationBar({super.key, this.settingsSelected = false});

  final bool settingsSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NavigationBar(
      selectedIndex: settingsSelected ? 3 : 0,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            if (settingsSelected && context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.database);
            }
          case 3 when !settingsSelected:
            context.push(AppRoutes.appSettingsInDatabase);
        }
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          label: l10n.navigationHome,
        ),
        NavigationDestination(
          icon: const Icon(Icons.casino_outlined),
          label: l10n.navigationGenerate,
          enabled: false,
        ),
        NavigationDestination(
          icon: const Icon(Icons.shield_outlined),
          label: l10n.navigationCheck,
          enabled: false,
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          label: l10n.settingsTitle,
        ),
      ],
    );
  }
}
