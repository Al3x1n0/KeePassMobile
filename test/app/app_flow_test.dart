import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File databaseFile;
  late String rootName;

  setUpAll(() async {
    final db = KdbxDatabase.create(
      credentials: KdbxCredentials(
        password: ProtectedData.fromString('segreta'),
      ),
      name: 'Prova',
    );
    db.header.kdf = KdfId.aes;
    void addEntry(KdbxGroup group, String title, String userName) {
      db.createEntry(parent: group).fields
        ..['Title'] = KdbxTextField.fromText(text: title)
        ..['UserName'] = KdbxTextField.fromText(text: userName);
    }

    final bank = db.createGroup(parent: db.root, name: 'Banca');
    db.createGroup(parent: db.root, name: 'email');
    addEntry(db.root, 'zeta', 'z@example.org');
    addEntry(db.root, 'Alfa', 'alfa');
    addEntry(bank, 'Conto', 'cliente');
    rootName = db.root.name;

    final dir = Directory.systemTemp.createTempSync('keepass_mobile_test');
    databaseFile = File('${dir.path}/prova.kdbx')
      ..writeAsBytesSync(await db.save());
  });

  testWidgets('file recente: sblocco, gruppi ordinati, navigazione e blocco', (
    tester,
  ) async {
    // given: il database è tra i file recenti
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        jsonEncode(
          RecentFile(
            database: FileRef(
              uri: databaseFile.uri.toString(),
              name: 'prova.kdbx',
            ),
          ).toJson(),
        ),
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
    expect(find.text(l10n.fileSelectRecentFiles), findsOneWidget);

    // when: password errata
    await tester.tap(find.text('prova.kdbx'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'sbagliata');
    await tester.tap(find.text(l10n.unlockButton));

    // then: messaggio dedicato, si resta sullo sblocco
    await pumpUntilFound(tester, find.text(l10n.errorInvalidCredentials));

    // when: password corretta
    await tester.enterText(find.byType(TextField), 'segreta');
    await tester.tap(find.text(l10n.unlockButton));

    // then: gruppi prima delle voci, ordine per nome senza maiuscole
    await pumpUntilFound(tester, find.text('Banca'));
    await tester.pumpAndSettle();
    expect(find.text(rootName), findsOneWidget);
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Banca'), lessThan(top('email')));
    expect(top('email'), lessThan(top('Alfa')));
    expect(top('Alfa'), lessThan(top('zeta')));
    expect(find.text('z@example.org'), findsOneWidget);

    final sortSheet = find.byType(BottomSheet);
    Finder sortOption(String label) => find.descendant(
      of: sortSheet,
      matching: find.widgetWithText(ListTile, label),
    );
    Future<void> openSortSheet() async {
      await tester.tap(find.byTooltip(l10n.groupSort));
      await tester.pumpAndSettle();
    }

    void expectSelectedSort(String label) {
      final option = sortOption(label);
      expect(tester.widget<ListTile>(option).selected, isTrue);
      expect(
        find.descendant(of: option, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
      final title = tester.element(
        find.descendant(of: option, matching: find.text(label)),
      );
      expect(
        DefaultTextStyle.of(title).style.color,
        AppColors.selectionAccent(Theme.of(title).brightness),
      );
    }

    // when: apre il pannello e passa all'ordine alfabetico inverso
    await openSortSheet();
    expect(tester.widget<BottomSheet>(sortSheet).showDragHandle, isTrue);
    expect(find.text(l10n.groupSort), findsOneWidget);
    expect(
      find.descendant(of: sortSheet, matching: find.byType(ListTile)),
      findsNWidgets(5),
    );
    expectSelectedSort(l10n.groupSortAscending);
    await tester.tap(sortOption(l10n.groupSortDescending));
    await tester.pumpAndSettle();

    // then: l'elenco cambia e il pannello ricorda la selezione
    expect(sortSheet, findsNothing);
    expect(top('zeta'), lessThan(top('Alfa')));
    await openSortSheet();
    expectSelectedSort(l10n.groupSortDescending);
    expect(
      tester.widget<ListTile>(sortOption(l10n.groupSortAscending)).selected,
      isFalse,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(sortSheet, findsNothing);
    expect(top('zeta'), lessThan(top('Alfa')));

    // when: apre un sottogruppo
    await tester.tap(find.text('Banca'));
    await tester.pumpAndSettle();
    expect(find.text('Conto'), findsOneWidget);

    // when: blocca il database
    await tester.tap(find.byTooltip(l10n.groupLock));
    await tester.pumpAndSettle();

    // then: sblocco dello stesso database (D22), nessun dato visibile
    expect(find.text('prova.kdbx'), findsOneWidget);
    expect(find.text(l10n.unlockPassword), findsOneWidget);
    expect(find.text('Conto'), findsNothing);
    expect(find.text('Banca'), findsNothing);

    // when: indietro
    await tester.pageBack();
    await tester.pumpAndSettle();

    // then: scelta del file
    expect(find.text(l10n.fileSelectTitle), findsOneWidget);
  });
}
