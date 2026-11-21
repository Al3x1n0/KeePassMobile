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
import 'package:keepass_mobile/shared/ui/url_opener.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

class _Opener extends UrlOpener {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File file;

  setUp(() async {
    final db = newTestDatabase();
    addTestEntry(db, db.root, {
      EntryFields.title: 'Sito',
      EntryFields.url: 'www.example.org',
    });
    addTestEntry(db, db.root, {
      EntryFields.title: 'Comando',
      EntryFields.url: 'cmd://calc.exe',
    });
    addTestEntry(db, db.root, {
      EntryFields.title: 'Riferimento protetto',
      EntryFields.password: 'token-sintetico',
      EntryFields.url: 'https://example.org/login?token={PASSWORD}',
    });
    addTestEntry(
      db,
      db.root,
      {
        EntryFields.title: 'URL protetto',
        EntryFields.url: 'https://example.org/private',
      },
      protectedKeys: {EntryFields.url},
    );
    final dir = Directory.systemTemp.createTempSync('keepass_mobile_5e');
    file = File('${dir.path}/prova.kdbx')..writeAsBytesSync(await db.save());
  });

  testWidgets('URL aperto nel browser con https://; cmd:// rifiutato', (
    tester,
  ) async {
    final opener = _Opener();
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        jsonEncode(RecentFile(database: fileRefOf(file)).toJson()),
      ],
    });
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          urlOpenerProvider.overrideWithValue(opener),
        ],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('prova.kdbx'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.text('Sito'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sito'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.entryUrlOpen));
    await tester.pumpAndSettle();
    expect(opener.opened, [Uri.parse('https://www.example.org')]);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comando'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.entryUrlOpen));
    await tester.pumpAndSettle();
    expect(find.text(l10n.entryUrlNotSupported), findsOneWidget);

    for (final title in ['Riferimento protetto', 'URL protetto']) {
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.byTooltip(l10n.entryUrlOpen), findsNothing);
      expect(find.byTooltip(l10n.entryCopy(l10n.entryUrl)), findsOneWidget);
    }
    expect(opener.opened, hasLength(1));
  });
}
