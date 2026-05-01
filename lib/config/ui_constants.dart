import 'package:flutter/material.dart';

/// ──────────────────────────────────────────────────────────────────────────
/// Gymies UI Constants
/// ──────────────────────────────────────────────────────────────────────────
/// Kleuren, border radius, padding, animatie-waarden en andere UI-constanten.
/// Gebruik deze in plaats van hardcoded waarden in screens en widgets.
/// ──────────────────────────────────────────────────────────────────────────

class UiConstants {
  UiConstants._();

  // ── Badge kleuren ───────────────────────────────────────────────────────
  static const Color badgeProPlusColor = Color(0xFFB8860B);
  static const Color badgeTopRatedColor = Color(0xFFFFD700);
  static const Color badgeDiplomaColor = Color(0xFF1B5E20);
  static const Color badgeSessions100Color = Color(0xFF9E9E9E);

  // ── App-brede kleuren ────────────────────────────────────────────────────
  static const Color darkNavyBackground = Color(0xFF0D1B2A);
  static const Color darkNavyCard = Color(0xFF1B2838);
  static const Color blueGrayAccent = Color(0xFF243B54);
  static const Color deepDarkBlue = Color(0xFF0B1F3A);
  static const Color warningYellow = Color(0xFFFEBE23);
  static const Color errorRed = Color(0xFFDC3545);

  // ── Border Radius ───────────────────────────────────────────────────────
  static const double cardBorderRadius = 12.0;
  static const double dialogBorderRadius = 20.0;
  static const double bottomSheetBorderRadius = 24.0;

  // ── Typografie ──────────────────────────────────────────────────────────
  static const double fontSizeH1 = 24.0;
  static const double fontSizeH2 = 18.0;
  static const double fontSizeH3 = 16.0;
  static const double fontSizeLabel = 15.0;
  static const double fontSizeDialogTitle = 20.0;
  static const double fontSizeBody = 16.0;

  // ── Padding ─────────────────────────────────────────────────────────────
  static const EdgeInsets inputContentPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 14);
  static const EdgeInsets dialogActionsPadding =
      EdgeInsets.fromLTRB(24, 0, 24, 20);
  static const EdgeInsets buttonPaddingSmall =
      EdgeInsets.symmetric(horizontal: 20, vertical: 12);
  static const EdgeInsets buttonPaddingLarge =
      EdgeInsets.symmetric(horizontal: 24, vertical: 14);

  // ── Animaties ───────────────────────────────────────────────────────────
  /// Basis animatie duration voor page transitions.
  static const Duration animDurationDefault = Duration(milliseconds: 280);

  /// Stagger waarden voor lijst-animaties.
  static const int animStaggerBaseMs = 400;
  static const int animStaggerStepMs = 80;
  static const int animStaggerMaxItems = 10;

  /// Stagger voor profile hub items.
  static const int animProfileBaseMs = 50;
  static const int animProfileStepMs = 50;

  /// Stagger voor chat messages.
  static const int animChatBaseMs = 350;
  static const int animChatStepMs = 60;
  static const int animChatMaxItems = 8;

  // ── Drag Handle ─────────────────────────────────────────────────────────
  static const Size dragHandleSize = Size(40, 4);
}
