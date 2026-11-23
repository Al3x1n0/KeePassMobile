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
  Future<void> open(WidgetTester tester, {Finder? waitFor}) async {
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
    await pumpUntilFound(tester, waitFor ?? find.text('Origine'));
    await tester.pumpAndSettle();
  }

  Future<void> entryMenu(WidgetTester tester, String action) async {
    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pumpAndSettle();
    await tester.tap(find.text(action));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> addGroup(WidgetTester tester) async {
    await tester.tap(find.byTooltip(l10n.groupAddEntry));
    await tester.pumpAndSettle();
    expect(find.text(l10n.groupAddTitle), findsOneWidget);
    expect(find.text(l10n.entryTemplateEmpty), findsOneWidget);
    await tester.tap(find.text(l10n.groupCreate));
    await tester.pumpAndSettle();
  }

  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

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
    // given
    await open(tester);
    await tester.tap(tab(l10n.settingsTitle));
    await tester.pumpAndSettle();
    expect(find.text(l10n.settingsDatabase), findsOneWidget);
    final install = find.widgetWithText(ListTile, l10n.templatesInstall);
    await tester.ensureVisible(install);
    expect(
      find.descendant(
        of: install,
        matching: find.text(l10n.templatesInstallHint),
      ),
      findsOneWidget,
    );

    // when
    await tester.tap(install);
    await tester.pumpAndSettle();
    expect(find.text(l10n.templatesInstallConfirm), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, l10n.templatesInstall));
    await pumpUntilFound(tester, find.text(l10n.templatesInstallSuccess));
    await tester.tap(tab(l10n.navigationHome));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, l10n.templateGroup), findsOneWidget);
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

    // then
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
    await tester.tap(find.text(l10n.itemsSelectAllShort));
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
    await addGroup(tester);
    await tester.enterText(find.byType(TextFormField), 'Sottogruppo');
    await tester.tap(find.text(l10n.entryEditSave));
    await pumpUntilFound(tester, find.widgetWithText(ListTile, 'Sottogruppo'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Voce sintetica'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sottogruppo'));
    await tester.pumpAndSettle();
    final before = file.readAsBytesSync();
    final sheet = find.byType(BottomSheet);
    final destination = find.descendant(
      of: sheet,
      matching: find.text('Prova / Destinazione'),
    );
    await tester.tap(find.byTooltip(l10n.itemMoveTitle));
    await tester.pumpAndSettle();
    expect(tester.widget<BottomSheet>(sheet).showDragHandle, isTrue);
    expect(destination, findsOneWidget);
    expect(find.text('Prova / Origine / Sottogruppo'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(find.text(l10n.itemsSelected(2)), findsOneWidget);
    expect(file.readAsBytesSync(), before);
    await tester.tap(find.byTooltip(l10n.itemMoveTitle));
    await tester.pumpAndSettle();
    await tester.tap(destination);
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
      expect(find.widgetWithText(ListTile, bin.name), findsNothing);
      await tester.tap(find.byTooltip(l10n.dbSettingsRecycleBin));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Origine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Seconda voce'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.itemRestore));
      await pumpUntilFound(
        tester,
        find.widgetWithText(AppBar, l10n.dbSettingsRecycleBin),
      );
      final restored = (await tester.runAsync(() => reopenFile(file)))!;
      expect(restored.root.groups.map((g) => g.name), contains('Origine'));
      expect(restored.root.entries.map(entryTitle), contains('Seconda voce'));
    },
  );

  testWidgets(
    'crea, rinomina ed elimina un gruppo, poi ripristina dal cestino',
    (tester) async {
      // given
      final withoutBin = (await tester.runAsync(() => reopenFile(file)))!;
      withoutBin.root.groups.remove(existingRecycleBin(withoutBin)!);
      withoutBin.meta.recycleBinUuid = null;
      await tester.runAsync(
        () async => file.writeAsBytes(await withoutBin.save()),
      );
      final initial = (await tester.runAsync(() => reopenFile(file)))!;
      expect(initial.meta.recycleBinEnabled, isTrue);
      expect(existingRecycleBin(initial), isNull);
      final before = file.readAsBytesSync();
      await open(tester);
      expect(find.byTooltip(l10n.dbSettingsRecycleBin), findsNothing);
      expect(file.readAsBytesSync(), before);

      // when
      await addGroup(tester);
      await tester.enterText(find.byType(TextFormField), 'Creato');
      await tester.tap(find.text(l10n.entryEditSave));
      await pumpUntilFound(tester, find.widgetWithText(ListTile, 'Creato'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Creato'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.groupEdit));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Rinominato');
      await tester.tap(find.text(l10n.entryEditSave));
      await pumpUntilFound(tester, find.widgetWithText(ListTile, 'Rinominato'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Prova'), findsOneWidget);
      await tester.longPress(find.text('Rinominato'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.entryDelete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, l10n.entryDelete));
      final recycleBin = find.byTooltip(l10n.dbSettingsRecycleBin);
      await pumpUntilFound(tester, recycleBin);
      await tester.pumpAndSettle();
      final db = (await tester.runAsync(() => reopenFile(file)))!;
      final binName = existingRecycleBin(db)!.name;
      expect(find.widgetWithText(ListTile, binName), findsNothing);
      expect(
        isInRecycleBin(
          db,
          db.root.allGroups.singleWhere((g) => g.name == 'Rinominato'),
        ),
        isTrue,
      );
      await tester.tap(recycleBin);
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Rinominato'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.itemRestore));
      await pumpUntilFound(
        tester,
        find.widgetWithText(AppBar, l10n.dbSettingsRecycleBin),
      );

      // then
      expect(find.text('Rinominato'), findsNothing);
      final restored = (await tester.runAsync(() => reopenFile(file)))!;
      expect(restored.root.groups.map((g) => g.name), contains('Rinominato'));
    },
  );

  testWidgets('mostra le azioni della Home nell’ordine richiesto', (
    tester,
  ) async {
    // given
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    addTestEntry(db, db.recycleBin!, {EntryFields.title: 'Voce eliminata'});
    db.root.allEntries
        .singleWhere((e) => entryTitle(e) == 'Voce sintetica')
        .tags = [
      'Favorite',
    ];
    await tester.runAsync(() async => file.writeAsBytes(await db.save()));
    await open(tester);

    // then: da sinistra a destra, con tutte le azioni visibili.
    final labels = [
      l10n.dbSettingsRecycleBin,
      l10n.groupSort,
      l10n.databasesTitle,
      l10n.syncNow,
      l10n.favoritesTitle,
      l10n.searchTitle,
      l10n.groupLock,
    ];
    final appBar = find.byType(AppBar);
    final actions = [
      for (final label in labels)
        find.descendant(of: appBar, matching: find.byTooltip(label)),
    ];
    for (final action in actions) {
      expect(action, findsOneWidget);
    }
    final positions = [
      for (final action in actions) tester.getTopLeft(action).dx,
    ];
    expect(positions, orderedEquals([...positions]..sort()));
    expect(find.widgetWithText(ListTile, db.recycleBin!.name), findsNothing);
  });

  testWidgets('nasconde cestino vuoto e preferiti assenti nella Home', (
    tester,
  ) async {
    // given: il gruppo Cestino esiste, ma non contiene elementi.
    final db = newTestDatabase();
    expect(db.recycleBin, isNotNull);
    await tester.runAsync(() async => file.writeAsBytes(await db.save()));
    final before = file.readAsBytesSync();

    // when / then
    await open(tester, waitFor: find.text(l10n.groupEmpty));
    expect(find.byTooltip(l10n.dbSettingsRecycleBin), findsNothing);
    expect(find.byTooltip(l10n.favoritesTitle), findsNothing);
    expect(find.byTooltip(l10n.syncNow), findsOneWidget);
    expect(file.readAsBytesSync(), before);
  });

  for (final groupOnly in [true, false]) {
    testWidgets(
      'mostra il cestino con ${groupOnly ? 'un solo gruppo' : 'una sola voce'}',
      (tester) async {
        final db = (await tester.runAsync(() => reopenFile(file)))!;
        final bin = db.recycleBin!;
        if (groupOnly) {
          db.createGroup(parent: bin, name: 'Gruppo eliminato');
        } else {
          addTestEntry(db, bin, {EntryFields.title: 'Voce eliminata'});
        }
        await tester.runAsync(() async => file.writeAsBytes(await db.save()));
        await open(tester);
        final action = find.byTooltip(l10n.dbSettingsRecycleBin);
        expect(action, findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(
          find.text(groupOnly ? 'Gruppo eliminato' : 'Voce eliminata'),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('elimina tutto dal cestino tramite selezione e conferma', (
    tester,
  ) async {
    // given
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    final bin = db.recycleBin!;
    db.createGroup(parent: bin, name: 'Gruppo eliminato');
    addTestEntry(db, bin, {EntryFields.title: 'Voce eliminata'});
    await tester.runAsync(() async => file.writeAsBytes(await db.save()));
    final before = file.readAsBytesSync();
    await open(tester);
    await tester.tap(find.byTooltip(l10n.dbSettingsRecycleBin));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(AppBar, l10n.dbSettingsRecycleBin),
      findsOneWidget,
    );
    expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
    expect(find.byIcon(Icons.delete_forever_outlined), findsNothing);
    expect(find.byTooltip(l10n.groupAddEntry), findsNothing);

    // when
    await tester.longPress(find.text('Gruppo eliminato'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNotNull);
    await tester.tap(find.text(l10n.itemsSelectAllShort));
    await tester.pumpAndSettle();
    expect(find.text(l10n.itemsSelected(2)), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.entryDelete));
    await tester.pumpAndSettle();
    expect(find.text(l10n.itemsDeletePermanent), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, l10n.cancel));
    await tester.pumpAndSettle();
    expect(file.readAsBytesSync(), before);
    await tester.tap(find.byTooltip(l10n.entryDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.entryDelete));
    await pumpUntilFound(tester, find.text(l10n.groupEmpty));
    await tester.pumpAndSettle();

    // then
    expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
    final reopened = (await tester.runAsync(() => reopenFile(file)))!;
    final savedBin = existingRecycleBin(reopened)!;
    expect(savedBin.groups, isEmpty);
    expect(savedBin.entries, isEmpty);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip(l10n.dbSettingsRecycleBin), findsNothing);
  });

  testWidgets('mostra Modifica gruppo solo per un gruppo fuori dal cestino', (
    tester,
  ) async {
    // given
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    db.createGroup(parent: db.recycleBin!, name: 'Gruppo eliminato');
    await tester.runAsync(() async => file.writeAsBytes(await db.save()));
    await open(tester);
    final edit = find.byTooltip(l10n.groupEdit);

    // when / then
    await tester.longPress(find.text('Origine'));
    await tester.pumpAndSettle();
    expect(edit, findsOneWidget);
    expect(
      find.descendant(of: edit, matching: find.byIcon(Icons.edit_outlined)),
      findsOneWidget,
    );
    await tester.tap(find.text('Destinazione'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.itemsSelected(2)), findsOneWidget);
    expect(edit, findsNothing);

    await tester.tap(find.byTooltip(l10n.cancel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Origine'));
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
    for (final label in [
      l10n.groupLock,
      l10n.syncNow,
      l10n.searchTitle,
      l10n.groupSort,
    ]) {
      expect(find.byTooltip(label), findsNothing);
    }
    await tester.longPress(find.text('Voce sintetica'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.itemsSelected(1)), findsOneWidget);
    expect(edit, findsNothing);

    await tester.tap(find.byTooltip(l10n.cancel));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.dbSettingsRecycleBin));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Gruppo eliminato'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.itemsSelected(1)), findsOneWidget);
    expect(edit, findsNothing);
    expect(find.byTooltip(l10n.itemRestore), findsOneWidget);
    expect(find.byIcon(Icons.delete_forever_outlined), findsNothing);
    await tester.tap(find.byTooltip(l10n.entryDelete));
    await tester.pumpAndSettle();
    expect(find.text(l10n.itemsDeletePermanent), findsOneWidget);
  });

  testWidgets('annullare una bozza di gruppo non modifica il file', (
    tester,
  ) async {
    await open(tester);
    final before = file.readAsBytesSync();
    await addGroup(tester);
    await tester.enterText(find.byType(TextFormField), 'Non salvato');
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.text('Non salvato'), findsNothing);
    expect(file.readAsBytesSync(), before);
  });

  testWidgets('sposta il gruppo selezionato dalla bottom sheet', (
    tester,
  ) async {
    await open(tester);
    await tester.longPress(find.text('Origine'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.itemMoveTitle));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Prova / Destinazione'),
      ),
    );
    await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Prova'));
    final reopened = (await tester.runAsync(() => reopenFile(file)))!;
    final target = reopened.root.groups.singleWhere(
      (group) => group.name == 'Destinazione',
    );
    expect(target.groups.map((group) => group.name), ['Origine']);
  });

  testWidgets('duplica e sposta la copia con selettore di destinazione', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Origine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voce sintetica'));
    await tester.pumpAndSettle();
    await entryMenu(tester, l10n.itemDuplicate);
    final copyTitle = 'Voce sintetica - ${l10n.itemDuplicateSuffix}';
    await pumpUntilFound(tester, find.widgetWithText(AppBar, copyTitle));
    await tester.pumpAndSettle();
    await entryMenu(tester, l10n.itemMoveTitle);
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Prova / Destinazione'),
      ),
    );
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
