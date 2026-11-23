import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/features/entry/totp_tile.dart';
import 'package:keepass_mobile/features/totp/totp.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'copia il TOTP valido al tap e il pulsante occhio rivela soltanto',
    (tester) async {
      // given
      const locale = Locale('it');
      final l10n = lookupAppLocalizations(locale);
      var now = DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true);
      final config = parseTotp({
        'otp': 'otpauth://totp/prova?secret=JBSWY3DPEHPK3PXP',
      })!;
      final copied = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [totpClockProvider.overrideWithValue(() => now)],
          child: MaterialApp(
            locale: locale,
            localizationsDelegates: [
              ...GlobalMaterialLocalizations.delegates,
              ...AppLocalizations.localizationsDelegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: TotpTile(config: config, onCopy: copied.add),
            ),
          ),
        ),
      );
      expect(find.text(config.codeAt(now)), findsNothing);
      expect(find.byIcon(Icons.copy), findsNothing);

      // when: il periodo cambia prima del prossimo frame.
      now = DateTime.fromMillisecondsSinceEpoch(60000, isUtc: true);
      await tester.tapAt(
        tester.getTopLeft(find.byType(ListTile)) + const Offset(4, 20),
      );

      // then
      expect(copied, [config.codeAt(now)]);
      await tester.tap(find.byTooltip(l10n.entryShow));
      await tester.pump();
      expect(find.text(config.codeAt(now)), findsOneWidget);
      expect(copied, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
