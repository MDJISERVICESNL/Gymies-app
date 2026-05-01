/// Trainer model voor API-response.
class Trainer {
  Trainer({
    required this.userId,
    required this.displayName,
    required this.email,
    this.specialty,
    this.region,
    this.city,
    this.categories = const [],
    this.lessonTypes = const [],
    this.distanceKm,
    this.hourlyRateCents,
    this.rating,
    this.reviewCount,
    this.avatarUrl,
    this.trainerVerified = false,
    this.emailVerified = false,
    this.woman2woman = false,
    this.isAmbassador = false,
    this.subscriptionTier,
    this.clientsWith5PlusSessions,
    this.avgResponseMinutes,
    this.diplomaVerified = false,
    this.specialistCategory,
    this.totalSessions,
    this.hasOwnLocation = false,
    this.offersDuoTraining = false,
    this.hasIntroOffer = false,
    this.profileCreatedAt,
    this.bookingsThisWeek,
    this.visibleBadgeIds,
    this.mediaGallery = const [],
    this.storyMedia = const [],
    this.boostedUntil,
    this.bookingAdvanceDays,
    this.paymentMethod,
    this.instagramUrl,
    this.snapchatUsername,
    this.facebookUrl,
    this.bio,
    this.specializationsTags = const [],
    this.cancellationHours,
    this.cancellationRefundPercent,
    this.cancellationExceptions,
    this.introOfferDescription,
    this.brandColor,
    this.brandLogoUrl,
    this.brandBannerUrl,
    this.introVideoUrl,
  });

  final String userId;
  final String displayName;
  final String email;
  final String? specialty;
  final String? region;
  final String? city;
  final List<String> categories;
  final List<String> lessonTypes;
  final double? distanceKm;
  final int? hourlyRateCents;
  final double? rating;
  final int? reviewCount;
  final String? avatarUrl;
  final bool trainerVerified;
  final bool emailVerified;
  final bool woman2woman;
  final bool isAmbassador;
  final String? subscriptionTier;
  final bool diplomaVerified;
  final String? specialistCategory;
  final int? totalSessions;
  final bool hasOwnLocation;
  final bool offersDuoTraining;
  final bool hasIntroOffer;
  final DateTime? profileCreatedAt;
  final int? bookingsThisWeek;
  final int? clientsWith5PlusSessions;
  final int? avgResponseMinutes;
  final List<String>? visibleBadgeIds;
  final List<Map<String, dynamic>> mediaGallery;
  final List<Map<String, dynamic>> storyMedia;
  final DateTime? boostedUntil;
  final int? bookingAdvanceDays;
  final String? paymentMethod;
  final String? instagramUrl;
  final String? snapchatUsername;
  final String? facebookUrl;
  final String? bio;
  final List<String> specializationsTags;
  final int? cancellationHours;
  final int? cancellationRefundPercent;
  final String? cancellationExceptions;
  final String? introOfferDescription;

  // ── Pro+ branding ──
  final String? brandColor;
  final String? brandLogoUrl;
  final String? brandBannerUrl;
  final String? introVideoUrl;

