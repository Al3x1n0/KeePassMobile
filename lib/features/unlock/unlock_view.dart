import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../../shared/security/biometric_key_store.dart';
import '../../shared/storage/file_storage.dart';
import '../../shared/storage/remote_cache.dart';
import '../../shared/storage/remote_storage.dart';
import '../../shared/ui/sensitive_text_editing.dart';
import 'unlock_view_model.dart';

/// Schermata di sblocco: password principale e file chiave facoltativo; con la
/// biometria attiva per il file la richiesta biometrica parte da sola.
class UnlockView extends ConsumerStatefulWidget {
  const UnlockView({super.key, required this.args});

  final UnlockArgs args;

  @override
  ConsumerState<UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends ConsumerState<UnlockView> {
  final _password = TextEditingController();
  bool _obscure = true;
  late PickedFile? _keyFile = widget.args.keyFile;

  late bool _offline = widget.args.offline;

  bool get _biometric =>
      ref.read(biometricKeyStoreProvider).isEnabled(widget.args.database.ref);

  /// Richiesta biometrica in attesa del ritorno in primo piano (blocco a
  /// schermo spento o con l'app in background).
  AppLifecycleListener? _resume;

  @override
  void initState() {
    super.initState();
    if (_biometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoBiometrics());
    }
  }

  void _autoBiometrics() {
    if (!mounted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
      _unlockWithBiometrics();
      return;
    }
    _resume ??= AppLifecycleListener(
      onResume: () {
        final listener = _resume;
        _resume = null;
        listener?.dispose();
        if (mounted) _unlockWithBiometrics();
      },
    );
  }

  @override
  void dispose() {
    _resume?.dispose();
    _password
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _unlock() {
    ref
        .read(unlockViewModelProvider.notifier)
        .unlock(
          args: UnlockArgs(
            database: widget.args.database,
            keyFile: _keyFile,
            offline: _offline,
            replacing: widget.args.replacing,
            additional: widget.args.additional,
            lockGeneration: widget.args.lockGeneration,
          ),
          password: _password.text,
          biometricTexts: _texts(
            AppLocalizations.of(context).biometricUpdateTitle,
          ),
        );
  }

  void _unlockWithBiometrics() {
    ref
        .read(unlockViewModelProvider.notifier)
        .unlockWithBiometrics(
          args: UnlockArgs(
            database: widget.args.database,
            keyFile: _keyFile,
            offline: _offline,
            replacing: widget.args.replacing,
            additional: widget.args.additional,
            lockGeneration: widget.args.lockGeneration,
          ),
          texts: _texts(AppLocalizations.of(context).biometricPromptTitle),
        );
  }

  BiometricPromptTexts _texts(String title) => BiometricPromptTexts(
    title: title,
    subtitle: widget.args.database.ref.name,
    cancel: AppLocalizations.of(context).biometricPromptCancel,
  );

  Future<void> _chooseKeyFile() async {
    final l10n = AppLocalizations.of(context);
    try {
      final picked = await ref.read(filePickerServiceProvider).pick();
      if (picked != null && mounted) setState(() => _keyFile = picked);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.errorKeyFileUnavailable)));
    }
  }

  Future<void> _chooseDatabaseAgain() async {
    final l10n = AppLocalizations.of(context);
    try {
      final picked = await ref.read(filePickerServiceProvider).pick();
      if (picked == null || !mounted) return;
      context.go(
        widget.args.additional ? AppRoutes.additionalUnlock : AppRoutes.unlock,
        extra: UnlockArgs(
          additional: widget.args.additional,
          lockGeneration: widget.args.lockGeneration,
          database: picked,
          keyFile: _keyFile,
          replacing: widget.args.replacing ?? widget.args.database.ref,
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(describeFilePickError(l10n, error))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (widget.args.additional) {
      ref.listen(databaseSessionProvider, (previous, next) {
        if (previous != next && next != null) context.go(AppRoutes.database);
      });
    }
    final state = ref.watch(unlockViewModelProvider);
    final busy = state.isLoading;
    final keyFile = _keyFile;
    final biometric = _biometric;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.l),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: appFormMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.args.database.ref.name,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.l),
                  SensitiveTextEditing(
                    child: TextField(
                      selectionControls: SensitiveTextEditing.selectionControls,
                      controller: _password,
                      enabled: !busy,
                      // Con la richiesta biometrica la tastiera resterebbe sotto.
                      autofocus: !biometric,
                      obscureText: _obscure,
                      autocorrect: false,
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          AppLimits.masterPassword,
                        ),
                      ],
                      onSubmitted: (_) => _unlock(),
                      decoration: InputDecoration(
                        labelText: l10n.unlockPassword,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscure
                              ? l10n.unlockShowPassword
                              : l10n.unlockHidePassword,
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.m),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.key_outlined),
                    title: Text(l10n.unlockKeyFile),
                    subtitle: Text(keyFile?.ref.name ?? l10n.unlockNoKeyFile),
                    trailing: keyFile == null
                        ? null
                        : IconButton(
                            tooltip: l10n.unlockRemoveKeyFile,
                            icon: const Icon(Icons.close),
                            onPressed: busy
                                ? null
                                : () => setState(() => _keyFile = null),
                          ),
                  ),
                  if (keyFile == null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton(
                        onPressed: busy ? null : _chooseKeyFile,
                        child: Text(l10n.unlockChooseKeyFile),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.l),
                  if (ref
                          .watch(
                            remoteCacheAvailableProvider(
                              widget.args.database.ref,
                            ),
                          )
                          .value ??
                      false)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.unlockFromCache),
                      value: _offline,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => _offline = v),
                    ),
                  FilledButton(
                    onPressed: busy ? null : _unlock,
                    child: Text(l10n.unlockButton),
                  ),
                  if (biometric) ...[
                    const SizedBox(height: AppSpacing.s),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _unlockWithBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: Text(l10n.unlockBiometric),
                    ),
                  ],
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
                          Text(l10n.unlockInProgress),
                        ],
                      ),
                    ),
                  ],
                  if (state case AsyncError(error: FileUnavailableException())
                      when !RemoteStorage.handles(widget.args.database.ref))
                    TextButton.icon(
                      onPressed: busy ? null : _chooseDatabaseAgain,
                      icon: const Icon(Icons.folder_open),
                      label: Text(l10n.unlockChooseAgain),
                    ),
                  if (state case AsyncError(:final error)) ...[
                    const SizedBox(height: AppSpacing.m),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        describeDatabaseError(l10n, error),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
