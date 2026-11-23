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
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = const Size(320, 640);
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
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tab(String label) => find
    .ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.button == true,
      ),
    )
    .first;

void _expectContains(Rect outer, Rect inner) {
  expect(inner.left, greaterThanOrEqualTo(outer.left));
  expect(inner.top, greaterThanOrEqualTo(outer.top));
  expect(inner.right, lessThanOrEqualTo(outer.right));
  expect(inner.bottom, lessThanOrEqualTo(outer.bottom));
}

void main() {
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
        expect(color.a, lessThan(1));
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
            (l10n.navigationGenerate, Icons.casino_outlined, false),
            (l10n.navigationCheck, Icons.shield_outlined, false),
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
            final activePill = find
                .ancestor(
                  of: find.text(label),
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is Material &&
                        widget.shape is StadiumBorder &&
                        widget.color ==
                            Theme.of(tester.element(tab))
                                .navigationBarTheme
                                .indicatorColor,
                  ),
                )
                .first;
            expect(activePill, findsOneWidget);
            final pill = tester.getRect(activePill);
            _expectContains(pill, tester.getRect(find.text(label)));
            _expectContains(pill, tester.getRect(find.byIcon(icon)));
            final activeColor = tester.widget<Material>(activePill).color!;
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
