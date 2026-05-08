import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../services/promotion_service.dart';
import '../../theme/gymies_theme.dart';

/// Banner die de actieve promotie/trial status toont op het dashboard.
///
/// Gebruik:
/// ```dart
/// Consumer<PromotionService>(
///   builder: (context, promoService, _) => PromotionBanner(
///     promotionService: promoService,
///   ),
/// )
/// ```
class PromotionBanner extends StatelessWidget {
  const PromotionBanner({
    super.key,
    required this.promotionService,
    this.onTap,
  });

  final PromotionService promotionService;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (!promotionService.hasActivePromotion) return const SizedBox.shrink();

    final promo = promotionService.activePromotion!;
    final isTrialEnding = promotionService.isTrialEndingSoon;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: isTrialEnding
                ? [Colors.orange.shade600, Colors.orange.shade800]
                : promo.isTrial
                    ? [GymiesColors.primary, GymiesColors.primary.withOpacity(0.8)]
                    : [Colors.green.shade600, Colors.green.shade800],
          ),
        ),
        child: Row(
          children: [
            Icon(
              isTrialEnding
                  ? Icons.warning_amber_rounded
                  : promo.isTrial
                      ? Icons.rocket_launch_rounded
                      : Icons.local_offer_rounded,
              color: isTrialEnding ? Colors.white : GymiesColors.darkBlue,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title(promo, isTrialEnding),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: isTrialEnding ? Colors.white : GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    promo.summaryText,
                    style: TextStyle(
                      fontSize: 12,
                      color: isTrialEnding
                          ? Colors.white.withOpacity(0.9)
                          : GymiesColors.darkBlue.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            if (isTrialEnding)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  S.of(context).upgradeAction,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Colors.orange.shade800,
                  ),
                ),
              )
            else
              Icon(
                Icons.chevron_right,
                color: isTrialEnding ? Colors.white : GymiesColors.darkBlue,
              ),
          ],
        ),
      ),
    );
  }

  String _title(dynamic promo, bool isTrialEnding) {
    if (isTrialEnding) return 'Proefperiode loopt bijna af';
    if (promo.isTrial) return 'Gratis proefperiode';
    if (promo.displayLabel != null && promo.displayLabel.isNotEmpty) {
      return promo.displayLabel;
    }
    return 'Actieve promotie';
  }
}
