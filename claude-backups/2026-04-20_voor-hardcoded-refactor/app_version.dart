import 'package:package_info_plus/package_info_plus.dart';

/// Centrale versie-informatie voor de GYMIES app.
///
/// Gebruik:
///   final info = await AppVersion.get();
///   print(info.display); // "Gymies v1.2.0 (12)"
///
/// Of als singleton (na eerste aanroep):
///   final info = AppVersion.current;
class AppVersion {
  AppVersion._({
    required this.version,
    required this.buildNumber,
    required this.packageName,
    required this.appName,
  });

  /// Semantic version string, bijv. "1.2.0"
  final String version;

  /// Build nummer, bijv. "12"
  final String buildNumber;

  /// Package identifier, bijv. "com.gymies.app"
  final String packageName;

  /// App display name
  final String appName;

  /// Geformatteerd voor weergave: "Gymies v1.2.0 (12)"
  String get display => 'Gymies v$version ($buildNumber)';

  /// Korte versie: "v1.2.0"
  String get short => 'v$version';

  // ─── Singleton cache ───────────────────────────────────────────────

  static AppVersion? _instance;

  /// Huidige versie (null als [get] nog niet is aangeroepen).
  static AppVersion? get current => _instance;

  /// Laad versie-informatie uit het platform.
  /// Resultaat wordt gecached — veilig om meerdere keren aan te roepen.
  static Future<AppVersion> get() async {
    if (_instance != null) return _instance!;

    try {
      final info = await PackageInfo.fromPlatform();
      _instance = AppVersion._(
        version: info.version,
        buildNumber: info.buildNumber,
        packageName: info.packageName,
        appName: info.appName,
      );
    } catch (_) {
      // Fallback als PackageInfo niet beschikbaar is (bijv. in tests)
      _instance = AppVersion._(
        version: '1.2.0',
        buildNumber: '12',
        packageName: 'com.gymies.app',
        appName: 'Gymies',
      );
    }

    return _instance!;
  }
}
