import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kpasslib/kpasslib.dart';

import '../../shared/clipboard/clipboard_service.dart';
import '../../shared/database/database_session.dart';
import '../../shared/storage/preferences.dart';
import '../../shared/storage/file_storage.dart';
import 'pending_generated_password.dart';
import 'password_generator.dart';

/// Stato del generatore: opzioni correnti e valore generato.
@immutable
class GeneratorState {
  GeneratorState({
    required this.options,
    required String value,
    this.customProfiles = const {},
  }) : _protectedValue = ProtectedData.fromString(value),
       _hasValue = value.isNotEmpty;

  final GeneratorOptions options;

  /// Profili salvati dall'utente (PasswordProfiles di Keepass2Android).
  final Map<String, GeneratorOptions> customProfiles;

  /// Valore generato; vuoto se le opzioni non sono valide.
  final ProtectedData _protectedValue;
  final bool _hasValue;

  String get value => _hasValue ? _protectedValue.text : '';

  bool get isValid => options.isValid && _hasValue;

  double get entropyBits => generationEntropyBits(options);
}

/// Generatore di password e passphrase (GeneratePasswordActivity di
/// Keepass2Android). Le ultime opzioni usate restano nelle preferenze; il
/// valore generato no (SEC-03).
final generatorViewModelProvider =
    NotifierProvider.autoDispose<GeneratorViewModel, GeneratorState>(
      GeneratorViewModel.new,
    );

/// Generatore della tab, distinto dal selettore aperto durante la modifica.
final tabGeneratorViewModelProvider =
    NotifierProvider.autoDispose<GeneratorViewModel, GeneratorState>(
      () => GeneratorViewModel(dedicatedTab: true),
    );

class GeneratorViewModel extends Notifier<GeneratorState> {
  GeneratorViewModel({this.dedicatedTab = false});

  final bool dedicatedTab;
  FileRef? _file;

  /// Chiave delle preferenze con le ultime opzioni usate.
  static const storageKey = 'generator_last_options';

  /// Chiave delle preferenze con i profili salvati dall'utente.
  static const profilesKey = 'generator_profiles';

  @override
  GeneratorState build() {
    final file = dedicatedTab
        ? ref.watch(databaseSessionProvider.select((session) => session?.file))
        : null;
    _file = file;
    final pending = dedicatedTab
        ? ref.read(pendingGeneratedPasswordProvider)
        : null;
    final initial = dedicatedTab && file == null
        ? GeneratorState(options: _load(), value: '')
        : pending != null && pending.file == file
        ? GeneratorState(
            options: pending.options,
            value: pending.protectedValue.text,
            customProfiles: _loadProfiles(),
          )
        : _generate(_load(), _loadProfiles());
    var current = initial;
    listenSelf((_, next) => current = next);
    ref.onDispose(() => current._protectedValue.clear());
    if (dedicatedTab && file != null && pending == null) {
      // La prima generazione viene custodita dopo l'inizializzazione dei provider.
      Future.microtask(() {
        if (ref.mounted &&
            ref.read(databaseSessionProvider)?.file == file &&
            identical(state, initial)) {
          _remember();
        }
      });
    }
    return initial;
  }

  void _remember() {
    if (!dedicatedTab) return;
    final file = ref.read(databaseSessionProvider)?.file;
    if (file == null || file != _file) return;
    ref
        .read(pendingGeneratedPasswordProvider.notifier)
        .replace(file, state.options, state.value);
  }

  void _replace(GeneratorState next) {
    final previous = state;
    state = next;
    previous._protectedValue.clear();
    _remember();
  }

  /// Rilascia il valore salvato senza generarne subito un altro in sospeso.
  void clearGeneratedValue() {
    final previous = state;
    state = GeneratorState(
      options: previous.options,
      value: '',
      customProfiles: previous.customProfiles,
    );
    previous._protectedValue.clear();
  }

  /// Copia con il timeout configurato e restituisce la durata per il feedback.
  Future<Duration?> copy() async {
    if (!state.isValid) return null;
    final clipboard = ref.read(clipboardServiceProvider);
    final timeout = clipboard.clearAfter;
    await clipboard.copy(state.value, generated: dedicatedTab);
    return timeout;
  }

  /// Applica nuove opzioni, genera un nuovo valore e le ricorda.
  void update(GeneratorOptions options) {
    _replace(_generate(options, state.customProfiles));
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
  void regenerate() => _replace(_generate(state.options, state.customProfiles));

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
    final previous = state;
    state = GeneratorState(
      options: state.options,
      value: state.value,
      customProfiles: Map.unmodifiable(profiles),
    );
    previous._protectedValue.clear();
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
