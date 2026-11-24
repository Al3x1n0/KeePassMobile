import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/entry/entry_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/item_edits.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/ui/entry_color.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_database.dart';

class _ControllableItemActions extends ItemActions {
  _ControllableItemActions(super.id);

  void setBusy(bool busy) {
    state = busy ? const AsyncLoading<void>() : const AsyncData<void>(null);
  }
}

Future<void> _pumpEntry(
  WidgetTester tester,
  ProviderContainer container,
  String entryId, {
  Locale locale = const Locale('it'),
  bool dark = false,
  int? historyIndex,
  GoRouter? router,
}) async {
  final theme = dark ? buildDarkTheme() : buildLightTheme();
  final delegates = [
    ...GlobalMaterialLocalizations.delegates,
    ...AppLocalizations.localizationsDelegates,
  ];
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: router == null
          ? MaterialApp(
              locale: locale,
              localizationsDelegates: delegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: theme,
              home: EntryView(entryId: entryId, historyIndex: historyIndex),
            )
          : MaterialApp.router(
              locale: locale,
              localizationsDelegates: delegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: theme,
              routerConfig: router,
            ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const locale = Locale('it');
  final l10n = lookupAppLocalizations(locale);

  for (final menuLocale in [const Locale('it'), const Locale('en')]) {
    for (final inBin in [false, true]) {
      testWidgets(
        'menu dettaglio ${menuLocale.languageCode}: azioni contestuali nel popup (cestino $inBin)',
        (tester) async {
          final db = newTestDatabase();
          final parent = inBin ? db.recycleBin! : db.root;
          final entry = addTestEntry(db, parent, {
            EntryFields.title: 'Voce di prova',
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
          await _pumpEntry(
            tester,
            container,
            itemIdOf(entry),
            locale: menuLocale,
            dark: inBin,
          );
          final menuL10n = lookupAppLocalizations(menuLocale);
          final actions = tester.widget<AppBar>(find.byType(AppBar)).actions!;
          expect(actions, hasLength(inBin ? 1 : 2));
          expect(
            find.byTooltip(menuL10n.entryFavoriteAdd),
            inBin ? findsNothing : findsOneWidget,
          );
          expect(find.byIcon(Icons.edit_outlined), findsNothing);
          expect(find.byIcon(Icons.delete_outline), findsNothing);
          if (!inBin) {
            expect(
              tester.getCenter(find.byTooltip(menuL10n.entryFavoriteAdd)).dx,
              lessThan(tester.getCenter(find.byTooltip(menuL10n.groupMore)).dx),
            );
          }

          await tester.tap(find.byTooltip(menuL10n.groupMore));
          await tester.pumpAndSettle();
          final rows = find.byWidgetPredicate(
            (widget) => widget is PopupMenuItem,
          );
          final expected = inBin
              ? [
                  (menuL10n.itemRestore, Icons.restore),
                  (menuL10n.entryDelete, Icons.delete_outline),
                ]
              : [
                  (menuL10n.entryEdit, Icons.edit_outlined),
                  (menuL10n.itemMoveTitle, Icons.drive_file_move_outline),
                  (menuL10n.itemDuplicate, Icons.content_copy_outlined),
                  (menuL10n.entryDelete, Icons.delete_outline),
                ];
          expect(rows, findsNWidgets(expected.length));
          for (final (index, (label, icon)) in expected.indexed) {
            expect(
              find.descendant(of: rows.at(index), matching: find.text(label)),
              findsOneWidget,
            );
            expect(
              find.descendant(of: rows.at(index), matching: find.byIcon(icon)),
              findsOneWidget,
            );
          }
          expect(find.byIcon(Icons.file_copy_outlined), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Modifica dal popup apre l’editor della voce', (tester) async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
    final id = itemIdOf(entry);
    final container = await newTestContainer();
    container
        .read(databaseSessionProvider.notifier)
        .open(
          DatabaseSession(
            file: const FileRef(uri: 'file:///prova.kdbx', name: 'prova.kdbx'),
            database: db,
          ),
        );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => EntryView(entryId: id),
        ),
        GoRoute(
          path: AppRoutes.entryEdit(id),
          builder: (_, _) => const Scaffold(body: Text('Editor voce di prova')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await _pumpEntry(tester, container, id, router: router);

    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.entryEdit));
    await tester.pumpAndSettle();

    expect(find.text('Editor voce di prova'), findsOneWidget);
    expect(
      GoRouterState.of(tester.element(find.text('Editor voce di prova')))
          .uri
          .path,
      AppRoutes.entryEdit(id),
    );
  });

  testWidgets('Elimina dal popup richiede la conferma contestuale', (
    tester,
  ) async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
    final container = await newTestContainer();
    container
        .read(databaseSessionProvider.notifier)
        .open(
          DatabaseSession(
            file: const FileRef(uri: 'file:///prova.kdbx', name: 'prova.kdbx'),
            database: db,
          ),
        );
    await _pumpEntry(tester, container, itemIdOf(entry));

    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.entryDelete));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(l10n.entryDeleteConfirmRecycle), findsOneWidget);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('busy disabilita stella e popup, poi ripristina le azioni', (
    tester,
  ) async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
    final id = itemIdOf(entry);
    final actions = _ControllableItemActions(id);
    final container = await newTestContainer(
      overrides: [itemActionsProvider(id).overrideWith(() => actions)],
    );
    container
        .read(databaseSessionProvider.notifier)
        .open(
          DatabaseSession(
            file: const FileRef(uri: 'file:///prova.kdbx', name: 'prova.kdbx'),
            database: db,
          ),
        );
    await _pumpEntry(tester, container, id);

    actions.setBusy(true);
    await tester.pump();
    final favoriteButton = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton && widget.tooltip == l10n.entryFavoriteAdd,
    );
    final favorite = tester.widget<IconButton>(favoriteButton);
    expect(favorite.onPressed, isNull);
    final popup = tester.widget<PopupMenuButton>(
      find.byWidgetPredicate((widget) => widget is PopupMenuButton),
    );
    expect(popup.enabled, isFalse);
    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pump();
    expect(
      find.byWidgetPredicate((widget) => widget is PopupMenuItem),
      findsNothing,
    );

    actions.setBusy(false);
    await tester.pump();
    expect(tester.widget<IconButton>(favoriteButton).onPressed, isNotNull);
    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pumpAndSettle();
    expect(find.text(l10n.itemDuplicate), findsOneWidget);
  });

  testWidgets('la cronologia conserva solo Ripristina ed Elimina versione', (
    tester,
  ) async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
    entry.pushHistory();
    final container = await newTestContainer();
    container
        .read(databaseSessionProvider.notifier)
        .open(
          DatabaseSession(
            file: const FileRef(uri: 'file:///prova.kdbx', name: 'prova.kdbx'),
            database: db,
          ),
        );
    await _pumpEntry(tester, container, itemIdOf(entry), historyIndex: 0);

    expect(tester.widget<AppBar>(find.byType(AppBar)).actions, hasLength(2));
    expect(find.byTooltip(l10n.entryHistoryRestore), findsOneWidget);
    expect(find.byTooltip(l10n.entryHistoryDelete), findsOneWidget);
    expect(find.byTooltip(l10n.groupMore), findsNothing);
    expect(find.byTooltip(l10n.entryFavoriteAdd), findsNothing);
  });

  for (final dark in [false, true]) {
    for (final history in [false, true]) {
      testWidgets(
        'colore adattato accessibile nel dettaglio ($dark, cronologia $history)',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final db = newTestDatabase();
            final entry = addTestEntry(db, db.root, {
              EntryFields.title: 'Voce di prova',
            })..background = '#FFCDD2';
            entry.pushHistory();
            entry.background = '#D0EAD0';
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
                  locale: locale,
                  localizationsDelegates: [
                    ...GlobalMaterialLocalizations.delegates,
                    ...AppLocalizations.localizationsDelegates,
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: dark ? buildDarkTheme() : buildLightTheme(),
                  home: EntryView(
                    entryId: itemIdOf(entry),
                    historyIndex: history ? 0 : null,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final color = history ? EntryColor.red : EntryColor.green;
            final label = l10n.entryColorIndicator(color.label(l10n));
            expect(
              find.byWidgetPredicate(
                (widget) => widget is Tooltip && widget.message == label,
              ),
              findsOneWidget,
            );
            expect(find.bySemanticsLabel(label), findsOneWidget);
            expect(
              tester.widget<Icon>(find.byIcon(Icons.circle)).color,
              color.color,
            );
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  for (final background in [null, '', '#12345g']) {
    testWidgets('dettaglio senza indicatore per colore $background', (
      tester,
    ) async {
      final db = newTestDatabase();
      final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'})
        ..background = background;
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
            localizationsDelegates: [
              ...GlobalMaterialLocalizations.delegates,
              ...AppLocalizations.localizationsDelegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: EntryView(entryId: itemIdOf(entry)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.circle), findsNothing);
    });
  }

  testWidgets(
    'copia ogni campo toccando la riga e conserva la pulizia scelta',
    (tester) async {
      // given
      FlutterSecureStorage.setMockInitialValues({});
      addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
      final clipboard = FakeClipboard(tester.binding);
      final db = newTestDatabase();
      final entry = addTestEntry(
        db,
        db.root,
        {
          EntryFields.title: 'Voce di prova',
          EntryFields.userName: 'utente-di-prova',
          EntryFields.password: 'password-di-prova',
          EntryFields.url: 'https://example.org',
          EntryFields.notes: 'Prima riga\nSeconda riga',
          'Codice': 'codice-di-prova',
          'Segreto': 'segreto-di-prova',
        },
        protectedKeys: {EntryFields.password, 'Segreto'},
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
      await container
          .read(appSettingsProvider.notifier)
          .update(const AppSettings(clipboardTimeout: Duration(seconds: 60)));
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
            home: EntryView(entryId: itemIdOf(entry)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // when / then
      for (final (label, value) in [
        (l10n.entryUserName, 'utente-di-prova'),
        (l10n.entryPassword, 'password-di-prova'),
        (l10n.entryUrl, 'https://example.org'),
        (l10n.entryNotes, 'Prima riga\nSeconda riga'),
        ('Codice', 'codice-di-prova'),
        ('Segreto', 'segreto-di-prova'),
      ]) {
        final tile = find.widgetWithText(ListTile, label);
        await tester.scrollUntilVisible(tile, 150);
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getTopLeft(tile) + const Offset(4, 20));
        await tester.pumpAndSettle();
        expect(clipboard.text, value);
        expect(clipboard.clearAfter, const Duration(seconds: 60));
        expect(find.byIcon(Icons.copy), findsNothing);
      }
      expect(find.text('segreto-di-prova'), findsNothing);
      expect(find.text(l10n.entryCopied(60)), findsOneWidget);

      final secret = find.widgetWithText(ListTile, 'Segreto');
      clipboard.text = 'copia esterna';
      await tester.tap(
        find.descendant(of: secret, matching: find.byTooltip(l10n.entryShow)),
      );
      await tester.pumpAndSettle();
      expect(find.text('segreto-di-prova'), findsOneWidget);
      expect(clipboard.text, 'copia esterna');
      expect(clipboard.clearAfter, const Duration(seconds: 60));
    },
  );
}
