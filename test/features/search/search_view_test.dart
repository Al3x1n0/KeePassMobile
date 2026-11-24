import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/features/favorites/favorites_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/search/search_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/ui/action_popup_menu.dart';
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
  bool disableAnimations = false,
  TextScaler textScaler = TextScaler.noScaling,
  GoRouter? router,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: router == null
          ? MaterialApp(
              locale: locale,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations: disableAnimations,
                  textScaler: textScaler,
                ),
                child: child!,
              ),
              localizationsDelegates: [
                ...GlobalMaterialLocalizations.delegates,
                ...AppLocalizations.localizationsDelegates,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildLightTheme(),
              home: const SearchView(),
            )
          : MaterialApp.router(
              routerConfig: router,
              locale: locale,
              localizationsDelegates: [
                ...GlobalMaterialLocalizations.delegates,
                ...AppLocalizations.localizationsDelegates,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildLightTheme(),
            ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), 'Voce');
  await tester.pumpAndSettle();
}

class _CountingStorage extends FileStorage {
  int writes = 0;
  Completer<void>? writeGate;

  @override
  Future<void> write(
    FileRef ref,
    Uint8List bytes, {
    String? expectedVersion,
  }) async {
    writes++;
    await writeGate?.future;
    await super.write(ref, bytes, expectedVersion: expectedVersion);
  }
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
        expect(find.byIcon(Icons.select_all), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        expect(tester.getRect(selectAll).left, lessThan(24));
        expect(tester.getRect(selectAll).top, greaterThanOrEqualTo(56));
        expect(
          tester.getRect(find.byTooltip(l10n.groupMore)).right,
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
        expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
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

  testWidgets('ricerca: menu contestuale singolo e multiplo in riga 1', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('it'));
    final db = newTestDatabase();
    addTestEntry(db, db.root, {EntryFields.title: 'Voce A'});
    addTestEntry(db, db.root, {EntryFields.title: 'Voce B'});
    final container = await newTestContainer();
    final sessions = container.read(databaseSessionProvider.notifier);
    sessions.open(DatabaseSession(file: _firstFile, database: db));
    sessions.openAdditional(
      DatabaseSession(file: _secondFile, database: newTestDatabase()),
      sessions.lockGeneration,
    );
    sessions.switchTo(_firstFile);
    await _pumpSearch(tester, container);
    await tester.longPress(find.text('Voce A'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((widget) => widget is ActionPopupMenu),
      findsOneWidget,
    );
    final favorite = find.byTooltip(l10n.entryFavoriteAdd);
    final more = find.byTooltip(l10n.groupMore);
    expect(tester.getRect(favorite).top, lessThan(kToolbarHeight));
    expect(
      tester.getRect(more).left - tester.getRect(favorite).right,
      inInclusiveRange(0, AppSpacing.s),
    );
    expect(find.byTooltip(l10n.entryEdit), findsNothing);
    expect(find.byTooltip(l10n.entryDelete), findsNothing);
    await tester.tap(more);
    await tester.pumpAndSettle();
    final labels = tester
        .widgetList<PopupMenuItem>(
          find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        )
        .map(
          (item) =>
              (item.child! as Row).children.whereType<Flexible>().single.child
                  as Text,
        )
        .map((text) => text.data)
        .toList();
    expect(labels, [
      l10n.entryEdit,
      l10n.itemMoveTitle,
      l10n.itemDuplicate,
      l10n.entryDelete,
      l10n.searchGoToGroup,
      l10n.databasesCopy,
      l10n.databasesMove,
    ]);
    expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.file_copy_outlined), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Voce B'));
    await tester.pumpAndSettle();
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text(l10n.entryEdit), findsNothing);
    expect(find.text(l10n.itemDuplicate), findsNothing);
    expect(find.text(l10n.searchGoToGroup), findsNothing);
    expect(find.text(l10n.itemMoveTitle), findsOneWidget);
    expect(find.text(l10n.entryDelete), findsOneWidget);
    expect(find.text(l10n.databasesCopy), findsOneWidget);
    expect(find.text(l10n.databasesMove), findsOneWidget);
  });

  testWidgets(
    'ricerca: collasso ed espansione muovono il contenuto con AppBar',
    (tester) async {
      final l10n = lookupAppLocalizations(const Locale('it'));
      final db = newTestDatabase();
      addTestEntry(db, db.root, {EntryFields.title: 'Voce A'});
      addTestEntry(db, db.root, {EntryFields.title: 'Voce B'});
      final container = await newTestContainer();
      container
          .read(databaseSessionProvider.notifier)
          .open(DatabaseSession(file: _firstFile, database: db));
      await _pumpSearch(tester, container);
      await tester.longPress(find.text('Voce A'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.itemsSelectAllShort));
      await tester.pump();
      expect(tester.getSize(find.byType(AppBar)).height, 104);
      await tester.pump(const Duration(milliseconds: 80));
      final collapsing = tester.getSize(find.byType(AppBar)).height;
      expect(collapsing, allOf(greaterThan(56), lessThan(104)));
      expect(tester.getTopLeft(find.byType(ListView)).dy, collapsing);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppBar)).height, 56);

      await tester.tap(find.text('Voce B'));
      await tester.pump();
      expect(tester.getSize(find.byType(AppBar)).height, 56);
      await tester.pump(const Duration(milliseconds: 80));
      final expanding = tester.getSize(find.byType(AppBar)).height;
      expect(expanding, allOf(greaterThan(56), lessThan(104)));
      expect(tester.getTopLeft(find.byType(ListView)).dy, expanding);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(AppBar)).height, 104);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ricerca: unica voce e animazioni disabilitate senza seconda riga',
    (tester) async {
      final l10n = lookupAppLocalizations(const Locale('it'));
      final db = newTestDatabase();
      addTestEntry(db, db.root, {EntryFields.title: 'Voce A'});
      final container = await newTestContainer();
      container
          .read(databaseSessionProvider.notifier)
          .open(DatabaseSession(file: _firstFile, database: db));
      await _pumpSearch(tester, container, disableAnimations: true);
      await tester.longPress(find.text('Voce A'));
      await tester.pump();
      expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
      expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
      expect(find.text(l10n.itemsSelectAllShort), findsNothing);
    },
  );

  testWidgets(
    'ricerca: con animazioni disabilitate la riga cambia subito altezza',
    (tester) async {
      final l10n = lookupAppLocalizations(const Locale('it'));
      final db = newTestDatabase();
      addTestEntry(db, db.root, {EntryFields.title: 'Voce A'});
      addTestEntry(db, db.root, {EntryFields.title: 'Voce B'});
      final container = await newTestContainer();
      container
          .read(databaseSessionProvider.notifier)
          .open(DatabaseSession(file: _firstFile, database: db));
      await _pumpSearch(tester, container, disableAnimations: true);
      await tester.longPress(find.text('Voce A'));
      await tester.pump();
      expect(tester.getSize(find.byType(AppBar)).height, 104);
      await tester.tap(find.text(l10n.itemsSelectAllShort));
      await tester.pump();
      expect(tester.getSize(find.byType(AppBar)).height, 56);
      await tester.tap(find.text('Voce B'));
      await tester.pump();
      expect(tester.getSize(find.byType(AppBar)).height, 104);
    },
  );

  testWidgets(
    'ricerca: titolo ellittico su schermo stretto con testo al 200%',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final l10n = lookupAppLocalizations(const Locale('it'));
      final db = newTestDatabase();
      addTestEntry(db, db.root, {EntryFields.title: 'Voce A'});
      final container = await newTestContainer();
      container
          .read(databaseSessionProvider.notifier)
          .open(DatabaseSession(file: _firstFile, database: db));
      await _pumpSearch(
        tester,
        container,
        textScaler: const TextScaler.linear(2),
      );
      await tester.longPress(find.text('Voce A'));
      await tester.pumpAndSettle();
      final title = tester.widget<Text>(find.text(l10n.itemsSelected(1)));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      final favorite = tester.getRect(
        find.ancestor(
          of: find.byTooltip(l10n.entryFavoriteAdd),
          matching: find.byType(IconButton),
        ),
      );
      final popup = tester.getRect(
        find.byWidgetPredicate((widget) => widget is PopupMenuButton),
      );
      expect(favorite.width, greaterThanOrEqualTo(48));
      expect(popup.width, greaterThanOrEqualTo(48));
      expect(popup.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ricerca: duplica nel gruppo originale e termina la selezione', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('it'));
    final db = newTestDatabase();
    final group = db.createGroup(parent: db.root, name: 'Gruppo origine');
    final original = addTestEntry(db, group, {EntryFields.title: 'Voce A'});
    final (file, reopened) = await tester
        .runAsync(() => saveToTempFile(db))
        .then((value) => value!);
    addTearDown(() => file.parent.deleteSync(recursive: true));
    final container = await newTestContainer(file: file, database: reopened);
    await _pumpSearch(tester, container);
    await tester.longPress(find.text('Voce A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.itemDuplicate));
    await pumpUntilFound(tester, find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('Voce A - ${l10n.itemDuplicateSuffix}'), findsOneWidget);
    final saved = await tester.runAsync(() => reopenFile(file));
    final entries = findGroup(saved!, itemIdOf(group))!.entries;
    expect(entries, hasLength(2));
    expect(entries.map(itemIdOf), contains(itemIdOf(original)));
    expect(entries.map((entry) => entryTitle(entry)), [
      'Voce A',
      'Voce A - ${l10n.itemDuplicateSuffix}',
    ]);
    expect(find.text(l10n.itemsSelected(1)), findsNothing);
  });

  testWidgets('ricerca: preferiti di tutte le voci in un salvataggio e busy', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('it'));
    final db = newTestDatabase();
    addTestEntry(db, db.root, {EntryFields.title: 'Voce A'}).tags = [
      'Favorite',
    ];
    addTestEntry(db, db.root, {EntryFields.title: 'Voce B'});
    final (file, reopened) = await tester
        .runAsync(() => saveToTempFile(db))
        .then((value) => value!);
    addTearDown(() => file.parent.deleteSync(recursive: true));
    final storage = _CountingStorage()..writeGate = Completer<void>();
    final container = await newTestContainer(
      file: file,
      database: reopened,
      overrides: [fileStorageProvider.overrideWithValue(storage)],
    );
    await _pumpSearch(tester, container);
    await tester.longPress(find.text('Voce A'));
    await tester.pumpAndSettle();
    expect(find.byTooltip(l10n.entryFavoriteRemove), findsOneWidget);
    await tester.tap(find.text(l10n.itemsSelectAllShort));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.entryFavoriteAdd));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip(l10n.entryFavoriteAdd),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip(l10n.cancel),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PopupMenuButton>(
            find.byWidgetPredicate((widget) => widget is PopupMenuButton),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('Voce B'));
    await tester.pump();
    expect(find.text(l10n.itemsSelected(2)), findsOneWidget);
    storage.writeGate!.complete();
    await pumpUntilFound(tester, find.byTooltip(l10n.entryFavoriteRemove));
    await tester.pumpAndSettle();
    expect(storage.writes, 1);
    final added = await tester.runAsync(() => reopenFile(file));
    expect(added!.root.entries.every(isEntryFavorite), isTrue);
    await tester.tap(find.byTooltip(l10n.entryFavoriteRemove));
    await pumpUntilFound(tester, find.byTooltip(l10n.entryFavoriteAdd));
    await tester.pumpAndSettle();
    expect(storage.writes, 2);
    final removed = await tester.runAsync(() => reopenFile(file));
    expect(removed!.root.entries.any(isEntryFavorite), isFalse);
  });

  testWidgets('ricerca: modifica singola apre editor dal popup', (
    tester,
  ) async {
    final l10n = lookupAppLocalizations(const Locale('it'));
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce A'});
    final container = await newTestContainer();
    container
        .read(databaseSessionProvider.notifier)
        .open(DatabaseSession(file: _firstFile, database: db));
    final router = GoRouter(
      initialLocation: AppRoutes.search,
      routes: [
        GoRoute(path: AppRoutes.search, builder: (_, _) => const SearchView()),
        GoRoute(
          path: AppRoutes.entryEdit(itemIdOf(entry)),
          builder: (_, _) => const Scaffold(body: Text('Editor voce')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpSearch(tester, container, router: router);
    await tester.longPress(find.text('Voce A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.entryEdit));
    await tester.pumpAndSettle();
    expect(find.text('Editor voce'), findsOneWidget);
  });
}
