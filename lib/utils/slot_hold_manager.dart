import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/gymies_api.dart';

/// SlotHoldManager
/// ────────────────
/// Beheert slot-reserveringen met zichtbare countdown, waarschuwing
/// bij bijna-verlopen, en auto-extend bij netwerkherstel.
///
/// Lost het probleem op dat gebruikers in ClientTrainerProfileScreen
/// hun slot kwijtraken bij traag internet zonder waarschuwing.
///
/// Gebruik:
/// ```dart
/// final manager = SlotHoldManager(api: api);
///
/// // Slot vasthouden
/// await manager.hold(trainerId: 42, slotDate: '2026-05-10', slotTime: '14:00');
///
/// // Luister naar state
/// manager.addListener(() {
///   print('Resterend: ${manager.remainingSeconds}s');
///   if (manager.isWarning) showWarning();
///   if (manager.isExpired) handleExpired();
/// });
///
/// // Bij betaling gestart: stop de countdown
/// manager.release();
///
/// // Vergeet niet te disposen
/// manager.dispose();
/// ```
class SlotHoldManager extends ChangeNotifier {
  SlotHoldManager({required GymiesApi api}) : _api = api;

  final GymiesApi _api;

  // ── State ────────────────────────────────────────────────────────────
  String? _holdId;
  DateTime? _expiresAt;
  Timer? _countdownTimer;
  bool _extending = false;

  /// Drempel in seconden waarna een waarschuwing wordt getoond.
  static const int warningThresholdSeconds = 30;

  /// Auto-extend marge: als er <15s over is, probeer te verlengen.
  static const int autoExtendThresholdSeconds = 15;

  /// Maximaal aantal extend pogingen.
  static const int maxExtendAttempts = 2;
  int _extendAttempts = 0;

  // ── Getters ──────────────────────────────────────────────────────────

  bool get isHolding => _holdId != null && !isExpired;
  bool get isExpired =>
      _expiresAt != null && DateTime.now().isAfter(_expiresAt!);
  bool get isWarning =>
      _expiresAt != null &&
      !isExpired &&
      remainingSeconds <= warningThresholdSeconds;
  bool get isExtending => _extending;
  String? get holdId => _holdId;

  int get remainingSeconds {
    if (_expiresAt == null) return 0;
    final diff = _expiresAt!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  /// Formatteert resterende tijd als "M:SS".
  String get remainingFormatted {
    final s = remainingSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  // ── Publieke API ─────────────────────────────────────────────────────

  /// Reserveer een slot. Retourneert true bij succes.
  Future<bool> hold({
    required int trainerId,
    required DateTime scheduledAt,
    String? availabilitySlotId,
  }) async {
    try {
      final result = await _api.holdTrainerPublicSlot(
        trainerUserId: trainerId.toString(),
        scheduledAt: scheduledAt,
        availabilitySlotId: availabilitySlotId,
      );

      _holdId = (result['hold_id'] ?? result['id'] ?? '').toString();
      final expiresIn =
          int.tryParse((result['expires_in'] ?? '300').toString()) ?? 300;
      _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
      _extendAttempts = 0;
      _startCountdown();
      notifyListeners();

      if (kDebugMode) {
        debugPrint(
            '[SlotHold] Slot gereserveerd: $_holdId, verloopt over ${expiresIn}s');
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[SlotHold] Hold mislukt: $e');
      return false;
    }
  }

  /// Laat het slot los (bv. bij annuleren of na betaling gestart).
  Future<void> release() async {
    _countdownTimer?.cancel();
    _countdownTimer = null;

    if (_holdId != null) {
      try {
        await _api.releaseSlotHold(_holdId!);
      } catch (e) {
        if (kDebugMode) debugPrint('[SlotHold] Release mislukt (ok): $e');
      }
    }

    _holdId = null;
    _expiresAt = null;
    _extendAttempts = 0;
    notifyListeners();
  }

  /// Probeer het slot te verlengen (handmatig of automatisch).
  Future<bool> extend() async {
    if (_holdId == null || _extending) return false;
    if (_extendAttempts >= maxExtendAttempts) {
      if (kDebugMode) {
        debugPrint('[SlotHold] Max extend pogingen bereikt');
      }
      return false;
    }

    _extending = true;
    _extendAttempts++;
    notifyListeners();

    try {
      final result = await _api.extendSlotHold(_holdId!);
      final expiresIn =
          int.tryParse((result['expires_in'] ?? '300').toString()) ?? 300;
      _expiresAt = DateTime.now().add(Duration(seconds: expiresIn));

      if (kDebugMode) {
        debugPrint('[SlotHold] Slot verlengd, nog ${expiresIn}s');
      }

      _extending = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[SlotHold] Extend mislukt: $e');
      _extending = false;
      notifyListeners();
      return false;
    }
  }

  // ── Countdown ────────────────────────────────────────────────────────

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isExpired) {
        _countdownTimer?.cancel();
        _countdownTimer = null;
        if (kDebugMode) debugPrint('[SlotHold] Slot verlopen!');
        notifyListeners();
        return;
      }

      // Auto-extend bij bijna-verlopen
      if (remainingSeconds <= autoExtendThresholdSeconds &&
          !_extending &&
          _extendAttempts < maxExtendAttempts) {
        if (kDebugMode) {
          debugPrint(
              '[SlotHold] Auto-extend poging (${remainingSeconds}s resterend)');
        }
        extend(); // fire-and-forget
      }

      notifyListeners();
    });
  }

  // ── Lifecycle ────────────────────────────────────────────────────────

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}
