import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/create_database/create_database_view_model.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_create_storage.dart';
import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('la demo salva una copia del file incluso e apre lo sblocco', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    final storage = FakeCreateStorage();
    addTearDown(() => storage.dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          fileStorageProvider.overrideWithValue(storage),
        ],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.fileSelectDemo));
    await pumpUntilFound(tester, find.text(l10n.unlockButton));
    expect(storage.suggestedName, 'Rifugio-Aurora.kdbx');
    final original = File('assets/demo/Rifugio-Aurora.kdbx');
    final copy = File('${storage.dir.path}/${storage.suggestedName}');
    expect(copy.readAsBytesSync(), original.readAsBytesSync());
  });

  testWidgets(
    'nuovo database: conferma diversa rifiutata, poi creato e aperto',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
      final storage = FakeCreateStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            fileStorageProvider.overrideWithValue(storage),
            newDatabaseKdfProvider.overrideWithValue(
              const AesKdfSettings(rounds: 1000),
            ),
          ],
          child: const KeePassMobileApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FloatingActionButton, l10n.fileSelectNewDatabase),
      );
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(AppBar, l10n.createDatabaseTitle),
        findsOneWidget,
      );
      final fields = find.byType(TextFormField);

      // Nessuna chiave: errore.
      await tester.tap(find.text(l10n.createDatabaseButton));
      await tester.pumpAndSettle();
      expect(find.text(l10n.createDatabaseKeyRequired), findsOneWidget);

      // Conferma diversa: errore.
      await tester.enterText(fields.at(0), 'nuova');
      await tester.enterText(fields.at(1), 'diversa');
      await tester.tap(find.text(l10n.createDatabaseButton));
      await tester.pumpAndSettle();
      expect(find.text(l10n.createDatabaseMismatch), findsOneWidget);

      // Conferma uguale: database creato e aperto.
      await tester.enterText(fields.at(1), 'nuova');
      await tester.tap(find.text(l10n.createDatabaseButton));
      await pumpUntilFound(tester, find.text('Internet'));
      await tester.pumpAndSettle();
      expect(find.text('eMail'), findsOneWidget);
      expect(find.text('keepass'), findsOneWidget);
    },
  );
}
