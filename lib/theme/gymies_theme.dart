import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/ui_constants.dart';

/// GYMIES kleuren
class GymiesColors {
  static const Color primary = Color(0xFFFEBE23); // #FEBE23 — goud/geel
  static const Color darkBlue = Color(0xFF1E3A5F);
  /// Donkerdere goud voor tekst/iconen op witte achtergrond (goed leesbaar).
  static const Color accent = Color(0xFFB8860B); // DarkGoldenrod — leesbaar op wit
  /// Licht goud voor achtergronden, badges, avatars.
  static const Color accentLight = Color(0xFFFFF8E1); // Warm cream
}

/// GYMIES tekststijlen voor consistente typografie
class GymiesTextStyles {
  GymiesTextStyles._();

  static TextStyle get h1 => GoogleFonts.sora(
        fontSize: UiConstants.fontSizeH1,
        fontWeight: FontWeight.bold,
        color: GymiesColors.darkBlue,
      );

  static TextStyle get h2 => GoogleFonts.sora(
        fontSize: UiConstants.fontSizeH2,
        fontWeight: FontWeight.w700,
        color: GymiesColors.darkBlue,
      );

  static TextStyle get h3 => GoogleFonts.sora(
        fontSize: UiConstants.fontSizeH3,
        fontWeight: FontWeight.w600,
        color: GymiesColors.darkBlue,
      );

  // ── Body & utility styles ──────────────────────────────────
  static TextStyle get body1 => GoogleFonts.sora(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: GymiesColors.darkBlue,
      );

  static TextStyle get body2 => GoogleFonts.sora(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: GymiesColors.darkBlue,
      );

  static TextStyle get caption => GoogleFonts.sora(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: Colors.grey,
      );

  static TextStyle get button => GoogleFonts.sora(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: GymiesColors.darkBlue,
      );

  // Material-style aliases (used by some generated screens)
  static TextStyle get headlineLarge => h1;
  static TextStyle get headlineSmall => h3;
  static TextStyle get titleMedium => GoogleFonts.sora(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: GymiesColors.darkBlue,
      );
  static TextStyle get bodyMedium => body1;
  static TextStyle get bodySmall => body2;
  static TextStyle get labelSmall => caption;
}

/// GYMIES thema voor de hele app (inclusief dialogen en bottom sheets)
final gymiesTheme = _buildGymiesTheme();

ThemeData _buildGymiesTheme() {
  const primary = GymiesColors.primary;
  const darkBlue = GymiesColors.darkBlue;

  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: darkBlue,
      surface: Colors.white,
      surfaceContainerHighest: Colors.white,
    ),
    useMaterial3: true,
    cardColor: Colors.white,
    scaffoldBackgroundColor: Colors.grey.shade50,
    fontFamily: GoogleFonts.sora().fontFamily,
    // Dialogen (AlertDialog)
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      elevation: 8,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiConstants.dialogBorderRadius),
      ),
      titleTextStyle: GoogleFonts.sora(
        fontSize: UiConstants.fontSizeDialogTitle,
        fontWeight: FontWeight.w700,
        color: darkBlue,
      ),
      contentTextStyle: TextStyle(
        fontSize: UiConstants.fontSizeBody,
        color: Colors.grey.shade800,
        height: 1.4,
      ),
      actionsPadding: UiConstants.dialogActionsPadding,
    ),
    // Bottom sheets
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.white,
      elevation: 8,
      modalElevation: 16,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(UiConstants.bottomSheetBorderRadius)),
      ),
      showDragHandle: true,
      dragHandleColor: Colors.grey.shade400,
      dragHandleSize: UiConstants.dragHandleSize,
    ),
    // Inputvelden in formulieren
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: UiConstants.inputContentPadding,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
        borderSide: const BorderSide(color: darkBlue, width: 2),
      ),
      labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: UiConstants.fontSizeLabel),
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: UiConstants.fontSizeLabel),
    ),
    // Knoppen in dialogen
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: darkBlue,
        padding: UiConstants.buttonPaddingSmall,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: darkBlue,
        padding: UiConstants.buttonPaddingLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkBlue,
        side: const BorderSide(color: darkBlue),
        padding: UiConstants.buttonPaddingSmall,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiConstants.cardBorderRadius),
        ),
      ),
    ),
  );
}
