import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/ui/app_dialog.dart';

void main() {
  setUpAll(() async {
    // Il font Ahem dei test ha metriche diverse dai font dell'interfaccia.
    var directory = File(Platform.resolvedExecutable).parent;
    while (!Directory('${directory.path}/bin/cache/artifacts/material_fonts')
        .existsSync()) {
      final parent = directory.parent;
      if (parent.path == directory.path) {
        throw StateError('Flutter SDK not found');
      }
      directory = parent;
    }
    final loader = FontLoader('Roboto');
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          await File(
            '${directory.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
          ).readAsBytes(),
        ),
      ),
    );
    await loader.load();
  });
  for (final count in [2, 3]) {
    testWidgets('$count scelte: titolo, descrizione, icona e stili uniformi', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppDialog(
              title: const Text('Titolo'),
              body: const Text('Descrizione'),
              icon: const Icon(Icons.fingerprint),
              content: const TextField(),
              actions: [
                for (var i = 0; i < count; i++)
                  AppDialogAction(onPressed: () {}, child: Text('Scelta $i')),
              ],
            ),
          ),
        ),
      );
      final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
      expect(dialog.title, isNotNull);
      expect(find.text('Descrizione'), findsOneWidget);
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(TextButton), findsNWidgets(count == 2 ? 1 : 3));
      expect(find.byType(FilledButton), findsNWidgets(count == 2 ? 1 : 0));
    });
  }

  for (final locale in ['it', 'en']) {
    testWidgets('azioni compatte affiancate a 360 dp: $locale', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          locale: Locale(locale),
          localizationsDelegates: [
            ...GlobalMaterialLocalizations.delegates,
            ...AppLocalizations.localizationsDelegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              final l10n = AppLocalizations.of(context);
              return Scaffold(
                body: AppDialog(
                  title: Text(l10n.dialogSaveUnencryptedTitle),
                  body: const Text('Descrizione'),
                  actions: [
                    AppDialogAction(onPressed: () {}, child: Text(l10n.cancel)),
                    AppDialogAction(
                      onPressed: () => selected = true,
                      child: Text(l10n.entryAttachmentSaveConfirm),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).icon, isNull);
      expect(
        tester.getCenter(find.byType(TextButton)).dy,
        tester.getCenter(find.byType(FilledButton)).dy,
      );
      await tester.tap(find.byType(FilledButton));
      expect(selected, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
