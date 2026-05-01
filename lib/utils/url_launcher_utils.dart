import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

/// Toegestane domeinen voor externe links vanuit notificaties en in-app links.
/// Alleen https-links naar deze domeinen worden geopend via launchUrl.
const _allowedDomains = AppConfig.allowedExternalDomains;

/// Controleert of een URL veilig is om te openen:
/// - Scheme moet 'https' zijn (geen http, javascript, file, data, etc.)
/// - Host moet in de allowlist staan of een subdomein zijn van een toegestaan domein
bool isSafeExternalUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return false;
  if (uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  if (_allowedDomains.contains(host)) return true;
  // Sta subdomeinen toe van toegestane domeinen (bijv. dash.gymies.nl)
  for (final allowed in _allowedDomains) {
    if (host.endsWith('.$allowed')) return true;
  }
  return false;
}

/// Opent een externe URL veilig. Valideert scheme en domein voor openen.
/// Retourneert true als de URL geopend is, false als geweigerd of mislukt.
Future<bool> safeLaunchUrl(
  String url, {
  LaunchMode mode = LaunchMode.externalApplication,
}) async {
  if (!isSafeExternalUrl(url)) {
    if (kDebugMode) {
      debugPrint('[UrlSecurity] Geblokkeerde URL: $url');
    }
    return false;
  }
  final uri = Uri.parse(url.trim());
  try {
    return await launchUrl(uri, mode: mode);
  } catch (_) {
    return false;
  }
}
