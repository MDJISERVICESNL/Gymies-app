import 'package:flutter/foundation.dart';

import 'gymies_api.dart';
import 'auth_service.dart';

/// Entitlements op basis van subscription tier.
/// Haalt config van backend (subscription/features) of berekent lokaal via tier + defaults.
class SubscriptionEntitlementsService extends ChangeNotifier {
  SubscriptionEntitlementsService({
    required GymiesApi api,
    required AuthService auth,
  })  : _api = api,
        _auth = auth;

  final GymiesApi _api;
  final AuthService _auth;

  Map<String, dynamic>? _entitlements;
  String? _tier;
  String? _nextBillingDate;
  bool _loading = false;
  bool _fromApi = false;

  bool get isLoading => _loading;
  /// Volgende factuurdatum (YYYY-MM-DD) van de backend, of null als niet beschikbaar.
  String? get nextBillingDate => _nextBillingDate;
  bool get isFromApi => _fromApi;
  String? get tier => _tier;

  /// Feature beschikbaar (boolean-features).
  bool hasFeature(String key) {
    if (_entitlements == null) return _fallbackHasFeature(key);
    final v = _entitlements![key];
    if (v == null) return _fallbackHasFeature(key);
    if (v is bool) return v;
    if (v is num && v.toInt() != 0) return true;
    if (v is String && v.toLowerCase() == 'true') return true;
    return false;
  }

  /// Limiet voor features met getal (bijv. profile_videos, max_clients).
  /// -1 = onbeperkt.
  int getLimit(String key) {
    if (_entitlements == null) return _fallbackLimit(key);
    final v = _entitlements![key];
    if (v == null) return _fallbackLimit(key);
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? _fallbackLimit(key);
    return _fallbackLimit(key);
  }

  /// Dossier + doelen (coach tools) – Pro+.
  bool get coachToolsEnabled => hasFeature('dossier') || hasFeature('goals');

  /// Pro Hub – health score, upsell, herboek – Pro+.
  bool get proHubEnabled =>
      hasFeature('health_score') ||
      hasFeature('upsell') ||
      hasFeature('rebook');

  /// Trainer Suite – Studio/Gym only.
  bool get suiteEnabled => hasFeature('advanced_reporting') || hasFeature('suite_tools');

  /// Pro+ features – branded profiel, eigen URL, verified badge, etc.
  bool get proPlusEnabled =>
      hasFeature('branded_profile') ||
      hasFeature('custom_url') ||
      hasFeature('verified_badge');

  /// Is dit een gym/studio account (niet zichtbaar voor trainers).
  bool get isStudio {
    final t = _tier ?? '';
    return t == 'studio' || t == 'elite';
  }

  bool _fallbackHasFeature(String key) {
    final t = _tier ?? _resolveTierFallback();
    return _defaultEnabledFor(key, t);
  }

  int _fallbackLimit(String key) {
    final t = _tier ?? _resolveTierFallback();
    return _defaultLimitFor(key, t);
  }

  String _resolveTierFallback() {
    final user = _auth.user;
    if (user != null) {
      final p = _str(user, [
        'subscription_tier',
        'subscription_plan',
        'plan',
        'tier',
        'plan_slug',
        'plan_name',
      ])
          .toLowerCase();
      if (p.contains('studio')) return 'studio';
      if (p.contains('pro_plus') || p.contains('proplus') || p.contains('pro+')) return 'pro_plus';
      if (p.contains('elite')) return 'studio'; // legacy: elite → studio
      if (p.contains('pro')) return 'pro';
      if (p.contains('starter') || p.contains('basic')) return 'starter';
    }
    return 'starter';
  }

  String _str(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return '';
  }

  static bool _defaultEnabledFor(String key, String tier) {
    const proKeys = {
      'search_priority',
      'group_sessions',
      'packages',
      'promo_codes',
      'crm',
      'income_dashboard',
      'marketing_tools',
      'priority_support',
    };
    const proPlusKeys = {
      'branded_profile',
      'custom_url',
      'profile_branding',
      'intro_video',
      'verified_badge',
      'newsletter',
      'booking_widget',
      'profile_qr',
      'client_analytics',
    };
    const studioKeys = {
      'advanced_reporting',
      'suite_tools',
    };
    if (studioKeys.contains(key)) return tier == 'studio';
    if (proPlusKeys.contains(key)) return tier == 'pro_plus' || tier == 'studio';
    if (proKeys.contains(key)) return tier == 'pro' || tier == 'pro_plus' || tier == 'studio';
    return true; // basis-features altijd (starter)
  }

  static int _defaultLimitFor(String key, String tier) {
    if (key == 'max_clients') {
      return -1; // Onbeperkt voor alle plannen
    }
    if (key == 'profile_videos') {
      if (tier == 'pro_plus' || tier == 'studio') return -1;
      if (tier == 'pro') return 1;
      return 0;
    }
    if (key == 'profile_stories') {
      if (tier == 'pro_plus' || tier == 'studio') return -1;
      if (tier == 'pro') return 1;
      return 0;
    }
    return -1;
  }

