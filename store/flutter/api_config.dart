import 'package:flutter/foundation.dart' show kIsWeb;

import 'app_build.dart';

/// API base URL voor Gymies backend (Laravel).
///
/// Prioriteit:
/// 1. `GYMIES_API_BASE` (dart-define) – altijd winnaar.
/// 2. **Web-kanaal** (`GYMIES_APP_CHANNEL=web` of web zonder store): same-origin op www.gymies.nl.
/// 3. **Store-kanaal** of mobiel default: `https://www.gymies.nl/api/gymies`.
///
/// Zo zijn Play Store / App Store / web **bewust gescheiden** qua build.
String get gymiesApiBaseUrl {
  const env = String.fromEnvironment('GYMIES_API_BASE', defaultValue: '');
  if (env.isNotEmpty) return env;

  // Web-build of web runtime: same-origin als we op gymies.nl draaien
  final useSameOrigin = AppBuild.isWebChannel ||
      (kIsWeb && !AppBuild.isStoreChannel);
  if (useSameOrigin) {
    try {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty &&
          !origin.startsWith('file:') &&
          origin != 'null') {
        return '$origin/api/gymies';
      }
    } catch (_) {}
  }

  // Store-builds en mobiel zonder web-channel: altijd productie-API
  return 'https://www.gymies.nl/api/gymies';
}
