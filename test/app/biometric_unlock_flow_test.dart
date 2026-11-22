import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/security/biometric_key_store.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_secure_storage.dart';
import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  const texts = BiometricPromptTexts(title: 't', subtitle: 's', cancel: 'c');
  late File databaseFile;
  late FileRef databaseRef;
  late KdbxTransformedKey key;

  setUpAll(() async {
    final db = newTestDatabase();
    addTestEntry(db, db.root, {'Title': 'Conto'});
    (databaseFile, _) = await saveToTempFile(db);
    databaseRef = fileRefOf(databaseFile);
    final opened = await reopenFile(databaseFile);
    key = opened.header.transformedKey!;
  });

  /// App con il database tra i recenti e lo sblocco biometrico attivo.
  Future<FakeSecureStorage> pumpApp(WidgetTester tester) async {
    final secure = FakeSecureStorage.install();
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        jsonEncode(RecentFile(database: databaseRef).toJson()),
      ],
    });
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.runAsync(
      () => BiometricKeyStore(prefs).store(databaseRef, key, texts: texts),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
    return secure;
  }

  testWidgets('la richiesta biometrica parte da sola e apre il database', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text(databaseRef.name));

    await pumpUntilFound(tester, find.text('Conto'));
  });

  testWidgets('annullata: si resta sullo sblocco, con il pulsante biometrico', (
    tester,
  ) async {
    final secure = await pumpApp(tester);
    secure.failure = FakeSecureStorage.canceled();

    await tester.tap(find.text(databaseRef.name));
    await tester.pump();
    // Attende la fine del tentativo (lettura del file fuori dal tempo simulato).
    final spinner = find.byType(CircularProgressIndicator);
    for (var i = 0; i < 250; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (i > 5 && spinner.evaluate().isEmpty) break;
    }
    expect(spinner, findsNothing);

    expect(find.text(l10n.unlockBiometric), findsOneWidget);
    expect(find.text(l10n.errorBiometricFailed), findsNothing);

    // when: riprova dal pulsante, questa volta riesce
    secure.failure = null;
    await tester.tap(find.text(l10n.unlockBiometric));
    await pumpUntilFound(tester, find.text('Conto'));
  });

  testWidgets(
    '"Blocca database": sblocco dello stesso database con la richiesta biometrica',
    (tester) async {
      final secure = await pumpApp(tester);
      await tester.tap(find.text(databaseRef.name));
      await pumpUntilFound(tester, find.text('Conto'));
      await tester.pumpAndSettle();
      int biometricRequests() => secure.options
          .where(
            (options) =>
                options['requireBiometricsPerOperation'] == 'true' ||
                options['accessControlFlags']?.contains('biometryCurrentSet') ==
                    true,
          )
          .length;
      final requests = biometricRequests();

      await tester.tap(find.byTooltip(l10n.groupLock));
      await tester.pump();

      // Blocco completo, poi di nuovo l'impronta per lo stesso file.
      await pumpUntilFound(tester, find.text('Conto'));
      expect(biometricRequests(), requests + 1);
    },
  );
}
