import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/item_edits.dart';
import 'package:keepass_mobile/shared/ui/icon_picker_dialog.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  testWidgets('sceglie una icona personalizzata già presente', (tester) async {
    final db = newTestDatabase();
    final id = KdbxUuid.random();
    db.meta.customIcons[id] = KdbxCustomIcon(data: []);
    IconChoice? chosen;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  chosen = await showDialog<IconChoice>(
                    context: context,
                    builder: (_) =>
                        IconPickerDialog(selected: KdbxIcon.key, database: db),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Custom icon'));
    await tester.pumpAndSettle();
    expect(chosen?.customId, id);
  });
}
