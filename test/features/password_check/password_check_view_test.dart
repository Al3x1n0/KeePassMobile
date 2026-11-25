import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/database_navigation_bar.dart';
import 'package:keepass_mobile/app/router.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/entry/entry_view.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view.dart';
import 'package:keepass_mobile/features/password_check/password_check_view.dart';
import 'package:keepass_mobile/features/password_check/password_check_view_model.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/ui/entry_tile.dart';
import 'package:keepass_mobile/shared/ui/expandable_section.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_database.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  KdbxDatabase db, {
  Locale locale = const Locale('it'),
  double scale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 720);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  final (file, reopened) = (await tester.runAsync(() => saveToTempFile(db)))!;
  addTearDown(() => file.parent.deleteSync(recursive: true));
  final container = await newTestContainer(file: file, database: reopened);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: [
          ...GlobalMaterialLocalizations.delegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildLightTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        routerConfig: container.read(routerProvider),
      ),
    ),
  );
  await tester.pumpAndSettle();
  container.read(routerProvider).push(AppRoutes.check);
  await tester.pumpAndSettle();
  return container;
}

KdbxDatabase _fixture() {
  final db = newTestDatabase();
  addTestEntry(db, db.root, {'Title': 'Alfa', 'Password': 'tiny'});
  addTestEntry(db, db.root, {'Title': 'Beta', 'Password': 'tiny'});
  addTestEntry(db, db.root, {
    'Title': 'Riferimento escluso',
    'Password': '{REF:P@T:Alfa}',
  });
  addTestEntry(
    db,
    db.root,
    {'Title': 'Carta', 'PIN': '9876'},
    protectedKeys: {'PIN'},
  );
  return db;
}

Finder _page() => find.byType(PasswordCheckView);
Finder _inPage(Finder finder) => find.descendant(of: _page(), matching: finder);
Finder _section(String title) =>
    find.byWidgetPredicate((w) => w is ExpandableSection && w.title == title);
Finder _tab(String label) => find.descendant(
  of: find.byType(DatabaseNavigationBar),
  matching: find.text(label),
);

