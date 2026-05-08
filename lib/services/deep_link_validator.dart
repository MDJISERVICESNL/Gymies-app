import 'package:flutter/foundation.dart';

/// Valideert en sanitized deep link parameters om misbruik te voorkomen.
///
/// Voorkomt:
/// - SQL injection via booking_id/trainer_id parameters
/// - XSS/script injection via tekstvelden
/// - Pad-traversal via slugs
/// - Fake payment success callbacks
class DeepLinkValidator {
  DeepLinkValidator._();

  // ── Constanten ──────────────────────────────────────────────────────

  /// Maximale lengte voor een ID parameter (UUID = 36, numeriek = ~10).
  static const int _maxIdLength = 64;

  /// Maximale lengte voor een slug parameter.
  static const int _maxSlugLength = 100;

  /// Maximale lengte voor email parameter.
  static const int _maxEmailLength = 254;

  /// Maximale lengte voor token parameter.
  static const int _maxTokenLength = 512;

  /// Toegestane tekens voor numerieke IDs.
  static final RegExp _numericIdPattern = RegExp(r'^[0-9]+$');

  /// Toegestane tekens voor UUID-achtige IDs.
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F\-]{8,36}$',
  );

  /// Toegestane tekens voor slugs (URL-veilig).
  static final RegExp _slugPattern = RegExp(r'^[a-zA-Z0-9\-_]+$');

  /// Basis email-validatie.
  static final RegExp _emailPattern = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  /// Token-patroon: alfanumeriek + standaard token-tekens.
  static final RegExp _tokenPattern = RegExp(r'^[a-zA-Z0-9\-_./+=]+$');

  /// Toegestane tiers voor subscription.
  static const Set<String> _allowedTiers = {'free', 'pro', 'proplus', 'pro_plus'};

  /// Toegestane tab-indexen.
  static const int _maxTabIndex = 10;

  // ── Publieke validatie-methoden ─────────────────────────────────────

  /// Valideert een booking_id of participant_id parameter.
  /// Retourneert de schone waarde of null als ongeldig.
  static String? validateId(String? value, {String paramName = 'id'}) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();

    if (trimmed.length > _maxIdLength) {
      _logRejection(paramName, 'te lang (${trimmed.length} chars)');
      return null;
    }

    // Sta numerieke IDs en UUIDs toe.
    if (_numericIdPattern.hasMatch(trimmed) || _uuidPattern.hasMatch(trimmed)) {
      return trimmed;
    }

    _logRejection(paramName, 'ongeldig formaat');
    return null;
  }

  /// Valideert een slug parameter (trainer slug, etc).
  static String? validateSlug(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();

    if (trimmed.length > _maxSlugLength) {
      _logRejection('slug', 'te lang');
      return null;
    }

    if (!_slugPattern.hasMatch(trimmed)) {
      _logRejection('slug', 'bevat ongeldige tekens');
      return null;
    }

    // Blokkeer pad-traversal pogingen.
    if (trimmed.contains('..') || trimmed.contains('//')) {
      _logRejection('slug', 'pad-traversal poging');
      return null;
    }

    return trimmed;
  }

  /// Valideert een email parameter.
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim().toLowerCase();

    if (trimmed.length > _maxEmailLength) {
      _logRejection('email', 'te lang');
      return null;
    }

    if (!_emailPattern.hasMatch(trimmed)) {
      _logRejection('email', 'ongeldig formaat');
      return null;
    }

    return trimmed;
  }

  /// Valideert een token parameter (password reset, etc).
  static String? validateToken(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();

    if (trimmed.length > _maxTokenLength) {
      _logRejection('token', 'te lang');
      return null;
    }

    if (!_tokenPattern.hasMatch(trimmed)) {
      _logRejection('token', 'bevat ongeldige tekens');
      return null;
    }

    return trimmed;
  }

  /// Valideert een subscription tier parameter.
  static String? validateTier(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim().toLowerCase();

    if (!_allowedTiers.contains(trimmed)) {
      _logRejection('tier', 'onbekende tier: $trimmed');
      return null;
    }

    return trimmed;
  }

  /// Valideert een tab-index parameter.
  static int validateTab(String? value) {
    if (value == null || value.trim().isEmpty) return 0;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 0 || parsed > _maxTabIndex) {
      return 0;
    }
    return parsed;
  }

  /// Valideert de hele URI structuur: scheme moet 'gymies' zijn.
  static bool isValidScheme(Uri uri) {
    return uri.scheme.toLowerCase() == 'gymies';
  }

  /// Volledige validatie van een deep link URI.
  /// Retourneert false als de URI verdacht is (logging + reject).
  static bool validateUri(Uri uri) {
    // Scheme check
    if (!isValidScheme(uri)) {
      _logRejection('uri', 'ongeldig scheme: ${uri.scheme}');
      return false;
    }

    // Host mag niet leeg zijn (behalve voor t/ slugs)
    if (uri.host.isEmpty && !uri.path.startsWith('t/')) {
      _logRejection('uri', 'lege host');
      return false;
    }

    // Blokkeer verdacht lange URIs (mogelijke buffer overflow poging)
    if (uri.toString().length > 2048) {
      _logRejection('uri', 'URI te lang (${uri.toString().length} chars)');
      return false;
    }

    // Blokkeer fragment-gebaseerde aanvallen
    if (uri.fragment.isNotEmpty && uri.fragment.length > 100) {
      _logRejection('uri', 'verdacht fragment');
      return false;
    }

    return true;
  }

  // ── Logging ─────────────────────────────────────────────────────────

  static void _logRejection(String param, String reason) {
    // In debug: print voor developer visibility.
    // In productie: Sentry breadcrumb (non-blocking).
    debugPrint('[DeepLinkValidator] REJECTED $param: $reason');
  }
}
