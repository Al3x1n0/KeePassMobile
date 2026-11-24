import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';

/// Azione del popup condiviso, con icona e descrizione localizzata.
class ActionPopupItem<T> {
  /// Crea una voce del menu contestuale.
  const ActionPopupItem({
    required this.value,
    required this.icon,
    required this.label,
    this.enabled = true,
  });

  /// Valore inoltrato alla scelta dell'azione.
  final T value;

  /// Icona mostrata a sinistra dell'etichetta.
  final IconData icon;

  /// Etichetta localizzata dell'azione.
  final String label;

  /// Indica se l'azione è disponibile.
  final bool enabled;
}

/// Popup a tre puntini con lo stile condiviso dei menu dell'app.
class ActionPopupMenu<T> extends StatefulWidget {
  /// Crea il menu con le azioni disponibili nel contesto corrente.
  const ActionPopupMenu({
    super.key,
    required this.items,
    required this.onSelected,
    this.enabled = true,
  });

  /// Azioni mostrate nell'ordine indicato.
  final List<ActionPopupItem<T>> items;

  /// Callback dell'azione scelta, invocata solo se ancora abilitata.
  final ValueChanged<T> onSelected;

  /// Indica se il menu può aprirsi ed eseguire azioni.
  final bool enabled;

  @override
  State<ActionPopupMenu<T>> createState() => _ActionPopupMenuState<T>();
}

class _ActionPopupMenuState<T> extends State<ActionPopupMenu<T>> {
  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
    useRootNavigator: true,
    tooltip: AppLocalizations.of(context).groupMore,
    enabled: widget.enabled,
    icon: const Icon(Icons.more_vert),
    position: PopupMenuPosition.under,
    itemBuilder: (context) => [
      for (final item in widget.items)
        PopupMenuItem<T>(
          value: item.value,
          enabled: item.enabled,
          child: Row(
            children: [
              Icon(item.icon),
              const SizedBox(width: AppSpacing.m),
              Flexible(child: Text(item.label)),
            ],
          ),
        ),
    ],
    onSelected: (value) {
      if (widget.enabled &&
          widget.items.any((item) => item.value == value && item.enabled)) {
        widget.onSelected(value);
      }
    },
  );
}
