import 'package:material_ui/material_ui.dart';

/// Mostra subito il feedback più recente senza accodare messaggi precedenti.
extension AppSnackBarMessenger on ScaffoldMessengerState {
  /// Sostituisce il messaggio corrente e svuota eventuali notifiche in attesa.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
    SnackBar snackBar,
  ) {
    clearSnackBars();
    removeCurrentSnackBar();
    return showSnackBar(snackBar);
  }
}
