import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/database_navigation_bar.dart';
import 'package:keepass_mobile/app/router.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/app/session_guard.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/group/group_view.dart';
import 'package:keepass_mobile/features/password_generator/generator_view.dart';
import 'package:keepass_mobile/features/password_generator/pending_generated_password.dart';
import 'package:keepass_mobile/features/unlock/relock.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
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

  for (final leaveGenerator in [false, true]) {
    testWidgets(
      'background dopo Genera${leaveGenerator ? " e Home" : ""}: conserva copia e ripristina la password esatta',
      (tester) async {
        // given
        final (container, clipboard) = await _pump(
          tester,
          settings: const AppSettings(
            lockInBackground: true,
            lockTimeout: null,
            openNotification: false,
          ),
        );
        await tester.tap(_tab(l10n.navigationGenerate));
        await tester.pumpAndSettle();
        final value = _generatedValue(tester);
        await tester.tap(find.byIcon(Icons.content_copy_outlined));
        await tester.pumpAndSettle();
        expect(clipboard.text, value);
        expect(clipboard.clearAfter, AppSettings.defaultClipboardTimeout);
        if (leaveGenerator) {
          await tester.tap(_tab(l10n.navigationHome));
          await tester.pumpAndSettle();
        }

        // when: inactive da solo non chiude la sessione.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(container.read(databaseSessionProvider), isNotNull);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();

        // then: il browser può ancora incollare entro il timeout nativo.
        expect(container.read(databaseSessionProvider), isNull);
        expect(clipboard.text, value);
        _resume(tester);
        await tester.pumpAndSettle();
        expect(find.byType(GeneratorView), findsNothing);
        _open(container);
        await tester.pumpAndSettle();
        expect(
          container.read(routerProvider).state.uri.path,
          AppRoutes.generate,
        );
        expect(_generatedValue(tester), value);
        expect(container.read(pendingGeneratedPasswordProvider), isNotNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
      },
    );
  }

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

  testWidgets('timeout dopo Genera: ripristina il valore anche dalla Home', (
    tester,
  ) async {
    // given
    final (container, _) = await _pump(
      tester,
      settings: const AppSettings(
        lockTimeout: Duration(seconds: 30),
        openNotification: false,
      ),
    );
    await tester.tap(_tab(l10n.navigationGenerate));
    await tester.pumpAndSettle();
    final value = _generatedValue(tester);
    await tester.tap(_tab(l10n.navigationHome));
    await tester.pumpAndSettle();

    // when
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    // then
    expect(container.read(databaseSessionProvider), isNull);
    _open(container);
    await tester.pumpAndSettle();
    expect(container.read(routerProvider).state.uri.path, AppRoutes.generate);
    expect(_generatedValue(tester), value);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
