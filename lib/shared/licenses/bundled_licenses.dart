import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Makes bundled notices available to Flutter's license page on demand.
void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'KeePassMobile',
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks(const [
      'KeePassMobile — attributions',
    ], await rootBundle.loadString('NOTICE'));
    final raw = await rootBundle.loadString(
      'assets/licenses/qr_scanner_0_2_0_alpha_3.json',
    );
    final entries = jsonDecode(raw) as List<dynamic>;
    for (final entry in entries) {
      final notice = entry as Map<String, dynamic>;
      yield LicenseEntryWithLineBreaks([
        notice['package'] as String,
      ], notice['text'] as String);
    }
  });
}
