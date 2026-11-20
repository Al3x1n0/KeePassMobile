import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Indirizzo da aprire per il campo URL di una voce, come `GotoUrl` di
/// Keepass2Android: `https://` se manca lo schema o se inizia con `www.`.
///
/// Solo `http` e `https` (decisione D14); `null` per gli altri
/// schemi (`cmd://` di KeePass, `file:`, `javascript:`, ...) e per gli
/// indirizzi non validi.
Uri? entryUrl(String value) {
  var text = value.trim();
  if (text.isEmpty) return null;
  if (!text.contains(':') || text.toLowerCase().startsWith('www.')) {
    text = 'https://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  return switch (uri.scheme.toLowerCase()) {
    'http' || 'https' => uri,
    _ => null,
  };
}

/// Apertura nel browser esterno (sovrascritta nei test).
class UrlOpener {
  const UrlOpener();

  /// `false` se nessuna app può aprire l'indirizzo.
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }
}

final urlOpenerProvider = Provider<UrlOpener>((_) => const UrlOpener());
