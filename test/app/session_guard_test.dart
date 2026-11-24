import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/screen_protection.dart';
import 'package:keepass_mobile/app/session_guard.dart';
import 'package:keepass_mobile/features/file_select/recent_files.dart';
import 'package:keepass_mobile/features/unlock/relock.dart';
import 'package:keepass_mobile/shared/database/database_session.dart';
import 'package:keepass_mobile/shared/security/device_security.dart';
import 'package:keepass_mobile/shared/security/external_activity.dart';
import 'package:keepass_mobile/shared/settings/app_settings.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:keepass_mobile/shared/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_app_security.dart';
import '../helpers/test_database.dart';

class _FakeProtection extends ScreenProtection {
  final applied = <bool>[];

  @override
  Future<bool> apply({required bool enabled}) async {
    applied.add(enabled);
    return true;
  }
}

class _RecordingStorage extends FileStorage {
  final released = <FileRef>[];

  @override
  Future<void> release(FileRef ref) async => released.add(ref);
}

final _containers = <ProviderContainer>[];

void main() {
  const database = FileRef(uri: 'content://docs/a', name: 'a.kdbx');
  const keyFile = FileRef(uri: 'content://docs/a.key', name: 'a.key');
  late DateTime now;
  late _FakeProtection protection;
  late FakeAppSecurity security;
  late _RecordingStorage storage;

  Future<ProviderContainer> start(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(),
    bool notificationAllowed = true,
  }) async {
    FakeClipboard(tester.binding);
    now = DateTime(2026, 11, 4, 12);
    protection = _FakeProtection();
    security = FakeAppSecurity();
    storage = _RecordingStorage();
    SharedPreferences.setMockInitialValues({});
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    await tester.runAsync(() => AppSettingsRepository(prefs).save(settings));
    // Container chiuso alla fine del corpo del test: il timer di inattività
    // va annullato prima del controllo dei timer di flutter_test.
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        sessionClockProvider.overrideWithValue(() => now),
        screenProtectionProvider.overrideWithValue(protection),
        appSecurityProvider.overrideWithValue(security),
        fileStorageProvider.overrideWithValue(storage),
        openNotificationAllowedProvider.overrideWithValue(notificationAllowed),
      ],
    );
    container.read(sessionGuardProvider);
    _containers.add(container);
    return container;
  }

  /// Esegue [body] e chiude il container prima dei controlli di flutter_test.
  void guardTest(
    String description,
    Future<void> Function(WidgetTester tester) body,
  ) => testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      for (final container in _containers) {
        container.dispose();
      }
      _containers.clear();
    }
  });

  void open(ProviderContainer container) => container
      .read(databaseSessionProvider.notifier)
      .open(
        DatabaseSession(
          file: database,
          keyFile: keyFile,
          database: newTestDatabase(),
        ),
      );

  bool isOpen(ProviderContainer container) =>
      container.read(databaseSessionProvider) != null;

  Future<void> wait(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }

  /// Completa le operazioni asincrone della notifica (permesso, preferenze).
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(pumpEventQueue);
    await tester.pump();
  }

  Future<void> remember(WidgetTester tester, ProviderContainer container) =>
      tester.runAsync(
        () => container
            .read(recentFilesRepositoryProvider)
            .remember(const RecentFile(database: database, keyFile: keyFile)),
      );

  guardTest(
    'inattività: blocca dopo il tempo impostato dall\'ultima interazione',
    (tester) async {
      final container = await start(tester);
      open(container);

      await wait(tester, const Duration(minutes: 4));
      container.read(sessionGuardProvider).userActivity();
      await wait(tester, const Duration(minutes: 4));
      expect(isOpen(container), isTrue);

      await wait(tester, const Duration(minutes: 1));
      expect(isOpen(container), isFalse);
    },
  );

  guardTest('inattività "mai": il database resta aperto', (tester) async {
    final container = await start(
      tester,
      settings: const AppSettings(lockTimeout: null),
    );
    open(container);

    await wait(tester, const Duration(hours: 2));

    expect(isOpen(container), isTrue);
  });

  guardTest('ritorno in primo piano dopo il tempo: blocca subito', (
    tester,
  ) async {
    // given: app sospesa, il timer non è scattato
    final container = await start(tester);
    open(container);
    now = now.add(const Duration(minutes: 6));

    // when
    container.read(sessionGuardProvider).appResumed();

    // then
    expect(isOpen(container), isFalse);
  });

  guardTest('ritorno in primo piano prima del tempo: resta aperto', (
    tester,
  ) async {
    final container = await start(tester);
    open(container);
    now = now.add(const Duration(minutes: 2));

    container.read(sessionGuardProvider).appResumed();

    expect(isOpen(container), isTrue);
  });

  for (final lifecycle in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    guardTest('background $lifecycle: blocca solo quando attivato', (
      tester,
    ) async {
      final container = await start(tester);
      open(container);
      final guard = container.read(sessionGuardProvider);
      guard.appLifecycleChanged(lifecycle);
      expect(isOpen(container), isTrue);
      guard.appResumed();
      await container
          .read(appSettingsProvider.notifier)
          .update(const AppSettings(lockInBackground: true));

      guard.appLifecycleChanged(lifecycle);

      expect(isOpen(container), isFalse);
      // Gli eventi sintetici hidden/paused dello stesso passaggio non
      // aprono una seconda sessione né riavviano lo sblocco.
      guard.appLifecycleChanged(AppLifecycleState.paused);
      guard.appResumed();
      expect(isOpen(container), isFalse);
    });
  }

  guardTest('inactive e resumed: biometria e permessi non bloccano', (
    tester,
  ) async {
    final container = await start(
      tester,
      settings: const AppSettings(lockInBackground: true),
    );
    open(container);
    final guard = container.read(sessionGuardProvider);

    guard.appLifecycleChanged(AppLifecycleState.inactive);
    guard.appLifecycleChanged(AppLifecycleState.resumed);

    expect(isOpen(container), isTrue);
  });

  guardTest('picker intenzionale: esente fino al resumed, poi blocco normale', (
    tester,
  ) async {
    final container = await start(
      tester,
      settings: const AppSettings(lockInBackground: true),
    );
    open(container);
    final guard = container.read(sessionGuardProvider);
    guard.appResumed();
    final result = Completer<void>();
    final operation = container
        .read(externalActivityProvider)
        .run(() => result.future);

    guard.appLifecycleChanged(AppLifecycleState.inactive);
    guard.appLifecycleChanged(AppLifecycleState.hidden);
    guard.appLifecycleChanged(AppLifecycleState.paused);
    expect(isOpen(container), isTrue);
    result.complete();
    await operation;
    // Il risultato del canale può precedere gli eventi del rientro.
    guard.appLifecycleChanged(AppLifecycleState.hidden);
    guard.appLifecycleChanged(AppLifecycleState.inactive);
    expect(isOpen(container), isTrue);
    guard.appResumed();
    expect(container.read(externalActivityProvider).isActive, isFalse);

    guard.appLifecycleChanged(AppLifecycleState.hidden);
    expect(isOpen(container), isFalse);
  });

  guardTest('il picker non disattiva il timeout di inattività', (tester) async {
    final container = await start(
      tester,
      settings: const AppSettings(lockInBackground: true),
    );
    open(container);
    final result = Completer<void>();
    final operation = container
        .read(externalActivityProvider)
        .run(() => result.future);
    container
        .read(sessionGuardProvider)
        .appLifecycleChanged(AppLifecycleState.hidden);
    expect(isOpen(container), isTrue);

    await wait(tester, const Duration(minutes: 5));

    expect(isOpen(container), isFalse);
    result.complete();
    await operation;
    container.read(sessionGuardProvider).appResumed();
  });

  guardTest('tempo di blocco cambiato: vale subito', (tester) async {
    final container = await start(tester);
    open(container);

    // Nel tempo simulato: il nuovo timer deve essere finto anch'esso.
    await container
        .read(appSettingsProvider.notifier)
        .update(const AppSettings(lockTimeout: Duration(seconds: 30)));
    await wait(tester, const Duration(seconds: 30));

    expect(isOpen(container), isFalse);
  });

  guardTest('schermo spento con l\'impostazione attiva: blocca', (
    tester,
  ) async {
    final container = await start(
      tester,
      settings: const AppSettings(lockOnScreenOff: true),
    );
    open(container);
    expect(security.events.hasListener, isTrue);

    security.events.add(null);
    await tester.pump();

    expect(isOpen(container), isFalse);
    expect(security.events.hasListener, isFalse);
  });

  guardTest('schermo spento con l\'impostazione spenta: nessun ascolto', (
    tester,
  ) async {
    final container = await start(tester);
    open(container);

    expect(security.events.hasListener, isFalse);
  });

  guardTest('schermo protetto: applicato all\'avvio e a ogni cambio', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.pump();
    expect(protection.applied, [true]);

    await tester.runAsync(
      () => container
          .read(appSettingsProvider.notifier)
          .update(const AppSettings(secureScreen: false)),
    );
    await tester.pump();

    expect(protection.applied, [true, false]);
  });

  guardTest(
    'chiusura di un database non ricordato: rilascia i permessi dei file',
    (tester) async {
      final container = await start(tester);
      open(container);

      container.read(databaseSessionProvider.notifier).lock();
      await tester.runAsync(pumpEventQueue);

      expect(storage.released, unorderedEquals([database, keyFile]));
    },
  );

  guardTest('chiusura di un database ricordato: i permessi restano', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.runAsync(
      () => container
          .read(recentFilesRepositoryProvider)
          .remember(const RecentFile(database: database, keyFile: keyFile)),
    );
    open(container);

    container.read(databaseSessionProvider.notifier).lock();
    await tester.runAsync(pumpEventQueue);

    expect(storage.released, isEmpty);
  });

  guardTest(
    'inattività con il database nei recenti: blocco completo e ritorno al suo sblocco',
    (tester) async {
      final container = await start(tester);
      await tester.runAsync(
        () => container
            .read(recentFilesRepositoryProvider)
            .remember(const RecentFile(database: database, keyFile: keyFile)),
      );
      open(container);

      await wait(tester, const Duration(minutes: 5));

      expect(isOpen(container), isFalse);
      final args = container.read(relockProvider);
      expect(args?.database.ref, database);
      expect(args?.keyFile?.ref, keyFile);
      await tester.runAsync(pumpEventQueue);
      expect(storage.released, isEmpty);
    },
  );

  guardTest(
    'inattività con un database non ricordato: scelta del file, permessi rilasciati',
    (tester) async {
      final container = await start(tester);
      open(container);

      await wait(tester, const Duration(minutes: 5));

      expect(isOpen(container), isFalse);
      expect(container.read(relockProvider), isNull);
      await tester.runAsync(pumpEventQueue);
      expect(storage.released, unorderedEquals([database, keyFile]));
    },
  );

  group('notifica del database aperto', () {
    guardTest(
      'compare all\'apertura senza dati del database, sparisce al blocco',
      (tester) async {
        final container = await start(tester);
        open(container);
        await settle(tester);

        expect(security.notification?.title, 'KeePassMobile');
        expect(security.notification?.text, 'Database open');
        expect(security.notification?.lock, 'Lock');
        expect(security.lockEvents.hasListener, isTrue);

        container.read(databaseSessionProvider.notifier).lock();
        await settle(tester);

        expect(security.notification, isNull);
        expect(security.lockEvents.hasListener, isFalse);
      },
    );

    guardTest('"Blocca": blocco completo e ritorno allo sblocco del file', (
      tester,
    ) async {
      final container = await start(tester);
      await remember(tester, container);
      open(container);
      await settle(tester);

      security.lockEvents.add(null);
      await settle(tester);

      expect(isOpen(container), isFalse);
      expect(container.read(relockProvider)?.database.ref, database);
      expect(security.notification, isNull);
    });

    guardTest(
      'permesso: chiesto alla prima apertura, di nuovo solo riattivando l\'impostazione',
      (tester) async {
        final container = await start(tester);
        open(container);
        await settle(tester);
        container.read(databaseSessionProvider.notifier).lock();
        open(container);
        await settle(tester);
        expect(security.permissionRequests, 1);

        await tester.runAsync(
          () => container
              .read(appSettingsProvider.notifier)
              .update(const AppSettings(openNotification: false)),
        );
        await settle(tester);
        expect(security.notification, isNull);

        await tester.runAsync(
          () => container
              .read(appSettingsProvider.notifier)
              .update(const AppSettings()),
        );
        await settle(tester);

        expect(security.permissionRequests, 2);
        expect(security.notification, isNotNull);
      },
    );

    guardTest('notifiche negate: database aperto, nessun ascolto di "Blocca"', (
      tester,
    ) async {
      final container = await start(tester);
      security.notificationsAllowed = false;
      open(container);
      await settle(tester);

      expect(isOpen(container), isTrue);
      expect(security.notification, isNull);
      expect(security.lockEvents.hasListener, isFalse);
    });

    guardTest(
      'motore della compilazione automatica: nessuna notifica, nessun permesso',
      (tester) async {
        final container = await start(tester, notificationAllowed: false);
        open(container);
        await settle(tester);

        expect(security.notification, isNull);
        expect(security.permissionRequests, 0);
        expect(security.lockEvents.hasListener, isFalse);
      },
    );

    guardTest(
      'impostazione spenta: nessuna notifica, nessun permesso chiesto',
      (tester) async {
        final container = await start(
          tester,
          settings: const AppSettings(openNotification: false),
        );
        open(container);
        await settle(tester);

        expect(security.notification, isNull);
        expect(security.permissionRequests, 0);
      },
    );
  });
}
