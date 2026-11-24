import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/autofill/autofill_file_select_view.dart';
import 'package:keepass_mobile/features/entry/entry_view.dart';
import 'package:keepass_mobile/features/file_select/file_select_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/ui/database_item_icon.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_database.dart';

void _expectSingleLine(
  WidgetTester tester,
  Finder title, {
  bool clipped = false,
}) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: title, matching: find.byType(RichText)),
  );
  expect(paragraph.softWrap, isFalse);
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: paragraph.text.toPlainText().length,
    ),
  );
  expect(boxes.map((box) => box.top).toSet().length, lessThanOrEqualTo(1));
  expect(paragraph.size.height, greaterThan(0));
  expect(paragraph.overflow, TextOverflow.ellipsis);
  if (clipped) expect(paragraph.didExceedMaxLines, isTrue);
  expect(tester.takeException(), isNull);
}

double _leadingRight(WidgetTester tester) {
  final toolbar = tester.widget<NavigationToolbar>(
    find.byType(NavigationToolbar),
  );
  return tester.getRect(find.byWidget(toolbar.leading!)).right;
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('it'));

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
        '${platform.name} ${brightness.name}: titoli a sinistra, spazi standard ed ellissi nelle viste e licenze',
        (tester) async {
          // given
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final container = await newTestContainer();
          final db = newTestDatabase();
          final entry = addTestEntry(db, db.root, {
            EntryFields.title:
                'Titolo di una voce molto lungo che deve terminare con ellissi',
          });
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

          Widget app(Widget home, {double scale = 1, String key = 'app'}) =>
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  key: ValueKey(key),
                  locale: const Locale('it'),
                  localizationsDelegates: [
                    ...GlobalMaterialLocalizations.delegates,
                    ...AppLocalizations.localizationsDelegates,
                  ],
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: buildLightTheme().copyWith(platform: platform),
                  darkTheme: buildDarkTheme().copyWith(platform: platform),
                  themeMode: brightness == Brightness.light
                      ? ThemeMode.light
                      : ThemeMode.dark,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: home,
                ),
              );

          Finder title(String text) => find.descendant(
            of: find.byType(AppBar),
            matching: find.text(text),
          );

          // when / then: senza leading il titolo parte dal margine standard.
          await tester.pumpWidget(app(const FileSelectView()));
          await tester.pumpAndSettle();
          expect(find.byType(BackButton), findsNothing);
          expect(
            tester.getTopLeft(title(l10n.fileSelectTitle)).dx,
            AppSpacing.m,
          );
          _expectSingleLine(tester, title(l10n.fileSelectTitle));

          await tester.pumpWidget(app(const FileSelectView(), scale: 2));
          await tester.pumpAndSettle();
          final fileTitle = title(l10n.fileSelectTitle);
          _expectSingleLine(tester, fileTitle, clipped: true);
          expect(
            tester.getRect(fileTitle).right,
            lessThanOrEqualTo(
              tester.getRect(find.byTooltip(l10n.settingsTitle)).left,
            ),
          );

          // when / then: back, icona della voce e azioni mantengono i loro spazi.
          final navigator = Navigator.of(
            tester.element(find.byType(FileSelectView)),
          );
          navigator.push<void>(
            MaterialPageRoute(
              builder: (_) => EntryView(entryId: itemIdOf(entry)),
            ),
          );
          await tester.pumpAndSettle();
          final entryText = title(entryTitle(entry));
          final icon = find.descendant(
            of: find.byType(AppBar),
            matching: find.byType(DatabaseItemIcon),
          );
          expect(find.byType(BackButton), findsOneWidget);
          expect(
            tester.getRect(icon).left,
            _leadingRight(tester) + AppSpacing.m,
          );
          expect(
            tester.getRect(entryText).left,
            tester.getRect(icon).right + AppSpacing.s,
          );
          expect(
            tester.getRect(entryText).right,
            lessThanOrEqualTo(
              tester.getRect(find.byTooltip(l10n.entryFavoriteAdd)).left,
            ),
          );
          _expectSingleLine(tester, entryText, clipped: true);
          navigator.pop();
          await tester.pumpAndSettle();

          // when / then: anche la pagina di sistema eredita l'allineamento.
          final context = tester.element(find.byType(FileSelectView));
          final licensesTitle = MaterialLocalizations.of(context)
              .licensesPageTitle;
          showLicensePage(context: context, applicationName: l10n.appTitle);
          await tester.pumpAndSettle();
          final licenses = title(licensesTitle);
          expect(
            tester.getRect(licenses).left,
            _leadingRight(tester) + AppSpacing.m,
          );
          _expectSingleLine(tester, licenses);
          navigator.pop();
          await tester.pumpAndSettle();

          // when / then: la chiusura Autofill usa lo stesso spazio del back.
          await tester.pumpWidget(
            app(const AutofillFileSelectView(), key: 'autofill'),
          );
          await tester.pumpAndSettle();
          final autofill = title(l10n.autofillChooseDatabase);
          expect(find.byTooltip(l10n.autofillClose), findsOneWidget);
          expect(
            tester.getRect(autofill).left,
            _leadingRight(tester) + AppSpacing.m,
          );
          _expectSingleLine(tester, autofill);
          await tester.pumpWidget(
            app(const AutofillFileSelectView(), scale: 2, key: 'autofill'),
          );
          await tester.pumpAndSettle();
          _expectSingleLine(tester, autofill, clipped: true);
        },
      );
    }
  }
}
