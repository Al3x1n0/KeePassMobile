import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

/// Riquadro espandibile con stato locale, inizialmente aperto.
class ExpandableSection extends StatefulWidget {
  /// Crea un riquadro con intestazione cliccabile e contenuti condivisi.
  const ExpandableSection({
    super.key,
    required this.title,
    required this.children,
  });

  /// Titolo dell'intestazione accessibile.
  final String title;

  /// Contenuti mostrati quando il riquadro è aperto.
  final List<Widget> children;

  @override
  State<ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<ExpandableSection>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin<ExpandableSection> {
  late final AnimationController _controller;
  late final Animation<double> _expansion;
  late final Animation<double> _rotation;
  bool _expanded = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppSectionLayout.transitionDuration,
      value: 1,
    );
    _expansion = _controller.drive(
      CurveTween(curve: AppSectionLayout.transitionCurve),
    );
    _rotation = _expansion.drive(Tween(begin: 0.5, end: 0));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    final target = _expanded ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = target;
    } else {
      _controller.animateTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Padding(
      padding: AppSectionLayout.margin,
      child: Material(
        color: theme.colorScheme.primary.withValues(
          alpha: AppSectionLayout.backgroundOpacity,
        ),
        shape: AppSectionLayout.shape,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              expanded: _expanded,
              child: InkWell(
                onTap: _toggle,
                child: Padding(
                  padding: AppSectionLayout.headerPadding,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AppSectionLayout.headerMinHeight,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        RotationTransition(
                          turns: _rotation,
                          child: const Icon(Icons.expand_less),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizeTransition(
              sizeFactor: _expansion,
              alignment: Alignment.topCenter,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) =>
                    Offstage(offstage: _controller.value == 0, child: child),
                child: ExcludeSemantics(
                  excluding: !_expanded,
                  child: IgnorePointer(
                    ignoring: !_expanded,
                    child: ExcludeFocus(
                      excluding: !_expanded,
                      child: TickerMode(
                        enabled: _expanded,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: widget.children,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
