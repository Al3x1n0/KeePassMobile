import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferenze non sensibili dell'app (file recenti, impostazioni).
///
/// Va sovrascritto in `main` con l'istanza caricata all'avvio. Mai usarlo per
/// password, chiavi o chiavi derivate (SEC-03).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('sharedPreferencesProvider non inizializzato'),
);
