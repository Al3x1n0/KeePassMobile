import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File file;

  setUp(() async {
    final db = newTestDatabase();
    final expired = addTestEntry(db, db.root, {EntryFields.title: 'Vecchia'});
    expired.times
      ..creation = KdbxTime(DateTime.utc(2018))
      ..modification = KdbxTime(DateTime.utc(2019))
      ..expires = true
      ..expiry = KdbxTime(DateTime.utc(2020));
    expired.tags = ['banca', 'web'];
    addTestEntry(db, db.root, {EntryFields.title: 'Nuova'}).icon =
        KdbxIcon.star;
    final dir = Directory.systemTemp.createTempSync('keepass_mobile_5b');
    file = File('${dir.path}/prova.kdbx')..writeAsBytesSync(await db.save());
  });

  testWidgets('voce scaduta barrata, dettaglio con scadenza e tag', (
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
    await pumpUntilFound(tester, find.text('Vecchia'));
    await tester.pumpAndSettle();

    // Elenco: icona "scaduta" e titolo barrato; l'altra voce con la sua icona.
    final expiredTitle = tester.widget<Text>(find.text('Vecchia'));
    expect(expiredTitle.style?.decoration, TextDecoration.lineThrough);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Vecchia'),
        matching: find.byIcon(Icons.event_busy),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Nuova'),
        matching: find.byIcon(Icons.star_outline),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Vecchia'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Expired on'), findsOneWidget);
    expect(find.widgetWithText(ListTile, l10n.entryCreated), findsOneWidget);
    expect(find.widgetWithText(ListTile, l10n.entryModified), findsOneWidget);
    expect(find.widgetWithText(Chip, 'banca'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'web'), findsOneWidget);
  });
}
