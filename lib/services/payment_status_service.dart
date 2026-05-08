import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'gymies_api.dart';
import 'notification_realtime_service.dart';

/// Payment status service met WebSocket-first + polling fallback.
///
/// In plaats van blind te pollen, luistert deze service naar real-time
/// WebSocket events (PaymentStatusUpdated) en valt terug op polling
/// als de WebSocket niet verbonden is.
///
/// Gebruik:
/// ```dart
/// final service = PaymentStatusService(api: api, auth: auth, realtime: realtime);
/// service.watchPayment(
///   bookingId: '123',
///   onStatusChanged: (status) {
///     if (status == 'paid') { /* navigeer naar succes */ }
///   },
/// );
/// // Vergeet niet te stoppen:
/// service.stopWatching();
/// ```
class PaymentStatusService {
  PaymentStatusService({
    required GymiesApi api,
    required AuthService auth,
    required NotificationRealtimeService realtime,
  })  : _api = api,
        _auth = auth,
        _realtime = realtime;

  final GymiesApi _api;
  // ignore: unused_field
  final AuthService _auth;
  final NotificationRealtimeService _realtime;

  String? _watchingBookingId;
  String? _lastKnownStatus;
  DateTime? _lastStatusTimestamp;
  Timer? _pollTimer;
  StreamSubscription<Map<String, dynamic>>? _realtimeSub;
  void Function(String status)? _onStatusChanged;
  int _pollCount = 0;

  /// Maximum aantal poll pogingen voordat we stoppen.
  static const _maxPollAttempts = 30;

  /// Poll intervals (exponential backoff): 2s, 4s, 6s, 8s, 10s, 10s...
  static const _pollIntervals = [2, 4, 6, 8, 10];

  /// Start met het volgen van een payment status.
  void watchPayment({
    required String bookingId,
    required void Function(String status) onStatusChanged,
    String? initialStatus,
  }) {
    stopWatching();

    _watchingBookingId = bookingId;
    _onStatusChanged = onStatusChanged;
    _lastKnownStatus = initialStatus ?? 'open';
    _lastStatusTimestamp = DateTime.now();
    _pollCount = 0;

    try {
      // BUG FIX: Add error handling for WebSocket event subscription
      // Luister naar WebSocket events
      _realtimeSub = _realtime.events.listen(
        _onRealtimeEvent,
        onError: (e) {
          if (kDebugMode) debugPrint('[PaymentStatus] WebSocket event stream error: $e');
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PaymentStatus] watchPayment subscription error: $e');
    }

    // Start ook polling als fallback
    _scheduleNextPoll();

    if (kDebugMode) {
      debugPrint('[PaymentStatus] Watching booking $bookingId '
          '(ws=${_realtime.isConnected ? "connected" : "disconnected"})');
    }
  }

  /// Stop met volgen.
  void stopWatching() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _realtimeSub?.cancel();
    _realtimeSub = null;
    _watchingBookingId = null;
    _onStatusChanged = null;
    _pollCount = 0;
  }

  bool get isWatching => _watchingBookingId != null;

  /// Verwerk real-time WebSocket event.
  void _onRealtimeEvent(Map<String, dynamic> event) {
    final type = (event['type'] ?? event['event'] ?? '').toString();

    // PaymentStatusUpdated event van backend
    if (type == 'PaymentStatusUpdated' || type == 'payment.status_updated') {
      final eventBookingId = (event['booking_id'] ?? '').toString();
      final eventStatus = (event['status'] ?? '').toString();
      final eventTimestamp = event['timestamp']?.toString();

      if (eventBookingId == _watchingBookingId && eventStatus.isNotEmpty) {
        // Deduplicatie: negeer als we deze status al kennen
        if (_isDuplicate(eventStatus, eventTimestamp)) {
          if (kDebugMode) {
            debugPrint('[PaymentStatus] Duplicate WebSocket event genegeerd: $eventStatus');
          }
          return;
        }

        if (kDebugMode) {
          debugPrint('[PaymentStatus] WebSocket update: $eventStatus');
        }

        _updateStatus(eventStatus);
        return;
      }
    }

    // Generieke payment-gerelateerde notificatie
    if (type.contains('payment') && _watchingBookingId != null) {
      // Trigger een poll om de exacte status op te halen
      _pollNow();
    }
  }

  /// Plan de volgende poll.
  void _scheduleNextPoll() {
    if (_watchingBookingId == null) return;
    if (_pollCount >= _maxPollAttempts) {
      if (kDebugMode) {
        debugPrint('[PaymentStatus] Max poll attempts bereikt, gestopt');
      }
      return;
    }

    // Als WebSocket verbonden is, poll minder vaak (elke 10s als backup)
    // BUG FIX: Ensure exponential backoff is properly applied even with WebSocket
    final intervalIndex = _realtime.isConnected
        ? _pollIntervals.length - 1 // Altijd langste interval als WS actief
        : _pollCount.clamp(0, _pollIntervals.length - 1);
    final delay = Duration(seconds: _pollIntervals[intervalIndex]);

    _pollTimer?.cancel();
    _pollTimer = Timer(delay, _pollNow);
  }

  /// Voer een poll uit naar de API.
  Future<void> _pollNow() async {
    if (_watchingBookingId == null) return;
    _pollCount++;

    try {
      final result = await _api.getBookingPaymentStatus(_watchingBookingId!);
      final status = (result['status'] ?? result['data']?['status'] ?? '').toString();

      if (status.isNotEmpty && !_isDuplicate(status, null)) {
        if (kDebugMode) {
          debugPrint('[PaymentStatus] Poll update #$_pollCount: $status');
        }
        _updateStatus(status);
        return; // Status changed, don't schedule more polls
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[PaymentStatus] Poll #$_pollCount failed: $e');
      }
    }

    // BUG FIX: Ensure timer is properly cancelled before returning
    // Schedule next poll als status nog niet definitief is
    if (_isFinalStatus(_lastKnownStatus ?? '')) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _scheduleNextPoll();
  }

  /// Update de status en notify callback.
  void _updateStatus(String newStatus) {
    _lastKnownStatus = newStatus;
    _lastStatusTimestamp = DateTime.now();

    _onStatusChanged?.call(newStatus);

    // Stop polling als de status definitief is
    if (_isFinalStatus(newStatus)) {
      _pollTimer?.cancel();
      _pollTimer = null;
      if (kDebugMode) {
        debugPrint('[PaymentStatus] Definitieve status: $newStatus, polling gestopt');
      }
    } else {
      _scheduleNextPoll();
    }
  }

  /// Check of een status update een duplicaat is.
  bool _isDuplicate(String status, String? eventTimestamp) {
    if (status != _lastKnownStatus) return false;

    // Zelfde status maar met timestamp check
    if (eventTimestamp != null && _lastStatusTimestamp != null) {
      final eventTime = DateTime.tryParse(eventTimestamp);
      if (eventTime != null && eventTime.isBefore(_lastStatusTimestamp!)) {
        return true; // Oudere update, negeren
      }
    }

    return true; // Zelfde status = duplicaat
  }

  /// Is dit een definitieve (eindtoestand) status?
  bool _isFinalStatus(String status) {
    return ['paid', 'failed', 'expired', 'canceled', 'cancelled', 'refunded']
        .contains(status.toLowerCase());
  }
}
