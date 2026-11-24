import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/database_navigation_bar.dart';
import 'package:keepass_mobile/app/router.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/group/group_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_database.dart';

Future<ProviderContainer> _pumpNavigation(
  WidgetTester tester, {
  ThemeMode themeMode = ThemeMode.light,
}) async {
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  final database = newTestDatabase();
  final bank = database.createGroup(parent: database.root, name: 'Banca');
  for (var index = 0; index < 36; index++) {
    database.createGroup(
      parent: bank,
      name: 'Gruppo ${index.toString().padLeft(2, '0')}',
    );
  }
  final container = await newTestContainer();
  container
      .read(databaseSessionProvider.notifier)
      .open(
        DatabaseSession(
          file: const FileRef(uri: 'file:///prova.kdbx', name: 'prova.kdbx'),
          database: database,
        ),
      );
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
        darkTheme: buildDarkTheme(),
        themeMode: themeMode,
        routerConfig: container.read(routerProvider),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _bar() => find.byType(DatabaseNavigationBar);

Finder _tab(String label) =>
    find.descendant(of: _bar(), matching: find.text(label));

Finder _groupList() => find.descendant(
  of: find.byType(GroupView),
  matching: find.byType(ListView),
);

ScrollableState _groupScrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find.descendant(of: _groupList(), matching: find.byType(Scrollable)),
    );

void _expectBarUnchanged(WidgetTester tester, Element element, Rect bounds) {
  expect(_bar(), findsOneWidget);
  expect(tester.element(_bar()), same(element));
  expect(tester.getRect(_bar()), bounds);
  expect(_bar().hitTestable(), findsOneWidget);
  final fades = find.ancestor(
    of: _bar(),
    matching: find.byType(FadeTransition),
  );
  for (final fade in tester.widgetList<FadeTransition>(fades)) {
    expect(fade.opacity.value, closeTo(1, 0.001));
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('it'));

  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'barra ${themeMode.name}: stessa superficie visibile durante Home e Impostazioni',
      (tester) async {
        // given
        await _pumpNavigation(tester, themeMode: themeMode);
        final element = tester.element(_bar());
        final bounds = tester.getRect(_bar());

        for (final (label, settingsSelected) in [
          (l10n.settingsTitle, true),
          (l10n.navigationHome, false),
        ]) {
          // when: campiona i frame della transizione avanti e indietro.
          await tester.tap(_tab(label));
          await tester.pump();
          for (final milliseconds in [0, 40, 60, 100, 100]) {
            await tester.pump(Duration(milliseconds: milliseconds));

            // then: la barra non viene sostituita, spostata o sfumata.
            _expectBarUnchanged(tester, element, bounds);
            expect(
              tester.widget<DatabaseNavigationBar>(_bar()).settingsSelected,
              settingsSelected,
            );
          }
          await tester.pumpAndSettle();
        }
        expect(find.widgetWithText(ListTile, 'Banca'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Impostazioni: Home e Indietro conservano sottogruppo e scorrimento',
    (tester) async {
      // given
      await _pumpNavigation(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Banca'));
      await tester.pumpAndSettle();
      _groupScrollable(tester).position.jumpTo(240);
      await tester.pumpAndSettle();
      final offset = _groupScrollable(tester).position.pixels;
      expect(offset, greaterThan(0));

      // when: torna prima con Home, poi con Indietro di sistema.
      for (final systemBack in [false, true]) {
        await tester.tap(_tab(l10n.settingsTitle));
        await tester.pumpAndSettle();
        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(_tab(l10n.navigationHome));
        }
        await tester.pumpAndSettle();

        // then
        expect(find.widgetWithText(AppBar, 'Banca'), findsOneWidget);
        expect(_groupScrollable(tester).position.pixels, closeTo(offset, 0.1));
        expect(
          tester.widget<DatabaseNavigationBar>(_bar()).settingsSelected,
          isFalse,
        );
      }
      final scrollable = _groupScrollable(tester);
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.widgetWithText(ListTile, 'Gruppo 35')).bottom,
        lessThan(tester.getRect(find.byType(FloatingActionButton)).top),
      );
      await tester.tap(_tab(l10n.navigationHome));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Banca'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selezione: nasconde la barra comune e libera il fondo', (
    tester,
  ) async {
    // given
    await _pumpNavigation(tester);
    final list = _groupList();
    final normalPadding = tester.widget<ListView>(list).padding;
    expect(normalPadding, isNotNull);
    final normalBounds = tester.getRect(_bar());

    // when
    await tester.longPress(find.widgetWithText(ListTile, 'Banca'));
    await tester.pumpAndSettle();

    // then
    expect(_bar(), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(tester.widget<ListView>(list).padding, isNull);
    final scaffold = find.descendant(
      of: find.byType(GroupView),
      matching: find.byType(Scaffold),
    );
    expect(tester.widget<Scaffold>(scaffold).extendBody, isFalse);
    expect(tester.widget<Scaffold>(scaffold).bottomNavigationBar, isNull);

    await tester.tap(find.byTooltip(l10n.cancel));
    await tester.pumpAndSettle();
    expect(_bar(), findsOneWidget);
    expect(tester.getRect(_bar()), normalBounds);
    expect(tester.widget<ListView>(list).padding, normalPadding);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.longPress(find.widgetWithText(ListTile, 'Banca'));
    await tester.pumpAndSettle();
    expect(_bar(), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_bar(), findsOneWidget);
    expect(tester.widget<ListView>(list).padding, normalPadding);
    expect(tester.takeException(), isNull);
  });

  for (final withSheet in [false, true]) {
    testWidgets(
      'blocco da Impostazioni${withSheet ? " con selettore aperto" : ""}: rimuove anche la barra comune',
      (tester) async {
        // given
        final container = await _pumpNavigation(tester);
        await tester.tap(_tab(l10n.settingsTitle));
        await tester.pumpAndSettle();

        if (withSheet) {
          await tester.tap(find.text(l10n.settingsClipboardTimeout));
          await tester.pumpAndSettle();
          expect(_bar().hitTestable(), findsNothing);
          expect(find.text(l10n.settingsSeconds(10)), findsOneWidget);
        }

        // when
        container.read(databaseSessionProvider.notifier).lock();
        await tester.pumpAndSettle();

        // then
        expect(_bar(), findsNothing);
        expect(find.text(l10n.fileSelectTitle), findsOneWidget);
        expect(find.byType(GroupView), findsNothing);
        expect(find.text(l10n.settingsSeconds(10)), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
