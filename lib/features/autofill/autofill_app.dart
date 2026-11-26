import '../entry_edit/entry_edit_view.dart';
import '../entry_edit/entry_edit_view_model.dart';
import '../password_generator/generator_view.dart';

import 'package:material_ui/material_ui.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/device_integrity.dart';
import '../../app/external_change_dialog.dart';
import '../../app/remote_dialogs.dart';
import '../../app/router.dart';
import '../../app/routes.dart';
import '../../app/screen_protection.dart';
import '../../app/screen_protection_warning.dart';
import '../../app/session_guard.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/crypto/app_crypto_engine.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/external_change.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/storage/preferences.dart';
import '../../shared/storage/remote_storage.dart';
import '../device_blocked/device_blocked_view.dart';
import '../unlock/unlock_view.dart';
import '../unlock/unlock_view_model.dart';
import 'autofill_channel.dart';
import 'autofill_file_select_view.dart';
import 'autofill_pick_view.dart';
import 'autofill_pick_view_model.dart';
import 'autofill_save_view.dart';

/// Route della scelta della voce, raggiungibile solo con il database aperto.
const autofillPickRoute = '/autofill';

/// Avvio della compilazione automatica nel motore di `AutofillActivity`
/// (ADR-013): stessa sicurezza dell'app (integrità, schermo protetto, blocco
/// per inattività), nessuna notifica del database aperto.
Future<void> runAutofill() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppCryptoEngine.install();
  const channel = AutofillChannel();
  final request = await channel.request();
  if (request == null) {
    await channel.cancel();
    return;
  }
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: autofillOverrides(preferences, request),
      child: const AutofillApp(),
    ),
  );
}

/// Provider del motore della compilazione automatica.
List<Override> autofillOverrides(
  SharedPreferences preferences,
  AutofillRequest request,
) => [
  sharedPreferencesProvider.overrideWithValue(preferences),
  autofillRequestProvider.overrideWithValue(request),
  routerProvider.overrideWith(autofillRouter),
  externalChangeResolverProvider.overrideWith(externalChangeDialog),
  remoteCredentialsPromptProvider.overrideWith(remoteCredentialsDialog),
  certificateTrustPromptProvider.overrideWith(certificateTrustDialog),
  sshHostTrustPromptProvider.overrideWith(sshHostTrustDialog),
  openNotificationAllowedProvider.overrideWithValue(false),
];

/// Router della compilazione automatica: database dei recenti, sblocco e
/// scelta della voce, come le route dell'app.
GoRouter autofillRouter(Ref ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(databaseSessionProvider, (previous, next) {
      if (previous != null &&
          next == null &&
          ref.read(autofillRequestProvider).save &&
          !ref.read(autofillDoneProvider)) {
        ref.read(autofillDoneProvider.notifier).done();
        unawaited(ref.read(autofillChannelProvider).cancel());
      }
      if ((previous == null) != (next == null)) refresh.value++;
    })
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final isOpen = ref.read(databaseSessionProvider) != null;
      final location = state.matchedLocation;
      final editing =
          location == '/autofill/new' || location == AppRoutes.generator;
      if (isOpen && location != autofillPickRoute && !editing) {
        return autofillPickRoute;
      }
      if (!isOpen && (location == autofillPickRoute || editing)) {
        return AppRoutes.fileSelect;
      }
      if (location == AppRoutes.unlock && state.extra is! UnlockArgs) {
        return AppRoutes.fileSelect;
      }
      if (location == '/autofill/new' && state.extra is! (String, EntryDraft)) {
        return isOpen ? autofillPickRoute : AppRoutes.fileSelect;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/autofill/new',
        builder: (_, state) {
          final args = state.extra;
          if (args is! (String, EntryDraft)) return const AutofillPickView();
          return EntryEditView(
            target: EntryEditTarget.create(args.$1),
            initialDraft: args.$2,
            returnCreated: true,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.generator,
        builder: (_, _) => const GeneratorView(),
      ),
      GoRoute(
        path: AppRoutes.fileSelect,
        builder: (_, _) => const AutofillFileSelectView(),
      ),
      GoRoute(
        path: AppRoutes.unlock,
        builder: (_, state) => switch (state.extra) {
          final UnlockArgs args => UnlockView(
            key: ValueKey(args.database.ref.uri),
            args: args,
          ),
          _ => const AutofillFileSelectView(),
        },
      ),
      GoRoute(
        path: autofillPickRoute,
        builder: (_, _) => ref.read(autofillRequestProvider).save
            ? const AutofillSaveView()
            : const AutofillPickView(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
}

class AutofillApp extends ConsumerWidget {
  const AutofillApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Blocco per inattività e a schermo spento, schermo protetto.
    ref.watch(sessionGuardProvider);
    final themeMode = ref.watch(appSettingsProvider.select((s) => s.themeMode));
    final integrity = ref.watch(integrityStatusProvider);
    final protection = ref.watch(screenProtectionStatusProvider);
    final done = ref.watch(autofillDoneProvider);
    // Dispositivo non verificato o non affidabile (D9), o risposta già data.
    if (integrity != IntegrityStatus.trusted ||
        done ||
        protection == ScreenProtectionStatus.checking ||
        protection == ScreenProtectionStatus.warning) {
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
        home: switch (integrity) {
          IntegrityStatus.compromised => const DeviceBlockedView(),
          IntegrityStatus.trusted
              when !done && protection == ScreenProtectionStatus.warning =>
            const ScreenProtectionWarning(),
          _ => const Scaffold(),
        },
      );
    }
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      builder: (context, child) =>
          SessionActivity(child: child ?? const SizedBox.shrink()),
      localizationsDelegates: [
        ...GlobalMaterialLocalizations.delegates,
        ...AppLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
