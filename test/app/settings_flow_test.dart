import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show LicenseEntry, LicenseRegistry;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/entry/totp_tile.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
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
      await tester.tap(find.byTooltip(l10n.entryEdit));
      await tester.pumpAndSettle();
      expectNoKeyboardLearning(tester);

      await tester.tap(find.byTooltip(l10n.entryEditGenerate));
      await tester.pumpAndSettle();
      expectNoKeyboardLearning(tester);
    },
  );

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

      final bar = find.byType(NavigationBar);
      NavigationBar navigation() => tester.widget<NavigationBar>(bar);
      Finder tab(String label) =>
          find.descendant(of: bar, matching: find.text(label));
      final destinations = navigation().destinations
          .cast<NavigationDestination>();
      expect(destinations.map((item) => (item.label, item.enabled)), [
        ('Home', true),
        ('Genera', false),
        ('Controllo', false),
        (localizations.settingsTitle, true),
      ]);
      expect(navigation().selectedIndex, 0);
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
      expect(navigation().selectedIndex, 3);

      // when: torna alla consultazione con Home o con Indietro di sistema
      await tester.tap(tab('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Conto'), findsOneWidget);
      expect(navigation().selectedIndex, 0);
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
