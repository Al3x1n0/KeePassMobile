import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/ui/action_popup_menu.dart';
import '../../shared/ui/selection_app_bar_builder.dart';
import '../../shared/ui/entry_tile.dart';
import '../../shared/ui/cross_database_copy_sheet.dart';
import '../../shared/ui/group_destination_sheet.dart';
import '../../shared/ui/selection_sheet.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/item_edits.dart';
import '../../shared/database/kdbx_items.dart';
import '../favorites/favorites_view_model.dart';
import 'search_view_model.dart';

enum _SearchSelectionAction {
  edit,
  move,
  duplicate,
  delete,
  group,
  copyDatabase,
  moveDatabase,
}

class _SearchHit {
  const _SearchHit(this.result, this.session);
  final SearchResult result;
  final DatabaseSession session;
  KdbxEntry get entry => result.entry;
  String get groupPath => result.groupPath;
}

/// Ricerca nelle voci del database (SearchActivity di Keepass2Android).
class SearchView extends ConsumerStatefulWidget {
  const SearchView({super.key});

  @override
  ConsumerState<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends ConsumerState<SearchView> {
  final _query = TextEditingController();
  final _selected = <String>{};
  void _toggleSelection(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  (String, String)? _sessionKey(DatabaseSession? session) => session == null
      ? null
      : (session.file.uri, itemIdOf(session.database.root));

  Future<void> _deleteSelection(String rootId, bool permanent) async {
    final sessionKey = _sessionKey(ref.read(databaseSessionProvider));
    final selected = _selected.toList();
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
    if (confirmed != true ||
        !mounted ||
        _sessionKey(ref.read(databaseSessionProvider)) != sessionKey) {
      return;
    }
    final success = await ref
        .read(itemActionsProvider(rootId).notifier)
        .deleteSearchEntries(selected);
    if (success && mounted) {
      setState(() {
        _selected.clear();
        _invalidateRegex();
      });
    }
  }

  Future<void> _moveSelection(String rootId) async {
    final sessionKey = _sessionKey(ref.read(databaseSessionProvider));
    final selected = _selected.toList();
    final destination = await showGroupDestinationSheet(context, selected);
    if (destination == null ||
        !mounted ||
        _sessionKey(ref.read(databaseSessionProvider)) != sessionKey) {
      return;
    }
    final success = await ref
        .read(itemActionsProvider(rootId).notifier)
        .moveSearchEntries(selected, destination);
    if (success && mounted) {
      setState(() {
        _selected.clear();
        _invalidateRegex();
      });
    }
  }

  Future<void> _duplicateSelection(String entryId) async {
    final sessionKey = _sessionKey(ref.read(databaseSessionProvider));
    final duplicate = await ref
        .read(itemActionsProvider(entryId).notifier)
        .duplicate(AppLocalizations.of(context).itemDuplicateSuffix);
    if (duplicate != null &&
        mounted &&
        _sessionKey(ref.read(databaseSessionProvider)) == sessionKey) {
      setState(() {
        _selected.clear();
        _invalidateRegex();
      });
    }
  }

  Future<void> _transferSelection({required bool move}) async {
    if (await copyToAnotherDatabase(
          context,
          ref,
          _selected.toList(),
          move: move,
        ) &&
        mounted) {
      setState(() {
        _selected.clear();
        _invalidateRegex();
      });
    }
  }

  final _fields = <String, bool>{
    'title': true,
    'userName': true,
    'url': true,
    'notes': true,
    'other': true,
    'tags': true,
    'password': false,
    'group': false,
    'regex': false,
    'caseSensitive': false,
    'excludeExpired': false,
  };

  SearchOptions get _options => SearchOptions(
    title: _fields['title']!,
    userName: _fields['userName']!,
    url: _fields['url']!,
    notes: _fields['notes']!,
    other: _fields['other']!,
    tags: _fields['tags']!,
    password: _fields['password']!,
    group: _fields['group']!,
    caseSensitive: _fields['caseSensitive']!,
    excludeExpired: _fields['excludeExpired']!,
    regex: _fields['regex']!,
  );

  final _regexSearch = RegexSearch();
  List<_SearchHit>? _regexResults;
  bool _regexPending = false;
  bool _regexError = false;
  int _generation = 0;

  void _invalidateRegex() {
    _generation++;
    _regexSearch.cancel();
    _regexResults = null;
    _regexPending = false;
    _regexError = false;
  }

  Future<void> _runRegex() async {
    _invalidateRegex();
    final session = ref.read(databaseSessionProvider);
    if (session == null || _query.text.trim().isEmpty) return;
    final generation = _generation;
    setState(() => _regexPending = true);
    try {
      final results = <_SearchHit>[];
      final sessions = ref.read(databaseSessionProvider.notifier).openSessions;
      for (final current in sessions) {
        final found = await _regexSearch.run(
          current.database,
          _query.text.trim(),
          _options,
        );
        if (!mounted || generation != _generation) return;
        results.addAll(found.map((result) => _SearchHit(result, current)));
      }
      if (mounted && generation == _generation) {
        setState(() => _regexResults = results);
      }
    } on FormatException {
      if (mounted && generation == _generation) {
        setState(() => _regexError = true);
      }
    } on TimeoutException {
      if (mounted && generation == _generation) {
        setState(() => _regexError = true);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _regexPending = false);
      }
    }
  }

  Future<void> _showOptions(AppLocalizations l10n) async {
    final labels = <String, String>{
      'title': l10n.searchFieldTitle,
      'userName': l10n.searchFieldUserName,
      'url': l10n.searchFieldUrl,
      'password': l10n.searchFieldPassword,
      'notes': l10n.searchFieldNotes,
      'other': l10n.searchFieldOther,
      'tags': l10n.searchFieldTags,
      'group': l10n.searchFieldGroup,
      'regex': l10n.searchRegex,
      'caseSensitive': l10n.searchCaseSensitive,
      'excludeExpired': l10n.searchExcludeExpired,
    };
    await showListSheet<void>(
      context: context,
      title: l10n.searchOptions,
      buildItems: (_) => [
        StatefulBuilder(
          builder: (context, update) => Column(
            children: [
              for (final item in labels.entries)
                CheckboxListTile(
                  title: Text(item.value),
                  value: _fields[item.key],
                  onChanged: (value) =>
                      update(() => _fields[item.key] = value ?? false),
                ),
            ],
          ),
        ),
      ],
    );
    if (mounted) setState(_invalidateRegex);
  }

  @override
  void dispose() {
    _invalidateRegex();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final query = _query.text.trim();
    final session = ref.watch(databaseSessionProvider);
    ref.listen(databaseSessionProvider, (previous, next) {
      if (_sessionKey(previous) != _sessionKey(next)) {
        setState(_selected.clear);
      }
      if (next == null ||
          (previous?.file == next.file &&
              previous?.database != next.database)) {
        setState(_invalidateRegex);
      }
    });
    if (session == null) {
      _selected.clear();
      _invalidateRegex();
      return const Scaffold();
    }
    final regex = _options.regex;
    final results = regex
        ? _regexResults
        : [
            for (final current
                in ref.read(databaseSessionProvider.notifier).openSessions)
              for (final result in searchEntries(
                current.database,
                query,
                options: _options,
              ))
                _SearchHit(result, current),
          ];
    final rootId = itemIdOf(session.database.root);
    final selectableIds = {
      for (final result in results ?? <_SearchHit>[])
        if (result.session.file == session.file) itemIdOf(result.entry),
    };
    _selected.retainAll(selectableIds);
    final hasUnselectedResults = selectableIds.any(
      (id) => !_selected.contains(id),
    );
    final selectedEntries = [
      for (final hit in results ?? <_SearchHit>[])
        if (hit.session.file == session.file &&
            _selected.contains(itemIdOf(hit.entry)))
          hit.entry,
    ];
    final selectedEntry = selectedEntries.length == 1
        ? selectedEntries.single
        : null;
    final selectedEntryId = selectedEntry == null
        ? null
        : itemIdOf(selectedEntry);
    final canFavorite =
        selectedEntries.isNotEmpty &&
        selectedEntries.every(
          (entry) => !isInRecycleBin(session.database, entry),
        );
    final allFavorite = canFavorite && selectedEntries.every(isEntryFavorite);
    final multipleDatabases =
        ref.read(databaseSessionProvider.notifier).openSessions.length > 1;
    var busy = ref.read(databaseSessionProvider.notifier).isSaving;
    for (final actionId in {rootId, ?selectedEntryId}) {
      final actions = itemActionsProvider(actionId);
      busy = ref.watch(actions).isLoading || busy;
      ref.listen(actions, (_, next) {
        if (next case AsyncError(:final error)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(describeSaveError(l10n, error))),
          );
        }
      });
    }

