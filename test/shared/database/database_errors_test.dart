import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keepass_mobile/l10n/app_localizations.dart';
import 'package:keepass_mobile/shared/database/database_errors.dart';
import 'package:keepass_mobile/shared/storage/file_storage.dart';
import 'package:kpasslib/kpasslib.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('it'));

  test('un messaggio distinto per ogni tipo di errore', () {
    expect(
      describeDatabaseError(l10n, const InvalidCredentialsError('x')),
      l10n.errorInvalidCredentials,
    );
    expect(
      describeDatabaseError(l10n, const FileCorruptedError('x')),
      l10n.errorFileCorrupted,
    );
    expect(
      describeDatabaseError(l10n, const UnsupportedValueError('x')),
      l10n.errorUnsupported,
    );
    expect(
      describeDatabaseError(l10n, const KeyFileUnavailableException()),
      l10n.errorKeyFileUnavailable,
    );
    expect(
      describeDatabaseError(l10n, const FileUnavailableException()),
      l10n.errorFileUnavailable,
    );
    expect(
      describeDatabaseError(
        l10n,
        const KdbxResourceLimitError(KdbxResourceLimit.kdfCost),
      ),
      l10n.errorDatabaseKdfTooCostly,
    );
  });

  test(
    'errore sconosciuto: messaggio generico, mai il testo dell\'eccezione',
    () {
      final message = describeDatabaseError(
        l10n,
        StateError('dettaglio interno'),
      );
      expect(message, l10n.errorGeneric);
      expect(message, isNot(contains('dettaglio')));
    },
  );
}
