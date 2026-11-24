import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/shared/ui/expandable_section.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpSection(
    WidgetTester tester, {
    bool disableAnimations = false,
    double textScale = 1,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildLightTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: ListView(
            children: [
              ExpandableSection(
                title: 'Sezione di prova',
                children: [
                  ListTile(
                    title: const Text('Contenuto di prova'),
                    onTap: () {},
                  ),
                  const SizedBox(height: 80),
                ],
              ),
              const ExpandableSection(
                title: 'Seconda sezione',
                children: [Text('Secondo contenuto')],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('stile condiviso, intestazione accessibile e spaziature', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSection(tester);
    final heading = find.text('Sezione di prova');
    final section = find.byType(ExpandableSection).first;
    final panel = find.descendant(of: section, matching: find.byType(Material));
    final material = tester.widget<Material>(panel);
    final scheme = Theme.of(tester.element(section)).colorScheme;
    expect(material.color, scheme.primary.withValues(alpha: 0.16));
    expect(material.clipBehavior, Clip.antiAlias);
    expect(
      (material.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(16),
    );
    expect(tester.getRect(panel).left, 16);
    expect(
      tester.getRect(panel).right,
      tester.getSize(find.byType(ListView)).width - 16,
    );
    final secondPanel = find.descendant(
      of: find.byType(ExpandableSection).last,
      matching: find.byType(Material),
    );
    expect(tester.getRect(secondPanel).top - tester.getRect(panel).bottom, 16);
    final header = find.ancestor(of: heading, matching: find.byType(InkWell));
    expect(tester.getSize(header).height, greaterThanOrEqualTo(48));
    final data = tester.getSemantics(heading).getSemanticsData();
    expect(data.flagsCollection.isHeader, isTrue);
    expect(data.flagsCollection.isExpanded, Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets('anima altezza e freccia, esclude contenuti chiusi e riapre', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSection(tester);
    final heading = find.text('Sezione di prova');
    final section = find.byType(ExpandableSection).first;
    final rotation = find.descendant(
      of: section,
      matching: find.byType(RotationTransition),
    );
    final initialHeight = tester.getSize(section).height;
    expect(find.text('Contenuto di prova').hitTestable(), findsOneWidget);

    // when: campiona la chiusura prima della fine della transizione.
    await tester.tap(heading);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final middleHeight = tester.getSize(section).height;
    expect(middleHeight, lessThan(initialHeight));
    expect(
      tester.widget<RotationTransition>(rotation).turns.value,
      inExclusiveRange(0, 0.5),
    );
    expect(find.text('Contenuto di prova').hitTestable(), findsNothing);
    expect(
      tester
          .getSemantics(heading)
          .getSemanticsData()
          .flagsCollection
          .isExpanded,
      Tristate.isFalse,
    );
    expect(find.text('Secondo contenuto').hitTestable(), findsOneWidget);

    // then: chiusura completa e riapertura animata.
    await tester.pumpAndSettle();
    expect(tester.getSize(section).height, lessThan(middleHeight));
    expect(find.text('Contenuto di prova'), findsNothing);
    expect(tester.widget<RotationTransition>(rotation).turns.value, 0.5);
    await tester.tap(heading);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(section).height, inExclusiveRange(80, initialHeight));
    await tester.pumpAndSettle();
    expect(tester.getSize(section).height, initialHeight);
    expect(find.text('Contenuto di prova').hitTestable(), findsOneWidget);
    expect(tester.widget<RotationTransition>(rotation).turns.value, 0);
    semantics.dispose();
  });

  testWidgets('i controlli chiusi non ricevono il focus da tastiera', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpandableSection(
            title: 'Sezione di prova',
            children: [
              TextButton(
                focusNode: focus,
                onPressed: () {},
                child: const Text('Controllo di prova'),
              ),
            ],
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.text('Sezione di prova'));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
    expect(focus.canRequestFocus, isFalse);
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);

    await tester.tap(find.text('Sezione di prova'));
    await tester.pumpAndSettle();
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('rispetta animazioni disabilitate e testo grande a 320 dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpSection(tester, disableAnimations: true, textScale: 2);
    await tester.tap(find.text('Sezione di prova'));
    await tester.pump();
    expect(find.text('Contenuto di prova'), findsNothing);
    expect(
      tester
          .widget<SizeTransition>(find.byType(SizeTransition).first)
          .sizeFactor
          .value,
      0,
    );
    await tester.tap(find.text('Sezione di prova'));
    await tester.pump();
    expect(find.text('Contenuto di prova').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
