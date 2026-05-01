import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Haptic feedback helper voor Gymies.
/// Centraal beheerpunt voor alle trillingen in de app.
/// Respecteert de gebruikersinstelling via SharedPreferences.
///
/// Initialiseer bij app start:
/// ```dart
/// await Haptics.init();
/// ```
///
/// Gebruik:
/// ```dart
/// onTap: () {
///   Haptics.light();
///   // doe iets
/// }
/// ```
class Haptics {
  Haptics._();

  static const _kHapticsEnabledKey = 'gymies_haptics_enabled';

  /// Interne state — standaard aan.
  static bool _enabled = true;

  /// Of trillingen zijn ingeschakeld.
  static bool get isEnabled => _enabled;

  /// Laad de instelling uit SharedPreferences. Roep aan bij app start.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_kHapticsEnabledKey) ?? true;
  }

  /// Schakel trillingen in of uit en sla de voorkeur op.
  static Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHapticsEnabledKey, enabled);
  }

  /// Lichte tik — voor kleine interacties (tab switch, toggle, swipe).
  static void light() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  /// Medium tik — voor bevestigingen (boeking, like, save).
  static void medium() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// Zware tik — voor belangrijke acties (betaling, delete).
  static void heavy() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
  }

  /// Selectie tik — voor scroll/picker selecties.
  static void selection() {
    if (!_enabled) return;
    HapticFeedback.selectionClick();
  }

  /// Succes patroon — voor positieve bevestigingen.
  /// Dubbele lichte tik: ta-tap.
  static Future<void> success() async {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.lightImpact();
  }

  /// Error patroon — voor fouten en waarschuwingen.
  /// Drie korte tikken: tap-tap-tap.
  static Future<void> error() async {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.mediumImpact();
  }

  /// Notificatie patroon — voor nieuwe berichten/boekingen.
  static Future<void> notification() async {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    HapticFeedback.mediumImpact();
  }

  /// Waarschuwing patroon — voor bijna-verlopen, lage voorraad, etc.
  /// Twee medium tikken met pauze: tum... tum.
  static Future<void> warning() async {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 200));
    HapticFeedback.mediumImpact();
  }

  /// Celebration patroon — voor mijlpalen, achievements, streaks.
  /// Opbouwend ritme: light → medium → heavy. Voelt als een drumroll.
  static Future<void> celebration() async {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact();
  }

  /// Payment ontvangen — zware bevestiging voor trainers.
  /// Eén krachtige tik gevolgd door een zachte: BOEM... tap.
  static Future<void> paymentReceived() async {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 200));
    HapticFeedback.lightImpact();
  }
}
