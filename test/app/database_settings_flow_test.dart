import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File file;

  setUp(() async {
    final db = newTestDatabase();
    db.header.kdfSettings = const AesKdfSettings(rounds: 1000);
    db.createGroup(parent: db.root, name: 'Banca');
    final dir = Directory.systemTemp.createTempSync('keepass_mobile_dbset');
    file = File('${dir.path}/prova.kdbx')..writeAsBytesSync(await db.save());
  });

  testWidgets('impostazioni del database dal menu: nome salvato nel file', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        jsonEncode(RecentFile(database: fileRefOf(file)).toJson()),
      ],
    });
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('prova.kdbx'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.text('Banca'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(l10n.groupMore));
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

    expect(find.text('Banca'), findsOneWidget);
    final db = (await tester.runAsync(() => reopenFile(file)))!;
    expect(db.meta.name, 'Personale');
    expect(db.getGroup(uuid: db.meta.entryTemplatesGroup)?.name, 'Banca');
  });
}
