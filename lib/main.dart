import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/external_change_dialog.dart';
import 'app/remote_dialogs.dart';
import 'autofill_ios_spike.dart';
import 'features/autofill/autofill_app.dart';
import 'features/file_select/demo_database.dart';
import 'shared/crypto/app_crypto_engine.dart';
import 'shared/database/external_change.dart';
import 'shared/storage/preferences.dart';
import 'shared/storage/remote_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Argon2 nativo per kpasslib (ADR-002). Gli isolate lo reinstallano.
  AppCryptoEngine.install();
  final preferences = await SharedPreferences.getInstance();
  await initializeDemoDatabase(preferences);
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        externalChangeResolverProvider.overrideWith(externalChangeDialog),
        remoteCredentialsPromptProvider.overrideWith(remoteCredentialsDialog),
        certificateTrustPromptProvider.overrideWith(certificateTrustDialog),
        sshHostTrustPromptProvider.overrideWith(sshHostTrustDialog),
      ],
      child: const KeePassMobileApp(),
    ),
  );
}

/// Compilazione automatica su Android: punto di ingresso del motore di
/// `AutofillActivity` (ADR-013).
@pragma('vm:entry-point')
Future<void> autofillMain() => runAutofill();

/// Prova tecnica D21: punto di ingresso dell'estensione di compilazione
/// automatica di iOS.
@pragma('vm:entry-point')
Future<void> autofillIosMain() => runAutofillIosSpike();
