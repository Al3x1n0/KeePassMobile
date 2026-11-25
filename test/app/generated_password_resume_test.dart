import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/database_navigation_bar.dart';
import 'package:keepass_mobile/app/router.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/app/session_guard.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/group/group_view.dart';
import 'package:keepass_mobile/features/password_generator/generator_view.dart';
import 'package:keepass_mobile/features/password_generator/generator_view_model.dart';
import 'package:keepass_mobile/features/password_generator/pending_generated_password.dart';
import 'package:keepass_mobile/features/unlock/relock.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/security/device_security.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_app_security.dart';
import '../helpers/test_database.dart';

const _file = FileRef(uri: 'content://synthetic/resume', name: 'prova.kdbx');
const _differentFile = FileRef(
  uri: 'content://synthetic/other',
  name: 'altro.kdbx',
);

Finder _tab(String text) => find.descendant(
  of: find.byType(DatabaseNavigationBar),
  matching: find.text(text),
);

String _generatedValue(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(GeneratorView.valueKey)).data!;

void _open(ProviderContainer container, [FileRef file = _file]) => container
    .read(databaseSessionProvider.notifier)
    .open(DatabaseSession(file: file, database: newTestDatabase()));

void _resume(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Future<(ProviderContainer, FakeClipboard)> _pump(
  WidgetTester tester, {
  required AppSettings settings,
}) async {
  _resume(tester);
  final clipboard = FakeClipboard(tester.binding);
  final security = FakeAppSecurity();
  final container = await newTestContainer(
    overrides: [appSecurityProvider.overrideWithValue(security)],
  );
  await tester.runAsync(
    () => container.read(appSettingsProvider.notifier).update(settings),
  );
  container.read(sessionGuardProvider);
  _open(container);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: const Locale('it'),
        localizationsDelegates: [
          ...GlobalMaterialLocalizations.delegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildLightTheme(),
        builder: (_, child) => SessionActivity(child: child!),
        routerConfig: container.read(routerProvider),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    _resume(tester);
    await security.events.close();
    await security.lockEvents.close();
  });
  return (container, clipboard);
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('it'));

  for (final background in [true, false]) {
    for (final hasPending in [true, false]) {
      for (final destination in [
        (label: l10n.navigationHome, path: AppRoutes.database),
        (label: l10n.settingsTitle, path: AppRoutes.appSettingsInDatabase),
        (label: l10n.navigationGenerate, path: AppRoutes.generate),
      ]) {
        testWidgets(
          '${background ? "background" : "timeout"}: ripristina ${destination.label} ${hasPending ? "con" : "senza"} password in sospeso',
          (tester) async {
            // given
            final (container, clipboard) = await _pump(
              tester,
              settings: AppSettings(
                lockInBackground: background,
                lockTimeout: background ? null : const Duration(seconds: 30),
                openNotification: false,
              ),
            );
            String? value;
            if (hasPending || destination.path == AppRoutes.generate) {
              await tester.tap(_tab(l10n.navigationGenerate));
              await tester.pumpAndSettle();
              if (hasPending) {
                value = _generatedValue(tester);
                await tester.tap(find.byIcon(Icons.content_copy_outlined));
                await tester.pumpAndSettle();
                expect(clipboard.text, value);
                expect(
                  clipboard.clearAfter,
                  AppSettings.defaultClipboardTimeout,
                );
              } else {
                // Come dopo il salvataggio: tab Genera senza valore corrente.
                container
                    .read(tabGeneratorViewModelProvider.notifier)
                    .clearGeneratedValue();
                container
                    .read(pendingGeneratedPasswordProvider.notifier)
                    .clear();
                await tester.pump();
              }
            }
            if (container.read(routerProvider).state.uri.path !=
                destination.path) {
              await tester.tap(_tab(destination.label));
              await tester.pumpAndSettle();
            }
            expect(
              container.read(pendingGeneratedPasswordProvider) != null,
              hasPending,
            );

            // when
            if (background) {
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
              await tester.pump();
              expect(container.read(databaseSessionProvider), isNotNull);
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.hidden,
              );
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.paused,
              );
            } else {
              await tester.pump(const Duration(seconds: 30));
            }
            await tester.pumpAndSettle();

            // then: tab e password sono ripristinate indipendentemente.
            expect(container.read(databaseSessionProvider), isNull);
            if (hasPending && background) expect(clipboard.text, value);
            if (background) _resume(tester);
            await tester.pumpAndSettle();
            expect(find.byType(GeneratorView), findsNothing);
            _open(container);
            await tester.pumpAndSettle();
            expect(
              container.read(routerProvider).state.uri.path,
              destination.path,
            );
            final navigation = tester.widget<DatabaseNavigationBar>(
              find.byType(DatabaseNavigationBar),
            );
            expect(
              navigation.generatorSelected,
              destination.path == AppRoutes.generate,
            );
            expect(
              navigation.settingsSelected,
              destination.path == AppRoutes.appSettingsInDatabase,
            );
            if (hasPending) {
              if (destination.path != AppRoutes.generate) {
                expect(find.byType(GeneratorView), findsNothing);
                await tester.tap(_tab(l10n.navigationGenerate));
                await tester.pumpAndSettle();
              }
              expect(_generatedValue(tester), value);
              expect(
                container
                    .read(pendingGeneratedPasswordProvider)!
                    .protectedValue
                    .text,
                value,
              );
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            container.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    'Home da sottogruppo dopo Genera: ripristina la root e conserva la password',
    (tester) async {
      // given
      final (container, _) = await _pump(
        tester,
        settings: const AppSettings(
          lockInBackground: true,
          lockTimeout: null,
          openNotification: false,
        ),
      );
      final database = container.read(databaseSessionProvider)!.database;
      final group = database.createGroup(
        parent: database.root,
        name: 'Gruppo sintetico',
      );
      final groupPath = AppRoutes.group(itemIdOf(group));
      container.read(routerProvider).push<void>(groupPath);
      await tester.pumpAndSettle();
      await tester.tap(_tab(l10n.navigationGenerate));
      await tester.pumpAndSettle();
      final value = _generatedValue(tester);
      await tester.tap(_tab(l10n.navigationHome));
      await tester.pumpAndSettle();
      expect(container.read(routerProvider).state.uri.path, groupPath);
      expect(
        tester
            .widget<DatabaseNavigationBar>(find.byType(DatabaseNavigationBar))
            .generatorSelected,
        isFalse,
      );

      // when
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(container.read(databaseSessionProvider), isNull);
      _resume(tester);
      await tester.pumpAndSettle();
      _open(container);
      await tester.pumpAndSettle();

      // then: Home si ripristina senza trattenere l'identità del sottogruppo.
      expect(container.read(routerProvider).state.uri.path, AppRoutes.database);
      expect(find.byType(GroupView), findsOneWidget);
      expect(find.byType(GeneratorView), findsNothing);
      expect(
        container.read(pendingGeneratedPasswordProvider)!.protectedValue.text,
        value,
      );
      await tester.tap(_tab(l10n.navigationGenerate));
      await tester.pumpAndSettle();
      expect(_generatedValue(tester), value);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets(
    'Impostazioni senza password: ripristino in due background consecutivi',
    (tester) async {
      // given
      final (container, _) = await _pump(
        tester,
        settings: const AppSettings(
          lockInBackground: true,
          lockTimeout: null,
          openNotification: false,
        ),
      );
      await tester.tap(_tab(l10n.settingsTitle));
      await tester.pumpAndSettle();

      for (var cycle = 0; cycle < 2; cycle++) {
        // when: il secondo ciclo parte dalle Impostazioni già ripristinate.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        expect(container.read(databaseSessionProvider), isNull);
        _resume(tester);
        await tester.pumpAndSettle();
        _open(container);
        await tester.pumpAndSettle();

        // then
        expect(
          container.read(routerProvider).state.uri.path,
          AppRoutes.appSettingsInDatabase,
        );
        expect(
          tester
              .widget<DatabaseNavigationBar>(find.byType(DatabaseNavigationBar))
              .settingsSelected,
          isTrue,
        );
        expect(container.read(pendingGeneratedPasswordProvider), isNull);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );

  testWidgets('blocco manuale dopo Genera: pulisce copia e torna a Home', (
    tester,
  ) async {
    // given
    final (container, clipboard) = await _pump(
      tester,
      settings: const AppSettings(lockTimeout: null, openNotification: false),
    );
    await tester.tap(_tab(l10n.navigationGenerate));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.content_copy_outlined));
    await tester.pumpAndSettle();
    expect(clipboard.text, isNotEmpty);

    // when
    container.read(relockProvider.notifier).lockAndReturn();
    await tester.pumpAndSettle();

    // then
    expect(clipboard.text, isEmpty);
    expect(container.read(pendingGeneratedPasswordProvider), isNull);
    _open(container);
    await tester.pumpAndSettle();
    expect(container.read(routerProvider).state.uri.path, AppRoutes.database);
    expect(find.byType(GroupView), findsOneWidget);
    expect(find.byType(GeneratorView), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('sblocco di un altro database: elimina il rientro in Genera', (
    tester,
  ) async {
    // given
    final (container, _) = await _pump(
      tester,
      settings: const AppSettings(lockTimeout: null, openNotification: false),
    );
    await tester.tap(_tab(l10n.navigationGenerate));
    await tester.pumpAndSettle();
    container.read(relockProvider.notifier).lockAndReturn(automatic: true);
    await tester.pumpAndSettle();
    expect(container.read(pendingGeneratedPasswordProvider), isNotNull);

    // when
    _open(container, _differentFile);
    await tester.pumpAndSettle();

    // then
    expect(container.read(pendingGeneratedPasswordProvider), isNull);
    expect(container.read(routerProvider).state.uri.path, AppRoutes.database);
    expect(find.byType(GeneratorView), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
