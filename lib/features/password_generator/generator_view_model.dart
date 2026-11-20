import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/storage/preferences.dart';
import 'password_generator.dart';

/// Stato del generatore: opzioni correnti e valore generato.
@immutable
class GeneratorState {
  const GeneratorState({
    required this.options,
    required this.value,
    this.customProfiles = const {},
  });

  final GeneratorOptions options;

  /// Profili salvati dall'utente (PasswordProfiles di Keepass2Android).
  final Map<String, GeneratorOptions> customProfiles;

  /// Valore generato; vuoto se le opzioni non sono valide.
  final String value;

  bool get isValid => options.isValid;

  double get entropyBits => generationEntropyBits(options);
}

/// Generatore di password e passphrase (GeneratePasswordActivity di
/// Keepass2Android). Le ultime opzioni usate restano nelle preferenze; il
/// valore generato no (SEC-03).
final generatorViewModelProvider =
    NotifierProvider.autoDispose<GeneratorViewModel, GeneratorState>(
      GeneratorViewModel.new,
    );

class GeneratorViewModel extends Notifier<GeneratorState> {
  /// Chiave delle preferenze con le ultime opzioni usate.
  static const storageKey = 'generator_last_options';

  /// Chiave delle preferenze con i profili salvati dall'utente.
  static const profilesKey = 'generator_profiles';

  @override
  GeneratorState build() => _generate(_load(), _loadProfiles());

  /// Applica nuove opzioni, genera un nuovo valore e le ricorda.
  void update(GeneratorOptions options) {
    state = _generate(options, state.customProfiles);
    ref
        .read(sharedPreferencesProvider)
        .setString(storageKey, jsonEncode(options.toJson()));
  }

  /// Applica il profilo [name], salvato dall'utente o predefinito.
  void applyProfile(String name) {
    final profile = state.customProfiles[name] ?? generatorProfiles[name];
    if (profile != null) update(profile);
  }

  /// Genera un nuovo valore con le stesse opzioni.
  void regenerate() => state = _generate(state.options, state.customProfiles);

  /// Salva le opzioni correnti come profilo [name]; un profilo dell'utente con
  /// lo stesso nome viene sostituito. `false` se il nome è vuoto o è quello di
  /// un profilo predefinito.
  bool saveProfile(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || generatorProfiles.containsKey(trimmed)) {
      return false;
    }
    _setProfiles({...state.customProfiles, trimmed: state.options});
    return true;
  }

  /// Rimuove il profilo dell'utente [name].
  void removeProfile(String name) =>
      _setProfiles({...state.customProfiles}..remove(name));

  void _setProfiles(Map<String, GeneratorOptions> profiles) {
    state = GeneratorState(
      options: state.options,
      value: state.value,
      customProfiles: Map.unmodifiable(profiles),
    );
    ref
        .read(sharedPreferencesProvider)
        .setString(
          profilesKey,
          jsonEncode({
            for (final MapEntry(:key, :value) in profiles.entries)
              key: value.toJson(),
          }),
        );
  }

  Map<String, GeneratorOptions> _loadProfiles() {
    final raw = ref.read(sharedPreferencesProvider).getString(profilesKey);
    if (raw == null) return const {};
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return const {};
      return Map.unmodifiable({
        for (final MapEntry(:key, :value) in json.entries)
          if (value is Map<String, Object?>)
            key: GeneratorOptions.fromJson(value),
      });
    } on FormatException {
      return const {};
    }
  }

  GeneratorOptions _load() {
    final raw = ref.read(sharedPreferencesProvider).getString(storageKey);
    if (raw == null) return defaultGeneratorOptions;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) return GeneratorOptions.fromJson(json);
    } on FormatException {
      // Preferenza illeggibile: si riparte dalle opzioni predefinite.
    }
    return defaultGeneratorOptions;
  }

  static GeneratorState _generate(
    GeneratorOptions options,
    Map<String, GeneratorOptions> customProfiles,
  ) => GeneratorState(
    options: options,
    value: options.isValid ? generateSecret(options) : '',
    customProfiles: customProfiles,
  );
}

/// Nome del profilo che corrisponde alle opzioni, se c'è. I profili
/// dell'utente ([custom]) hanno la precedenza: uno appena salvato con le
/// stesse opzioni di un predefinito resta selezionato e si può rimuovere.
String? matchingProfile(
  GeneratorOptions options, {
  Map<String, GeneratorOptions> custom = const {},
}) {
  for (final profiles in [custom, generatorProfiles]) {
    for (final MapEntry(:key, :value) in profiles.entries) {
      if (value == options) return key;
    }
  }
  return null;
}
