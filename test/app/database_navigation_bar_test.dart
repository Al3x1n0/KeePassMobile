import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/database_navigation_bar.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

Future<void> _pumpBar(
  WidgetTester tester, {
  required Brightness brightness,
  Locale locale = const Locale('it'),
  bool settingsSelected = false,
  bool checkSelected = false,
  TextScaler textScaler = TextScaler.noScaling,
  double width = 320,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const safeInsets = EdgeInsets.fromLTRB(11, 0, 7, 34);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: [
        ...GlobalMaterialLocalizations.delegates,
        ...AppLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: safeInsets,
          viewPadding: safeInsets,
          textScaler: textScaler,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        extendBody: true,
        body: const SizedBox.expand(),
        bottomNavigationBar: DatabaseNavigationBar(
          settingsSelected: settingsSelected,
          checkSelected: checkSelected,
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

Finder _tab(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.button == true,
      ),
    )
    .first;

Finder _indicator() => find.descendant(
  of: find.byType(DatabaseNavigationBar),
  matching: find.byWidgetPredicate(
    (widget) => widget is AnimatedPositionedDirectional,
  ),
);

void _expectContains(Rect outer, Rect inner) {
  expect(inner.left, greaterThanOrEqualTo(outer.left));
  expect(inner.top, greaterThanOrEqualTo(outer.top));
  expect(inner.right, lessThanOrEqualTo(outer.right));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom));
}

void main() {
  testWidgets('Controllo attiva la terza destinazione', (tester) async {
    await _pumpBar(tester, brightness: Brightness.light, checkSelected: true);
    final data = tester.getSemantics(_tab('Controllo')).getSemanticsData();
    expect(data.flagsCollection.isSelected, Tristate.isTrue);
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'capsula ${brightness.name}: vetro e margini oltre gli inset di sistema',
      (tester) async {
        // given
        await _pumpBar(tester, brightness: brightness);

        // then: la superficie sfocata non copre i margini o la SafeArea.
        final blur = find.descendant(
          of: find.byType(DatabaseNavigationBar),
          matching: find.byType(BackdropFilter),
        );
        expect(blur, findsOneWidget);
        final surface = find
            .descendant(of: blur, matching: find.byType(Material))
            .first;
        final material = tester.widget<Material>(surface);
        final bounds = tester.getRect(surface);
        expect(material.shape, isA<StadiumBorder>());
        expect(bounds.left, greaterThan(11));
        expect(bounds.right, lessThan(320 - 7));
        expect(bounds.bottom, lessThan(640 - 34));
        expect(bounds.height, greaterThanOrEqualTo(48));

        final color = material.color!;
        expect(color.a, greaterThan(0));
        expect(color.a, lessThan(0.5));
        expect(
          color.toARGB32() & 0x00FFFFFF,
          brightness == Brightness.dark ? 0x0020202E : 0x00F5F5F7,
        );
        expect(tester.takeException(), isNull);
      },
    );

    for (final settingsSelected in [false, true]) {
      testWidgets(
        'tab ${brightness.name}: pillola e semantica con ${settingsSelected ? "Impostazioni" : "Home"} attiva',
        (tester) async {
          // given
          await _pumpBar(
            tester,
            brightness: brightness,
            settingsSelected: settingsSelected,
          );
          final l10n = lookupAppLocalizations(const Locale('it'));
          final destinations = [
            (l10n.navigationHome, Icons.home_outlined, true),
            (l10n.navigationGenerate, Icons.casino_outlined, true),
            (l10n.navigationCheck, Icons.shield_outlined, true),
            (l10n.settingsTitle, Icons.settings_outlined, true),
          ];
          final activeIndex = settingsSelected ? 3 : 0;

          // then: tutte le destinazioni mantengono target e stati accessibili.
          for (var index = 0; index < destinations.length; index++) {
            final (label, icon, enabled) = destinations[index];
            final tab = _tab(label);
            final data = tester.getSemantics(tab).getSemanticsData();
            expect(
              data.flagsCollection.isSelected,
              index == activeIndex ? Tristate.isTrue : Tristate.isFalse,
            );
            expect(
              data.flagsCollection.isEnabled,
              enabled ? Tristate.isTrue : Tristate.isFalse,
            );
            expect(data.hasAction(SemanticsAction.tap), enabled);
            expect(
              find.byWidgetPredicate(
                (widget) => widget is Tooltip && widget.message == label,
              ),
              findsOneWidget,
            );
            final target = tester.getRect(tab);
            expect(target.width, greaterThanOrEqualTo(48));
            expect(target.height, greaterThanOrEqualTo(48));

            if (index != activeIndex) continue;
            final activePill = _indicator();
            expect(activePill, findsOneWidget);
            final pill = tester.getRect(activePill);
            final labelBounds = tester.getRect(find.text(label));
            _expectContains(pill, labelBounds);
            _expectContains(pill, tester.getRect(find.byIcon(icon)));
            expect(labelBounds.left - pill.left, greaterThanOrEqualTo(8));
            expect(pill.right - labelBounds.right, greaterThanOrEqualTo(8));
            final decoration =
                tester
                        .widget<DecoratedBox>(
                          find.descendant(
                            of: activePill,
                            matching: find.byType(DecoratedBox),
                          ),
                        )
                        .decoration
                    as ShapeDecoration;
            final activeColor = decoration.color!;
            expect(decoration.shape, isA<StadiumBorder>());
            expect(activeColor.a, greaterThan(0));
            expect(activeColor.a, lessThan(1));
            expect(activeColor.toARGB32() & 0x00FFFFFF, 0x000066FF);
            final iconContext = tester.element(find.byIcon(icon));
            expect(
              tester.widget<Icon>(find.byIcon(icon)).color ??
                  IconTheme.of(iconContext).color,
              AppColors.blue,
            );
            final textContext = tester.element(find.text(label));
            expect(
              tester.widget<Text>(find.text(label)).style?.color ??
                  DefaultTextStyle.of(textContext).style.color,
              AppColors.blue,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'barra ${brightness.name}: capsula compatta e selezione con margini',
      (tester) async {
        // Il font dei widget test è più largo dei caratteri dell'app.
        await _pumpBar(tester, brightness: brightness, width: 600);
        final capsule = tester.getRect(find.byType(BackdropFilter));
        final pill = tester.getRect(_indicator());
        expect(capsule.height, 56);
        expect(pill.width, greaterThan(pill.height));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'barra ${brightness.name}: lo stesso ovale si sposta e si allarga verso Impostazioni',
      (tester) async {
        // given
        await _pumpBar(tester, brightness: brightness, width: 600);
        final element = tester.element(_indicator());
        final home = tester.getRect(_indicator());

        // when
        await _pumpBar(
          tester,
          brightness: brightness,
          width: 600,
          settingsSelected: true,
          settle: false,
        );
        expect(tester.element(_indicator()), same(element));
        expect(tester.getRect(_indicator()), home);
        await tester.pump(const Duration(milliseconds: 120));
        final halfway = tester.getRect(_indicator());
        await tester.pumpAndSettle();
        final settings = tester.getRect(_indicator());

        // then: posizione e larghezza cambiano senza ricreare l'indicatore.
        expect(halfway.left, greaterThan(home.left));
        expect(halfway.left, lessThan(settings.left));
        expect(halfway.width, greaterThan(home.width));
        expect(halfway.width, lessThan(settings.width));
        expect(settings.width, greaterThan(home.width));
        final label = tester.getRect(find.text('Impostazioni'));
        expect(label.left - settings.left, greaterThanOrEqualTo(8));
        expect(settings.right - label.right, greaterThanOrEqualTo(8));
        expect(tester.takeException(), isNull);
      },
    );

    for (final locale in [const Locale('it'), const Locale('en')]) {
      testWidgets(
        'barra ${brightness.name} ${locale.languageCode}: testo doppio a 320 dp senza overflow',
        (tester) async {
          // given
          await _pumpBar(
            tester,
            brightness: brightness,
            locale: locale,
            textScaler: const TextScaler.linear(2),
          );
          final l10n = lookupAppLocalizations(locale);

          // then: le etichette restano interamente nei rispettivi target.
          for (final label in [
            l10n.navigationHome,
            l10n.navigationGenerate,
            l10n.navigationCheck,
            l10n.settingsTitle,
          ]) {
            _expectContains(
              tester.getRect(_tab(label)),
              tester.getRect(find.text(label)),
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
