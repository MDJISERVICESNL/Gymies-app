/// Omzet & uitbetalingen (API-response).
class TrainerRevenue {
  const TrainerRevenue({
    required this.totalRevenueCents,
    required this.paidRevenueCents,
    required this.pendingPayoutCents,
    required this.monthlyRevenueCents,
    required this.items,
  });

  final int totalRevenueCents;
  final int paidRevenueCents;
  final int pendingPayoutCents;
  final Map<String, int> monthlyRevenueCents;
  final List<TrainerRevenueItem> items;

  static TrainerRevenue fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final monthlyRaw = json['monthly_revenue_cents'] as Map? ?? {};
    final monthly = <String, int>{};
    for (final e in monthlyRaw.entries) {
      monthly[e.key.toString()] = toInt(e.value);
    }
    final items = (json['items'] is List ? json['items'] as List : const [])
        .map(
          (e) => e is Map
              ? TrainerRevenueItem.fromJson(Map<String, dynamic>.from(e))
              : null,
        )
        .whereType<TrainerRevenueItem>()
        .toList();
    return TrainerRevenue(
      totalRevenueCents: toInt(json['total_revenue_cents']),
      paidRevenueCents: toInt(json['paid_revenue_cents']),
      pendingPayoutCents: toInt(json['pending_payout_cents']),
      monthlyRevenueCents: monthly,
      items: items,
    );
  }
}

class TrainerRevenueItem {
  const TrainerRevenueItem({
    required this.id,
    required this.scheduledAt,
    required this.status,
    required this.amountCents,
    this.paidAt,
    this.bookingId,
    this.paymentMethod,
    this.paymentReference,
    this.paymentStatus,
  });

  final String id;
  final String scheduledAt;
  final String status;
  final int amountCents;
  final String? paidAt;
  final String? bookingId;
  final String? paymentMethod;
  final String? paymentReference;
  final String? paymentStatus;

  static TrainerRevenueItem fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return TrainerRevenueItem(
      id: json['id']?.toString() ?? '',
      scheduledAt: json['scheduled_at']?.toString() ?? '',
      status: json['status'] as String? ?? 'pending',
      amountCents: toInt(json['amount_cents']),
      paidAt: json['paid_at'] as String?,
      bookingId: json['booking_id']?.toString(),
      paymentMethod:
          json['payment_method']?.toString() ?? json['method']?.toString(),
      paymentReference:
          json['payment_reference']?.toString() ??
          json['reference_id']?.toString(),
      paymentStatus:
          json['payment_status']?.toString() ??
          json['mollie_status']?.toString(),
    );
  }
}

/// Gesprek trainer–klant.
class TrainerConversation {
  const TrainerConversation({
    required this.id,
    required this.clientUserId,
    required this.clientName,
    this.bookingId,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String id;
  final String clientUserId;
  final String clientName;
  final String? bookingId;
  final String? lastMessage;
  final String? lastMessageAt;
  final int unreadCount;

  static TrainerConversation fromJson(Map<String, dynamic> json) {
    return TrainerConversation(
      id: json['id']?.toString() ?? '',
      clientUserId: json['client_user_id']?.toString() ?? '',
      clientName: json['client_name'] as String? ?? 'Klant',
      bookingId: json['booking_id']?.toString(),
      lastMessage: json['last_message'] as String?,
      lastMessageAt: json['last_message_at'] as String?,
      unreadCount: int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
    );
  }
}

class TrainerMessage {
  const TrainerMessage({
    required this.id,
    required this.conversationId,
    required this.senderType,
    required this.body,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String conversationId;
  final String senderType;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isFromTrainer => senderType.toLowerCase() == 'trainer';

  static TrainerMessage fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic raw) {
      final v = raw?.toString() ?? '';
      return DateTime.tryParse(v) ?? DateTime.now();
    }

    DateTime? parseNullableDate(dynamic raw) {
      final v = raw?.toString() ?? '';
      if (v.isEmpty) return null;
      return DateTime.tryParse(v);
    }

    return TrainerMessage(
      id: json['id']?.toString() ?? '',
      conversationId:
          json['conversation_id']?.toString() ??
          json['conversationId']?.toString() ??
          '',
      senderType:
          json['sender_type']?.toString() ??
          json['senderType']?.toString() ??
          'client',
      body: json['body']?.toString() ?? '',
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
      readAt: parseNullableDate(json['read_at'] ?? json['readAt']),
    );
  }
}

class TrainerAvailabilitySlot {
  const TrainerAvailabilitySlot({
    required this.id,
    required this.weekday,
    required this.startTime,
    required this.endTime,
    this.isActive = true,
  });

  final String id;
  final int weekday; // 1 = maandag ... 7 = zondag
  final String startTime; // HH:mm
  final String endTime; // HH:mm
  final bool isActive;

  static TrainerAvailabilitySlot fromJson(Map<String, dynamic> json) {
    return TrainerAvailabilitySlot(
      id: json['id']?.toString() ?? '',
      weekday: int.tryParse(json['weekday']?.toString() ?? '') ?? 1,
      startTime: json['start_time']?.toString() ?? '09:00',
      endTime: json['end_time']?.toString() ?? '17:00',
      isActive: json['is_active'] == null ? true : json['is_active'] == true,
    );
  }
}

class TrainerAvailabilityException {
  const TrainerAvailabilityException({
    required this.id,
    required this.date,
    this.reason,
  });

  final String id;
  final DateTime date;
  final String? reason;

  static TrainerAvailabilityException fromJson(Map<String, dynamic> json) {
    final rawDate =
        json['date']?.toString() ?? json['blocked_date']?.toString();
    final date = DateTime.tryParse(rawDate ?? '') ?? DateTime.now();
    return TrainerAvailabilityException(
      id: json['id']?.toString() ?? '',
      date: date,
      reason: json['reason']?.toString(),
    );
  }
}
