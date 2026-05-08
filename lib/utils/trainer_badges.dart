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

/// Badges die trainers NIET kunnen uitzetten — altijd zichtbaar als ze kwalificeren.
const Set<String> kAlwaysVisibleBadgeIds = {
  kBadgeIdPrice,
  'verified',
  'founding_partner',
  'verified_trainer',
};

/// Max badges op het volledige profiel (Wrap). Kaart gebruikt forCard() met max 4.
const int kMaxProfileBadges = 6;

/// Badge-logica: welke badges een trainer krijgt.
class TrainerBadges {
  TrainerBadges._();

  /// Alle badges voor het volledige profiel (Wrap).
  /// Always-visible badges (prijs, verified, founding partner) staan altijd aan.
  /// Overige badges worden gefilterd op visibleBadgeIds.
  /// Bij null/leeg visibleBadgeIds: alle badges tonen (backward compat).
  /// Resultaat is beperkt tot [kMaxProfileBadges] (6).
  static List<TrainerBadge> all(Trainer t) {
    final list = <TrainerBadge>[];
    list.addAll(_priorityBadges(t));
    list.addAll(_trustBadges(t));
    list.addAll(_expertiseBadges(t));
    list.addAll(_logisticsBadges(t));
    list.addAll(_activityBadges(t));
    final visible = t.visibleBadgeIds;
    List<TrainerBadge> filtered;
    if (visible != null) {
      filtered = list
          .where((b) =>
              kAlwaysVisibleBadgeIds.contains(b.id) ||
              visible.contains(b.id))
          .toList();
    } else {
      filtered = list;
    }
    // Beperk tot max badges op profiel
    if (filtered.length > kMaxProfileBadges) {
      filtered = filtered.sublist(0, kMaxProfileBadges);
    }
    return filtered;
  }

  /// Max 4 badges voor de profielkaart in zoekresultaten.
  /// Always-visible badges krijgen voorrang.
  static List<TrainerBadge> forCard(Trainer t) {
    final allBadges = all(t);
    final prioritized = <TrainerBadge>[];
    for (final b in allBadges) {
      if (prioritized.length >= 4) break;
      prioritized.add(b);
    }
    return prioritized;
  }

