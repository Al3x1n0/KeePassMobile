import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/database/database_errors.dart';
import '../../shared/database/database_session.dart';
import '../../shared/database/kdbx_items.dart';
import '../../shared/security/biometric_key_store.dart';
import '../../shared/ui/master_key_form.dart';
import '../../shared/ui/selection_sheet.dart';
import 'biometric_unlock_view_model.dart';
import 'database_settings_view_model.dart';

/// Impostazioni del database aperto (DatabaseSettingsActivity di
/// Keepass2Android): nome, nome utente predefinito, cestino, cronologia,
/// cifrario e derivazione della chiave con la stima del tempo di apertura,
/// sblocco biometrico.
class DatabaseSettingsView extends ConsumerStatefulWidget {
  const DatabaseSettingsView({super.key});

  @override
  ConsumerState<DatabaseSettingsView> createState() =>
      _DatabaseSettingsViewState();
}

/// Limiti dei valori numerici (AES-KDF e Argon2 su un telefono).
abstract final class _Limits {
  static const rounds = (1, KdbxResourceLimits.maxAesRounds);
  static const memoryMiB = (
    1,
    KdbxResourceLimits.maxArgon2Memory ~/ DataSize.mebi,
  );
  static const iterations = (1, KdbxResourceLimits.maxArgon2Iterations);
  static const parallelism = (1, KdbxResourceLimits.maxArgon2Parallelism);
  static const historyItems = (0, 9999);
  static const historySizeMiB = (0, 1024);
}

class _DatabaseSettingsViewState extends ConsumerState<DatabaseSettingsView> {
  final _form = GlobalKey<FormState>();
  late final DatabaseSettings _initial;
  late final _name = TextEditingController(text: _initial.name);
  late final _defaultUser = TextEditingController(
    text: _initial.defaultUserName,
  );
  late final _historyItems = TextEditingController(
    text: _initial.historyMaxItems < 0 ? '' : '${_initial.historyMaxItems}',
  );
  late final _historySize = TextEditingController(
    text: _initial.historyMaxSize < 0
        ? ''
        : '${(_initial.historyMaxSize / DataSize.mebi).ceil()}',
  );
  late final _rounds = TextEditingController();
  late final _memory = TextEditingController();
  late final _iterations = TextEditingController();
  late final _parallelism = TextEditingController();
  late bool _recycleBin = _initial.recycleBinEnabled;
  late String _templatesGroupId = _initial.templatesGroupId;
  late String _cipher = _initial.cipher;
  late String _kdfId = _initial.kdf.kdfId;

