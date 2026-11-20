import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../shared/database/database_session.dart';
import '../shared/database/linked_databases.dart';
import '../shared/storage/file_storage.dart';
import 'router.dart';

/// Runs only the passive database-opening subset of AutoOpen.
class LinkedDatabaseHost extends ConsumerStatefulWidget {
  const LinkedDatabaseHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<LinkedDatabaseHost> createState() => _LinkedDatabaseHostState();
}

class _LinkedDatabaseHostState extends ConsumerState<LinkedDatabaseHost> {
  bool _running = false;
  final _processed = <String>{};
  DialogRoute<bool>? _approvalRoute;
  LinkedOpenOperation? _opening;
  FileRef? _openingParent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _onSession(DatabaseSession? previous, DatabaseSession? next) {
    if (next == null) {
      _processed.clear();
      _opening?.cancel();
      final route = _approvalRoute;
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
      _approvalRoute = null;
    } else if (_openingParent case final parent?
        when !ref
            .read(databaseSessionProvider.notifier)
            .openSessions
            .any((s) => s.file == parent)) {
      _opening?.cancel();
    } else if (!_processed.contains(next.file.uri)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  Future<bool> _confirm(LinkedDatabase link) async {
    final navigator = ref
        .read(routerProvider)
        .routerDelegate
        .navigatorKey
        .currentState;
    final context = navigator?.context;
    if (navigator == null || context == null || !context.mounted) return false;
    final l10n = AppLocalizations.of(context);
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.linkedDatabaseTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.linkedDatabaseBody(link.file.uri, link.keyFile?.uri ?? ''),
              ),
              if (link.deviceRule.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(l10n.linkedDatabaseDeviceWarning),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.linkedDatabaseAllow),
          ),
        ],
      ),
    );
    _approvalRoute = route;
    try {
      return await navigator.push(route) ?? false;
    } finally {
      if (identical(_approvalRoute, route)) _approvalRoute = null;
    }
  }

  Future<void> _start() async {
    if (!mounted || _running) return;
    final sessions = ref.read(databaseSessionProvider.notifier);
    if (sessions.isSaving) return;
    final firstFile = ref.read(databaseSessionProvider)?.file;
    if (firstFile == null || _processed.contains(firstFile.uri)) return;
    final generation = sessions.lockGeneration;
    final pending = <FileRef>[firstFile];
    _running = true;
    try {
      while (pending.isNotEmpty &&
          _processed.length < 32 &&
          mounted &&
          sessions.lockGeneration == generation) {
        final parentFile = pending.removeAt(0);
        if (!_processed.add(parentFile.uri)) continue;
        DatabaseSession? lookup() => sessions.openSessions
            .where((s) => s.file == parentFile)
            .firstOrNull;
        final links = () {
          final parent = lookup();
          return parent == null ? <LinkedDatabase>[] : linkedDatabases(parent);
        }();
        for (final link in links) {
          if (!mounted ||
              sessions.lockGeneration != generation ||
              lookup() == null) {
            return;
          }
          if (sessions.openSessions.any((s) => s.file == link.file) ||
              _processed.contains(link.file.uri)) {
            continue;
          }
          final approvals = ref.read(linkedDatabaseApprovalsProvider);
          final id = linkedDatabaseApprovalId(parentFile, link);
          if (!approvals.contains(id)) {
            if (!await _confirm(link)) continue;
            if (!mounted ||
                sessions.lockGeneration != generation ||
                lookup() == null) {
              return;
            }
            try {
              await approvals.add(id);
            } on Object {
              continue;
            }
          }
          if (!mounted ||
              sessions.lockGeneration != generation ||
              lookup() == null) {
            return;
          }
          final operation = LinkedOpenOperation(
            ref.read(fileStorageProvider),
            lookup,
            link,
          );
          _opening = operation;
          _openingParent = parentFile;
          try {
            final child = await operation.run();
            if (!mounted ||
                sessions.lockGeneration != generation ||
                lookup() == null) {
              return;
            }
            final selected = ref.read(databaseSessionProvider)?.file;
            sessions.openAdditional(child, generation);
            pending.add(child.file);
            if (selected != null &&
                sessions.openSessions.any((s) => s.file == selected)) {
              sessions.switchTo(selected);
            }
          } on Object {
            if (mounted && sessions.lockGeneration == generation) {
              final navigator = ref
                  .read(routerProvider)
                  .routerDelegate
                  .navigatorKey
                  .currentContext;
              if (navigator != null && navigator.mounted) {
                ScaffoldMessenger.maybeOf(navigator)?.showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(navigator).linkedDatabaseFailure,
                    ),
                  ),
                );
              }
            }
          } finally {
            if (identical(_opening, operation)) {
              _opening = null;
              _openingParent = null;
            }
          }
        }
      }
    } finally {
      _running = false;
      if (mounted) {
        final current = ref.read(databaseSessionProvider);
        if (current != null && !_processed.contains(current.file.uri)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _start());
        }
      }
    }
  }

  @override
  void dispose() {
    _opening?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DatabaseSession?>(databaseSessionProvider, _onSession);
    return widget.child;
  }
}
