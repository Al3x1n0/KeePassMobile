import 'dart:ui' show SemanticsAction;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/ui/sensitive_text_editing.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'Copia e Taglia bloccati per menu, accessibilità e tastiera; Incolla disponibile',
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final writes = <Object?>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        switch (call.method) {
          case 'Clipboard.hasStrings':
            return {'value': true};
          case 'Clipboard.getData':
            return {'text': 'test-incolla'};
          case 'Clipboard.setData':
            writes.add(call.arguments);
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SensitiveTextEditing(
              child: TextField(
                controller: controller,
                selectionControls: SensitiveTextEditing.selectionControls,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'test-selezione');
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
      await tester.pump();

      final editable = find.byType(EditableText);
      final actions = tester.getSemantics(editable).getSemanticsData();
      expect(actions.hasAction(SemanticsAction.copy), isFalse);
      expect(actions.hasAction(SemanticsAction.cut), isFalse);

      final modifier = defaultTargetPlatform == TargetPlatform.iOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.sendKeyUpEvent(modifier);
      expect(writes, isEmpty);
      expect(controller.text, 'test-selezione');

      tester.state<EditableTextState>(editable).showToolbar();
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Cut'), findsNothing);
      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();
      expect(controller.text, 'test-incolla');

      final node = tester.getSemantics(editable);
      expect(node.getSemanticsData().hasAction(SemanticsAction.paste), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.paste);
      await tester.pumpAndSettle();
      expect(controller.text, 'test-incollatest-incolla');
    },
  );
}
