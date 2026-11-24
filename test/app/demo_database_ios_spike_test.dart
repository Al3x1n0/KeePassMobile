import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/autofill_ios_spike.dart';
import 'package:keepass_mobile/features/file_select/demo_database.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const channel = MethodChannel('io.github.al3x1n0.keepassmobile/autofill_ios');
  const other = FileRef(uri: 'bookmark:altro', name: 'Rifugio-Aurora.kdbx');
  for (final locale in [const Locale('it'), const Locale('en')]) {
    testWidgets(
      '${locale.languageCode}: spike iOS indica la password della sola demo',
      (tester) async {
        // given: il canale dello spike condivide i riferimenti dei recenti.
        final dispatcher = tester.binding.platformDispatcher;
        dispatcher.localesTestValue = [locale];
        addTearDown(dispatcher.clearLocalesTestValue);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => switch (call.method) {
            'request' || 'memory' || 'config' => <String, Object?>{},
            'recents' => [
              jsonEncode(
                const RecentFile(database: DemoDatabaseRepository.file)
                    .toJson(),
              ),
              jsonEncode(const RecentFile(database: other).toJson()),
            ],
            _ => null,
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await runAutofillIosSpike();
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(locale);
        expect(find.text(l10n.demoDatabaseSubtitle), findsOneWidget);

        // when / then: il suggerimento compare nello sblocco della demo.
        await tester.tap(
          find.widgetWithText(ListTile, l10n.demoDatabaseSubtitle),
        );
        await tester.pumpAndSettle();
        expect(find.text(l10n.demoDatabasePassword), findsOneWidget);
        await tester.tap(find.text('Annulla'));
        await tester.pumpAndSettle();

        // Il bookmark di un file omonimo non riceve il suggerimento.
        await tester.tap(find.widgetWithText(ListTile, other.name).last);
        await tester.pumpAndSettle();
        expect(find.text(l10n.demoDatabasePassword), findsNothing);
        await tester.tap(find.text('Annulla'));
        await tester.pumpAndSettle();
      },
    );
  }
}
