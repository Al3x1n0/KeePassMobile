import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../app/database_navigation_bar.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/entry_templates.dart';
import '../../shared/database/external_change.dart';
import '../../shared/database/item_edits.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/security/biometric_key_store.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/storage/file_storage.dart';
import '../../shared/storage/remote_storage.dart';
import '../file_select/recent_files.dart';
import '../../shared/ui/database_item_icon.dart';
import '../../shared/ui/cross_database_copy_dialog.dart';
import '../../shared/ui/linked_database_edit_dialog.dart';
import '../../shared/ui/entry_tile.dart';
import '../../shared/ui/group_destination_dialog.dart';
import '../../shared/ui/remote_cache_banner.dart';
import '../../shared/ui/selection_sheet.dart';
import '../database_settings/biometric_unlock_view_model.dart';
import '../export/export_view_model.dart';
import '../unlock/relock.dart';
import 'group_view_model.dart';
import 'group_edit_dialog.dart';

/// Elenco di sottogruppi e voci di un gruppo (GroupActivity di
/// Keepass2Android).
class GroupView extends ConsumerStatefulWidget {
  const GroupView({super.key, this.groupId});

  /// `null` per il gruppo radice.
  final String? groupId;

  @override
  ConsumerState<GroupView> createState() => _GroupViewState();
}

