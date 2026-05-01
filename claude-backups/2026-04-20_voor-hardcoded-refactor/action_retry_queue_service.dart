import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'gymies_api.dart';

class ActionRetryQueueService {
  static const _kQueueKey = 'gymies_action_retry_queue_v1';
  static const _kHistoryKey = 'gymies_action_history_v1';
  static const _kMaxHistory = 250;

  static Future<void> enqueue({
    required String actionType,
    required Map<String, dynamic> payload,
    String? reason,
  }) async {
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
  }

  static Future<void> log({
    required String actionType,
    required String status,
    Map<String, dynamic>? payload,
    String? detail,
  }) async {
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
  }

  static Future<List<Map<String, dynamic>>> getQueue() async {
    return _readList(_kQueueKey);
  }

  static Future<Map<String, int>> getQueueStats() async {
    final queue = await _readList(_kQueueKey);
    var pending = 0;
    var failed = 0;
    var highRetry = 0;
    for (final item in queue) {
      final status = (item['status'] ?? 'pending').toString().toLowerCase();
      if (status == 'failed') {
        failed += 1;
      } else {
        pending += 1;
      }
      if (_toInt(item['retries']) >= 3) highRetry += 1;
    }
    return {
      'total': queue.length,
      'pending': pending,
      'failed': failed,
      'high_retry': highRetry,
    };
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
  }

  static Future<void> _writeList(
    String key,
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(items));
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
