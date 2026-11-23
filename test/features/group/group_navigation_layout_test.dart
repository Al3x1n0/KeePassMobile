import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/database_navigation_bar.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/group/group_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_database.dart';

Future<void> _pumpGroupList(
  WidgetTester tester, {
  required ThemeMode themeMode,
  TextScaler textScaler = TextScaler.noScaling,
  bool inBin = false,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(bottom: 24);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  final database = newTestDatabase();
  final parent = inBin ? database.recycleBin! : database.root;
  for (var index = 0; index < 36; index++) {
    database.createGroup(
      parent: parent,
      name: 'Gruppo ${index.toString().padLeft(2, '0')}',
    );
  }
  final container = await newTestContainer();
  container
      .read(databaseSessionProvider.notifier)
      .open(
        DatabaseSession(
          file: const FileRef(uri: 'file:///prova.kdbx', name: 'prova.kdbx'),
          database: database,
        ),
      );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('it'),
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
        home: GroupView(groupId: inBin ? itemIdOf(parent) : null),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ScrollableState _scrollable(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );

Finder _capsule() => find.descendant(
  of: find.byType(DatabaseNavigationBar),
  matching: find.byType(BackdropFilter),
);

Future<void> _scrollToEnd(WidgetTester tester) async {
  final position = _scrollable(tester).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pumpAndSettle();
}

void main() {
  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'gruppi ${themeMode.name} testo $textScale: scorrono dietro la capsula e liberano lo spazio in selezione',
        (tester) async {
          // given
          await _pumpGroupList(
            tester,
            themeMode: themeMode,
            textScaler: TextScaler.linear(textScale),
          );
          final list = find.byType(ListView);
          final scaffold = find.byType(Scaffold);
          final fab = find.byType(FloatingActionButton);
          expect(tester.widget<Scaffold>(scaffold).extendBody, isTrue);
          expect(tester.getRect(list).bottom, 640);
          final capsuleBounds = tester.getRect(_capsule());
          expect(tester.getRect(fab).bottom, lessThan(capsuleBounds.top));

          // when: una riga attraversa la fascia occupata dalla capsula.
          final position = _scrollable(tester).position;
          position.jumpTo(position.maxScrollExtent / 2);
          await tester.pumpAndSettle();

          // then: il margine laterale resta trasparente anche agli eventi.
          final probe = Offset(capsuleBounds.left / 2, capsuleBounds.center.dy);
          final tiles = find.byType(ListTile);
          Finder? behindBar;
          for (var index = 0; index < tiles.evaluate().length; index++) {
            final tile = tiles.at(index);
            if (tester.getRect(tile).contains(probe)) {
              behindBar = tile;
              break;
            }
          }
          expect(behindBar, isNotNull);
          final tileRenderObject = tester.renderObject(behindBar!);
          expect(
            tester
                .hitTestOnBinding(probe)
                .path
                .any((entry) => entry.target == tileRenderObject),
            isTrue,
          );

          // when: si arriva al fondo, quindi si seleziona l'ultima riga.
          await _scrollToEnd(tester);
          final last = find.widgetWithText(ListTile, 'Gruppo 35');
          expect(last.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(last).bottom,
            lessThan(tester.getRect(fab).top),
          );
          await tester.longPress(last);
          await tester.pumpAndSettle();

          // then: scompaiono barra, FAB e relativo padding aggiuntivo.
          expect(find.byType(DatabaseNavigationBar), findsNothing);
          expect(fab, findsNothing);
          expect(tester.widget<Scaffold>(scaffold).extendBody, isFalse);
          expect(tester.widget<ListView>(list).padding, isNull);
          await _scrollToEnd(tester);
          expect(last.hitTestable(), findsOneWidget);
          expect(tester.getRect(last).bottom, lessThanOrEqualTo(640 - 24));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'cestino ${themeMode.name}: ultima riga sopra la capsula senza FAB',
      (tester) async {
        // given
        await _pumpGroupList(tester, themeMode: themeMode, inBin: true);
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).extendBody,
          isTrue,
        );
        expect(tester.getRect(find.byType(ListView)).bottom, 640);

        // when
        await _scrollToEnd(tester);

        // then
        final last = find.widgetWithText(ListTile, 'Gruppo 35');
        expect(last.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(last).bottom,
          lessThan(tester.getRect(_capsule()).top),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
