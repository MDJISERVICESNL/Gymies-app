import '../utils/currency_format.dart';

class Trainer {
  final int id;
  final String name;
  final String? avatarUrl;
  final bool hasActiveStory;

  // Profile basics
  final String? specialty;
  final String? region;
  final int? hourlyRateCents;

  // Tier / verification
  final String? tierRaw;
  final bool? trainerVerifiedFlag;
  final bool? woman2womanFlag;
  final bool? isAmbassadorFlag;

  // Trust / rating
  final double? rating;
  final int? reviewCount;
  final int? clientsWith5PlusSessions;
  final double? avgResponseMinutes;

  // Expertise / logistics
  final bool? diplomaVerifiedFlag;
  final String? specialistCategory;
  final int? totalSessions;
  final bool? hasOwnLocationFlag;
  final bool? offersDuoTrainingFlag;
  final bool? hasIntroOfferFlag;

  // Activity
  final DateTime? profileCreatedAt;
  final int? bookingsThisWeek;

  // Founding Partner (computed by backend via feature flags)
  final bool? isFoundingPartnerFlag;

  // Trust & social proof (computed by backend)
  final double? returnClientPercentage;
  final bool? isTopBookedFlag;
  final bool? hasFreeTrialFlag;

  // Service & beschikbaarheid
  final bool? offersOnlineSessionsFlag;
  final bool? hasFlexibleHoursFlag;
  final bool? sameDayBookingFlag;
  final bool? hasFreeCancellationFlag;

  // UI / badges preferences
  final String? city;
  final List<String>? visibleBadgeIds;

  // Storefront/editor usage (veelgebruikte velden in screens)
  final String? bio;
  final String? brandColor;
  final String? brandLogoUrl;
  final List<String> specializationsTags;
  final int? bookingAdvanceDays;
  final String? paymentMethodLabel;
  final String? introOfferDescription;
  final bool? hasCancellationPolicyFlag;
  final String? cancellationPolicyLabel;
  final String? cancellationExceptions;

  final String? instagramUrl;
  final String? snapchatUsername;
  final String? facebookUrl;
  final String? profileSlug;

  // Discovery / filtering
  final List<String> categories;
  final List<String> lessonTypes;
  final double? distanceKm;
  final bool isBoosted;

  Trainer({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.hasActiveStory = false,

    this.specialty,
    this.region,
    this.hourlyRateCents,

    this.tierRaw,
    this.trainerVerifiedFlag,
    this.woman2womanFlag,
    this.isAmbassadorFlag,

    this.rating,
    this.reviewCount,
    this.clientsWith5PlusSessions,
    this.avgResponseMinutes,

    this.diplomaVerifiedFlag,
    this.specialistCategory,
    this.totalSessions,
    this.hasOwnLocationFlag,
    this.offersDuoTrainingFlag,
    this.hasIntroOfferFlag,

    this.profileCreatedAt,
    this.bookingsThisWeek,
    this.isFoundingPartnerFlag,

    this.returnClientPercentage,
    this.isTopBookedFlag,
    this.hasFreeTrialFlag,

    this.offersOnlineSessionsFlag,
    this.hasFlexibleHoursFlag,
    this.sameDayBookingFlag,
    this.hasFreeCancellationFlag,

    this.city,
    this.visibleBadgeIds,

    this.bio,
    this.brandColor,
    this.brandLogoUrl,
    this.specializationsTags = const [],
    this.bookingAdvanceDays,
    this.paymentMethodLabel,
    this.introOfferDescription,
    this.hasCancellationPolicyFlag,
    this.cancellationPolicyLabel,
    this.cancellationExceptions,

    this.instagramUrl,
    this.snapchatUsername,
    this.facebookUrl,
    this.profileSlug,

    this.categories = const [],
    this.lessonTypes = const [],
    this.distanceKm,
    this.isBoosted = false,
  });

