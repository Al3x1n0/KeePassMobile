import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jailbreak_root_detection/jailbreak_root_detection.dart';
import 'package:keepass_mobile/app/app.dart';
import 'package:keepass_mobile/app/device_integrity.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

/// Controlli simulati: [result] o, se `null`, un errore del plugin.
class _FakeIntegrity extends DeviceIntegrity {
  _FakeIntegrity(this.result, {super.enforce = true, super.deviceTest})
    : super();

  Set<IntegrityProblem>? result;
  int probes = 0;

  @override
  Future<Set<IntegrityProblem>> probe() async {
    probes++;
    return result ?? (throw StateError('plugin'));
  }
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  group('DeviceIntegrity', () {
    test('release, dispositivo pulito: nessun problema', () async {
      expect(await _FakeIntegrity({}).check(), isEmpty);
    });

    test(
      'release: mantiene il root con opzioni sviluppatore e debug USB',
      () async {
        final integrity = _FakeIntegrity({
          IntegrityProblem.jailbreak,
          IntegrityProblem.debugged,
          IntegrityProblem.devMode,
        });

        expect(await integrity.check(), {IntegrityProblem.jailbreak});
      },
    );

    test('release di prova: salta il debugger', () async {
      final integrity = _FakeIntegrity({
        IntegrityProblem.devMode,
        IntegrityProblem.debugged,
        IntegrityProblem.jailbreak,
      }, deviceTest: true);

      expect(await integrity.check(), {IntegrityProblem.jailbreak});
      expect(
        await _FakeIntegrity({
          IntegrityProblem.devMode,
          IntegrityProblem.debugged,
        }, deviceTest: true).check(),
        isEmpty,
      );
    });

    test('release: opzioni sviluppatore e debug USB non bloccano', () async {
      expect(
        await _FakeIntegrity({
          IntegrityProblem.devMode,
          IntegrityProblem.debugged,
        }).check(),
        isEmpty,
      );
    });

    for (final problem in IntegrityProblem.values) {
      if (allowedIntegrityProblems.contains(problem)) continue;
      test('release: mantiene il blocco per $problem', () async {
        expect(
          await _FakeIntegrity({IntegrityProblem.devMode, problem}).check(),
          {problem},
        );
      });
    }

    test('release di prova: un errore del controllo blocca comunque', () async {
      expect(await _FakeIntegrity(null, deviceTest: true).check(), {
        IntegrityProblem.checkFailed,
      });
    });

    test('errore del controllo: conta come problema', () async {
      expect(await _FakeIntegrity(null).check(), {
        IntegrityProblem.checkFailed,
      });
    });

    test('debug e profile: nessun controllo', () async {
      final integrity = _FakeIntegrity({
        IntegrityProblem.jailbreak,
      }, enforce: false);

      expect(await integrity.check(), isEmpty);
      expect(integrity.probes, 0);
    });

    test('predefinito: controlli solo in release, release di prova spenta', () {
      expect(const DeviceIntegrity().enforce, kReleaseMode);
      expect(const DeviceIntegrity().deviceTest, isFalse);
    });

    test('ogni risultato della libreria diventa un problema', () {
      expect(problemOf(JailbreakIssue.fridaFound), IntegrityProblem.jailbreak);
      expect(problemOf(JailbreakIssue.cydiaFound), IntegrityProblem.jailbreak);
      expect(problemOf(JailbreakIssue.devMode), IntegrityProblem.devMode);
      expect(problemOf(JailbreakIssue.proxied), IntegrityProblem.other);
      expect(problemOf(JailbreakIssue.unknown), IntegrityProblem.other);
      for (final issue in JailbreakIssue.values) {
        expect(problemOf(issue), isA<IntegrityProblem>());
      }
    });
  });

  group('IntegrityStatusNotifier', () {
    test(
      'problema al ritorno in primo piano: database chiuso, app bloccata',
      () async {
        FakeClipboard(TestDefaultBinaryMessengerBinding.instance);
        final fake = _FakeIntegrity({});
        final container = await newTestContainer(
          overrides: [deviceIntegrityProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);
        container.listen(integrityStatusProvider, (_, _) {});
        await pumpEventQueue();
        expect(
          container.read(integrityStatusProvider),
          IntegrityStatus.trusted,
        );
        container
            .read(databaseSessionProvider.notifier)
            .open(
              DatabaseSession(
                file: const FileRef(uri: 'content://docs/a', name: 'a.kdbx'),
                database: newTestDatabase(),
              ),
            );

        fake.result = {IntegrityProblem.jailbreak};
        await container.read(integrityStatusProvider.notifier).recheck();

        expect(container.read(databaseSessionProvider), isNull);
        expect(
          container.read(integrityStatusProvider),
          IntegrityStatus.compromised,
        );
      },
    );

    test('bloccata resta bloccata fino al riavvio', () async {
      final fake = _FakeIntegrity({IntegrityProblem.jailbreak});
      final container = await newTestContainer(
        overrides: [deviceIntegrityProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);
      container.listen(integrityStatusProvider, (_, _) {});
      await pumpEventQueue();

      fake.result = {};
      await container.read(integrityStatusProvider.notifier).recheck();

      expect(
        container.read(integrityStatusProvider),
        IntegrityStatus.compromised,
      );
    });
  });

  testWidgets('dispositivo con root: solo la schermata di blocco', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          deviceIntegrityProvider.overrideWithValue(
            _FakeIntegrity({IntegrityProblem.jailbreak}),
          ),
        ],
        child: const KeePassMobileApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.deviceBlockedTitle), findsOneWidget);
    expect(find.text(l10n.deviceBlockedBody), findsOneWidget);
    expect(find.text(l10n.fileSelectTitle), findsNothing);
    expect(find.byType(IconButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });
}
