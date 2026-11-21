import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Indirizzo da aprire per il campo URL di una voce, come `GotoUrl` di
/// Keepass2Android: `https://` se manca lo schema o se inizia con `www.`.
///
/// Solo `http` e `https` (decisione D14); `null` per gli altri
/// schemi (`cmd://` di KeePass, `file:`, `javascript:`, ...) e per gli
/// indirizzi non validi o con credenziali nell'autorità.
Uri? entryUrl(String value) {
  var text = value.trim();
  if (text.isEmpty) return null;
  if (!text.contains(':') || text.toLowerCase().startsWith('www.')) {
    text = 'https://$text';
  }
  final uri = Uri.tryParse(text);
  return uri != null && _isWebUrl(uri) ? uri : null;
}

bool _isWebUrl(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') &&
    uri.host.isNotEmpty &&
    !uri.authority.contains('@');

/// Apertura nel browser esterno (sovrascritta nei test).
class UrlOpener {
  const UrlOpener();

  /// `false` se l'indirizzo non è ammesso o nessuna app può aprirlo.
  Future<bool> open(Uri uri) async {
    if (!_isWebUrl(uri)) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Exception {
      return false;
    }
  }
}

final urlOpenerProvider = Provider<UrlOpener>((_) => const UrlOpener());
