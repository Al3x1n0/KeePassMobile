import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/autofill/autofill_app.dart';
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
    AutofillRequest request,
  ) async {
    FakeClipboard(tester.binding);
    SharedPreferences.setMockInitialValues({
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

  testWidgets(
    'browser: voce del sito proposta, compilazione e database chiuso',
    (tester) async {
      await start(
        tester,
        const AutofillRequest(
          packageName: 'com.android.chrome',
          webDomain: 'www.example.com',
          isBrowser: true,
        ),
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
    'app che dichiara un dominio: avviso e ricerca per app; "Usa sempre" ricorda la coppia',
    (tester) async {
      final prefs = await start(
        tester,
        const AutofillRequest(
          packageName: 'com.example.reader',
          webDomain: 'www.example.com',
        ),
      );

      expect(
        find.text(
          l10n.autofillDomainWarning('com.example.reader', 'www.example.com'),
        ),
        findsOneWidget,
      );
      expect(find.text('Esempio'), findsNothing);
      expect(find.text(l10n.autofillNoMatches), findsOneWidget);

      await tester.tap(find.text(l10n.autofillUseDomainAlways));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();

      expect(find.text('Esempio'), findsOneWidget);
      expect(prefs.getStringList(AutofillTrustRepository.storageKey), [
        'www.example.com + com.example.reader',
      ]);
    },
  );

  testWidgets(
    'voce trovata con la ricerca: "Compila e ricorda" aggiunge AndroidApp1 e salva',
    (tester) async {
      await start(
        tester,
        const AutofillRequest(packageName: 'com.example.app'),
      );
      expect(find.text(l10n.autofillNoMatches), findsOneWidget);

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
    await start(
      tester,
      const AutofillRequest(
        packageName: 'com.example.app',
        webDomain: 'untrusted.example',
        save: true,
        userName: 'test-user',
      ),
    );
    expect(find.text('com.example.app'), findsOneWidget);
    expect(find.text('test-secret'), findsNothing);
    expect(calls.where((c) => c.method == 'takeSavePassword'), isEmpty);
    await tester.ensureVisible(find.text(l10n.autofillSaveConfirm));
    await tester.tap(find.text(l10n.autofillSaveConfirm));
    for (var i = 0; i < 250 && !calls.any((c) => c.method == 'cancel'); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(calls.where((c) => c.method == 'takeSavePassword'), hasLength(1));
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
              .fill(entry.uuid, remember: true),
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
