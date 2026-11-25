import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../shared/database/database_session.dart';
import 'database_navigation_bar.dart';
import 'routes.dart';

/// Mantiene la navigazione del database fuori dalle transizioni delle pagine.
class DatabaseNavigationShell extends ConsumerStatefulWidget {
  const DatabaseNavigationShell({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  /// Riserva nella schermata lo spazio misurato della barra condivisa.
  static Widget bottomBar(
    BuildContext context, {
    bool settingsSelected = false,
    bool generatorSelected = false,
    bool checkSelected = false,
  }) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DatabaseNavigationScope>();
    if (scope == null) {
      return DatabaseNavigationBar(
        settingsSelected: settingsSelected,
        generatorSelected: generatorSelected,
        checkSelected: checkSelected,
      );
    }
    return SizedBox(height: MediaQuery.paddingOf(context).bottom);
  }

  /// Aggiorna la visibilità della barra in seguito a una selezione nella pagina.
  static void selectionChanged(BuildContext context, bool active) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    context
        .getInheritedWidgetOfExactType<_DatabaseNavigationScope>()
        ?.onSelectionChanged(active);
  }

  @override
  ConsumerState<DatabaseNavigationShell> createState() =>
      _DatabaseNavigationShellState();
}

class _DatabaseNavigationShellState
    extends ConsumerState<DatabaseNavigationShell> {
  bool _selectionActive = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _closed = ref.read(databaseSessionProvider) == null;
    ref.listenManual(
      databaseSessionProvider.select((session) => session == null),
      (_, closed) {
        if (!closed || _closed) return;
        // I popup in uscita possono trattenere la vecchia route dopo il blocco.
        setState(() => _closed = true);
      },
    );
  }

  @override
  void didUpdateWidget(DatabaseNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.location != oldWidget.location) _selectionActive = false;
  }

  void _selectionChanged(bool active) {
    if (_selectionActive == active) return;
    setState(() => _selectionActive = active);
  }

  @override
  Widget build(BuildContext context) {
    if (_closed) return const SizedBox.shrink();
    final settingsSelected = widget.location == AppRoutes.appSettingsInDatabase;
    final generatorSelected = widget.location == AppRoutes.generate;
    final checkSelected = widget.location == AppRoutes.check;
    final groupLocation = Uri.parse(widget.location).pathSegments;
    final inGroup = groupLocation.length == 3 && groupLocation[1] == 'group';
    final showNavigation =
        !_selectionActive &&
        (widget.location == AppRoutes.database ||
            settingsSelected ||
            generatorSelected ||
            checkSelected ||
            inGroup);
    return _DatabaseNavigationScope(
      onSelectionChanged: _selectionChanged,
      child: Scaffold(
        extendBody: showNavigation,
        bottomNavigationBar: showNavigation
            ? DatabaseNavigationBar(
                settingsSelected: settingsSelected,
                generatorSelected: generatorSelected,
                checkSelected: checkSelected,
              )
            : null,
        body: ScaffoldMessenger(child: widget.child),
      ),
    );
  }
}

class _DatabaseNavigationScope extends InheritedWidget {
  const _DatabaseNavigationScope({
    required this.onSelectionChanged,
    required super.child,
  });

  final ValueChanged<bool> onSelectionChanged;

  @override
  bool updateShouldNotify(_DatabaseNavigationScope oldWidget) => false;
}
