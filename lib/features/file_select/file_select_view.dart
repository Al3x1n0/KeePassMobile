import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/storage/file_storage.dart';
import '../../shared/database/database_session.dart';
import '../../shared/storage/remote_storage.dart';
import '../unlock/relock.dart';
import '../unlock/unlock_view_model.dart';
import 'recent_files.dart';

/// Scelta del database: file recenti e apertura di un nuovo file
/// (FileSelectActivity di Keepass2Android). Dopo un blocco apre subito lo
/// sblocco dello stesso database ([relockProvider]).
class FileSelectView extends ConsumerStatefulWidget {
  const FileSelectView({super.key, this.additional = false});
  final bool additional;

  @override
  ConsumerState<FileSelectView> createState() => _FileSelectViewState();
}

class _FileSelectViewState extends ConsumerState<FileSelectView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reopenAfterLock());
  }

  void _reopenAfterLock() {
    if (!mounted || widget.additional) return;
    final args = ref.read(relockProvider.notifier).take();
    if (args != null && !widget.additional) {
      context.push(AppRoutes.unlock, extra: args);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recents = ref.watch(recentFilesProvider);
    ref.listen(relockProvider, (_, next) {
      if (next != null) _reopenAfterLock();
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.fileSelectTitle),
        actions: [
          IconButton(
            tooltip: l10n.remoteOpenTitle,
            icon: const Icon(Icons.cloud_outlined),
            onPressed: () => context.push(
              widget.additional
                  ? AppRoutes.additionalRemote
                  : AppRoutes.remoteOpen,
            ),
          ),
          if (!widget.additional)
            IconButton(
              tooltip: l10n.createDatabaseTitle,
              icon: const Icon(Icons.note_add_outlined),
              onPressed: () => context.push(AppRoutes.createDatabase),
            ),
          if (!widget.additional)
            IconButton(
              tooltip: l10n.settingsTitle,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.push(AppRoutes.appSettings),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openFile,
        icon: const Icon(Icons.folder_open),
        label: Text(l10n.fileSelectOpenFile),
      ),
      body: recents.isEmpty
          ? Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.l),
                      child: Text(
                        l10n.fileSelectNoRecent,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (!widget.additional) _demoTile(l10n),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: recents.length + (widget.additional ? 1 : 2),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.m,
                      AppSpacing.m,
                      AppSpacing.m,
                      AppSpacing.s,
                    ),
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.fileSelectRecentFiles,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  );
                }
                if (index > recents.length) return _demoTile(l10n);
                final recent = recents[index - 1];
                final remote = RemoteStorage.handles(recent.database);
                return ListTile(
                  leading: Icon(
                    remote ? Icons.cloud_outlined : Icons.description_outlined,
                  ),
                  title: Text(recent.database.name),
                  subtitle: remote
                      ? Text(Uri.tryParse(recent.database.uri)?.host ?? '')
                      : null,
                  trailing: widget.additional
                      ? null
                      : IconButton(
                          tooltip: l10n.fileSelectRemove,
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            try {
                              await ref
                                  .read(recentFilesProvider.notifier)
                                  .forget(recent);
                            } on Exception {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l10n.errorGeneric)),
                                );
                              }
                            }
                          },
                        ),
                  onTap: () => context.push(
                    widget.additional
                        ? AppRoutes.additionalUnlock
                        : AppRoutes.unlock,
                    extra: UnlockArgs(
                      additional: widget.additional,
                      lockGeneration: ref
                          .read(databaseSessionProvider.notifier)
                          .lockGeneration,
                      database: PickedFile(ref: recent.database),
                      keyFile: switch (recent.keyFile) {
                        final key? => PickedFile(ref: key),
                        null => null,
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _demoTile(AppLocalizations l10n) => ListTile(
    leading: const Icon(Icons.explore_outlined),
    title: Text(l10n.fileSelectDemo),
    subtitle: Text(l10n.fileSelectDemoHint),
    onTap: _savingDemo ? null : _saveDemo,
  );

  bool _savingDemo = false;

  Future<void> _saveDemo() async {
    if (_savingDemo) return;
    setState(() => _savingDemo = true);
    final storage = ref.read(fileStorageProvider);
    try {
      const name = 'Rifugio-Aurora.kdbx';
      final data = await rootBundle.load('assets/demo/$name');
      if (!mounted) return;
      final file = await storage.create(
        suggestedName: name,
        bytes: Uint8List.sublistView(data),
      );
      if (file == null || !mounted) return;
      await context.push(
        AppRoutes.unlock,
        extra: UnlockArgs(database: PickedFile(ref: file)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).errorFileUnavailable),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingDemo = false);
    }
  }

  Future<void> _openFile() async {
    final l10n = AppLocalizations.of(context);
    try {
      final picked = await ref.read(filePickerServiceProvider).pick();
      if (picked == null || !mounted) return;
      if (!picked.persistent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.fileSelectNotPersistent)));
      }
      await context.push(
        widget.additional ? AppRoutes.additionalUnlock : AppRoutes.unlock,
        extra: UnlockArgs(
          database: picked,
          additional: widget.additional,
          lockGeneration: ref
              .read(databaseSessionProvider.notifier)
              .lockGeneration,
        ),
      );
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.errorFileUnavailable)));
    }
  }
}
