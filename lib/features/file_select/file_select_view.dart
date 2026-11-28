import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/storage/file_storage.dart';
import '../../shared/database/database_session.dart';
import '../../shared/storage/remote_storage.dart';
import '../../shared/ui/app_snack_bar.dart';
import '../../shared/ui/demo_database_dialog.dart';
import '../unlock/relock.dart';
import '../unlock/unlock_view_model.dart';
import 'demo_database.dart';
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final fabTheme = theme.floatingActionButtonTheme;
        final media = MediaQuery.of(context);
        final labelStyle =
            fabTheme.extendedTextStyle ?? theme.textTheme.labelLarge!;
        final textStyle = media.boldText
            ? labelStyle.copyWith(fontWeight: FontWeight.bold)
            : labelStyle;
        final iconSize = fabTheme.iconSize ?? AppFileSelectLayout.fabIconSize;
        final labels = [
          if (!widget.additional) l10n.fileSelectNewDatabase,
          l10n.fileSelectOpenFile,
          l10n.remoteOpenTitle,
        ];
        final labelChrome =
            AppFileSelectLayout.fabPadding.horizontal + iconSize + AppSpacing.s;
        final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: media.textScaler,
          locale: Localizations.localeOf(context),
        );
        var labelWidth = 0.0;
        for (final label in labels) {
          painter.text = TextSpan(text: label, style: textStyle);
          painter.layout();
          labelWidth = math.max(labelWidth, painter.width);
        }
        labelWidth = math.min(
          labelWidth.ceilToDouble(),
          math.max(
            0,
            constraints.maxWidth -
                media.padding.horizontal -
                AppSpacing.m * 2 -
                labelChrome,
          ),
        );
        final buttonHeights = <String, double>{};
        for (final label in labels) {
          painter.text = TextSpan(text: label, style: textStyle);
          painter.layout(maxWidth: labelWidth);
          buttonHeights[label] = math.max(
            AppFileSelectLayout.fabMinHeight,
            painter.height.ceilToDouble() + AppSpacing.s * 2,
          );
        }
        painter.dispose();
        final stackHeight =
            buttonHeights.values.fold(0.0, (sum, height) => sum + height) +
            (labels.length - 1) * AppSpacing.s;
        // Se la pila non entra, scorre senza coprire AppBar e contenuti.
        final visibleStackHeight = math.min(
          stackHeight,
          math.max(
            AppFileSelectLayout.fabMinHeight,
            constraints.maxHeight -
                media.padding.vertical -
                media.viewInsets.bottom -
                kToolbarHeight -
                AppSpacing.m * 2 -
                AppFileSelectLayout.contentMinHeight,
          ),
        );
        final bottomClearance =
            visibleStackHeight + AppSpacing.m * 2 + media.padding.bottom;

        Widget action(
          String label,
          IconData icon,
          String tag,
          VoidCallback onPressed,
        ) => SizedBox(
          height: buttonHeights[label],
          child: FloatingActionButton.extended(
            heroTag: '$tag-${widget.additional}',
            onPressed: onPressed,
            icon: Icon(icon),
            extendedTextStyle: textStyle,
            extendedIconLabelSpacing: AppSpacing.s,
            extendedPadding: AppFileSelectLayout.fabPadding,
            label: SizedBox(width: labelWidth, child: Text(label)),
          ),
        );

        final buttons = SizedBox(
          width: labelWidth + labelChrome,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!widget.additional) ...[
                action(
                  l10n.fileSelectNewDatabase,
                  Icons.note_add_outlined,
                  'file-select-new',
                  () => context.push(AppRoutes.createDatabase),
                ),
                const SizedBox(height: AppSpacing.s),
              ],
              action(
                l10n.fileSelectOpenFile,
                Icons.folder_open,
                'file-select-file',
                _openFile,
              ),
              const SizedBox(height: AppSpacing.s),
              action(
                l10n.remoteOpenTitle,
                Icons.cloud_outlined,
                'file-select-server',
                () => context.push(
                  widget.additional
                      ? AppRoutes.additionalRemote
                      : AppRoutes.remoteOpen,
                ),
              ),
            ],
          ),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.fileSelectTitle),
            actions: [
              if (!widget.additional)
                IconButton(
                  tooltip: l10n.settingsTitle,
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push(AppRoutes.appSettings),
                ),
            ],
          ),
          floatingActionButton: Theme(
            data: theme.copyWith(
              floatingActionButtonTheme: fabTheme.copyWith(
                extendedSizeConstraints: const BoxConstraints(
                  minHeight: AppFileSelectLayout.fabMinHeight,
                ),
              ),
            ),
            child: stackHeight > visibleStackHeight
                ? SizedBox(
                    height: visibleStackHeight,
                    child: SingleChildScrollView(
                      primary: false,
                      child: buttons,
                    ),
                  )
                : buttons,
          ),
          body: SafeArea(
            bottom: false,
            child: recents.isEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: EdgeInsets.only(bottom: bottomClearance),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: math.max(
                            0,
                            constraints.maxHeight - bottomClearance,
                          ),
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.l),
                            child: Text(
                              l10n.fileSelectNoRecent,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(bottom: bottomClearance),
                    itemCount: recents.length + 1,
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
                      final recent = recents[index - 1];
                      final remote = RemoteStorage.handles(recent.database);
                      final demo = ref
                          .read(demoDatabaseRepositoryProvider)
                          .isDemo(recent.database);
                      return ListTile(
                        leading: Icon(
                          remote
                              ? Icons.cloud_outlined
                              : Icons.description_outlined,
                        ),
                        title: Text(recent.database.name),
                        subtitle: demo
                            ? Text(l10n.demoDatabaseSubtitle)
                            : remote
                            ? Text(
                                Uri.tryParse(recent.database.uri)?.host ?? '',
                              )
                            : null,
                        trailing: widget.additional
                            ? null
                            : IconButton(
                                tooltip: l10n.fileSelectRemove,
                                icon: const Icon(Icons.close),
                                onPressed: () async {
                                  if (demo) {
                                    final confirmed =
                                        await showDemoDatabaseRemovalDialog(
                                          context,
                                        );
                                    if (!confirmed || !context.mounted) return;
                                  }
                                  try {
                                    await ref
                                        .read(recentFilesProvider.notifier)
                                        .forget(recent);
                                  } on Exception {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showAppSnackBar(
                                            SnackBar(
                                              content: Text(l10n.errorGeneric),
                                            ),
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
          ),
        );
      },
    );
  }

  Future<void> _openFile() async {
    final l10n = AppLocalizations.of(context);
    try {
      final picked = await ref.read(filePickerServiceProvider).pick();
      if (picked == null || !mounted) return;
      if (!picked.persistent) {
        ScaffoldMessenger.of(context).showAppSnackBar(
          SnackBar(content: Text(l10n.fileSelectNotPersistent)),
        );
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
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showAppSnackBar(
        SnackBar(content: Text(describeFilePickError(l10n, error))),
      );
    }
  }
}
