import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/shared/settings/app_locale.dart';

void main() {
  test('system locales resolve supported languages with English fallback', () {
    expect(resolveAppLocale(null, [const Locale('ro')]), const Locale('en'));
    expect(resolveAppLocale(null, []), const Locale('en'));
    expect(
      resolveAppLocale(null, [const Locale('it', 'CH')]),
      const Locale('it'),
    );
    expect(
      resolveAppLocale(null, [const Locale('ro'), const Locale('it')]),
      const Locale('it'),
    );
    expect(resolveAppLocale('en', [const Locale('it')]), const Locale('en'));
    expect(resolveAppLocale('it', [const Locale('en')]), const Locale('it'));
    expect(resolveAppLocale('ro', [const Locale('it')]), const Locale('it'));
  });
}
