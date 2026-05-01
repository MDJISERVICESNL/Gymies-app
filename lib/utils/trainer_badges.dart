import 'package:flutter/material.dart';

import '../config/ui_constants.dart';
import '../models/trainer.dart';
import '../theme/gymies_theme.dart';

/// Badge-definitie voor trainerprofiel.
class TrainerBadge {
  const TrainerBadge({
    required this.id,
    required this.label,
    required this.color,
    this.icon,
    this.priority,
  });

  final String id;
  final String label;
  final Color color;
  final IconData? icon;
  /// Lagere waarde = hogere prioriteit (1 = eerst op kaart).
  final int? priority;

  @override
  String toString() => 'TrainerBadge($id: $label)';
}

/// Badge-IDs voor voorkeuren. Prijs (price) wordt altijd getoond.
const String kBadgeIdPrice = 'price';

/// Badge-logica: welke badges een trainer krijgt.
class TrainerBadges {
  TrainerBadges._();

  /// Alle badges voor het volledige profiel (Wrap).
  /// Prijs-badge blijft altijd staan. Andere badges worden gefilterd op visibleBadgeIds.
  /// Bij null/leeg visibleBadgeIds: alle badges tonen (backward compat).
  static List<TrainerBadge> all(Trainer t) {
    final list = <TrainerBadge>[];
    list.addAll(_priorityBadges(t));
    list.addAll(_trustBadges(t));
    list.addAll(_expertiseBadges(t));
    list.addAll(_logisticsBadges(t));
    list.addAll(_activityBadges(t));
    final visible = t.visibleBadgeIds;
    if (visible != null) {
      return list
          .where((b) => b.id == kBadgeIdPrice || visible.contains(b.id))
          .toList();
    }
    return list;
  }

  /// Max 4 badges voor de profielkaart in zoekresultaten.
  /// Prijs en Geverifieerd altijd prioriteit.
  static List<TrainerBadge> forCard(Trainer t) {
    final allBadges = all(t);
    final prioritized = <TrainerBadge>[];
    for (final b in allBadges) {
      if (prioritized.length >= 4) break;
      prioritized.add(b);
    }
    return prioritized;
  }

  static List<TrainerBadge> _priorityBadges(Trainer t) {
    final list = <TrainerBadge>[];
    list.add(TrainerBadge(
      id: kBadgeIdPrice,
      label: t.priceBadgeLabel,
      color: GymiesColors.darkBlue,
      priority: 1,
    ));
    // Alleen trainerVerified telt — emailVerified is een basis-stap die
    // iedere gebruiker doorloopt en geen badge rechtvaardigt.
    if (t.trainerVerified) {
      list.add(TrainerBadge(
        id: 'verified',
        label: 'Geverifieerd',
        color: Colors.green.shade700,
        icon: Icons.verified,
        priority: 2,
      ));
    }
    if (t.woman2woman) {
      list.add(TrainerBadge(
        id: 'woman2woman',
        label: 'WOMAN2WOMAN',
        color: Colors.purple.shade700,
        priority: 3,
      ));
    }
    if (t.isAmbassador) {
      list.add(TrainerBadge(
        id: 'ambassador',
        label: 'Ambassadeur',
        color: Colors.purple.shade700,
        icon: Icons.military_tech,
        priority: 3,
      ));
    }
    // Tier-badges: alleen de huidige tier tonen
    if (t.tierNormalized == 'pro') {
      list.add(TrainerBadge(
        id: 'pro',
        label: 'Pro Trainer',
        color: Colors.blue.shade700,
        icon: Icons.check_circle,
        priority: 4,
      ));
    } else if (t.tierNormalized == 'pro_plus') {
      list.add(TrainerBadge(
        id: 'pro_plus',
        label: 'Pro+',
        color: UiConstants.badgeProPlusColor,
        icon: Icons.workspace_premium,
        priority: 4,
      ));
    } else if (t.tierNormalized == 'studio') {
      list.add(TrainerBadge(
        id: 'studio',
        label: 'Studio',
        color: UiConstants.badgeProPlusColor,
        icon: Icons.fitness_center,
        priority: 4,
      ));
    }
    // "Verified Trainer" badge alleen als de trainer daadwerkelijk
    // geverifieerd is — niet automatisch bij Pro+.
    if (t.trainerVerified &&
        (t.tierNormalized == 'pro_plus' || t.tierNormalized == 'studio')) {
      list.add(TrainerBadge(
        id: 'verified_trainer',
        label: 'Verified Trainer',
        color: Colors.blue.shade800,
        icon: Icons.verified,
        priority: 5,
      ));
    }
    return list;
  }

