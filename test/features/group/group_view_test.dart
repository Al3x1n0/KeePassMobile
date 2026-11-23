import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/group/group_view.dart';
import 'package:keepass_mobile/features/recent_passwords/recent_passwords_view_model.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/ui/entry_tile.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_database.dart';

void main() {
  const locale = Locale('it');
  final l10n = lookupAppLocalizations(locale);

  for (final binLocale in [const Locale('it'), const Locale('en')]) {
    testWidgets(
      'Cestino ${binLocale.languageCode}: titolo localizzato e selezione dinamica',
      (tester) async {
        // given
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final binL10n = lookupAppLocalizations(binLocale);
        final binTitle = binLocale.languageCode == 'it'
            ? 'Cestino'
            : 'Recycle Bin';
        final db = newTestDatabase();
        final bin = db.recycleBin!..name = 'Stored bin label';
        final group = db.createGroup(parent: bin, name: 'Gruppo eliminato');
        addTestEntry(db, bin, {EntryFields.title: 'Prima voce eliminata'});
        addTestEntry(db, bin, {EntryFields.title: 'Seconda voce eliminata'});
        final container = await newTestContainer();
        container
            .read(databaseSessionProvider.notifier)
            .open(
              DatabaseSession(
                file: const FileRef(
                  uri: 'file:///prova.kdbx',
                  name: 'prova.kdbx',
                ),
                database: db,
              ),
            );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: binLocale,
              localizationsDelegates: [
                ...GlobalMaterialLocalizations.delegates,
                ...AppLocalizations.localizationsDelegates,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildLightTheme(),
              home: GroupView(groupId: itemIdOf(bin)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // when
        expect(find.widgetWithText(AppBar, binTitle), findsOneWidget);
        expect(find.text(bin.name), findsNothing);
        expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
        await tester.longPress(find.text(group.name));
        await tester.pumpAndSettle();

        // then
        final selectAll = find.widgetWithText(
          TextButton,
          binL10n.itemsSelectAllShort,
        );
        expect(selectAll, findsOneWidget);
        expect(find.byIcon(Icons.select_all), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        final restore = find.byTooltip(binL10n.itemRestore);
        final delete = find.byTooltip(binL10n.entryDelete);
        expect(restore, findsOneWidget);
        expect(delete, findsOneWidget);
        expect(tester.getRect(selectAll).left, lessThan(24));
        expect(tester.getRect(selectAll).top, greaterThanOrEqualTo(48));
        expect(tester.getRect(delete).right, greaterThan(336));
        expect(
          tester.getRect(selectAll).right,
          lessThan(tester.getRect(restore).left),
        );

        await tester.tap(selectAll);
        await tester.pumpAndSettle();
        expect(find.text(binL10n.itemsSelected(3)), findsOneWidget);
        expect(selectAll, findsNothing);
        expect(
          tester
              .widgetList<EntryTile>(find.byType(EntryTile))
              .every((tile) => tile.selected),
          isTrue,
        );
        expect(
          tester
              .widget<ListTile>(find.widgetWithText(ListTile, group.name))
              .selected,
          isTrue,
        );
        expect(restore, findsOneWidget);
        expect(delete, findsOneWidget);

        await tester.tap(find.text(group.name));
        await tester.pumpAndSettle();
        expect(find.text(binL10n.itemsSelected(2)), findsOneWidget);
        expect(selectAll, findsOneWidget);

        await tester.tap(find.byTooltip(binL10n.cancel));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, binTitle), findsOneWidget);
        expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
        expect(
          tester
              .widgetList<EntryTile>(find.byType(EntryTile))
              .every((tile) => !tile.selected),
          isTrue,
        );
      },
    );
  }

  for (final currentLocale in [const Locale('it'), const Locale('en')]) {
    for (final home in [true, false]) {
      testWidgets(
        '${home ? "Home" : "Sottogruppo"} ${currentLocale.languageCode}: seleziona tutti con testo dinamico nella seconda riga',
        (tester) async {
          // given
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final strings = lookupAppLocalizations(currentLocale);
          final db = newTestDatabase();
          final group = home
              ? db.root
              : db.createGroup(parent: db.root, name: 'Gruppo ordinario');
          final child = db.createGroup(
            parent: group,
            name: 'Sottogruppo visibile',
          );
          addTestEntry(db, group, {EntryFields.title: 'Prima voce ordinaria'});
          addTestEntry(db, group, {
            EntryFields.title: 'Seconda voce ordinaria',
          });
          addTestEntry(db, db.recycleBin!, {
            EntryFields.title: 'Voce nel Cestino',
          });
          final container = await newTestContainer();
          container
              .read(databaseSessionProvider.notifier)
              .open(
                DatabaseSession(
                  file: const FileRef(
                    uri: 'file:///prova.kdbx',
                    name: 'prova.kdbx',
                  ),
                  database: db,
                ),
              );
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                locale: currentLocale,
                localizationsDelegates: [
                  ...GlobalMaterialLocalizations.delegates,
                  ...AppLocalizations.localizationsDelegates,
                ],
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildLightTheme(),
                home: GroupView(groupId: home ? null : itemIdOf(group)),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.widgetWithText(AppBar, group.name), findsOneWidget);
          expect(find.text(strings.itemsSelectAllShort), findsNothing);

          // when
          await tester.longPress(find.text('Prima voce ordinaria'));
          await tester.pumpAndSettle();

          // then
          final selectAll = find.widgetWithText(
            TextButton,
            strings.itemsSelectAllShort,
          );
          final delete = find.byTooltip(strings.entryDelete);
          final move = find.byTooltip(strings.itemMoveTitle);
          expect(selectAll, findsOneWidget);
          expect(find.byIcon(Icons.select_all), findsNothing);
          expect(find.byType(Checkbox), findsNothing);
          expect(tester.getRect(selectAll).left, lessThan(24));
          expect(tester.getRect(selectAll).top, greaterThanOrEqualTo(48));
          expect(tester.getRect(delete).top, greaterThanOrEqualTo(48));
          expect(tester.getRect(delete).right, greaterThan(336));
          expect(
            tester.getRect(selectAll).right,
            lessThan(tester.getRect(move).left),
          );
          await tester.tap(selectAll);
          await tester.pumpAndSettle();
          expect(selectAll, findsNothing);
          expect(find.text(strings.itemsSelected(3)), findsOneWidget);
          expect(
            tester
                .widgetList<EntryTile>(find.byType(EntryTile))
                .every((tile) => tile.selected),
            isTrue,
          );
          expect(
            tester
                .widget<ListTile>(find.widgetWithText(ListTile, child.name))
                .selected,
            isTrue,
          );

          await tester.tap(find.text('Seconda voce ordinaria'));
          await tester.pumpAndSettle();
          expect(selectAll, findsOneWidget);
          expect(find.text(strings.itemsSelected(2)), findsOneWidget);
          await tester.tap(find.byTooltip(strings.cancel));
          await tester.pumpAndSettle();
          expect(selectAll, findsNothing);
          expect(find.widgetWithText(AppBar, group.name), findsOneWidget);
          expect(
            tester
                .widgetList<EntryTile>(find.byType(EntryTile))
                .every((tile) => !tile.selected),
            isTrue,
          );
        },
      );
    }
  }

  for (final (limit, themeMode) in [
    (5, ThemeMode.light),
    (10, ThemeMode.light),
    (15, ThemeMode.dark),
  ]) {
    testWidgets('riquadro unico con $limit password recenti', (tester) async {
      // given
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = newTestDatabase();
      final group = db.createGroup(parent: db.root, name: 'Gruppo di prova');
      final recent = [
        for (var index = 1; index <= 15; index++)
          addTestEntry(db, group, {EntryFields.title: 'Voce recente $index'}),
      ];
      final ids = recent.map(itemIdOf).toList();
      final container = await newTestContainer(
        overrides: [recentPasswordIdsProvider.overrideWith((_, _) => ids)],
      );
      container
          .read(databaseSessionProvider.notifier)
          .open(
            DatabaseSession(
              file: const FileRef(
                uri: 'file:///prova.kdbx',
                name: 'prova.kdbx',
              ),
              database: db,
            ),
          );
      await container
          .read(appSettingsProvider.notifier)
          .update(AppSettings(recentPasswordLimit: limit));

      // when
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
            darkTheme: buildDarkTheme(),
            themeMode: themeMode,
            home: const GroupView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // then
      final heading = find.text(l10n.recentPasswordsTitle);
      final panel = find.ancestor(
        of: heading,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Material && widget.shape is RoundedRectangleBorder,
        ),
      );
      expect(panel, findsOneWidget);
      final material = tester.widget<Material>(panel);
      expect(material.color?.withValues(alpha: 1), AppColors.blue);
      expect(material.color?.a, inExclusiveRange(0, 1));
      expect(
        find.ancestor(
          of: heading,
          matching: find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.header == true,
          ),
        ),
        findsOneWidget,
      );
      final tiles = find.descendant(
        of: panel,
        matching: find.byType(EntryTile),
      );
      expect(
        tester.widgetList<EntryTile>(tiles).map((tile) => tile.entry),
        orderedEquals(recent.take(limit)),
      );

      expect(
        find.descendant(of: panel, matching: find.byIcon(Icons.expand_less)),
        findsOneWidget,
      );
      await tester.tap(heading);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: panel, matching: find.byType(EntryTile)),
        findsNothing,
      );
      expect(
        find.descendant(of: panel, matching: find.byIcon(Icons.expand_more)),
        findsOneWidget,
      );
      await tester.tap(heading);
      await tester.pumpAndSettle();
      expect(
        tester.widgetList<EntryTile>(tiles).map((tile) => tile.entry),
        orderedEquals(recent.take(limit)),
      );
      expect(
        find.descendant(of: panel, matching: find.byIcon(Icons.expand_less)),
        findsOneWidget,
      );

      final scrollable = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      final lastEntry = find.text('Voce recente $limit').hitTestable();
      final groupTitle = find.text(group.name).hitTestable();
      await tester.scrollUntilVisible(lastEntry, 160, scrollable: scrollable);
      expect(lastEntry, findsOneWidget);
      await tester.scrollUntilVisible(groupTitle, 160, scrollable: scrollable);
      expect(groupTitle, findsOneWidget);
      expect(find.descendant(of: panel, matching: groupTitle), findsNothing);

      await tester.longPress(groupTitle);
      await tester.pumpAndSettle();
      expect(heading, findsNothing);
    });
  }
}
