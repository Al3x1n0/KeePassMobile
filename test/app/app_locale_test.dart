import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/app/device_integrity.dart';
import 'package:keepass_mobile/features/autofill/autofill_app.dart';
import 'package:keepass_mobile/features/autofill/autofill_channel.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';

import 'package:keepass_mobile/shared/storage/preferences.dart';

class _Integrity extends IntegrityStatusNotifier {
  _Integrity(this.status);
  final IntegrityStatus status;
  @override
  IntegrityStatus build() => status;
}

void main() {
  for (final autofill in [false, true]) {
    for (final blocked in [false, true]) {
      testWidgets('${autofill ? "Autofill" : "App"} locale, blocked=$blocked', (
        tester,
      ) async {
        // given
        tester.binding.platformDispatcher.localesTestValue = [
          const Locale('ro'),
        ];
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        SharedPreferences.setMockInitialValues({
          'settings.language_code': 'it',
        });
        final prefs = await SharedPreferences.getInstance();
        final scope = ProviderContainer(
          overrides: [
            if (autofill)
              ...autofillOverrides(
                prefs,
                const AutofillRequest(packageName: 'com.example.app'),
              )
            else
              sharedPreferencesProvider.overrideWithValue(prefs),
            integrityStatusProvider.overrideWith(
              () => _Integrity(
                blocked ? IntegrityStatus.compromised : IntegrityStatus.trusted,
              ),
            ),
          ],
        );
        addTearDown(scope.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: scope,
            child: autofill ? const AutofillApp() : const KeePassMobileApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
          const Locale('it'),
        );
        // when / then: persisted override, manual switch, return to system.
        for (final code in ['it', 'en', null]) {
          await scope
              .read(appSettingsProvider.notifier)
              .update(
                scope.read(appSettingsProvider).copyWith(languageCode: code),
              );
          await tester.pumpAndSettle();
          final materialApp = tester.widget<MaterialApp>(
            find.byType(MaterialApp),
          );
          expect(materialApp.locale, Locale(code ?? 'en'));
          final context = tester.element(find.byType(Scaffold).first);
          expect(AppLocalizations.of(context).localeName, code ?? 'en');
        }
        tester.binding.platformDispatcher.localesTestValue = [
          const Locale('it', 'CH'),
        ];
        await tester.pumpAndSettle();
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
          const Locale('it'),
        );
        tester.binding.platformDispatcher.localesTestValue = [
          const Locale('ro'),
        ];
        await tester.pumpAndSettle();
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
          const Locale('en'),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
