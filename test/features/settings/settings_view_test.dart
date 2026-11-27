import 'package:keepass_mobile/shared/ui/url_opener.dart';
import 'package:keepass_mobile/shared/settings/app_locale.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/settings/settings_view.dart';
import 'package:keepass_mobile/features/settings/settings_view_model.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/ui/expandable_section.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_database.dart';

class _SourceCodeOpener extends UrlOpener {
  _SourceCodeOpener(this.result);
  final Future<bool> result;
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) {
    opened.add(uri);
    return result;
  }
}

void main() {
  void viewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget app(
    ProviderContainer container, {
    Locale locale = const Locale('en'),
    bool databaseOpen = false,
    Key? settingsKey,
    double textScale = 1,
  }) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: [
        ...GlobalMaterialLocalizations.delegates,
        ...AppLocalizations.localizationsDelegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildLightTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SettingsView(
        key: settingsKey,
        showDatabaseNavigation: databaseOpen,
      ),
    ),
  );

  Future<ProviderContainer> container({
    bool databaseOpen = false,
    Future<String?>? version,
  }) async {
    final result = await newTestContainer(
      overrides: [
        if (version != null)
          settingsAppVersionProvider.overrideWith((ref) => version),
      ],
    );
    if (databaseOpen) {
      result
          .read(databaseSessionProvider.notifier)
          .open(
            DatabaseSession(
              file: const FileRef(
                uri: 'file:///prova.kdbx',
                name: 'prova.kdbx',
              ),
              database: newTestDatabase(),
            ),
          );
    }
    return result;
  }

  for (final locale in [const Locale('it'), const Locale('en')]) {
    for (final result in [true, false]) {
      testWidgets('sorgente ${locale.languageCode}: apertura esterna $result', (
        tester,
      ) async {
        // given
        viewport(tester, const Size(800, 3000));
        final opener = _SourceCodeOpener(Future.value(result));
        final scope = await newTestContainer(
          overrides: [urlOpenerProvider.overrideWithValue(opener)],
        );
        final l10n = lookupAppLocalizations(locale);
        await tester.pumpWidget(app(scope, locale: locale));
        await tester.pumpAndSettle();

        // when
        await tester.tap(find.text(l10n.settingsSourceCode));
        await tester.pumpAndSettle();

        // then
        expect(opener.opened, [
          Uri.parse('https://github.com/Al3x1n0/KeePassMobile'),
        ]);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(l10n.entryUrlNoApp),
          ),
          result ? findsNothing : findsOneWidget,
        );
      });
    }
    testWidgets('sorgente ${locale.languageCode}: risultato dopo smontaggio', (
      tester,
    ) async {
      viewport(tester, const Size(800, 3000));
      final completion = Completer<bool>();
      final scope = await newTestContainer(
        overrides: [
          urlOpenerProvider.overrideWithValue(
            _SourceCodeOpener(completion.future),
          ),
        ],
      );
      await tester.pumpWidget(app(scope, locale: locale));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(lookupAppLocalizations(locale).settingsSourceCode),
      );
      await tester.pumpWidget(const SizedBox());
      completion.complete(false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
    for (final result in [true, false]) {
      testWidgets('privacy ${locale.languageCode}: apertura esterna $result', (
        tester,
      ) async {
        // given
        viewport(tester, const Size(800, 3000));
        final opener = _SourceCodeOpener(Future.value(result));
        final scope = await newTestContainer(
          overrides: [urlOpenerProvider.overrideWithValue(opener)],
        );
        final l10n = lookupAppLocalizations(locale);
        await tester.pumpWidget(app(scope, locale: locale));
        await tester.pumpAndSettle();

        // when
        await tester.tap(find.text(l10n.settingsPrivacyPolicy));
        await tester.pumpAndSettle();

        // then
        expect(opener.opened, [
          Uri.parse('https://al3x1n0.github.io/KeePassMobile/privacy/'),
        ]);
        expect(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(l10n.entryUrlNoApp),
          ),
          result ? findsNothing : findsOneWidget,
        );
      });
    }
    testWidgets('privacy ${locale.languageCode}: risultato dopo smontaggio', (
      tester,
    ) async {
      viewport(tester, const Size(800, 3000));
      final completion = Completer<bool>();
      final scope = await newTestContainer(
        overrides: [
          urlOpenerProvider.overrideWithValue(
            _SourceCodeOpener(completion.future),
          ),
        ],
      );
      await tester.pumpWidget(app(scope, locale: locale));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(lookupAppLocalizations(locale).settingsPrivacyPolicy),
      );
      await tester.pumpWidget(const SizedBox());
      completion.complete(false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('language sheet switches UI immediately and restores system', (
    tester,
  ) async {
    viewport(tester, const Size(800, 3000));
    tester.binding.platformDispatcher.localesTestValue = [const Locale('ro')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final scope = await container(version: Future.value('1.2.3'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: ref.watch(appLocaleProvider),
            localizationsDelegates: [
              ...GlobalMaterialLocalizations.delegates,
              ...AppLocalizations.localizationsDelegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final choice in ['Italiano', 'English', 'Italiano', 'Sistema']) {
      final label = scope.read(appLocaleProvider).languageCode == 'it'
          ? 'Lingua'
          : 'Language';
      await tester.scrollUntilVisible(find.text(label), 350);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice).last);
      await tester.pumpAndSettle();
      final italian = choice == 'Italiano';
      expect(find.text(italian ? 'Impostazioni' : 'Settings'), findsOneWidget);
      expect(
        scope.read(appSettingsProvider).languageCode,
        choice == 'Sistema'
            ? null
            : italian
            ? 'it'
            : 'en',
      );
      expect(
        AppSettingsRepository(scope.read(sharedPreferencesProvider))
            .load()
            .languageCode,
        scope.read(appSettingsProvider).languageCode,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  Finder section(String title) => find.byWidgetPredicate(
    (widget) => widget is ExpandableSection && widget.title == title,
  );

  for (final locale in [const Locale('it'), const Locale('en')]) {
    final l10n = lookupAppLocalizations(locale);
    for (final databaseOpen in [false, true]) {
      testWidgets(
        'Impostazioni ${locale.languageCode}: riquadri ordinati ed espansi con database ${databaseOpen ? "aperto" : "chiuso"}',
        (tester) async {
          // given
          viewport(tester, const Size(800, 3000));
          final scope = await container(
            databaseOpen: databaseOpen,
            version: Future.value('1.2.3'),
          );

          // when
          await tester.pumpWidget(
            app(scope, locale: locale, databaseOpen: databaseOpen),
          );
          await tester.pumpAndSettle();

          // then
          final titles = [
            if (databaseOpen) l10n.settingsDatabase,
            l10n.settingsSecurity,
            l10n.settingsDisplay,
            l10n.settingsFiles,
            l10n.settingsAbout,
          ];
          expect(
            tester
                .widgetList<ExpandableSection>(find.byType(ExpandableSection))
                .map((widget) => widget.title),
            titles,
          );
          final contents = {
            if (databaseOpen) l10n.settingsDatabase: l10n.dbSettingsTitle,
            l10n.settingsSecurity: l10n.settingsClipboardTimeout,
            l10n.settingsDisplay: l10n.settingsMaskPassword,
            l10n.settingsFiles: l10n.settingsRememberRecentFiles,
            l10n.settingsAbout: l10n.settingsAppVersion,
          };
          for (final entry in contents.entries) {
            expect(
              find
                  .descendant(
                    of: section(entry.key),
                    matching: find.text(entry.value),
                  )
                  .hitTestable(),
              findsOneWidget,
            );
          }
          expect(
            section(l10n.settingsDatabase),
            databaseOpen ? findsOneWidget : findsNothing,
          );
          final about = section(l10n.settingsAbout);
          final context = tester.element(about);
          final licenses = MaterialLocalizations.of(context).licensesPageTitle;
          expect(
            find.descendant(of: about, matching: find.text(licenses)),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: section(l10n.settingsFiles),
              matching: find.text(licenses),
            ),
            findsNothing,
          );
          expect(
            tester.getTopLeft(find.text(licenses)).dy,
            lessThan(tester.getTopLeft(find.text(l10n.settingsAppVersion)).dy),
          );
          final sourceTile = find.widgetWithText(
            ListTile,
            l10n.settingsSourceCode,
          );
          expect(
            find.descendant(of: about, matching: sourceTile),
            findsOneWidget,
          );
          expect(
            find.descendant(of: sourceTile, matching: find.text('GitHub')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: sourceTile,
              matching: find.byIcon(Icons.open_in_new),
            ),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(find.text(licenses)).dy,
            lessThan(tester.getTopLeft(sourceTile).dy),
          );
          expect(
            tester.getTopLeft(sourceTile).dy,
            lessThan(tester.getTopLeft(find.text(l10n.settingsAppVersion)).dy),
          );
          expect(
            tester
                .widgetList<ListTile>(
                  find.descendant(of: about, matching: find.byType(ListTile)),
                )
                .last
                .title,
            isA<Text>().having(
              (text) => text.data,
              'title',
              l10n.settingsAppVersion,
            ),
          );
          final privacyTile = find.widgetWithText(
            ListTile,
            l10n.settingsPrivacyPolicy,
          );
          expect(
            find.descendant(of: about, matching: privacyTile),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(sourceTile).dy,
            lessThan(tester.getTopLeft(privacyTile).dy),
          );
          expect(
            tester.getTopLeft(privacyTile).dy,
            lessThan(tester.getTopLeft(find.text(l10n.settingsAppVersion)).dy),
          );
          final versionTile = find.widgetWithText(
            ListTile,
            l10n.settingsAppVersion,
          );
          final tile = tester.widget<ListTile>(versionTile);
          expect(tile.onTap, isNull);
          expect(tile.onLongPress, isNull);
          expect(
            find.descendant(of: versionTile, matching: find.text('1.2.3')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: versionTile, matching: find.byType(Icon)),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final locale in [const Locale('it'), const Locale('en')]) {
    testWidgets(
      'blocco in background ${locale.languageCode}: toggle localizzato e persistito con testo doppio',
      (tester) async {
        viewport(tester, const Size(320, 640));
        final scope = await container();
        final l10n = lookupAppLocalizations(locale);
        await tester.pumpWidget(app(scope, locale: locale, textScale: 2));
        await tester.pumpAndSettle();
        final toggle = find.widgetWithText(
          SwitchListTile,
          l10n.settingsLockInBackground,
        );
        await tester.scrollUntilVisible(toggle, 150);
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
        expect(find.text(l10n.settingsLockInBackgroundHint), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(toggle);
        await tester.pumpAndSettle();

        expect(scope.read(appSettingsProvider).lockInBackground, isTrue);
        expect(
          scope
              .read(sharedPreferencesProvider)
              .getBool('settings.lock_in_background'),
          isTrue,
        );
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'i riquadri si richiudono separatamente e ripartono espansi alla riapertura',
    (tester) async {
      // given
      viewport(tester, const Size(800, 3000));
      final scope = await container(version: Future.value('1.2.3'));
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpWidget(app(scope, settingsKey: const ValueKey('prima')));
      await tester.pumpAndSettle();

      // when
      await tester.tap(find.text(l10n.settingsSecurity));
      await tester.pumpAndSettle();

      // then
      expect(
        find.text(l10n.settingsClipboardTimeout).hitTestable(),
        findsNothing,
      );
      expect(
        find.text(l10n.settingsMaskPassword).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.text(l10n.settingsRememberRecentFiles).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text(l10n.settingsAbout));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsAppVersion).hitTestable(), findsNothing);
      expect(
        find.text(l10n.settingsMaskPassword).hitTestable(),
        findsOneWidget,
      );

      await tester.pumpWidget(
        app(scope, settingsKey: const ValueKey('seconda')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.settingsClipboardTimeout).hitTestable(),
        findsOneWidget,
      );
      expect(find.text(l10n.settingsAppVersion).hitTestable(), findsOneWidget);
    },
  );

  testWidgets('un riquadro resta chiuso dopo aver scorso le Impostazioni', (
    tester,
  ) async {
    // given
    viewport(tester, const Size(360, 640));
    final scope = await container(version: Future.value('1.2.3'));
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.pumpWidget(app(scope));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.settingsSecurity));
    await tester.pumpAndSettle();

    // when
    await tester.scrollUntilVisible(find.text(l10n.settingsAbout), 250);
    await tester.ensureVisible(find.text(l10n.settingsAbout));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();

    // then
    expect(find.text(l10n.settingsSecurity).hitTestable(), findsOneWidget);
    expect(
      find.text(l10n.settingsClipboardTimeout).hitTestable(),
      findsNothing,
    );
    await tester.tap(find.text(l10n.settingsSecurity));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.settingsClipboardTimeout).hitTestable(),
      findsOneWidget,
    );
  });

  for (final locale in [const Locale('it'), const Locale('en')]) {
    for (final value in ['123.456.789', null]) {
      testWidgets(
        'versione ${locale.languageCode} ${value ?? "non disponibile"}: riga e titolo restano fermi durante il caricamento',
        (tester) async {
          // given
          viewport(tester, const Size(320, 640));
          final result = Completer<String?>();
          final scope = await container(version: result.future);
          final l10n = lookupAppLocalizations(locale);
          await tester.pumpWidget(app(scope, locale: locale, textScale: 2));
          await tester.pumpAndSettle();
          final tile = find.widgetWithText(ListTile, l10n.settingsAppVersion);
          await tester.scrollUntilVisible(tile, 250);
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          final before = tester.getRect(tile);
          final titleBefore = tester.getRect(
            find.text(l10n.settingsAppVersion),
          );
          expect(
            find.descendant(of: tile, matching: find.text('—')),
            findsOneWidget,
          );

          // when
          result.complete(value);
          await tester.pumpAndSettle();

          // then
          expect(tester.getRect(tile), before);
          expect(
            tester.getRect(find.text(l10n.settingsAppVersion)),
            titleBefore,
          );
          expect(
            find.descendant(of: tile, matching: find.text(value ?? '—')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'il canale nativo assente lascia la versione non disponibile senza errori',
    (tester) async {
      // given
      final scope = await container();
      final l10n = lookupAppLocalizations(const Locale('en'));

      // when
      await tester.pumpWidget(app(scope));
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(ListTile, l10n.settingsAppVersion);
      await tester.scrollUntilVisible(tile, 250);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();

      // then
      expect(
        find.descendant(of: tile, matching: find.text('—')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final locale in [const Locale('it'), const Locale('en')]) {
    testWidgets(
      'Impostazioni ${locale.languageCode}: testo doppio a 320 dp senza overflow',
      (tester) async {
        // given
        viewport(tester, const Size(320, 640));
        final scope = await container(version: Future.value('1.2.3'));
        final l10n = lookupAppLocalizations(locale);

        // when
        await tester.pumpWidget(app(scope, locale: locale, textScale: 2));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final title in [
          l10n.settingsDisplay,
          l10n.settingsFiles,
          l10n.settingsAbout,
          l10n.settingsAppVersion,
        ]) {
          await tester.scrollUntilVisible(find.text(title), 200);
          await tester.ensureVisible(find.text(title));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }

        // then
        expect(
          find.text(l10n.settingsAppVersion).hitTestable(),
          findsOneWidget,
        );
        expect(find.text('1.2.3').hitTestable(), findsOneWidget);
      },
    );
  }
}
