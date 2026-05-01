import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';

/// RescheduleSuggestionSheet
/// ─────────────────────────
/// Bottom sheet die alternatieve tijdslots toont wanneer een klant
/// een sessie annuleert. "Voordat je annuleert — je trainer heeft
/// nog plek op donderdag 14:00 en vrijdag 10:00."
///
/// Gebruik:
/// ```dart
/// RescheduleSuggestionSheet.show(context, options, onSelect);
/// ```
class RescheduleSuggestionSheet extends StatelessWidget {
  const RescheduleSuggestionSheet({
    super.key,
    required this.trainerName,
    required this.options,
    required this.onSelect,
    required this.onCancelAnyway,
  });

  final String trainerName;

  /// Lijst van alternatieven: {'slot_id', 'day', 'time', 'date'}.
  final List<Map<String, dynamic>> options;

  /// Gebruiker kiest een alternatief slot.
  final void Function(Map<String, dynamic> option) onSelect;

  /// Gebruiker wil toch annuleren.
  final VoidCallback onCancelAnyway;

  /// Toon als bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String trainerName,
    required List<Map<String, dynamic>> options,
    required void Function(Map<String, dynamic>) onSelect,
    required VoidCallback onCancelAnyway,
  }) {
    Haptics.notification();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RescheduleSuggestionSheet(
        trainerName: trainerName,
        options: options,
        onSelect: onSelect,
        onCancelAnyway: onCancelAnyway,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: GymiesColors.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.swap_horiz,
              color: GymiesColors.darkBlue,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),

          Text(
            'Liever verzetten?',
            style: GoogleFonts.sora(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$trainerName heeft nog plek op deze momenten:',
            style: GoogleFonts.sora(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),

          // Slot opties
          ...options.take(4).map((opt) => _SlotOption(
                option: opt,
                onTap: () {
                  Haptics.medium();
                  Navigator.of(context).pop();
                  onSelect(opt);
                },
              )),

          const SizedBox(height: 16),

          // Toch annuleren
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onCancelAnyway();
            },
            child: Text(
              'Nee, toch annuleren',
              style: GoogleFonts.sora(
                fontSize: 13,
                color: Colors.grey.shade500,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotOption extends StatelessWidget {
  const _SlotOption({
    required this.option,
    required this.onTap,
  });

  final Map<String, dynamic> option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final day = option['day']?.toString() ?? '';
    final time = option['time']?.toString() ?? '';
    final date = option['date']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: GymiesColors.darkBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$day, $time',
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      if (date.isNotEmpty)
                        Text(
                          date,
                          style: GoogleFonts.sora(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: GymiesColors.darkBlue,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
