import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

/// Seconda riga dell'AppBar con azioni a destra e comando facoltativo a sinistra.
class AppBarActionRow extends StatelessWidget implements PreferredSizeWidget {
  const AppBarActionRow({super.key, required this.actions, this.leading});

  /// Azioni contestuali, allineate a destra e scorrevoli se necessario.
  final List<Widget> actions;

  /// Comando iniziale, separato dalle azioni dallo spazio disponibile.
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: preferredSize.height,
    child: LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: IntrinsicWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (leading case final control?) ...[control, const Spacer()],
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
