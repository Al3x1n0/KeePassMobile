import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/app/external_change_dialog.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/external_change.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

void _rename(KdbxDatabase db) => db.meta.name = 'Rinominato';

/// Salvataggio avviato dal test: l'esito si legge quando [done] è vero.
class _SaveRun {
  _SaveRun(Future<void> saving) {
    saving.then<void>(
      (_) {
        done = true;
      },
      onError: (Object e) {
        error = e;
        done = true;
      },
    );
  }

  bool done = false;
  Object? error;
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  late File databaseFile;
  late List<int> original;

  setUpAll(() async {
    final db = newTestDatabase();
    addTestEntry(db, db.root, {EntryFields.title: 'Comune'});
    final (file, _) = await saveToTempFile(db);
    original = file.readAsBytesSync();
  });

  // Ogni test parte dallo stesso file (scrittura sincrona: il setUp dei
  // testWidgets gira nel tempo simulato).
  setUp(() {
    final dir = Directory.systemTemp.createTempSync('keepass_mobile_test');
    databaseFile = File('${dir.path}/prova.kdbx')..writeAsBytesSync(original);
  });

  /// Fa avanzare tempo reale e frame finché [run] non finisce.
  Future<void> waitFor(WidgetTester tester, _SaveRun run) async {
    for (var i = 0; i < 250 && !run.done; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(run.done, isTrue);
  }

  /// App con la finestra vera, database sbloccato con la password.
  Future<ProviderContainer> unlock(WidgetTester tester) async {
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
          externalChangeResolverProvider.overrideWith(externalChangeDialog),
        ],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(fileRefOf(databaseFile).name));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), testMasterKey);
    await tester.tap(find.text(l10n.unlockButton));
    await pumpUntilFound(tester, find.text('Comune'));
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(KeePassMobileApp)),
    );
  }

  Future<void> changeElsewhere(WidgetTester tester) async {
    await tester.runAsync(() async {
      final other = await reopenFile(databaseFile);
      addTestEntry(other, other.root, {EntryFields.title: 'Altrove'});
      databaseFile.writeAsBytesSync(await other.save());
    });
  }

  testWidgets('salvataggio con il file cambiato: domanda, poi Sincronizza', (
    tester,
  ) async {
    final container = await unlock(tester);
    await changeElsewhere(tester);

    final run = _SaveRun(
      container.read(databaseSessionProvider.notifier).apply(_rename),
    );
    await pumpUntilFound(tester, find.text(l10n.externalChangeTitle));
    expect(
      find.text(l10n.externalChangeBody(fileRefOf(databaseFile).name)),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.externalChangeSynchronize));
    await waitFor(tester, run);

    expect(run.error, isNull);
    await pumpUntilFound(tester, find.text('Altrove'));
    expect(find.text('Comune'), findsOneWidget);
  });

  testWidgets('Annulla: niente scritto', (tester) async {
    final container = await unlock(tester);
    await changeElsewhere(tester);
    final bytes = bytesOf(databaseFile);

    final run = _SaveRun(
      container.read(databaseSessionProvider.notifier).apply(_rename),
    );
    await pumpUntilFound(tester, find.text(l10n.externalChangeTitle));
    await tester.tap(find.text(l10n.externalChangeCancel));
    await waitFor(tester, run);

    expect(run.error, isA<ExternalChangeCanceledException>());
    expect(bytesOf(databaseFile), bytes);
  });

  testWidgets('"Sincronizza ora" dalla barra superiore', (tester) async {
    await unlock(tester);
    final sync = find.byTooltip(l10n.syncNow);

    await tester.tap(sync);
    await pumpUntilFound(tester, find.text(l10n.syncUnchanged));

    await changeElsewhere(tester);
    await tester.tap(sync);
    // Anche tempo simulato: il messaggio precedente deve uscire.
    final done = find.text(l10n.syncDone);
    for (var i = 0; i < 100 && done.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(done, findsOneWidget);
    expect(find.text('Altrove'), findsOneWidget);
  });
}
