import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/ui/action_popup_menu.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('popup condiviso: icone, ordine e azioni disabilitate', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        locale: const Locale('it'),
        localizationsDelegates: [
          ...GlobalMaterialLocalizations.delegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          appBar: AppBar(
            actions: [
              ActionPopupMenu<String>(
                items: const [
                  ActionPopupItem(
                    value: 'edit',
                    icon: Icons.edit_outlined,
                    label: 'Modifica',
                  ),
                  ActionPopupItem(
                    value: 'duplicate',
                    icon: Icons.content_copy_outlined,
                    label: 'Duplica',
                    enabled: false,
                  ),
                ],
                onSelected: (value) => selected = value,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.content_copy_outlined), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Modifica')).dy,
      lessThan(tester.getTopLeft(find.text('Duplica')).dy),
    );
    await tester.tap(find.text('Duplica'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(find.text('Modifica'), findsOneWidget);
    await tester.tap(find.text('Modifica'));
    await tester.pumpAndSettle();
    expect(selected, 'edit');
    expect(find.text('Modifica'), findsNothing);
  });

  testWidgets('busy impedisce apertura e azioni di un popup già aperto', (
    tester,
  ) async {
    var enabled = true;
    var calls = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [
          ...GlobalMaterialLocalizations.delegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              appBar: AppBar(
                actions: [
                  ActionPopupMenu<int>(
                    enabled: enabled,
                    items: const [
                      ActionPopupItem(
                        value: 1,
                        icon: Icons.delete_outline,
                        label: 'Elimina',
                      ),
                    ],
                    onSelected: (_) => calls++,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    update(() => enabled = false);
    await tester.pump();
    await tester.tap(find.text('Elimina'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('Elimina'), findsNothing);
  });
}
