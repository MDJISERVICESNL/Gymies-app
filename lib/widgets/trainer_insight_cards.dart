import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/gymies_theme.dart';

/// TrainerInsightCards
/// ───────────────────
/// Toont natuurlijke-taal inzichten voor trainers in compacte
/// kaartjes. Bijv. "Deze maand 12 boekingen — 20% meer dan vorige
/// maand" of "Je populairste dag is donderdag".
class TrainerInsightCards extends StatelessWidget {
  const TrainerInsightCards({
    super.key,
    required this.insights,
  });

  /// Lijst van insights, elk met 'type', 'title', 'description', 'sentiment'.
  final List<Map<String, dynamic>> insights;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.insights, size: 18, color: GymiesColors.darkBlue),
              const SizedBox(width: 8),
              Text(
                'Jouw inzichten',
                style: GoogleFonts.sora(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: GymiesColors.darkBlue,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: insights.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _InsightChip(insight: insights[i]),
          ),
        ),
      ],
    );
  }
}

class _InsightChip extends StatelessWidget {
  const _InsightChip({required this.insight});
  final Map<String, dynamic> insight;

  @override
  Widget build(BuildContext context) {
    final sentiment = (insight['sentiment'] ?? 'neutral').toString();
    final icon = _iconForType(insight['type']?.toString() ?? '');
    final accentColor = _colorForSentiment(sentiment);

    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: accentColor, width: 3),
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
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  insight['title']?.toString() ?? '',
                  style: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              insight['description']?.toString() ?? '',
              style: GoogleFonts.sora(
                fontSize: 12,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'bookings':
        return Icons.calendar_today;
      case 'rating':
        return Icons.star;
      case 'revenue':
        return Icons.euro;
      case 'popular_day':
        return Icons.trending_up;
      default:
        return Icons.lightbulb_outline;
    }
  }

  Color _colorForSentiment(String sentiment) {
    switch (sentiment) {
      case 'positive':
        return const Color(0xFF4CAF50);
      case 'attention':
        return const Color(0xFFFF9800);
      case 'opportunity':
        return GymiesColors.primary;
      default:
        return GymiesColors.darkBlue;
    }
  }
}