  @override
  void initState() {
    super.initState();
    // Il database è aperto: la route esiste solo con una sessione.
    _initial =
        ref.read(databaseSettingsProvider) ??
        (throw StateError('database chiuso'));
    final aes = switch (_initial.kdf) {
      AesKdfSettings(:final rounds) => rounds,
      _ => Defaults.keyEncryptionRounds,
    };
    // Argon2: valori attuali o quelli dei database nuovi (D1).
    final argon = switch (_initial.kdf) {
      final Argon2KdfSettings a => a,
      _ => const Argon2KdfSettings(
        id: true,
        memory: 64 * DataSize.mebi,
        iterations: 2,
        parallelism: 2,
      ),
    };
    _rounds.text = '$aes';
    _memory.text = '${(argon.memory / DataSize.mebi).ceil()}';
    _iterations.text = '${argon.iterations}';
    _parallelism.text = '${argon.parallelism}';
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _defaultUser,
      _historyItems,
      _historySize,
      _rounds,
      _memory,
      _iterations,
      _parallelism,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  KdfSettings _kdf() => _kdfId == KdfId.aes
      ? AesKdfSettings(rounds: int.parse(_rounds.text))
      : Argon2KdfSettings(
          id: _kdfId == KdfId.argon2id,
          memory: int.parse(_memory.text) * DataSize.mebi,
          iterations: int.parse(_iterations.text),
          parallelism: int.parse(_parallelism.text),
        );

  DatabaseSettings _settings() => _initial.copyWith(
    name: _name.text,
    defaultUserName: _defaultUser.text,
    recycleBinEnabled: _recycleBin,
    templatesGroupId: _templatesGroupId,
    historyMaxItems: _historyItems.text.isEmpty
        ? DatabaseSettings.unlimited
        : int.parse(_historyItems.text),
    historyMaxSize: _historySize.text.isEmpty
        ? DatabaseSettings.unlimited
        : int.parse(_historySize.text) * DataSize.mebi,
    cipher: _cipher,
    // Con la sola chiave derivata la KDF non si può cambiare (ADR-008).
    kdf: _hasRawKey ? _kdf() : _initial.kdf,
  );

  bool get _hasRawKey => ref.read(databaseSessionProvider)?.hasRawKey ?? true;

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final saved = await ref
        .read(databaseSettingsViewModelProvider.notifier)
        .save(_settings());
    if (!saved || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.dbSettingsSaved)));
    context.pop();
  }

  void _measure() {
    if (!(_form.currentState?.validate() ?? false)) return;
    ref
        .read(databaseSettingsViewModelProvider.notifier)
        .measure(_kdf(), kdbxVersion: _initial.kdbxVersion);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(databaseSettingsViewModelProvider);
    final busy = state.isLoading;
    final measured = state.value;
    final kdfEditable =
        !busy &&
        ref.watch(databaseSessionProvider.select((s) => s?.hasRawKey ?? true));

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.dbSettingsTitle),
        actions: [
          IconButton(
            tooltip: l10n.entryEditSave,
            icon: const Icon(Icons.check),
            onPressed: busy ? null : _save,
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.m),
          children: [
            _text(_name, l10n.dbSettingsName, enabled: !busy),
            _text(_defaultUser, l10n.dbSettingsDefaultUserName, enabled: !busy),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.dbSettingsRecycleBin),
              value: _recycleBin,
              onChanged: busy ? null : (v) => setState(() => _recycleBin = v),
            ),
            _number(
              _historyItems,
              l10n.dbSettingsHistoryMaxItems,
              _Limits.historyItems,
              enabled: !busy,
              optional: true,
            ),
            _number(
              _historySize,
              l10n.dbSettingsHistoryMaxSize,
              _Limits.historySizeMiB,
              enabled: !busy,
              optional: true,
            ),
            _templatesGroupChoice(l10n, enabled: !busy),
            _BiometricUnlockTile(enabled: !busy),
            const SizedBox(height: AppSpacing.m),
            Text(
              l10n.dbSettingsEncryption(_initial.kdbxVersion),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.s),
            _choice(
              l10n.dbSettingsCipher,
              _cipher,
              {
                for (final c in _initial.allowedCiphers)
                  c: _cipherLabel(l10n, c),
              },
              enabled: !busy,
              onChanged: (c) => setState(() => _cipher = c),
            ),
            _choice(
              l10n.dbSettingsKdf,
              _kdfId,
              {for (final k in _initial.allowedKdfs) k: _kdfLabel(l10n, k)},
              enabled: kdfEditable,
              onChanged: (k) => setState(() => _kdfId = k),
            ),
            if (!busy && !kdfEditable)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.m),
                child: Text(
                  l10n.dbSettingsKdfLocked,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (_kdfId == KdfId.aes)
              _number(
                _rounds,
                l10n.dbSettingsRounds,
                _Limits.rounds,
                enabled: kdfEditable,
              )
            else ...[
              _number(
                _memory,
                l10n.dbSettingsMemory,
                _Limits.memoryMiB,
                enabled: kdfEditable,
              ),
              _number(
                _iterations,
                l10n.dbSettingsIterations,
                _Limits.iterations,
                enabled: kdfEditable,
              ),
              _number(
                _parallelism,
                l10n.dbSettingsParallelism,
                _Limits.parallelism,
                enabled: kdfEditable,
              ),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: busy ? null : _measure,
                icon: const Icon(Icons.timer_outlined),
                label: Text(l10n.dbSettingsMeasure),
              ),
            ),
            if (measured != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.dbSettingsMeasured(
                    NumberFormat.decimalPatternDigits(
                      locale: Localizations.localeOf(context).toString(),
                      decimalDigits: 1,
                    ).format(measured.inMilliseconds / 1000),
                  ),
                ),
              ),
            FormStatus(
              busy: busy,
              busyText: l10n.saving,
              error: switch (state) {
                AsyncError(:final error) => describeSaveError(l10n, error),
                _ => null,
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _templatesGroupChoice(AppLocalizations l10n, {required bool enabled}) {
    final database = ref.watch(databaseSessionProvider)?.database;
    final options = <String, String>{'': l10n.dbSettingsTemplatesNone};
    if (database != null) {
      void addGroups(KdbxGroup group, String parent) {
        if (isInRecycleBin(database, group)) return;
        final path = parent.isEmpty ? group.name : '$parent / ${group.name}';
        options[itemIdOf(group)] = path;
        for (final child in group.groups) {
          addGroups(child, path);
        }
      }

      addGroups(database.root, '');
    }
    return _choice(
      l10n.dbSettingsTemplatesGroup,
      _templatesGroupId,
      options,
      enabled: enabled,
      onChanged: (id) => setState(() => _templatesGroupId = id),
    );
  }

  Widget _text(
    TextEditingController controller,
    String label, {
    required bool enabled,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.m),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      enableIMEPersonalizedLearning: false,
      inputFormatters: [LengthLimitingTextInputFormatter(AppLimits.fieldName)],
      decoration: InputDecoration(labelText: label),
    ),
  );

  Widget _number(
    TextEditingController controller,
    String label,
    (int, int) range, {
    required bool enabled,
    bool optional = false,
  }) {
    final l10n = AppLocalizations.of(context);
    final (min, max) = range;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        enableIMEPersonalizedLearning: false,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter('$max'.length),
        ],
        validator: (text) {
          if ((text ?? '').isEmpty && optional) return null;
          final value = int.tryParse(text ?? '');
          return value == null || value < min || value > max
              ? l10n.dbSettingsRange(min, max)
              : null;
        },
        decoration: InputDecoration(
          labelText: label,
          helperText: optional ? l10n.dbSettingsEmptyUnlimited : null,
        ),
      ),
    );
  }

  Widget _choice(
    String label,
    String value,
    Map<String, String> options, {
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    enabled: enabled,
    subtitle: Text(options[value] ?? value),
    trailing: const Icon(Icons.chevron_right),
    onTap: !enabled
        ? null
        : () async {
            final choice = await showSelectionSheet<String>(
              context: context,
              title: label,
              selected: value,
              options: options,
            );
            if (mounted && choice != null) onChanged(choice);
          },
  );

  static String _cipherLabel(AppLocalizations l10n, String id) => switch (id) {
    CipherId.chaCha20 => l10n.cipherChaCha20,
    CipherId.twofish => l10n.cipherTwofish,
    _ => l10n.cipherAes,
  };

  static String _kdfLabel(AppLocalizations l10n, String id) => switch (id) {
    KdfId.argon2d => l10n.kdfArgon2d,
    KdfId.argon2id => l10n.kdfArgon2id,
    _ => l10n.kdfAes,
  };
}

/// "Sblocco biometrico" del database aperto (ADR-008).
class _BiometricUnlockTile extends ConsumerWidget {
  const _BiometricUnlockTile({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(biometricUnlockViewModelProvider);
    final error = switch (state) {
      AsyncError(error: BiometricKeyException(:final reason)) =>
        describeBiometricError(l10n, reason),
      AsyncError() => l10n.errorBiometricFailed,
      _ => null,
    };
    final name = ref.read(databaseSessionProvider)?.file.name ?? '';

    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(Icons.fingerprint),
      title: Text(l10n.dbSettingsBiometric),
      subtitle: Text(
        error ?? l10n.dbSettingsBiometricInfo,
        style: error == null
            ? null
            : TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      value: state.value ?? false,
      onChanged: !enabled || state.isLoading
          ? null
          : (on) {
              final viewModel = ref.read(
                biometricUnlockViewModelProvider.notifier,
              );
              if (on) {
                viewModel.enable(
                  BiometricPromptTexts(
                    title: l10n.biometricEnableTitle,
                    subtitle: name,
                    cancel: l10n.biometricPromptCancel,
                  ),
                );
              } else {
                viewModel.disable();
              }
            },
    );
  }
}
