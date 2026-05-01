import 'package:flutter/foundation.dart';

import 'gymies_api.dart';

/// StorefrontCmsProvider
/// ─────────────────────
/// Deelt CMS-data (etalage) tussen alle storefront-schermen zodat
/// er slechts één API-call wordt gedaan in plaats van 7+ identieke.
///
/// Werkt als een simpele in-memory cache met TTL en invalidatie bij
/// updates. Alle storefront-schermen lezen via [data] en hoeven niet
/// zelf `api.getTrainerStorefrontCms()` aan te roepen.
///
/// Gebruik:
/// ```dart
/// // In main.dart: ChangeNotifierProvider(create: (_) => StorefrontCmsProvider(api: api))
///
/// // In een scherm:
/// final cms = context.watch<StorefrontCmsProvider>();
/// if (cms.isLoading) return LoadingWidget();
/// if (cms.error != null) return ErrorWidget(cms.error!);
/// final bio = cms.data?['bio'] ?? '';
/// ```
class StorefrontCmsProvider extends ChangeNotifier {
  StorefrontCmsProvider({required GymiesApi api}) : _api = api;

  final GymiesApi _api;

  // ── State ──────────────────────────────────────────────────────────
  Map<String, dynamic>? _data;
  DateTime? _loadedAt;
  bool _isLoading = false;
  String? _error;

  /// Cache TTL: data ouder dan dit wordt als stale beschouwd.
  static const Duration cacheTtl = Duration(minutes: 5);

  /// Minimum interval tussen refreshes (voorkom spam).
  static const Duration minRefreshInterval = Duration(seconds: 5);

  // ── Getters ────────────────────────────────────────────────────────
  Map<String, dynamic>? get data => _data;
  bool get isLoading => _isLoading;
  bool get hasData => _data != null;
  String? get error => _error;

  bool get isStale {
    if (_loadedAt == null) return true;
    return DateTime.now().difference(_loadedAt!) > cacheTtl;
  }

  // ── Publieke API ───────────────────────────────────────────────────

  /// Zorg dat data geladen is. Als er al verse cache is, doet dit niets.
  /// Ideaal om in initState/didChangeDependencies aan te roepen.
  Future<void> ensureLoaded() async {
    if (hasData && !isStale) return;
    await refresh();
  }

  /// Forceer een verse load van de API.
  Future<void> refresh() async {
    // Voorkom dubbele requests
    if (_isLoading) return;

    // Minimum interval check
    if (_loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < minRefreshInterval) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.getTrainerStorefrontCms();
      _data = result;
      _loadedAt = DateTime.now();
      _error = null;

      if (kDebugMode) {
        debugPrint('[StorefrontCms] Data geladen (${result.length} keys)');
      }
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) {
        debugPrint('[StorefrontCms] Laden mislukt: $e');
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Invalideer de cache na een update. Volgende [ensureLoaded] haalt
  /// verse data op.
  void invalidate() {
    _loadedAt = null;
    if (kDebugMode) {
      debugPrint('[StorefrontCms] Cache geïnvalideerd');
    }
  }

  /// Update de CMS data via API en refresh de lokale cache.
  Future<Map<String, dynamic>> update(Map<String, dynamic> body) async {
    final result = await _api.updateTrainerStorefrontCms(body);

    // Merge de updates in de lokale cache zodat schermen
    // meteen de nieuwe waarden zien zonder extra API-call.
    _data = {...?_data, ...result};
    _loadedAt = DateTime.now();
    _error = null;
    notifyListeners();

    if (kDebugMode) {
      debugPrint('[StorefrontCms] Data bijgewerkt en cache ververst');
    }

    return result;
  }

  /// Handige getter voor veelgebruikte velden.
  String get profileSlug =>
      (_data?['profile_slug'] ?? _data?['profileSlug'] ?? _data?['slug'] ?? '')
          as String;

  String get bio => (_data?['bio'] ?? '') as String;

  List<String> get specializationTags {
    final raw = _data?['specializations_tags'] ?? _data?['specializations'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.isNotEmpty) return raw.split(',');
    return <String>[];
  }
}
