import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/entry/totp_tile.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

class _NotPersistentPicker extends FilePickerService {
  _NotPersistentPicker(this.file);

  final File file;

  @override
  Future<PickedFile?> pick() async => PickedFile(
    ref: fileRefOf(file),
    bytes: file.readAsBytesSync(),
    persistent: false,
  );
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File file;

  setUp(() async {
    final db = newTestDatabase();
    addTestEntry(db, db.root, {
      EntryFields.title: 'Servizio',
      EntryFields.userName: 'alex',
    });
    final dir = Directory.systemTemp.createTempSync('keepass_mobile_4e');
    file = File('${dir.path}/prova.kdbx')..writeAsBytesSync(await db.save());
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    List<String> recents = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: recents,
    });
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          filePickerServiceProvider.overrideWithValue(
            _NotPersistentPicker(file),
          ),
          totpClockProvider.overrideWithValue(
            () => DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true),
          ),
        ],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('file senza accesso persistente: avviso alla scelta', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text(l10n.fileSelectOpenFile));
    await tester.pumpAndSettle();

    expect(find.text(l10n.fileSelectNotPersistent), findsOneWidget);
    expect(find.text(l10n.unlockButton), findsOneWidget);
  });

  testWidgets('TOTP guidato: URI incollato, salvato nel campo otp', (
    tester,
  ) async {
    await pumpApp(
      tester,
      recents: [jsonEncode(RecentFile(database: fileRefOf(file)).toJson())],
    );
    await tester.tap(find.text('prova.kdbx'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.text('Servizio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servizio'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.entryEdit));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text(l10n.entryEditTotpSetup),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(l10n.entryEditTotpSetup));
    await tester.pumpAndSettle();
    expect(find.text(l10n.entryEditTotpScan), findsOneWidget);
    final uriField = find.widgetWithText(TextField, l10n.entryEditTotpUri);
    await tester.enterText(uriField, 'non valido');
    await tester.tap(find.text(l10n.entryEditTotpApply));
    await tester.pumpAndSettle();
    expect(find.text(l10n.entryEditTotpInvalid), findsOneWidget);

    await tester.enterText(
      uriField,
      'otpauth://totp/Servizio:alex?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
    );
    await tester.tap(find.text(l10n.entryEditTotpApply));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.entryEditSave));
    await pumpUntilFound(tester, find.byType(TotpTile));
    await tester.pumpAndSettle();

    final db = (await tester.runAsync(() => reopenFile(file)))!;
    final otp = db.root.allEntries.single.fields['otp'];
    expect(otp?.text, startsWith('otpauth://totp/'));
  });
}