class _GroupViewState extends ConsumerState<GroupView> {
  final _selected = <String>{};

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = ref.watch(groupContentProvider(widget.groupId));
    // Database chiuso: il router sta già tornando alla scelta del file.
    if (content == null) return const Scaffold();
    final id = itemIdOf(content.group);
    final session = ref.watch(databaseSessionProvider)!;
    final inBin = isInRecycleBin(session.database, content.group);
    final protected =
        content.group == session.database.root ||
        content.group == content.recycleBin;
    final busy = ref.watch(itemActionsProvider(id)).isLoading;
    ref.listen(itemActionsProvider(id), (_, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeSaveError(l10n, error))));
      }
    });

    return _BiometricOfferHost(
      enabled: widget.groupId == null,
      child: PopScope(
        canPop: _selected.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _selected.isNotEmpty && !busy) {
            setState(_selected.clear);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              _selected.isEmpty
                  ? content.group.name
                  : l10n.itemsSelected(_selected.length),
            ),
            leading: _selected.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.cancel,
                    icon: const Icon(Icons.close),
                    onPressed: busy ? null : () => setState(_selected.clear),
                  ),
            actions: _selected.isNotEmpty
                ? [
                    if (ref
                                .read(databaseSessionProvider.notifier)
                                .openSessions
                                .length >
                            1 &&
                        !inBin)
                      IconButton(
                        tooltip: l10n.databasesCopy,
                        icon: const Icon(Icons.file_copy_outlined),
                        onPressed: busy
                            ? null
                            : () async {
                                if (await copyToAnotherDatabase(
                                      context,
                                      ref,
                                      _selected.toList(),
                                    ) &&
                                    mounted) {
                                  setState(_selected.clear);
                                }
                              },
                      ),
                    if (ref
                                .read(databaseSessionProvider.notifier)
                                .openSessions
                                .length >
                            1 &&
                        !inBin)
                      IconButton(
                        tooltip: l10n.databasesMove,
                        icon: const Icon(Icons.drive_file_move_outline),
                        onPressed: busy
                            ? null
                            : () async {
                                if (await copyToAnotherDatabase(
                                      context,
                                      ref,
                                      _selected.toList(),
                                      move: true,
                                    ) &&
                                    mounted) {
                                  setState(_selected.clear);
                                }
                              },
                      ),
                    IconButton(
                      tooltip: l10n.itemsSelectAll,
                      icon: const Icon(Icons.select_all),
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              _selected.addAll(
                                content.groups
                                    .where((g) => g != content.recycleBin)
                                    .map(itemIdOf),
                              );
                              _selected.addAll(content.entries.map(itemIdOf));
                            }),
                    ),
                    if (inBin)
                      IconButton(
                        tooltip: l10n.itemRestore,
                        icon: const Icon(Icons.restore),
                        onPressed: busy
                            ? null
                            : () => _restoreSelection(ref, id),
                      ),
                    if (!inBin)
                      IconButton(
                        tooltip: l10n.itemMoveTitle,
                        icon: const Icon(Icons.drive_file_move_outline),
                        onPressed: busy
                            ? null
                            : () => _moveSelection(context, ref, id),
                      ),
                    IconButton(
                      tooltip: l10n.entryDelete,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: busy
                          ? null
                          : () => _deleteSelection(
                              context,
                              ref,
                              id,
                              inBin || !session.database.meta.recycleBinEnabled,
                            ),
                    ),
                  ]
                : [
                    IconButton(
                      tooltip: l10n.searchTitle,
                      icon: const Icon(Icons.search),
                      onPressed: () => context.push(AppRoutes.search),
                    ),
                    PopupMenuButton<GroupSortOrder>(
                      tooltip: l10n.groupSort,
                      icon: const Icon(Icons.sort),
                      initialValue: ref.watch(groupSortOrderProvider),
                      onSelected: ref
                          .read(groupSortOrderProvider.notifier)
                          .select,
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: GroupSortOrder.ascending,
                          child: Text(l10n.groupSortAscending),
                        ),
                        PopupMenuItem(
                          value: GroupSortOrder.descending,
                          child: Text(l10n.groupSortDescending),
                        ),
                        PopupMenuItem(
                          value: GroupSortOrder.database,
                          child: Text(l10n.groupSortDatabase),
                        ),
                        PopupMenuItem(
                          value: GroupSortOrder.modification,
                          child: Text(l10n.groupSortModification),
                        ),
                        PopupMenuItem(
                          value: GroupSortOrder.creation,
                          child: Text(l10n.groupSortCreation),
                        ),
                      ],
                    ),
                    if (widget.groupId == null)
                      IconButton(
                        tooltip: l10n.databasesTitle,
                        icon: const Icon(Icons.folder_copy_outlined),
                        onPressed: busy
                            ? null
                            : () => _chooseDatabase(context, ref),
                      ),
                    IconButton(
                      tooltip: l10n.groupLock,
                      icon: const Icon(Icons.lock_outline),
                      onPressed: () =>
                          ref.read(relockProvider.notifier).lockAndReturn(),
                    ),
                    IconButton(
                      tooltip: l10n.groupMore,
                      icon: const Icon(Icons.more_vert),
                      onPressed: () async {
                        final route = await showSelectionSheet<String>(
                          context: context,
                          title: l10n.groupMore,
                          options: {
                            if (!inBin) ...{
                              _createGroup: l10n.groupCreate,
                              _editCurrent: l10n.groupEdit,
                              _installTemplates: l10n.templatesInstall,
                            },
                            if (!protected) ...{
                              if (!inBin) _moveCurrent: l10n.itemMoveTitle,
                              if (inBin) _restoreCurrent: l10n.itemRestore,
                              _deleteCurrent: l10n.groupDelete,
                            },
                            if (content.group == content.recycleBin)
                              _emptyBin: l10n.recycleBinEmpty,
                            if (widget.groupId == null &&
                                ref
                                        .read(databaseSessionProvider.notifier)
                                        .openSessions
                                        .length >
                                    1)
                              _linkedAdd: l10n.linkedDatabaseAdd,
                            AppRoutes.databaseSettings: l10n.dbSettingsTitle,
                            AppRoutes.changeMasterKey: l10n.changeKeyTitle,
                            _export: l10n.exportTitle,
                            _sync: l10n.syncNow,
                          },
                          disabled: busy
                              ? {
                                  _createGroup,
                                  _installTemplates,
                                  _editCurrent,
                                  _moveCurrent,
                                  _deleteCurrent,
                                  _restoreCurrent,
                                  _emptyBin,
                                }
                              : const {},
                        );
                        if (!context.mounted || route == null) return;
                        switch (route) {
                          case _linkedAdd:
                            await addLinkedDatabase(context, ref);
                          case _export:
                            _exportDatabase(context, ref);
                          case _sync:
                            _synchronize(context, ref);
                          case _createGroup:
                            _editGroup(context, ref, id);
                          case _installTemplates:
                            _addBuiltInTemplates(context, ref, id);
                          case _editCurrent:
                            _editGroup(
                              context,
                              ref,
                              id,
                              initial: GroupDraft(
                                name: content.group.name,
                                icon: content.group.icon,
                              ),
                            );
                          case _moveCurrent:
                            _moveGroup(
                              context,
                              ref,
                              id,
                              content.group.parent == null
                                  ? null
                                  : itemIdOf(content.group.parent!),
                            );
                          case _deleteCurrent:
                            _deleteGroup(
                              context,
                              ref,
                              id,
                              content.group.parent == null
                                  ? null
                                  : itemIdOf(content.group.parent!),
                              deletesPermanently(
                                session.database,
                                content.group,
                              ),
                            );
                          case _restoreCurrent:
                            _restoreGroup(context, ref, id);
                          case _emptyBin:
                            _emptyRecycleBin(context, ref, id);
                          default:
                            context.push(route);
                        }
                      },
                    ),
                  ],
          ),
          bottomNavigationBar: _selected.isEmpty
              ? const DatabaseNavigationBar()
              : null,
          floatingActionButton: inBin || _selected.isNotEmpty
              ? null
              : FloatingActionButton(
                  tooltip: l10n.groupAddEntry,
                  onPressed: () =>
                      _newEntry(context, session.database, content.group),
                  child: const Icon(Icons.add),
                ),
          body: Column(
            children: [
              const RemoteCacheBanner(),
              Expanded(
                child: content.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.l),
                          child: Text(l10n.groupEmpty),
                        ),
                      )
                    : ListView.builder(
                        itemCount:
                            content.groups.length + content.entries.length,
                        itemBuilder: (context, index) {
                          if (index < content.groups.length) {
                            final group = content.groups[index];
                            final isBin = group == content.recycleBin;
                            return ListTile(
                              leading: DatabaseItemIcon(
                                item: group,
                                database: session.database,
                                recycleBin: isBin,
                              ),
                              title: Text(
                                group.name,
                                style: TextStyle(
                                  fontSize: ref
                                      .watch(
                                        appSettingsProvider.select(
                                          (s) => s.listTextSize,
                                        ),
                                      )
                                      .toDouble(),
                                ),
                              ),
                              selected: _selected.contains(itemIdOf(group)),
                              onLongPress: isBin
                                  ? null
                                  : () => _toggle(itemIdOf(group)),
                              onTap: _selected.isNotEmpty
                                  ? (isBin
                                        ? null
                                        : () => _toggle(itemIdOf(group)))
                                  : () => context.push(
                                      AppRoutes.group(itemIdOf(group)),
                                    ),
                            );
                          }
                          final entry =
                              content.entries[index - content.groups.length];
                          final entryId = itemIdOf(entry);
                          return EntryTile(
                            entry: entry,
                            selected: _selected.contains(entryId),
                            onLongPress: () => _toggle(entryId),
                            onTap: _selected.isEmpty
                                ? null
                                : () => _toggle(entryId),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSelection(
    BuildContext context,
    WidgetRef ref,
    String id,
    bool permanent,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.entryDelete),
        content: Text(
          permanent ? l10n.itemsDeletePermanent : l10n.itemsDeleteRecycle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.entryDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await ref
        .read(itemActionsProvider(id).notifier)
        .deleteItems(_selected.toList());
    if (success && mounted) setState(_selected.clear);
  }

  Future<void> _moveSelection(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final database = ref.read(databaseSessionProvider)?.database;
    if (database == null) return;
    final selected = _selected.toList();
    final target = await showDialog<String>(
      context: context,
      builder: (_) => GroupDestinationsDialog(
        destinations: moveDestinations(database, selected),
      ),
    );
    if (target == null || !mounted) return;
    final success = await ref
        .read(itemActionsProvider(id).notifier)
        .moveItems(selected, target);
    if (success && mounted) setState(_selected.clear);
  }

  Future<void> _restoreSelection(WidgetRef ref, String id) async {
    final success = await ref
        .read(itemActionsProvider(id).notifier)
        .restoreItems(_selected.toList());
    if (success && mounted) setState(_selected.clear);
  }

  Future<void> _chooseDatabase(BuildContext context, WidgetRef ref) async {
    final sessions = ref.read(databaseSessionProvider.notifier);
    if (sessions.isSaving) return;
    final current = ref.read(databaseSessionProvider);
    final l10n = AppLocalizations.of(context);
    final selection = await showModalBottomSheet<({FileRef? file, bool close})>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final session in sessions.openSessions)
              ListTile(
                leading: Icon(
                  session.file == current?.file
                      ? Icons.check_circle
                      : Icons.folder_outlined,
                ),
                title: Text(session.file.name),
                trailing: IconButton(
                  tooltip: l10n.databasesClose,
                  icon: const Icon(Icons.close),
                  onPressed: () =>
                      Navigator.pop(context, (file: session.file, close: true)),
                ),
                onTap: () =>
                    Navigator.pop(context, (file: session.file, close: false)),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: Text(l10n.databasesOpenAnother),
              onTap: () => Navigator.pop(context, (file: null, close: false)),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || selection == null) return;
    final file = selection.file;
    if (file == null) {
      context.push(AppRoutes.additionalDatabase);
    } else if (selection.close) {
      if (sessions.openSessions.length == 1) {
        ref.read(relockProvider.notifier).lockAndReturn();
        return;
      }
      final closed = sessions.closeSession(file);
      ref.read(remoteSessionProvider).remove(file);
      final used = {
        for (final session in sessions.openSessions) ...[
          session.file,
          ?session.keyFile,
        ],
      };
      final release = {closed.file, ?closed.keyFile}.difference(used);
      await ref.read(recentFilesRepositoryProvider).releaseUnused(release);
      if (context.mounted) context.go(AppRoutes.database);
    } else if (file != current?.file) {
      sessions.switchTo(file);
      if (context.mounted) context.go(AppRoutes.database);
    }
  }

  static const _linkedAdd = 'linked-add';
  static const _createGroup = 'create-group';
  static const _installTemplates = 'install-templates';
  static const _editCurrent = 'edit-group';
  static const _moveCurrent = 'move-group';
  static const _deleteCurrent = 'delete-group';
  static const _restoreCurrent = 'restore-group';
  static const _emptyBin = 'empty-bin';

  Future<void> _addBuiltInTemplates(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.templatesInstall),
        content: Text(l10n.templatesInstallConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.templatesInstall),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(itemActionsProvider(id).notifier)
        .addBuiltInTemplates(
          BuiltInTemplateLabels(
            group: l10n.templateGroup,
            idCard: l10n.templateIdCard,
            wlan: l10n.templateWlan,
            note: l10n.templateNote,
            creditCard: l10n.templateCreditCard,
            membership: l10n.templateMembership,
            number: l10n.templateNumber,
            name: l10n.templateName,
            place: l10n.templatePlace,
            issueDate: l10n.templateIssueDate,
            holder: l10n.templateHolder,
          ),
        );
  }

  Future<void> _newEntry(
    BuildContext context,
    KdbxDatabase database,
    KdbxGroup group,
  ) async {
    final templates = entryTemplates(database);
    if (templates.isEmpty) {
      await context.push(AppRoutes.newEntry(itemIdOf(group)));
      return;
    }
    final l10n = AppLocalizations.of(context);
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.entryTemplateChoose),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(l10n.entryTemplateEmpty),
          ),
          for (final template in templates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, itemIdOf(template)),
              child: Text(
                entryTitle(template).isEmpty
                    ? l10n.entryUntitled
                    : entryTitle(template),
              ),
            ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    await context.push(
      AppRoutes.newEntry(itemIdOf(group)),
      extra: selected.isEmpty ? null : selected,
    );
  }

  Future<void> _editGroup(
    BuildContext context,
    WidgetRef ref,
    String id, {
    GroupDraft? initial,
  }) async {
    final draft = await showDialog<GroupDraft>(
      context: context,
      builder: (_) {
        final database = ref.read(databaseSessionProvider)?.database;
        return GroupEditDialog(
          initial: initial,
          database: database,
          group: initial == null || database == null
              ? null
              : findGroup(database, id),
        );
      },
    );
    if (draft == null || !context.mounted) return;
    final actions = ref.read(itemActionsProvider(id).notifier);
    if (initial == null) {
      await actions.create(draft);
    } else {
      await actions.editGroup(draft);
    }
  }

  Future<void> _moveGroup(
    BuildContext context,
    WidgetRef ref,
    String id,
    String? parent,
  ) async {
    final target = await showDialog<String>(
      context: context,
      builder: (_) => GroupDestinationDialog(itemId: id),
    );
    if (target == null || !context.mounted) return;
    if (await ref.read(itemActionsProvider(id).notifier).move(target) &&
        context.mounted) {
      context.go(parent == null ? AppRoutes.database : AppRoutes.group(parent));
    }
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String message,
  ) async {
    final l10n = AppLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.entryDelete),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteGroup(
    BuildContext context,
    WidgetRef ref,
    String id,
    String? parent,
    bool permanent,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (!await _confirm(
          context,
          l10n.groupDelete,
          permanent ? l10n.groupDeletePermanent : l10n.groupDeleteToBin,
        ) ||
        !context.mounted) {
      return;
    }
    if (await ref.read(itemActionsProvider(id).notifier).deleteGroup() &&
        context.mounted) {
      context.go(parent == null ? AppRoutes.database : AppRoutes.group(parent));
    }
  }

  Future<void> _restoreGroup(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    if (await ref.read(itemActionsProvider(id).notifier).restore() &&
        context.mounted) {
      context.go(AppRoutes.database);
    }
  }

  Future<void> _emptyRecycleBin(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final l10n = AppLocalizations.of(context);
    if (await _confirm(
          context,
          l10n.recycleBinEmpty,
          l10n.recycleBinEmptyConfirm,
        ) &&
        context.mounted) {
      await ref.read(itemActionsProvider(id).notifier).emptyBin();
    }
  }

  /// Voci del menu che non sono route.
  static const _export = 'export';
  static const _sync = 'sync';

  /// "Sincronizza ora": unisce le modifiche fatte altrove, se ci sono.
  Future<void> _synchronize(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    // Messaggi precedenti tolti: l'esito si vede subito.
    final messenger = ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.syncInProgress)));
    String message;
    try {
      message = switch (await ref
          .read(databaseSessionProvider.notifier)
          .synchronize()) {
        SyncResult.unchanged => l10n.syncUnchanged,
        SyncResult.synchronized => l10n.syncDone,
        SyncResult.pendingUpload => l10n.cachePending,
        SyncResult.offline => l10n.cacheOffline,
      };
    } on Object catch (e) {
      message = describeSaveError(l10n, e);
    }
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportDatabase(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final viewModel = ref.read(exportDatabaseViewModelProvider.notifier);
    // Mantiene vivo il ViewModel autoDispose durante il selettore.
    final keepAlive = ref.listenManual(
      exportDatabaseViewModelProvider,
      (_, _) {},
    );
    try {
      final name = await viewModel.export();
      final state = ref.read(exportDatabaseViewModelProvider);
      final message = switch ((name, state)) {
        (final n?, _) => l10n.exportDone(n),
        (_, AsyncError(:final error)) => describeSaveError(l10n, error),
        _ => null,
      };
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      keepAlive.close();
    }
  }
}

