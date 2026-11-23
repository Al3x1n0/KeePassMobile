import 'package:qr_scanner_offline_private/qr_scanner_offline_private.dart';

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/entry_templates.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/database/item_edits.dart';
import '../../shared/storage/file_storage.dart';
import '../../shared/ui/date_format.dart';
import '../../shared/ui/entry_icon.dart';
import '../../shared/ui/database_item_icon.dart';
import '../../shared/ui/icon_picker_sheet.dart';
import '../../shared/ui/sensitive_text_editing.dart';
import '../../shared/ui/size_format.dart';
import '../totp/totp.dart';
import 'entry_edit_view_model.dart';

/// Modifica o creazione di una voce (EntryEditActivity di Keepass2Android).
class EntryEditView extends ConsumerWidget {
  const EntryEditView({super.key, required this.target});

  final EntryEditTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = ref.watch(entryInitialDraftProvider(target));
    // Database chiuso o voce eliminata: si sta già lasciando la schermata.
    if (initial == null) return const Scaffold();
    return _EntryEditForm(target: target, initial: initial);
  }
}

class _CustomFieldControllers {
  _CustomFieldControllers(CustomFieldDraft field)
    : key = TextEditingController(text: field.key),
      value = TextEditingController(text: field.value),
      protected = field.protected;

  final TextEditingController key;
  final TextEditingController value;
  bool protected;

  CustomFieldDraft toDraft() =>
      CustomFieldDraft(key: key.text, value: value.text, protected: protected);

  void dispose() {
    key.dispose();
    value.dispose();
  }
}

class _EntryEditForm extends ConsumerStatefulWidget {
  const _EntryEditForm({required this.target, required this.initial});

  final EntryEditTarget target;
  final EntryDraft initial;

  @override
  ConsumerState<_EntryEditForm> createState() => _EntryEditFormState();
}

class _EntryEditFormState extends ConsumerState<_EntryEditForm> {
  Widget? _existingIcon(WidgetRef ref) {
    final id = widget.target.entryId;
    final db = ref.watch(databaseSessionProvider)?.database;
    final choice = _iconChoice;
    if (choice != null) {
      final bytes = choice.data ?? db?.meta.customIcons[choice.customId]?.data;
      return bytes == null ? null : CustomIconPreview(bytes: bytes);
    }
    if (id == null || db == null || _icon != widget.initial.icon) return null;
    final entry = findEntry(db, id);
    return entry == null ? null : DatabaseItemIcon(item: entry, database: db);
  }

  bool _hideTemplateReference(_CustomFieldControllers field) {
    if (field.key.text != structuredTemplateReference) return false;
    final db = ref.read(databaseSessionProvider)?.database;
    if (db == null) return false;
    final id = field.value.text.toLowerCase();
    final template = findEntry(db, id);
    return template != null && isStructuredTemplate(template);
  }

