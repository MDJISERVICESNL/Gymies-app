import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// GYMIES kleuren
class GymiesColors {
  static const Color primary = Color(0xFFFEBE23); // #FEBE23
  static const Color darkBlue = Color(0xFF1E3A5F);
}

/// GYMIES tekststijlen voor consistente typografie
class GymiesTextStyles {
  GymiesTextStyles._();

  static TextStyle get h1 => GoogleFonts.fjallaOne(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: GymiesColors.darkBlue,
      );

  static TextStyle get h2 => GoogleFonts.fjallaOne(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: GymiesColors.darkBlue,
      );

  static TextStyle get h3 => GoogleFonts.fjallaOne(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: GymiesColors.darkBlue,
      );
}

/// GYMIES thema voor de hele app (inclusief dialogen en bottom sheets)
final gymiesTheme = _buildGymiesTheme();

ThemeData _buildGymiesTheme() {
  const primary = GymiesColors.primary;
  const darkBlue = GymiesColors.darkBlue;

  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: primary),
    useMaterial3: true,
    fontFamily: GoogleFonts.roboto().fontFamily,
    // Dialogen (AlertDialog)
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      elevation: 8,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      titleTextStyle: GoogleFonts.fjallaOne(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: darkBlue,
      ),
      contentTextStyle: TextStyle(
        fontSize: 16,
        color: Colors.grey.shade800,
        height: 1.4,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
    ),
    // Bottom sheets
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.white,
      elevation: 8,
      modalElevation: 16,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
      dragHandleColor: Colors.grey.shade400,
      dragHandleSize: const Size(40, 4),
    ),
    // Inputvelden in formulieren
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: 15),
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 15),
    ),
    // Knoppen in dialogen
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: darkBlue,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: darkBlue,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkBlue,
        side: const BorderSide(color: darkBlue),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
  );
}
