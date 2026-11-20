import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/password_generator/generator_view_model.dart';
import 'package:keepass_mobile/features/password_generator/password_generator.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';

import '../../helpers/test_database.dart';

void main() {
  test('opzioni predefinite di Keepass2Android senza preferenze', () async {
    final container = await newTestContainer();
    final state = container.read(generatorViewModelProvider);
    expect(state.options, defaultGeneratorOptions);
    expect(state.value, hasLength(12));
  });

  test('profilo applicato, valore rigenerato e opzioni ricordate', () async {
    final container = await newTestContainer();
    container.listen(generatorViewModelProvider, (_, _) {});
    final viewModel = container.read(generatorViewModelProvider.notifier);

    viewModel.applyProfile('Passphrase7');
    final first = container.read(generatorViewModelProvider);
    expect(first.value.split(' '), hasLength(7));
    expect(matchingProfile(first.options), 'Passphrase7');

    viewModel.regenerate();
    expect(
      container.read(generatorViewModelProvider).value,
      isNot(first.value),
    );

    final saved = container
        .read(sharedPreferencesProvider)
        .getString(GeneratorViewModel.storageKey);
    expect(
      GeneratorOptions.fromJson(jsonDecode(saved!) as Map<String, Object?>),
      generatorProfiles['Passphrase7'],
    );
    // Il valore generato non viene mai salvato.
    expect(saved.contains(first.value), isFalse);
  });

  test('opzioni non valide: nessun valore', () async {
    final container = await newTestContainer();
    container.listen(generatorViewModelProvider, (_, _) {});
    container
        .read(generatorViewModelProvider.notifier)
        .update(const GeneratorOptions());
    final state = container.read(generatorViewModelProvider);
    expect(state.isValid, isFalse);
    expect(state.value, isEmpty);
  });

  test(
    'profili dell\'utente: salvati, riapplicati, ricordati e rimossi',
    () async {
      final container = await newTestContainer();
      container.listen(generatorViewModelProvider, (_, _) {});
      final viewModel = container.read(generatorViewModelProvider.notifier);
      viewModel.applyProfile('Passphrase7');
      viewModel.update(
        container
            .read(generatorViewModelProvider)
            .options
            .copyWith(passphrase: const PassphraseOptions(wordCount: 4)),
      );
      final mine = container.read(generatorViewModelProvider).options;

      expect(viewModel.saveProfile(' Mio '), isTrue);
      viewModel.applyProfile('Simple12');
      viewModel.applyProfile('Mio');

      expect(container.read(generatorViewModelProvider).options, mine);
      expect(
        matchingProfile(
          mine,
          custom: container.read(generatorViewModelProvider).customProfiles,
        ),
        'Mio',
      );
      // Riletti dalle preferenze da un generatore nuovo.
      container.invalidate(generatorViewModelProvider);
      expect(
        container.read(generatorViewModelProvider).customProfiles['Mio'],
        mine,
      );

      viewModel.removeProfile('Mio');
      expect(
        container.read(generatorViewModelProvider.notifier).saveProfile(''),
        isFalse,
      );
      container.read(generatorViewModelProvider.notifier).removeProfile('Mio');
      expect(
        container.read(generatorViewModelProvider).customProfiles,
        isEmpty,
      );
    },
  );

  test('profilo dell\'utente uguale a un predefinito: ha la precedenza', () {
    final same = generatorProfiles['Passphrase5Plus']!;

    expect(matchingProfile(same), 'Passphrase5Plus');
    expect(matchingProfile(same, custom: {'Mio': same}), 'Mio');
  });

  test('nome di un profilo predefinito: rifiutato', () async {
    final container = await newTestContainer();
    container.listen(generatorViewModelProvider, (_, _) {});

    final saved = container
        .read(generatorViewModelProvider.notifier)
        .saveProfile('Simple12');

    expect(saved, isFalse);
    expect(container.read(generatorViewModelProvider).customProfiles, isEmpty);
  });
}
