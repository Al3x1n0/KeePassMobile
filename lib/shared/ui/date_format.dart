import 'package:material_ui/material_ui.dart';

/// Data e ora nel formato della lingua dell'app (scadenza, cronologia).
String formatDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final ml = MaterialLocalizations.of(context);
  final time = ml.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '${ml.formatShortDate(local)} $time';
}
