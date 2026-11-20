import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Dimensione in byte leggibile (B, KiB, MiB) nel formato della lingua.
String formatBytes(BuildContext context, int bytes) {
  if (bytes < 1024) return '$bytes B';
  final number = NumberFormat.decimalPatternDigits(
    locale: Localizations.localeOf(context).toString(),
    decimalDigits: 1,
  );
  if (bytes < 1024 * 1024) return '${number.format(bytes / 1024)} KiB';
  return '${number.format(bytes / (1024 * 1024))} MiB';
}
