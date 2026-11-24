import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// Colori delle voci distinguibili sulle superfici chiare e scure dell'app.
enum EntryColor {
  red('#D64550'),
  orange('#BC6500'),
  yellow('#997D00'),
  green('#39854A'),
  teal('#008577'),
  blue('#4D70D8'),
  purple('#8264CA'),
  pink('#B84F97'),
  brown('#986C4A'),
  gray('#747A83');

  const EntryColor(this.hex);

  /// Valore KDBX canonico nel formato `#RRGGBB`.
  final String hex;

  /// Colore opaco condiviso da liste, dettaglio e selettore.
  Color get color => Color(0xff000000 | int.parse(hex.substring(1), radix: 16));

  /// Nome del colore nella lingua dell'interfaccia.
  String label(AppLocalizations l10n) => switch (this) {
    red => l10n.entryColorRed,
    orange => l10n.entryColorOrange,
    yellow => l10n.entryColorYellow,
    green => l10n.entryColorGreen,
    teal => l10n.entryColorTeal,
    blue => l10n.entryColorBlue,
    purple => l10n.entryColorPurple,
    pink => l10n.entryColorPink,
    brown => l10n.entryColorBrown,
    gray => l10n.entryColorGray,
  };
}

final _kdbxColorPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

/// Adatta un colore KDBX alla palette senza modificarne il valore originale.
///
/// Restituisce `null` per valori assenti o diversi da `#RRGGBB`. La distanza
/// privilegia la tonalità; la saturazione HSL mantiene cromatici anche i
/// pastelli molto chiari. I colori quasi acromatici usano il grigio.
EntryColor? adaptEntryColor(String? value) {
  if (value == null || !_kdbxColorPattern.hasMatch(value)) return null;
  final canonical = value.toUpperCase();
  for (final preset in EntryColor.values) {
    if (preset.hex == canonical) return preset;
  }
  final source = HSLColor.fromColor(
    Color(0xff000000 | int.parse(value.substring(1), radix: 16)),
  );
  if (source.saturation < .1) return EntryColor.gray;

  EntryColor? closest;
  var minimum = double.infinity;
  for (final preset in EntryColor.values) {
    if (preset == EntryColor.gray) continue;
    final target = HSLColor.fromColor(preset.color);
    final difference = (source.hue - target.hue).abs();
    final hue = (difference > 180 ? 360 - difference : difference) / 180;
    final saturation = source.saturation - target.saturation;
    final lightness = source.lightness - target.lightness;
    final distance =
        4 * hue * hue +
        .15 * saturation * saturation +
        .1 * lightness * lightness;
    if (distance < minimum) {
      closest = preset;
      minimum = distance;
    }
  }
  return closest;
}
