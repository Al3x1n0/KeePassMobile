import 'dart:convert';

import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/field_references.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/database/item_edits.dart';
import '../../shared/settings/app_settings.dart';
import '../../shared/ui/date_format.dart';
import '../../shared/ui/group_destination_dialog.dart';
import '../../shared/ui/database_item_icon.dart';
import '../../shared/ui/size_format.dart';
import '../../shared/ui/selection_sheet.dart';
import '../../shared/ui/url_opener.dart';
import '../totp/totp.dart';
import 'entry_view_model.dart';
import 'totp_tile.dart';

/// Dettaglio di una voce (EntryActivity di Keepass2Android): campi con
/// copia negli appunti, valori protetti nascosti, modifica ed eliminazione.
///
/// Con [historyIndex] mostra una versione della cronologia in sola lettura,
/// con "Ripristina" ed "Elimina versione" al posto di modifica ed
/// eliminazione.
class EntryView extends ConsumerStatefulWidget {
  const EntryView({super.key, required this.entryId, this.historyIndex});

  final String entryId;
  final int? historyIndex;

  @override
  ConsumerState<EntryView> createState() => _EntryViewState();
}

class _EntryViewState extends ConsumerState<EntryView> {
  /// Campi mostrati o nascosti dall'utente, al contrario dell'impostazione.
  final _toggled = <String>{};

  @override
  void initState() {
    super.initState();
    _scheduleTanExpiration();
  }

