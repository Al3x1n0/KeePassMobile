import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/search/search_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/ui/app_bar_action_row.dart';
import 'package:keepass_mobile/shared/ui/entry_tile.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_database.dart';

const _firstFile = FileRef(uri: 'file:///first.kdbx', name: 'first.kdbx');
const _secondFile = FileRef(uri: 'file:///second.kdbx', name: 'second.kdbx');

Future<void> _pumpSearch(
  WidgetTester tester,
  ProviderContainer container, {
  Locale locale = const Locale('it'),
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: [
          ...GlobalMaterialLocalizations.delegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildLightTheme(),
        home: const SearchView(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Voce');
  await tester.pumpAndSettle();
}

void main() {
  for (final locale in [const Locale('it'), const Locale('en')]) {
    testWidgets(
      'Ricerca ${locale.languageCode}: seleziona tutti dinamico sulla seconda riga',
      (tester) async {
        // given
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final l10n = lookupAppLocalizations(locale);
        final db = newTestDatabase();
        addTestEntry(db, db.root, {EntryFields.title: 'Voce A'});
        addTestEntry(db, db.root, {EntryFields.title: 'Voce B'});
        final container = await newTestContainer();
        container
            .read(databaseSessionProvider.notifier)
            .open(DatabaseSession(file: _firstFile, database: db));
        await _pumpSearch(tester, container, locale: locale);
        expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
        expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
        expect(tester.getTopLeft(find.byType(TextField)).dx, AppSpacing.m);

        // when
        await tester.longPress(find.text('Voce A'));
        await tester.pumpAndSettle();

        // then
        expect(
          tester.getTopLeft(find.text(l10n.itemsSelected(1))).dx,
          kToolbarHeight + AppSpacing.m,
        );
        final selectAll = find.widgetWithText(
          TextButton,
          l10n.itemsSelectAllShort,
        );
        expect(selectAll, findsOneWidget);
        expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight + 48);
        expect(find.byType(AppBarActionRow), findsOneWidget);
        expect(find.byIcon(Icons.select_all), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        expect(tester.getRect(selectAll).left, lessThan(24));
        expect(tester.getRect(selectAll).top, greaterThanOrEqualTo(56));
        expect(
          tester.getRect(find.byTooltip(l10n.entryDelete)).right,
          greaterThan(336),
        );
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text(l10n.itemsSelected(1)),
          ),
          findsOneWidget,
        );

        await tester.tap(selectAll);
        await tester.pumpAndSettle();
        expect(selectAll, findsNothing);
        expect(find.text(l10n.itemsSelected(2)), findsOneWidget);
        expect(
          tester
              .widgetList<EntryTile>(find.byType(EntryTile))
              .every((tile) => tile.selected),
          isTrue,
        );

        await tester.tap(find.text('Voce B'));
        await tester.pumpAndSettle();
        expect(selectAll, findsOneWidget);
        expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight + 48);
        expect(find.byType(AppBarActionRow), findsOneWidget);
        expect(find.text(l10n.itemsSelected(1)), findsOneWidget);

        await tester.tap(find.byTooltip(l10n.cancel));
        await tester.pumpAndSettle();
        expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
        expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
        expect(find.byType(TextField), findsOneWidget);
      },
    );
  }

  testWidgets(
    'seleziona solo i risultati attivi e azzera al cambio database con UUID uguali',
    (tester) async {
      // given
      final l10n = lookupAppLocalizations(const Locale('it'));
      final firstDb = newTestDatabase();
      final first = addTestEntry(firstDb, firstDb.root, {
        EntryFields.title: 'Voce A',
      });
      addTestEntry(firstDb, firstDb.root, {EntryFields.title: 'Voce B'});
      final secondDb = newTestDatabase();
      addTestEntry(secondDb, secondDb.root, {
        EntryFields.title: 'Voce C',
      }).uuid = first.uuid;
      addTestEntry(secondDb, secondDb.root, {EntryFields.title: 'Voce D'});
      final container = await newTestContainer();
      final sessions = container.read(databaseSessionProvider.notifier);
      sessions.open(DatabaseSession(file: _firstFile, database: firstDb));
      sessions.openAdditional(
        DatabaseSession(file: _secondFile, database: secondDb),
        sessions.lockGeneration,
      );
      sessions.switchTo(_firstFile);
      await _pumpSearch(tester, container);

      // when / then
      await tester.longPress(find.text('Voce A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.itemsSelectAllShort));
      await tester.pumpAndSettle();
      expect(find.text(l10n.itemsSelected(2)), findsOneWidget);
      expect(find.text(l10n.itemsSelectAllShort), findsNothing);
      final tiles = tester.widgetList<EntryTile>(find.byType(EntryTile));
      expect(
        tiles
            .where((tile) => tile.selected)
            .map((tile) => entryTitle(tile.entry)),
        ['Voce A', 'Voce B'],
      );
      await tester.tap(find.text('Voce C'));
      await tester.longPress(find.text('Voce D'));
      await tester.pumpAndSettle();
      expect(container.read(databaseSessionProvider)!.file, _firstFile);
      expect(find.text(l10n.itemsSelected(2)), findsOneWidget);

      sessions.switchTo(_secondFile);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester
            .widgetList<EntryTile>(find.byType(EntryTile))
            .any((tile) => tile.selected),
        isFalse,
      );
      await tester.longPress(find.text('Voce C'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.itemsSelected(1)), findsOneWidget);
      await tester.tap(find.text(l10n.itemsSelectAllShort));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<EntryTile>(find.byType(EntryTile))
            .where((tile) => tile.selected)
            .map((tile) => entryTitle(tile.entry)),
        ['Voce C', 'Voce D'],
      );
    },
  );

  testWidgets(
    'regex: selezione limitata al database attivo dopo il cambio sessione',
    (tester) async {
      // given
      final l10n = lookupAppLocalizations(const Locale('it'));
      final firstDb = newTestDatabase();
      addTestEntry(firstDb, firstDb.root, {EntryFields.title: 'Voce A'});
      addTestEntry(firstDb, firstDb.root, {EntryFields.title: 'Voce B'});
      final secondDb = newTestDatabase();
      addTestEntry(secondDb, secondDb.root, {EntryFields.title: 'Voce C'});
      addTestEntry(secondDb, secondDb.root, {EntryFields.title: 'Voce D'});
      final container = await newTestContainer();
      final sessions = container.read(databaseSessionProvider.notifier);
      sessions.open(DatabaseSession(file: _firstFile, database: firstDb));
      sessions.openAdditional(
        DatabaseSession(file: _secondFile, database: secondDb),
        sessions.lockGeneration,
      );
      sessions.switchTo(_firstFile);
      await _pumpSearch(tester, container);
      await tester.tap(find.byTooltip(l10n.searchOptions));
      await tester.pumpAndSettle();
      final regex = find.widgetWithText(CheckboxListTile, l10n.searchRegex);
      await tester.scrollUntilVisible(
        regex,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(regex);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.searchTitle));
      await pumpUntilFound(tester, find.text('Voce C'));
      await tester.pumpAndSettle();

      // when: il primo long press su un risultato inattivo attiva quel database.
      await tester.longPress(find.text('Voce C'));
      await tester.pumpAndSettle();

      // then
      expect(container.read(databaseSessionProvider)!.file, _secondFile);
      expect(find.text(l10n.itemsSelected(1)), findsOneWidget);
      await tester.tap(find.text(l10n.itemsSelectAllShort));
      await tester.pumpAndSettle();
      expect(find.text(l10n.itemsSelected(2)), findsOneWidget);
      expect(find.text(l10n.itemsSelectAllShort), findsNothing);
      expect(
        tester
            .widgetList<EntryTile>(find.byType(EntryTile))
            .where((tile) => tile.selected)
            .map((tile) => entryTitle(tile.entry)),
        ['Voce C', 'Voce D'],
      );

      sessions.switchTo(_firstFile);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Voce C'), findsOneWidget);
      expect(
        tester
            .widgetList<EntryTile>(find.byType(EntryTile))
            .any((tile) => tile.selected),
        isFalse,
      );
      await tester.longPress(find.text('Voce A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.itemsSelectAllShort));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<EntryTile>(find.byType(EntryTile))
            .where((tile) => tile.selected)
            .map((tile) => entryTitle(tile.entry)),
        ['Voce A', 'Voce B'],
      );
      final refreshedDb = newTestDatabase();
      refreshedDb.root.uuid = firstDb.root.uuid;
      addTestEntry(refreshedDb, refreshedDb.root, {
        EntryFields.title: 'Voce aggiornata',
      });
      sessions.open(DatabaseSession(file: _firstFile, database: refreshedDb));
      await tester.pumpAndSettle();
      expect(find.text(l10n.searchRegexSubmit), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(EntryTile), findsNothing);
    },
  );

  testWidgets(
    'rimuove dalla selezione risultati esclusi dalla query o dai filtri',
    (tester) async {
      // given
      final l10n = lookupAppLocalizations(const Locale('it'));
      final db = newTestDatabase();
      addTestEntry(db, db.root, {EntryFields.title: 'Voce A'});
      final expired = addTestEntry(db, db.root, {EntryFields.title: 'Voce B'});
      expired.times
        ..expires = true
        ..expiry = KdbxTime(DateTime.utc(2020));
      final container = await newTestContainer();
      container
          .read(databaseSessionProvider.notifier)
          .open(DatabaseSession(file: _firstFile, database: db));
      await _pumpSearch(tester, container);
      final queryField = tester.widget<TextField>(find.byType(TextField));
      await tester.longPress(find.text('Voce A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.itemsSelectAllShort));
      await tester.pumpAndSettle();

      // when: un nuovo testo arriva mentre il campo è sostituito dal contatore.
      queryField.controller!.text = 'Voce A';
      queryField.onChanged!('Voce A');
      await tester.pumpAndSettle();

      // then
      expect(find.text(l10n.itemsSelected(1)), findsOneWidget);
      expect(find.text('Voce B'), findsNothing);
      expect(find.text(l10n.itemsSelectAllShort), findsNothing);
      queryField.controller!.text = 'Voce';
      queryField.onChanged!('Voce');
      await tester.pumpAndSettle();
      expect(find.text(l10n.itemsSelectAllShort), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.cancel));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.searchOptions));
      await tester.pumpAndSettle();
      final excludeExpired = find.widgetWithText(
        CheckboxListTile,
        l10n.searchExcludeExpired,
      );
      await tester.scrollUntilVisible(
        excludeExpired,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(excludeExpired);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Voce B'), findsNothing);
      await tester.longPress(find.text('Voce A'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.itemsSelected(1)), findsOneWidget);
      expect(find.text(l10n.itemsSelectAllShort), findsNothing);
    },
  );
}