  /// Laadt entitlements: eerst API, anders lokaal berekenen.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();

    try {
      final res = await _api.getSubscriptionFeatures();
      if (res != null) {
        final tierRaw = res['tier'] ?? res['plan'] ?? res['plan_slug'];
        _tier = tierRaw?.toString().trim().toLowerCase();
        final nb = res['next_billing_date'];
        _nextBillingDate = nb != null && nb.toString().trim().isNotEmpty
            ? nb.toString().trim()
            : null;
        final features = res['features'] ?? res['entitlements'] ?? res;
        if (features is Map<String, dynamic>) {
          _entitlements = Map<String, dynamic>.from(features);
          _fromApi = true;
          _loading = false;
          notifyListeners();
          return;
        }
      }
    } catch (_) {
      // API niet beschikbaar – fallback
    }

    // Fallback: tier uit subscription/my of trainer/me
    if (_tier == null) {
      try {
        final sub = await _api.getMySubscription();
        final tierFromSub = _str(sub, [
          'plan_slug',
          'plan_name',
          'tier',
          'plan',
        ]).toLowerCase();
        if (tierFromSub.isNotEmpty) {
          if (tierFromSub.contains('studio')) {
            _tier = 'studio';
          } else if (tierFromSub.contains('pro_plus') || tierFromSub.contains('proplus') || tierFromSub.contains('pro+')) {
            _tier = 'pro_plus';
          } else if (tierFromSub.contains('elite')) {
            _tier = 'studio'; // legacy
          } else if (tierFromSub.contains('pro')) {
            _tier = 'pro';
          } else {
            _tier = 'starter';
          }
        }
      } catch (_) {
        // Ignore
      }
    }
    if (_tier == null) {
      try {
        final profile = await _api.getTrainerProfile();
        final tierFromProfile = _str(profile, [
          'subscription_plan',
          'subscription_tier',
          'plan',
          'tier',
        ]).toLowerCase();
        if (tierFromProfile.contains('studio')) {
          _tier = 'studio';
        } else if (tierFromProfile.contains('pro_plus') || tierFromProfile.contains('proplus') || tierFromProfile.contains('pro+')) {
          _tier = 'pro_plus';
        } else if (tierFromProfile.contains('elite')) {
          _tier = 'studio'; // legacy
        } else if (tierFromProfile.contains('pro')) {
          _tier = 'pro';
        }
      } catch (_) {
        // Ignore
      }
    }
    _tier ??= _resolveTierFallback();
    _tier ??= 'starter';
    _nextBillingDate = null;

    // Bouw entitlements vanuit defaults
    _entitlements = _buildFallbackEntitlements(_tier!);
    _fromApi = false;
    _loading = false;
    notifyListeners();
  }

  Map<String, dynamic> _buildFallbackEntitlements(String tier) {
    const proKeys = {
      'search_priority',
      'group_sessions',
      'packages',
      'promo_codes',
      'crm',
      'income_dashboard',
      'marketing_tools',
      'priority_support',
    };
    const proPlusKeys = {
      'branded_profile',
      'custom_url',
      'profile_branding',
      'intro_video',
      'verified_badge',
      'newsletter',
      'booking_widget',
      'profile_qr',
      'client_analytics',
    };
    const studioKeys = {
      'advanced_reporting',
      'suite_tools',
    };
    final out = <String, dynamic>{};
    for (final k in proKeys) {
      out[k] = tier == 'pro' || tier == 'pro_plus' || tier == 'studio';
    }
    for (final k in proPlusKeys) {
      out[k] = tier == 'pro_plus' || tier == 'studio';
    }
    for (final k in studioKeys) {
      out[k] = tier == 'studio';
    }
    out['max_clients'] = _defaultLimitFor('max_clients', tier);
    out['profile_videos'] = _defaultLimitFor('profile_videos', tier);
    out['profile_stories'] = _defaultLimitFor('profile_stories', tier);
    return out;
  }

  /// Lijst van feature-keys die de gebruiker mist (voor upsell).
  List<String> missingFeatureKeys() {
    final t = _tier ?? 'starter';
    if (t == 'pro_plus' || t == 'studio') return [];
    final missing = <String>[];
    if (t == 'starter') {
      // Mist alle Pro features
      missing.addAll([
        'search_priority', 'group_sessions', 'packages', 'promo_codes',
        'crm', 'income_dashboard', 'marketing_tools', 'priority_support',
      ]);
      // Mist alle Pro+ features
      missing.addAll([
        'branded_profile', 'custom_url', 'profile_branding', 'intro_video',
        'verified_badge', 'newsletter', 'booking_widget', 'profile_qr',
        'client_analytics',
      ]);
    } else if (t == 'pro') {
      // Mist Pro+ features
      missing.addAll([
        'branded_profile', 'custom_url', 'profile_branding', 'intro_video',
        'verified_badge', 'newsletter', 'booking_widget', 'profile_qr',
        'client_analytics',
      ]);
    }
    return missing;
  }
}
