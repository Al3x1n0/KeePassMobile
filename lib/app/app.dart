import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/device_blocked/device_blocked_view.dart';
import '../l10n/app_localizations.dart';
import '../shared/settings/app_settings.dart';
import 'device_integrity.dart';
import 'linked_database_host.dart';
import 'router.dart';
import 'session_guard.dart';
import 'theme.dart';

class KeePassMobileApp extends ConsumerWidget {
  const KeePassMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Blocco per inattività e a schermo spento, schermo protetto.
    ref.watch(sessionGuardProvider);
    final themeMode = ref.watch(appSettingsProvider.select((s) => s.themeMode));
    final integrity = ref.watch(integrityStatusProvider);
    // Dispositivo non ancora verificato o non affidabile (D9): niente router,
    // file recenti, impostazioni o database.
    if (integrity != IntegrityStatus.trusted) {
      return MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: themeMode,
        localizationsDelegates: [
          ...GlobalMaterialLocalizations.delegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: integrity == IntegrityStatus.compromised
            ? const DeviceBlockedView()
            : const Scaffold(),
      );
    }
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      builder: (context, child) => SessionActivity(
        child: LinkedDatabaseHost(child: child ?? const SizedBox.shrink()),
      ),
      localizationsDelegates: [
        ...GlobalMaterialLocalizations.delegates,
        ...AppLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
