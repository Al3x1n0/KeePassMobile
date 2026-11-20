import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/security/biometric_key_store.dart';
import 'package:keepass_mobile/shared/security/device_security.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_app_security.dart';
import '../helpers/fake_secure_storage.dart';
import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File databaseFile;

  setUpAll(() async {
    final db = newTestDatabase();
    addTestEntry(db, db.root, {'Title': 'Conto'});
    (databaseFile, _) = await saveToTempFile(db);
  });

  /// Sblocca con la password il database dei recenti; restituisce le preferenze.
  Future<SharedPreferences> unlock(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        jsonEncode(RecentFile(database: fileRefOf(databaseFile)).toJson()),
      ],
    });
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appSecurityProvider.overrideWithValue(
            FakeAppSecurity(biometrics: true),
          ),
        ],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(fileRefOf(databaseFile).name));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.text(l10n.biometricOfferTitle));
    return prefs;
  }

  testWidgets('dopo lo sblocco con password: "Attiva" salva la chiave', (
    tester,
  ) async {
    final secure = FakeSecureStorage.install();
    final prefs = await unlock(tester);

    await tester.tap(find.text(l10n.biometricOfferEnable));
    await pumpUntilFound(tester, find.text(l10n.biometricOfferEnabled));

    expect(secure.data, hasLength(1));
    expect(BiometricKeyStore(prefs).isEnabled(fileRefOf(databaseFile)), isTrue);
    expect(find.text('Conto'), findsOneWidget);
  });

  testWidgets('"Non chiedere più": ricordato per il file', (tester) async {
    final secure = FakeSecureStorage.install();
    final prefs = await unlock(tester);

    await tester.tap(find.text(l10n.biometricOfferNever));
    await tester.pumpAndSettle();
    await tester.runAsync(pumpEventQueue);

    expect(find.text(l10n.biometricOfferTitle), findsNothing);
    expect(secure.data, isEmpty);
    expect(
      BiometricKeyStore(prefs).isOfferDeclined(fileRefOf(databaseFile)),
      isTrue,
    );
  });

  testWidgets(
    'richiesta biometrica annullata: nessun messaggio, resta spenta',
    (tester) async {
      final secure = FakeSecureStorage.install()
        ..failure = FakeSecureStorage.canceled();
      final prefs = await unlock(tester);

      await tester.tap(find.text(l10n.biometricOfferEnable));
      await tester.pumpAndSettle();
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(secure.data, isEmpty);
      expect(
        BiometricKeyStore(prefs).isEnabled(fileRefOf(databaseFile)),
        isFalse,
      );
    },
  );
}
