import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'app_settings.dart';

Locale resolveAppLocale(String? languageCode, List<Locale> systemLocales) {
  final requested = AppSettings.languageCodes.contains(languageCode)
      ? [Locale(languageCode!)]
      : systemLocales;
  for (final locale in requested) {
    for (final supported in AppLocalizations.supportedLocales) {
      if (locale.languageCode == supported.languageCode) return supported;
    }
  }
  return const Locale('en');
}

final appLocaleProvider = Provider<Locale>((ref) {
  final binding = WidgetsBinding.instance;
  final observer = _LocaleObserver(ref.invalidateSelf);
  binding.addObserver(observer);
  ref.onDispose(() => binding.removeObserver(observer));
  return resolveAppLocale(
    ref.watch(appSettingsProvider.select((settings) => settings.languageCode)),
    binding.platformDispatcher.locales,
  );
});

class _LocaleObserver extends WidgetsBindingObserver {
  _LocaleObserver(this.onChange);
  final VoidCallback onChange;

  @override
  void didChangeLocales(List<Locale>? locales) => onChange();
}
