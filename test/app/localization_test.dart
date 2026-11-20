import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/features/device_blocked/device_blocked_view.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'Italian and English resources have the same messages and parameters',
    () {
      Map<String, dynamic> read(String language) =>
          jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
              as Map<String, dynamic>;

      final english = read('en');
      final italian = read('it');
      final keys = english.keys.where((key) => !key.startsWith('@')).toSet();
      expect(italian.keys.where((key) => !key.startsWith('@')).toSet(), keys);
      final parameters = RegExp(r'\{\s*(\w+)\s*[,}]');
      Set<String?> names(String value) =>
          parameters.allMatches(value).map((match) => match.group(1)).toSet();
      for (final key in keys) {
        expect(italian[key], isA<String>(), reason: key);
        expect((italian[key] as String).trim(), isNotEmpty, reason: key);
        expect(
          names(italian[key] as String),
          names(english[key] as String),
          reason: key,
        );
      }
    },
  );

  test('Plural messages format singular and plural in both languages', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final it = lookupAppLocalizations(const Locale('it'));
    expect(en.settingsSeconds(1), '1 second');
    expect(en.settingsSeconds(2), '2 seconds');
    expect(it.settingsSeconds(1), '1 secondo');
    expect(it.settingsSeconds(2), '2 secondi');
    expect(en.settingsMinutes(2), '2 minutes');
    expect(it.settingsMinutes(2), '2 minuti');
    expect(en.entryCopied(2), contains('2 seconds'));
    expect(it.entryCopied(2), contains('2 secondi'));
  });

  for (final (requested, expected) in [
    (const Locale('it', 'CH'), const Locale('it')),
    (const Locale('en', 'GB'), const Locale('en')),
    (const Locale('fr'), const Locale('en')),
  ]) {
    testWidgets('Locale $requested resolves to $expected', (tester) async {
      Locale? resolved;
      await tester.pumpWidget(
        MaterialApp(
          locale: requested,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            ...GlobalMaterialLocalizations.delegates,
            ...AppLocalizations.localizationsDelegates,
          ],
          home: Builder(
            builder: (context) {
              resolved = Localizations.localeOf(context);
              return const DeviceBlockedView();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(resolved, expected);
      expect(
        find.text(lookupAppLocalizations(expected).deviceBlockedTitle),
        findsOneWidget,
      );
    });
  }

  for (final locale in [const Locale('en'), const Locale('it')]) {
    testWidgets('Blocked screen renders at large text size in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            ...GlobalMaterialLocalizations.delegates,
            ...AppLocalizations.localizationsDelegates,
          ],
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const DeviceBlockedView(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(lookupAppLocalizations(locale).deviceBlockedTitle),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final locale in [const Locale('en'), const Locale('it')]) {
    testWidgets('File selection renders with large text in $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.localesTestValue = [locale];
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({
        RecentFilesRepository.storageKey: [
          jsonEncode(
            const RecentFile(
              database: FileRef(
                uri: 'file:///synthetic.kdbx',
                name: 'synthetic.kdbx',
              ),
            ).toJson(),
          ),
        ],
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const KeePassMobileApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(lookupAppLocalizations(locale).fileSelectTitle),
        findsOneWidget,
      );
      await tester.tap(find.text('synthetic.kdbx'));
      await tester.pumpAndSettle();
      expect(
        find.text(lookupAppLocalizations(locale).unlockPassword),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
