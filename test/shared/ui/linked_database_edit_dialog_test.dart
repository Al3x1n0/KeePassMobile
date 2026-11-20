import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/ui/linked_database_edit_dialog.dart';

import '../../helpers/test_database.dart';

void main() {
  testWidgets('il blocco chiude la finestra di creazione del collegamento', (
    tester,
  ) async {
    final first = newTestDatabase();
    final second = newTestDatabase();
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
    final container = (await tester.runAsync(
      () => newTestContainer(file: firstFile, database: firstDb),
    ))!;
    final sessions = container.read(databaseSessionProvider.notifier);
    sessions.openAdditional(
      DatabaseSession(file: fileRefOf(secondFile), database: secondDb),
      sessions.lockGeneration,
    );
    sessions.switchTo(fileRefOf(firstFile));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => addLinkedDatabase(context, ref),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'password sintetica');
    sessions.lock();
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(container.read(databaseSessionProvider), isNull);
  });
}
