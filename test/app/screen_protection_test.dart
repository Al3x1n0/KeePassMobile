import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/app/screen_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.flutterplaza.no_screenshot_methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'release, attiva: blocco e copertura nera con un colore a 32 bit',
    () async {
      await const ScreenProtection(
        enforce: true,
        deviceTest: false,
      ).apply(enabled: true);

      expect(calls.map((c) => c.method), [
        'screenshotOff',
        'screenshotWithColor',
      ]);
      final color = (calls.last.arguments as Map)['color'] as int;
      // Entro Int32: il plugin Android legge `Integer`, non `Long`.
      expect(color, inInclusiveRange(-0x80000000, 0x7FFFFFFF));
      expect(color & 0xFFFFFFFF, 0xFF000000);
    },
  );

  test('release, disattiva: copertura tolta e blocco rilasciato', () async {
    await const ScreenProtection(
      enforce: true,
      deviceTest: false,
    ).apply(enabled: false);

    expect(calls.map((c) => c.method), ['overlayOff', 'screenshotOn']);
  });

  test('debug: impostazione attiva ma protezione spenta', () async {
    await const ScreenProtection(
      enforce: false,
      deviceTest: false,
    ).apply(enabled: true);

    expect(calls.map((c) => c.method), ['overlayOff', 'screenshotOn']);
  });

  test('release di prova: la protezione precedente viene rimossa', () async {
    await const ScreenProtection(
      enforce: true,
      deviceTest: true,
    ).apply(enabled: true);
    expect(calls.map((c) => c.method), ['overlayOff', 'screenshotOn']);
  });

  test(
    'release normale: riattiva la protezione dopo una build di prova',
    () async {
      await const ScreenProtection(
        enforce: true,
        deviceTest: true,
      ).apply(enabled: true);
      await const ScreenProtection(
        enforce: true,
        deviceTest: false,
      ).apply(enabled: true);
      expect(calls.map((c) => c.method), [
        'overlayOff',
        'screenshotOn',
        'screenshotOff',
        'screenshotWithColor',
      ]);
    },
  );

  test('flag di prova letto dalla configurazione di compilazione', () {
    expect(
      const ScreenProtection().deviceTest,
      const bool.fromEnvironment('KPM_DEVICE_TEST'),
    );
  });

  test('predefinito: protezione solo nelle build di release', () {
    expect(const ScreenProtection().enforce, kReleaseMode);
  });

  test('errore del codice nativo: richiede una conferma esplicita', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'x'),
    );

    final container = ProviderContainer.test(
      overrides: [
        screenProtectionProvider.overrideWithValue(
          const ScreenProtection(enforce: true, deviceTest: false),
        ),
      ],
    );
    final notifier = container.read(screenProtectionStatusProvider.notifier);
    expect(await notifier.apply(enabled: true), isFalse);
    expect(
      container.read(screenProtectionStatusProvider),
      ScreenProtectionStatus.warning,
    );
    notifier.acknowledge();
    expect(await notifier.apply(enabled: true), isTrue);
    expect(
      container.read(screenProtectionStatusProvider),
      ScreenProtectionStatus.acknowledged,
    );
  });

  test(
    'un esito falso del plugin segnala protezione non disponibile',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      expect(
        await const ScreenProtection(
          enforce: true,
          deviceTest: false,
        ).apply(enabled: true),
        isFalse,
      );
    },
  );
}
