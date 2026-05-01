import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// API base URL voor Gymies backend.
/// Override met --dart-define=GYMIES_API_BASE=https://...
/// Productiewebsite: https://gymies.nl/#/login – app moet hetzelfde domein gebruiken.
/// Je kunt de homepage geven (https://gymies.nl) – dan wordt /api/gymies automatisch toegevoegd.
String get gymiesApiBaseUrl {
  const env = String.fromEnvironment('GYMIES_API_BASE', defaultValue: '');
  var value = env.isNotEmpty ? env : AppConfig.websiteUrl;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw StateError('GYMIES_API_BASE moet een geldige https:// URL zijn.');
  }
  // Als alleen domein (geen /api/gymies): voeg API-pad toe
  final path = (uri.path.isEmpty || uri.path == '/')
      ? ''
      : uri.path.replaceAll(RegExp(r'/+$'), '');
  if (!path.contains('api/gymies')) {
    value = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/api/gymies';
  } else {
    value = value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }
  assert(() {
    // ignore: avoid_print
    if (kDebugMode) debugPrint('[api_config] gymiesApiBaseUrl: $value');
    return true;
  }());
  return value;
}

/// Zet port 443/80 als Uri.port==0, stript fragment – voorkomt WebSocketChannelException op iOS.
Uri ensureWsPort(Uri u) {
  var fixed = u;
  if (u.port == 0) {
    final port = (u.scheme == 'wss' || u.scheme == 'https') ? 443 : 80;
    fixed = fixed.replace(port: port);
  }
  if (u.fragment.isNotEmpty) fixed = fixed.replace(fragment: '');
  return fixed;
}

/// WebSocket notificaties/chat. Standaard AAN – Reverb/nginx geconfigureerd op www.gymies.nl.
/// Zet --dart-define=GYMIES_WS_ENABLED=false om uit te schakelen.
const bool gymiesWsEnabled = bool.fromEnvironment(
  'GYMIES_WS_ENABLED',
  defaultValue: true,
);

/// Optionele websocket URL template voor chat.
/// Voorbeeld:
/// --dart-define=GYMIES_WS_CHAT_URL=wss://www.gymies.nl/ws/chat/{conversationId}?access_token={token}
String get gymiesWsChatUrlTemplate {
  const env = String.fromEnvironment('GYMIES_WS_CHAT_URL', defaultValue: '');
  return env.trim();
}

/// Fallback websocket basis URL. Kan overschreven worden met GYMIES_WS_BASE.
/// Hardcoded wss://gymies.nl voorkomt Uri-parsing bug (port :0 op iOS).
String get gymiesWsBaseUrl {
  const env = String.fromEnvironment('GYMIES_WS_BASE', defaultValue: '');
  if (env.trim().isNotEmpty) {
    final raw = env.trim();
    if (raw.startsWith('wss://') || raw.startsWith('ws://')) {
      // Strip :0 uit URL – voorkomt WebSocketChannelException
      final cleaned = raw
          .replaceAll(':0/', '/')
          .replaceAll(':0?', '?')
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');
      final u = Uri.tryParse(cleaned);
      if (u != null && u.host.isNotEmpty && u.port != 0) {
        return cleaned.split('?').first;
      }
      final match = RegExp(r'(?:wss?://)([^:/]+)').firstMatch(cleaned);
      if (match != null) return 'wss://${match.group(1)}:443';
    }
  }
  // www.gymies.nl per deploy docs (nginx /ws proxy). Expliciet :443 voorkomt port=0 bug.
  return AppConfig.wsFallbackBaseUrl;
}

/// Token in query EN headers. GymiesAuthMiddleware leest headers (Authorization, X-Gymies-Token).
/// useAuthViaQueryOnly=false: stuur headers zodat GymiesAuthMiddleware werkt; query blijft fallback.
const bool useAuthViaQueryOnly = false;

/// Optionele websocket URL template voor notificaties.
/// Voorbeeld:
/// --dart-define=GYMIES_WS_NOTIFICATIONS_URL=wss://www.gymies.nl/ws/notifications?access_token={token}&role={role}
String get gymiesWsNotificationsUrlTemplate {
  const env = String.fromEnvironment(
    'GYMIES_WS_NOTIFICATIONS_URL',
    defaultValue: '',
  );
  return env.trim();
}
