import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

/// Mostra una scelta singola; la chiusura senza scelta restituisce null.
Future<T?> showSelectionSheet<T>({
  required BuildContext context,
  required String title,
  T? selected,
  Set<T> disabled = const {},
  required Map<T, String> options,
}) => showListSheet<T>(
  context: context,
  title: title,
  buildItems: (context) => [
    for (final option in options.entries)
      ListTile(
        title: Text(option.value),
        enabled: !disabled.contains(option.key),
        selected: selected != null && option.key == selected,
        selectedColor: Theme.of(context).colorScheme.primary,
        trailing: selected != null && option.key == selected
            ? const Icon(Icons.check_circle)
            : null,
        onTap: disabled.contains(option.key)
            ? null
            : () => Navigator.of(context).pop(option.key),
      ),
  ],
);

/// Mostra un elenco scorrevole in un pannello con titolo e maniglia.
Future<T?> showListSheet<T>({
  required BuildContext context,
  required String title,
  required List<Widget> Function(BuildContext) buildItems,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.l,
                AppSpacing.s,
                AppSpacing.l,
                AppSpacing.m,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            ...buildItems(context),
            const SizedBox(height: AppSpacing.m),
          ],
        ),
      ),
    ),
  ),
);
