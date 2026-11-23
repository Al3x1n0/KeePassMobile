import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';

/// Apre il menu delle azioni della Home.
Future<void> openHomeMenu(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.byTooltip(l10n.groupMore));
  await tester.pumpAndSettle();
}

/// Seleziona un'azione dal menu della Home tramite la sua etichetta.
Future<void> selectHomeAction(
  WidgetTester tester,
  AppLocalizations l10n,
  String label,
) async {
  await openHomeMenu(tester, l10n);
  await tester.tap(find.text(label));
}
