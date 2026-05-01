/// ──────────────────────────────────────────────────────────────────────────
/// Gymies App Configuration
/// ──────────────────────────────────────────────────────────────────────────
/// Centrale plek voor alle app-brede constanten: brand, URLs, domeinen,
/// deep link scheme. Nooit meer hardcoded strings verspreid over screens.
/// ──────────────────────────────────────────────────────────────────────────

class AppConfig {
  AppConfig._();

  // ── Brand ───────────────────────────────────────────────────────────────
  static const String appName = 'GYMIES';
  static const String appNameDisplay = 'Gymies';

  // ── URLs ────────────────────────────────────────────────────────────────
  static const String websiteUrl = 'https://www.gymies.nl';
  static const String termsUrl = 'https://www.gymies.nl/algemene-voorwaarden';
  static const String privacyUrl = 'https://www.gymies.nl/privacy';

  // ── Share ───────────────────────────────────────────────────────────────
  static const String shareBaseUrl = 'https://www.gymies.nl';
  static const String shareText =
      'Ontdek GYMIES — jouw persoonlijke fitness coach! '
      'Vind de perfecte personal trainer bij jou in de buurt. '
      '$shareBaseUrl';
  static const String shareSubject = 'Probeer GYMIES!';

  // ── Deep Links ──────────────────────────────────────────────────────────
  static const String deepLinkScheme = 'gymies';

  // ── Maps ─────────────────────────────────────────────────────────────────
  static const String googleMapsSearchUrl =
      'https://www.google.com/maps/search/?api=1&query=';
  static const String appleMapsSearchUrl = 'https://maps.apple.com/?q=';

  // ── Security – Domain Allowlists ────────────────────────────────────────
  /// Toegestane domeinen voor externe links (notificaties, in-app links).
  static const Set<String> allowedExternalDomains = {
    'gymies.nl',
    'www.gymies.nl',
    'mollie.com',
    'www.mollie.com',
    'my.mollie.com',
    'api.mollie.com',
  };

  /// Toegestane hosts voor de Mollie OAuth WebView.
  static const Set<String> mollieWebViewHosts = {
    'mollie.com',
    'www.mollie.com',
    'my.mollie.com',
    'api.mollie.com',
    'auth.mollie.com',
    'gymies.nl',
    'www.gymies.nl',
  };

  // ── WebSocket ───────────────────────────────────────────────────────────
  static const String wsHost = 'www.gymies.nl';
  static const String wsFallbackBaseUrl = 'wss://www.gymies.nl:443';

  // ── App Store ────────────────────────────────────────────────────────────
  /// iOS App Store ID – nodig voor in-app review en "Beoordeel ons" link.
  /// Stel in via --dart-define=IOS_APP_STORE_ID=... of pas hier de default aan
  /// zodra de app in de App Store staat.
  static const String iosAppStoreId = String.fromEnvironment(
    'IOS_APP_STORE_ID',
    defaultValue: '6760937860',
  );

  // ── Fallback App Info (voor wanneer PackageInfo niet beschikbaar is) ────
  static const String fallbackVersion = '1.2.1';
  static const String fallbackBuildNumber = '13';
  static const String fallbackPackageName = 'com.gymies.app';

  // ── Berekeningen ────────────────────────────────────────────────────────
  /// Straal van de aarde in kilometers (voor afstandsberekeningen).
  static const double earthRadiusKm = 6371.0;
}