  void _scheduleTanExpiration() {
    final id = widget.entryId;
    final historyIndex = widget.historyIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.entryId != id ||
          widget.historyIndex != historyIndex ||
          historyIndex != null ||
          !ref.read(appSettingsProvider).expireTanOnOpen) {
        return;
      }
      ref.read(entryActionsProvider(id).notifier).expireTan();
    });
  }

  @override
  void didUpdateWidget(covariant EntryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entryId != widget.entryId ||
        oldWidget.historyIndex != widget.historyIndex) {
      _toggled.clear();
      _scheduleTanExpiration();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final historyIndex = widget.historyIndex;
    final entry = historyIndex == null
        ? ref.watch(entryProvider(widget.entryId))
        : ref.watch(historyEntryProvider((widget.entryId, historyIndex)));
    // Database chiuso, voce o versione eliminata: il router o la navigazione
    // sta già lasciando questa schermata.
    if (entry == null) return const Scaffold();
    final busy =
        ref.watch(entryActionsProvider(widget.entryId)).isLoading ||
        ref.watch(itemActionsProvider(widget.entryId)).isLoading;
    final database = ref.watch(databaseSessionProvider)?.database;
    final inBin = database != null && isInRecycleBin(database, entry);
    ref.listen(itemActionsProvider(widget.entryId), (_, next) {
      if (next case AsyncError(:final error)) {
        _showMessage(describeSaveError(l10n, error));
      }
    });
    final title = visibleEntryTitle(database, entry);
    final fields = visibleFields(entry, database: database);
    final totp = historyIndex == null
        ? ref.watch(entryTotpProvider(widget.entryId))
        : entryTotpOf(entry);
    final settings = ref.watch(appSettingsProvider);
    final expired = isExpired(entry, DateTime.now());
    final expiry = entry.times.expiry.time;
    final tags = entry.tags ?? const <String>[];
    // Il TOTP va dopo i campi standard, prima di quelli personalizzati.
    final totpIndex = fields.indexWhere((f) => !f.isStandard);
    final totpAt = totpIndex < 0 ? fields.length : totpIndex;

    ref.listen(entryActionsProvider(widget.entryId), (_, next) {
      if (next case AsyncError(:final error)) {
        _showMessage(describeSaveError(l10n, error));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            DatabaseItemIcon(item: entry, database: database, expired: expired),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Text(
                title.isEmpty ? l10n.entryUntitled : title,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: historyIndex == null
            ? [
                IconButton(
                  tooltip: l10n.entryEdit,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: busy || inBin
                      ? null
                      : () => context.push(AppRoutes.entryEdit(widget.entryId)),
                ),
                IconButton(
                  tooltip: l10n.entryDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: busy ? null : _delete,
                ),
                IconButton(
                  tooltip: l10n.groupMore,
                  icon: const Icon(Icons.more_vert),
                  onPressed: busy
                      ? null
                      : () async {
                          final action = await showSelectionSheet<String>(
                            context: context,
                            title: l10n.groupMore,
                            options: {
                              if (!inBin) ...{
                                'move': l10n.itemMoveTitle,
                                'duplicate': l10n.itemDuplicate,
                              },
                              if (inBin) 'restore': l10n.itemRestore,
                            },
                          );
                          if (!mounted || action == null) return;
                          switch (action) {
                            case 'move':
                              _move();
                            case 'duplicate':
                              _duplicate();
                            case 'restore':
                              _restoreFromBin();
                          }
                        },
                ),
              ]
            : [
                IconButton(
                  tooltip: l10n.entryHistoryRestore,
                  icon: const Icon(Icons.restore),
                  onPressed: busy ? null : () => _restore(historyIndex),
                ),
                IconButton(
                  tooltip: l10n.entryHistoryDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: busy ? null : () => _deleteVersion(historyIndex),
                ),
              ],
      ),
      body: ListView(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (historyIndex != null)
            MaterialBanner(
              content: Text(
                l10n.entryHistoryReadOnly(_versionLabel(l10n, entry)),
              ),
              leading: const Icon(Icons.history),
              actions: const [SizedBox.shrink()],
            ),
          if (settings.showGroupInEntry)
            if (entry.parent case final group?)
              ListTile(
                title: Text(l10n.entryGroup),
                subtitle: Text(groupFullPath(group)),
              ),
          for (final (index, field) in fields.indexed) ...[
            if (index == totpAt && totp != null) _totpTile(l10n, totp),
            _FieldTile(
              label: _label(l10n, field.key),
              value: field.issue == null
                  ? field.value
                  : l10n.errorFieldReference,
              masked:
                  field.issue == null &&
                  field.protected &&
                  _hiddenByDefault(settings, field.key) !=
                      _toggled.contains(field.key),
              multiline: field.key == EntryFields.notes,
              onToggle: field.issue == null && field.protected
                  ? () => setState(() {
                      if (!_toggled.remove(field.key)) {
                        _toggled.add(field.key);
                      }
                    })
                  : null,
              onCopy: field.issue == null ? () => _copy(field.value) : null,
              onOpen:
                  field.key == EntryFields.url &&
                      field.issue == null &&
                      !field.protected
                  ? () => _openUrl(field)
                  : null,
            ),
          ],
          if (totpAt == fields.length && totp != null) _totpTile(l10n, totp),
          if (entry.times.creation.time case final created?)
            ListTile(
              title: Text(l10n.entryCreated),
              subtitle: Text(formatDateTime(context, created)),
            ),
          if (entry.times.modification.time case final modified?)
            ListTile(
              title: Text(l10n.entryModified),
              subtitle: Text(formatDateTime(context, modified)),
            ),
          if (entry.times.expires && expiry != null)
            ListTile(
              leading: Icon(
                expired ? Icons.event_busy : Icons.event_outlined,
                color: expired ? Theme.of(context).colorScheme.error : null,
              ),
              title: Text(
                expired
                    ? l10n.entryExpiredOn(formatDateTime(context, expiry))
                    : l10n.entryExpiresOn(formatDateTime(context, expiry)),
              ),
            ),
          if (tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Semantics(
                label: l10n.entryTags,
                child: Wrap(
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  children: [for (final tag in tags) Chip(label: Text(tag))],
                ),
              ),
            ),
          if (entry.overrideUrl case final value? when value.isNotEmpty)
            ListTile(title: Text(l10n.entryOverrideUrl), subtitle: Text(value)),
          ..._attachmentTiles(l10n, entry),
          if (historyIndex == null && entry.history.isNotEmpty)
            ..._historyTiles(l10n, entry),
        ],
      ),
    );
  }

  Future<void> _move() async {
    final target = await showDialog<String>(
      context: context,
      builder: (_) => GroupDestinationDialog(itemId: widget.entryId),
    );
    if (target == null || !mounted) return;
    if (await ref
            .read(itemActionsProvider(widget.entryId).notifier)
            .move(target) &&
        mounted) {
      context.go(AppRoutes.group(target));
    }
  }

  Future<void> _duplicate() async {
    final suffix = AppLocalizations.of(context).itemDuplicateSuffix;
    final id = await ref
        .read(itemActionsProvider(widget.entryId).notifier)
        .duplicate(suffix);
    if (id != null && mounted) context.go(AppRoutes.entry(id));
  }

  Future<void> _restoreFromBin() async {
    if (await ref
            .read(itemActionsProvider(widget.entryId).notifier)
            .restore() &&
        mounted) {
      final parent = ref.read(entryProvider(widget.entryId))?.parent;
      context.go(
        parent == null ? AppRoutes.database : AppRoutes.group(itemIdOf(parent)),
      );
    }
  }

  Widget _totpTile(AppLocalizations l10n, EntryTotp totp) {
    final config = totp.config;
    if (config == null) {
      return ListTile(
        title: Text(l10n.entryTotp),
        subtitle: Text(
          l10n.entryTotpInvalid,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: Theme.of(context).colorScheme.error),
        ),
      );
    }
    return TotpTile(
      config: config,
      masked: ref.watch(appSettingsProvider.select((s) => s.maskTotp)),
      onCopy: _copyCode,
    );
  }

  Future<void> _copyCode(String code) async {
    final l10n = AppLocalizations.of(context);
    final clearAfter = await ref
        .read(entryActionsProvider(widget.entryId).notifier)
        .copyText(code);
    if (mounted) _showMessage(l10n.entryCopied(clearAfter.inSeconds));
  }

  /// Come Keepass2Android: masktotp per i campi TOTP, maskpass per la
  /// password e gli altri campi protetti.
  static bool _hiddenByDefault(AppSettings settings, String key) =>
      isTotpField(key) ? settings.maskTotp : settings.maskPassword;

  static String _label(AppLocalizations l10n, String key) => switch (key) {
    EntryFields.userName => l10n.entryUserName,
    EntryFields.password => l10n.entryPassword,
    EntryFields.url => l10n.entryUrl,
    EntryFields.notes => l10n.entryNotes,
    _ => key,
  };

  Future<void> _copy(String value) async {
    if (value.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final clearAfter = await ref
        .read(entryActionsProvider(widget.entryId).notifier)
        .copyText(value);
    if (mounted) _showMessage(l10n.entryCopied(clearAfter.inSeconds));
  }

  /// Data della versione; nei file senza tempi (generati da altri programmi)
  /// può mancare.
  static DateTime? _modified(KdbxEntry entry) => entry.times.modification.time;

  String _versionLabel(AppLocalizations l10n, KdbxEntry entry) =>
      switch (_modified(entry)) {
        final date? => l10n.entryHistoryVersion(formatDateTime(context, date)),
        null => l10n.entryHistoryUndated,
      };

  /// Versioni precedenti, dalla più recente (EntryActivity di Keepass2Android).
  List<Widget> _historyTiles(AppLocalizations l10n, KdbxEntry entry) {
    final indexes = [for (var i = 0; i < entry.history.length; i++) i]
      // Dalla più recente; le versioni senza data in fondo.
      ..sort((a, b) {
        final da = _modified(entry.history[a]);
        final db = _modified(entry.history[b]);
        if (da == null || db == null) return da == null ? 1 : -1;
        return db.compareTo(da);
      });
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.m,
          AppSpacing.l,
          AppSpacing.m,
          AppSpacing.s,
        ),
        child: Semantics(
          header: true,
          child: Text(
            l10n.entryHistory,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ),
      for (final i in indexes)
        ListTile(
          leading: const Icon(Icons.history),
          title: Text(_versionLabel(l10n, entry.history[i])),
          subtitle: Text(entryTitle(entry.history[i])),
          onTap: () => context.push(AppRoutes.entryHistory(widget.entryId, i)),
        ),
    ];
  }

  /// Apre il campo URL nel browser (GotoUrl di Keepass2Android, D14).
  Future<void> _openUrl(EntryFieldView field) async {
    if (field.protected || ref.read(databaseSessionProvider) == null) return;
    final l10n = AppLocalizations.of(context);
    final uri = entryUrl(field.value);
    if (uri == null) {
      _showMessage(l10n.entryUrlNotSupported);
      return;
    }
    final opened = await ref.read(urlOpenerProvider).open(uri);
    if (!opened && mounted) _showMessage(l10n.entryUrlNoApp);
  }

  /// Allegati: anteprima nell'app e salvataggio su file (EntryActivity).
  List<Widget> _attachmentTiles(AppLocalizations l10n, KdbxEntry entry) {
    final database = ref.watch(databaseSessionProvider)?.database;
    if (database == null || entry.binaries.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.m,
          AppSpacing.l,
          AppSpacing.m,
          AppSpacing.s,
        ),
        child: Semantics(
          header: true,
          child: Text(
            l10n.entryAttachments,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      ),
      for (final attachment in entryAttachments(database, entry))
        ListTile(
          leading: const Icon(Icons.attach_file),
          title: Text(attachment.name),
          subtitle: Text(formatBytes(context, attachment.size)),
          onTap: () => _preview(
            attachment.name,
            attachmentData(database, entry, attachment.name),
          ),
          trailing: IconButton(
            tooltip: l10n.entryAttachmentSave(attachment.name),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _saveAttachment(attachment.name),
          ),
        ),
    ];
  }

  static const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
  static const _textExtensions = {
    'txt',
    'md',
    'csv',
    'json',
    'xml',
    'log',
    'ini',
    'conf',
    'pem',
    'key',
    'asc',
  };

  /// Anteprima solo in memoria: nessun file temporaneo (SEC-02).
  Future<void> _preview(String name, Uint8List? data) async {
    final l10n = AppLocalizations.of(context);
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    final Widget content;
    if (data == null) {
      content = Text(l10n.entryAttachmentNoPreview);
    } else if (_imageExtensions.contains(ext)) {
      content = Image(
        image: _AttachmentPreviewImage(data),
        errorBuilder: (_, _, _) => Text(l10n.entryAttachmentNoPreview),
      );
    } else if (_textExtensions.contains(ext)) {
      // Solo l'inizio dei file di testo grandi.
      final text = utf8.decode(
        data.length > 65536 ? Uint8List.sublistView(data, 0, 65536) : data,
        allowMalformed: true,
      );
      content = Text(text);
    } else {
      content = Text(l10n.entryAttachmentNoPreview);
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: SingleChildScrollView(child: content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  /// Salvataggio su file con avviso: il file non è cifrato (D11, ADR-007).
  Future<void> _saveAttachment(String name) async {
    final l10n = AppLocalizations.of(context);
    if (!await _confirm(
      l10n.entryAttachmentSaveWarning(name),
      l10n.entryAttachmentSaveConfirm,
    )) {
      return;
    }
    final result = await ref
        .read(entryActionsProvider(widget.entryId).notifier)
        .saveAttachment(name, historyIndex: widget.historyIndex);
    if (!mounted) return;
    switch (result) {
      case AttachmentSaveResult.saved:
        _showMessage(l10n.entryAttachmentSaved(name));
      case AttachmentSaveResult.failed:
        _showMessage(l10n.entryAttachmentSaveFailed);
      case AttachmentSaveResult.cancelled:
        break;
    }
  }

  Future<bool> _confirm(String message, String action) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _restore(int index) async {
    final l10n = AppLocalizations.of(context);
    if (!await _confirm(
      l10n.entryHistoryRestoreConfirm,
      l10n.entryHistoryRestore,
    )) {
      return;
    }
    final restored = await ref
        .read(entryActionsProvider(widget.entryId).notifier)
        .restoreHistory(index);
    if (restored && mounted) context.pop();
  }

  Future<void> _deleteVersion(int index) async {
    final l10n = AppLocalizations.of(context);
    if (!await _confirm(
      l10n.entryHistoryDeleteConfirm,
      l10n.entryHistoryDelete,
    )) {
      return;
    }
    final deleted = await ref
        .read(entryActionsProvider(widget.entryId).notifier)
        .deleteHistory(index);
    if (deleted && mounted) context.pop();
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final permanent = ref.read(entryDeletesPermanentlyProvider(widget.entryId));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(
          permanent
              ? l10n.entryDeleteConfirmPermanent
              : l10n.entryDeleteConfirmRecycle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.entryDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final deleted = await ref
        .read(entryActionsProvider(widget.entryId).notifier)
        .delete();
    if (deleted && mounted) context.pop();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Le anteprime decifrate appartengono solo al flusso immagine del dialogo.
class _AttachmentPreviewImage extends MemoryImage {
  const _AttachmentPreviewImage(super.bytes);

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    MemoryImage key,
    ImageErrorListener handleError,
  ) {
    if (stream.completer != null) return;
    stream.setCompleter(
      loadImage(key, PaintingBinding.instance.instantiateImageCodecWithSize),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.value,
    required this.masked,
    required this.multiline,
    required this.onCopy,
    this.onToggle,
    this.onOpen,
  });

  static const _mask = '••••••••';

  final String label;
  final String value;
  final bool masked;
  final bool multiline;
  final VoidCallback? onCopy;
  final VoidCallback? onToggle;

  /// Apertura nel browser (solo il campo URL).
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final toggle = onToggle;
    final open = onOpen;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: Semantics(
        // Il valore nascosto non va letto dallo screen reader.
        excludeSemantics: masked,
        label: masked ? l10n.entryHiddenValue : null,
        child: Text(
          masked ? _mask : value,
          style: Theme.of(context).textTheme.bodyLarge,
          maxLines: multiline ? null : 3,
          overflow: multiline ? null : TextOverflow.ellipsis,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (toggle != null)
            IconButton(
              tooltip: masked ? l10n.entryShow : l10n.entryHide,
              icon: Icon(masked ? Icons.visibility : Icons.visibility_off),
              onPressed: toggle,
            ),
          if (open != null)
            IconButton(
              tooltip: l10n.entryUrlOpen,
              icon: const Icon(Icons.open_in_new),
              onPressed: open,
            ),
          IconButton(
            tooltip: l10n.entryCopy(label),
            icon: const Icon(Icons.copy),
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
