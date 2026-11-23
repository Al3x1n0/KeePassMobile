import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/group/group_edit_dialog.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/item_edits.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('la scelta di un’icona lascia aperta la modifica del gruppo', (
    tester,
  ) async {
    // given
    final l10n = lookupAppLocalizations(const Locale('en'));
    GroupDraft? draft;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  draft = await showDialog<GroupDraft>(
                    context: context,
                    builder: (_) => const GroupEditDialog(),
                  );
                },
                child: Text(l10n.groupCreate),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text(l10n.groupCreate));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Gruppo di prova');

    // when
    await tester.tap(find.text(l10n.entryEditChooseIcon));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(
      find.byTooltip(l10n.entryEditIconNumber(KdbxIcon.key.index)),
    );
    await tester.pumpAndSettle();

    // then
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(GroupEditDialog), findsOneWidget);
    await tester.tap(find.text(l10n.entryEditSave));
    await tester.pumpAndSettle();
    expect(draft?.name, 'Gruppo di prova');
    expect(draft?.icon, KdbxIcon.key);
  });
}
