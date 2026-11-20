import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  for (final enabled in [true, false]) {
    testWidgets('apertura TAN con scadenza automatica $enabled', (
      tester,
    ) async {
      final db = newTestDatabase();
      addTestEntry(db, db.root, {EntryFields.title: '<TAN>'});
      final dir = Directory.systemTemp.createTempSync('tan_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/prova.kdbx')
        ..writeAsBytesSync((await tester.runAsync(db.save))!);
      SharedPreferences.setMockInitialValues({
        'settings.expire_tan_on_open': enabled,
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
      await pumpUntilFound(tester, find.text('<TAN>'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('<TAN>'));
      if (enabled) await pumpUntilFound(tester, find.text(l10n.entryHistory));
      await tester.pumpAndSettle();
      final reopened = (await tester.runAsync(() => reopenFile(file)))!;
      final entry = reopened.root.allEntries.single;
      expect(entry.times.expires, enabled);
      expect(entry.history.length, enabled ? 1 : 0);
      if (enabled) {
        expect(entry.times.expiry.time!.isBefore(DateTime.now()), isTrue);
        expect(entry.history.single.times.expires, isFalse);
      }
    });
  }
}
