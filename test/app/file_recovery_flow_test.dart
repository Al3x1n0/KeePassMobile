import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/security/device_security.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_app_security.dart';
import '../helpers/fake_secure_storage.dart';
import '../helpers/test_database.dart';

class LostStorage extends FileStorage {
  final released = <FileRef>[];
  @override
  Future<StoredFile> read(FileRef ref) async =>
      throw const FileUnavailableException();
  @override
  Future<void> release(FileRef ref) async {
    released.add(ref);
  }
}

class ReplacementPicker extends FilePickerService {
  ReplacementPicker(this.file);
  final PickedFile file;
  @override
  Future<PickedFile?> pick() async => file;
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  testWidgets(
    'riferimento perso: nuova scelta, password azzerata, recente sostituito dopo sblocco',
    (tester) async {
      FakeClipboard(tester.binding);
      FakeSecureStorage.install();
      const old = FileRef(uri: 'content://test/old', name: 'old.kdbx');
      const next = FileRef(uri: 'content://test/new', name: 'new.kdbx');
      final db = newTestDatabase();
      addTestEntry(db, db.root, {EntryFields.title: 'Voce recuperata'});
      final bytes = Uint8List.fromList(await tester.runAsync(db.save) ?? []);
      SharedPreferences.setMockInitialValues({
        RecentFilesRepository.storageKey: [
          jsonEncode(const RecentFile(database: old).toJson()),
        ],
      });
      final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
      final storage = LostStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appSecurityProvider.overrideWithValue(FakeAppSecurity()),
            fileStorageProvider.overrideWithValue(storage),
            filePickerServiceProvider.overrideWithValue(
              ReplacementPicker(PickedFile(ref: next, bytes: bytes)),
            ),
          ],
          child: const KeePassMobileApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('old.kdbx'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'prima prova');
      await tester.tap(find.text(l10n.unlockButton));
      await pumpUntilFound(tester, find.text(l10n.unlockChooseAgain));
      await tester.tap(find.text(l10n.unlockChooseAgain));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(RecentFilesRepository(prefs, storage).load().single.database, old);
      await tester.enterText(find.byType(TextField), testMasterKey);
      await tester.tap(find.text(l10n.unlockButton));
      await pumpUntilFound(tester, find.text('Voce recuperata'));
      expect(
        RecentFilesRepository(prefs, storage).load().single.database,
        next,
      );
      expect(storage.released, contains(old));
    },
  );
}
