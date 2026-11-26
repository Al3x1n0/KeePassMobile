import 'package:keepass_mobile/app/router.dart';
import 'package:keepass_mobile/app/routes.dart';
import 'package:keepass_mobile/features/password_generator/generator_view.dart';
import 'package:keepass_mobile/shared/database/database_errors.dart';

import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/autofill/autofill_app.dart';
import 'package:keepass_mobile/features/entry_edit/entry_edit_view.dart';
import 'package:keepass_mobile/features/autofill/autofill_channel.dart';
import 'package:keepass_mobile/features/autofill/autofill_pick_view_model.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/features/settings/settings_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/security/device_security.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kpasslib/kpasslib.dart';

import '../helpers/fake_app_security.dart';
import '../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final l10n = lookupAppLocalizations(const Locale('en'));
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late File databaseFile;
  late List<MethodCall> calls;
  late FakeAppSecurity security;

  setUp(() async {
    final db = newTestDatabase();
    addTestEntry(
      db,
      db.root,
      {
        EntryFields.title: 'Esempio',
        EntryFields.url: 'https://www.example.com',
        EntryFields.userName: 'mario',
        EntryFields.password: 'segreto-1',
      },
      protectedKeys: {EntryFields.password},
    );
    addTestEntry(db, db.root, {
      EntryFields.title: 'Altro',
      EntryFields.url: 'https://other.org',
      EntryFields.userName: 'luigi',
      EntryFields.password: 'segreto-2',
    });
    addTestEntry(db, db.root, {
      EntryFields.title: 'Messaggi',
      'AndroidApp1': 'androidapp://com.example.messenger',
      EntryFields.userName: 'utente-app',
      EntryFields.password: 'segreto-app',
    });
    (databaseFile, _) = await saveToTempFile(db);
    calls = [];
    security = FakeAppSecurity();
    messenger.setMockMethodCallHandler(AutofillChannel.channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(
    () => messenger.setMockMethodCallHandler(AutofillChannel.channel, null),
  );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(AutofillApp)));

  /// Avvia la compilazione automatica con un solo database recente (lo
  /// sblocco si apre da solo) e sblocca con la password.
  Future<SharedPreferences> start(
    WidgetTester tester,
    AutofillRequest request, {
    Map<String, Object> preferences = const {},
  }) async {
    FakeClipboard(tester.binding);
    SharedPreferences.setMockInitialValues({
      ...preferences,
      RecentFilesRepository.storageKey: [
        jsonEncode(RecentFile(database: fileRefOf(databaseFile)).toJson()),
      ],
    });
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...autofillOverrides(prefs, request),
          appSecurityProvider.overrideWithValue(security),
        ],
        child: const AutofillApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(
      tester,
      find.text(request.save ? l10n.autofillSaveTitle : l10n.autofillPickTitle),
    );
    // Fine della transizione: la schermata di sblocco esce dall'albero.
    await tester.pumpAndSettle();
    return prefs;
  }

  Future<Map<Object?, Object?>> filled(WidgetTester tester) async {
    for (var i = 0; i < 250 && !calls.any((c) => c.method == 'fill'); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    return calls.singleWhere((c) => c.method == 'fill').arguments as Map;
  }

  Future<void> createFromPicker(WidgetTester tester) async {
    await start(
      tester,
      const AutofillRequest(
        packageName: 'com.example.newapp',
        signingIds: ['synthetic-signer'],
      ),
    );
    await tester.tap(find.text(l10n.entryEditTitleNew));
    await tester.pumpAndSettle();
    final db = containerOf(tester).read(databaseSessionProvider)!.database;
    await tester.tap(find.text(db.root.name));
    await tester.pumpAndSettle();
  }

  testWidgets('creazione: generatore, salvataggio, conferma e compilazione', (
    tester,
  ) async {
    await createFromPicker(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.entryTitle),
      'Synthetic new login',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.entryUserName),
      'synthetic-user',
    );
    await tester.tap(find.byTooltip(l10n.entryEditGenerate));
    await tester.pumpAndSettle();
    expect(find.byType(GeneratorView), findsOneWidget);
    final generated = tester
        .widget<Text>(find.byKey(GeneratorView.valueKey))
        .data!;
    await tester.tap(find.text(l10n.generatorUse));
    await tester.pumpAndSettle();
    expect(find.byType(EntryEditView), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.entryEditSave));
    await pumpUntilFound(tester, find.text(l10n.autofillFillOnly));
    await tester.tap(find.text(l10n.autofillFillOnly));
    final values = await filled(tester);
    await tester.pumpAndSettle();
    expect(values, {'userName': 'synthetic-user', 'password': generated});
    expect(containerOf(tester).read(databaseSessionProvider), isNull);
    expect(containerOf(tester).read(autofillDoneProvider), isTrue);
    final saved = await tester.runAsync(() => reopenFile(databaseFile));
    expect(
      saved!.root.allEntries.any((e) => entryTitle(e) == 'Synthetic new login'),
      isTrue,
    );
  });

  testWidgets('blocco durante creazione torna alla scelta file', (
    tester,
  ) async {
    await createFromPicker(tester);
    final container = containerOf(tester);
    container.read(databaseSessionProvider.notifier).lock();
    await tester.pumpAndSettle();
    expect(
      container.read(routerProvider).routeInformationProvider.value.uri.path,
      AppRoutes.fileSelect,
    );
    expect(find.byType(EntryEditView), findsNothing);
  });

  testWidgets('route creazione rifiuta extra assente o non valido', (
    tester,
  ) async {
    await start(
      tester,
      const AutofillRequest(
        packageName: 'com.example.newapp',
        signingIds: ['synthetic-signer'],
      ),
    );
    final router = containerOf(tester).read(routerProvider);
    for (final extra in [null, 'invalid']) {
      router.go('/autofill/new', extra: extra);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, autofillPickRoute);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('voce salvata senza campi richiesti mostra errore dedicato', (
    tester,
  ) async {
    await createFromPicker(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.entryTitle),
      'Synthetic empty login',
    );
    await tester.tap(find.byTooltip(l10n.entryEditSave));
    await pumpUntilFound(tester, find.text(l10n.autofillFillOnly));
    await tester.tap(find.text(l10n.autofillFillOnly));
    await tester.pumpAndSettle();
    expect(find.text(l10n.autofillNoFillableFields), findsOneWidget);
    expect(find.text(l10n.errorSaveFailed), findsNothing);
    final container = containerOf(tester);
    expect(container.read(databaseSessionProvider), isNotNull);
    expect(container.read(autofillDoneProvider), isFalse);
    expect(calls.where((c) => c.method == 'fill'), isEmpty);
    for (final locale in ['it', 'en']) {
      final translated = lookupAppLocalizations(Locale(locale));
      expect(
        describeSaveError(
          translated,
          const AutofillNoFillableFieldsException(),
        ),
        translated.autofillNoFillableFields,
      );
    }
  });

  testWidgets('creazione sito confermato: URL HTTPS e titolo vuoto', (
    tester,
  ) async {
    await start(
      tester,
      const AutofillRequest(
        packageName: 'com.example.browser',
        webDomain: 'www.example.com',
        signingIds: ['synthetic-signer'],
      ),
    );
    containerOf(tester).read(autofillUseDomainProvider.notifier).useOnce();
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.entryEditTitleNew));
    await tester.pumpAndSettle();
    final db = containerOf(tester).read(databaseSessionProvider)!.database;
    await tester.tap(find.text(db.root.name));
    await tester.pumpAndSettle();
    final editor = tester.widget<EntryEditView>(find.byType(EntryEditView));
    expect(editor.initialDraft!.title, isEmpty);
    expect(editor.initialDraft!.url, 'https://www.example.com');
    expect(editor.initialDraft!.custom, isEmpty);
  });

  testWidgets(
    'creazione app: package in URL e titolo vuoto, dominio non confermato escluso',
    (tester) async {
      await start(
        tester,
        const AutofillRequest(
          packageName: 'com.example.newapp',
          webDomain: 'unconfirmed.example',
          signingIds: ['synthetic-signer'],
        ),
      );
      await tester.tap(find.text(l10n.entryEditTitleNew));
      await tester.pumpAndSettle();
      final db = containerOf(tester).read(databaseSessionProvider)!.database;
      await tester.tap(find.text(db.root.name));
      await tester.pumpAndSettle();
      final editor = tester.widget<EntryEditView>(find.byType(EntryEditView));
      expect(editor.initialDraft!.title, isEmpty);
      expect(editor.initialDraft!.url, 'androidapp://com.example.newapp');
      expect(
        editor.initialDraft!.custom.single.value,
        'androidapp://com.example.newapp',
      );
    },
  );

  testWidgets(
    'nuova voce disponibile senza corrispondenze e scelta annullabile',
    (tester) async {
      await start(
        tester,
        const AutofillRequest(
          packageName: 'com.example.newapp',
          signingIds: ['synthetic-signer'],
        ),
      );
      expect(find.text(l10n.autofillNoMatches), findsOneWidget);
      await tester.tap(find.text(l10n.entryEditTitleNew));
      await tester.pumpAndSettle();
      expect(find.text(l10n.generatorChooseGroup), findsOneWidget);
      final container = containerOf(tester);
      expect(container.read(databaseSessionProvider), isNotNull);
      Navigator.of(tester.element(find.text(l10n.generatorChooseGroup))).pop();
      await tester.pumpAndSettle();
      expect(find.text(l10n.autofillPickTitle), findsOneWidget);
      expect(calls.where((c) => c.method == 'fill'), isEmpty);
    },
  );

  testWidgets(
    'browser: la conferma segue una rotazione verificata, poi compila e chiude',
    (tester) async {
      await start(
        tester,
        const AutofillRequest(
          packageName: 'com.android.chrome',
          webDomain: 'www.example.com',
          signingIds: ['signer-one', 'signer-two'],
        ),
        preferences: {
          AutofillTrustRepository.storageKey: [
            jsonEncode([
              'site',
              'www.example.com',
              'com.android.chrome',
              'signer-one',
            ]),
          ],
        },
      );

      expect(find.text('Esempio'), findsOneWidget);
      expect(find.text('Altro'), findsNothing);

      await tester.tap(find.text('Esempio'));
      final values = await filled(tester);
      await tester.pumpAndSettle();

      expect(values, {'userName': 'mario', 'password': 'segreto-1'});
      final container = containerOf(tester);
      expect(container.read(databaseSessionProvider), isNull);
      expect(container.read(autofillDoneProvider), isTrue);
      // Il motore della compilazione automatica non tocca la notifica.
      expect(security.notification, isNull);
      expect(security.permissionRequests, 0);
    },
  );

  testWidgets(
    'app che dichiara un dominio: chiede conferma per la firma corrente',
    (tester) async {
      final prefs = await start(
        tester,
        const AutofillRequest(
          packageName: 'com.example.reader',
          webDomain: 'www.example.com',
          signingIds: ['signer-new'],
        ),
        preferences: {
          'autofill.trusted_links': ['www.example.com + com.example.reader'],
          AutofillTrustRepository.storageKey: [
            jsonEncode([
              'site',
              'www.example.com',
              'com.example.reader',
              'signer-old',
            ]),
          ],
        },
      );

      expect(
        find.text(
          l10n.autofillDomainWarning('com.example.reader', 'www.example.com'),
        ),
        findsOneWidget,
      );
      expect(find.text('Esempio'), findsNothing);
      expect(find.text(l10n.autofillNoMatches), findsOneWidget);
      expect(find.text(l10n.entryEditTitleNew), findsOneWidget);

      await tester.tap(find.text(l10n.autofillUseDomainAlways));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();

      expect(find.text('Esempio'), findsOneWidget);
      expect(prefs.getStringList(AutofillTrustRepository.storageKey), [
        jsonEncode([
          'site',
          'www.example.com',
          'com.example.reader',
          'signer-new',
        ]),
        jsonEncode([
          'site',
          'www.example.com',
          'com.example.reader',
          'signer-old',
        ]),
      ]);
    },
  );

  testWidgets(
    'associazione KDBX storica: conferma nuova firma prima del fill',
    (tester) async {
      final before = databaseFile.readAsBytesSync();
      const app = 'com.example.messenger';
      final old = jsonEncode(['app', app, 'firma-precedente']);
      final prefs = await start(
        tester,
        const AutofillRequest(packageName: app, signingIds: ['nuova-firma']),
        preferences: {
          AutofillTrustRepository.storageKey: [old],
        },
      );

      await tester.tap(find.text('Messaggi'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(l10n.autofillAppIdentityWarning('Messaggi', app)),
        findsOneWidget,
      );
      expect(calls.where((call) => call.method == 'fill'), isEmpty);
      expect(prefs.getStringList(AutofillTrustRepository.storageKey), [old]);

      await tester.tap(find.text(l10n.autofillFillAndRememberApp));
      expect(await filled(tester), {
        'userName': 'utente-app',
        'password': 'segreto-app',
      });
      expect(prefs.getStringList(AutofillTrustRepository.storageKey), [
        old,
        jsonEncode(['app', app, 'nuova-firma']),
      ]);
      expect(databaseFile.readAsBytesSync(), before);
    },
  );

  testWidgets('la firma storica verificata vale dopo una rotazione dell’app', (
    tester,
  ) async {
    const app = 'com.example.messenger';
    await start(
      tester,
      const AutofillRequest(
        packageName: app,
        signingIds: ['firma-valida', 'firma-ruotata'],
      ),
      preferences: {
        AutofillTrustRepository.storageKey: [
          jsonEncode(['app', app, 'firma-valida']),
        ],
      },
    );

    await tester.tap(find.text('Messaggi'));
    expect(await filled(tester), {
      'userName': 'utente-app',
      'password': 'segreto-app',
    });
  });

  testWidgets('un sottodominio richiede conferma prima della compilazione', (
    tester,
  ) async {
    await start(
      tester,
      const AutofillRequest(
        packageName: 'com.example.reader',
        webDomain: 'login.www.example.com',
      ),
    );
    await tester.tap(find.text(l10n.autofillUseDomainOnce));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esempio'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        l10n.autofillApproximateBody(
          'Esempio',
          l10n.autofillSiteInApp('login.www.example.com', 'com.example.reader'),
        ),
      ),
      findsOneWidget,
    );
    expect(calls.where((call) => call.method == 'fill'), isEmpty);
    await tester.tap(find.text(l10n.autofillFillOnly));
    expect(await filled(tester), {
      'userName': 'mario',
      'password': 'segreto-1',
    });
  });

  testWidgets(
    'voce trovata con la ricerca: "Compila e ricorda" aggiunge AndroidApp1 e salva',
    (tester) async {
      await start(
        tester,
        const AutofillRequest(packageName: 'com.example.app'),
      );
      expect(find.text(l10n.autofillNoMatches), findsOneWidget);
      expect(find.text(l10n.entryEditTitleNew), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Altro');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Altro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.autofillFillAndRemember));
      final values = await filled(tester);

      expect(values, {'userName': 'luigi', 'password': 'segreto-2'});
      final saved = (await tester.runAsync(() => reopenFile(databaseFile)))!;
      final entry = saved.root.allEntries.singleWhere(
        (e) => entryTitle(e) == 'Altro',
      );
      expect(entry.fields['AndroidApp1']?.text, 'androidapp://com.example.app');
    },
  );

  testWidgets('"Compila soltanto": nessuna modifica al file', (tester) async {
    final before = databaseFile.readAsBytesSync();
    await start(tester, const AutofillRequest(packageName: 'com.example.app'));

    await tester.enterText(find.byType(TextField), 'Altro');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Altro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.autofillFillOnly));
    await filled(tester);

    expect(databaseFile.readAsBytesSync(), before);
  });

  testWidgets('chiudi: risposta annullata e database chiuso', (tester) async {
    await start(tester, const AutofillRequest(packageName: 'com.example.app'));

    await tester.tap(find.byTooltip(l10n.autofillClose));
    await tester.runAsync(pumpEventQueue);
    await tester.pump();

    expect(calls.map((c) => c.method), contains('cancel'));
    expect(containerOf(tester).read(databaseSessionProvider), isNull);
  });

  testWidgets('salvataggio richiede conferma e crea una nuova voce protetta', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(AutofillChannel.channel, (call) async {
      calls.add(call);
      return call.method == 'takeSavePassword' ? 'test-secret' : null;
    });
    final prefs = await start(
      tester,
      const AutofillRequest(
        packageName: 'com.example.app',
        webDomain: 'untrusted.example',
        signingIds: ['test-signer'],
        save: true,
        userName: 'test-user',
      ),
    );
    expect(find.text('com.example.app'), findsOneWidget);
    expect(find.text('test-secret'), findsNothing);
    expect(calls.where((c) => c.method == 'takeSavePassword'), isEmpty);
    expect(prefs.getStringList(AutofillTrustRepository.storageKey), isNull);
    final confirm = find.text(l10n.autofillSaveAndRememberApp);
    await tester.scrollUntilVisible(confirm, 150);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    for (var i = 0; i < 250 && !calls.any((c) => c.method == 'cancel'); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(calls.where((c) => c.method == 'takeSavePassword'), hasLength(1));
    expect(prefs.getStringList(AutofillTrustRepository.storageKey), [
      jsonEncode(['app', 'com.example.app', 'test-signer']),
    ]);
    final saved = (await tester.runAsync(() => reopenFile(databaseFile)))!;
    final entry = saved.root.allEntries.singleWhere(
      (e) => entryTitle(e) == 'com.example.app',
    );
    expect(entry.fields[EntryFields.userName]?.text, 'test-user');
    expect(entry.fields[EntryFields.password]?.text, 'test-secret');
    expect(entry.fields[EntryFields.password], isA<ProtectedTextField>());
    expect(entry.fields['AndroidApp1']?.text, 'androidapp://com.example.app');
    expect(entry.fields[EntryFields.url]?.text, isEmpty);
  });

  testWidgets(
    'annullamento non richiede la password e non modifica il database',
    (tester) async {
      final before = databaseFile.readAsBytesSync();
      await start(
        tester,
        const AutofillRequest(packageName: 'com.example.app', save: true),
      );
      await tester.ensureVisible(find.text(l10n.autofillClose));
      await tester.tap(find.text(l10n.autofillClose));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'takeSavePassword'), isEmpty);
      expect(databaseFile.readAsBytesSync(), before);
    },
  );

  testWidgets('il blocco annulla la richiesta di salvataggio', (tester) async {
    await start(
      tester,
      const AutofillRequest(packageName: 'com.example.app', save: true),
    );
    containerOf(tester).read(databaseSessionProvider.notifier).lock();
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'takeSavePassword'), isEmpty);
    expect(calls.where((c) => c.method == 'cancel'), hasLength(1));
  });

  testWidgets('impostazioni: stato del servizio e scelta di sistema', (
    tester,
  ) async {
    final settingsCalls = <String>[];
    messenger.setMockMethodCallHandler(AutofillSettings.channel, (call) async {
      settingsCalls.add(call.method);
      return call.method == 'status'
          ? {'supported': true, 'enabled': false}
          : true;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(AutofillSettings.channel, null),
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(l10n.settingsAutofill));
    expect(find.text(l10n.settingsAutofillOff), findsOneWidget);
    await tester.tap(find.text(l10n.settingsAutofill));
    await tester.pump();

    expect(settingsCalls, ['status', 'openSettings']);
  });

  for (final broken in [false, true]) {
    testWidgets(
      'autofill riferimenti: risoluzione o rifiuto senza associazione ($broken)',
      (tester) async {
        final db = await tester.runAsync(() => reopenFile(databaseFile));
        final entry = db!.root.allEntries.firstWhere(
          (e) => entryTitle(e) == 'Esempio',
        );
        entry.fields[EntryFields.userName] = PlainTextField('{REF:U@T:Altro}');
        entry.fields[EntryFields.password] = PlainTextField(
          broken ? '{S:assente}' : '{REF:P@T:Altro}',
        );
        await tester.runAsync(
          () async => databaseFile.writeAsBytes(await db.save()),
        );
        await start(
          tester,
          const AutofillRequest(packageName: 'com.example.app'),
        );
        final container = containerOf(tester);
        await tester.runAsync(
          () => container
              .read(autofillPickViewModelProvider.notifier)
              .fill(entry.uuid, choice: AutofillChoice.rememberEntry),
        );
        await tester.pumpAndSettle();
        if (broken) {
          expect(calls.where((c) => c.method == 'fill'), isEmpty);
          expect(container.read(databaseSessionProvider), isNotNull);
          expect(find.text(l10n.errorFieldReference), findsOneWidget);
          final saved = (await tester.runAsync(
            () => reopenFile(databaseFile),
          ))!;
          expect(
            saved.root.allEntries
                .firstWhere((e) => entryTitle(e) == 'Esempio')
                .fields
                .containsKey('AndroidApp1'),
            isFalse,
          );
        } else {
          expect(await filled(tester), {
            'userName': 'luigi',
            'password': 'segreto-2',
          });
          expect(container.read(databaseSessionProvider), isNull);
          final saved = (await tester.runAsync(
            () => reopenFile(databaseFile),
          ))!;
          expect(
            saved.root.allEntries
                .firstWhere((e) => entryTitle(e) == 'Esempio')
                .fields[EntryFields.password]!
                .text,
            '{REF:P@T:Altro}',
          );
        }
      },
    );
  }
}
