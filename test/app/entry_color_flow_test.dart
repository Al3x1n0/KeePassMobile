import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/entry/entry_view.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view_model.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/ui/entry_color.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets(
    'selettore conserva colori originali finché non si sceglie un preset o Nessuno',
    (tester) async {
      final db = newTestDatabase();
      final original = addTestEntry(db, db.root, {EntryFields.title: 'Voce'})
        ..background = '#D0EAD0'
        ..foreground = '#123456';
      final (file, reopened) = (await tester.runAsync(
        () => saveToTempFile(db),
      ))!;
      final id = itemIdOf(original);
      final container = await newTestContainer(file: file, database: reopened);
      final router = GoRouter(
        initialLocation: AppRoutes.entry(id),
        routes: [
          GoRoute(
            path: '/db/entry/:id',
            builder: (_, state) =>
                EntryView(entryId: state.pathParameters['id']!),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (_, state) => EntryEditView(
                  target: EntryEditTarget.edit(state.pathParameters['id']!),
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            locale: const Locale('en'),
            localizationsDelegates: [
              ...GlobalMaterialLocalizations.delegates,
              ...AppLocalizations.localizationsDelegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildDarkTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> edit() async {
        await tester.tap(find.byTooltip(l10n.groupMore));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.entryEdit));
        await tester.pumpAndSettle();
      }

      Future<void> openColors() async {
        await tester.tap(find.widgetWithText(ListTile, l10n.entryColor));
        await tester.pumpAndSettle();
      }

      Future<void> save() async {
        await tester.tap(find.byTooltip(l10n.entryEditSave));
        await pumpUntilFound(tester, find.byTooltip(l10n.groupMore));
        await tester.pumpAndSettle();
      }

      await edit();
      final selector = find.widgetWithText(ListTile, l10n.entryColor);
      expect(
        find.descendant(
          of: selector,
          matching: find.text(l10n.entryColorGreen),
        ),
        findsOneWidget,
      );
      await openColors();
      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.byType(ListTile)),
        findsNWidgets(11),
      );
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, l10n.entryColorGreen).last,
            )
            .selected,
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.entryTitle),
        'Voce aggiornata',
      );
      await save();
      var saved = (await tester.runAsync(() => reopenFile(file)))!;
      expect(findEntry(saved, id)!.background, '#D0EAD0');
      expect(findEntry(saved, id)!.foreground, '#123456');

      await edit();
      await openColors();
      await tester.tap(
        find.widgetWithText(ListTile, l10n.entryColorGreen).last,
      );
      await tester.pumpAndSettle();
      await save();
      saved = (await tester.runAsync(() => reopenFile(file)))!;
      expect(findEntry(saved, id)!.background, EntryColor.green.hex);
      expect(findEntry(saved, id)!.foreground, '#123456');

      await edit();
      await openColors();
      await tester.tap(find.widgetWithText(ListTile, l10n.entryColorNone));
      await tester.pumpAndSettle();
      await save();
      saved = (await tester.runAsync(() => reopenFile(file)))!;
      expect(findEntry(saved, id)!.background, isNull);
      expect(findEntry(saved, id)!.foreground, '#123456');
      expect(find.byIcon(Icons.circle), findsNothing);
    },
  );

  testWidgets('crea una voce con un colore scelto dalla palette', (
    tester,
  ) async {
    final db = newTestDatabase();
    final (file, reopened) = (await tester.runAsync(() => saveToTempFile(db)))!;
    final container = await newTestContainer(file: file, database: reopened);
    final router = GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(
          path: '/new',
          builder: (_, _) => EntryEditView(
            target: EntryEditTarget.create(itemIdOf(reopened.root)),
          ),
        ),
        GoRoute(
          path: '/db/entry/:id',
          builder: (_, state) =>
              EntryView(entryId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);
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
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final italian = lookupAppLocalizations(const Locale('it'));
    await tester.enterText(
      find.widgetWithText(TextFormField, italian.entryTitle),
      'Nuova voce',
    );
    await tester.tap(find.widgetWithText(ListTile, italian.entryColor));
    await tester.pumpAndSettle();
    final blue = find.widgetWithText(ListTile, italian.entryColorBlue);
    await tester.scrollUntilVisible(
      blue,
      150,
      scrollable: find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(blue);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(italian.entryEditSave));
    await pumpUntilFound(tester, find.byType(EntryView));
    await tester.pumpAndSettle();
    final saved = (await tester.runAsync(() => reopenFile(file)))!;
    expect(saved.root.allEntries.single.background, EntryColor.blue.hex);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            widget.message ==
                italian.entryColorIndicator(italian.entryColorBlue),
      ),
      findsOneWidget,
    );
  });
}
