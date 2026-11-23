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
