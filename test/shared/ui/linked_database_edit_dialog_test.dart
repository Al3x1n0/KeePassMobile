import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/ui/linked_database_edit_dialog.dart';

import '../../helpers/test_database.dart';

void main() {
  testWidgets(
    'sceglie il database collegato in una bottom sheet e conserva la password',
    (tester) async {
      // given
      await _openForm(tester);
      final password = find.byType(TextField);
      await tester.enterText(password, testMasterKey);

      // when
      await tester.tap(find.text(_second.name));
      await tester.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      final selected = find.descendant(
        of: sheet,
        matching: find.widgetWithText(ListTile, _second.name),
      );
      expect(tester.widget<BottomSheet>(sheet).showDragHandle, isTrue);
      expect(tester.widget<ListTile>(selected).selected, isTrue);
      await tester.tap(find.widgetWithText(ListTile, _third.name));
      await tester.pumpAndSettle();

      // then
      expect(sheet, findsNothing);
      expect(find.text(_third.name), findsOneWidget);
      expect(
        tester.widget<TextField>(password).controller?.text,
        testMasterKey,
      );
      await tester.tap(find.text(_third.name));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(find.text(_third.name), findsOneWidget);
    },
  );

  for (final openPicker in [false, true]) {
    testWidgets(
      openPicker
          ? 'il blocco chiude la bottom sheet e il modulo del collegamento'
          : 'il blocco chiude il modulo del collegamento',
      (tester) async {
        // given
        final container = await _openForm(tester);
        await tester.enterText(find.byType(TextField), testMasterKey);
        if (openPicker) {
          await tester.tap(find.text(_second.name));
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsOneWidget);
        }

        // when
        container.read(databaseSessionProvider.notifier).lock();
        await tester.pumpAndSettle();

        // then
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(container.read(databaseSessionProvider), isNull);
      },
    );
  }
}

const _first = FileRef(uri: 'file:///primo.kdbx', name: 'Primo.kdbx');
const _second = FileRef(uri: 'file:///secondo.kdbx', name: 'Secondo.kdbx');
const _third = FileRef(uri: 'file:///terzo.kdbx', name: 'Terzo.kdbx');

Future<ProviderContainer> _openForm(WidgetTester tester) async {
  final container = (await tester.runAsync(newTestContainer))!;
  final sessions = container.read(databaseSessionProvider.notifier);
  sessions.open(DatabaseSession(file: _first, database: newTestDatabase()));
  for (final file in [_second, _third]) {
    sessions.openAdditional(
      DatabaseSession(file: file, database: newTestDatabase()),
      sessions.lockGeneration,
    );
  }
  sessions.switchTo(_first);
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
              child: const Text('Apri'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Apri'));
  await tester.pumpAndSettle();
  return container;
}
