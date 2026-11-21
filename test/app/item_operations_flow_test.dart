import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File file;
  setUp(() async {
    final db = newTestDatabase();
    final group = db.createGroup(parent: db.root, name: 'Origine');
    db.createGroup(parent: db.root, name: 'Destinazione');
    addTestEntry(db, group, {EntryFields.title: 'Voce sintetica'});
    final saved = await saveToTempFile(db);
    file = saved.$1;
    addTearDown(() => file.parent.deleteSync(recursive: true));
  });
  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        jsonEncode(RecentFile(database: fileRefOf(file)).toJson()),
      ],
    });
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('prova.kdbx'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.text('Origine'));
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String action) async {
    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets('apre il gruppo della voce trovata dalla ricerca', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip(l10n.searchTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Voce sintetica');
    await tester.pumpAndSettle();
    final entry = find.widgetWithText(ListTile, 'Voce sintetica');
    final chevron = find.descendant(
      of: entry,
      matching: find.byIcon(Icons.chevron_right),
    );
    final detail = find.widgetWithText(AppBar, 'Voce sintetica');
    expect(chevron, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(detail, findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.longPress(entry);
    await tester.pumpAndSettle();
    expect(chevron, findsNothing);
    await tester.tap(find.byTooltip(l10n.searchGoToGroup));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Origine'), findsOneWidget);
    expect(chevron, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(detail, findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.longPress(entry);
    await tester.pumpAndSettle();
    expect(chevron, findsNothing);
  });

  testWidgets('aggiunge i modelli predefiniti al database', (tester) async {
    await open(tester);
    await menu(tester, l10n.templatesInstall);
    expect(find.text(l10n.templatesInstallConfirm), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l10n.templatesInstall));
    await pumpUntilFound(
      tester,
      find.widgetWithText(ListTile, l10n.templateGroup),
    );
    await tester.tap(find.byTooltip(l10n.groupAddEntry));
    await tester.pumpAndSettle();
    expect(find.text(l10n.templateCreditCard), findsOneWidget);
    await tester.tap(find.text(l10n.templateCreditCard));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.entryTitle),
      'Card sample',
    );
    await tester.tap(find.byTooltip(l10n.entryEditSave));
    await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Card sample'));
    final reopened = (await tester.runAsync(() => reopenFile(file)))!;
    final entry = reopened.root.entries.singleWhere(
      (e) => entryTitle(e) == 'Card sample',
    );
    expect(entry.fields.keys, containsAll(['CVV', 'PIN']));
  });

  testWidgets('seleziona tutti gli elementi e consente di annullare', (
    tester,
  ) async {
    await open(tester);
    await tester.longPress(find.text('Origine'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.itemsSelectAll));
    await tester.pumpAndSettle();
    expect(find.text(l10n.itemsSelected(2)), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Prova'), findsOneWidget);
    expect(find.text('Origine'), findsOneWidget);
    expect(find.text('Destinazione'), findsOneWidget);
  });

  testWidgets('sposta più elementi nello stesso gruppo di destinazione', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Origine'));
    await tester.pumpAndSettle();
    await menu(tester, l10n.groupCreate);
    await tester.enterText(find.byType(TextFormField), 'Sottogruppo');
    await tester.tap(find.text(l10n.entryEditSave));
    await pumpUntilFound(tester, find.widgetWithText(ListTile, 'Sottogruppo'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Voce sintetica'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sottogruppo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.itemMoveTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prova / Destinazione'));
    await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Origine'));
    final reopened = (await tester.runAsync(() => reopenFile(file)))!;
    final target = reopened.root.groups.singleWhere(
      (g) => g.name == 'Destinazione',
    );
    expect(target.entries.map(entryTitle), contains('Voce sintetica'));
    expect(target.groups.map((g) => g.name), contains('Sottogruppo'));
  });

  testWidgets(
    'seleziona e sposta più elementi nel cestino con un salvataggio',
    (tester) async {
      final db = (await tester.runAsync(() => reopenFile(file)))!;
      addTestEntry(db, db.root, {EntryFields.title: 'Seconda voce'});
      await tester.runAsync(() async => file.writeAsBytes(await db.save()));
      await open(tester);
      await tester.longPress(find.text('Origine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seconda voce'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.itemsSelected(2)), findsOneWidget);
      await tester.tap(find.byTooltip(l10n.entryDelete));
      await tester.pumpAndSettle();
      expect(find.text(l10n.itemsDeleteRecycle), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, l10n.entryDelete));
      await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Prova'));
      await tester.pumpAndSettle();
      final reopened = (await tester.runAsync(() => reopenFile(file)))!;
      final bin = existingRecycleBin(reopened)!;
      expect(bin.groups.map((g) => g.name), contains('Origine'));
      expect(bin.entries.map(entryTitle), contains('Seconda voce'));
      expect(
        bin.groups
            .singleWhere((g) => g.name == 'Origine')
            .entries
            .map(entryTitle),
        contains('Voce sintetica'),
      );
      await tester.tap(find.text(bin.name));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Origine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seconda voce'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.itemRestore));
      await pumpUntilFound(tester, find.widgetWithText(AppBar, bin.name));
      final restored = (await tester.runAsync(() => reopenFile(file)))!;
      expect(restored.root.groups.map((g) => g.name), contains('Origine'));
      expect(restored.root.entries.map(entryTitle), contains('Seconda voce'));
    },
  );

  testWidgets(
    'crea, rinomina ed elimina un gruppo, poi ripristina dal cestino',
    (tester) async {
      await open(tester);
      await menu(tester, l10n.groupCreate);
      await tester.enterText(find.byType(TextFormField), 'Creato');
      await tester.tap(find.text(l10n.entryEditSave));
      await pumpUntilFound(tester, find.widgetWithText(ListTile, 'Creato'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Creato'));
      await tester.pumpAndSettle();
      await menu(tester, l10n.groupEdit);
      await tester.enterText(find.byType(TextFormField), 'Rinominato');
      await tester.tap(find.text(l10n.entryEditSave));
      await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Rinominato'));
      await tester.pumpAndSettle();
      await menu(tester, l10n.groupDelete);
      await tester.tap(find.widgetWithText(FilledButton, l10n.entryDelete));
      await pumpUntilFound(tester, find.text('Origine'));
      await tester.pumpAndSettle();
      final db = (await tester.runAsync(() => reopenFile(file)))!;
      final binName = existingRecycleBin(db)!.name;
      expect(
        isInRecycleBin(
          db,
          db.root.allGroups.singleWhere((g) => g.name == 'Rinominato'),
        ),
        isTrue,
      );
      await tester.tap(find.text(binName));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rinominato'));
      await tester.pumpAndSettle();
      await menu(tester, l10n.itemRestore);
      await pumpUntilFound(tester, find.text('Origine'));
      final restored = (await tester.runAsync(() => reopenFile(file)))!;
      expect(restored.root.groups.map((g) => g.name), contains('Rinominato'));
    },
  );

  testWidgets('annullare una bozza di gruppo non modifica il file', (
    tester,
  ) async {
    await open(tester);
    final before = file.readAsBytesSync();
    await menu(tester, l10n.groupCreate);
    await tester.enterText(find.byType(TextFormField), 'Non salvato');
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.text('Non salvato'), findsNothing);
    expect(file.readAsBytesSync(), before);
  });

  testWidgets('duplica e sposta la copia con selettore di destinazione', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Origine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voce sintetica'));
    await tester.pumpAndSettle();
    await menu(tester, l10n.itemDuplicate);
    final copyTitle = 'Voce sintetica - ${l10n.itemDuplicateSuffix}';
    await pumpUntilFound(tester, find.widgetWithText(AppBar, copyTitle));
    await tester.pumpAndSettle();
    await menu(tester, l10n.itemMoveTitle);
    await tester.tap(find.text('Prova / Destinazione'));
    await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Destinazione'));
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    final copy = db.root.allEntries.singleWhere(
      (e) => entryTitle(e) == copyTitle,
    );
    expect(copy.parent!.name, 'Destinazione');
    expect(
      db.root.allEntries.where((e) => entryTitle(e) == 'Voce sintetica'),
      hasLength(1),
    );
  });
}
