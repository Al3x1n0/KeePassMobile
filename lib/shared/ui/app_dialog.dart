import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

/// Azione di un dialog; lo stile dipende dal numero di scelte.
class AppDialogAction {
  /// Etichetta e callback dell'azione, disabilitata se la callback è nulla.
  const AppDialogAction({required this.onPressed, required this.child});

  /// Callback della scelta.
  final VoidCallback? onPressed;

  /// Etichetta localizzata.
  final Widget child;
}

/// Dialog uniforme: descrizione obbligatoria e due o tre scelte.
/// Con due scelte l'ultima è quella consigliata; con tre sono tutte neutre.
class AppDialog extends StatelessWidget {
  /// Crea una conferma o un modulo con descrizione e icona opzionale.
  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    required this.actions,
    this.content,
    this.icon,
  }) : assert(actions.length == 2 || actions.length == 3);

  /// Titolo della finestra.
  final Widget title;

  /// Descrizione della decisione richiesta.
  final Widget body;

  /// Eventuali campi o dettagli dopo la descrizione.
  final Widget? content;

  /// Icona facoltativa in testa.
  final Widget? icon;

  /// Scelte in ordine di visualizzazione.
  final List<AppDialogAction> actions;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: icon,
    title: title,
    content: content == null
        ? body
        : SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                body,
                const SizedBox(height: AppSpacing.m),
                content!,
              ],
            ),
          ),
    actions: [
      for (var i = 0; i < actions.length; i++)
        if (actions.length == 2 && i == 1)
          FilledButton(onPressed: actions[i].onPressed, child: actions[i].child)
        else
          TextButton(onPressed: actions[i].onPressed, child: actions[i].child),
    ],
  );
}
