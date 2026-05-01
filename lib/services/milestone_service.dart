import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MilestoneService
/// ────────────────
/// Detecteert en viert mijlpalen: sessie-count, reviews, streaks.
/// Triggert confetti + haptics bij bereiken van achievements.
///
/// Milestones:
/// - Eerste sessie voltooid
/// - 5, 10, 25, 50, 100 sessies
/// - Eerste review geschreven
/// - 5-sterren rating ontvangen (trainer)
/// - 7-dagen trainingstreak (client)
/// - Eerste betaling ontvangen (trainer)
///
/// Gebruik:
/// ```dart
/// final ms = context.read<MilestoneService>();
/// final milestone = ms.checkSessionMilestone(completedCount: 10);
/// if (milestone != null) {
///   showCelebration(milestone);
/// }
/// ```
class MilestoneService extends ChangeNotifier {
  MilestoneService();

  /// Set van al eerder getoonde milestones (voorkom herhalingen).
  final Set<String> _shownMilestones = {};
  bool _initialized = false;

  static const _prefsKey = 'gymies_shown_milestones';

  /// Initialiseer vanuit SharedPreferences.
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_prefsKey) ?? [];
    _shownMilestones.addAll(stored);
    _initialized = true;
  }

  /// Check of er een sessie-mijlpaal bereikt is.
  Milestone? checkSessionMilestone({required int completedCount}) {
    const milestones = [1, 5, 10, 25, 50, 100, 250, 500];
    for (final target in milestones) {
      if (completedCount == target) {
        return _createIfNew(
          id: 'sessions_$target',
          type: MilestoneType.sessions,
          title: _sessionTitle(target),
          subtitle: _sessionSubtitle(target),
          count: target,
        );
      }
    }
    return null;
  }

  /// Check of er een review-mijlpaal bereikt is.
  Milestone? checkReviewMilestone({required int reviewCount, required bool isFirst}) {
    if (isFirst) {
      return _createIfNew(
        id: 'first_review',
        type: MilestoneType.review,
        title: 'Eerste review!',
        subtitle: 'Je mening telt — bedankt voor je feedback!',
        count: 1,
      );
    }
    const milestones = [5, 10, 25];
    for (final target in milestones) {
      if (reviewCount == target) {
        return _createIfNew(
          id: 'reviews_$target',
          type: MilestoneType.review,
          title: '$target reviews geschreven!',
          subtitle: 'Je helpt andere sporters de beste trainer te vinden.',
          count: target,
        );
      }
    }
    return null;
  }

  /// Check trainer-specifieke mijlpalen.
  Milestone? checkTrainerMilestone({
    int? totalBookings,
    double? averageRating,
    int? totalEarningsCents,
    bool? firstPayment,
  }) {
    if (firstPayment == true) {
      return _createIfNew(
        id: 'first_payment',
        type: MilestoneType.payment,
        title: 'Eerste betaling!',
        subtitle: 'Je bent officieel een GYMIES trainer. Gefeliciteerd!',
        count: 1,
      );
    }

    if (averageRating != null && averageRating >= 4.9 && (totalBookings ?? 0) >= 5) {
      return _createIfNew(
        id: 'top_rated',
        type: MilestoneType.rating,
        title: 'Top-rated trainer!',
        subtitle: 'Gemiddeld ${averageRating.toStringAsFixed(1)} sterren — uitzonderlijk!',
        count: 0,
      );
    }

    if (totalBookings != null) {
      const milestones = [10, 25, 50, 100, 250, 500];
      for (final target in milestones) {
        if (totalBookings == target) {
          return _createIfNew(
            id: 'trainer_bookings_$target',
            type: MilestoneType.sessions,
            title: '$target boekingen!',
            subtitle: _trainerBookingSubtitle(target),
            count: target,
          );
        }
      }
    }

    return null;
  }

  /// Check streak-mijlpaal (client).
  Milestone? checkStreakMilestone({required int streakDays}) {
    const milestones = [7, 14, 30, 60, 100];
    for (final target in milestones) {
      if (streakDays == target) {
        return _createIfNew(
          id: 'streak_$target',
          type: MilestoneType.streak,
          title: '$target dagen streak!',
          subtitle: _streakSubtitle(target),
          count: target,
        );
      }
    }
    return null;
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Milestone? _createIfNew({
    required String id,
    required MilestoneType type,
    required String title,
    required String subtitle,
    required int count,
  }) {
    if (_shownMilestones.contains(id)) return null;

    _shownMilestones.add(id);
    _persistShown();

    return Milestone(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      count: count,
    );
  }

  Future<void> _persistShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _shownMilestones.toList());
  }

  String _sessionTitle(int count) {
    if (count == 1) return 'Eerste sessie!';
    return '$count sessies voltooid!';
  }

  String _sessionSubtitle(int count) {
    if (count == 1) return 'Je fitness-reis begint hier. Keep going!';
    if (count <= 10) return 'Je bouwt een mooie routine op!';
    if (count <= 50) return 'Serieuze toewijding — dat verdient respect!';
    return 'Ongelooflijk! Je bent een echte atleet.';
  }

  String _trainerBookingSubtitle(int count) {
    if (count <= 25) return 'Je reputatie groeit!';
    if (count <= 100) return 'Je bent een gevestigde GYMIES trainer!';
    return 'Legendarisch! Een van de actiefste trainers op GYMIES.';
  }

  String _streakSubtitle(int days) {
    if (days <= 7) return 'Een hele week consistent — sterk!';
    if (days <= 30) return 'Een maand lang elke week getraind!';
    return 'Onbreekbaar! Jouw discipline is inspirerend.';
  }
}

// ── Data ────────────────────────────────────────────────────────────────

enum MilestoneType { sessions, review, payment, rating, streak }

class Milestone {
  const Milestone({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.count,
  });

  final String id;
  final MilestoneType type;
  final String title;
  final String subtitle;
  final int count;

  /// Emoji voor het type milestone.
  String get emoji {
    switch (type) {
      case MilestoneType.sessions:
        return '🏋️';
      case MilestoneType.review:
        return '⭐';
      case MilestoneType.payment:
        return '💰';
      case MilestoneType.rating:
        return '🏆';
      case MilestoneType.streak:
        return '🔥';
    }
  }
}