  KdbxEntry? _template(WidgetRef ref) {
    final db = ref.watch(databaseSessionProvider)?.database;
    if (db == null) return null;
    if (widget.target.templateId case final id?) {
      final template = findEntry(db, id);
      return template != null && isStructuredTemplate(template)
          ? template
          : null;
    }
    final id = widget.target.entryId;
    final entry = id == null ? null : findEntry(db, id);
    return entry == null ? null : structuredTemplateOf(db, entry);
  }

  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial.title);
  late final _userName = TextEditingController(text: widget.initial.userName);
  late final _password = TextEditingController(text: widget.initial.password);
  late final _url = TextEditingController(text: widget.initial.url);
  late final _overrideUrl = TextEditingController(
    text: widget.initial.overrideUrl,
  );
  late final _notes = TextEditingController(text: widget.initial.notes);
  late final _tags = TextEditingController(text: tagsText(widget.initial.tags));
  late KdbxIcon _icon = widget.initial.icon;
  IconChoice? _iconChoice;
  late bool _expires = widget.initial.expires;
  late DateTime? _expiry = widget.initial.expiry;
  late final _attachments = [...widget.initial.attachments];
  late final _custom = [
    for (final field in widget.initial.custom) _CustomFieldControllers(field),
  ];
  bool _obscurePassword = true;
  bool _saved = false;
  bool _showAllTemplateFields = false;

  @override
  void dispose() {
    for (final c in [
      _title,
      _userName,
      _password,
      _url,
      _overrideUrl,
      _notes,
      _tags,
    ]) {
      c.dispose();
    }
    for (final c in _custom) {
      c.dispose();
    }
    super.dispose();
  }

  EntryDraft get _draft => EntryDraft(
    title: _title.text,
    userName: _userName.text,
    password: _password.text,
    url: _url.text,
    overrideUrl: _overrideUrl.text,
    notes: _notes.text,
    custom: List.unmodifiable(_custom.map((c) => c.toDraft())),
    icon: _icon,
    iconChoice: _iconChoice,
    expires: _expires,
    expiry: _expiry,
    tags: parseTags(_tags.text),
    attachments: List.unmodifiable(_attachments),
  );

  /// Aggiunge un allegato scelto dall'utente (AddBinaryOrAsk di
  /// Keepass2Android). Il permesso sul file scelto si rilascia subito: il
  /// contenuto è già nel database.
  Future<void> _addAttachment() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final PickedFile? picked;
    try {
      picked = await ref.read(filePickerServiceProvider).pick();
    } on Exception {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.entryEditAttachmentUnreadable)),
      );
      return;
    }
    if (picked == null) return;
    unawaited(ref.read(fileStorageProvider).release(picked.ref));
    final data = picked.bytes;
    if (!mounted || data == null) return;
    if (data.length > AppLimits.attachmentBytes) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.entryEditAttachmentTooLarge(
              formatBytes(context, AppLimits.attachmentBytes),
            ),
          ),
        ),
      );
      return;
    }
    var name = picked.ref.name.isEmpty ? 'attachment.bin' : picked.ref.name;
    final index = _attachments.indexWhere((a) => a.name == name);
    if (index >= 0) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.entryEditAttachmentExistsTitle),
          content: Text(l10n.entryEditAttachmentExists(name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.entryEditAttachmentRename),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.entryEditAttachmentReplace),
            ),
          ],
        ),
      );
      if (overwrite == null || !mounted) return;
      if (overwrite) {
        setState(
          () => _attachments[index] = AttachmentDraft.added(
            name: name,
            data: data,
          ),
        );
        return;
      }
      name = uniqueAttachmentName(name, _attachments.map((a) => a.name));
    }
    setState(
      () => _attachments.add(AttachmentDraft.added(name: name, data: data)),
    );
  }

  int _attachmentSize(AttachmentDraft attachment) {
    if (attachment.data case final data?) return data.length;
    final database = ref.read(databaseSessionProvider)?.database;
    final id = attachment.existingId;
    if (database == null || id == null) return 0;
    return database.binaries.getByRef(BinaryReference(id))?.data.length ?? 0;
  }

  Future<void> _chooseIcon() async {
    final icon = await showIconPickerSheet(
      context: context,
      selected: _icon,
      database: ref.read(databaseSessionProvider)?.database,
    );
    if (icon != null && mounted) {
      setState(() {
        _icon = icon.icon;
        _iconChoice = icon;
      });
    }
  }

  /// "Scade" attivato con una data passata o assente: parte da adesso, come
  /// EntryEditActivity di Keepass2Android.
  void _toggleExpires(bool value) {
    setState(() {
      _expires = value;
      final now = DateTime.now();
      if (value && (_expiry == null || _expiry!.isBefore(now))) _expiry = now;
    });
  }

  Future<void> _pickExpiry() async {
    final current = _expiry ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(9999),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted) return;
    final chosen = time ?? TimeOfDay.fromDateTime(current);
    setState(
      () => _expiry = DateTime(
        date.year,
        date.month,
        date.day,
        chosen.hour,
        chosen.minute,
      ),
    );
  }

  bool get _dirty => !_saved && _draft != widget.initial;

  /// Apre il generatore e, se l'utente sceglie "Usa", mette il valore nel
  /// campo password.
  Future<void> _openGenerator() async {
    final generated = await context.push<String>(AppRoutes.generator);
    if (generated == null || !mounted) return;
    setState(() => _password.text = generated);
  }

  /// Chiede l'URI `otpauth://` e lo scrive nel campo `otp`, al posto dei
  /// campi TOTP esistenti.
  Future<void> _setupTotp() async {
    final uri = await showDialog<String>(
      context: context,
      builder: (_) => const _TotpSetupDialog(),
    );
    if (uri == null || !mounted) return;
    final next = withTotpUri([for (final c in _custom) c.toDraft()], uri);
    final removed = [
      for (final c in _custom)
        if (isTotpField(c.key.text.trim())) c,
    ];
    setState(() {
      _custom
        ..removeWhere(removed.contains)
        ..add(_CustomFieldControllers(next.last));
    });
    // I controller tolti si eliminano dopo che i loro campi sono smontati.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in removed) {
        c.dispose();
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final entryId = await ref
        .read(entryEditViewModelProvider(widget.target).notifier)
        .save(_draft);
    if (entryId == null || !mounted) return;
    setState(() => _saved = true);
    if (widget.target.entryId == null) {
      context.pushReplacement(AppRoutes.entry(entryId));
    } else {
      context.pop();
    }
  }

  Future<void> _confirmDiscard() async {
    final l10n = AppLocalizations.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.entryEditDiscardTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.entryEditKeepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.entryEditDiscard),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      setState(() => _saved = true);
      context.pop();
    }
  }

  String? _fieldNameError(AppLocalizations l10n, int index) =>
      switch (validateFieldName([for (final c in _custom) c.key.text], index)) {
        FieldNameError.empty => l10n.entryEditFieldNameRequired,
        FieldNameError.reserved => l10n.entryEditFieldNameReserved,
        FieldNameError.duplicate => l10n.entryEditFieldNameDuplicate,
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(entryEditViewModelProvider(widget.target));
    final busy = state.isLoading;
    final isNew = widget.target.entryId == null;
    final template = _template(ref);
    final database = ref.watch(databaseSessionProvider)?.database;
    final sourceId = widget.target.entryId ?? widget.target.templateId;
    final source = database != null && sourceId != null
        ? findEntry(database, sourceId)
        : null;
    final memoryProtection = database?.meta.memoryProtection;
    bool sensitive(String key, bool? setting) =>
        setting == true || source?.fields[key] is ProtectedTextField;
    bool show(String key, bool hasValue) =>
        template == null ||
        _showAllTemplateFields ||
        hasValue ||
        template.fields.containsKey('_etm_title_$key');

    return PopScope(
      canPop: !_dirty && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isNew ? l10n.entryEditTitleNew : l10n.entryEditTitle),
          actions: [
            IconButton(
              tooltip: l10n.entryEditSave,
              icon: const Icon(Icons.check),
              onPressed: busy ? null : _save,
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.m),
            children: [
              if (busy) ...[
                Semantics(
                  liveRegion: true,
                  label: l10n.saving,
                  child: const LinearProgressIndicator(),
                ),
                const SizedBox(height: AppSpacing.m),
              ],
              if (state case AsyncError(:final error)) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    describeSaveError(l10n, error),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _existingIcon(ref) ?? Icon(kdbxIconData(_icon)),
                title: Text(l10n.entryIcon),
                trailing: TextButton(
                  onPressed: busy ? null : _chooseIcon,
                  child: Text(l10n.entryEditChooseIcon),
                ),
              ),
              _textField(
                _title,
                l10n.entryTitle,
                enabled: !busy,
                sensitive: sensitive(
                  EntryFields.title,
                  memoryProtection?.title,
                ),
              ),
              if (show(EntryFields.userName, _userName.text.isNotEmpty))
                _textField(
                  _userName,
                  l10n.entryUserName,
                  enabled: !busy,
                  sensitive: sensitive(
                    EntryFields.userName,
                    memoryProtection?.userName,
                  ),
                ),
              if (show(EntryFields.password, _password.text.isNotEmpty))
                _textField(
                  _password,
                  l10n.entryPassword,
                  enabled: !busy,
                  obscure: _obscurePassword,
                  sensitive: true,
                  keyboardType: TextInputType.visiblePassword,
                  suffix: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l10n.entryEditGenerate,
                        icon: const Icon(Icons.casino_outlined),
                        onPressed: busy ? null : _openGenerator,
                      ),
                      IconButton(
                        tooltip: _obscurePassword
                            ? l10n.entryShow
                            : l10n.entryHide,
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ],
                  ),
                ),
              if (show(EntryFields.url, _url.text.isNotEmpty))
                _textField(
                  _url,
                  l10n.entryUrl,
                  enabled: !busy,
                  sensitive: true,
                  keyboardType: TextInputType.url,
                ),
              if (show('@override', _overrideUrl.text.isNotEmpty))
                _textField(
                  _overrideUrl,
                  l10n.entryOverrideUrl,
                  enabled: !busy,
                  sensitive: true,
                ),
              if (show(EntryFields.notes, _notes.text.isNotEmpty))
                _textField(
                  _notes,
                  l10n.entryNotes,
                  enabled: !busy,
                  sensitive: sensitive(
                    EntryFields.notes,
                    memoryProtection?.notes,
                  ),
                  maxLength: AppLimits.notes,
                  multiline: true,
                ),
              if (show('@tags', _tags.text.isNotEmpty))
                _textField(
                  _tags,
                  l10n.entryTags,
                  enabled: !busy,
                  helper: l10n.entryEditTagsHint,
                ),
              if (show('@exp_date', _expires))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.entryExpires),
                  value: _expires,
                  onChanged: busy ? null : _toggleExpires,
                ),
              if (_expires)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(l10n.entryEditExpiryDate),
                  subtitle: Text(formatDateTime(context, _expiry!)),
                  onTap: busy ? null : _pickExpiry,
                ),
              if (template != null && !_showAllTemplateFields)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => setState(() => _showAllTemplateFields = true),
                    icon: const Icon(Icons.unfold_more),
                    label: Text(l10n.templateShowAllFields),
                  ),
                ),
              for (final (index, field) in _custom.indexed)
                if (!_hideTemplateReference(field))
                  _customField(l10n, index, field, enabled: !busy),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(
                          () => _custom.add(
                            _CustomFieldControllers(
                              const CustomFieldDraft(
                                key: '',
                                value: '',
                                protected: false,
                              ),
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.entryEditAddField),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: busy ? null : _setupTotp,
                  icon: const Icon(Icons.timer_outlined),
                  label: Text(l10n.entryEditTotpSetup),
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              Semantics(
                header: true,
                child: Text(
                  l10n.entryAttachments,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final (index, attachment) in _attachments.indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file),
                  title: Text(attachment.name),
                  subtitle: Text(
                    formatBytes(context, _attachmentSize(attachment)),
                  ),
                  trailing: IconButton(
                    tooltip: l10n.entryEditAttachmentRemove,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: busy
                        ? null
                        : () => setState(() => _attachments.removeAt(index)),
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: busy ? null : _addAttachment,
                  icon: const Icon(Icons.attach_file),
                  label: Text(l10n.entryEditAttachmentAdd),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customField(
    AppLocalizations l10n,
    int index,
    _CustomFieldControllers field, {
    required bool enabled,
  }) {
    final sensitive = field.protected || isTotpField(field.key.text.trim());
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s),
        child: Column(
          children: [
            SensitiveTextEditing(
              child: TextFormField(
                selectionControls: SensitiveTextEditing.selectionControls,
                controller: field.key,
                enabled: enabled,
                enableIMEPersonalizedLearning: false,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(AppLimits.fieldName),
                ],
                validator: (_) => _fieldNameError(l10n, index),
                decoration: InputDecoration(labelText: l10n.entryEditFieldName),
              ),
            ),
            SensitiveTextEditing(
              child: TextFormField(
                selectionControls: SensitiveTextEditing.selectionControls,
                controller: field.value,
                enabled: enabled,
                obscureText: field.protected,
                autocorrect: !sensitive,
                smartDashesType: sensitive ? SmartDashesType.disabled : null,
                smartQuotesType: sensitive ? SmartQuotesType.disabled : null,
                enableSuggestions: !sensitive,
                enableIMEPersonalizedLearning: false,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(AppLimits.fieldValue),
                ],
                decoration: InputDecoration(
                  labelText: l10n.entryEditFieldValue,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.entryEditFieldProtected),
                    value: field.protected,
                    onChanged: enabled
                        ? (v) => setState(() => field.protected = v)
                        : null,
                  ),
                ),
                IconButton(
                  tooltip: l10n.entryEditRemoveField,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: enabled
                      ? () => setState(() => _custom.removeAt(index).dispose())
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String label, {
    required bool enabled,
    bool obscure = false,
    bool sensitive = false,
    bool multiline = false,
    int maxLength = AppLimits.fieldValue,
    TextInputType? keyboardType,
    Widget? suffix,
    String? helper,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: SensitiveTextEditing(
        child: TextFormField(
          selectionControls: SensitiveTextEditing.selectionControls,
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          autocorrect: !sensitive,
          smartDashesType: sensitive ? SmartDashesType.disabled : null,
          smartQuotesType: sensitive ? SmartQuotesType.disabled : null,
          enableSuggestions: !sensitive,
          // La tastiera non deve imparare i valori delle voci (decisione D8).
          enableIMEPersonalizedLearning: false,
          keyboardType:
              keyboardType ??
              (multiline ? TextInputType.multiline : TextInputType.text),
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? null : 1,
          inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
          decoration: InputDecoration(
            labelText: label,
            helperText: helper,
            suffixIcon: suffix,
          ),
        ),
      ),
    );
  }
}

/// Inserimento dell'URI `otpauth://`; restituisce l'URI solo se valido.
class _TotpSetupDialog extends StatefulWidget {
  const _TotpSetupDialog();

  @override
  State<_TotpSetupDialog> createState() => _TotpSetupDialogState();
}

class _TotpSetupDialogState extends State<_TotpSetupDialog> {
  final _uri = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _uri
      ..clear()
      ..dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final value = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const _TotpScanner()));
    if (!mounted || value == null) return;
    if (value.length > AppLimits.fieldValue) {
      setState(() => _invalid = true);
      return;
    }
    _uri.text = value;
    setState(() => _invalid = false);
  }

  void _apply() {
    try {
      withTotpUri(const [], _uri.text);
      Navigator.of(context).pop(_uri.text.trim());
    } on InvalidTotpConfig {
      setState(() => _invalid = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.entryEditTotpSetup),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.entryEditTotpHint),
          TextButton.icon(
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(l10n.entryEditTotpScan),
          ),
          const SizedBox(height: AppSpacing.m),
          SensitiveTextEditing(
            child: TextField(
              selectionControls: SensitiveTextEditing.selectionControls,
              controller: _uri,
              autofocus: true,
              autocorrect: false,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              keyboardType: TextInputType.url,
              inputFormatters: [
                LengthLimitingTextInputFormatter(AppLimits.fieldValue),
              ],
              onSubmitted: (_) => _apply(),
              decoration: InputDecoration(
                labelText: l10n.entryEditTotpUri,
                errorText: _invalid ? l10n.entryEditTotpInvalid : null,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: _apply, child: Text(l10n.entryEditTotpApply)),
      ],
    );
  }
}

class _TotpScanner extends StatefulWidget {
  const _TotpScanner();

  @override
  State<_TotpScanner> createState() => _TotpScannerState();
}

class _TotpScannerState extends State<_TotpScanner> {
  bool _finished = false;
  bool _error = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.entryEditTotpScan)),
      body: _error
          ? Center(child: Text(l10n.entryEditTotpScanError))
          : OfflineQrScanner(
              onDetected: (value) {
                if (_finished || !mounted) return;
                _finished = true;
                Navigator.of(context).pop(value);
              },
              onError: (_) {
                if (mounted) setState(() => _error = true);
              },
            ),
    );
  }
}

/// Scelta tra le icone standard (IconPickerActivity di Keepass2Android).
