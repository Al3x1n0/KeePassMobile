import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/ui/selection_app_bar_builder.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const bodyKey = Key('contenuto');
  var showSelectAll = true;
  var disableAnimations = false;
  var enabled = true;
  var calls = 0;
  late StateSetter update;

  Future<void> pumpPage(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      locale: const Locale('it'),
      localizationsDelegates: [
        ...GlobalMaterialLocalizations.delegates,
        ...AppLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: SelectionAppBarBuilder(
              showSelectAll: showSelectAll,
              onSelectAll: enabled ? () => calls++ : null,
              builder: (context, bottom) => Scaffold(
                appBar: AppBar(
                  title: const Text('1 selezionati'),
                  bottom: bottom,
                ),
                body: const SizedBox.expand(key: bodyKey),
              ),
            ),
          );
        },
      ),
    ),
  );

  setUp(() {
    showSelectAll = true;
    disableAnimations = false;
    enabled = true;
    calls = 0;
  });

  testWidgets(
    'riga e contenuto scorrono insieme durante collasso ed espansione',
    (tester) async {
      await pumpPage(tester);
      final row = find.text('Selez. tutti');
      final rowTop = tester.getTopLeft(row).dy;
      expect(tester.getTopLeft(find.byKey(bodyKey)).dy, kToolbarHeight + 48);

      update(() => showSelectAll = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final middle = tester.getTopLeft(find.byKey(bodyKey)).dy;
      expect(middle, inExclusiveRange(kToolbarHeight, kToolbarHeight + 48));
      expect(tester.getTopLeft(row).dy, lessThan(rowTop));
      expect(
        tester.getSize(find.byType(AppBar)).height,
        closeTo(middle, 0.001),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selez. tutti'), findsNothing);
      expect(tester.getTopLeft(find.byKey(bodyKey)).dy, kToolbarHeight);

      update(() => showSelectAll = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getTopLeft(find.byKey(bodyKey)).dy,
        inExclusiveRange(kToolbarHeight, kToolbarHeight + 48),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(bodyKey)).dy, kToolbarHeight + 48);
      expect(tester.getTopLeft(row).dy, rowTop);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('prima selezione completa mantiene solo la toolbar standard', (
    tester,
  ) async {
    showSelectAll = false;
    await pumpPage(tester);
    expect(tester.getTopLeft(find.byKey(bodyKey)).dy, kToolbarHeight);
    expect(find.text('Selez. tutti'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(bodyKey)).dy, kToolbarHeight);
  });

  testWidgets(
    'animazioni disabilitate aggiornano subito lo spazio della pagina',
    (tester) async {
      disableAnimations = true;
      await pumpPage(tester);
      update(() => showSelectAll = false);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(bodyKey)).dy, kToolbarHeight);
      update(() => showSelectAll = true);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(bodyKey)).dy, kToolbarHeight + 48);
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );

  testWidgets('busy disabilita Selez. tutti', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Selez. tutti'));
    expect(calls, 1);
    update(() => enabled = false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selez. tutti'));
    expect(calls, 1);
  });
}