  factory Trainer.fromJson(Map<String, dynamic> json) {
    String? pickString(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return null;
    }

    int? pickInt(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is int) return v;
        if (v is num) return v.toInt();
        if (v is String) return int.tryParse(v.trim());
      }
      return null;
    }

    double? pickDouble(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is double) return v;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v.trim());
      }
      return null;
    }

    bool? pickBool(List<String> keys) {
      bool? parse(dynamic v) {
        if (v == null) return null;
        if (v is bool) return v;
        if (v is num) return v != 0;
        if (v is String) {
          final s = v.trim().toLowerCase();
          if (s.isEmpty) return null;
          if (s == 'true' || s == '1' || s == 'yes' || s == 'y') return true;
          if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
        }
        return null;
      }

      for (final k in keys) {
        final v = json[k];
        final b = parse(v);
        if (b != null) return b;
      }
      return null;
    }

    DateTime? parseDate(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is DateTime) return v;
        if (v is String) {
          final s = v.trim();
          if (s.isEmpty) continue;
          final dt = DateTime.tryParse(s);
          if (dt != null) return dt;
        }
      }
      return null;
    }

    // API kan 'id', 'user_id', of 'trainer_user_id' teruggeven
    final rawId = json['id'] ?? json['user_id'] ?? json['trainer_user_id'];
    final id = rawId is int
        ? rawId
        : int.tryParse(rawId?.toString() ?? '') ?? 0;

    final visibleBadgesRaw = json['visibleBadgeIds'] ?? json['visible_badge_ids'] ?? json['visible_badges'];
    final visibleBadges = visibleBadgesRaw is List
        ? visibleBadgesRaw.map((e) => e.toString()).toList()
        : null;

    final specializationsRaw =
        json['specializationsTags'] ?? json['specializations_tags'] ?? json['specializations'];
    final specializationsTags = specializationsRaw is List
        ? specializationsRaw.map((e) => e.toString()).toList()
        : const <String>[];

    final categoriesRaw = json['categories'] ?? json['category'] ?? json['trainer_categories'];
    final categories = categoriesRaw is List
        ? categoriesRaw.map((e) => e.toString()).toList()
        : categoriesRaw is String && categoriesRaw.isNotEmpty
            ? [categoriesRaw]
            : const <String>[];

    final lessonTypesRaw = json['lessonTypes'] ?? json['lesson_types'] ?? json['lesson_type'];
    final lessonTypes = lessonTypesRaw is List
        ? lessonTypesRaw.map((e) => e.toString()).toList()
        : lessonTypesRaw is String && lessonTypesRaw.isNotEmpty
            ? [lessonTypesRaw]
            : const <String>[];

    return Trainer(
      id: id,
      name: (json['name'] as String?) ??
          (json['display_name'] as String?) ??
          (json['email'] as String?) ??
          'Trainer',
      avatarUrl: json['avatar_url'] as String? ?? json['avatarUrl'] as String?,
      hasActiveStory: (json['hasActiveStory'] ?? json['has_active_story'] ?? false) as bool? ?? false,

      specialty: pickString(['specialty', 'specialism', 'trainer_specialty', 'specialty_name']),
      region: pickString(['region', 'trainer_region', 'city_region', 'location_region']),
      hourlyRateCents: pickInt(['hourly_rate_cents', 'hourlyRateCents', 'hourly_rate', 'hourlyRate']),

      tierRaw: pickString(['tierNormalized', 'tier_normalized', 'tier', 'subscription_tier', 'subscription_tier_name']),

      trainerVerifiedFlag: pickBool(['trainerVerified', 'trainer_verified', 'verified', 'trainer_is_verified']),
      woman2womanFlag: pickBool(['woman2woman', 'woman_2_woman', 'w2w']),
      isAmbassadorFlag: pickBool(['isAmbassador', 'ambassador', 'is_ambassador']),

      rating: pickDouble(['rating', 'avg_rating', 'rating_avg', 'ratingAvg']),
      reviewCount: pickInt(['reviewCount', 'review_count', 'count_reviews', 'reviews_count']),
      clientsWith5PlusSessions: pickInt(['clientsWith5PlusSessions', 'clients_with_5_plus_sessions']),
      avgResponseMinutes: pickDouble(['avgResponseMinutes', 'avg_response_minutes']),

      diplomaVerifiedFlag: pickBool(['diplomaVerified', 'diploma_verified']),
      specialistCategory: pickString(['specialistCategory', 'specialist_category', 'specialist', 'specialist_type']),
      totalSessions: pickInt(['totalSessions', 'total_sessions']),
      hasOwnLocationFlag: pickBool(['hasOwnLocation', 'has_own_location', 'own_location']),
      offersDuoTrainingFlag: pickBool(['offersDuoTraining', 'offers_duo_training', 'duo_training']),
      hasIntroOfferFlag: pickBool(['hasIntroOffer', 'has_intro_offer', 'intro_offer']),

      profileCreatedAt: parseDate(['profileCreatedAt', 'profile_created_at', 'created_at']),
      bookingsThisWeek: pickInt(['bookingsThisWeek', 'bookings_this_week']),
      isFoundingPartnerFlag: pickBool(['isFoundingPartner', 'is_founding_partner', 'founding_partner']),

      returnClientPercentage: pickDouble(['returnClientPercentage', 'return_client_percentage']),
      isTopBookedFlag: pickBool(['isTopBooked', 'is_top_booked', 'top_booked']),
      hasFreeTrialFlag: pickBool(['hasFreeTrial', 'has_free_trial', 'free_trial']),

      offersOnlineSessionsFlag: pickBool(['offersOnlineSessions', 'offers_online_sessions', 'online_sessions']),
      hasFlexibleHoursFlag: pickBool(['hasFlexibleHours', 'has_flexible_hours', 'flexible_hours']),
      sameDayBookingFlag: pickBool(['sameDayBooking', 'same_day_booking']),
      hasFreeCancellationFlag: pickBool(['hasFreeCancellation', 'has_free_cancellation', 'free_cancellation']),

      city: pickString(['city', 'town', 'client_city']),
      visibleBadgeIds: visibleBadges,

      bio: pickString(['bio', 'trainer_bio']),
      brandColor: pickString(['brandColor', 'brand_color']),
      brandLogoUrl: pickString(['brandLogoUrl', 'brand_logo_url']),
      specializationsTags: specializationsTags,
      bookingAdvanceDays: pickInt(['bookingAdvanceDays', 'booking_advance_days']),
      paymentMethodLabel: pickString(['paymentMethodLabel', 'payment_method_label']),
      introOfferDescription: pickString(['introOfferDescription', 'intro_offer_description', 'intro_offer_label']),

      hasCancellationPolicyFlag: pickBool(['hasCancellationPolicy', 'has_cancellation_policy']),
      cancellationPolicyLabel: pickString(['cancellationPolicyLabel', 'cancellation_policy_label']),
      cancellationExceptions: pickString(['cancellationExceptions', 'cancellation_exceptions']),

      instagramUrl: pickString(['instagramUrl', 'instagram_url']),
      snapchatUsername: pickString(['snapchatUsername', 'snapchat_username']),
      facebookUrl: pickString(['facebookUrl', 'facebook_url']),

      profileSlug: pickString(['profileSlug', 'profile_slug']),

      categories: categories,
      lessonTypes: lessonTypes,
      distanceKm: pickDouble(['distanceKm', 'distance_km', 'distance']),
      isBoosted: pickBool(['isBoosted', 'is_boosted', 'boosted']) ?? false,
    );
  }

  // ---------------- Getters expected by UI (computed, NO field name clashes) ----------------

  String get nameOrEmail => name;
  String get displayName => name;
  String get userId => id.toString();

  bool get trainerVerified => trainerVerifiedFlag ?? false;
  bool get woman2woman => woman2womanFlag ?? false;
  bool get isAmbassador => isAmbassadorFlag ?? false;
  bool get isFoundingPartner => isFoundingPartnerFlag ?? false;

  String get tierNormalized {
    final raw = (tierRaw ?? '').toLowerCase().trim();
    if (raw.isEmpty) return 'starter';
    if (raw == 'proplus' || raw == 'pro-plus') return 'pro_plus';
    if (raw.contains('pro_plus') || raw.contains('proplus')) return 'pro_plus';
    if (raw.contains('pro')) return 'pro';
    if (raw == 'studio') return 'studio';
    return raw;
  }

  bool get isProPlus => tierNormalized == 'pro_plus' || tierNormalized == 'studio';
  bool get isPro => tierNormalized == 'pro';
  bool get isProOrHigher => isPro || isProPlus;

  String get priceBadgeLabel {
    return formatEuroShort(hourlyRateCents);
  }

  String get priceLabel {
    return formatEuroShort(hourlyRateCents);
  }

  bool get diplomaVerified => diplomaVerifiedFlag ?? false;
  bool get hasOwnLocation => hasOwnLocationFlag ?? false;
  bool get offersDuoTraining => offersDuoTrainingFlag ?? false;
  bool get hasIntroOffer => hasIntroOfferFlag ?? false;

  bool get hasCancellationPolicy => hasCancellationPolicyFlag ?? false;

  // Nieuwe badge getters
  bool get isTopBooked => isTopBookedFlag ?? false;
  bool get hasFreeTrial => hasFreeTrialFlag ?? false;
  bool get offersOnlineSessions => offersOnlineSessionsFlag ?? false;
  bool get hasFlexibleHours => hasFlexibleHoursFlag ?? false;
  bool get sameDayBooking => sameDayBookingFlag ?? false;
  bool get hasFreeCancellation => hasFreeCancellationFlag ?? false;

  /// Terugkerende klanten: ≥80% is badge-waardig.
  bool get hasHighRetention =>
      returnClientPercentage != null && returnClientPercentage! >= 80.0;

  /// Platform anciënniteit in dagen.
  int get daysOnPlatform =>
      profileCreatedAt != null
          ? DateTime.now().difference(profileCreatedAt!).inDays
          : 0;

  /// Categorieën / specialisaties als lowercase set voor badge matching.
  Set<String> get _allTags {
    final tags = <String>{};
    for (final c in categories) {
      tags.add(c.toLowerCase().trim());
    }
    for (final s in specializationsTags) {
      tags.add(s.toLowerCase().trim());
    }
    final spec = (specialty ?? '').toLowerCase().trim();
    if (spec.isNotEmpty) tags.add(spec);
    final specCat = (specialistCategory ?? '').toLowerCase().trim();
    if (specCat.isNotEmpty) tags.add(specCat);
    return tags;
  }

  bool _matchesAnyTag(List<String> keywords) {
    final tags = _allTags;
    for (final kw in keywords) {
      for (final tag in tags) {
        if (tag.contains(kw)) return true;
      }
    }
    return false;
  }

  bool get isSeniorenSpecialist =>
      _matchesAnyTag(['senior', '55+', '65+', 'ouderen']);
  bool get isRevalidatieSpecialist =>
      _matchesAnyTag(['revalidatie', 'rehabilitatie', 'herstel', 'fysiotherapie', 'blessure']);
  bool get isZwangerschapSpecialist =>
      _matchesAnyTag(['zwanger', 'prenatal', 'postnatal', 'mama', 'pregnancy']);
  bool get isJeugdSpecialist =>
      _matchesAnyTag(['jeugd', 'kids', 'kinderen', 'tiener', 'youth', 'junior']);
  bool get isAfvallenSpecialist =>
      _matchesAnyTag(['afvallen', 'gewichtsverlies', 'weight loss', 'vetverbranding', 'slank']);
  bool get isKrachtSpecialist =>
      _matchesAnyTag(['kracht', 'powerlifting', 'strength', 'weightlifting', 'bodybuilding']);
}
