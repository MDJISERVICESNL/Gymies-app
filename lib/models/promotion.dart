/// Model voor een actieve promotie van de trainer.
class TrainerActivePromotion {
  const TrainerActivePromotion({
    required this.id,
    required this.promotionId,
    this.promotionSlug,
    required this.type,
    required this.status,
    this.displayLabel,
    required this.appliedTier,
    this.originalPriceCents,
    this.discountedPriceCents,
    this.originalPrice,
    this.discountedPrice,
    this.activatedAt,
    this.expiresAt,
    this.daysRemaining,
    this.monthsRemaining,
    this.monthsUsed,
    this.isTrial = false,
    this.isActive = false,
  });

  final int id;
  final int promotionId;
  final String? promotionSlug;
  final String type; // discount_months, coupon, campaign, trial
  final String status; // active, expired, cancelled, converted
  final String? displayLabel;
  final String appliedTier;
  final int? originalPriceCents;
  final int? discountedPriceCents;
  final String? originalPrice; // "€64,99"
  final String? discountedPrice; // "€32,50"
  final DateTime? activatedAt;
  final DateTime? expiresAt;
  final int? daysRemaining;
  final int? monthsRemaining;
  final int? monthsUsed;
  final bool isTrial;
  final bool isActive;

  factory TrainerActivePromotion.fromJson(Map<String, dynamic> json) {
    return TrainerActivePromotion(
      id: _toInt(json['id']),
      promotionId: _toInt(json['promotion_id']),
      promotionSlug: json['promotion_slug']?.toString(),
      type: (json['type'] ?? 'coupon').toString(),
      status: (json['status'] ?? 'active').toString(),
      displayLabel: json['display_label']?.toString(),
      appliedTier: (json['applied_tier'] ?? 'starter').toString(),
      originalPriceCents: json['original_price_cents'] as int?,
      discountedPriceCents: json['discounted_price_cents'] as int?,
      originalPrice: json['original_price']?.toString(),
      discountedPrice: json['discounted_price']?.toString(),
      activatedAt: _parseDate(json['activated_at']),
      expiresAt: _parseDate(json['expires_at']),
      daysRemaining: json['days_remaining'] as int?,
      monthsRemaining: json['months_remaining'] as int?,
      monthsUsed: json['months_used'] as int?,
      isTrial: json['is_trial'] == true,
      isActive: json['is_active'] == true,
    );
  }

  /// Is de trial bijna afgelopen (3 dagen of minder)?
  bool get isTrialEndingSoon =>
      isTrial && isActive && daysRemaining != null && daysRemaining! <= 3;

  /// Heeft de trainer nog kortingsmaanden over?
  bool get hasDiscountMonthsRemaining =>
      monthsRemaining != null && monthsRemaining! > 0;

  /// Korte samenvatting voor de UI.
  String get summaryText {
    if (isTrial && daysRemaining != null) {
      return 'Proefperiode: nog $daysRemaining ${daysRemaining == 1 ? 'dag' : 'dagen'}';
    }
    if (monthsRemaining != null && monthsRemaining! > 0) {
      return 'Korting: nog $monthsRemaining ${monthsRemaining == 1 ? 'maand' : 'maanden'}';
    }
    if (displayLabel != null && displayLabel!.isNotEmpty) {
      return displayLabel!;
    }
    return 'Promotie actief';
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }
}

/// Model voor een beschikbare promotie (bij het kiezen van een plan).
class AvailablePromotion {
  const AvailablePromotion({
    required this.promotionId,
    this.promotionSlug,
    required this.type,
    this.displayLabel,
    this.displayBadge,
    this.discountType,
    this.discountValue,
    this.discountMonths,
    this.trialDays,
    this.originalPrice,
    this.price,
    this.endsAt,
  });

  final int promotionId;
  final String? promotionSlug;
  final String type;
  final String? displayLabel;
  final String? displayBadge;
  final String? discountType; // percentage, fixed_amount
  final int? discountValue;
  final int? discountMonths;
  final int? trialDays;
  final String? originalPrice; // "€64,99"
  final String? price; // "€32,50"
  final DateTime? endsAt;

  factory AvailablePromotion.fromJson(Map<String, dynamic> json) {
    return AvailablePromotion(
      promotionId: _toInt(json['promotion_id']),
      promotionSlug: json['promotion_slug']?.toString(),
      type: (json['type'] ?? 'coupon').toString(),
      displayLabel: json['display_label']?.toString(),
      displayBadge: json['display_badge']?.toString(),
      discountType: json['discount_type']?.toString(),
      discountValue: json['discount_value'] as int?,
      discountMonths: json['discount_months'] as int?,
      trialDays: json['trial_days'] as int?,
      originalPrice: json['original_price']?.toString(),
      price: json['price']?.toString(),
      endsAt: json['ends_at'] != null ? DateTime.tryParse(json['ends_at'].toString()) : null,
    );
  }

  /// Heeft deze promotie een deadline?
  bool get hasDeadline => endsAt != null;

  /// Is deze promotie bijna voorbij?
  bool get isEndingSoon {
    if (endsAt == null) return false;
    return endsAt!.difference(DateTime.now()).inDays <= 3;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}
