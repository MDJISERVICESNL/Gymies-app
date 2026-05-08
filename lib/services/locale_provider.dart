import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the user's locale preference (NL / EN).
/// Wraps SharedPreferences so the setting persists across restarts.
///
/// Usage:
///   final lp = context.watch<LocaleProvider>();
///   Text('Hello');  // auto-updates when locale changes
///
///   lp.setLocale(const Locale('en', 'US'));  // switch to English
class LocaleProvider extends ChangeNotifier {
  static const String _prefKey = 'gymies_locale';

  Locale _locale = const Locale('nl', 'NL');
  Locale get locale => _locale;

  /// Whether the user has explicitly chosen a language.
  bool _hasExplicitChoice = false;
  bool get hasExplicitChoice => _hasExplicitChoice;

  LocaleProvider() {
    _loadFromPrefs();
  }

  /// Supported locales.
  static const List<Locale> supportedLocales = [
    Locale('nl', 'NL'),
    Locale('en', 'US'),
  ];

  /// Human-readable label for locale picker.
  static String labelFor(Locale locale) {
    switch (locale.languageCode) {
      case 'nl':
        return 'Nederlands';
      case 'en':
        return 'English';
      default:
        return locale.languageCode;
    }
  }

  /// Flag emoji for locale picker.
  static String flagFor(Locale locale) {
    switch (locale.languageCode) {
      case 'nl':
        return '🇳🇱';
      case 'en':
        return '🇬🇧';
      default:
        return '🌐';
    }
  }

  /// Change locale and persist.
  Future<void> setLocale(Locale newLocale) async {
    if (_locale == newLocale) return;
    _locale = newLocale;
    _hasExplicitChoice = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, '${newLocale.languageCode}_${newLocale.countryCode}');
  }

  /// Load saved preference.
  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && saved.contains('_')) {
      final parts = saved.split('_');
      _locale = Locale(parts[0], parts[1]);
      _hasExplicitChoice = true;
      notifyListeners();
    }
  }
}
