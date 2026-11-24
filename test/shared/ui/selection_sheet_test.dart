import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/shared/ui/selection_sheet.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final selectOption in [false, true]) {
    testWidgets(
      'selettore con Navigator annidato: copre la barra comune e ${selectOption ? "restituisce la scelta" : "si chiude dalla barriera"}',
      (tester) async {
        // given
        final rootNavigator = GlobalKey<NavigatorState>();
        final nestedNavigator = GlobalKey<NavigatorState>();
        Route<int>? sheetRoute;
        int? result = -1;
        var navigationTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: rootNavigator,
            theme: buildLightTheme(),
            home: Scaffold(
              bottomNavigationBar: TextButton(
                onPressed: () => navigationTaps++,
                child: const Text('Barra comune'),
              ),
              body: Navigator(
                key: nestedNavigator,
                onGenerateRoute: (settings) => MaterialPageRoute<void>(
                  settings: settings,
                  builder: (context) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () async {
                          result = await showSelectionSheet<int>(
                            context: context,
                            title: 'Scelta sintetica',
                            options: const {1: 'Prima', 2: 'Seconda'},
                            onRoute: (route) => sheetRoute = route,
                          );
                        },
                        child: const Text('Apri scelte'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final commonBar = find.text('Barra comune');
        expect(commonBar.hitTestable(), findsOneWidget);

        // when
        await tester.tap(find.text('Apri scelte'));
        await tester.pumpAndSettle();

        // then: il pannello e la barriera stanno sopra l'intera navigazione.
        expect(sheetRoute?.navigator, same(rootNavigator.currentState));
        expect(nestedNavigator.currentState?.canPop(), isFalse);
        expect(commonBar.hitTestable(), findsNothing);
        expect(find.text('Scelta sintetica'), findsOneWidget);
        if (selectOption) {
          await tester.tap(find.text('Seconda'));
        } else {
          await tester.tapAt(const Offset(20, 20));
        }
        await tester.pumpAndSettle();
        expect(result, selectOption ? 2 : isNull);
        expect(find.text('Scelta sintetica'), findsNothing);
        expect(navigationTaps, 0);
        expect(rootNavigator.currentState?.canPop(), isFalse);
        expect(nestedNavigator.currentState?.canPop(), isFalse);
        expect(commonBar.hitTestable(), findsOneWidget);
        await tester.tap(commonBar);
        expect(navigationTaps, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
