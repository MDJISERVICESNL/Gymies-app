import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/gymies_theme.dart';

/// PricingInsightCard
/// ──────────────────
/// Toont trainer hoe hun prijs zich verhoudt tot de markt.
/// "Je tarief van €45/u ligt 12% onder het gemiddelde in Amsterdam.
///  Er is ruimte om je prijs te verhogen."
class PricingInsightCard extends StatelessWidget {
  const PricingInsightCard({
    super.key,
    required this.trainerRate,
    required this.marketAverage,
    required this.message,
    required this.sentiment,
    this.region,
  });

  /// Het huidige tarief van de trainer in euro.
  final double trainerRate;

  /// Het marktgemiddelde tarief in euro.
  final double marketAverage;

  /// Gegenereerd advies vanuit de backend.
  final String message;

  /// 'opportunity', 'attention', of 'positive'.
  final String sentiment;

  /// Stad/regio naam.
  final String? region;

  @override
  Widget build(BuildContext context) {
    final diff = trainerRate - marketAverage;
    final pct = marketAverage > 0
        ? ((diff / marketAverage) * 100).round()
        : 0;
    final isAbove = diff > 0;
    final isBelow = diff < 0;

    final sentimentColor = _sentimentColor();
    final sentimentIcon = _sentimentIcon();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: sentimentColor, width: 3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(sentimentIcon, color: sentimentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Prijsinzicht',
                style: GoogleFonts.sora(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const Spacer(),
              if (region != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    region!,
                    style: GoogleFonts.sora(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Prijs vergelijking
          Row(
            children: [
              Expanded(
                child: _PriceColumn(
                  label: 'Jouw tarief',
                  amount: trainerRate,
                  highlight: true,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: sentimentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isAbove
                      ? '+$pct%'
                      : isBelow
                          ? '$pct%'
                          : '≈',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: sentimentColor,
                  ),
                ),
              ),
              Expanded(
                child: _PriceColumn(
                  label: 'Markt gem.',
                  amount: marketAverage,
                  highlight: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: GoogleFonts.sora(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Color _sentimentColor() {
    switch (sentiment) {
      case 'opportunity':
        return GymiesColors.primary;
      case 'attention':
        return const Color(0xFFFF9800);
      case 'positive':
        return const Color(0xFF4CAF50);
      default:
        return GymiesColors.darkBlue;
    }
  }

  IconData _sentimentIcon() {
    switch (sentiment) {
      case 'opportunity':
        return Icons.trending_up;
      case 'attention':
        return Icons.warning_amber;
      case 'positive':
        return Icons.check_circle_outline;
      default:
        return Icons.euro;
    }
  }
}

class _PriceColumn extends StatelessWidget {
  const _PriceColumn({
    required this.label,
    required this.amount,
    required this.highlight,
  });

  final String label;
  final double amount;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '€${amount.toStringAsFixed(0)}/u',
          style: GoogleFonts.sora(
            fontSize: 20,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
            color: highlight ? GymiesColors.darkBlue : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}
