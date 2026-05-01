/// Boeking model voor API-response.
class Booking {
  Booking({
    required this.id,
    required this.trainerName,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.status,
    this.clientName,
    this.trainerUserId,
    this.packageId,
    this.packageName,
    this.amountCents,
    this.paidAt,
    this.checkInAt,
    this.checkOutAt,
    this.sessionsRemaining,
    this.packageSessionsTotal,
    this.sessionType,
    this.noShowReason,
    this.noShowEvidenceUrl,
    this.noShowNote,
    this.noShowFeeCents,
    this.locationName,
    // Safe Session velden
    this.safeSessionActive = false,
    this.safeSessionStartedAt,
    this.safeSessionExpectedEndAt,
  });

  final String id;
  final String trainerName;
  final String? clientName;
  final DateTime scheduledAt;
  final int durationMinutes;
  final String status;
  final String? trainerUserId;
  final String? packageId;
  final String? packageName;
  final int? amountCents;
  final DateTime? paidAt;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
  final int? sessionsRemaining;
  final int? packageSessionsTotal;
  final String? noShowReason;
  final String? noShowEvidenceUrl;
  final String? noShowNote;
  final String? sessionType;
  final int? noShowFeeCents;
  final String? locationName;

  // Safe Session
  final bool safeSessionActive;
  final DateTime? safeSessionStartedAt;
  final DateTime? safeSessionExpectedEndAt;

  bool get isUpcoming =>
      scheduledAt.isAfter(DateTime.now()) && status != 'cancelled';
  bool get isPast => scheduledAt
      .add(Duration(minutes: durationMinutes))
      .isBefore(DateTime.now());
  bool get isCheckedIn =>
      status == 'checked_in' || checkInAt != null;

  factory Booking.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      final s = v.toString();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    final scheduled = parseDate(json['scheduled_at'] ?? json['scheduledAt']);
    return Booking(
      id: (json['id'] ?? '').toString(),
      trainerName: (json['trainer_name'] ?? json['trainerName'] ?? '')
          .toString(),
      clientName: json['client_name']?.toString().trim(),
      scheduledAt: scheduled ?? DateTime.now(),
      durationMinutes:
          parseInt(json['duration_minutes'] ?? json['durationMinutes']) ?? 60,
      status: (json['status'] ?? 'pending').toString(),
      trainerUserId:
          json['trainer_user_id'] ?? json['trainerUserId']?.toString(),
      packageId: json['package_id'] ?? json['packageId']?.toString(),
      packageName: json['package_name'] ?? json['packageName']?.toString(),
      amountCents: parseInt(json['amount_cents'] ?? json['amountCents']),
      paidAt: parseDate(json['paid_at'] ?? json['paidAt']),
      checkInAt: parseDate(json['check_in_at'] ?? json['checkInAt']),
      checkOutAt: parseDate(json['check_out_at'] ?? json['checkOutAt']),
      sessionsRemaining: parseInt(
        json['sessions_remaining'] ?? json['sessionsRemaining'],
      ),
      packageSessionsTotal: parseInt(
        json['package_sessions_total'] ??
            json['packageSessionsTotal'] ??
            json['sessions_total'],
      ),
      sessionType: (json['session_type'] ?? json['sessionType'] ??
              json['lesson_type'] ?? json['lessonType'])
          ?.toString()
          .trim(),
      noShowReason:
          (json['no_show_reason'] ?? json['noShowReason'])?.toString().trim(),
      noShowEvidenceUrl: (json['no_show_evidence_url'] ??
              json['noShowEvidenceUrl'] ??
              json['evidence_url'])
          ?.toString()
          .trim(),
      noShowNote:
          (json['no_show_note'] ?? json['noShowNote'])?.toString().trim(),
      noShowFeeCents: parseInt(
        json['no_show_fee_cents'] ??
            json['noShowFeeCents'] ??
            json['late_cancel_fee_cents'],
      ),
      locationName: (json['location_name'] ?? json['locationName'] ??
              json['gym_name'] ?? json['gymName'] ??
              json['venue'] ?? json['location'])
          ?.toString()
          .trim(),
      // Safe Session
      safeSessionActive: json['safe_session_active'] == true ||
          json['safeSessionActive'] == true ||
          json['safe_session_active'] == 1,
      safeSessionStartedAt: parseDate(
        json['safe_session_started_at'] ?? json['safeSessionStartedAt'],
      ),
      safeSessionExpectedEndAt: parseDate(
        json['safe_session_expected_end_at'] ??
            json['safeSessionExpectedEndAt'],
      ),
    );
  }
}
