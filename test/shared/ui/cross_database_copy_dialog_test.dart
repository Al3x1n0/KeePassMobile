import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/database/kdbx_items.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/remote_cache.dart';
import 'package:keepass_mobile/shared/ui/cross_database_copy_dialog.dart';

import '../../helpers/test_database.dart';

class _FailingStorage extends FileStorage {
  _FailingStorage(this.failed);
  final FileRef failed;
  @override
  Future<void> write(FileRef ref, Uint8List bytes, {String? expectedVersion}) {
    if (ref == failed) throw const FileWriteException();
    return super.write(ref, bytes, expectedVersion: expectedVersion);
  }
}

void main() {
  for (final failSource in [false, true]) {
    testWidgets(
      'spostamento conserva la sorgente se fallisce ${failSource ? 'la sorgente' : 'la destinazione'}',
      (tester) async {
        final first = newTestDatabase()..root.name = 'Sorgente';
        final second = newTestDatabase()..root.name = 'Destinazione';
        addTestEntry(first, first.root, {EntryFields.title: 'Voce'});
        final (firstFile, firstDb) = (await tester.runAsync(
          () => saveToTempFile(first),
        ))!;
        final (secondFile, secondDb) = (await tester.runAsync(
          () => saveToTempFile(second),
        ))!;
        addTearDown(() {
          firstFile.parent.deleteSync(recursive: true);
          secondFile.parent.deleteSync(recursive: true);
        });
        final firstRef = fileRefOf(firstFile),
            secondRef = fileRefOf(secondFile);
        final container = await tester.runAsync(
          () => newTestContainer(
            file: firstFile,
            database: firstDb,
            overrides: [
              databaseFileStorageProvider.overrideWithValue(
                _FailingStorage(failSource ? firstRef : secondRef),
              ),
            ],
          ),
        );
        final sessions = container!.read(databaseSessionProvider.notifier);
        sessions.openAdditional(
          DatabaseSession(file: secondRef, database: secondDb),
          sessions.lockGeneration,
        );
        sessions.switchTo(firstRef);
        final id = itemIdOf(firstDb.root.entries.single);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () =>
                        copyToAnotherDatabase(context, ref, [id], move: true),
                    child: const Text('Avvia'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Avvia'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('prova.kdbx / Destinazione'));
        final l10n = lookupAppLocalizations(const Locale('en'));
        await pumpUntilFound(
          tester,
          find.text(
            failSource ? l10n.databasesMoveIncomplete : l10n.errorGeneric,
          ),
        );
        final original = (await tester.runAsync(() => reopenFile(firstFile)))!;
        final destination = (await tester.runAsync(
          () => reopenFile(secondFile),
        ))!;
        expect(original.root.entries.map(entryTitle), contains('Voce'));
        expect(
          destination.root.entries.map(entryTitle),
          failSource ? contains('Voce') : isEmpty,
        );
      },
    );
  }
}
