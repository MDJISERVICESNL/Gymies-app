import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/timing_constants.dart';
import 'gymies_api.dart';

class ActionRetryQueueService {
  static const _kQueueKey = 'gymies_action_retry_queue_v1';
  static const _kHistoryKey = 'gymies_action_history_v1';
  static const _kMaxHistory = TimingConstants.maxRetryHistory;

  static Future<void> enqueue({
    required String actionType,
    required Map<String, dynamic> payload,
    String? reason,
  }) async {
    try {
      // BUG FIX: Add try-catch to prevent crashes during enqueue
      final queue = await _readList(_kQueueKey);
      final now = DateTime.now().toIso8601String();
      queue.add({
        'id': '${DateTime.now().millisecondsSinceEpoch}_$actionType',
        'action_type': actionType,
        'payload': payload,
        'status': 'pending',
        'retries': 0,
        'created_at': now,
        'updated_at': now,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });
      await _writeList(_kQueueKey, queue);
      await log(
        actionType: actionType,
        status: 'queued',
        payload: payload,
        detail: reason ?? 'Actie in wachtrij geplaatst',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ActionRetryQueue] enqueue error: $e');
    }
  }

  static Future<void> log({
    required String actionType,
    required String status,
    Map<String, dynamic>? payload,
    String? detail,
  }) async {
    try {
      // BUG FIX: Add try-catch to prevent crashes in logging
      final items = await _readList(_kHistoryKey);
      items.add({
        'id': '${DateTime.now().millisecondsSinceEpoch}_${status}_$actionType',
        'action_type': actionType,
        'status': status,
        'created_at': DateTime.now().toIso8601String(),
        ...?(payload == null ? null : {'payload': payload}),
        if (detail != null && detail.trim().isNotEmpty) 'detail': detail.trim(),
      });
      if (items.length > _kMaxHistory) {
        items.removeRange(0, items.length - _kMaxHistory);
      }
      await _writeList(_kHistoryKey, items);
    } catch (e) {
      if (kDebugMode) debugPrint('[ActionRetryQueue] log error: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getQueue() async {
    return _readList(_kQueueKey);
  }

  static Future<Map<String, int>> getQueueStats() async {
    final queue = await _readList(_kQueueKey);
    var pending = 0;
    var failed = 0;
    var highRetry = 0;
    int? oldestAgeSeconds;
    for (final item in queue) {
      final status = (item['status'] ?? 'pending').toString().toLowerCase();
      if (status == 'failed') {
        failed += 1;
      } else {
        pending += 1;
      }
      if (_toInt(item['retries']) >= 3) highRetry += 1;

      // Track oudste item
      final createdAt = DateTime.tryParse(
          (item['created_at'] ?? '').toString());
      if (createdAt != null) {
        final age = DateTime.now().difference(createdAt).inSeconds;
        if (oldestAgeSeconds == null || age > oldestAgeSeconds) {
          oldestAgeSeconds = age;
        }
      }
    }
    return {
      'total': queue.length,
      'pending': pending,
      'failed': failed,
      'high_retry': highRetry,
      'oldest_age_seconds': oldestAgeSeconds ?? 0,
    };
  }

  /// Rapporteer queue stats naar Sentry als breadcrumb.
  /// Roep dit periodiek aan (bv. bij app resume of dashboard load).
  static Future<void> reportToSentry() async {
    try {
      final stats = await getQueueStats();
      final total = stats['total'] ?? 0;
      if (total == 0) return; // Niets te rapporteren

      Sentry.addBreadcrumb(Breadcrumb(
        category: 'action_retry_queue',
        message: 'Queue: ${stats['pending']} pending, '
            '${stats['failed']} failed, '
            '${stats['high_retry']} high-retry',
        level: (stats['failed'] ?? 0) > 0
            ? SentryLevel.warning
            : SentryLevel.info,
        data: {
          'total': total,
          'pending': stats['pending'] ?? 0,
          'failed': stats['failed'] ?? 0,
          'high_retry': stats['high_retry'] ?? 0,
          'oldest_age_seconds': stats['oldest_age_seconds'] ?? 0,
        },
      ));

      // Als er >5 failed items zijn of items >1 uur oud, stuur Sentry event
      final failedCount = stats['failed'] ?? 0;
      final oldestAge = stats['oldest_age_seconds'] ?? 0;
      if (failedCount >= 5 || oldestAge > 3600) {
        Sentry.captureMessage(
          'ActionRetryQueue alert: $failedCount failed, oudste ${oldestAge}s',
          level: SentryLevel.warning,
          params: [
            'failed=$failedCount',
            'oldest_age=${oldestAge}s',
            'total=$total',
          ],
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[RetryQueue] Sentry rapportage mislukt: $e');
    }
  }

  static Future<Map<String, String>> buildIncidentSupportDraft({
    required String contextLabel,
  }) async {
    final stats = await getQueueStats();
    final queue = await getQueue();
    final failedItems = queue
        .where((e) => (e['status'] ?? '').toString().toLowerCase() == 'failed')
        .toList();
    final topFailed = failedItems.take(5).map((e) {
      final action = (e['action_type'] ?? 'unknown').toString();
      final retries = _toInt(e['retries']);
      final err = (e['last_error'] ?? '').toString();
      return '- $action · retries=$retries · error=${err.isEmpty ? '-' : err}';
    }).join('\n');

    final subject =
        '[Incident][$contextLabel] Retry failures=${stats['failed'] ?? 0}';
    final body = '''
Automatische incidentmelding vanuit app.

Context: $contextLabel
Queue totaal: ${stats['total'] ?? 0}
Queue pending: ${stats['pending'] ?? 0}
Queue failed: ${stats['failed'] ?? 0}
High retry (>=3): ${stats['high_retry'] ?? 0}

Top failed acties:
${topFailed.isEmpty ? '- geen details' : topFailed}
''';
    return {
      'type': 'other',
      'subject': subject,
      'message': body.trim(),
      'booking_id': '',
      'invoice_id': '',
    };
  }

  static Future<List<Map<String, dynamic>>> getHistory() async {
    final items = await _readList(_kHistoryKey);
    items.sort((a, b) {
      final ad = DateTime.tryParse((a['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bd = DateTime.tryParse((b['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return items;
  }

  static Future<int> flushPending(GymiesApi api) async {
    final queue = await _readList(_kQueueKey);
    if (queue.isEmpty) return 0;
    var successCount = 0;
    final remaining = <Map<String, dynamic>>[];
    for (final item in queue) {
      final actionType = (item['action_type'] ?? '').toString();
      final payload = _asMap(item['payload']) ?? <String, dynamic>{};
      try {
        await _executeAction(api, actionType, payload);
        successCount += 1;
        await log(
          actionType: actionType,
          status: 'sent',
          payload: payload,
          detail: 'Opnieuw verstuurd en gelukt',
        );
      } catch (e) {
        final retries = _toInt(item['retries']) + 1;
        remaining.add({
          ...item,
          'status': 'failed',
          'retries': retries,
          'last_error': e.toString(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        await log(
          actionType: actionType,
          status: 'failed',
          payload: payload,
          detail: e.toString(),
        );
      }
    }
    await _writeList(_kQueueKey, remaining);

    // Rapporteer resultaat naar Sentry
    if (successCount > 0 || remaining.isNotEmpty) {
      Sentry.addBreadcrumb(Breadcrumb(
        category: 'action_retry_queue',
        message: 'Flush: $successCount geslaagd, ${remaining.length} resterend',
        level: remaining.isNotEmpty ? SentryLevel.warning : SentryLevel.info,
        data: {
          'flushed': successCount,
          'remaining': remaining.length,
          'total_processed': queue.length,
        },
      ));
    }

    return successCount;
  }

  static Future<void> _executeAction(
    GymiesApi api,
    String actionType,
    Map<String, dynamic> payload,
  ) async {
    switch (actionType) {
      case 'trainer_check_in':
        await api.markBookingCheckedIn(
          bookingId: (payload['booking_id'] ?? '').toString(),
          qrToken: (payload['token'] ?? '').toString().isEmpty
              ? null
              : (payload['token'] ?? '').toString(),
          payload: (payload['payload'] ?? '').toString().isEmpty
              ? null
              : (payload['payload'] ?? '').toString(),
          source: 'retry_queue',
        );
        return;
      case 'trainer_no_show':
        await api.markTrainerBookingNoShow(
          bookingId: (payload['booking_id'] ?? '').toString(),
          reason: (payload['reason'] ?? '').toString(),
          note: (payload['note'] ?? '').toString().isEmpty
              ? null
              : (payload['note'] ?? '').toString(),
          evidenceUrl: (payload['evidence_url'] ?? '').toString().isEmpty
              ? null
              : (payload['evidence_url'] ?? '').toString(),
        );
        return;
      case 'support_ticket':
        await api.createSupportTicket(
          type: (payload['type'] ?? 'booking').toString(),
          subject: (payload['subject'] ?? '').toString(),
          message: (payload['message'] ?? '').toString(),
          bookingId: (payload['booking_id'] ?? '').toString().isEmpty
              ? null
              : (payload['booking_id'] ?? '').toString(),
          invoiceId: (payload['invoice_id'] ?? '').toString().isEmpty
              ? null
              : (payload['invoice_id'] ?? '').toString(),
        );
        return;
    }
    throw Exception('Onbekend actie-type: $actionType');
  }

  static Future<List<Map<String, dynamic>>> _readList(String key) async {
    try {
      // BUG FIX: Add try-catch for SharedPreferences.getInstance() which can throw
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return <Map<String, dynamic>>[];
        return decoded.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
      } catch (_) {
        return <Map<String, dynamic>>[];
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ActionRetryQueue] _readList error: $e');
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> _writeList(
    String key,
    List<Map<String, dynamic>> items,
  ) async {
    try {
      // BUG FIX: Add try-catch for SharedPreferences operations
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(items));
    } catch (e) {
      if (kDebugMode) debugPrint('[ActionRetryQueue] _writeList error: $e');
      // Fail-open: log the error but don't crash
    }
  }

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
