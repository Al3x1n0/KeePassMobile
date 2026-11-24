import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/group/group_view.dart';
import 'package:keepass_mobile/features/favorites/favorites_view_model.dart';
import 'package:keepass_mobile/features/recent_passwords/recent_passwords_view_model.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/item_edits.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/ui/entry_tile.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_database.dart';

class _ControllableItemActions extends ItemActions {
  _ControllableItemActions(super.id);

  void setBusy(bool busy) {
    state = busy ? const AsyncLoading<void>() : const AsyncData<void>(null);
  }
}

class _CountingGroupStorage extends FileStorage {
  int writes = 0;

  @override
  Future<void> write(
    FileRef ref,
    Uint8List bytes, {
    String? expectedVersion,
  }) async {
    writes++;
    await super.write(ref, bytes, expectedVersion: expectedVersion);
  }
}

Future<void> _pumpGroup(
  WidgetTester tester,
  ProviderContainer container, {
  Locale locale = const Locale('it'),
  ThemeMode themeMode = ThemeMode.light,
  TextScaler textScaler = TextScaler.noScaling,
  String? groupId,
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
        darkTheme: buildDarkTheme(),
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child ?? const SizedBox.shrink(),
        ),
        home: GroupView(groupId: groupId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<String?> _popupLabels(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is PopupMenuItem<Object?>,
        ),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .toList();

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
        expect(tester.widget<AppBar>(find.byType(AppBar)).actions, isNull);
        expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
        expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
        await tester.longPress(find.text(group.name));
        await tester.pumpAndSettle();

        // then
        final selectAll = find.widgetWithText(
          TextButton,
          binL10n.itemsSelectAllShort,
        );
        expect(selectAll, findsOneWidget);
        expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight + 48);
        expect(
          tester
              .widget<AppBar>(find.byType(AppBar))
              .bottom!
              .preferredSize
              .height,
          48,
        );
        expect(find.byIcon(Icons.select_all), findsNothing);
        expect(find.byType(Checkbox), findsNothing);
        final more = find.byTooltip(binL10n.groupMore);
        expect(more, findsOneWidget);
        expect(find.byTooltip(binL10n.entryFavoriteAdd), findsNothing);
        expect(tester.getRect(selectAll).left, lessThan(24));
        expect(tester.getRect(selectAll).top, greaterThanOrEqualTo(56));
        expect(tester.getRect(more).right, greaterThan(336));
        expect(tester.getRect(more).top, lessThan(kToolbarHeight));
        await tester.tap(more);
        await tester.pumpAndSettle();
        expect(_popupLabels(tester), [
          binL10n.itemRestore,
          binL10n.entryDelete,
        ]);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

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
        expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
        expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);

        await tester.tap(find.text(group.name));
        await tester.pumpAndSettle();
        expect(find.text(binL10n.itemsSelected(2)), findsOneWidget);
        expect(selectAll, findsOneWidget);
        expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight + 48);
        expect(
          tester
              .widget<AppBar>(find.byType(AppBar))
              .bottom!
              .preferredSize
              .height,
          48,
        );

        await tester.tap(find.byTooltip(binL10n.cancel));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, binTitle), findsOneWidget);
        expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
        expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
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
          expect(tester.getTopLeft(find.text(group.name)).dx, AppSpacing.m);
          final normalBar = tester.widget<AppBar>(find.byType(AppBar));
          expect(normalBar.bottom, isNull);
          expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
          if (!home) {
            expect(normalBar.actions, hasLength(1));
            expect(find.byTooltip(strings.groupMore), findsOneWidget);
          }
          expect(find.text(strings.itemsSelectAllShort), findsNothing);

          // when
          await tester.longPress(find.text('Prima voce ordinaria'));
          await tester.pumpAndSettle();

          // then
          expect(
            tester.getTopLeft(find.text(strings.itemsSelected(1))).dx,
            kToolbarHeight + AppSpacing.m,
          );
          final selectAll = find.widgetWithText(
            TextButton,
            strings.itemsSelectAllShort,
          );
          final more = find.byTooltip(strings.groupMore);
          final favorite = find.byTooltip(strings.entryFavoriteAdd);
          expect(selectAll, findsOneWidget);
          expect(
            tester.getSize(find.byType(AppBar)).height,
            kToolbarHeight + 48,
          );
          expect(
            tester
                .widget<AppBar>(find.byType(AppBar))
                .bottom!
                .preferredSize
                .height,
            48,
          );
          expect(find.byIcon(Icons.select_all), findsNothing);
          expect(find.byType(Checkbox), findsNothing);
          expect(tester.getRect(selectAll).left, lessThan(24));
          expect(tester.getRect(selectAll).top, greaterThanOrEqualTo(56));
          expect(tester.getRect(more).top, lessThan(kToolbarHeight));
          expect(tester.getRect(more).right, greaterThan(336));
          expect(
            tester.getRect(more).left - tester.getRect(favorite).right,
            inInclusiveRange(0, AppSpacing.s),
          );
          await tester.tap(selectAll);
          await tester.pumpAndSettle();
          expect(selectAll, findsNothing);
          expect(find.text(strings.itemsSelected(3)), findsOneWidget);
          expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
          expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
          expect(favorite, findsNothing);
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
          expect(
            tester.getSize(find.byType(AppBar)).height,
            kToolbarHeight + 48,
          );
          expect(
            tester
                .widget<AppBar>(find.byType(AppBar))
                .bottom!
                .preferredSize
                .height,
            48,
          );
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

  for (final locale in [const Locale('it'), const Locale('en')]) {
    for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'Home ${locale.languageCode} ${themeMode.name}: titolo mono-riga e menu continuo sotto i puntini',
        (tester) async {
          // given
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final strings = lookupAppLocalizations(locale);
          final db = newTestDatabase();
          db.root.name = 'Archivio con un titolo molto lungo che deve terminare con ellissi';
          addTestEntry(db, db.root, {
            EntryFields.title: 'Preferita attiva',
          }).tags = [
            'Favorite',
          ];
          addTestEntry(db, db.recycleBin!, {
            EntryFields.title: 'Voce eliminata',
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
          await _pumpGroup(
            tester,
            container,
            locale: locale,
            themeMode: themeMode,
          );

          // then: il titolo usa lo spazio disponibile senza toccare Cerca.
          final appBar = find.byType(AppBar);
          final bar = tester.widget<AppBar>(appBar);
          expect(bar.bottom, isNull);
          expect(bar.toolbarHeight, isNull);
          expect(
            tester
                .widget<NavigationToolbar>(find.byType(NavigationToolbar))
                .centerMiddle,
            isFalse,
          );
          expect(tester.getSize(appBar).height, kToolbarHeight);
          final title = find.text(db.root.name);
          final text = tester.widget<Text>(title);
          expect(text.maxLines, 1);
          expect(text.overflow, TextOverflow.ellipsis);
          final search = find.byTooltip(strings.searchTitle);
          final more = find.byTooltip(strings.groupMore);
          expect(bar.actions, hasLength(2));
          expect(
            tester.getRect(search).right,
            lessThanOrEqualTo(tester.getRect(more).left),
          );
          expect(
            tester.getRect(title).right,
            lessThanOrEqualTo(tester.getRect(search).left - AppSpacing.s),
          );
          expect(tester.getCenter(search).dy, tester.getCenter(more).dy);

          // when
          await tester.tap(more);
          await tester.pumpAndSettle();

          // then: tutte le righe sono contigue, senza separatori.
          final labels = [
            strings.favoritesTitle,
            strings.groupSort,
            strings.databasesTitle,
            strings.syncNow,
            strings.dbSettingsRecycleBin,
            strings.groupLock,
          ];
          final icons = [
            Icons.star_border,
            Icons.sort,
            Icons.folder_copy_outlined,
            Icons.sync,
            Icons.delete_outline,
            Icons.lock_outline,
          ];
          final entries = [
            for (final label in labels)
              find.ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate(
                  (widget) => widget is PopupMenuItem<Object?>,
                ),
              ),
          ];
          expect(
            find.byWidgetPredicate(
              (widget) => widget is PopupMenuItem<Object?>,
            ),
            findsNWidgets(labels.length),
          );
          expect(find.byType(PopupMenuDivider), findsNothing);
          for (var index = 0; index < entries.length; index++) {
            final entry = entries[index];
            expect(entry, findsOneWidget);
            expect(
              tester.widget<PopupMenuItem<Object?>>(entry).enabled,
              isTrue,
            );
            final icon = find.descendant(
              of: entry,
              matching: find.byIcon(icons[index]),
            );
            expect(icon, findsOneWidget);
            expect(
              tester.getRect(icon).right,
              lessThan(tester.getRect(find.text(labels[index])).left),
            );
            if (index > 0) {
              expect(
                tester.getRect(entry).top,
                tester.getRect(entries[index - 1]).bottom,
              );
            }
          }
          expect(
            tester.getRect(entries.first).top,
            greaterThanOrEqualTo(tester.getRect(more).bottom),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Home con testo ingrandito: barra standard e popup senza overflow',
    (tester) async {
      // given
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = newTestDatabase();
      db.root.name = 'Archivio dal titolo molto lungo';
      addTestEntry(db, db.root, {EntryFields.title: 'Preferita attiva'}).tags =
          ['Favorite'];
      addTestEntry(db, db.recycleBin!, {EntryFields.title: 'Voce eliminata'});
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
      await _pumpGroup(tester, container, textScaler: TextScaler.linear(2));
      expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
      expect(tester.takeException(), isNull);

      // when
      await tester.tap(find.byTooltip(l10n.groupMore));
      await tester.pumpAndSettle();

      // then
      expect(
        find.byWidgetPredicate((widget) => widget is PopupMenuItem<Object?>),
        findsNWidgets(6),
      );
      expect(find.text(l10n.groupLock), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home occupata: disabilita solo database aperti e sincronizzazione',
    (tester) async {
      // given
      final db = newTestDatabase();
      addTestEntry(db, db.root, {EntryFields.title: 'Preferita attiva'}).tags =
          ['Favorite'];
      addTestEntry(db, db.recycleBin!, {EntryFields.title: 'Voce eliminata'});
      final rootId = itemIdOf(db.root);
      final actions = _ControllableItemActions(rootId);
      final container = await newTestContainer(
        overrides: [itemActionsProvider(rootId).overrideWith(() => actions)],
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
      await _pumpGroup(tester, container);
      actions.setBusy(true);
      await tester.pump();

      // when
      await tester.tap(find.byTooltip(l10n.groupMore));
      await tester.pumpAndSettle();

      // then
      for (final (label, enabled) in [
        (l10n.favoritesTitle, true),
        (l10n.groupSort, true),
        (l10n.databasesTitle, false),
        (l10n.syncNow, false),
        (l10n.dbSettingsRecycleBin, true),
        (l10n.groupLock, true),
      ]) {
        final item = find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate(
            (widget) => widget is PopupMenuItem<Object?>,
          ),
        );
        expect(tester.widget<PopupMenuItem<Object?>>(item).enabled, enabled);
      }
      await tester.tap(find.text(l10n.databasesTitle));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((widget) => widget is PopupMenuItem<Object?>),
        findsNWidgets(6),
      );
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.text(l10n.syncNow));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((widget) => widget is PopupMenuItem<Object?>),
        findsNWidgets(6),
      );
      actions.setBusy(false);
    },
  );

  testWidgets(
    'Home non mostra Preferiti quando la sola voce preferita è nel Cestino',
    (tester) async {
      // given
      final db = newTestDatabase();
      addTestEntry(db, db.recycleBin!, {
        EntryFields.title: 'Preferita eliminata',
      }).tags = [
        'Favorite',
      ];
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
      await _pumpGroup(tester, container);

      // when
      await tester.tap(find.byTooltip(l10n.groupMore));
      await tester.pumpAndSettle();

      // then
      expect(find.text(l10n.favoritesTitle), findsNothing);
      expect(find.text(l10n.dbSettingsRecycleBin), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) => widget is PopupMenuItem<Object?>),
        findsNWidgets(5),
      );
    },
  );

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
        tester
            .widget<RotationTransition>(
              find.descendant(
                of: panel,
                matching: find.byType(RotationTransition),
              ),
            )
            .turns
            .value,
        0.5,
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

  for (final location in ['ordinario', 'nel Cestino', 'radice Cestino']) {
    testWidgets('gruppo $location: menu contestuale fuori selezione', (
      tester,
    ) async {
      final db = newTestDatabase();
      final group = location == 'radice Cestino'
          ? db.recycleBin!
          : db.createGroup(
              parent: location == 'ordinario' ? db.root : db.recycleBin!,
              name: 'Gruppo di prova',
            );
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
      await _pumpGroup(tester, container, groupId: itemIdOf(group));
      expect(find.byTooltip(l10n.entryFavoriteAdd), findsNothing);
      expect(find.byTooltip(l10n.entryFavoriteRemove), findsNothing);
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.bottom, isNull);
      if (location == 'radice Cestino') {
        expect(bar.actions, isNull);
        expect(find.byTooltip(l10n.groupMore), findsNothing);
      } else {
        expect(bar.actions, hasLength(1));
        await tester.tap(find.byTooltip(l10n.groupMore));
        await tester.pumpAndSettle();
        expect(
          _popupLabels(tester),
          location == 'ordinario'
              ? [l10n.entryEdit, l10n.itemMoveTitle, l10n.entryDelete]
              : [l10n.itemRestore, l10n.entryDelete],
        );
        expect(find.text(l10n.itemDuplicate), findsNothing);
      }
    });
  }

  testWidgets('selezione gruppo, voce e mista: menu e stella si adattano', (
    tester,
  ) async {
    final db = newTestDatabase();
    final child = db.createGroup(parent: db.root, name: 'Gruppo figlio');
    addTestEntry(db, db.root, {EntryFields.title: 'Voce di prova'});
    final container = await newTestContainer();
    container
        .read(databaseSessionProvider.notifier)
        .open(
          DatabaseSession(
            file: const FileRef(uri: 'file:///prova.kdbx', name: 'prova.kdbx'),
            database: db,
          ),
        );
    await _pumpGroup(tester, container);
    await tester.longPress(find.text(child.name));
    await tester.pumpAndSettle();
    expect(find.byTooltip(l10n.entryFavoriteAdd), findsNothing);
    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pumpAndSettle();
    expect(_popupLabels(tester), [
      l10n.entryEdit,
      l10n.itemMoveTitle,
      l10n.entryDelete,
    ]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voce di prova'));
    await tester.pumpAndSettle();
    expect(find.byTooltip(l10n.entryFavoriteAdd), findsNothing);
    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pumpAndSettle();
    expect(_popupLabels(tester), [l10n.itemMoveTitle, l10n.entryDelete]);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text(child.name));
    await tester.pumpAndSettle();
    expect(find.byTooltip(l10n.entryFavoriteAdd), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pumpAndSettle();
    expect(_popupLabels(tester), [
      l10n.entryEdit,
      l10n.itemMoveTitle,
      l10n.itemDuplicate,
      l10n.entryDelete,
    ]);
    expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.file_copy_outlined), findsNothing);
  });

  testWidgets(
    'selezione con altri database: copia e sposta solo fuori Cestino',
    (tester) async {
      final db = newTestDatabase();
      addTestEntry(db, db.recycleBin!, {EntryFields.title: 'Voce eliminata'});
      final child = db.createGroup(parent: db.root, name: 'Gruppo figlio');
      final container = await newTestContainer();
      final sessions = container.read(databaseSessionProvider.notifier);
      const source = FileRef(uri: 'file:///prova.kdbx', name: 'prova.kdbx');
      sessions.open(DatabaseSession(file: source, database: db));
      sessions.openAdditional(
        DatabaseSession(
          file: const FileRef(uri: 'file:///altro.kdbx', name: 'altro.kdbx'),
          database: newTestDatabase(),
        ),
        sessions.lockGeneration,
      );
      sessions.switchTo(source);
      await _pumpGroup(tester, container);
      await tester.longPress(find.text(child.name));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.groupMore));
      await tester.pumpAndSettle();
      expect(_popupLabels(tester), [
        l10n.entryEdit,
        l10n.itemMoveTitle,
        l10n.entryDelete,
        l10n.databasesCopy,
        l10n.databasesMove,
      ]);
      expect(find.byIcon(Icons.file_copy_outlined), findsOneWidget);
      expect(find.text(l10n.itemDuplicate), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpGroup(tester, container, groupId: itemIdOf(db.recycleBin!));
      await tester.longPress(find.text('Voce eliminata'));
      await tester.pumpAndSettle();
      expect(find.byTooltip(l10n.entryFavoriteAdd), findsNothing);
      await tester.tap(find.byTooltip(l10n.groupMore));
      await tester.pumpAndSettle();
      expect(_popupLabels(tester), [l10n.itemRestore, l10n.entryDelete]);
    },
  );

  testWidgets(
    'selezione stretta al 200%: titolo ellittico e azioni accessibili',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = newTestDatabase();
      addTestEntry(db, db.root, {EntryFields.title: 'Voce di prova'});
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
      await _pumpGroup(
        tester,
        container,
        textScaler: const TextScaler.linear(2),
      );
      await tester.longPress(find.text('Voce di prova'));
      await tester.pumpAndSettle();
      final title = tester.widget<Text>(find.text(l10n.itemsSelected(1)));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
      expect(tester.widget<AppBar>(find.byType(AppBar)).bottom, isNull);
      expect(find.text(l10n.itemsSelectAllShort), findsNothing);
      final star = find.ancestor(
        of: find.byTooltip(l10n.entryFavoriteAdd),
        matching: find.byType(IconButton),
      );
      final popup = find.byWidgetPredicate(
        (widget) => widget is PopupMenuButton,
      );
      expect(tester.getSize(star).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(popup).width, greaterThanOrEqualTo(48));
      expect(tester.getRect(popup).right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selezione occupata: disabilita stella popup seleziona tutti e lista',
    (tester) async {
      final db = newTestDatabase();
      addTestEntry(db, db.root, {EntryFields.title: 'Voce A'});
      addTestEntry(db, db.root, {EntryFields.title: 'Voce B'});
      final rootId = itemIdOf(db.root);
      final actions = _ControllableItemActions(rootId);
      final container = await newTestContainer(
        overrides: [itemActionsProvider(rootId).overrideWith(() => actions)],
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
      await _pumpGroup(tester, container);
      await tester.longPress(find.text('Voce A'));
      await tester.pumpAndSettle();
      actions.setBusy(true);
      await tester.pump();
      final favorite = find.ancestor(
        of: find.byTooltip(l10n.entryFavoriteAdd),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(favorite).onPressed, isNull);
      final popup = find.byWidgetPredicate(
        (widget) => widget is PopupMenuButton,
      );
      expect(tester.widget<PopupMenuButton>(popup).enabled, isFalse);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, l10n.itemsSelectAllShort),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Voce B'));
      await tester.pump();
      expect(find.text(l10n.itemsSelected(1)), findsOneWidget);
      actions.setBusy(false);
      await tester.pump();
      expect(tester.widget<IconButton>(favorite).onPressed, isNotNull);
      expect(tester.widget<PopupMenuButton>(popup).enabled, isTrue);
    },
  );

  testWidgets(
    'voce selezionata: duplica nel gruppo corrente e chiude selezione',
    (tester) async {
      final db = newTestDatabase();
      final group = db.createGroup(parent: db.root, name: 'Gruppo origine');
      addTestEntry(db, group, {EntryFields.title: 'Voce originale'});
      final saved = await tester.runAsync(() => saveToTempFile(db));
      final (file, reopened) = saved!;
      addTearDown(() => file.parent.deleteSync(recursive: true));
      final container = await newTestContainer(file: file, database: reopened);
      await _pumpGroup(tester, container, groupId: itemIdOf(group));
      await tester.longPress(find.text('Voce originale'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.groupMore));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.itemDuplicate));
      await pumpUntilFound(
        tester,
        find.text('Voce originale - ${l10n.itemDuplicateSuffix}'),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.itemsSelected(1)), findsNothing);
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).title,
        isA<Text>().having((text) => text.data, 'titolo', group.name),
      );
      final written = await tester.runAsync(() => reopenFile(file));
      expect(findGroup(written!, itemIdOf(group))!.entries, hasLength(2));
    },
  );

  testWidgets(
    'selezione voci: aggiunge e rimuove preferiti con un salvataggio',
    (tester) async {
      final db = newTestDatabase();
      addTestEntry(db, db.root, {EntryFields.title: 'Voce A'}).tags = [
        'Favorite',
      ];
      addTestEntry(db, db.root, {EntryFields.title: 'Voce B'});
      final saved = await tester.runAsync(() => saveToTempFile(db));
      final (file, reopened) = saved!;
      addTearDown(() => file.parent.deleteSync(recursive: true));
      final storage = _CountingGroupStorage();
      final container = await newTestContainer(
        file: file,
        database: reopened,
        overrides: [fileStorageProvider.overrideWithValue(storage)],
      );
      await _pumpGroup(tester, container);
      await tester.longPress(find.text('Voce A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.itemsSelectAllShort));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.entryFavoriteAdd));
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
    },
  );
}
