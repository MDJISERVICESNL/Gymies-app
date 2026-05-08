/// ──────────────────────────────────────────────────────────────────────────
/// Gymies App Configuration
/// ──────────────────────────────────────────────────────────────────────────
/// Centrale plek voor alle app-brede constanten: brand, URLs, domeinen,
/// deep link scheme. Nooit meer hardcoded strings verspreid over screens.
///
/// Environment Switching:
/// Compileer met: flutter run --dart-define=ENV=development
/// Of voor productie: flutter run --dart-define=ENV=production
/// ──────────────────────────────────────────────────────────────────────────
library;

class AppConfig {
  AppConfig._();

  // ── Environment Detection ───────────────────────────────────────────────
  static const String environment = String.fromEnvironment('ENV', defaultValue: 'production');

  static bool get isDevelopment => environment == 'development';
  static bool get isProduction => environment == 'production';
  static bool get isStaging => environment == 'staging';

  // ── Brand ───────────────────────────────────────────────────────────────
  static const String appName = 'GYMIES';
  static const String appNameDisplay = 'Gymies';

  // ── URLs (Environment-aware) ────────────────────────────────────────────
  static String get websiteUrl {
    switch (environment) {
      case 'development':
        return 'https://localhost:3000';
      case 'staging':
        return 'https://staging.gymies.nl';
      default:
        return 'https://www.gymies.nl';
    }
  }

  static String get apiBaseUrl {
    switch (environment) {
      case 'development':
        return 'http://localhost:8000/api/gymies';
      case 'staging':
        return 'https://api-staging.gymies.nl/api/gymies';
      default:
        return 'https://api.gymies.nl/api/gymies';
    }
  }

  static const String termsUrl = 'https://www.gymies.nl/algemene-voorwaarden';
  static const String privacyUrl = 'https://www.gymies.nl/privacy';

  // ── Share ───────────────────────────────────────────────────────────────
  static String get shareBaseUrl => websiteUrl;
  static const String shareText =
      'Ontdek GYMIES — jouw persoonlijke fitness coach! '
      'Vind de perfecte personal trainer bij jou in de buurt.';
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

  // ── WebSocket (Environment-aware) ───────────────────────────────────────
  static String get wsHost {
    switch (environment) {
      case 'development':
        return 'localhost:6001';
      case 'staging':
        return 'ws-staging.gymies.nl';
      default:
        return 'ws.gymies.nl';
    }
  }

  static String get wsFallbackBaseUrl {
    switch (environment) {
      case 'development':
        return 'ws://localhost:6001';
      case 'staging':
        return 'wss://ws-staging.gymies.nl:443';
      default:
        return 'wss://ws.gymies.nl:443';
    }
  }

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
