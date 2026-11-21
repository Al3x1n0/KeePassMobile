import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kpasslib/kpasslib.dart';

import '../helpers/test_database.dart';

void main() {
  testWidgets('apre due database e passa dal secondo al primo', (tester) async {
    final first = newTestDatabase()..root.name = 'Primo';
    addTestEntry(first, first.root, {EntryFields.title: 'Prima esclusiva'});
    final second = newTestDatabase()..root.name = 'Secondo';
    addTestEntry(second, second.root, {EntryFields.title: 'Da copiare'});
    addTestEntry(second, second.root, {EntryFields.title: 'Da spostare'});
    final (firstFile, _) = (await tester.runAsync(
      () => saveToTempFile(first),
    ))!;
    final (secondFile, _) = (await tester.runAsync(
      () => saveToTempFile(second),
    ))!;
    addTearDown(() {
      firstFile.parent.deleteSync(recursive: true);
      secondFile.parent.deleteSync(recursive: true);
    });
    final firstRef = FileRef(uri: firstFile.uri.toString(), name: 'Primo.kdbx');
    final secondRef = FileRef(
      uri: secondFile.uri.toString(),
      name: 'Secondo.kdbx',
    );
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        jsonEncode(RecentFile(database: firstRef).toJson()),
        jsonEncode(RecentFile(database: secondRef).toJson()),
      ],
    });
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const KeePassMobileApp(),
      ),
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Primo.kdbx'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Primo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.databasesTitle));
    await tester.pumpAndSettle();
    final databaseSheet = find.byType(BottomSheet);
    expect(tester.widget<BottomSheet>(databaseSheet).showDragHandle, isTrue);
    expect(
      find.descendant(
        of: databaseSheet,
        matching: find.text(l10n.databasesTitle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: databaseSheet, matching: find.byType(Scrollable)),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.databasesOpenAnother));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Secondo.kdbx'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Secondo'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Da copiare'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.databasesCopy));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Primo.kdbx / Primo'));
    await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Secondo'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Da spostare'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.databasesMove));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Primo.kdbx / Primo'));
    await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Secondo'));
    await tester.pumpAndSettle();
    expect(find.text('Da spostare'), findsNothing);
    await tester.tap(find.byTooltip(l10n.searchTitle));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Prima esclusiva');
    await tester.pumpAndSettle();
    expect(find.textContaining('Primo.kdbx'), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.searchOptions));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(l10n.searchRegex),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(l10n.searchRegex));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '^Prima');
    await tester.tap(find.byTooltip(l10n.searchTitle));
    await pumpUntilFound(
      tester,
      find.widgetWithText(ListTile, 'Prima esclusiva'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Prima esclusiva'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Prima esclusiva'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.databasesTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Primo.kdbx'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Primo'), findsOneWidget);
    expect(find.text('Da copiare'), findsOneWidget);
    expect(find.text('Da spostare'), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.groupMore));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.linkedDatabaseAdd));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, l10n.linkedDatabasePassword),
      testMasterKey,
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.entryEditSave));
    await pumpUntilFound(tester, find.widgetWithText(ListTile, 'AutoOpen'));
    final reopened = (await tester.runAsync(() => reopenFile(firstFile)))!;
    final link = reopened.root.groups
        .singleWhere((g) => g.name == 'AutoOpen')
        .entries
        .single;
    expect(link.fields[EntryFields.url]!.text, secondRef.uri);
    expect(link.fields[EntryFields.password], isA<ProtectedTextField>());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.databasesTitle));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Secondo.kdbx'),
        matching: find.byTooltip(l10n.databasesClose),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Primo'), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.databasesTitle));
    await tester.pumpAndSettle();
    expect(find.text('Secondo.kdbx'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KeePassMobileApp)),
    );
    container.read(databaseSessionProvider.notifier).lock();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Primo.kdbx'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.text(l10n.linkedDatabaseTitle));
    await tester.tap(find.text(l10n.linkedDatabaseAllow));
    for (
      var i = 0;
      i < 100 &&
          container.read(databaseSessionProvider.notifier).openSessions.length <
              2;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(
      container.read(databaseSessionProvider.notifier).openSessions.length,
      2,
    );
  });
}
