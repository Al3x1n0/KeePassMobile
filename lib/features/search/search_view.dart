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
import '../../shared/ui/entry_tile.dart';
import '../../shared/ui/cross_database_copy_sheet.dart';
import '../../shared/ui/group_destination_sheet.dart';
import '../../shared/ui/selection_sheet.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/item_edits.dart';
import '../../shared/database/kdbx_items.dart';
import 'search_view_model.dart';

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

  Future<void> _deleteSelection(String rootId, bool permanent) async {
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
        .read(itemActionsProvider(rootId).notifier)
        .deleteSearchEntries(_selected.toList());
    if (success && mounted) {
      setState(() {
        _selected.clear();
        _invalidateRegex();
      });
    }
  }

  Future<void> _moveSelection(String rootId) async {
    final selected = _selected.toList();
    final destination = await showGroupDestinationSheet(context, selected);
    if (destination == null || !mounted) return;
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
    if (session == null) {
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
    final busy = ref.watch(itemActionsProvider(rootId)).isLoading;
    ref.listen(itemActionsProvider(rootId), (_, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeSaveError(l10n, error))));
      }
    });

    return PopScope(
      canPop: _selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selected.isNotEmpty && !busy) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _selected.isEmpty
              ? null
              : IconButton(
                  tooltip: l10n.cancel,
                  icon: const Icon(Icons.close),
                  onPressed: busy ? null : () => setState(_selected.clear),
                ),
          title: _selected.isNotEmpty
              ? Text(l10n.itemsSelected(_selected.length))
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
          actions: _selected.isNotEmpty
              ? [
                  if (_selected.length == 1)
                    IconButton(
                      tooltip: l10n.searchGoToGroup,
                      icon: const Icon(Icons.folder_open),
                      onPressed: busy
                          ? null
                          : () {
                              final matches = (results ?? []).where(
                                (r) =>
                                    r.session.file == session.file &&
                                    itemIdOf(r.entry) == _selected.single,
                              );
                              final group = matches.firstOrNull?.entry.parent;
                              if (group != null) {
                                context.go(AppRoutes.group(itemIdOf(group)));
                              }
                            },
                    ),
                  if (ref
                          .read(databaseSessionProvider.notifier)
                          .openSessions
                          .length >
                      1)
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
                                setState(() {
                                  _selected.clear();
                                  _invalidateRegex();
                                });
                              }
                            },
                    ),
                  if (ref
                          .read(databaseSessionProvider.notifier)
                          .openSessions
                          .length >
                      1)
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
                                setState(() {
                                  _selected.clear();
                                  _invalidateRegex();
                                });
                              }
                            },
                    ),
                  IconButton(
                    tooltip: l10n.itemMoveTitle,
                    icon: const Icon(Icons.drive_file_move_outline),
                    onPressed: busy ? null : () => _moveSelection(rootId),
                  ),
                  IconButton(
                    tooltip: l10n.itemsSelectAll,
                    icon: const Icon(Icons.select_all),
                    onPressed: busy
                        ? null
                        : () => setState(
                            () => _selected.addAll(
                              (results ?? [])
                                  .where((r) => r.session.file == session.file)
                                  .map((r) => itemIdOf(r.entry)),
                            ),
                          ),
                  ),
                  IconButton(
                    tooltip: l10n.entryDelete,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: busy
                        ? null
                        : () => _deleteSelection(
                            rootId,
                            !session.database.meta.recycleBinEnabled,
                          ),
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
                      if (!active && _selected.isNotEmpty) return;
                      if (!active) {
                        ref
                            .read(databaseSessionProvider.notifier)
                            .switchTo(hit.session.file);
                      }
                      _toggleSelection(id);
                    },
                    onTap: () {
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
    );
  }
}
