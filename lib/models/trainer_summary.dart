import 'booking.dart';

/// Samenvatting voor trainer-dashboard (API-response).
class TrainerSummary {
  const TrainerSummary({
    required this.pendingCount,
    required this.upcomingCount,
    required this.thisWeekCount,
    required this.completedCount,
    required this.revenueCents,
    required this.upcomingBookings,
    this.weekGoal,
  });

  final int pendingCount;
  final int upcomingCount;
  final int thisWeekCount;
  final int completedCount;
  final int revenueCents;
  final List<Booking> upcomingBookings;
  /// Configurable week goal from trainer settings (null = API doesn't supply it yet).
  final int? weekGoal;

  static TrainerSummary fromJson(Map<String, dynamic> json) {
    final upcoming = (json['upcoming_bookings'] as List<dynamic>? ?? [])
        .map((e) => Booking.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return TrainerSummary(
      pendingCount: json['pending_count'] as int? ?? 0,
      upcomingCount: json['upcoming_count'] as int? ?? 0,
      thisWeekCount: json['this_week_count'] as int? ?? 0,
      completedCount: json['completed_count'] as int? ?? 0,
      revenueCents: json['revenue_cents'] as int? ?? 0,
      upcomingBookings: upcoming,
      weekGoal: json['week_goal'] as int?,
    );
  }
}
