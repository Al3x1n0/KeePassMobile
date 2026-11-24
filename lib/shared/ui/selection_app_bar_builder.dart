import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';

/// Anima la seconda riga di selezione insieme allo spazio occupato dall'AppBar.
class SelectionAppBarBuilder extends StatelessWidget {
  /// Crea il contenitore che ricostruisce la pagina durante la transizione.
  const SelectionAppBarBuilder({
    super.key,
    required this.showSelectAll,
    required this.onSelectAll,
    required this.builder,
  });

  /// Indica se restano elementi da selezionare nella vista corrente.
  final bool showSelectAll;

  /// Comando di selezione completa, oppure `null` durante un'operazione.
  final VoidCallback? onSelectAll;

  /// Costruisce la pagina con la seconda riga da passare ad `AppBar.bottom`.
  final Widget Function(BuildContext context, PreferredSizeWidget? bottom)
  builder;

  static const _rowHeight = 48.0;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(
      begin: showSelectAll ? 1 : 0,
      end: showSelectAll ? 1 : 0,
    ),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppSectionLayout.transitionDuration,
    curve: AppSectionLayout.transitionCurve,
    builder: (context, factor, _) => builder(
      context,
      factor == 0
          ? null
          : PreferredSize(
              preferredSize: Size.fromHeight(_rowHeight * factor),
              child: ClipRect(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  heightFactor: factor,
                  child: SizedBox(
                    height: _rowHeight,
                    child: ExcludeSemantics(
                      excluding: !showSelectAll,
                      child: ExcludeFocus(
                        excluding: !showSelectAll,
                        child: IgnorePointer(
                          ignoring: !showSelectAll,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.s,
                            ),
                            child: Row(
                              children: [
                                Flexible(
                                  child: TextButton(
                                    onPressed: onSelectAll,
                                    child: Text(
                                      AppLocalizations.of(context)
                                          .itemsSelectAllShort,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    ),
  );
}
