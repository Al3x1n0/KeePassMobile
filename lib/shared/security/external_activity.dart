import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Attività di sistema aperte esplicitamente dall'app: il relativo passaggio
/// in background non deve bloccare la sessione mentre il risultato è atteso.
final externalActivityProvider = Provider<ExternalActivity>((ref) {
  final activity = ExternalActivity(
    initialState:
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
  );
  ref.onDispose(activity.dispose);
  return activity;
});

/// Custodisce soltanto la durata delle attività esterne, senza dati sensibili.
/// Il timeout di inattività e il blocco dello schermo restano indipendenti.
class ExternalActivity {
  ExternalActivity({AppLifecycleState initialState = AppLifecycleState.resumed})
    : _lifecycle = initialState;

  AppLifecycleState _lifecycle;
  final _scopes = <_ExternalScope>{};

  /// Un'attività nativa è ancora in corso o sta tornando in primo piano.
  bool get isActive => _scopes.isNotEmpty;

  /// Esegue un picker o una richiesta biometrica fino al risultato. Se il
  /// risultato precede `resumed`, l'esenzione copre anche il rientro.
  Future<T> run<T>(Future<T> Function() operation) async {
    final scope = _ExternalScope()
      ..departed = _lifecycle != AppLifecycleState.resumed;
    _scopes.add(scope);
    try {
      return await operation();
    } finally {
      scope.completed = true;
      if (_lifecycle == AppLifecycleState.resumed) _remove(scope);
    }
  }

  /// Apre una schermata di sistema il cui canale risponde subito, prima
  /// dell'uscita dall'app. L'esenzione termina al ritorno; se non avviene
  /// alcun cambio lifecycle, scade senza lasciare un'esenzione permanente.
  Future<bool> launch(Future<bool> Function() operation) async {
    final scope = _ExternalScope()
      ..departed = _lifecycle != AppLifecycleState.resumed;
    _scopes.add(scope);
    try {
      final launched = await operation();
      scope.completed = true;
      if (!launched) {
        _remove(scope);
      } else if (!scope.departed) {
        scope.launchTimer = Timer(const Duration(seconds: 2), () {
          if (!scope.departed) _remove(scope);
        });
      } else if (_lifecycle == AppLifecycleState.resumed) {
        _remove(scope);
      }
      return launched;
    } catch (_) {
      _remove(scope);
      rethrow;
    }
  }

  /// Aggiorna lo stato prima che SessionGuard valuti il blocco background.
  void appLifecycleChanged(AppLifecycleState state) {
    _lifecycle = state;
    for (final scope in _scopes.toList()) {
      if (state == AppLifecycleState.resumed) {
        if (scope.completed && scope.departed) _remove(scope);
      } else {
        scope.departed = true;
        scope.launchTimer?.cancel();
        scope.launchTimer = null;
      }
    }
  }

  void _remove(_ExternalScope scope) {
    scope.launchTimer?.cancel();
    _scopes.remove(scope);
  }

  /// Rilascia timer e riferimenti alla chiusura del processo/provider.
  void dispose() {
    for (final scope in _scopes) {
      scope.launchTimer?.cancel();
    }
    _scopes.clear();
  }
}

class _ExternalScope {
  bool completed = false;
  bool departed = false;
  Timer? launchTimer;
}
