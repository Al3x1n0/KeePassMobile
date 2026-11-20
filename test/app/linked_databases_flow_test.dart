import 'dart:convert';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

class _TrackingStorage extends FileStorage {
  int reads = 0;
  Completer<void>? gate;
  @override
  Future<StoredFile> readWithoutRedirects(FileRef ref) async {
    reads++;
    final waiting = gate;
    if (waiting != null) await waiting.future;
    return super.readWithoutRedirects(ref);
  }
}

void main() {
  testWidgets('chiede conferma prima dell’apertura e la ricorda', (
    tester,
  ) async {
    final child = newTestDatabase()..root.name = 'Figlio';
    final (childFile, _) = (await tester.runAsync(
      () => saveToTempFile(child),
    ))!;
    final parent = newTestDatabase()..root.name = 'Principale';
    final group = parent.createGroup(parent: parent.root, name: 'AutoOpen');
    addTestEntry(
      parent,
      group,
      {
        EntryFields.title: 'Collegamento',
        EntryFields.url: childFile.uri.toString(),
        EntryFields.password: testMasterKey,
      },
      protectedKeys: {EntryFields.password},
    );
    final (parentFile, _) = (await tester.runAsync(
      () => saveToTempFile(parent),
    ))!;
    addTearDown(() {
      childFile.parent.deleteSync(recursive: true);
      parentFile.parent.deleteSync(recursive: true);
    });
    SharedPreferences.setMockInitialValues({
      RecentFilesRepository.storageKey: [
        jsonEncode(RecentFile(database: fileRefOf(parentFile)).toJson()),
      ],
    });
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    final storage = _TrackingStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          fileStorageProvider.overrideWithValue(storage),
        ],
        child: const KeePassMobileApp(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(KeePassMobileApp)),
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    Future<void> openParent() async {
      await tester.pumpAndSettle();
      await tester.tap(find.text('prova.kdbx'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), testMasterKey);
      await tester.tap(find.text(l10n.unlockButton));
      await pumpUntilFound(tester, find.widgetWithText(AppBar, 'Principale'));
      await tester.pumpAndSettle();
    }

    Future<void> waitForChild() async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (container
                .read(databaseSessionProvider.notifier)
                .openSessions
                .length ==
            2) {
          return;
        }
      }
      fail('linked session not opened');
    }

    await openParent();
    expect(find.text(l10n.linkedDatabaseTitle), findsOneWidget);
    expect(storage.reads, 0);
    await tester.tap(find.text(l10n.linkedDatabaseAllow));
    await waitForChild();
    expect(storage.reads, 1);
    expect(
      container.read(databaseSessionProvider.notifier).openSessions.length,
      2,
    );
    container.read(databaseSessionProvider.notifier).lock();
    await tester.pumpAndSettle();
    await openParent();
    await waitForChild();
    expect(find.text(l10n.linkedDatabaseTitle), findsNothing);
    expect(storage.reads, 2);
  });
  testWidgets(
    'rifiuto e blocco durante la lettura non aprono il collegamento',
    (tester) async {
      final child = newTestDatabase();
      final (childFile, _) = (await tester.runAsync(
        () => saveToTempFile(child),
      ))!;
      final parent = newTestDatabase()..root.name = 'Principale';
      final group = parent.createGroup(parent: parent.root, name: 'AutoOpen');
      addTestEntry(
        parent,
        group,
        {
          EntryFields.url: childFile.uri.toString(),
          EntryFields.password: testMasterKey,
        },
        protectedKeys: {EntryFields.password},
      );
      final (parentFile, _) = (await tester.runAsync(
        () => saveToTempFile(parent),
      ))!;
      addTearDown(() {
        childFile.parent.deleteSync(recursive: true);
        parentFile.parent.deleteSync(recursive: true);
      });
      SharedPreferences.setMockInitialValues({
        RecentFilesRepository.storageKey: [
          jsonEncode(RecentFile(database: fileRefOf(parentFile)).toJson()),
        ],
      });
      final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
      final storage = _TrackingStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            fileStorageProvider.overrideWithValue(storage),
          ],
          child: const KeePassMobileApp(),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(KeePassMobileApp)),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      Future<void> openParent() async {
        await tester.pumpAndSettle();
        await tester.tap(find.text('prova.kdbx'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), testMasterKey);
        await tester.tap(find.text(l10n.unlockButton));
        await pumpUntilFound(tester, find.text(l10n.linkedDatabaseTitle));
        await tester.pumpAndSettle();
      }

      await openParent();
      container.read(databaseSessionProvider.notifier).lock();
      await tester.pumpAndSettle();
      expect(find.text(l10n.linkedDatabaseTitle), findsNothing);
      expect(storage.reads, 0);
      await openParent();
      await tester.tap(find.widgetWithText(TextButton, l10n.cancel));
      await tester.pumpAndSettle();
      expect(storage.reads, 0);
      expect(
        container.read(databaseSessionProvider.notifier).openSessions.length,
        1,
      );
      container.read(databaseSessionProvider.notifier).lock();
      await tester.pumpAndSettle();
      await openParent();
      storage.gate = Completer<void>();
      await tester.tap(find.text(l10n.linkedDatabaseAllow));
      for (var i = 0; i < 50 && storage.reads == 0; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(storage.reads, 1);
      container.read(databaseSessionProvider.notifier).lock();
      await tester.pumpAndSettle();
      storage.gate!.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(container.read(databaseSessionProvider), isNull);
      expect(
        container.read(databaseSessionProvider.notifier).openSessions,
        isEmpty,
      );
    },
  );
}
