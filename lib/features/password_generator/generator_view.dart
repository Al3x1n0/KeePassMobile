import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/ui/selection_sheet.dart';
import 'generator_view_model.dart';
import 'password_generator.dart';

/// Generatore di password e passphrase (GeneratePasswordActivity di
/// Keepass2Android). "Usa" chiude la schermata restituendo il valore.
class GeneratorView extends ConsumerStatefulWidget {
  const GeneratorView({super.key});

  /// Chiave del testo con il valore generato (per i test).
  static const valueKey = ValueKey('generator-value');

  @override
  ConsumerState<GeneratorView> createState() => _GeneratorViewState();
}

class _GeneratorViewState extends ConsumerState<GeneratorView> {
  static const _quickLengths = [6, 8, 12, 16, 24, 32];

  late final TextEditingController _length;
  late final TextEditingController _wordCount;
  late final TextEditingController _separator;

  @override
  void initState() {
    super.initState();
    final options = ref.read(generatorViewModelProvider).options;
    _length = TextEditingController();
    _wordCount = TextEditingController();
    _separator = TextEditingController();
    _syncControllers(options);
  }

  @override
  void dispose() {
    _length.dispose();
    _wordCount.dispose();
    _separator.dispose();
    super.dispose();
  }

  void _syncControllers(GeneratorOptions options) {
    _length.text = '${options.charset.length}';
    _wordCount.text = '${options.passphrase.wordCount}';
    _separator.text = options.passphrase.separator;
  }

  GeneratorViewModel get _viewModel =>
      ref.read(generatorViewModelProvider.notifier);

  GeneratorOptions get _options => ref.read(generatorViewModelProvider).options;

  void _updateCharset(CharsetOptions charset) =>
      _viewModel.update(_options.copyWith(charset: charset));

  void _updatePassphrase(PassphraseOptions passphrase) =>
      _viewModel.update(_options.copyWith(passphrase: passphrase));

  void _toggleGroup(CharGroup group, bool selected) {
    final groups = {..._options.charset.groups};
    selected ? groups.add(group) : groups.remove(group);
    _updateCharset(_options.charset.copyWith(groups: groups));
  }

