import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kpasslib/kpasslib.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/database_navigation_shell.dart';
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
import '../../shared/ui/action_popup_menu.dart';
import '../../shared/ui/selection_app_bar_builder.dart';
import '../../shared/ui/cross_database_copy_sheet.dart';
import '../../shared/ui/database_item_icon.dart';
import '../../shared/ui/entry_tile.dart';
import '../../shared/ui/expandable_section.dart';
import '../../shared/ui/group_destination_sheet.dart';
import '../../shared/ui/remote_cache_banner.dart';
import '../../shared/ui/selection_sheet.dart';
import '../database_settings/biometric_unlock_view_model.dart';
import '../file_select/recent_files.dart';
import '../favorites/favorites_view_model.dart';
import '../recent_passwords/recent_passwords_view_model.dart';
import '../unlock/relock.dart';
import 'group_edit_dialog.dart';
import 'group_view_model.dart';

enum _HomeAction { favorites, sort, databases, synchronize, recycleBin, lock }

enum _ItemAction {
  edit,
  move,
  duplicate,
  delete,
  restore,
  copyDatabase,
  moveDatabase,
}

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
  bool _synchronizing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = ref.watch(groupContentProvider(widget.groupId));
    // Database chiuso: il router sta già tornando alla scelta del file.
    if (content == null) return const Scaffold();
    final id = itemIdOf(content.group);
    final session = ref.watch(databaseSessionProvider)!;
    final recycleBin = content.recycleBin;
    final inBin = isInRecycleBin(session.database, content.group);
    final visibleGroups = content.groups.where((g) => g != recycleBin).toList();
    final selectedGroup = !inBin && _selected.length == 1
        ? visibleGroups
              .where((g) => itemIdOf(g) == _selected.single)
              .firstOrNull
        : null;
    final selectedItemId = _selected.length == 1 ? _selected.single : null;
    final selectedEntries = content.entries
        .where((entry) => _selected.contains(itemIdOf(entry)))
        .toList();
    final entriesOnly =
        !inBin &&
        _selected.isNotEmpty &&
        selectedEntries.length == _selected.length;
    final allFavorites = entriesOnly && selectedEntries.every(isEntryFavorite);
    final selectedEntry =
        !inBin && selectedEntries.length == 1 && _selected.length == 1
        ? selectedEntries.single
        : null;
    var busy = _synchronizing;
    for (final actionId in {id, ?selectedItemId}) {
      final actions = itemActionsProvider(actionId);
      final actionBusy = ref.watch(actions).isLoading;
      busy = busy || actionBusy;
      ref.listen(actions, (_, next) {
        if (next case AsyncError(:final error)
            when ModalRoute.isCurrentOf(context) != false) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(describeSaveError(l10n, error))),
          );
        }
      });
    }
    final recentEntries = widget.groupId == null && _selected.isEmpty
        ? ref.watch(recentPasswordEntriesProvider)
        : const <KdbxEntry>[];
    final hasFavorites =
        widget.groupId == null &&
        _selected.isEmpty &&
        (ref.watch(favoriteEntriesProvider)?.isNotEmpty ?? false);
    final recentSectionCount = recentEntries.isEmpty ? 0 : 1;
    final listIsEmpty =
        visibleGroups.isEmpty &&
        content.entries.isEmpty &&
        recentEntries.isEmpty;

    void toggleSelection(String itemId) {
      if (busy) return;
      _updateSelection(() {
        if (!_selected.remove(itemId)) _selected.add(itemId);
      });
    }

    void selectAll() => _updateSelection(() {
      _selected.addAll(visibleGroups.map(itemIdOf));
      _selected.addAll(content.entries.map(itemIdOf));
    });

    final hasUnselectedItems =
        visibleGroups.any((group) => !_selected.contains(itemIdOf(group))) ||
        content.entries.any((entry) => !_selected.contains(itemIdOf(entry)));

    final hasOtherDatabases =
        ref.read(databaseSessionProvider.notifier).openSessions.length > 1;
    final itemMenu = <ActionPopupItem<_ItemAction>>[
      if (!inBin) ...[
        if (_selected.isEmpty || selectedGroup != null || selectedEntry != null)
          ActionPopupItem(
            value: _ItemAction.edit,
            icon: Icons.edit_outlined,
            label: l10n.entryEdit,
          ),
        ActionPopupItem(
          value: _ItemAction.move,
          icon: Icons.drive_file_move_outline,
          label: l10n.itemMoveTitle,
        ),
        if (selectedEntry != null)
          ActionPopupItem(
            value: _ItemAction.duplicate,
            icon: Icons.content_copy_outlined,
            label: l10n.itemDuplicate,
          ),
      ] else
        ActionPopupItem(
          value: _ItemAction.restore,
          icon: Icons.restore,
          label: l10n.itemRestore,
        ),
      ActionPopupItem(
        value: _ItemAction.delete,
        icon: Icons.delete_outline,
        label: l10n.entryDelete,
      ),
      if (_selected.isNotEmpty && !inBin && hasOtherDatabases) ...[
        ActionPopupItem(
          value: _ItemAction.copyDatabase,
          icon: Icons.file_copy_outlined,
          label: l10n.databasesCopy,
        ),
        ActionPopupItem(
          value: _ItemAction.moveDatabase,
          icon: Icons.drive_file_move_outline,
          label: l10n.databasesMove,
        ),
      ],
    ];
    final itemActions = <Widget>[
      if (entriesOnly)
        IconButton(
          tooltip: allFavorites
              ? l10n.entryFavoriteRemove
              : l10n.entryFavoriteAdd,
          isSelected: allFavorites,
          color: allFavorites ? Theme.of(context).colorScheme.primary : null,
          icon: const Icon(Icons.star_border),
          selectedIcon: const Icon(Icons.star),
          onPressed: busy
              ? null
              : () => ref
                    .read(itemActionsProvider(id).notifier)
                    .setFavorites(_selected.toList(), !allFavorites),
        ),
      ActionPopupMenu<_ItemAction>(
        enabled: !busy,
        items: itemMenu,
        onSelected: (action) async {
          switch (action) {
            case _ItemAction.edit:
              if (selectedEntry != null) {
                final entryId = itemIdOf(selectedEntry);
                _updateSelection(_selected.clear);
                context.push(AppRoutes.entryEdit(entryId));
              } else {
                final group = selectedGroup ?? content.group;
                await _editGroup(
                  context,
                  ref,
                  itemIdOf(group),
                  initial: GroupDraft(name: group.name, icon: group.icon),
                );
                if (mounted && _selected.isNotEmpty) {
                  _updateSelection(_selected.clear);
                }
              }
            case _ItemAction.move:
              if (_selected.isNotEmpty) {
                await _moveSelection(context, ref, id);
              } else {
                final target = await showGroupDestinationSheet(context, [id]);
                if (target != null && mounted) {
                  await ref.read(itemActionsProvider(id).notifier).move(target);
                }
              }
            case _ItemAction.duplicate:
              if (selectedItemId == null) return;
              final copy = await ref
                  .read(itemActionsProvider(selectedItemId).notifier)
                  .duplicate(l10n.itemDuplicateSuffix);
              if (copy != null && mounted) _updateSelection(_selected.clear);
            case _ItemAction.delete:
              if (_selected.isNotEmpty) {
                await _deleteSelection(
                  context,
                  ref,
                  id,
                  inBin || !session.database.meta.recycleBinEnabled,
                );
              } else {
                await _deleteCurrentGroup(
                  content.group,
                  inBin || !session.database.meta.recycleBinEnabled,
                );
              }
            case _ItemAction.restore:
              if (_selected.isNotEmpty) {
                await _restoreSelection(ref, id);
              } else {
                await ref.read(itemActionsProvider(id).notifier).restore();
              }
            case _ItemAction.copyDatabase:
            case _ItemAction.moveDatabase:
              if (await copyToAnotherDatabase(
                    context,
                    ref,
                    _selected.toList(),
                    move: action == _ItemAction.moveDatabase,
                  ) &&
                  mounted) {
                _updateSelection(_selected.clear);
              }
          }
        },
      ),
    ];

    return _BiometricOfferHost(
      enabled: widget.groupId == null,
      child: PopScope(
        canPop: _selected.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _selected.isNotEmpty && !busy) {
            _updateSelection(_selected.clear);
          }
        },
        child: SelectionAppBarBuilder(
          showSelectAll: _selected.isNotEmpty && hasUnselectedItems,
          onSelectAll: busy ? null : selectAll,
          builder: (context, bottom) => Scaffold(
            extendBody: _selected.isEmpty,
            appBar: AppBar(
              title: Text(
                _selected.isEmpty
                    ? content.group == recycleBin
                          ? l10n.dbSettingsRecycleBin
                          : content.group.name
                    : l10n.itemsSelected(_selected.length),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              leading: _selected.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.cancel,
                      icon: const Icon(Icons.close),
                      onPressed: busy
                          ? null
                          : () => _updateSelection(_selected.clear),
                    ),
              actions: _selected.isNotEmpty
                  ? itemActions
                  : widget.groupId == null
                  ? [
                      IconButton(
                        tooltip: l10n.searchTitle,
                        icon: const Icon(Icons.search),
                        onPressed: () => context.push(AppRoutes.search),
                      ),
                      ActionPopupMenu<_HomeAction>(
                        items: [
                          if (hasFavorites)
                            _homeMenuItem(
                              _HomeAction.favorites,
                              Icons.star_border,
                              l10n.favoritesTitle,
                            ),
                          _homeMenuItem(
                            _HomeAction.sort,
                            Icons.sort,
                            l10n.groupSort,
                          ),
                          _homeMenuItem(
                            _HomeAction.databases,
                            Icons.folder_copy_outlined,
                            l10n.databasesTitle,
                            enabled: !busy,
                          ),
                          _homeMenuItem(
                            _HomeAction.synchronize,
                            Icons.sync,
                            l10n.syncNow,
                            enabled: !busy,
                          ),
                          if (recycleBin != null &&
                              (recycleBin.groups.isNotEmpty ||
                                  recycleBin.entries.isNotEmpty))
                            _homeMenuItem(
                              _HomeAction.recycleBin,
                              Icons.delete_outline,
                              l10n.dbSettingsRecycleBin,
                            ),
                          _homeMenuItem(
                            _HomeAction.lock,
                            Icons.lock_outline,
                            l10n.groupLock,
                          ),
                        ],
                        onSelected: (action) {
                          switch (action) {
                            case _HomeAction.favorites:
                              context.push(AppRoutes.favorites);
                            case _HomeAction.sort:
                              _chooseSortOrder(context, ref);
                            case _HomeAction.databases:
                              _chooseDatabase(context, ref);
                            case _HomeAction.synchronize:
                              _synchronize(context, ref);
                            case _HomeAction.recycleBin:
                              if (recycleBin != null) {
                                context.push(
                                  AppRoutes.group(itemIdOf(recycleBin)),
                                );
                              }
                            case _HomeAction.lock:
                              ref.read(relockProvider.notifier).lockAndReturn();
                          }
                        },
                      ),
                    ]
                  : content.group == recycleBin
                  ? null
                  : itemActions,
              bottom: bottom,
            ),
            bottomNavigationBar: _selected.isEmpty
                ? DatabaseNavigationShell.bottomBar(context)
                : null,
            floatingActionButton: inBin || _selected.isNotEmpty
                ? null
                : FloatingActionButton(
                    tooltip: l10n.groupAddEntry,
                    onPressed: busy
                        ? null
                        : () => _addItem(context, session.database, id),
                    child: const Icon(Icons.add),
                  ),
            body: Builder(
              builder: (context) => Column(
                children: [
                  const RemoteCacheBanner(),
                  Expanded(
                    child: listIsEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.l),
                              child: Text(l10n.groupEmpty),
                            ),
                          )
                        : ListView.builder(
                            padding: _selected.isEmpty
                                ? EdgeInsets.only(
                                    bottom:
                                        MediaQuery.paddingOf(context).bottom +
                                        (inBin
                                            ? AppSpacing.m
                                            : AppNavigationLayout.fabClearance),
                                  )
                                : null,
                            itemCount:
                                recentSectionCount +
                                visibleGroups.length +
                                content.entries.length,
                            itemBuilder: (context, index) {
                              if (index < recentSectionCount) {
                                return _RecentPasswordsSection(
                                  entries: recentEntries,
                                );
                              }
                              final groupIndex = index - recentSectionCount;
                              if (groupIndex < visibleGroups.length) {
                                final group = visibleGroups[groupIndex];
                                final groupId = itemIdOf(group);
                                return ListTile(
                                  leading: DatabaseItemIcon(
                                    item: group,
                                    database: session.database,
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
                                  selected: _selected.contains(groupId),
                                  onLongPress: () => toggleSelection(groupId),
                                  onTap: _selected.isNotEmpty
                                      ? () => toggleSelection(groupId)
                                      : () => context.push(
                                          AppRoutes.group(groupId),
                                        ),
                                );
                              }
                              final entry = content
                                  .entries[groupIndex - visibleGroups.length];
                              final entryId = itemIdOf(entry);
                              return EntryTile(
                                entry: entry,
                                selected: _selected.contains(entryId),
                                showChevron: _selected.isEmpty,
                                onLongPress: () => toggleSelection(entryId),
                                onTap: _selected.isEmpty
                                    ? null
                                    : () => toggleSelection(entryId),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _updateSelection(VoidCallback change) {
    setState(change);
    DatabaseNavigationShell.selectionChanged(context, _selected.isNotEmpty);
  }

  ActionPopupItem<_HomeAction> _homeMenuItem(
    _HomeAction action,
    IconData icon,
    String label, {
    bool enabled = true,
  }) => ActionPopupItem(
    value: action,
    icon: icon,
    label: label,
    enabled: enabled,
  );

  Future<void> _deleteCurrentGroup(KdbxGroup group, bool permanent) async {
    final groupId = itemIdOf(group);
    final parentId = group.parent == null ? null : itemIdOf(group.parent!);
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
        .read(itemActionsProvider(groupId).notifier)
        .deleteGroup();
    if (!success || !mounted) return;
    final database = ref.read(databaseSessionProvider)?.database;
    if (database == null) return;
    final parent = findGroup(database, parentId);
    context.go(
      parent == null || parent == database.root
          ? AppRoutes.database
          : AppRoutes.group(itemIdOf(parent)),
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
    if (success && mounted) _updateSelection(_selected.clear);
  }

  Future<void> _moveSelection(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final selected = _selected.toList();
    final target = await showGroupDestinationSheet(context, selected);
    if (target == null || !mounted) return;
    final success = await ref
        .read(itemActionsProvider(id).notifier)
        .moveItems(selected, target);
    if (success && mounted) _updateSelection(_selected.clear);
  }

  Future<void> _restoreSelection(WidgetRef ref, String id) async {
    final success = await ref
        .read(itemActionsProvider(id).notifier)
        .restoreItems(_selected.toList());
    if (success && mounted) _updateSelection(_selected.clear);
  }

  Future<void> _chooseSortOrder(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final order = await showSelectionSheet<GroupSortOrder>(
      context: context,
      title: l10n.groupSort,
      selected: ref.read(groupSortOrderProvider),
      options: {
        GroupSortOrder.ascending: l10n.groupSortAscending,
        GroupSortOrder.descending: l10n.groupSortDescending,
        GroupSortOrder.database: l10n.groupSortDatabase,
        GroupSortOrder.modification: l10n.groupSortModification,
        GroupSortOrder.creation: l10n.groupSortCreation,
      },
    );
    if (context.mounted && order != null) {
      await ref.read(groupSortOrderProvider.notifier).select(order);
    }
  }

  Future<void> _chooseDatabase(BuildContext context, WidgetRef ref) async {
    final sessions = ref.read(databaseSessionProvider.notifier);
    if (sessions.isSaving) return;
    final current = ref.read(databaseSessionProvider);
    final l10n = AppLocalizations.of(context);
    final selection = await showListSheet<({FileRef? file, bool close})>(
      context: context,
      title: l10n.databasesTitle,
      buildItems: (context) => [
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

  static const _newGroup = 'group';

  Future<void> _addItem(
    BuildContext context,
    KdbxDatabase database,
    String groupId,
  ) async {
    final templates = entryTemplates(database);
    final l10n = AppLocalizations.of(context);
    final selected = await showSelectionSheet<String>(
      context: context,
      title: l10n.groupAddTitle,
      options: {
        '': l10n.entryTemplateEmpty,
        _newGroup: l10n.groupCreate,
        for (final template in templates)
          itemIdOf(template): entryTitle(template).isEmpty
              ? l10n.entryUntitled
              : entryTitle(template),
      },
    );
    if (selected == null || !context.mounted) return;
    if (selected == _newGroup) {
      await _editGroup(context, ref, groupId);
      return;
    }
    await context.push(
      AppRoutes.newEntry(groupId),
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

  /// "Sincronizza ora": unisce le modifiche fatte altrove, se ci sono.
  Future<void> _synchronize(BuildContext context, WidgetRef ref) async {
    if (_synchronizing) return;
    setState(() => _synchronizing = true);
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
    if (!mounted) return;
    setState(() => _synchronizing = false);
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _RecentPasswordsSection extends StatelessWidget {
  const _RecentPasswordsSection({required this.entries});

  final List<KdbxEntry> entries;

  @override
  Widget build(BuildContext context) => ExpandableSection(
    title: AppLocalizations.of(context).recentPasswordsTitle,
    children: [for (final entry in entries) EntryTile(entry: entry)],
  );
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
