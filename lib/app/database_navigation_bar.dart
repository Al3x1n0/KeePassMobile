import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import 'routes.dart';
import 'theme.dart';

/// Destinazioni principali durante la consultazione del database.
class DatabaseNavigationBar extends StatelessWidget {
  const DatabaseNavigationBar({super.key, this.settingsSelected = false});

  final bool settingsSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final navigationTheme = theme.navigationBarTheme;

    void selectDestination(int index) {
      switch (index) {
        case 0:
          if (settingsSelected && context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.database);
          }
        case 3 when !settingsSelected:
          context.push(AppRoutes.appSettingsInDatabase);
      }
    }

    final destinations = [
      (Icons.home_outlined, l10n.navigationHome, true),
      (Icons.casino_outlined, l10n.navigationGenerate, false),
      (Icons.shield_outlined, l10n.navigationCheck, false),
      (Icons.settings_outlined, l10n.settingsTitle, true),
    ];
    final selectedIndex = settingsSelected ? 3 : 0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: AppNavigationLayout.margin,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: const StadiumBorder(),
            shadows: [
              BoxShadow(
                color: navigationTheme.shadowColor ?? theme.colorScheme.shadow,
                blurRadius: AppNavigationLayout.shadowBlurRadius,
                offset: const Offset(0, AppSpacing.xs),
              ),
            ],
          ),
          child: ClipPath(
            clipper: const ShapeBorderClipper(shape: StadiumBorder()),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: AppNavigationLayout.blurSigma,
                sigmaY: AppNavigationLayout.blurSigma,
              ),
              child: Material(
                color: navigationTheme.backgroundColor,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: AppNavigationLayout.borderOpacity,
                    ),
                  ),
                ),
                child: Padding(
                  padding: AppNavigationLayout.surfacePadding,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final labelStyle =
                          navigationTheme.labelTextStyle?.resolve(
                            const <WidgetState>{},
                          ) ??
                          theme.textTheme.labelMedium;
                      final preferredWidths = <double>[];
                      for (final (_, label, enabled) in destinations) {
                        final painter = TextPainter(
                          text: TextSpan(text: label, style: labelStyle),
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                        )..layout();
                        preferredWidths.add(
                          math.max(
                            enabled
                                ? AppNavigationLayout.enabledMinWidth
                                : kMinInteractiveDimension,
                            painter.width +
                                (enabled
                                    ? AppNavigationLayout.labelSidePadding * 2
                                    : 0),
                          ),
                        );
                        painter.dispose();
                      }
                      final minimumWidth =
                          kMinInteractiveDimension * destinations.length;
                      final preferredWidth = preferredWidths.fold<double>(
                        0,
                        (sum, width) => sum + width,
                      );
                      final extraWidth =
                          math.max(0.0, constraints.maxWidth - preferredWidth) /
                          destinations.length;
                      final shrinkRatio = preferredWidth > constraints.maxWidth
                          ? math.max(
                              0.0,
                              (constraints.maxWidth - minimumWidth) /
                                  (preferredWidth - minimumWidth),
                            )
                          : 1.0;
                      final widths = [
                        for (final width in preferredWidths)
                          kMinInteractiveDimension +
                              (width - kMinInteractiveDimension) * shrinkRatio +
                              extraWidth,
                      ];

                      return IntrinsicHeight(
                        child: Stack(
                          children: [
                            AnimatedPositionedDirectional(
                              duration: AppNavigationLayout.transitionDuration,
                              curve: AppNavigationLayout.selectionCurve,
                              start: widths
                                  .take(selectedIndex)
                                  .fold<double>(0, (sum, width) => sum + width),
                              top: 0,
                              bottom: 0,
                              width: widths[selectedIndex],
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: navigationTheme.indicatorColor,
                                    shape: const StadiumBorder(),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final (index, destination)
                                    in destinations.indexed)
                                  SizedBox(
                                    width: widths[index],
                                    child: _DatabaseDestination(
                                      icon: destination.$1,
                                      label: destination.$2,
                                      selected: index == selectedIndex,
                                      onTap: destination.$3
                                          ? () => selectDestination(index)
                                          : null,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DatabaseDestination extends StatelessWidget {
  const _DatabaseDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navigationTheme = theme.navigationBarTheme;
    final states = {
      if (selected) WidgetState.selected,
      if (onTap == null) WidgetState.disabled,
    };
    final iconColor =
        navigationTheme.iconTheme?.resolve(states)?.color ??
        theme.colorScheme.onSurfaceVariant;
    final labelStyle =
        navigationTheme.labelTextStyle?.resolve(states) ??
        theme.textTheme.labelMedium ??
        DefaultTextStyle.of(context).style;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          color: Colors.transparent,
          shape: const StadiumBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: kMinInteractiveDimension,
                minHeight: AppNavigationLayout.destinationMinHeight,
              ),
              child: Padding(
                padding: onTap == null
                    ? AppNavigationLayout.disabledDestinationPadding
                    : AppNavigationLayout.destinationPadding,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: iconColor),
                      duration: AppNavigationLayout.transitionDuration,
                      curve: AppNavigationLayout.selectionCurve,
                      builder: (context, color, child) => Icon(
                        icon,
                        size: AppNavigationLayout.iconSize,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: AppNavigationLayout.iconLabelGap),
                    AnimatedDefaultTextStyle(
                      style: labelStyle,
                      duration: AppNavigationLayout.transitionDuration,
                      curve: AppNavigationLayout.selectionCurve,
                      child: Text(label, textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
