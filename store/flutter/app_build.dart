import 'package:flutter/foundation.dart' show kIsWeb;

/// Bepaalt voor welk kanaal deze **build** bedoeld is (compile-time via dart-define).
///
/// - **store** – iOS/Android voor App Store / Play Store → vaste API, geen same-origin.
/// - **web** – `flutter build web` op www.gymies.nl → same-origin API waar mogelijk.
///
/// Builds:
/// ```text
/// Play Store:  flutter build appbundle --flavor store --dart-define=GYMIES_APP_CHANNEL=store
/// App Store:   flutter build ipa     --dart-define=GYMIES_APP_CHANNEL=store
/// Web:         flutter build web     --dart-define=GYMIES_APP_CHANNEL=web
/// ```
///
/// Lokaal Android zonder flavor: gebruik dev-flavor of define weglaten → gedrag als store-API.
class AppBuild {
  AppBuild._();

  /// Waarde uit `--dart-define=GYMIES_APP_CHANNEL=store|web`
  static const String _channel = String.fromEnvironment(
    'GYMIES_APP_CHANNEL',
    defaultValue: '',
  );

  /// Expliciet als store-build gecompileerd (aanbevolen voor alle app-store builds).
  static bool get isStoreChannel =>
      _channel.toLowerCase() == 'store';

  /// Expliciet als web-build gecompileerd.
  static bool get isWebChannel => _channel.toLowerCase() == 'web';

  /// Op web-platform (runtime).
  static bool get isWebPlatform => kIsWeb;

  /// Korte label voor logs/debug (geen PII).
  static String get channelLabel {
    if (_channel.isNotEmpty) return _channel;
    if (kIsWeb) return 'web_runtime';
    return 'mobile_default';
  }
}
