import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/file_select/file_select_view.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/features/unlock/unlock_view_model.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_database.dart';

const _pickedFile = FileRef(uri: 'file:///scelto.kdbx', name: 'scelto.kdbx');

class _Picker extends FilePickerService {
  int calls = 0;

  @override
  Future<PickedFile?> pick() async {
    calls++;
    return const PickedFile(ref: _pickedFile);
  }
}

class _DemoStorage extends FileStorage {
  String? suggestedName;
  Uint8List? savedBytes;

  @override
  Future<FileRef?> create({
    required String suggestedName,
    required Uint8List bytes,
  }) async {
    this.suggestedName = suggestedName;
    savedBytes = bytes;
    return FileRef(uri: 'file:///demo.kdbx', name: suggestedName);
  }
}

class _Harness {
  _Harness(this.router, this.picker, this.storage);

  final GoRouter router;
  final _Picker picker;
  final _DemoStorage storage;
  Object? lastExtra;
}

Future<_Harness> _pumpSelection(
  WidgetTester tester, {
  Locale locale = const Locale('it'),
  bool additional = false,
  int recentCount = 0,
  double scale = 1,
  bool boldText = false,
  Brightness brightness = Brightness.light,
  Size size = const Size(320, 568),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  SharedPreferences.setMockInitialValues({
    RecentFilesRepository.storageKey: [
      for (var index = 0; index < recentCount; index++)
        jsonEncode(
          RecentFile(
            database: FileRef(
              uri: 'file:///recente-$index.kdbx',
              name: 'Recente $index.kdbx',
            ),
          ).toJson(),
        ),
    ],
  });
  final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
  final picker = _Picker();
  final storage = _DemoStorage();
  late _Harness harness;
  final router = GoRouter(
    initialLocation: additional ? AppRoutes.additionalDatabase : '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => additional
            ? const Scaffold(body: Text('Home'))
            : const FileSelectView(),
        routes: [
          GoRoute(
            path: AppRoutes.additionalDatabase.substring(1),
            builder: (_, _) => const FileSelectView(additional: true),
          ),
        ],
      ),
      for (final path in [
        AppRoutes.createDatabase,
        AppRoutes.appSettings,
        AppRoutes.remoteOpen,
        AppRoutes.additionalRemote,
        AppRoutes.unlock,
        AppRoutes.additionalUnlock,
      ])
        GoRoute(
          path: path,
          builder: (_, state) {
            harness.lastExtra = state.extra;
            return Scaffold(body: Text('Destinazione $path'));
          },
        ),
    ],
  );
  harness = _Harness(router, picker, storage);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        filePickerServiceProvider.overrideWithValue(picker),
        fileStorageProvider.overrideWithValue(storage),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        localizationsDelegates: [
          ...GlobalMaterialLocalizations.delegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: brightness == Brightness.light
            ? ThemeMode.light
            : ThemeMode.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale), boldText: boldText),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Finder _fab(String label) => find.widgetWithText(FloatingActionButton, label);

ScrollPosition _bodyPosition(WidgetTester tester) {
  final body = tester.widget<Scaffold>(find.byType(Scaffold).last).body!;
  final scrollables = find.descendant(
    of: find.byWidget(body),
    matching: find.byType(Scrollable),
  );
  return tester.state<ScrollableState>(scrollables.first).position;
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  final position = _bodyPosition(tester);
  for (var attempt = 0; attempt < 10; attempt++) {
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    if ((position.pixels - position.maxScrollExtent).abs() < 0.01) break;
  }
}