void main() {
  final it = lookupAppLocalizations(const Locale('it'));
  testWidgets(
    'pagina: panoramica, duplicate senza valore, motivi, PIN neutro e riferimenti esclusi',
    (tester) async {
      await _pump(tester, _fixture());
      expect(_inPage(find.text(it.checkAttention)), findsOneWidget);
      expect(_inPage(find.text(it.checkSharedCount(2))), findsOneWidget);
      expect(_inPage(find.text(it.checkSummary(2))), findsOneWidget);
      expect(
        _inPage(find.text('${it.checkVeryWeak} · ${it.checkTooShort}')),
        findsNWidgets(2),
      );
      expect(_inPage(find.text('tiny')), findsNothing);
      expect(_inPage(find.text('Riferimento escluso')), findsNothing);
      final exclusions = _inPage(
        find.text(it.checkExclusions('{REF:...} / {S:...}')),
      );
      await tester.ensureVisible(exclusions);
      await tester.pumpAndSettle();
      expect(exclusions.hitTestable(), findsOneWidget);
      final other = _section(it.checkOtherProtected);
      expect(
        find.descendant(
          of: other,
          matching: find.text('PIN · ${it.checkTooShort}'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: other,
          matching: find.text(it.checkProtectedExplanation),
        ),
        findsOneWidget,
      );
      final icon = tester.widget<Icon>(
        find.descendant(of: other, matching: find.byIcon(Icons.info_outline)),
      );
      final context = tester.element(other);
      expect(icon.color, isNot(Theme.of(context).colorScheme.error));
      expect(find.byType(BackButton), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final state in ['empty', 'good', 'weak', 'secondary']) {
    testWidgets('panoramica $state: stato dipende solo dalle Password', (
      tester,
    ) async {
      final db = newTestDatabase();
      if (state == 'good') {
        addTestEntry(db, db.root, {'Password': 'vK9!tR4?mZ'});
      }
      if (state == 'weak') addTestEntry(db, db.root, {'Password': 'hvrnktps'});
      if (state == 'secondary') {
        addTestEntry(db, db.root, {'PIN': '1234'}, protectedKeys: {'PIN'});
      }
      await _pump(tester, db);
      final expected = state == 'empty'
          ? it.checkEmpty
          : state == 'weak'
          ? it.checkImprove
          : it.checkAllGood;
      expect(_inPage(find.text(expected)), findsOneWidget);
      expect(_inPage(find.text(it.checkAttention)), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final language in ['it', 'en']) {
    testWidgets(
      '$language: 320 dp testo 2x, contatori e ultima voce sopra la barra',
      (tester) async {
        final l10n = lookupAppLocalizations(Locale(language));
        await _pump(tester, _fixture(), locale: Locale(language), scale: 2);
        final counter = find.widgetWithText(
          OutlinedButton,
          '${l10n.checkOtherProtected}: 1',
        );
        await tester.ensureVisible(counter);
        await tester.pumpAndSettle();
        await tester.tap(counter);
        await tester.pumpAndSettle();
        final scroll = _inPage(find.byType(Scrollable));
        tester
            .state<ScrollableState>(scroll)
            .position
            .jumpTo(
              tester.state<ScrollableState>(scroll).position.maxScrollExtent,
            );
        await tester.pumpAndSettle();
        final last = find.descendant(
          of: _section(l10n.checkOtherProtected),
          matching: find.byType(EntryTile),
        );
        expect(last.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(last).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byType(DatabaseNavigationBar)).top,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('tutte le coppie di tab conservano barra e ritorno Home', (
    tester,
  ) async {
    final container = await _pump(tester, newTestDatabase());
    final bar = tester.element(find.byType(DatabaseNavigationBar));
    final routes = {
      it.navigationHome: AppRoutes.database,
      it.navigationGenerate: AppRoutes.generate,
      it.navigationCheck: AppRoutes.check,
      it.settingsTitle: AppRoutes.appSettingsInDatabase,
    };
    for (final source in routes.keys) {
      await tester.tap(_tab(source));
      await tester.pumpAndSettle();
      for (final target in routes.keys) {
        await tester.tap(_tab(target));
        await tester.pumpAndSettle();
        expect(container.read(routerProvider).state.uri.path, routes[target]);
        expect(tester.element(find.byType(DatabaseNavigationBar)), same(bar));
        await tester.tap(_tab(source));
        await tester.pumpAndSettle();
      }
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'tap voce, modifica reale, salvataggio e ritorno aggiornano subito Controllo',
    (tester) async {
      final db = newTestDatabase();
      final item = addTestEntry(db, db.root, {
        'Title': 'Da correggere',
        'Password': 'tiny',
      });
      final container = await _pump(tester, db);
      final tile = _inPage(find.byType(EntryTile));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byType(EntryView), findsOneWidget);
      expect(
        container.read(routerProvider).state.uri.path,
        AppRoutes.entry(itemIdOf(item)),
      );
      // Open the actual edit route from the entry's action menu.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(it.entryEdit));
      await tester.pumpAndSettle();
      expect(find.byType(EntryEditView), findsOneWidget);
      final password = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == it.entryPassword,
      );
      await tester.ensureVisible(password);
      await tester.enterText(password, 'vK9!tR4?mZ');
      await tester.tap(find.byTooltip(it.entryEditSave));
      await pumpUntilFound(tester, find.byType(EntryView));
      await tester.pumpAndSettle();
      container.read(routerProvider).pop();
      await tester.pumpAndSettle();
      expect(_page(), findsOneWidget);
      expect(_inPage(find.text(it.checkAllGood)), findsOneWidget);
      expect(_inPage(find.byType(EntryTile)), findsNothing);
      expect(container.read(passwordCheckReportProvider)!.weakEntries, isEmpty);
      final session = container.read(databaseSessionProvider)!;
      final reopened = await tester.runAsync(
        () => reopenFile(File.fromUri(Uri.parse(session.file.uri))),
      );
      expect(
        entryField(findEntry(reopened!, itemIdOf(item))!, EntryFields.password),
        'vK9!tR4?mZ',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