    return PopScope(
      canPop: _selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selected.isNotEmpty && !busy) setState(_selected.clear);
      },
      child: SelectionAppBarBuilder(
        showSelectAll: _selected.isNotEmpty && hasUnselectedResults,
        onSelectAll: busy
            ? null
            : () => setState(() => _selected.addAll(selectableIds)),
        builder: (context, bottom) => Scaffold(
          appBar: AppBar(
            leading: _selected.isEmpty
                ? null
                : IconButton(
                    tooltip: l10n.cancel,
                    icon: const Icon(Icons.close),
                    onPressed: busy ? null : () => setState(_selected.clear),
                  ),
            title: _selected.isNotEmpty
                ? Text(
                    l10n.itemsSelected(_selected.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : TextField(
                    controller: _query,
                    autofocus: true,
                    // La tastiera non deve imparare le ricerche (decisione D8).
                    enableIMEPersonalizedLearning: false,
                    textInputAction: TextInputAction.search,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(AppLimits.searchQuery),
                    ],
                    onChanged: (_) => setState(_invalidateRegex),
                    onSubmitted: (_) {
                      if (_options.regex) _runRegex();
                    },
                    decoration: InputDecoration(hintText: l10n.searchHint),
                  ),
            bottom: bottom,
            actions: _selected.isNotEmpty
                ? [
                    if (canFavorite)
                      IconButton(
                        tooltip: allFavorite
                            ? l10n.entryFavoriteRemove
                            : l10n.entryFavoriteAdd,
                        isSelected: allFavorite,
                        color: allFavorite
                            ? Theme.of(context).colorScheme.primary
                            : null,
                        icon: const Icon(Icons.star_border),
                        selectedIcon: const Icon(Icons.star),
                        onPressed: busy
                            ? null
                            : () => ref
                                  .read(itemActionsProvider(rootId).notifier)
                                  .setFavorites(
                                    _selected.toList(),
                                    !allFavorite,
                                  ),
                      ),
                    ActionPopupMenu<_SearchSelectionAction>(
                      enabled: !busy,
                      items: [
                        if (selectedEntryId != null)
                          ActionPopupItem(
                            value: _SearchSelectionAction.edit,
                            icon: Icons.edit_outlined,
                            label: l10n.entryEdit,
                          ),
                        ActionPopupItem(
                          value: _SearchSelectionAction.move,
                          icon: Icons.drive_file_move_outline,
                          label: l10n.itemMoveTitle,
                        ),
                        if (selectedEntryId != null)
                          ActionPopupItem(
                            value: _SearchSelectionAction.duplicate,
                            icon: Icons.content_copy_outlined,
                            label: l10n.itemDuplicate,
                          ),
                        ActionPopupItem(
                          value: _SearchSelectionAction.delete,
                          icon: Icons.delete_outline,
                          label: l10n.entryDelete,
                        ),
                        if (selectedEntryId != null)
                          ActionPopupItem(
                            value: _SearchSelectionAction.group,
                            icon: Icons.folder_open,
                            label: l10n.searchGoToGroup,
                          ),
                        if (multipleDatabases) ...[
                          ActionPopupItem(
                            value: _SearchSelectionAction.copyDatabase,
                            icon: Icons.file_copy_outlined,
                            label: l10n.databasesCopy,
                          ),
                          ActionPopupItem(
                            value: _SearchSelectionAction.moveDatabase,
                            icon: Icons.drive_file_move_outline,
                            label: l10n.databasesMove,
                          ),
                        ],
                      ],
                      onSelected: (action) {
                        if (busy) return;
                        switch (action) {
                          case _SearchSelectionAction.edit:
                            if (selectedEntryId != null) {
                              setState(_selected.clear);
                              context.push(
                                AppRoutes.entryEdit(selectedEntryId),
                              );
                            }
                          case _SearchSelectionAction.move:
                            _moveSelection(rootId);
                          case _SearchSelectionAction.duplicate:
                            if (selectedEntryId != null) {
                              _duplicateSelection(selectedEntryId);
                            }
                          case _SearchSelectionAction.delete:
                            _deleteSelection(
                              rootId,
                              !session.database.meta.recycleBinEnabled,
                            );
                          case _SearchSelectionAction.group:
                            if (selectedEntry?.parent case final group?) {
                              context.go(AppRoutes.group(itemIdOf(group)));
                            }
                          case _SearchSelectionAction.copyDatabase:
                            _transferSelection(move: false);
                          case _SearchSelectionAction.moveDatabase:
                            _transferSelection(move: true);
                        }
                      },
                    ),
                  ]
                : [
                    if (regex)
                      IconButton(
                        tooltip: l10n.searchTitle,
                        icon: const Icon(Icons.search),
                        onPressed: _runRegex,
                      ),
                    IconButton(
                      tooltip: l10n.searchOptions,
                      icon: const Icon(Icons.tune),
                      onPressed: () => _showOptions(l10n),
                    ),
                    if (query.isNotEmpty)
                      IconButton(
                        tooltip: l10n.searchClear,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _query.clear();
                          _invalidateRegex();
                        }),
                      ),
                  ],
          ),
          body: query.isEmpty
              ? const SizedBox.shrink()
              : _regexPending
              ? const Center(child: CircularProgressIndicator())
              : _regexError
              ? Center(child: Text(l10n.searchRegexError))
              : results == null
              ? Center(child: Text(l10n.searchRegexSubmit))
              : results.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.l),
                    child: Text(l10n.searchNoResults),
                  ),
                )
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final hit = results[index];
                    final active = hit.session.file == session.file;
                    final id = itemIdOf(hit.entry);
                    final group =
                        ref.watch(appSettingsProvider).showGroupNameInSearch
                        ? hit.groupPath
                        : null;
                    final label =
                        ref
                                .read(databaseSessionProvider.notifier)
                                .openSessions
                                .length >
                            1
                        ? [hit.session.file.name, ?group].join(' · ')
                        : group;
                    return EntryTile(
                      entry: hit.entry,
                      databaseOverride: hit.session.database,
                      selected: active && _selected.contains(id),
                      showChevron: _selected.isEmpty,
                      onLongPress: () {
                        if (busy) return;
                        if (!active && _selected.isNotEmpty) return;
                        if (!active) {
                          ref
                              .read(databaseSessionProvider.notifier)
                              .switchTo(hit.session.file);
                        }
                        _toggleSelection(id);
                      },
                      onTap: () {
                        if (busy) return;
                        if (_selected.isNotEmpty) {
                          if (active) _toggleSelection(id);
                          return;
                        }
                        if (!active) {
                          ref
                              .read(databaseSessionProvider.notifier)
                              .switchTo(hit.session.file);
                        }
                        context.push(AppRoutes.entry(id));
                      },
                      groupName: label,
                    );
                  },
                ),
        ),
      ),
    );
  }
}
