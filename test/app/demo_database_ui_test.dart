import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/theme.dart';
import 'package:keepass_mobile/features/autofill/autofill_file_select_view.dart';
import 'package:keepass_mobile/features/file_select/demo_database.dart';
import 'package:keepass_mobile/features/file_select/file_select_view.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/features/settings/settings_view.dart';
import 'package:keepass_mobile/features/unlock/unlock_view.dart';
import 'package:keepass_mobile/features/unlock/unlock_view_model.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/security/biometric_key_store.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sameName = FileRef(
  uri: 'file:///utente/Rifugio-Aurora.kdbx',
  name: 'Rifugio-Aurora.kdbx',
);

class _Storage extends FileStorage {
  final deletions = <bool>[];

  @override
  Future<void> deleteDemoDatabase({bool keepFile = false}) async {
    deletions.add(keepFile);
  }

  @override
  Future<void> release(FileRef ref) async {}
}

class _Biometrics extends BiometricKeyStore {
  _Biometrics(super.prefs);

  final removed = <FileRef>[];
  int cleared = 0;

  @override
  Future<void> remove(FileRef file) async => removed.add(file);

  @override
  Future<void> removeAll() async => cleared++;
}

class _Harness {
  _Harness(this.container, this.storage, this.biometrics);

  final ProviderContainer container;
  final _Storage storage;
  final _Biometrics biometrics;

  List<RecentFile> get recent =>
      container.read(recentFilesRepositoryProvider).load();
}

Future<_Harness> _pump(
  WidgetTester tester,
  Widget home, {
  required Locale locale,
  bool withDemo = true,
}) async {
  tester.view.physicalSize = const Size(800, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    DemoDatabaseRepository.stateKey: withDemo ? 'ready' : 'removed',
    RecentFilesRepository.storageKey: [
      if (withDemo)
        jsonEncode(
          const RecentFile(database: DemoDatabaseRepository.file).toJson(),
        ),
      jsonEncode(const RecentFile(database: _sameName).toJson()),
    ],
  });
  final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
  final storage = _Storage();
  final biometrics = _Biometrics(prefs);
  final container = ProviderContainer.test(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      fileStorageProvider.overrideWithValue(storage),
      biometricKeyStoreProvider.overrideWithValue(biometrics),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        theme: buildLightTheme(),
        localizationsDelegates: [
          ...GlobalMaterialLocalizations.delegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(container, storage, biometrics);
}

void main() {
  for (final locale in [const Locale('it'), const Locale('en')]) {
    final l10n = lookupAppLocalizations(locale);
    testWidgets(
      '${locale.languageCode}: X demo annulla e conferma la rimozione',
      (tester) async {
        // given: un file utente omonimo non è il database preinstallato.
        final harness = await _pump(
          tester,
          const FileSelectView(),
          locale: locale,
        );
        expect(find.text(l10n.demoDatabaseSubtitle), findsOneWidget);
        expect(find.byType(ListTile), findsNWidgets(2));
        final remove = find.byTooltip(l10n.fileSelectRemove);

        // when / then: annullare conserva recenti, file e biometria.
        await tester.tap(remove.first);
        await tester.pumpAndSettle();
        expect(find.text(l10n.demoDatabaseRemoveTitle), findsOneWidget);
        expect(find.text(l10n.demoDatabaseRemoveMessage), findsOneWidget);
        await tester.tap(find.text(l10n.cancel));
        await tester.pumpAndSettle();
        expect(harness.recent, hasLength(2));
        expect(harness.storage.deletions, isEmpty);
        expect(harness.biometrics.removed, isEmpty);

        // when / then: la conferma toglie solo la demo.
        await tester.tap(remove.first);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.demoDatabaseRemoveConfirm));
        await tester.pumpAndSettle();
        expect(harness.recent.single.database, _sameName);
        expect(
          harness.container.read(demoDatabaseRepositoryProvider).isRemoved,
          isTrue,
        );
        expect(harness.storage.deletions, isNotEmpty);
        expect(
          harness.biometrics.removed,
          contains(DemoDatabaseRepository.file),
        );
        expect(find.text(l10n.demoDatabaseSubtitle), findsNothing);

        // Il file utente omonimo continua a essere rimosso immediatamente.
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(harness.recent, isEmpty);
        expect(find.text(l10n.fileSelectNoRecent), findsOneWidget);
        expect(find.byType(ListTile), findsNothing);
      },
    );

    testWidgets('${locale.languageCode}: impostazioni annulla poi conferma', (
      tester,
    ) async {
      final harness = await _pump(tester, const SettingsView(), locale: locale);
      final toggle = find.widgetWithText(
        SwitchListTile,
        l10n.settingsRememberRecentFiles,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text(l10n.demoDatabaseRemoveWithRecents), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      expect(harness.recent, hasLength(2));
      expect(harness.storage.deletions, isEmpty);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.demoDatabaseRemoveConfirm));
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(
        harness.container.read(appSettingsProvider).rememberRecentFiles,
        isFalse,
      );
      expect(harness.recent, isEmpty);
      expect(harness.storage.deletions, isNotEmpty);
      expect(harness.biometrics.cleared, 1);
    });

    testWidgets(
      '${locale.languageCode}: recenti senza demo disattivati subito',
      (tester) async {
        final harness = await _pump(
          tester,
          const SettingsView(),
          locale: locale,
          withDemo: false,
        );
        await tester.tap(find.text(l10n.settingsRememberRecentFiles));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          harness.container.read(appSettingsProvider).rememberRecentFiles,
          isFalse,
        );
        expect(harness.recent, isEmpty);
      },
    );

    for (final screen in [
      const FileSelectView(additional: true),
      const AutofillFileSelectView(),
    ]) {
      testWidgets(
        '${locale.languageCode}: ${screen.runtimeType} riconosce il riferimento demo',
        (tester) async {
          await _pump(tester, screen, locale: locale);
          expect(find.text(l10n.demoDatabaseSubtitle), findsOneWidget);
          expect(find.byTooltip(l10n.fileSelectRemove), findsNothing);
        },
      );
    }

    for (final selected in [DemoDatabaseRepository.file, _sameName]) {
      testWidgets(
        '${locale.languageCode}: password demo solo per ${selected.uri}',
        (tester) async {
          await _pump(
            tester,
            UnlockView(
              args: UnlockArgs(database: PickedFile(ref: selected)),
            ),
            locale: locale,
          );
          expect(
            find.text(l10n.demoDatabasePassword),
            selected == DemoDatabaseRepository.file
                ? findsOneWidget
                : findsNothing,
          );
        },
      );
    }
  }
}
