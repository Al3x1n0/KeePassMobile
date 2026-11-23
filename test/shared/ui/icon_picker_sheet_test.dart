import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/item_edits.dart';
import 'package:keepass_mobile/shared/ui/icon_picker_sheet.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../helpers/test_database.dart';

void main() {
  testWidgets('sceglie una icona personalizzata dalla bottom sheet', (
    tester,
  ) async {
    // given
    final db = newTestDatabase();
    final id = KdbxUuid.random();
    db.meta.customIcons[id] = KdbxCustomIcon(data: []);
    IconChoice? chosen;
    await tester.pumpWidget(
      _pickerApp((choice) => chosen = choice, database: db),
    );

    // when
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(sheet.showDragHandle, isTrue);
    expect(find.text('Import image'), findsOneWidget);
    await tester.tap(find.byTooltip('Custom icon'));
    await tester.pumpAndSettle();

    // then
    expect(chosen?.customId, id);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('scorre le icone standard e chiude anche senza sceglierne una', (
    tester,
  ) async {
    // given
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    IconChoice? chosen;
    await tester.pumpWidget(_pickerApp((choice) => chosen = choice));

    // when
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final selected = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == 'Icon ${KdbxIcon.key.index}',
      ),
    );
    expect(selected.isSelected, isTrue);
    final lastIcon = find.byTooltip('Icon ${KdbxIcon.values.last.index}');
    await tester.scrollUntilVisible(
      lastIcon,
      120,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(lastIcon);
    await tester.pumpAndSettle();

    // then
    expect(chosen?.icon, KdbxIcon.values.last);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(chosen, isNull);
    expect(find.byType(BottomSheet), findsNothing);
  });
}

Widget _pickerApp(
  void Function(IconChoice?) onChoice, {
  KdbxDatabase? database,
}) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => onChoice(
            await showIconPickerSheet(
              context: context,
              selected: KdbxIcon.key,
              database: database,
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);
