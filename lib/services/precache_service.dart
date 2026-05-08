import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gymies_api.dart';

/// PrecacheService
/// ────────────────
/// Predictive prefetching: laadt trainer data voordat de gebruiker
/// op een kaart tikt. Wanneer een trainer-kaart in de viewport komt,
/// wordt het profiel, reviews en beschikbaarheid op de achtergrond
/// opgehaald. Als de gebruiker tikt → geen spinner, instant data.
///
/// Gebruik:
/// ```dart
/// final precache = context.read<PrecacheService>();
///
/// // Als trainer-kaart zichtbaar wordt:
/// precache.prefetchTrainer(trainerId);
///
/// // Bij navigatie naar detail:
/// final cached = precache.getCachedTrainer(trainerId);
/// if (cached != null) {
///   // Direct tonen, geen API call nodig
/// }
/// ```
class PrecacheService extends ChangeNotifier {
  PrecacheService({required GymiesApi api}) : _api = api;

  final GymiesApi _api;

  /// Cache met TTL. Key = "type:id", value = data + timestamp.
  final Map<String, _CacheEntry> _cache = {};

  /// Actieve prefetch requests (voorkom duplicates).
  final Set<String> _inflight = {};

  /// Max cache grootte om geheugen te beperken.
  static const int _maxCacheSize = 50;

  /// Cache TTL: data ouder dan dit wordt als stale beschouwd.
  static const Duration _cacheTtl = Duration(minutes: 3);

  /// Debounce: wacht even voordat prefetch start (gebruiker scrollt vaak snel).
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  /// Debounce timers per trainer.
  final Map<int, Timer> _debounceTimers = {};

  // ── Publieke API ─────────────────────────────────────────────────────

  /// Prefetch trainer data (profiel + reviews + beschikbaarheid).
  /// Debounced: wacht 300ms voordat de call wordt gemaakt (snel scrollen).
  void prefetchTrainer(String trainerId) {
    final key = 'trainer:$trainerId';
    if (_cache.containsKey(key) && !_isStale(key)) return;
    if (_inflight.contains(key)) return;

    // Debounce
    final id = int.tryParse(trainerId) ?? trainerId.hashCode;
    _debounceTimers[id]?.cancel();
    _debounceTimers[id] = Timer(_debounceDelay, () {
      _doPrefetchTrainer(trainerId);
      _debounceTimers.remove(id);
    });
  }

  /// Haal gecachede trainer data op. Retourneert null als niet gecached.
  Map<String, dynamic>? getCachedTrainer(String trainerId) {
    final key = 'trainer:$trainerId';
    final entry = _cache[key];
    if (entry == null || _isStale(key)) return null;
    return entry.data;
  }

  /// Haal gecachede reviews op.
  List<dynamic>? getCachedReviews(String trainerId) {
    final key = 'reviews:$trainerId';
    final entry = _cache[key];
    if (entry == null || _isStale(key)) return null;
    return entry.data['reviews'] as List<dynamic>?;
  }

  /// Haal gecachede beschikbaarheid op.
  Map<String, dynamic>? getCachedAvailability(String trainerId) {
    final key = 'availability:$trainerId';
    final entry = _cache[key];
    if (entry == null || _isStale(key)) return null;
    return entry.data;
  }

  /// Handmatig cache invalideren (bv. na boeking).
  void invalidateTrainer(String trainerId) {
    _cache.remove('trainer:$trainerId');
    _cache.remove('reviews:$trainerId');
    _cache.remove('availability:$trainerId');
  }

  /// Hele cache legen.
  void clearAll() {
    _cache.clear();
    _inflight.clear();
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
  }

  /// Aantal items in cache (voor debugging).
  int get cacheSize => _cache.length;

  // ── Interne prefetch logica ──────────────────────────────────────────

  Future<void> _doPrefetchTrainer(String trainerId) async {
    final key = 'trainer:$trainerId';
    if (_inflight.contains(key)) return;
    _inflight.add(key);

    try {
      // Parallel ophalen: profiel + reviews + beschikbaarheid
      final results = await Future.wait<dynamic>([
        _api.getTrainerById(trainerId).catchError((_) => null),
        _api.getTrainerReviews(trainerId).catchError((_) => <String, dynamic>{}),
        _api.getTrainerPublicAvailability(trainerId).catchError((_) => <Map<String, dynamic>>[]),
      ]);

      _evictIfNeeded();

      // Profiel: Trainer object → toJson of lege map
      final trainer = results[0];
      _cache['trainer:$trainerId'] = _CacheEntry(
        data: trainer != null ? {'trainer': trainer} : <String, dynamic>{},
        cachedAt: DateTime.now(),
      );

      if (results[1] is Map<String, dynamic>) {
        _cache['reviews:$trainerId'] = _CacheEntry(
          data: results[1] as Map<String, dynamic>,
          cachedAt: DateTime.now(),
        );
      }

      final avail = results[2];
      if (avail is List) {
        _cache['availability:$trainerId'] = _CacheEntry(
          data: {'slots': avail},
          cachedAt: DateTime.now(),
        );
      }

      if (kDebugMode) {
        debugPrint('[Precache] Trainer $trainerId prefetched (cache: ${_cache.length} items)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Precache] Trainer $trainerId prefetch failed: $e');
      }
    } finally {
      _inflight.remove(key);
    }
  }

  bool _isStale(String key) {
    final entry = _cache[key];
    if (entry == null) return true;
    return DateTime.now().difference(entry.cachedAt) > _cacheTtl;
  }

  void _evictIfNeeded() {
    if (_cache.length < _maxCacheSize) return;
    // Verwijder oudste entries
    final sorted = _cache.entries.toList()
      ..sort((a, b) => a.value.cachedAt.compareTo(b.value.cachedAt));
    final toRemove = sorted.take(_cache.length - _maxCacheSize + 10);
    for (final entry in toRemove) {
      _cache.remove(entry.key);
    }
  }

  @override
  void dispose() {
    for (final t in _debounceTimers.values) {
      t.cancel();
    }
    _debounceTimers.clear();
    super.dispose();
  }
}

class _CacheEntry {
  _CacheEntry({required this.data, required this.cachedAt});
  final Map<String, dynamic> data;
  final DateTime cachedAt;
}
