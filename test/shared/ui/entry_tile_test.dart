import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/ui/entry_tile.dart';
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
  testWidgets('mostra i colori della voce e ignora i valori non validi', (
    tester,
  ) async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Esempio'})
      ..foreground = '#aBc123'
      ..background = '#102030';
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

    var tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.textColor, const Color(0xffabc123));
    expect(tile.tileColor, const Color(0xff102030));

    entry
      ..foreground = '#12345g'
      ..background = '#123';
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
    tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.textColor, isNull);
    expect(tile.tileColor, isNull);
  });
}