/// Proposta dello sblocco biometrico dopo uno sblocco con password (D23), nel
/// gruppo radice: "Attiva" chiede la biometria e salva la chiave derivata,
/// "Non chiedere più" vale per questo database; chiudere la finestra la
/// ripropone al prossimo sblocco con password.
class _BiometricOfferHost extends ConsumerStatefulWidget {
  const _BiometricOfferHost({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  ConsumerState<_BiometricOfferHost> createState() =>
      _BiometricOfferHostState();
}

class _BiometricOfferHostState extends ConsumerState<_BiometricOfferHost> {
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offer());
    }
  }

  Future<void> _offer() async {
    if (!mounted || _showing) return;
    final file = ref.read(biometricOfferProvider);
    if (file == null) return;
    ref.read(biometricOfferProvider.notifier).clear();
    if (ref.read(databaseSessionProvider)?.file != file) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    _showing = true;
    final enable = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.fingerprint),
        title: Text(l10n.biometricOfferTitle),
        content: Text(l10n.biometricOfferBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.biometricOfferNever),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.biometricOfferEnable),
          ),
        ],
      ),
    );
    _showing = false;
    if (!mounted || enable == null) return;
    if (!enable) {
      await ref.read(biometricKeyStoreProvider).declineOffer(file);
      return;
    }
    // Mantiene vivo il ViewModel autoDispose durante la richiesta biometrica.
    final keepAlive = ref.listenManual(
      biometricUnlockViewModelProvider,
      (_, _) {},
    );
    try {
      await ref
          .read(biometricUnlockViewModelProvider.notifier)
          .enable(
            BiometricPromptTexts(
              title: l10n.biometricEnableTitle,
              subtitle: file.name,
              cancel: l10n.biometricPromptCancel,
            ),
          );
      if (!mounted) return;
      final message = switch (ref.read(biometricUnlockViewModelProvider)) {
        AsyncData(value: true) => l10n.biometricOfferEnabled,
        AsyncError(error: BiometricKeyException(:final reason)) =>
          describeBiometricError(l10n, reason),
        AsyncError() => l10n.errorBiometricFailed,
        _ => null,
      };
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      keepAlive.close();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