  /// Chiede il nome e salva le opzioni correnti come profilo.
  Future<void> _saveProfile() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _ProfileNameDialog(),
    );
    if (name == null || !mounted) return;
    if (!_viewModel.saveProfile(name)) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.generatorProfileReserved)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(generatorViewModelProvider);
    final charset = state.options.charset;
    final passphrase = state.options.passphrase;
    final profile = matchingProfile(
      state.options,
      custom: state.customProfiles,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.generatorTitle),
        actions: [
          TextButton(
            onPressed: state.isValid ? () => context.pop(state.value) : null,
            child: Text(l10n.generatorUse),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.m),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.isValid ? state.value : l10n.generatorInvalid,
                          key: GeneratorView.valueKey,
                          style: state.isValid
                              ? theme.textTheme.titleMedium?.copyWith(
                                  fontFamily: 'monospace',
                                )
                              : theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                        ),
                        if (state.isValid) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            l10n.generatorEntropy(state.entropyBits.floor()),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.generatorRegenerate,
                    icon: const Icon(Icons.refresh),
                    onPressed: state.isValid ? _viewModel.regenerate : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.generatorProfile),
            subtitle: Text(profile ?? l10n.generatorProfileCustom),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final name = await showSelectionSheet<String>(
                context: context,
                title: l10n.generatorProfile,
                selected: profile ?? '',
                options: {
                  '': l10n.generatorProfileCustom,
                  for (final name in generatorProfiles.keys) name: name,
                  for (final name in state.customProfiles.keys) name: name,
                },
              );
              if (!mounted || name == null || name.isEmpty) return;
              _viewModel.applyProfile(name);
              _syncControllers(_options);
            },
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: state.isValid ? _saveProfile : null,
                icon: const Icon(Icons.bookmark_add_outlined),
                label: Text(l10n.generatorSaveProfile),
              ),
              if (state.customProfiles.containsKey(profile))
                IconButton(
                  tooltip: l10n.generatorRemoveProfile,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _viewModel.removeProfile(profile ?? ''),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),
          Text(l10n.generatorCharacters, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.s),
          TextField(
            controller: _length,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: InputDecoration(
              labelText: l10n.generatorLength,
            ),
            onChanged: (text) => _updateCharset(
              charset.copyWith(
                length: (int.tryParse(text) ?? 0).clamp(
                  0,
                  AppLimits.generatedLength,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.s,
            children: [
              for (final length in _quickLengths)
                ChoiceChip(
                  label: Text('$length'),
                  selected: charset.length == length,
                  onSelected: (_) {
                    _length.text = '$length';
                    _updateCharset(charset.copyWith(length: length));
                  },
                ),
            ],
          ),
          for (final group in CharGroup.values)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_groupLabel(l10n, group)),
              value: charset.groups.contains(group),
              onChanged: (v) => _toggleGroup(group, v ?? false),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.generatorExcludeLookAlike(lookAlikeChars)),
            value: charset.excludeLookAlike,
            onChanged: (v) =>
                _updateCharset(charset.copyWith(excludeLookAlike: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.generatorAtLeastOne),
            value: charset.atLeastOneFromEachGroup,
            onChanged: (v) =>
                _updateCharset(charset.copyWith(atLeastOneFromEachGroup: v)),
          ),
          const SizedBox(height: AppSpacing.l),
          Text(l10n.generatorPassphrase, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.s),
          TextField(
            controller: _wordCount,
            enableIMEPersonalizedLearning: false,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            decoration: InputDecoration(
              labelText: l10n.generatorWordCount,
            ),
            onChanged: (text) => _updatePassphrase(
              passphrase.copyWith(
                wordCount: (int.tryParse(text) ?? 0).clamp(
                  0,
                  AppLimits.generatedWords,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          TextField(
            controller: _separator,
            enableIMEPersonalizedLearning: false,
            inputFormatters: [
              LengthLimitingTextInputFormatter(AppLimits.wordSeparator),
            ],
            decoration: InputDecoration(
              labelText: l10n.generatorSeparator,
            ),
            onChanged: (text) =>
                _updatePassphrase(passphrase.copyWith(separator: text)),
          ),
          const SizedBox(height: AppSpacing.m),
          SegmentedButton<WordCase>(
            segments: [
              ButtonSegment(
                value: WordCase.lowercase,
                label: Text(l10n.generatorCaseLower),
              ),
              ButtonSegment(
                value: WordCase.uppercase,
                label: Text(l10n.generatorCaseUpper),
              ),
              ButtonSegment(
                value: WordCase.pascalCase,
                label: Text(l10n.generatorCasePascal),
              ),
            ],
            selected: {passphrase.wordCase},
            onSelectionChanged: (s) =>
                _updatePassphrase(passphrase.copyWith(wordCase: s.first)),
          ),
        ],
      ),
    );
  }

  static String _groupLabel(AppLocalizations l10n, CharGroup group) =>
      switch (group) {
        CharGroup.upperCase => l10n.generatorUpperCase,
        CharGroup.lowerCase => l10n.generatorLowerCase,
        CharGroup.digits => l10n.generatorDigits,
        CharGroup.minus => l10n.generatorMinus,
        CharGroup.underline => l10n.generatorUnderline,
        CharGroup.space => l10n.generatorSpace,
        CharGroup.specials => l10n.generatorSpecials,
        CharGroup.specialsExtended => l10n.generatorSpecialsExtended,
        CharGroup.brackets => l10n.generatorBrackets(CharGroup.brackets.chars),
      };
}

/// Nome del profilo da salvare.
class _ProfileNameDialog extends StatefulWidget {
  const _ProfileNameDialog();

  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) return;
    Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.generatorSaveProfile),
      content: TextField(
        controller: _name,
        autofocus: true,
        enableIMEPersonalizedLearning: false,
        inputFormatters: [
          LengthLimitingTextInputFormatter(AppLimits.fieldName),
        ],
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: l10n.generatorProfileName,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: _save, child: Text(l10n.entryEditSave)),
      ],
    );
  }
}
