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
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Vecchio'});
    entry.times.modification = KdbxTime(DateTime.utc(2025, 1, 1));
    entry.pushHistory();
    entry.fields[EntryFields.title] = KdbxTextField.fromText(text: 'Nuovo');
    final dir = Directory.systemTemp.createTempSync('keepass_mobile_5c');
    file = File('${dir.path}/prova.kdbx')..writeAsBytesSync(await db.save());
  });

  testWidgets('versione aperta in sola lettura e ripristinata', (tester) async {
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
    await pumpUntilFound(tester, find.text('Nuovo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nuovo'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.entryHistory), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Vecchio'));
    await tester.pumpAndSettle();

    // Sola lettura: niente modifica, sì ripristino ed eliminazione.
    expect(find.byTooltip(l10n.entryEdit), findsNothing);
    expect(find.byTooltip(l10n.entryHistoryRestore), findsOneWidget);
    expect(find.byTooltip(l10n.entryHistoryDelete), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.entryHistoryRestore));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.entryHistoryRestore).last);
    // Dopo il salvataggio si torna al dettaglio, che ha la sezione Cronologia
    // (la versione in sola lettura non ce l'ha).
    await pumpUntilFound(tester, find.text(l10n.entryHistory));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Vecchio'), findsOneWidget);

    final db = (await tester.runAsync(() => reopenFile(file)))!;
    final entry = db.root.allEntries.single;
    expect(entryTitle(entry), 'Vecchio');
    expect(entry.history.map(entryTitle), ['Vecchio', 'Nuovo']);
  });

  testWidgets('versione senza data di modifica: "Versione senza data"', (
    tester,
  ) async {
    final db = newTestDatabase();
    final entry = addTestEntry(db, db.root, {EntryFields.title: 'Voce'});
    entry.times.modification = KdbxTime();
    entry.pushHistory();
    file.writeAsBytesSync(await tester.runAsync(db.save) ?? const []);
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
    await pumpUntilFound(tester, find.text('Voce'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voce'));
    await tester.pumpAndSettle();

    expect(find.text(l10n.entryHistoryUndated), findsOneWidget);
    expect(find.textContaining('1970'), findsNothing);
  });
}