  /// Badges die de trainer kan togglen in voorkeuren.
  /// Always-visible badges worden uitgesloten (die staan altijd aan).
  static List<({String id, String label})> toggleableOptions() {
    return availableOptions()
        .where((o) => !kAlwaysVisibleBadgeIds.contains(o.id))
        .toList();
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
    if (t.isFoundingPartner) {
      list.add(TrainerBadge(
        id: 'founding_partner',
        label: 'Founding Partner',
        color: GymiesColors.accent,
        icon: Icons.diamond,
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
    // Terugkerende Klanten: ≥80% klanten boekt opnieuw
    if (t.hasHighRetention) {
      list.add(TrainerBadge(
        id: 'returning_clients',
        label: 'Terugkerende Klanten',
        color: Colors.green.shade700,
        icon: Icons.repeat,
      ));
    }
    // Meest Geboekt: top 10% in regio (backend computed)
    if (t.isTopBooked) {
      list.add(TrainerBadge(
        id: 'top_booked',
        label: 'Meest Geboekt',
        color: Colors.amber.shade800,
        icon: Icons.local_fire_department,
      ));
    }
    // Eerste Sessie Gratis
    if (t.hasFreeTrial) {
      list.add(TrainerBadge(
        id: 'free_trial',
        label: 'Eerste Sessie Gratis',
        color: Colors.green.shade600,
        icon: Icons.card_giftcard,
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
    // Sessie milestones
    if ((t.totalSessions ?? 0) >= 500) {
      list.add(TrainerBadge(
        id: 'sessions_500',
        label: '500+ Sessies',
        color: Colors.amber.shade900,
        icon: Icons.emoji_events,
      ));
    } else if ((t.totalSessions ?? 0) >= 100) {
      list.add(TrainerBadge(
        id: 'sessions_100',
        label: '100+ Sessies',
        color: UiConstants.badgeSessions100Color,
        icon: Icons.emoji_events,
      ));
    }
    // Doelgroep-specialisaties (op basis van categories/tags)
    if (t.isSeniorenSpecialist) {
      list.add(TrainerBadge(
        id: 'senioren',
        label: 'Senioren Specialist',
        color: Colors.brown.shade600,
        icon: Icons.elderly,
      ));
    }
    if (t.isRevalidatieSpecialist) {
      list.add(TrainerBadge(
        id: 'revalidatie',
        label: 'Revalidatie',
        color: Colors.teal.shade600,
        icon: Icons.healing,
      ));
    }
    if (t.isZwangerschapSpecialist) {
      list.add(TrainerBadge(
        id: 'zwangerschap',
        label: 'Zwangerschap',
        color: Colors.pink.shade400,
        icon: Icons.pregnant_woman,
      ));
    }
    if (t.isJeugdSpecialist) {
      list.add(TrainerBadge(
        id: 'jeugd',
        label: 'Jeugd',
        color: Colors.lightGreen.shade700,
        icon: Icons.child_care,
      ));
    }
    if (t.isAfvallenSpecialist) {
      list.add(TrainerBadge(
        id: 'afvallen',
        label: 'Afvallen',
        color: Colors.lime.shade800,
        icon: Icons.monitor_weight,
      ));
    }
    if (t.isKrachtSpecialist) {
      list.add(TrainerBadge(
        id: 'krachttraining',
        label: 'Krachttraining',
        color: Colors.red.shade700,
        icon: Icons.fitness_center,
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
    // Online sessies beschikbaar
    if (t.offersOnlineSessions) {
      list.add(TrainerBadge(
        id: 'online_sessions',
        label: 'Online Beschikbaar',
        color: Colors.blue.shade600,
        icon: Icons.videocam,
      ));
    }
    // Flexibele tijden (avond/weekend)
    if (t.hasFlexibleHours) {
      list.add(TrainerBadge(
        id: 'flexible_hours',
        label: 'Flexibele Tijden',
        color: Colors.purple.shade500,
        icon: Icons.access_time,
      ));
    }
    // Zelfde dag beschikbaar (last-minute bookings)
    if (t.sameDayBooking) {
      list.add(TrainerBadge(
        id: 'same_day',
        label: 'Zelfde Dag Beschikbaar',
        color: Colors.orange.shade600,
        icon: Icons.bolt,
      ));
    }
    // Gratis annuleren
    if (t.hasFreeCancellation) {
      list.add(TrainerBadge(
        id: 'free_cancellation',
        label: 'Gratis Annuleren',
        color: Colors.green.shade500,
        icon: Icons.event_available,
      ));
    }
    return list;
  }

  static List<TrainerBadge> _activityBadges(Trainer t) {
    final list = <TrainerBadge>[];
    final days = t.daysOnPlatform;
    // Nieuw vs loyaliteitsbadges: wederzijds exclusief
    if (days <= 30 && t.profileCreatedAt != null) {
      list.add(TrainerBadge(
        id: 'new',
        label: 'Nieuw',
        color: Colors.cyan.shade700,
        icon: Icons.fiber_new,
      ));
    } else if (days >= 730) {
      list.add(TrainerBadge(
        id: 'years_2',
        label: '2 Jaar op Gymies',
        color: GymiesColors.accent,
        icon: Icons.workspace_premium,
      ));
    } else if (days >= 365) {
      list.add(TrainerBadge(
        id: 'years_1',
        label: '1 Jaar op Gymies',
        color: Colors.blueGrey.shade700,
        icon: Icons.cake,
      ));
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
        // Priority / status
        (id: 'verified', label: 'Geverifieerd'),
        (id: 'woman2woman', label: 'WOMAN2WOMAN'),
        (id: 'ambassador', label: 'Ambassadeur'),
        (id: 'founding_partner', label: 'Founding Partner'),
        (id: 'pro', label: 'Pro Trainer'),
        (id: 'pro_plus', label: 'Pro+'),
        (id: 'studio', label: 'Studio'),
        (id: 'verified_trainer', label: 'Verified Trainer'),
        // Trust & social proof
        (id: 'top_rated', label: 'Topbeoordeeld'),
        (id: 'favorite', label: 'Favoriet'),
        (id: 'fast_responder', label: 'Snelste Responder'),
        (id: 'returning_clients', label: 'Terugkerende Klanten'),
        (id: 'top_booked', label: 'Meest Geboekt'),
        (id: 'free_trial', label: 'Eerste Sessie Gratis'),
        // Expertise
        (id: 'diploma', label: 'Gediplomeerd'),
        (id: 'specialist', label: 'Specialist'),
        (id: 'sessions_100', label: '100+ Sessies'),
        (id: 'sessions_500', label: '500+ Sessies'),
        (id: 'senioren', label: 'Senioren Specialist'),
        (id: 'revalidatie', label: 'Revalidatie'),
        (id: 'zwangerschap', label: 'Zwangerschap'),
        (id: 'jeugd', label: 'Jeugd'),
        (id: 'afvallen', label: 'Afvallen'),
        (id: 'krachttraining', label: 'Krachttraining'),
        // Logistics & service
        (id: 'own_location', label: 'Eigen Locatie'),
        (id: 'duo_training', label: 'Duo-Training'),
        (id: 'intro_offer', label: 'Introductiekorting'),
        (id: 'online_sessions', label: 'Online Beschikbaar'),
        (id: 'flexible_hours', label: 'Flexibele Tijden'),
        (id: 'same_day', label: 'Zelfde Dag Beschikbaar'),
        (id: 'free_cancellation', label: 'Gratis Annuleren'),
        // Activity & loyaliteit
        (id: 'new', label: 'Nieuw'),
        (id: 'popular', label: 'Populair'),
        (id: 'years_1', label: '1 Jaar op Gymies'),
        (id: 'years_2', label: '2 Jaar op Gymies'),
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
        color: badge.color.withOpacity(0.12),
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