  static List<TrainerBadge> _trustBadges(Trainer t) {
    final list = <TrainerBadge>[];
    if (t.rating != null &&
        t.rating! >= 4.8 &&
        (t.reviewCount ?? 0) >= 10) {
      list.add(TrainerBadge(
        id: 'top_rated',
        label: 'Topbeoordeeld',
        color: UiConstants.badgeTopRatedColor,
      ));
    }
    if ((t.clientsWith5PlusSessions ?? 0) > 0) {
      list.add(TrainerBadge(
        id: 'favorite',
        label: 'Favoriet',
        color: Colors.pink.shade600,
        icon: Icons.favorite,
      ));
    }
    if (t.avgResponseMinutes != null && t.avgResponseMinutes! <= 60) {
      list.add(TrainerBadge(
        id: 'fast_responder',
        label: 'Snelste Responder',
        color: Colors.lightBlue.shade600,
        icon: Icons.schedule,
      ));
    }
    return list;
  }

  static List<TrainerBadge> _expertiseBadges(Trainer t) {
    final list = <TrainerBadge>[];
    if (t.diplomaVerified) {
      list.add(TrainerBadge(
        id: 'diploma',
        label: 'Gediplomeerd',
        color: UiConstants.badgeDiplomaColor,
        icon: Icons.school,
      ));
    }
    final spec = (t.specialistCategory ?? '').trim();
    if (spec.isNotEmpty) {
      list.add(TrainerBadge(
        id: 'specialist',
        label: spec,
        color: Colors.indigo.shade700,
        icon: Icons.star,
      ));
    }
    if ((t.totalSessions ?? 0) >= 100) {
      list.add(TrainerBadge(
        id: 'sessions_100',
        label: '100+ Sessies',
        color: UiConstants.badgeSessions100Color,
        icon: Icons.emoji_events,
      ));
    }
    return list;
  }

  static List<TrainerBadge> _logisticsBadges(Trainer t) {
    final list = <TrainerBadge>[];
    if (t.hasOwnLocation) {
      list.add(TrainerBadge(
        id: 'own_location',
        label: 'Eigen Locatie',
        color: Colors.teal.shade700,
        icon: Icons.home_work,
      ));
    }
    if (t.offersDuoTraining) {
      list.add(TrainerBadge(
        id: 'duo_training',
        label: 'Duo-Training',
        color: Colors.orange.shade700,
        icon: Icons.groups,
      ));
    }
    if (t.hasIntroOffer) {
      list.add(TrainerBadge(
        id: 'intro_offer',
        label: 'Introductiekorting',
        color: Colors.green.shade600,
        icon: Icons.local_offer,
      ));
    }
    return list;
  }

  static List<TrainerBadge> _activityBadges(Trainer t) {
    final list = <TrainerBadge>[];
    if (t.profileCreatedAt != null) {
      final days = DateTime.now().difference(t.profileCreatedAt!).inDays;
      if (days <= 30) {
        list.add(TrainerBadge(
          id: 'new',
          label: 'Nieuw',
          color: Colors.cyan.shade700,
          icon: Icons.fiber_new,
        ));
      }
    }
    if ((t.bookingsThisWeek ?? 0) > 10) {
      list.add(TrainerBadge(
        id: 'popular',
        label: 'Populair',
        color: Colors.deepOrange.shade600,
        icon: Icons.trending_up,
      ));
    }
    final city = (t.city ?? '').trim();
    if (city.isNotEmpty) {
      list.add(TrainerBadge(
        id: 'location',
        label: city,
        color: Colors.grey.shade700,
        icon: Icons.location_on,
      ));
    }
    return list;
  }

  /// Lijst van alle badge-opties (id, label) voor voorkeuren-UI.
  /// Prijs wordt niet meegenomen – die staat altijd aan.
  static List<({String id, String label})> availableOptions() => [
        (id: 'verified', label: 'Geverifieerd'),
        (id: 'woman2woman', label: 'WOMAN2WOMAN'),
        (id: 'ambassador', label: 'Ambassadeur'),
        (id: 'pro', label: 'Pro Trainer'),
        (id: 'pro_plus', label: 'Pro+'),
        (id: 'studio', label: 'Studio'),
        (id: 'verified_trainer', label: 'Verified Trainer'),
        (id: 'top_rated', label: 'Topbeoordeeld'),
        (id: 'favorite', label: 'Favoriet'),
        (id: 'fast_responder', label: 'Snelste Responder'),
        (id: 'diploma', label: 'Gediplomeerd'),
        (id: 'specialist', label: 'Specialist'),
        (id: 'sessions_100', label: '100+ Sessies'),
        (id: 'own_location', label: 'Eigen Locatie'),
        (id: 'duo_training', label: 'Duo-Training'),
        (id: 'intro_offer', label: 'Introductiekorting'),
        (id: 'new', label: 'Nieuw'),
        (id: 'popular', label: 'Populair'),
        (id: 'location', label: 'Locatie (stad)'),
      ];
}

/// Pill-widget voor een enkele badge.
class TrainerBadgePill extends StatelessWidget {
  const TrainerBadgePill({
    super.key,
    required this.badge,
    this.compact = false,
  });

  final TrainerBadge badge;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: badge.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge.icon != null) ...[
            Icon(badge.icon!, size: compact ? 12 : 14, color: badge.color),
            SizedBox(width: compact ? 3 : 4),
          ],
          Text(
            badge.label,
            style: TextStyle(
              color: badge.color,
              fontWeight: FontWeight.w600,
              fontSize: compact ? 10 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
