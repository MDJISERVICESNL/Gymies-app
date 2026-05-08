import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/gymies_theme.dart';
import '../trainer_subscription_screen.dart';

/// Herbruikbare upgrade-prompt die verschijnt wanneer een feature
/// niet beschikbaar is voor de huidige tier.
///
/// Gebruik in plaats van grijze locked tiles. Toont de waarde van
/// de feature en een CTA naar het subscription-scherm.
class GymiesUpgradePrompt extends StatelessWidget {
  const GymiesUpgradePrompt({
    super.key,
    required this.icon,
    required this.feature,
    required this.tier,
    required this.description,
  });

  /// Feature-specifiek icoon (niet een slotje).
  final IconData icon;

  /// Feature naam, bijv. "Groepslessen".
  final String feature;

  /// Benodigde tier, bijv. "Pro" of "Pro+".
  final String tier;

  /// 1-2 zinnen over de waarde (niet wat het is, maar wat het oplevert).
  final String description;

  @override
  Widget build(BuildContext context) {
    final isPro = tier.toLowerCase().contains('+');
    final bgColor = isPro ? Colors.blue.shade50 : Colors.amber.shade50;
    final accentColor = isPro ? Colors.blue.shade800 : Colors.amber.shade800;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 36, color: accentColor),
            ),
            const SizedBox(height: 20),
            Text(
              feature,
              style: GoogleFonts.sora(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: GymiesColors.darkBlue,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: GymiesColors.primary.withOpacity(0.85),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Beschikbaar met $tier',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: GymiesColors.darkBlue,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TrainerSubscriptionScreen(),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
              icon: const Icon(Icons.stars_rounded, size: 20),
              label: Text(
                'Bekijk $tier',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
