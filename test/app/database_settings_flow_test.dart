import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_create_storage.dart';
import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File file;

  setUp(() async {
    final db = newTestDatabase();
    db.header.kdfSettings = const AesKdfSettings(rounds: 1000);
    db.createGroup(parent: db.root, name: 'Banca');
    final dir = Directory.systemTemp.createTempSync('keepass_mobile_dbset');
    addTearDown(() => dir.deleteSync(recursive: true));
    file = File('${dir.path}/prova.kdbx')..writeAsBytesSync(await db.save());
  });

  Future<void> pumpApp(WidgetTester tester, {FileStorage? storage}) async {
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        jsonEncode(RecentFile(database: fileRefOf(file)).toJson()),
      ],
    });
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          if (storage != null) fileStorageProvider.overrideWithValue(storage),
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

  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('impostazioni del database dalla barra: nome salvato nel file', (
    tester,
  ) async {
    // given
    await pumpApp(tester);
    await unlock(tester);

    // when
    await tester.tap(tab(l10n.settingsTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.dbSettingsTitle));
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.dbSettingsTemplatesGroup));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prova / Banca'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, l10n.dbSettingsName),
      'Personale',
    );
    await tester.tap(find.byTooltip(l10n.entryEditSave));
    await pumpUntilFound(tester, find.text(l10n.dbSettingsSaved));
    await tester.pumpAndSettle();

    // then
    expect(find.widgetWithText(AppBar, l10n.settingsTitle), findsOneWidget);
    await tester.tap(tab(l10n.navigationHome));
    await tester.pumpAndSettle();
    expect(find.text('Banca'), findsOneWidget);
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    expect(db.meta.name, 'Personale');
    expect(db.getGroup(uuid: db.meta.entryTemplatesGroup)?.name, 'Banca');
  });

  testWidgets(
    'le azioni del database sono disponibili solo nella scheda Impostazioni',
    (tester) async {
      // given
      final storage = FakeCreateStorage();
      addTearDown(() => storage.dir.deleteSync(recursive: true));
      await pumpApp(tester, storage: storage);
      final actions = [
        l10n.dbSettingsTitle,
        l10n.changeKeyTitle,
        l10n.exportTitle,
      ];

      // Impostazioni aperte dalla scelta del file, senza un database attivo.
      await tester.tap(find.byTooltip(l10n.settingsTitle));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, l10n.settingsTitle), findsOneWidget);
      expect(find.text(l10n.settingsDatabase), findsNothing);
      for (final action in actions) {
        expect(find.text(action), findsNothing);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      await unlock(tester);

      // Il menu del gruppo mantiene le proprie azioni.
      await tester.tap(find.byTooltip(l10n.groupMore));
      await tester.pumpAndSettle();
      expect(find.text(l10n.groupCreate), findsOneWidget);
      for (final action in actions) {
        expect(find.text(action), findsNothing);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // La scheda Impostazioni raggiunge le operazioni del database aperto.
      await tester.tap(tab(l10n.settingsTitle));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsDatabase), findsOneWidget);
      for (final action in actions) {
        expect(find.text(action).hitTestable(), findsOneWidget);
      }
      await tester.tap(find.text(l10n.changeKeyTitle));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, l10n.changeKeyTitle), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.exportTitle));
      const copyName = 'prova-copia.kdbx';
      await pumpUntilFound(tester, find.text(l10n.exportDone(copyName)));
      expect(storage.suggestedName, copyName);
      final copy = File('${storage.dir.path}/$copyName');
      final reopened = (await tester.runAsync(() => reopenFile(copy)))!;
      expect(
        reopened.root.groups.map((group) => group.name),
        contains('Banca'),
      );
    },
  );
}
