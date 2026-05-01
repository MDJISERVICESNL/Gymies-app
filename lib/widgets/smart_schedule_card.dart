import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/gymies_theme.dart';

/// SmartScheduleCard
/// ─────────────────
/// Toont een trainingspatroon suggestie op basis van boekingshistorie.
/// Bijvoorbeeld: "Je traint meestal op maandag om 18:00 — plan je
/// volgende sessie?" met een CTA knop.
class SmartScheduleCard extends StatelessWidget {
  const SmartScheduleCard({
    super.key,
    required this.patterns,
    required this.suggestedTrainers,
    this.onBook,
  });

  /// Lijst van gedetecteerde patronen, elk met 'day', 'time', 'frequency'.
  final List<Map<String, dynamic>> patterns;

  /// Trainers waarmee de gebruiker eerder heeft getraind.
  final List<Map<String, dynamic>> suggestedTrainers;

  /// Callback wanneer de gebruiker op "Plan sessie" tikt.
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    if (patterns.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            GymiesColors.primary.withOpacity(0.12),
            GymiesColors.primary.withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: GymiesColors.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: GymiesColors.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: GymiesColors.darkBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Slim plannen',
                  style: GoogleFonts.sora(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _buildPatternText(),
            style: GoogleFonts.sora(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
          if (suggestedTrainers.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: suggestedTrainers.take(3).map((t) {
                final name = t['name'] ?? 'Trainer';
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: GymiesColors.primary.withOpacity(0.4),
                    ),
                  ),
                  child: Text(
                    name,
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (onBook != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onBook,
                style: TextButton.styleFrom(
                  backgroundColor: GymiesColors.primary,
                  foregroundColor: GymiesColors.darkBlue,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  'Plan sessie',
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _buildPatternText() {
    if (patterns.isEmpty) return '';

    final p = patterns.first;
    final day = p['day'] ?? '';
    final time = p['time'] ?? '';
    final freq = p['frequency'];

    String freqText = '';
    if (freq is int && freq > 1) {
      freqText = ' ($freq keer)';
    }

    if (patterns.length == 1) {
      return 'Je traint meestal op $day om $time$freqText. Wil je weer een sessie plannen?';
    }

    final second = patterns[1];
    return 'Je traint meestal op $day om $time$freqText en op ${second['day']} om ${second['time']}. Plan je volgende sessie!';
  }
}
