import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/ui/entry_tile.dart';
import 'package:keepass_mobile/shared/ui/entry_color.dart';
import 'package:keepass_mobile/shared/ui/expandable_section.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  testWidgets('dimensione del testo segue la preferenza', (tester) async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Esempio'});
    final container = await newTestContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: EntryTile(entry: entry, onTap: () {}),
          ),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('Esempio')).style?.fontSize, 20);
    final settings = container.read(appSettingsProvider);
    await container
        .read(appSettingsProvider.notifier)
        .update(settings.copyWith(listTextSize: 28));
    await tester.pump();
    expect(tester.widget<Text>(find.text('Esempio')).style?.fontSize, 28);
  });
  testWidgets('titolo risolto solo se valido e non protetto', (tester) async {
    final db = newTestDatabase();
    addTestEntry(
      db,
      db.root,
      {
        EntryFields.title: 'Origine',
        EntryFields.userName: 'Visibile',
        EntryFields.password: 'segreto',
      },
      protectedKeys: {EntryFields.password},
    );
    final entry = addTestEntry(db, db.root, {
      EntryFields.title: '{REF:U@T:Origine}',
    });
    final (file, reopened) = (await tester.runAsync(() => saveToTempFile(db)))!;
    final saved = reopened.root.allEntries.firstWhere(
      (item) => entryTitle(item) == entryTitle(entry),
    );
    final container = await newTestContainer(file: file, database: reopened);
    Widget view() => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EntryTile(entry: saved, onTap: () {}),
        ),
      ),
    );
    await tester.pumpWidget(view());
    expect(find.text('Visibile'), findsOneWidget);
    saved.fields[EntryFields.title] = PlainTextField('{REF:P@T:Origine}');
    await tester.pumpWidget(view());
    expect(find.text('segreto'), findsNothing);
    expect(find.text('(no title)'), findsOneWidget);
    saved.fields[EntryFields.title] = PlainTextField('{REF:U@T:Assente}');
    await tester.pumpWidget(view());
    expect(find.text('(no title)'), findsOneWidget);
  });
  testWidgets('barra adattata senza cambiare testo, sfondo o allineamento', (
    tester,
  ) async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Esempio'})
      ..foreground = '#aBc123'
      ..background = '#CCFFCC';
    final container = await newTestContainer();
    Widget view() => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: EntryTile(entry: entry, onTap: () {}),
        ),
      ),
    );
    await tester.pumpWidget(view());
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.textColor, isNull);
    expect(tile.tileColor, isNull);
    final titleOffset = tester.getTopLeft(find.text('Esempio'));
    final iconOffset = tester.getTopLeft(find.byType(Icon).first);
    final stripe = find.byWidgetPredicate(
      (widget) =>
          widget is ColoredBox && widget.color == EntryColor.green.color,
    );
    expect(stripe, findsOneWidget);
    expect(
      tester.getRect(stripe).height,
      tester.getSize(find.byType(ListTile)).height,
    );
    expect(
      tester.getRect(stripe).left,
      tester.getRect(find.byType(ListTile)).left,
    );
    expect(find.byIcon(Icons.attach_file), findsNothing);
    for (final background in <String?>[
      null,
      '',
      '#123',
      '!#123456',
      '#12345g',
    ]) {
      entry.background = background;
      await tester.pumpWidget(view());
      expect(stripe, findsNothing);
      expect(tester.getTopLeft(find.text('Esempio')), titleOffset);
      expect(tester.getTopLeft(find.byType(Icon).first), iconOffset);
    }
  });

  for (final dark in [false, true]) {
    for (final selected in [false, true]) {
      testWidgets('barra a tutta altezza: scuro=$dark selezione=$selected', (
        tester,
      ) async {
        final db = newTestDatabase();
        final entry = addTestEntry(db, db.root, {
          EntryFields.title: List.filled(8, 'Titolo lungo').join(' '),
          EntryFields.userName: List.filled(5, 'utente').join(' '),
        })..background = '#CCFFCC';
        final container = await newTestContainer();
        final settings = container.read(appSettingsProvider);
        await container
            .read(appSettingsProvider.notifier)
            .update(
              settings.copyWith(listTextSize: 28, showUserNameInList: true),
            );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: dark ? buildDarkTheme() : buildLightTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SizedBox(
                    width: 320,
                    child: EntryTile(
                      entry: entry,
                      databaseOverride: db,
                      groupName: 'Gruppo di prova con nome esteso su più righe',
                      selected: selected,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final stripe = find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == EntryColor.green.color,
        );
        final row = tester.getRect(find.byType(ListTile));
        final bar = tester.getRect(stripe);
        expect(row.height, greaterThan(150));
        expect(bar.height, row.height);
        expect(bar.top, row.top);
        expect(bar.bottom, row.bottom);
        expect(bar.width, AppEntryColorLayout.stripeWidth);
        final tile = tester.widget<ListTile>(find.byType(ListTile));
        expect(tile.selected, selected);
        expect(tile.textColor, isNull);
        expect(tile.tileColor, isNull);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('barra ritagliata nel riquadro recenti: scuro=$dark', (
      tester,
    ) async {
      final db = newTestDatabase();
      final entry = addTestEntry(db, db.root, {EntryFields.title: 'Recente'})
        ..background = EntryColor.yellow.hex;
      final container = await newTestContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: dark ? buildDarkTheme() : buildLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: ExpandableSection(
                  title: 'Password recenti',
                  children: [EntryTile(entry: entry, onTap: () {})],
                ),
              ),
            ),
          ),
        ),
      );
      final stripe = find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == EntryColor.yellow.color,
      );
      final materials = tester.widgetList<Material>(
        find.ancestor(of: stripe, matching: find.byType(Material)),
      );
      expect(
        materials.any(
          (m) =>
              m.shape == AppSectionLayout.shape &&
              m.clipBehavior == Clip.antiAlias,
        ),
        isTrue,
      );
      expect(
        tester.getRect(stripe).bottom,
        tester.getRect(find.byType(ListTile)).bottom,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