Future<void> _expectButtons(
  WidgetTester tester,
  AppLocalizations l10n, {
  required bool additional,
}) async {
  final labels = [
    if (!additional) l10n.fileSelectNewDatabase,
    l10n.fileSelectOpenFile,
    l10n.remoteOpenTitle,
  ];
  final tags = <Object?>{};
  final rectangles = <Rect>[];
  for (final label in labels) {
    final finder = _fab(label);
    final fab = tester.widget<FloatingActionButton>(finder);
    expect(fab.isExtended, isTrue);
    expect(fab.heroTag, isNotNull);
    tags.add(fab.heroTag);
    final rect = tester.getRect(finder);
    rectangles.add(rect);
    expect(rect.left, greaterThanOrEqualTo(AppSpacing.m - 0.01));
    expect(rect.right, lessThanOrEqualTo(320 - AppSpacing.m + 0.01));
    expect(rect.height, greaterThanOrEqualTo(48));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.descendant(of: finder, matching: find.text(label)),
        matching: find.byType(RichText),
      ),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.text.toPlainText(), label);
    for (var offset = 0; offset < label.length; offset++) {
      if (label[offset].trim().isEmpty) continue;
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      )) {
        expect(box.left, greaterThanOrEqualTo(-0.01));
        expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.01));
      }
    }
  }
  expect(tags.length, labels.length);
  expect(find.byType(FloatingActionButton), findsNWidgets(labels.length));
  for (var index = 1; index < rectangles.length; index++) {
    expect(rectangles[index].width, closeTo(rectangles.first.width, 0.01));
    expect(rectangles[index].right, closeTo(rectangles.first.right, 0.01));
    expect(rectangles[index].top, greaterThan(rectangles[index - 1].bottom));
  }
  if (rectangles.length == 3) {
    expect(
      rectangles[1].top - rectangles[0].bottom,
      closeTo(rectangles[2].top - rectangles[1].bottom, 0.01),
    );
  }
  final floating = tester
      .widget<Scaffold>(find.byType(Scaffold).last)
      .floatingActionButton!;
  final stackScrollable = find.descendant(
    of: find.byWidget(floating),
    matching: find.byType(Scrollable),
  );
  if (stackScrollable.evaluate().isEmpty) {
    expect(rectangles.last.bottom, lessThanOrEqualTo(568 - 24));
  }
  expect(rectangles.first.top, greaterThanOrEqualTo(56));
  for (final label in labels) {
    await tester.ensureVisible(_fab(label));
    await tester.pumpAndSettle();
    expect(_fab(label).hitTestable(), findsOneWidget);
  }
  if (stackScrollable.evaluate().isNotEmpty) {
    tester.state<ScrollableState>(stackScrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
  }
  expect(find.byIcon(Icons.folder_open), findsOneWidget);
  expect(find.byIcon(Icons.cloud_outlined), findsOneWidget);
  expect(
    find.byIcon(Icons.note_add_outlined),
    additional ? findsNothing : findsOneWidget,
  );
  final appBar = tester.widget<AppBar>(find.byType(AppBar));
  expect(appBar.actions ?? [], hasLength(additional ? 0 : 1));
  expect(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.settings_outlined),
    ),
    additional ? findsNothing : findsOneWidget,
  );
  expect(find.byType(BackButton), additional ? findsOneWidget : findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  for (final locale in [const Locale('it'), const Locale('en')]) {
    final l10n = lookupAppLocalizations(locale);
    testWidgets(
      '${locale.languageCode}: testo in grassetto ingrandito senza overflow nei FAB',
      (tester) async {
        await _pumpSelection(tester, locale: locale, scale: 2, boldText: true);
        await _expectButtons(tester, l10n, additional: false);
        expect(
          tester.getRect(_fab(l10n.fileSelectNewDatabase)).top,
          greaterThanOrEqualTo(56),
        );
      },
    );
    for (final additional in [false, true]) {
      for (final scale in [1.0, 2.0, 3.0]) {
        for (final recentCount in [0, 30]) {
          testWidgets(
            '${locale.languageCode} additional=$additional testo=$scale recenti=$recentCount: FAB e contenuti accessibili su schermo compatto',
            (tester) async {
              // given
              final harness = await _pumpSelection(
                tester,
                locale: locale,
                additional: additional,
                recentCount: recentCount,
                scale: scale,
                brightness: scale == 2 ? Brightness.dark : Brightness.light,
              );
              await _expectButtons(tester, l10n, additional: additional);

              // when
              await _scrollToEnd(tester);
              final firstFab = _fab(
                additional
                    ? l10n.fileSelectOpenFile
                    : l10n.fileSelectNewDatabase,
              );

              // then
              final contentTop = tester.getRect(find.byType(AppBar)).bottom;
              if (recentCount == 0 && additional) {
                final message = find.text(l10n.fileSelectNoRecent);
                expect(
                  tester.getRect(message).bottom,
                  lessThan(tester.getRect(firstFab).top),
                );
                final position = _bodyPosition(tester);
                position.jumpTo(0);
                await tester.pumpAndSettle();
                expect(
                  message.hitTestable(at: Alignment.topCenter),
                  findsOneWidget,
                );
                expect(find.text(l10n.fileSelectDemo), findsNothing);
              } else {
                final lastTile = find.widgetWithText(
                  ListTile,
                  additional ? 'Recente 29.kdbx' : l10n.fileSelectDemo,
                );
                expect(
                  tester.getRect(lastTile).bottom,
                  lessThan(tester.getRect(firstFab).top),
                );
                if (tester.getRect(lastTile).top >= contentTop) {
                  expect(lastTile.hitTestable(), findsOneWidget);
                  await tester.tap(lastTile);
                } else {
                  // Una riga più alta della zona libera si legge scorrendola:
                  // il fondo è raggiungibile, così come l'inizio e il tap.
                  final position = _bodyPosition(tester);
                  position.jumpTo(
                    (position.pixels -
                            (contentTop - tester.getRect(lastTile).top))
                        .clamp(0, position.maxScrollExtent)
                        .toDouble(),
                  );
                  await tester.pumpAndSettle();
                  expect(
                    tester.getRect(lastTile).top,
                    greaterThanOrEqualTo(contentTop - 0.01),
                  );
                  final probe = Offset(
                    tester.getRect(lastTile).center.dx,
                    tester.getRect(lastTile).top + AppSpacing.l,
                  );
                  expect(probe.dy, lessThan(tester.getRect(firstFab).top));
                  await tester.tapAt(probe);
                }
                await pumpUntilFound(
                  tester,
                  find.text(
                    'Destinazione ${additional ? AppRoutes.additionalUnlock : AppRoutes.unlock}',
                  ),
                );
                final args = harness.lastExtra! as UnlockArgs;
                expect(args.additional, additional);
                if (additional) {
                  expect(args.database.ref.name, 'Recente 29.kdbx');
                } else {
                  expect(harness.storage.suggestedName, 'Rifugio-Aurora.kdbx');
                  expect(harness.storage.savedBytes, isNotEmpty);
                }
              }
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }

    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
        '${locale.languageCode} ${brightness.name}: colori del tema e larghezza naturale condivisa',
        (tester) async {
          // given
          expect(
            l10n.fileSelectNewDatabase,
            locale.languageCode == 'it' ? 'Nuovo DB' : 'New DB',
          );
          expect(
            l10n.createDatabaseTitle,
            locale.languageCode == 'it' ? 'Nuovo database' : 'New database',
          );
          await _pumpSelection(
            tester,
            locale: locale,
            brightness: brightness,
            size: const Size(800, 800),
          );
          final defaultWidth = tester.getSize(_fab(l10n.remoteOpenTitle)).width;
          final context = tester.element(_fab(l10n.remoteOpenTitle));
          final theme = Theme.of(context);
          final loneFab = MaterialApp(
            locale: locale,
            localizationsDelegates: [
              ...GlobalMaterialLocalizations.delegates,
              ...AppLocalizations.localizationsDelegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: theme,
            home: Scaffold(
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () {},
                icon: const Icon(Icons.cloud_outlined),
                label: Text(l10n.remoteOpenTitle),
              ),
            ),
          );
          for (final label in [
            l10n.fileSelectNewDatabase,
            l10n.fileSelectOpenFile,
            l10n.remoteOpenTitle,
          ]) {
            final material = find
                .descendant(of: _fab(label), matching: find.byType(Material))
                .first;
            expect(tester.widget<Material>(material).color, AppColors.blue);
            final textContext = tester.element(
              find.descendant(of: _fab(label), matching: find.text(label)),
            );
            expect(
              DefaultTextStyle.of(textContext).style.color,
              AppColors.white,
            );
            final iconContext = tester.element(
              find.descendant(of: _fab(label), matching: find.byType(Icon)),
            );
            expect(IconTheme.of(iconContext).color, AppColors.white);
          }

          // when / then: la pila conserva la dimensione del FAB più lungo.
          await tester.pumpWidget(loneFab);
          await tester.pumpAndSettle();
          expect(
            tester.getSize(find.byType(FloatingActionButton)).width,
            closeTo(defaultWidth, 1),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    for (final additional in [false, true]) {
      testWidgets(
        '${locale.languageCode} additional=$additional: i FAB aprono i percorsi corretti e il picker invariato',
        (tester) async {
          // given
          final harness = await _pumpSelection(
            tester,
            locale: locale,
            additional: additional,
          );
          if (!additional) {
            await tester.tap(_fab(l10n.fileSelectNewDatabase));
            await tester.pumpAndSettle();
            expect(
              find.text('Destinazione ${AppRoutes.createDatabase}'),
              findsOneWidget,
            );
            harness.router.pop();
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip(l10n.settingsTitle));
            await tester.pumpAndSettle();
            expect(
              find.text('Destinazione ${AppRoutes.appSettings}'),
              findsOneWidget,
            );
            harness.router.pop();
            await tester.pumpAndSettle();
          }

          // when / then
          await tester.tap(_fab(l10n.remoteOpenTitle));
          await tester.pumpAndSettle();
          expect(
            find.text(
              'Destinazione ${additional ? AppRoutes.additionalRemote : AppRoutes.remoteOpen}',
            ),
            findsOneWidget,
          );
          harness.router.pop();
          await tester.pumpAndSettle();
          await tester.tap(_fab(l10n.fileSelectOpenFile));
          await tester.pumpAndSettle();
          expect(harness.picker.calls, 1);
          expect(
            find.text(
              'Destinazione ${additional ? AppRoutes.additionalUnlock : AppRoutes.unlock}',
            ),
            findsOneWidget,
          );
          final args = harness.lastExtra! as UnlockArgs;
          expect(args.additional, additional);
          expect(args.database.ref, _pickedFile);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
