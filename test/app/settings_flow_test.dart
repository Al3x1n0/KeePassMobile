import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show LicenseEntry, LicenseRegistry;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/app/router.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/app/database_navigation_bar.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/entry/totp_tile.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/features/password_generator/generator_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/external_change.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:keepass_mobile/shared/storage/remote_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/memory_cache_documents.dart';
import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File file;
  late SharedPreferences prefs;

  setUp(() async {
    final db = newTestDatabase();
    final bank = db.createGroup(parent: db.root, name: 'Banca');
    addTestEntry(
      db,
      bank,
      {
        EntryFields.title: 'Conto',
        EntryFields.userName: 'cliente',
        EntryFields.password: 'pin-123',
        'otp': 'otpauth://totp/x?secret=JBSWY3DPEHPK3PXP',
      },
      protectedKeys: {EntryFields.password},
    );
    final dir = Directory.systemTemp.createTempSync('keepass_mobile_settings');
    file = File('${dir.path}/prova.kdbx')..writeAsBytesSync(await db.save());
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(),
    RemoteCacheStore? remoteCache,
  }) async {
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        jsonEncode(RecentFile(database: fileRefOf(file)).toJson()),
      ],
    });
    prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.runAsync(() => AppSettingsRepository(prefs).save(settings));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          if (remoteCache != null)
            remoteCacheStoreProvider.overrideWithValue(remoteCache),
          totpClockProvider.overrideWithValue(
            () => DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true),
          ),
        ],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unlock(WidgetTester tester) async {
    await tester.tap(find.text('prova.kdbx'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.text('Banca'));
    await tester.pumpAndSettle();
  }

  void expectNoKeyboardLearning(WidgetTester tester) {
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, isNotEmpty);
    for (final field in fields) {
      expect(field.enableIMEPersonalizedLearning, isFalse);
    }
  }

  testWidgets(
    'cambio chiave richiede password attuale e rifiuta quella errata',
    (tester) async {
      await pumpApp(tester);
      await unlock(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.text('Banca')),
      );
      container.read(routerProvider).push(AppRoutes.changeMasterKey);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(3));
      await tester.enterText(fields.at(1), 'nuova');
      await tester.enterText(fields.at(2), 'nuova');
      await tester.ensureVisible(find.text(l10n.changeKeyButton));
      await tester.tap(find.text(l10n.changeKeyButton));
      await tester.pumpAndSettle();
      expect(find.text(l10n.changeKeyCurrentRequired), findsOneWidget);
      await tester.enterText(fields.first, 'errata');
      await tester.ensureVisible(find.text(l10n.changeKeyButton));
      await tester.tap(find.text(l10n.changeKeyButton));
      await pumpUntilFound(
        tester,
        find.text(l10n.changeKeyWrongCurrentPassword),
      );
      await tester.enterText(fields.first, testMasterKey);
      await tester.ensureVisible(find.text(l10n.changeKeyButton));
      await tester.tap(find.text(l10n.changeKeyButton));
      await pumpUntilFound(tester, find.text('Banca'));
      await tester.runAsync(
        () => openDatabase(data: bytesOf(file), password: 'nuova'),
      );
    },
  );

  Future<void> backGesture(
    WidgetTester tester,
    String method, {
    double progress = 0,
  }) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.backGesture.name,
      SystemChannels.backGesture.codec.encodeMethodCall(
        MethodCall(
          method,
          method == 'startBackGesture' || method == 'updateBackGestureProgress'
              ? {
                  'touchOffset': [5.0, 300.0],
                  'progress': progress,
                  'swipeEdge': 0,
                }
              : null,
        ),
      ),
      (_) {},
    );
  }

  for (final overlay in ['popup', 'sheet']) {
    testWidgets('Predictive Back chiude $overlay senza lasciare Banca', (
      tester,
    ) async {
      await pumpApp(tester);
      await unlock(tester);
      await tester.tap(find.text('Banca'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.text('Conto')),
      );
      final router = container.read(routerProvider);
      final location = router.state.uri;
      if (overlay == 'popup') {
        await tester.tap(find.byIcon(Icons.more_vert));
      } else {
        showModalBottomSheet<void>(
          context: tester.element(find.text('Conto')),
          useRootNavigator: true,
          builder: (_) =>
              const SizedBox(height: 100, child: Text('Predictive sheet')),
        );
      }
      await tester.pumpAndSettle();
      final observer = container.read(rootOverlayObserverProvider);
      expect(observer.hasOverlay, isTrue);
      // Un gesto annullato lascia intatti overlay e pagina.
      await backGesture(tester, 'startBackGesture');
      await backGesture(tester, 'updateBackGestureProgress', progress: 0.4);
      await backGesture(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(observer.hasOverlay, isTrue);
      expect(router.state.uri, location);
      // Il commit chiude solo l'overlay, anche se la pagina può fare pop.
      await backGesture(tester, 'startBackGesture');
      await backGesture(tester, 'updateBackGestureProgress', progress: 0.6);
      await backGesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(observer.hasOverlay, isFalse);
      expect(router.state.uri, location);
      expect(find.text('Conto'), findsOneWidget);
      expect(find.text('Predictive sheet'), findsNothing);
      // Senza overlay il successivo gesto conserva la navigazione nativa.
      await backGesture(tester, 'startBackGesture');
      await backGesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.database);
      expect(find.text('Banca'), findsOneWidget);
    });
  }

  testWidgets('Back chiude overlay prima della pagina e la selezione in Home', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip(l10n.settingsTitle));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await unlock(tester);
    await tester.longPress(find.text('Banca'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.text('Banca'), findsOneWidget);
    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Conto'), findsOneWidget);
    await tester.tap(find.text('Conto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final context = tester.element(find.text('Conto'));
    showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(title: Text('Dialog test')),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Dialog test'), findsNothing);
    expect(find.text('Conto'), findsOneWidget);
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const SizedBox(height: 100, child: Text('Sheet test')),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Sheet test'), findsNothing);
    expect(find.text('Conto'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Banca'), findsOneWidget);
  });

  testWidgets('apre la pagina delle licenze dalle impostazioni', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip(l10n.settingsTitle));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).last);
    final title = MaterialLocalizations.of(context).licensesPageTitle;
    await tester.scrollUntilVisible(find.text(title), 200);
    await tester.ensureVisible(find.text(title));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LicensePage), findsOneWidget);
    LicenseEntry? found;
    Object? failure;
    LicenseRegistry.licenses
        .firstWhere(
          (entry) => entry.packages.contains(
            'qr_scanner_offline_private / rust/rqrr-0.11.0/LICENSE-ISC',
          ),
        )
        .then<void>(
          (entry) {
            found = entry;
          },
          onError: (Object e) {
            failure = e;
          },
        );
    for (var i = 0; i < 100 && found == null && failure == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(failure, isNull);
    expect(found, isNotNull);
    expect(found!.paragraphs.any((p) => p.text.contains('Permission')), isTrue);
  });

  testWidgets('pulizia della cache disattivata richiede conferma', (
    tester,
  ) async {
    final cache = RemoteCacheStore(documents: MemoryCacheDocuments());
    const remote = FileRef(
      uri: 'https://example.test/test.kdbx',
      name: 'test.kdbx',
    );
    final bytes = file.readAsBytesSync();
    await cache.write(
      remote,
      bytes,
      previous: null,
      baseHash: fileHashOf(bytes),
      pending: false,
    );
    await pumpApp(
      tester,
      settings: const AppSettings(cacheRemoteFiles: false),
      remoteCache: cache,
    );
    await tester.tap(find.byTooltip(l10n.settingsTitle));
    await tester.pumpAndSettle();

    final clear = find.text(l10n.settingsRemoteCacheClear);
    await tester.scrollUntilVisible(clear, 200);
    await tester.ensureVisible(clear);
    await tester.pumpAndSettle();
    await tester.tap(clear);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(await cache.read(remote), isNotNull);

    await tester.tap(clear);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.entryDelete));
    await tester.pumpAndSettle();
    expect(await cache.read(remote), isNull);
    expect(find.text(l10n.settingsRemoteCacheClearDone), findsOneWidget);
  });

  testWidgets('tema: scelta e chiusura del pannello', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip(l10n.settingsTitle));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(l10n.settingsTheme), 200);
    await tester.ensureVisible(find.text(l10n.settingsTheme));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.settingsTheme));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(AppSettingsRepository(prefs).load().themeMode, ThemeMode.system);
    await tester.tap(find.text(l10n.settingsTheme));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.settingsThemeDark));
    await tester.pumpAndSettle();
    expect(AppSettingsRepository(prefs).load().themeMode, ThemeMode.dark);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets(
    'impostazioni a database chiuso: appunti senza "mai", scelta salvata',
    (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byTooltip(l10n.settingsTitle));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsTitle), findsOneWidget);

      await tester.tap(find.text(l10n.settingsSeconds(30)));
      await tester.pumpAndSettle();
      for (final s in [10, 15, 30, 60, 120, 180, 240]) {
        expect(find.text(l10n.settingsSeconds(s)), findsWidgets);
      }
      // "Mai" c'è solo nel blocco per inattività, non nel menu aperto.
      expect(find.text(l10n.settingsLockNever), findsNothing);

      await tester.tap(find.text(l10n.settingsSeconds(10)).last);
      await tester.pumpAndSettle();

      expect(
        AppSettingsRepository(prefs).load().clipboardTimeout,
        const Duration(seconds: 10),
      );
    },
  );

  testWidgets('blocco automatico: annulla e seleziona mai', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip(l10n.settingsTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.settingsLockTimeout));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    final original = AppSettingsRepository(prefs).load().lockTimeout;
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(AppSettingsRepository(prefs).load().lockTimeout, original);
    await tester.tap(find.text(l10n.settingsLockTimeout));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.settingsLockNever).last);
    await tester.pumpAndSettle();
    expect(AppSettingsRepository(prefs).load().lockTimeout, isNull);
  });

  testWidgets('"Ricorda file recenti" disattivato: l\'elenco si svuota', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip(l10n.settingsTitle));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(l10n.settingsRememberRecentFiles),
      200,
    );
    await tester.ensureVisible(find.text(l10n.settingsRememberRecentFiles));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.settingsRememberRecentFiles));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('prova.kdbx'), findsNothing);
    expect(find.text(l10n.fileSelectNoRecent), findsOneWidget);
  });

  testWidgets(
    'visualizzazione: password visibile, nome utente nascosto, TOTP nascosto',
    (tester) async {
      await pumpApp(
        tester,
        settings: const AppSettings(
          maskPassword: false,
          showUserNameInList: false,
        ),
      );
      await unlock(tester);

      await tester.tap(find.text('Banca'));
      await tester.pumpAndSettle();
      expect(find.text('Conto'), findsOneWidget);
      expect(find.text('cliente'), findsNothing);

      await tester.tap(find.text('Conto'));
      await tester.pumpAndSettle();
      expect(find.text('pin-123'), findsOneWidget);
      expect(find.text('cliente'), findsOneWidget);
      // Codice del secondo 59 della RFC 6238 nascosto.
      expect(find.text('••••••'), findsOneWidget);
    },
  );

  testWidgets(
    'tastiera senza apprendimento in sblocco, ricerca, modifica, generatore',
    (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('prova.kdbx'));
      await tester.pumpAndSettle();
      expectNoKeyboardLearning(tester);

      await tester.enterText(find.byType(TextField), testMasterKey);
      await tester.tap(find.text(l10n.unlockButton));
      await pumpUntilFound(tester, find.text('Banca'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(l10n.searchTitle));
      await tester.pumpAndSettle();
      expectNoKeyboardLearning(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conto'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.groupMore));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.entryEdit));
      await tester.pumpAndSettle();
      expectNoKeyboardLearning(tester);

      await tester.tap(find.byTooltip(l10n.entryEditGenerate));
      await tester.pumpAndSettle();
      expectNoKeyboardLearning(tester);
    },
  );

  for (final databaseOpen in [false, true]) {
    testWidgets(
      'impostazioni con database ${databaseOpen ? "aperto" : "chiuso"}: ultima voce accessibile oltre la barra',
      (tester) async {
        // given
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(bottom: 24);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        await pumpApp(tester);
        if (databaseOpen) await unlock(tester);
        await tester.tap(
          databaseOpen
              ? find.text(l10n.settingsTitle)
              : find.byTooltip(l10n.settingsTitle),
        );
        await tester.pumpAndSettle();
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
        expect(scaffold.extendBody, databaseOpen);
        expect(scaffold.bottomNavigationBar != null, databaseOpen);
        final list = find.byType(ListView);
        expect(tester.getRect(list).bottom, 640);
        if (!databaseOpen) {
          expect(
            tester.widget<ListView>(list).padding,
            const EdgeInsets.only(bottom: 24 + AppSpacing.m),
          );
        }

        // when
        final scrollable = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        );
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pumpAndSettle();

        // then: l'ultima riga e il comando delle licenze restano sopra la capsula.
        final context = tester.element(list);
        final licensesTitle = MaterialLocalizations.of(context)
            .licensesPageTitle;
        final lastTile = find.widgetWithText(ListTile, l10n.settingsAppVersion);
        final licenseTile = find.widgetWithText(ListTile, licensesTitle);
        final contentBottom = databaseOpen
            ? tester.getRect(find.byType(BackdropFilter)).top
            : 640 - 24;
        expect(
          tester.getRect(lastTile).bottom,
          lessThanOrEqualTo(contentBottom),
        );
        expect(tester.widget<ListTile>(lastTile).onTap, isNull);
        await tester.tap(licenseTile);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(LicensePage), findsOneWidget);
        expect(find.byType(DatabaseNavigationBar), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'barra di navigazione: Home, impostazioni e blocco del database',
    (tester) async {
      // given
      await pumpApp(tester);
      await unlock(tester);
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.localesTestValue = const [Locale('it')];
      addTearDown(dispatcher.clearLocalesTestValue);
      await tester.pumpAndSettle();
      final localizations = lookupAppLocalizations(const Locale('it'));

      final bar = find.byType(DatabaseNavigationBar);
      DatabaseNavigationBar navigation() =>
          tester.widget<DatabaseNavigationBar>(bar);
      Finder tab(String label) =>
          find.descendant(of: bar, matching: find.text(label));
      const selected = {WidgetState.selected};
      for (final theme in [buildLightTheme(), buildDarkTheme()]) {
        final blue = theme.floatingActionButtonTheme.backgroundColor;
        expect(blue, AppColors.blue);
        expect(
          theme.navigationBarTheme.iconTheme?.resolve(selected)?.color,
          blue,
        );
        expect(
          theme.navigationBarTheme.labelTextStyle?.resolve(selected)?.color,
          blue,
        );
      }
      for (final (label, enabled) in [
        ('Home', true),
        ('Genera', true),
        ('Controllo', true),
        (localizations.settingsTitle, true),
      ]) {
        final target = find.ancestor(
          of: tab(label),
          matching: find.byType(InkWell),
        );
        expect(tester.widget<InkWell>(target).onTap != null, enabled);
      }
      expect(navigation().settingsSelected, isFalse);
      await tester.tap(tab('Genera'));
      await tester.pumpAndSettle();
      expect(navigation().generatorSelected, isTrue);
      expect(find.byType(GeneratorView), findsOneWidget);
      await tester.tap(tab('Controllo'));
      await tester.pumpAndSettle();
      expect(navigation().checkSelected, isTrue);
      expect(navigation().generatorSelected, isFalse);
      expect(find.byType(GeneratorView), findsNothing);
      await tester.tap(tab('Home'));
      await tester.pumpAndSettle();
      expect(navigation().generatorSelected, isFalse);
      expect(navigation().settingsSelected, isFalse);
      expect(find.text('Banca'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip(localizations.settingsTitle),
        ),
        findsNothing,
      );

      // when: apre le impostazioni da un sottogruppo
      await tester.tap(find.text('Banca'));
      await tester.pumpAndSettle();
      await tester.tap(tab(localizations.settingsTitle));
      await tester.pumpAndSettle();

      // then: impostazioni esistenti, con la destinazione selezionata
      expect(find.text(localizations.settingsSecurity), findsOneWidget);
      expect(navigation().settingsSelected, isTrue);
      expect(find.byType(BackButton), findsNothing);

      // when: torna alla consultazione con Home o con Indietro di sistema
      await tester.tap(tab('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Conto'), findsOneWidget);
      expect(navigation().settingsSelected, isFalse);
      await tester.tap(tab(localizations.settingsTitle));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Conto'), findsOneWidget);
      await tester.tap(tab('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Banca'), findsOneWidget);

      // when: il database viene bloccato mentre sono aperte le impostazioni
      await tester.tap(tab(localizations.settingsTitle));
      await tester.pumpAndSettle();
      ProviderScope.containerOf(
        tester.element(bar),
        listen: false,
      ).read(databaseSessionProvider.notifier).lock();
      await tester.pumpAndSettle();

      // then: l'app torna alla scelta del file, senza barra del database
      expect(find.text(localizations.fileSelectTitle), findsOneWidget);
      expect(find.text('Banca'), findsNothing);
      expect(bar, findsNothing);
    },
  );
}
