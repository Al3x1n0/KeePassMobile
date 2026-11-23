import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/app/database_navigation_bar.dart';
import 'package:keepass_mobile/features/entry/totp_tile.dart';
import 'package:keepass_mobile/features/password_generator/generator_view.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/home_menu.dart';
import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File file;

  setUp(() async {
    final db = newTestDatabase();
    final bank = db.createGroup(parent: db.root, name: 'Banca');
    addTestEntry(
      db,
      bank,
      {
        EntryFields.title: 'Conto',
        EntryFields.userName: 'cliente',
        EntryFields.password: 'pin-123',
        'PIN': '9999',
        'otp': 'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP',
      },
      protectedKeys: {EntryFields.password, 'PIN'},
    );
    final dir = Directory.systemTemp.createTempSync('keepass_mobile_flow');
    file = File('${dir.path}/prova.kdbx')..writeAsBytesSync(await db.save());
  });

  Future<void> openApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        jsonEncode(RecentFile(database: fileRefOf(file)).toJson()),
      ],
    });
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          totpClockProvider.overrideWithValue(
            () => DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true),
          ),
        ],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('prova.kdbx'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.text('Banca'));
    await tester.pumpAndSettle();
  }

  Future<KdbxEntry?> entryOnDisk(WidgetTester tester, String title) async {
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    return db.root.allEntries.where((e) => entryTitle(e) == title).firstOrNull;
  }

  testWidgets(
    'sceglie un modello standard e crea una voce senza modificare il modello',
    (tester) async {
      final db = (await tester.runAsync(() => reopenFile(file)))!;
      final templates = db.createGroup(parent: db.root, name: 'Templates');
      db.meta.entryTemplatesGroup = templates.uuid;
      addTestEntry(db, templates, {
        EntryFields.title: 'Sample template',
        EntryFields.userName: 'sample-user',
      });
      await tester.runAsync(() async => file.writeAsBytes(await db.save()));
      await openApp(tester);
      await tester.tap(find.text('Banca'));
      await tester.pumpAndSettle();

      Future<void> openEntryChoices() async {
        await tester.tap(find.byTooltip(l10n.groupAddEntry));
        await tester.pumpAndSettle();
      }

      await openEntryChoices();
      final sheet = find.byType(BottomSheet);
      expect(tester.widget<BottomSheet>(sheet).showDragHandle, isTrue);
      expect(
        find.widgetWithText(BottomSheet, l10n.groupAddTitle),
        findsOneWidget,
      );
      final empty = find.widgetWithText(ListTile, l10n.entryTemplateEmpty);
      final template = find.widgetWithText(ListTile, 'Sample template');
      expect(empty, findsOneWidget);
      expect(find.widgetWithText(ListTile, l10n.groupCreate), findsOneWidget);
      expect(template, findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(find.widgetWithText(AppBar, 'Banca'), findsOneWidget);

      await openEntryChoices();
      await tester.tap(empty);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(AppBar, l10n.entryEditTitleNew),
        findsOneWidget,
      );
      final userName = find.widgetWithText(TextFormField, l10n.entryUserName);
      expect(tester.widget<TextFormField>(userName).controller?.text, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await openEntryChoices();
      await tester.tap(template);
      await tester.pumpAndSettle();
      expect(find.text('sample-user'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.entryTitle),
        'Sample copy',
      );
      await tester.tap(find.byTooltip(l10n.entryEditSave));
      await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Sample copy'));
      final saved = (await tester.runAsync(() => reopenFile(file)))!;
      expect(
        saved.root.allEntries.where((e) => entryTitle(e) == 'Sample template'),
        hasLength(1),
      );
      expect(
        saved.root.allEntries.where((e) => entryTitle(e) == 'Sample copy'),
        hasLength(1),
      );
    },
  );

  testWidgets('usa un modello strutturato e nasconde il collegamento tecnico', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    final templates = db.createGroup(parent: db.root, name: 'Templates');
    db.meta.entryTemplatesGroup = templates.uuid;
    addTestEntry(db, templates, {
      EntryFields.title: 'Structured',
      '_etm_template': '1',
      '_etm_title_PIN': 'PIN',
      '_etm_type_PIN': 'Protected Inline',
    });
    await tester.runAsync(() async => file.writeAsBytes(await db.save()));
    await openApp(tester);
    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.groupAddEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Structured'));
    await tester.pumpAndSettle();
    expect(find.text('_etm_template_uuid'), findsNothing);
    expect(
      find.widgetWithText(TextFormField, l10n.entryPassword),
      findsNothing,
    );
    await tester.ensureVisible(find.text(l10n.templateShowAllFields));
    await tester.tap(find.text(l10n.templateShowAllFields));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, l10n.entryPassword),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.entryTitle),
      'Structured copy',
    );
    await tester.tap(find.byTooltip(l10n.entryEditSave));
    await pumpUntilFound(
      tester,
      find.widgetWithText(AppBar, 'Structured copy'),
    );
    final saved = (await tester.runAsync(() => reopenFile(file)))!;
    final entry = saved.root.allEntries.singleWhere(
      (e) => entryTitle(e) == 'Structured copy',
    );
    expect(entry.fields['PIN'], isA<ProtectedTextField>());
    expect(entry.fields['_etm_template_uuid'], isNotNull);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.entryEdit));
    await tester.pumpAndSettle();
    expect(find.text('_etm_template_uuid'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.entryTitle),
      'Updated structured',
    );
    await tester.tap(find.byTooltip(l10n.entryEditSave));
    await pumpUntilFound(
      tester,
      find.widgetWithText(AppBar, 'Updated structured'),
    );
    final updated = (await tester.runAsync(() => reopenFile(file)))!
        .root
        .allEntries
        .singleWhere((e) => entryTitle(e) == 'Updated structured');
    expect(
      updated.fields['_etm_template_uuid']?.text,
      entry.fields['_etm_template_uuid']?.text,
    );
  });

  testWidgets('dettaglio: valori protetti nascosti, rivelati e copiati', (
    tester,
  ) async {
    final clipboard = FakeClipboard(tester.binding);
    await openApp(tester);

    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conto'));
    await tester.pumpAndSettle();

    expect(find.text('cliente'), findsOneWidget);
    expect(find.text('pin-123'), findsNothing);
    expect(find.text('9999'), findsNothing);

    await tester.tap(find.byTooltip(l10n.entryShow).first);
    await tester.pumpAndSettle();
    expect(find.text('pin-123'), findsOneWidget);
    expect(find.text('9999'), findsNothing);

    expect(find.byIcon(Icons.copy), findsNothing);
    expect(clipboard.text, isNull);
    await tester.tap(find.widgetWithText(ListTile, l10n.entryPassword));
    await tester.pumpAndSettle();
    expect(clipboard.text, 'pin-123');
    expect(find.text(l10n.entryCopied(30)), findsOneWidget);
  });

  testWidgets(
    'modifica: salvata nel file con la versione precedente in cronologia',
    (tester) async {
      await openApp(tester);
      await tester.tap(find.text('Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conto'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.entryEdit));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, l10n.entryTitle),
        'Conto corrente',
      );
      await tester.tap(find.byTooltip(l10n.entryEditSave));

      // Torna al dettaglio con il nuovo titolo.
      await pumpUntilFound(
        tester,
        find.widgetWithText(AppBar, 'Conto corrente'),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip(l10n.entryEditSave), findsNothing);

      final saved = await entryOnDisk(tester, 'Conto corrente');
      expect(saved, isNotNull);
      expect(saved!.history.map(entryTitle), ['Conto']);
      expect(saved.fields[EntryFields.password], isA<ProtectedTextField>());
      expect(saved.fields['PIN']?.text, '9999');
    },
  );

  testWidgets('nuova voce dal gruppo e ricerca', (tester) async {
    await openApp(tester);
    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.groupAddEntry));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(BottomSheet, l10n.groupAddTitle),
      findsOneWidget,
    );
    expect(find.widgetWithText(ListTile, l10n.groupCreate), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, l10n.entryTemplateEmpty));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.entryTitle),
      'Carta di credito',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.entryUserName),
      'titolare',
    );
    await tester.tap(find.byTooltip(l10n.entryEditSave));
    await pumpUntilFound(
      tester,
      find.widgetWithText(AppBar, 'Carta di credito'),
    );
    await tester.pumpAndSettle();
    expect(await entryOnDisk(tester, 'Carta di credito'), isNotNull);

    // Dal dettaglio si torna al gruppo, che mostra la nuova voce.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Carta di credito'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.searchTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'titolare');
    await tester.pumpAndSettle();
    expect(find.text('Carta di credito'), findsOneWidget);
    expect(find.text('Conto'), findsNothing);

    await tester.enterText(find.byType(TextField), 'nessuna');
    await tester.pumpAndSettle();
    expect(find.text(l10n.searchNoResults), findsOneWidget);
  });

  testWidgets('nome del gruppo nei risultati segue la preferenza', (
    tester,
  ) async {
    // PwEntryView: il nome del gruppo è visibile per impostazione predefinita.
    await openApp(tester);
    await tester.tap(find.byTooltip(l10n.searchTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Conto');
    await tester.pumpAndSettle();
    expect(find.text('cliente · Banca'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).last),
    );
    final settings = container.read(appSettingsProvider);
    await container
        .read(appSettingsProvider.notifier)
        .update(settings.copyWith(showGroupNameInSearch: false));
    await tester.pumpAndSettle();
    expect(find.text('cliente · Banca'), findsNothing);
    expect(find.text('cliente'), findsOneWidget);
  });

  testWidgets('sposta risultati provenienti da gruppi diversi', (tester) async {
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    final bank = db.root.groups.firstWhere((group) => group.name == 'Banca');
    db.createGroup(parent: db.root, name: 'Destinazione');
    addTestEntry(db, bank, {EntryFields.title: 'Ricerca multipla A'});
    addTestEntry(db, db.root, {EntryFields.title: 'Ricerca multipla B'});
    await tester.runAsync(() async => file.writeAsBytes(await db.save()));
    await openApp(tester);
    await tester.tap(find.byTooltip(l10n.searchTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ricerca multipla');
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Ricerca multipla A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ricerca multipla B'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.itemMoveTitle));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Prova / Destinazione'),
      ),
    );
    await pumpUntilFound(tester, find.byType(TextField));
    final reopened = (await tester.runAsync(() => reopenFile(file)))!;
    final target = reopened.root.groups.singleWhere(
      (g) => g.name == 'Destinazione',
    );
    expect(
      target.entries.map(entryTitle),
      containsAll(['Ricerca multipla A', 'Ricerca multipla B']),
    );
  });

  testWidgets('elimina più risultati provenienti da gruppi diversi', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    final bank = db.root.groups.firstWhere((group) => group.name == 'Banca');
    addTestEntry(db, bank, {EntryFields.title: 'Ricerca multipla A'});
    addTestEntry(db, db.root, {EntryFields.title: 'Ricerca multipla B'});
    await tester.runAsync(() async => file.writeAsBytes(await db.save()));
    await openApp(tester);
    await tester.tap(find.byTooltip(l10n.searchTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ricerca multipla');
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Ricerca multipla A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ricerca multipla B'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.itemsSelected(2)), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.entryDelete));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, l10n.entryDelete));
    await pumpUntilFound(tester, find.text(l10n.searchNoResults));
    final reopened = (await tester.runAsync(() => reopenFile(file)))!;
    final bin = existingRecycleBin(reopened)!;
    expect(
      bin.entries.map(entryTitle),
      containsAll(['Ricerca multipla A', 'Ricerca multipla B']),
    );
  });

  testWidgets('ricerca mostra il percorso del gruppo annidato', (tester) async {
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    final bank = db.root.groups.firstWhere((group) => group.name == 'Banca');
    final cards = db.createGroup(parent: bank, name: 'Carte');
    addTestEntry(db, cards, {
      EntryFields.title: 'Carta annidata',
      EntryFields.userName: 'titolare',
    });
    await tester.runAsync(() async => file.writeAsBytes(await db.save()));
    await openApp(tester);
    await tester.tap(find.byTooltip(l10n.searchTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Carta annidata');
    await tester.pumpAndSettle();
    expect(find.text('titolare · Banca.Carte'), findsOneWidget);
  });

  testWidgets('dettaglio mostra il titolo risolto', (tester) async {
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    final bank = db.root.groups.firstWhere((group) => group.name == 'Banca');
    addTestEntry(db, bank, {
      EntryFields.title: '{REF:U@T:Conto}',
      EntryFields.notes: 'ricerca-titolo',
    });
    await tester.runAsync(() async => file.writeAsBytes(await db.save()));
    await openApp(tester);
    await tester.tap(find.byTooltip(l10n.searchTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ricerca-titolo');
    await tester.pumpAndSettle();
    await tester.tap(find.text('cliente'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'cliente'), findsOneWidget);
  });

  testWidgets('il gruppo nel dettaglio segue la preferenza', (tester) async {
    await openApp(tester);
    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conto'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.entryGroup), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).last),
    );
    final settings = container.read(appSettingsProvider);
    await container
        .read(appSettingsProvider.notifier)
        .update(settings.copyWith(showGroupInEntry: true));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, l10n.entryGroup), findsOneWidget);
    expect(find.text('Banca'), findsOneWidget);
  });

  testWidgets('modifica e conserva l’URL sostitutivo', (tester) async {
    await openApp(tester);
    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.entryEdit));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, l10n.entryOverrideUrl);
    await tester.ensureVisible(field);
    await tester.enterText(field, 'https://example.org/override');
    await tester.tap(find.byTooltip(l10n.entryEditSave));
    await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Conto'));
    await tester.pumpAndSettle();
    expect(find.text('https://example.org/override'), findsOneWidget);
    final entry = (await entryOnDisk(tester, 'Conto'))!;
    expect(entry.overrideUrl, 'https://example.org/override');
  });

  testWidgets('ricerca avanzata: password solo quando selezionata', (
    tester,
  ) async {
    await openApp(tester);
    await tester.tap(find.byTooltip(l10n.searchTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pin-123');
    await tester.pumpAndSettle();
    expect(find.text(l10n.searchNoResults), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.searchOptions));
    await tester.pumpAndSettle();
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
      isTrue,
    );
    await tester.tap(find.text(l10n.searchFieldPassword));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Conto'), findsOneWidget);
  });

  testWidgets('modifiche non salvate: conferma prima di uscire', (
    tester,
  ) async {
    await openApp(tester);
    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.groupAddEntry));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, l10n.entryTemplateEmpty));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.entryTitle),
      'bozza',
    );
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(l10n.entryEditDiscardTitle), findsOneWidget);

    await tester.tap(find.text(l10n.entryEditDiscard));
    await tester.pumpAndSettle();
    expect(find.text('Conto'), findsOneWidget);
    expect(await entryOnDisk(tester, 'bozza'), isNull);
  });

  testWidgets('eliminazione: conferma e voce spostata nel cestino', (
    tester,
  ) async {
    await openApp(tester);
    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conto'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.entryDelete));
    await tester.pumpAndSettle();
    expect(find.text(l10n.entryDeleteConfirmRecycle), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, l10n.entryDelete));

    // Torna al gruppo, ora vuoto.
    await pumpUntilFound(tester, find.text(l10n.groupEmpty));
    await tester.pumpAndSettle();

    final db = (await tester.runAsync(() => reopenFile(file)))!;
    final entry = db.root.allEntries.singleWhere(
      (e) => entryTitle(e) == 'Conto',
    );
    expect(isInRecycleBin(db, entry), isTrue);
  });

  testWidgets('i preferiti aprono il dettaglio e si salvano nel database', (
    tester,
  ) async {
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    db.root.allEntries.single.tags = ['banca'];
    addTestEntry(db, db.recycleBin!, {
      EntryFields.title: 'Voce nel cestino',
    }).tags = [
      'Favorite',
    ];
    await tester.runAsync(() async => file.writeAsBytes(await db.save()));
    await openApp(tester);

    final favorites = find.text(l10n.favoritesTitle);
    final empty = find.text(l10n.favoritesEmpty);
    final add = find.byTooltip(l10n.entryFavoriteAdd);
    final remove = find.byTooltip(l10n.entryFavoriteRemove);
    final detail = find.widgetWithText(AppBar, 'Conto');

    await openHomeMenu(tester, l10n);
    expect(favorites, findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Voce nel cestino'), findsNothing);

    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conto'));
    await tester.pumpAndSettle();
    await tester.tap(add);
    await pumpUntilFound(tester, remove);
    expect(
      (await entryOnDisk(tester, 'Conto'))?.tags,
      unorderedEquals(['banca', 'Favorite']),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await selectHomeAction(tester, l10n, l10n.favoritesTitle);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Conto'));
    await tester.pumpAndSettle();
    expect(detail, findsOneWidget);

    await tester.tap(remove);
    await pumpUntilFound(tester, add);
    expect((await entryOnDisk(tester, 'Conto'))?.tags, ['banca']);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, l10n.favoritesTitle), findsOneWidget);
    expect(empty, findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openHomeMenu(tester, l10n);
    expect(favorites, findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('TOTP: codice nascosto, rivelato e copiato', (tester) async {
    final clipboard = FakeClipboard(tester.binding);
    await openApp(tester);
    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conto'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.entryTotp), findsOneWidget);
    expect(find.text('996554'), findsNothing);
    expect(find.text(l10n.entryTotpRemaining(1)), findsOneWidget);

    expect(find.byIcon(Icons.copy), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, l10n.entryTotp));
    await tester.pumpAndSettle();
    expect(clipboard.text, '996554');

    final totpTile = find.byType(TotpTile);
    await tester.tap(
      find.descendant(of: totpTile, matching: find.byTooltip(l10n.entryShow)),
    );
    await tester.pump();
    expect(find.text('996554'), findsOneWidget);
  });

  testWidgets('password recenti: scelta in Impostazioni e accesso dalla Home', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
    final clipboard = FakeClipboard(tester.binding);
    await openApp(tester);

    Finder tab(String label) => find.descendant(
      of: find.byType(DatabaseNavigationBar),
      matching: find.text(label),
    );
    Future<void> tap(Finder finder) async {
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    Future<void> revealSetting(Finder finder) async {
      await tester.scrollUntilVisible(finder, 250);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    final title = find.text(l10n.recentPasswordsTitle);
    final setting = find.widgetWithText(
      SwitchListTile,
      l10n.recentPasswordsTitle,
    );
    final limit = find.widgetWithText(
      ListTile,
      l10n.settingsRecentPasswordLimit,
    );
    expect(title, findsNothing);
    await tap(tab(l10n.settingsTitle));
    await revealSetting(setting);
    expect(tester.widget<SwitchListTile>(setting).value, isTrue);
    await revealSetting(limit);
    await tap(limit);
    Finder count(String value) => find.descendant(
      of: find.byType(BottomSheet),
      matching: find.widgetWithText(ListTile, value),
    );
    expect(tester.widget<ListTile>(count('5')).selected, isTrue);
    expect(count('15'), findsOneWidget);
    await tap(count('10'));
    expect(
      find.descendant(of: limit, matching: find.text('10')),
      findsOneWidget,
    );
    await tap(tab(l10n.navigationHome));

    final account = find.widgetWithText(ListTile, 'Conto');
    Future<void> copyFromAccount(String label) async {
      await tap(find.text('Banca'));
      await tap(account);
      await tap(find.widgetWithText(ListTile, label));
      await back();
      await back();
      await pumpUntilFound(tester, account);
    }

    await copyFromAccount('PIN');
    expect(clipboard.text, '9999');
    expect(title, findsOneWidget);
    expect(
      tester.getTopLeft(account).dy,
      lessThan(tester.getTopLeft(find.text('Banca')).dy),
    );
    expect(find.text('9999'), findsNothing);
    await tap(account);
    expect(find.widgetWithText(AppBar, 'Conto'), findsOneWidget);
    await back();

    await tap(tab(l10n.settingsTitle));
    await revealSetting(setting);
    await tap(setting);
    await tap(tab(l10n.navigationHome));
    expect(title, findsNothing);
    await tap(tab(l10n.settingsTitle));
    await revealSetting(setting);
    await tap(setting);
    await tap(tab(l10n.navigationHome));
    expect(account, findsOneWidget);

    await copyFromAccount(l10n.entryTotp);
    expect(clipboard.text, '996554');
    expect(title, findsOneWidget);
    expect(find.text('996554'), findsNothing);
  });

  testWidgets('generatore: valore usato come password e salvato', (
    tester,
  ) async {
    await openApp(tester);
    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.entryEdit));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.entryEditGenerate));
    await tester.pumpAndSettle();
    expect(find.text(l10n.generatorTitle), findsOneWidget);
    final generated = tester
        .widget<Text>(find.byKey(GeneratorView.valueKey))
        .data!;
    expect(generated, hasLength(12));

    await tester.tap(find.text(l10n.generatorUse));
    await tester.pumpAndSettle();
    expect(find.text(l10n.entryEditTitle), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.entryEditSave));
    await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Conto'));
    await tester.pumpAndSettle();

    final saved = await entryOnDisk(tester, 'Conto');
    expect(saved!.fields[EntryFields.password]?.text, generated);
    expect(saved.history, hasLength(1));
  });

  testWidgets(
    'riferimenti nel dettaglio: protezione, copia ed errore senza valori grezzi',
    (tester) async {
      final db = await tester.runAsync(() => reopenFile(file));
      final entry = db!.root.allEntries.first;
      entry.fields['Alias'] = PlainTextField('{PASSWORD}');
      entry.fields['Mancante'] = PlainTextField('{S:assente}');
      await tester.runAsync(() async => file.writeAsBytes(await db.save()));
      final clipboard = FakeClipboard(tester.binding);
      await openApp(tester);
      await tester.tap(find.text('Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conto'));
      await tester.pumpAndSettle();
      expect(find.text('{PASSWORD}'), findsNothing);
      expect(find.text('pin-123'), findsNothing);
      await tester.scrollUntilVisible(find.text('Alias'), 200);
      await tester.tap(find.widgetWithText(ListTile, 'Alias'));
      await tester.pumpAndSettle();
      expect(clipboard.text, 'pin-123');
      await tester.scrollUntilVisible(find.text(l10n.errorFieldReference), 200);
      final field = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Mancante'),
      );
      expect(field.onTap, isNull);
      expect(
        (await entryOnDisk(tester, 'Conto'))!.fields['Alias']!.text,
        '{PASSWORD}',
      );
    },
  );

  for (final protected in [false, true]) {
    testWidgets(
      'anteprima utente risolve REF senza esporre valori protetti ($protected)',
      (tester) async {
        final db = (await tester.runAsync(() => reopenFile(file)))!;
        final entry = db.root.allEntries.first;
        entry.fields[EntryFields.userName] = PlainTextField(
          '{REF:U@T:Origine}',
        );
        addTestEntry(db, db.root, {
          EntryFields.title: 'Origine',
          EntryFields.userName: 'utente-reference',
        }, protectedKeys: protected ? {EntryFields.userName} : {});
        await tester.runAsync(() async => file.writeAsBytes(await db.save()));
        await openApp(tester);
        await tester.tap(find.text('Banca'));
        await tester.pumpAndSettle();
        expect(find.text('Conto'), findsOneWidget);
        expect(find.text('{REF:U@T:Origine}'), findsNothing);
        expect(
          find.text('utente-reference'),
          protected ? findsNothing : findsOneWidget,
        );
      },
    );
  }
}
