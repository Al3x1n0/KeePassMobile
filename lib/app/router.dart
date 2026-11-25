import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/create_database/create_database_view.dart';
import '../features/database_settings/change_master_key_view.dart';
import '../features/database_settings/database_settings_view.dart';
import '../features/entry/entry_view.dart';
import '../features/entry_edit/entry_edit_view.dart';
import '../features/entry_edit/entry_edit_view_model.dart';
import '../features/favorites/favorites_view.dart';
import '../features/file_select/file_select_view.dart';
import '../features/group/group_view.dart';
import '../features/password_check/password_check_view.dart';
import '../features/password_generator/generator_view.dart';
import '../features/remote_open/remote_open_view.dart';
import '../features/search/search_view.dart';
import '../features/settings/settings_view.dart';
import '../features/unlock/unlock_view.dart';
import '../features/unlock/unlock_view_model.dart';
import '../features/unlock/relock.dart';
import '../shared/database/database_session.dart';
import 'database_navigation_shell.dart';
import 'routes.dart';
import 'theme.dart';

/// Router dell'app. Le route del database sono raggiungibili solo con un
/// database sbloccato; aprire o bloccare il database cambia la route.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    // Solo apertura e blocco: un salvataggio sostituisce il database nella
    // sessione e non deve ricostruire la navigazione in corso.
    ..listen(databaseSessionProvider, (previous, next) {
      if ((previous == null) != (next == null)) refresh.value++;
    })
    ..onDispose(refresh.dispose);

  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(databaseSessionProvider);
      final isOpen = session != null;
      final location = state.matchedLocation;
      final inDatabase = location.startsWith(AppRoutes.database);
      if (!isOpen && inDatabase) return AppRoutes.fileSelect;
      if (isOpen && !inDatabase) {
        return ref
                .read(relockProvider.notifier)
                .takeRestoreDestination(session.file) ??
            AppRoutes.database;
      }
      if (location == AppRoutes.unlock && state.extra is! UnlockArgs) {
        return AppRoutes.fileSelect;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.fileSelect,
        builder: (_, _) => const FileSelectView(),
      ),
      GoRoute(
        path: AppRoutes.unlock,
        builder: (_, state) => switch (state.extra) {
          final UnlockArgs args => UnlockView(
            key: ValueKey(args.database.ref.uri),
            args: args,
          ),
          _ => const FileSelectView(),
        },
      ),
      GoRoute(
        path: AppRoutes.remoteOpen,
        builder: (_, _) => const RemoteOpenView(),
      ),
      GoRoute(
        path: AppRoutes.createDatabase,
        builder: (_, _) => const CreateDatabaseView(),
      ),
      GoRoute(
        path: AppRoutes.appSettings,
        builder: (_, _) => const SettingsView(),
      ),
      ShellRoute(
        pageBuilder: (_, state, child) => NoTransitionPage<void>(
          key: state.pageKey,
          child: DatabaseNavigationShell(
            location: state.uri.path,
            child: child,
          ),
        ),
        routes: [
          GoRoute(
            path: AppRoutes.database,
            builder: (_, _) => const GroupView(),
            routes: [
              GoRoute(
                path: 'group/:groupId',
                builder: (_, state) =>
                    GroupView(groupId: state.pathParameters['groupId']),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (_, state) => EntryEditView(
                      target: EntryEditTarget.create(
                        state.pathParameters['groupId'] ?? '',
                        templateId: state.extra is String
                            ? state.extra as String
                            : null,
                        fromGenerator:
                            state.extra == EntryCreationSource.generator,
                      ),
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'entry/:entryId',
                builder: (_, state) =>
                    EntryView(entryId: state.pathParameters['entryId'] ?? ''),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => EntryEditView(
                      target: EntryEditTarget.edit(
                        state.pathParameters['entryId'] ?? '',
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'history/:index',
                    builder: (_, state) => EntryView(
                      entryId: state.pathParameters['entryId'] ?? '',
                      historyIndex:
                          int.tryParse(state.pathParameters['index'] ?? '') ??
                          -1,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'open',
                builder: (_, _) => const FileSelectView(additional: true),
                routes: [
                  GoRoute(
                    path: 'remote',
                    builder: (_, _) => const RemoteOpenView(additional: true),
                  ),
                  GoRoute(
                    path: 'unlock',
                    builder: (_, state) => state.extra is UnlockArgs
                        ? UnlockView(args: state.extra! as UnlockArgs)
                        : const FileSelectView(additional: true),
                  ),
                ],
              ),
              GoRoute(path: 'search', builder: (_, _) => const SearchView()),
              GoRoute(
                path: 'favorites',
                builder: (_, _) => const FavoritesView(),
              ),
              GoRoute(
                path: 'generator',
                builder: (_, _) => const GeneratorView(),
              ),
              GoRoute(
                path: 'generate',
                pageBuilder: (_, state) => CustomTransitionPage<void>(
                  key: state.pageKey,
                  transitionDuration: AppNavigationLayout.transitionDuration,
                  reverseTransitionDuration:
                      AppNavigationLayout.transitionDuration,
                  child: const GeneratorView(showDatabaseNavigation: true),
                  transitionsBuilder: (_, animation, _, child) =>
                      FadeTransition(opacity: animation, child: child),
                ),
              ),
              GoRoute(
                path: 'check',
                pageBuilder: (_, state) => CustomTransitionPage<void>(
                  key: state.pageKey,
                  transitionDuration: AppNavigationLayout.transitionDuration,
                  reverseTransitionDuration:
                      AppNavigationLayout.transitionDuration,
                  child: const PasswordCheckView(),
                  transitionsBuilder: (_, animation, _, child) =>
                      FadeTransition(opacity: animation, child: child),
                ),
              ),
              GoRoute(
                path: 'settings',
                pageBuilder: (_, state) => CustomTransitionPage<void>(
                  key: state.pageKey,
                  transitionDuration: AppNavigationLayout.transitionDuration,
                  reverseTransitionDuration:
                      AppNavigationLayout.transitionDuration,
                  child: const SettingsView(showDatabaseNavigation: true),
                  transitionsBuilder: (_, animation, _, child) =>
                      FadeTransition(opacity: animation, child: child),
                ),
              ),
              GoRoute(
                path: 'database-settings',
                builder: (_, _) => const DatabaseSettingsView(),
              ),
              GoRoute(
                path: 'change-key',
                builder: (_, _) => const ChangeMasterKeyView(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  void rememberTab() {
    if (ref.read(databaseSessionProvider) == null) return;
    final current = router.state;
    final location = current.fullPath == '${AppRoutes.database}/group/:groupId'
        ? AppRoutes.database
        : current.uri.path;
    ref.read(relockProvider.notifier).rememberTab(location);
  }

  router.routerDelegate.addListener(rememberTab);
  ref.onDispose(() {
    router.routerDelegate.removeListener(rememberTab);
    router.dispose();
  });
  return router;
});
