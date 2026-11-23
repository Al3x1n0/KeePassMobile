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
                      alpha: 0.45,
                    ),
                  ),
                ),
                child: Padding(
                  padding: AppNavigationLayout.surfacePadding,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, destination) in destinations.indexed)
                          Expanded(
                            child: _DatabaseDestination(
                              icon: destination.$1,
                              label: destination.$2,
                              selected: index == (settingsSelected ? 3 : 0),
                              onTap: destination.$3
                                  ? () => selectDestination(index)
                                  : null,
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
    final navigationTheme = Theme.of(context).navigationBarTheme;
    final states = {
      if (selected) WidgetState.selected,
      if (onTap == null) WidgetState.disabled,
    };
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          color: selected ? navigationTheme.indicatorColor : Colors.transparent,
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
                padding: AppNavigationLayout.destinationPadding,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconTheme(
                      data:
                          navigationTheme.iconTheme?.resolve(states) ??
                          const IconThemeData(),
                      child: Icon(icon, size: AppNavigationLayout.iconSize),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: navigationTheme.labelTextStyle?.resolve(states),
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
