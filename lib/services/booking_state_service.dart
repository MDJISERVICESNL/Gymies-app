import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'gymies_api.dart';
import 'notification_realtime_service.dart';

/// Centraal booking state management.
///
/// Lost het probleem op dat 3+ schermen (ClientHome, ClientSessions,
/// TrainerSessions, ClientInvoices, Dashboard) elk apart bookingen laden
/// en niet op de hoogte zijn van wijzigingen in andere schermen.
///
/// Gebruik:
/// ```dart
/// // In widget tree (main.dart):
/// ChangeNotifierProvider(create: (_) => BookingStateService(
///   api: api,
///   auth: auth,
///   realtime: realtime,
/// )),
///
/// // In schermen:
/// final bookingState = context.watch<BookingStateService>();
/// final bookings = bookingState.bookings;
///
/// // Na een actie (confirm, cancel, etc.):
/// context.read<BookingStateService>().invalidate();
/// ```
class BookingStateService extends ChangeNotifier {
  BookingStateService({
    required GymiesApi api,
    required AuthService auth,
    required NotificationRealtimeService realtime,
  })  : _api = api,
        _auth = auth,
        _realtime = realtime {
    _realtimeSub = _realtime.events.listen(_onRealtimeEvent);
    _auth.addListener(_onAuthChanged);
  }

  final GymiesApi _api;
  final AuthService _auth;
  final NotificationRealtimeService _realtime;
  StreamSubscription<Map<String, dynamic>>? _realtimeSub;

  // ── State ────────────────────────────────────────────────────────────
  List<dynamic> _bookings = [];
  bool _loading = false;
  String? _error;
  DateTime? _lastFetched;
  Timer? _staleCacheTimer;

  /// Huidige bookingen — leeg tot eerste load.
  List<dynamic> get bookings => List.unmodifiable(_bookings);
  bool get loading => _loading;
  String? get error => _error;
  bool get hasData => _bookings.isNotEmpty || _lastFetched != null;

  /// Cache TTL: na 2 minuten wordt data als stale beschouwd.
  static const _cacheTtl = Duration(minutes: 2);

  /// Minimale interval tussen API calls om hammering te voorkomen.
  static const _minRefreshInterval = Duration(seconds: 5);

  // ── Publieke API ─────────────────────────────────────────────────────

  /// Laad bookingen (cached). Forceert alleen een API call als data
  /// stale is of nog nooit geladen.
  Future<void> ensureLoaded() async {
    if (_loading) return;
    if (_lastFetched != null &&
        DateTime.now().difference(_lastFetched!) < _cacheTtl) {
      return; // Cache is vers genoeg
    }
    await refresh();
  }

  /// Forceer een verse load van de server.
  Future<void> refresh() async {
    if (_loading) return;

    // Throttle: voorkom rapid-fire refreshes
    if (_lastFetched != null &&
        DateTime.now().difference(_lastFetched!) < _minRefreshInterval) {
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final isTrainer = _auth.isTrainer;
      final list = isTrainer
          ? await _api.getTrainerBookings()
          : await _api.getBookings();

      _bookings = (list is List) ? list : [];
      _lastFetched = DateTime.now();
      _error = null;

      // Plan stale-check zodat luisteraars weten wanneer data oud wordt
      _staleCacheTimer?.cancel();
      _staleCacheTimer = Timer(_cacheTtl, () {
        // Notify dat cache stale is geworden — schermen kunnen re-fetchen
        notifyListeners();
      });
    } catch (e) {
      _error = e.toString();
      if (kDebugMode) debugPrint('[BookingState] Laden mislukt: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Markeer data als stale zodat volgende [ensureLoaded] opnieuw laadt.
  /// Gebruik na een mutatie (confirm, cancel, reschedule, etc.).
  void invalidate() {
    _lastFetched = null;
    _staleCacheTimer?.cancel();
    // Trigger immediate refresh
    refresh();
  }

  /// Update een enkele booking lokaal (optimistic UI).
  /// Als [alsoRefresh] is true, wordt daarna ook de server geraadpleegd.
  void updateBookingLocally(
    dynamic bookingId,
    Map<String, dynamic> updates, {
    bool alsoRefresh = true,
  }) {
    final id = bookingId.toString();
    bool found = false;

    _bookings = _bookings.map((b) {
      final bId = _extractId(b);
      if (bId == id) {
        found = true;
        if (b is Map<String, dynamic>) {
          return {...b, ...updates};
        }
        return b;
      }
      return b;
    }).toList();

    if (found) {
      notifyListeners();
    }

    if (alsoRefresh) {
      // Vertraagd refreshen zodat backend tijd heeft om te verwerken
      Future.delayed(const Duration(milliseconds: 500), invalidate);
    }
  }

  /// Verwijder een booking uit de lokale lijst (na cancel/delete).
  void removeBookingLocally(dynamic bookingId, {bool alsoRefresh = true}) {
    final id = bookingId.toString();
    final before = _bookings.length;
    _bookings = _bookings.where((b) => _extractId(b) != id).toList();
    if (_bookings.length != before) {
      notifyListeners();
    }
    if (alsoRefresh) {
      Future.delayed(const Duration(milliseconds: 500), invalidate);
    }
  }

  // ── Filters (convenience) ───────────────────────────────────────────

  List<dynamic> get upcoming => _bookings.where((b) {
        final status = _extractStatus(b);
        return status == 'confirmed' || status == 'pending';
      }).toList();

  List<dynamic> get pending =>
      _bookings.where((b) => _extractStatus(b) == 'pending').toList();

  List<dynamic> get completed =>
      _bookings.where((b) => _extractStatus(b) == 'completed').toList();

  int get pendingCount => pending.length;
  int get upcomingCount => upcoming.length;

  // ── Real-time event handling ─────────────────────────────────────────

  /// Luister naar WebSocket events die booking-gerelateerd zijn.
  /// Events van het type 'booking.*' triggeren een refresh.
  void _onRealtimeEvent(Map<String, dynamic> event) {
    final type = (event['type'] ?? event['event'] ?? '').toString().toLowerCase();
    final category =
        (event['category'] ?? event['notification_type'] ?? '').toString().toLowerCase();

    // Booking-gerelateerde events
    if (type.contains('booking') ||
        category == 'bookings' ||
        type == 'session.confirmed' ||
        type == 'session.cancelled' ||
        type == 'payment.completed' ||
        type == 'payment.paid') {
      if (kDebugMode) {
        debugPrint('[BookingState] Real-time update ontvangen: $type');
      }
      // Korte delay zodat backend de wijziging heeft verwerkt
      Future.delayed(const Duration(seconds: 1), invalidate);
    }
  }

  void _onAuthChanged() {
    if (!_auth.isLoggedIn) {
      _bookings = [];
      _lastFetched = null;
      _error = null;
      _staleCacheTimer?.cancel();
      notifyListeners();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  String _extractId(dynamic booking) {
    if (booking is Map) return (booking['id'] ?? '').toString();
    return '';
  }

  String _extractStatus(dynamic booking) {
    if (booking is Map) return (booking['status'] ?? '').toString().toLowerCase();
    return '';
  }

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _staleCacheTimer?.cancel();
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