  /// Of deze trainer momenteel geboost is (in top 5 van zijn stad).
  bool get isBoosted {
    final until = boostedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  factory Trainer.fromJson(Map<String, dynamic> json) {
    // Merge storefront data (nested 'storefront' object) naar root-niveau
    // zodat alle velden uniform bereikbaar zijn.
    final sf = json['storefront'];
    if (sf is Map<String, dynamic>) {
      for (final entry in sf.entries) {
        json.putIfAbsent(entry.key, () => entry.value);
      }
    }
    // Merge branding data (nested 'branding' object) naar root-niveau
    final br = json['branding'];
    if (br is Map<String, dynamic>) {
      for (final entry in br.entries) {
        json.putIfAbsent(entry.key, () => entry.value);
      }
    }
    final id = json['user_id'] ?? json['id']?.toString() ?? '';
    List<String> listFrom(dynamic raw) {
      if (raw is List) {
        return raw
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
      }
      final asString = raw?.toString().trim() ?? '';
      if (asString.isEmpty) return const [];
      return asString
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    double? numberFrom(dynamic raw) {
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw?.toString() ?? '');
    }

    return Trainer(
      userId: id.toString(),
      displayName: (json['display_name'] ?? json['name'] ?? json['email'] ?? '')
          .toString()
          .trim(),
      email: (json['email'] ?? '').toString().trim(),
      specialty: json['specialty']?.toString().trim(),
      region: json['region']?.toString().trim(),
      city: (json['city'] ?? json['place'] ?? json['town'])?.toString().trim(),
      categories: listFrom(
        json['categories'] ?? json['category_list'] ?? json['category'],
      ),
      lessonTypes: listFrom(
        json['lesson_types'] ?? json['lessons'] ?? json['classes'],
      ),
      distanceKm: numberFrom(json['distance_km'] ?? json['distance']),
      hourlyRateCents: (json['hourly_rate_cents'] ?? json['hourly_rate']) is int
          ? json['hourly_rate_cents'] ?? json['hourly_rate']
          : ((json['hourly_rate_cents'] ?? json['hourly_rate']) as num?)
                ?.toInt(),
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: (json['review_count'] as num?)?.toInt(),
      avatarUrl: json['avatar_url'] ?? json['avatar']?.toString(),
      trainerVerified: json['trainer_verified'] == true,
      emailVerified: json['email_verified'] == true,
      woman2woman: json['woman2woman'] == true || json['woman_2_woman'] == true,
      isAmbassador: json['is_ambassador'] == true || json['ambassador'] == true,
      subscriptionTier:
          (json['subscription_tier'] ??
                  json['tier'] ??
                  json['plan_tier'] ??
                  json['plan'] ??
                  json['subscription'])
              ?.toString()
              .trim(),
      diplomaVerified: json['diploma_verified'] == true ||
          json['certified'] == true ||
          json['gediplomeerd'] == true,
      specialistCategory: (json['specialist_category'] ??
              json['specialist'] ??
              json['specialty_badge'])
          ?.toString()
          .trim(),
      totalSessions: (json['total_sessions'] ?? json['sessions_count'] ?? json['completed_sessions']) is int
          ? (json['total_sessions'] ?? json['sessions_count'] ?? json['completed_sessions']) as int
          : int.tryParse((json['total_sessions'] ?? json['sessions_count'] ?? json['completed_sessions'])?.toString() ?? ''),
      hasOwnLocation: json['has_own_location'] == true ||
          json['own_location'] == true ||
          json['eigen_locatie'] == true,
      offersDuoTraining: json['offers_duo_training'] == true ||
          json['duo_training'] == true ||
          json['duo_discount'] == true,
      hasIntroOffer: json['has_intro_offer'] == true ||
          json['intro_offer'] == true ||
          json['introductiekorting'] == true,
      profileCreatedAt: () {
        final raw = json['profile_created_at'] ?? json['created_at'] ?? json['registered_at'];
        if (raw == null) return null;
        if (raw is DateTime) return raw;
        return DateTime.tryParse(raw.toString());
      }(),
      bookingsThisWeek: (json['bookings_this_week'] ?? json['weekly_bookings']) is int
          ? (json['bookings_this_week'] ?? json['weekly_bookings']) as int
          : int.tryParse((json['bookings_this_week'] ?? json['weekly_bookings'])?.toString() ?? ''),
      clientsWith5PlusSessions: (json['clients_with_5_plus_sessions'] ?? json['repeat_clients']) is int
          ? (json['clients_with_5_plus_sessions'] ?? json['repeat_clients']) as int
          : int.tryParse((json['clients_with_5_plus_sessions'] ?? json['repeat_clients'])?.toString() ?? ''),
      avgResponseMinutes: (json['avg_response_minutes'] ?? json['response_time_minutes']) is int
          ? (json['avg_response_minutes'] ?? json['response_time_minutes']) as int
          : int.tryParse((json['avg_response_minutes'] ?? json['response_time_minutes'])?.toString() ?? ''),
      visibleBadgeIds: () {
        final raw = json['visible_badges'] ?? json['visible_badge_ids'] ?? json['badge_ids'];
        if (raw == null) return null;
        return listFrom(raw);
      }(),
      mediaGallery: _listOfMaps(json['media_gallery'] ?? json['mediaGallery'] ?? json['media']),
      storyMedia: _listOfMaps(json['story_media'] ?? json['storyMedia'] ?? json['story'] ?? json['stories']),
      boostedUntil: () {
        final raw = json['boosted_until'] ?? json['boostedUntil'];
        if (raw == null) return null;
        if (raw is DateTime) return raw;
        return DateTime.tryParse(raw.toString());
      }(),
      bookingAdvanceDays: (json['booking_advance_days'] ?? json['bookingAdvanceDays']) is int
          ? (json['booking_advance_days'] ?? json['bookingAdvanceDays']) as int
          : int.tryParse((json['booking_advance_days'] ?? json['bookingAdvanceDays'])?.toString() ?? ''),
      paymentMethod: (json['payment_method'] ?? json['paymentMethod'])?.toString().trim(),
      instagramUrl: (json['instagram_url'] ?? json['instagramUrl'])?.toString().trim(),
      snapchatUsername: (json['snapchat_username'] ?? json['snapchatUsername'])?.toString().trim(),
      facebookUrl: (json['facebook_url'] ?? json['facebookUrl'])?.toString().trim(),
      bio: (json['bio'] ?? json['about'] ?? json['intro'])?.toString().trim(),
      specializationsTags: listFrom(json['specializations_tags'] ?? json['specializationsTags']),
      cancellationHours: (json['cancellation_hours'] ?? json['cancellationHours']) is int
          ? (json['cancellation_hours'] ?? json['cancellationHours']) as int
          : int.tryParse((json['cancellation_hours'] ?? json['cancellationHours'])?.toString() ?? ''),
      cancellationRefundPercent: (json['cancellation_refund_percent'] ?? json['cancellationRefundPercent']) is int
          ? (json['cancellation_refund_percent'] ?? json['cancellationRefundPercent']) as int
          : int.tryParse((json['cancellation_refund_percent'] ?? json['cancellationRefundPercent'])?.toString() ?? ''),
      cancellationExceptions: (json['cancellation_exceptions'] ?? json['cancellationExceptions'])?.toString().trim(),
      introOfferDescription: (json['intro_offer_description'] ?? json['introOfferDescription'])?.toString().trim(),
      brandColor: (json['brand_color'] ?? json['brandColor'])?.toString().trim(),
      brandLogoUrl: (json['brand_logo_url'] ?? json['brandLogoUrl'])?.toString().trim(),
      brandBannerUrl: (json['brand_banner_url'] ?? json['brandBannerUrl'])?.toString().trim(),
      introVideoUrl: (json['intro_video_url'] ?? json['introVideoUrl'])?.toString().trim(),
    );
  }

  /// Label voor betaalmethode op profiel.
  String get paymentMethodLabel {
    final m = (paymentMethod ?? 'transfer_and_cash').toLowerCase();
    if (m == 'transfer_only') return 'Accepteert alleen overboekingen';
    if (m == 'cash_only') return 'Accepteert alleen cash';
    return 'Accepteert overboekingen & cash';
  }

  static List<Map<String, dynamic>> _listOfMaps(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) {
          if (e is Map<String, dynamic>) return e;
          if (e is Map) return Map<String, dynamic>.from(e);
          return null;
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Label voor de prijs-badge: "Op aanvraag" bij prijs op aanvraag.
  String get priceBadgeLabel => hourlyRateCents != null
      ? '€${(hourlyRateCents! / 100).toStringAsFixed(0)}/sessie'
      : 'Op aanvraag';

  /// Leesbaar label voor annuleringsbeleid op openbaar profiel.
  String? get cancellationPolicyLabel {
    if (cancellationHours == null) return null;
    final hours = cancellationHours!;
    final refund = cancellationRefundPercent ?? 100;
    final termijn = hours >= 48
        ? '${hours ~/ 24} dagen'
        : '$hours uur';
    return 'Annuleer tot $termijn van tevoren — $refund% restitutie';
  }

  /// Heeft de trainer een annuleringsbeleid ingesteld?
  bool get hasCancellationPolicy => cancellationHours != null;

  /// Heeft de trainer Pro+ branding ingesteld?
  bool get hasBranding =>
      (brandColor != null && brandColor!.isNotEmpty) ||
      (brandLogoUrl != null && brandLogoUrl!.isNotEmpty) ||
      (brandBannerUrl != null && brandBannerUrl!.isNotEmpty);

  /// Heeft de trainer een intro video?
  bool get hasIntroVideo =>
      introVideoUrl != null && introVideoUrl!.isNotEmpty;

  /// Is dit een Pro+ trainer?
  bool get isProPlus => tierNormalized == 'pro_plus' || tierNormalized == 'studio';

  String get nameOrEmail => displayName.isNotEmpty ? displayName : email;
  String get priceLabel => hourlyRateCents != null
      ? '€${(hourlyRateCents! / 100).toStringAsFixed(0)}/sessie'
      : 'Prijs op aanvraag';

  String get tierNormalized {
    final raw = (subscriptionTier ?? '').trim().toLowerCase();
    if (raw.contains('studio')) return 'studio';
    if (raw.contains('pro_plus') || raw.contains('proplus') || raw.contains('pro+')) return 'pro_plus';
    if (raw.contains('elite')) return 'studio'; // legacy: elite is nu studio (gym-only)
    if (raw.contains('pro')) return 'pro';
    if (raw.contains('starter') || raw.contains('basic')) return 'starter';
    return 'starter';
  }

  bool get coachToolsEnabled => tierNormalized == 'pro' || tierNormalized == 'pro_plus' || tierNormalized == 'studio';

  String get coachToolsLabel {
    return coachToolsEnabled
        ? 'Doelen & progressie beschikbaar'
        : 'Doelen & progressie niet beschikbaar';
  }
}
