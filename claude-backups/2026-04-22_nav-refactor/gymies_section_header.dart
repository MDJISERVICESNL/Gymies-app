import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/gymies_theme.dart';

/// Gestandaardiseerde section header voor alle trainer-schermen.
/// Gebruik: `GymiesSectionHeader('Titel')`
class GymiesSectionHeader extends StatelessWidget {
  const GymiesSectionHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.fjallaOne(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: GymiesColors.darkBlue,
        ),
      ),
    );
  }
}
