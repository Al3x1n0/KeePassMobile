import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Disabilita Copia e Taglia da tastiera nei campi di testo contenuti.
/// I campi devono anche usare [selectionControls] per i menu e l'accessibilità.
class SensitiveTextEditing extends StatelessWidget {
  const SensitiveTextEditing({super.key, required this.child});

  /// Mantiene Incolla e Seleziona tutto senza esportare il testo selezionato.
  static final TextSelectionControls selectionControls =
      _SensitiveSelectionControls();

  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: {CopySelectionTextIntent: DoNothingAction()},
    child: child,
  );
}

// Flutter consulta questi controlli anche per esporre le azioni semantiche.
// Il solo contextMenuBuilder filtrerebbe le azioni nel menu visibile.
class _SensitiveSelectionControls extends MaterialTextSelectionControls {
  @override
  bool canCopy(TextSelectionDelegate delegate) => false;

  @override
  bool canCut(TextSelectionDelegate delegate) => false;

  @override
  Widget buildToolbar(
    BuildContext context,
    Rect globalEditableRegion,
    double textLineHeight,
    Offset selectionMidpoint,
    List<TextSelectionPoint> endpoints,
    TextSelectionDelegate delegate,
    ValueListenable<ClipboardStatus>? clipboardStatus,
    Offset? lastSecondaryTapDownPosition,
  ) {
    final editable = delegate as EditableTextState;
    Widget toolbar(ClipboardStatus status) =>
        AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editable.contextMenuAnchors,
          buttonItems: [
            for (final item in editable.contextMenuButtonItems)
              if (item.kind == ContextMenuButtonKind.selectAll ||
                  (item.kind == ContextMenuButtonKind.paste &&
                      status == ClipboardStatus.pasteable))
                item,
          ],
        );
    return clipboardStatus == null
        ? toolbar(ClipboardStatus.pasteable)
        : ValueListenableBuilder<ClipboardStatus>(
            valueListenable: clipboardStatus,
            builder: (_, status, _) => toolbar(status),
          );
  }

  // EditableText effettua già Incolla dopo questo hook di accessibilità.
  @override
  Future<void> handlePaste(TextSelectionDelegate delegate) async {}
}
