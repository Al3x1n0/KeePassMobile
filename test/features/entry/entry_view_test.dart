import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/entry/entry_view.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_database.dart';

void main() {
  const locale = Locale('it');
  final l10n = lookupAppLocalizations(locale);

  testWidgets(
    'copia ogni campo toccando la riga e conserva la pulizia scelta',
    (tester) async {
      // given
      FlutterSecureStorage.setMockInitialValues({});
      addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
      final clipboard = FakeClipboard(tester.binding);
      final db = newTestDatabase();
      final entry = addTestEntry(
        db,
        db.root,
        {
          EntryFields.title: 'Voce di prova',
          EntryFields.userName: 'utente-di-prova',
          EntryFields.password: 'password-di-prova',
          EntryFields.url: 'https://example.org',
          EntryFields.notes: 'Prima riga\nSeconda riga',
          'Codice': 'codice-di-prova',
          'Segreto': 'segreto-di-prova',
        },
        protectedKeys: {EntryFields.password, 'Segreto'},
      );
      final container = await newTestContainer();
      container
          .read(databaseSessionProvider.notifier)
          .open(
            DatabaseSession(
              file: const FileRef(
                uri: 'file:///prova.kdbx',
                name: 'prova.kdbx',
              ),
              database: db,
            ),
          );
      await container
          .read(appSettingsProvider.notifier)
          .update(const AppSettings(clipboardTimeout: Duration(seconds: 60)));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: [
              ...GlobalMaterialLocalizations.delegates,
              ...AppLocalizations.localizationsDelegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildLightTheme(),
            home: EntryView(entryId: itemIdOf(entry)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // when / then
      for (final (label, value) in [
        (l10n.entryUserName, 'utente-di-prova'),
        (l10n.entryPassword, 'password-di-prova'),
        (l10n.entryUrl, 'https://example.org'),
        (l10n.entryNotes, 'Prima riga\nSeconda riga'),
        ('Codice', 'codice-di-prova'),
        ('Segreto', 'segreto-di-prova'),
      ]) {
        final tile = find.widgetWithText(ListTile, label);
        await tester.scrollUntilVisible(tile, 150);
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tapAt(tester.getTopLeft(tile) + const Offset(4, 20));
        await tester.pumpAndSettle();
        expect(clipboard.text, value);
        expect(clipboard.clearAfter, const Duration(seconds: 60));
        expect(find.byIcon(Icons.copy), findsNothing);
      }
      expect(find.text('segreto-di-prova'), findsNothing);
      expect(find.text(l10n.entryCopied(60)), findsOneWidget);

      final secret = find.widgetWithText(ListTile, 'Segreto');
      clipboard.text = 'copia esterna';
      await tester.tap(
        find.descendant(of: secret, matching: find.byTooltip(l10n.entryShow)),
      );
      await tester.pumpAndSettle();
      expect(find.text('segreto-di-prova'), findsOneWidget);
      expect(clipboard.text, 'copia esterna');
      expect(clipboard.clearAfter, const Duration(seconds: 60));
    },
  );
}
