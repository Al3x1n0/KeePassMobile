import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../storage/file_storage.dart';
import '../storage/key_file.dart';
import 'sensitive_text_editing.dart';

/// Chiave principale nuova: password con conferma e file chiave facoltativo
/// (creazione del database e cambio della chiave, SetPasswordDialog di
/// Keepass2Android). Serve almeno uno dei due.
class MasterKeyForm extends ConsumerStatefulWidget {
  const MasterKeyForm({
    super.key,
    required this.enabled,
    required this.submitLabel,
    required this.onSubmit,
    this.passwordLabel,
    this.requireCurrentPassword = false,
    this.allowEmptyCurrentPassword = false,
    this.currentPasswordLabel,
    this.onSubmitWithCurrent,
    this.info,
  });

  final bool enabled;
  final bool requireCurrentPassword;
  final bool allowEmptyCurrentPassword;
  final String? currentPasswordLabel;
  final void Function(
    String currentPassword,
    String password,
    PickedFile? keyFile,
  )?
  onSubmitWithCurrent;
  final String submitLabel;

  /// Etichetta del primo campo (predefinita: password principale).
  final String? passwordLabel;

  /// Testo informativo sopra il pulsante.
  final String? info;

  /// Chiamato con valori validi: [password] può essere vuota se c'è [keyFile].
  final void Function(String password, PickedFile? keyFile) onSubmit;

  @override
  ConsumerState<MasterKeyForm> createState() => _MasterKeyFormState();
}

class _MasterKeyFormState extends ConsumerState<MasterKeyForm> {
  final _form = GlobalKey<FormState>();
  final _currentPassword = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _choosing = false;
  bool _obscure = true;
  PickedFile? _keyFile;

  @override
  void dispose() {
    _currentPassword
      ..clear()
      ..dispose();
    _password
      ..clear()
      ..dispose();
    _confirm
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    if (widget.onSubmitWithCurrent case final submit?) {
      submit(_currentPassword.text, _password.text, _keyFile);
    } else {
      widget.onSubmit(_password.text, _keyFile);
    }
  }

  Future<void> _chooseKeyFile({bool generate = false}) async {
    if (_choosing) return;
    setState(() => _choosing = true);
    final l10n = AppLocalizations.of(context);
    try {
      final picked = generate
          ? await createKeyFile(ref.read(fileStorageProvider))
          : await ref.read(filePickerServiceProvider).pick();
      if (picked != null && mounted) setState(() => _keyFile = picked);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            generate ? l10n.errorCreateKeyFile : l10n.errorKeyFileUnavailable,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _choosing = false);
    }
  }

  Widget _secretField(
    TextEditingController controller,
    String label,
    String? Function(String?) validator,
  ) {
    final l10n = AppLocalizations.of(context);
    return SensitiveTextEditing(
      child: TextFormField(
        selectionControls: SensitiveTextEditing.selectionControls,
        controller: controller,
        enabled: widget.enabled,
        obscureText: _obscure,
        autocorrect: false,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        keyboardType: TextInputType.visiblePassword,
        inputFormatters: [
          LengthLimitingTextInputFormatter(AppLimits.masterPassword),
        ],
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(
            tooltip: _obscure
                ? l10n.unlockShowPassword
                : l10n.unlockHidePassword,
            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final keyFile = _keyFile;
    final info = widget.info;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.requireCurrentPassword) ...[
            _secretField(
              _currentPassword,
              widget.currentPasswordLabel ?? l10n.changeKeyCurrentPassword,
              (value) =>
                  !widget.allowEmptyCurrentPassword && (value ?? "").isEmpty
                  ? l10n.changeKeyCurrentRequired
                  : null,
            ),
            const SizedBox(height: AppSpacing.m),
          ],
          _secretField(
            _password,
            widget.passwordLabel ?? l10n.unlockPassword,
            (value) => (value ?? '').isEmpty && _keyFile == null
                ? l10n.createDatabaseKeyRequired
                : null,
          ),
          const SizedBox(height: AppSpacing.m),
          _secretField(
            _confirm,
            l10n.createDatabaseConfirm,
            (value) =>
                value != _password.text ? l10n.createDatabaseMismatch : null,
          ),
          const SizedBox(height: AppSpacing.m),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.key_outlined),
            title: Text(l10n.unlockKeyFile),
            subtitle: Text(keyFile?.ref.name ?? l10n.unlockNoKeyFile),
            trailing: keyFile == null
                ? TextButton(
                    onPressed: widget.enabled && !_choosing
                        ? () => _chooseKeyFile()
                        : null,
                    child: Text(l10n.unlockChooseKeyFile),
                  )
                : IconButton(
                    tooltip: l10n.unlockRemoveKeyFile,
                    icon: const Icon(Icons.close),
                    onPressed: widget.enabled
                        ? () => setState(() => _keyFile = null)
                        : null,
                  ),
          ),
          if (keyFile == null)
            TextButton.icon(
              onPressed: widget.enabled && !_choosing
                  ? () => _chooseKeyFile(generate: true)
                  : null,
              icon: const Icon(Icons.add),
              label: Text(l10n.generateKeyFile),
            ),
          if (info != null) ...[
            const SizedBox(height: AppSpacing.s),
            Text(info, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: AppSpacing.l),
          FilledButton(
            onPressed: widget.enabled && !_choosing ? _submit : null,
            child: Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}

/// Avanzamento e messaggio d'errore sotto un modulo.
class FormStatus extends StatelessWidget {
  const FormStatus({
    super.key,
    required this.busy,
    required this.busyText,
    this.error,
  });

  final bool busy;
  final String busyText;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = this.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (busy) ...[
          const SizedBox(height: AppSpacing.m),
          Semantics(
            liveRegion: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox.square(
                  dimension: AppSpacing.l,
                  child: CircularProgressIndicator(),
                ),
                const SizedBox(width: AppSpacing.s),
                Flexible(child: Text(busyText)),
              ],
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.m),
          Semantics(
            liveRegion: true,
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
