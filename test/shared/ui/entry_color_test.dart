import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/shared/ui/entry_color.dart';

double contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  test('i preset restano identici anche con esadecimali minuscoli', () {
    for (final preset in EntryColor.values) {
      expect(adaptEntryColor(preset.hex), preset);
      expect(adaptEntryColor(preset.hex.toLowerCase()), preset);
    }
  });

  test('solo i valori KDBX esadecimali completi producono un colore', () {
    for (final value in <String?>[
      null,
      '',
      '#123',
      '112233',
      '#11223344',
      '!#123456',
      '#12345g',
      ' #123456',
      '#123456\n',
    ]) {
      expect(adaptEntryColor(value), isNull, reason: '$value');
    }
  });

  test('tonalità e saturazione distinguono pastelli, neutri e marroni', () {
    const examples = {
      '#CCFFCC': EntryColor.green,
      '#F0FFF0': EntryColor.green,
      '#FFF0F0': EntryColor.red,
      '#FFDAB9': EntryColor.orange,
      '#FFFFCC': EntryColor.yellow,
      '#CCFFFF': EntryColor.teal,
      '#CCE5FF': EntryColor.blue,
      '#0000FF': EntryColor.blue,
      '#F0F0FF': EntryColor.blue,
      '#E5CCFF': EntryColor.purple,
      '#FFCCEE': EntryColor.pink,
      '#D2B48C': EntryColor.brown,
      '#A52A2A': EntryColor.red,
      '#FFFFFF': EntryColor.gray,
      '#000000': EntryColor.gray,
      '#808080': EntryColor.gray,
      '#7F8081': EntryColor.gray,
    };
    for (final example in examples.entries) {
      expect(adaptEntryColor(example.key), example.value, reason: example.key);
    }
  });

  test('palette con contrasto almeno 3:1 su temi e riquadri recenti', () {
    for (final theme in [buildLightTheme(), buildDarkTheme()]) {
      final surface = theme.colorScheme.surface;
      final recent = Color.alphaBlend(
        theme.colorScheme.primary.withValues(
          alpha: AppSectionLayout.backgroundOpacity,
        ),
        surface,
      );
      for (final preset in EntryColor.values) {
        for (final background in [surface, recent]) {
          expect(
            contrast(preset.color, background),
            greaterThanOrEqualTo(3),
            reason: '${preset.name}, ${theme.brightness}',
          );
        }
      }
    }
  });
}
