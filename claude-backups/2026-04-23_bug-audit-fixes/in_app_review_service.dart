import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Slimme In-App Review service.
/// Vraagt een review op het PERFECTE moment — wanneer de gebruiker happy is.
///
/// Triggers (na positieve actie):
/// - Na 3e succesvolle boeking
/// - Na het voltooien van een training
/// - Na het ontvangen van een goede review als trainer
///
/// Regels:
/// - Maximaal 1x per 90 dagen vragen
/// - Niet in de eerste 3 dagen na installatie
/// - Alleen als de gebruiker minimaal 3 sessies heeft gehad
class InAppReviewService {
  InAppReviewService._();
  static final instance = InAppReviewService._();

  static const _prefLastAsked = 'gymies_review_last_asked';
  static const _prefSessionCount = 'gymies_review_session_count';
  static const _prefInstallDate = 'gymies_review_install_date';
  static const _prefDismissCount = 'gymies_review_dismiss_count';

  final InAppReview _inAppReview = InAppReview.instance;

  /// Registreer een positieve actie (boeking, training voltooid, etc.)
  /// De service bepaalt zelf of het een goed moment is om te vragen.
  Future<void> trackPositiveAction() async {
    final prefs = await SharedPreferences.getInstance();

    // Tel positieve acties
    final count = (prefs.getInt(_prefSessionCount) ?? 0) + 1;
    await prefs.setInt(_prefSessionCount, count);

    // Registreer installatiedatum bij eerste keer
    if (!prefs.containsKey(_prefInstallDate)) {
      await prefs.setInt(_prefInstallDate, DateTime.now().millisecondsSinceEpoch);
    }

    // Check of we mogen vragen
    if (await _shouldRequestReview(prefs, count)) {
      await _requestReview(prefs);
    }
  }

  Future<bool> _shouldRequestReview(SharedPreferences prefs, int actionCount) async {
    // Regel 1: Minimaal 3 positieve acties
    if (actionCount < 3) return false;

    // Regel 2: Minimaal 3 dagen sinds installatie
    final installDate = prefs.getInt(_prefInstallDate);
    if (installDate != null) {
      final daysSinceInstall = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(installDate))
          .inDays;
      if (daysSinceInstall < 3) return false;
    }

    // Regel 3: Maximaal 1x per 90 dagen
    final lastAsked = prefs.getInt(_prefLastAsked);
    if (lastAsked != null) {
      final daysSinceLastAsk = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(lastAsked))
          .inDays;
      if (daysSinceLastAsk < 90) return false;
    }

    // Regel 4: Max 3x geweigerd = stop met vragen
    final dismissCount = prefs.getInt(_prefDismissCount) ?? 0;
    if (dismissCount >= 3) return false;

    // Regel 5: Check of de store het toestaat
    try {
      return await _inAppReview.isAvailable();
    } catch (_) {
      return false;
    }
  }

  Future<void> _requestReview(SharedPreferences prefs) async {
    try {
      await _inAppReview.requestReview();
      await prefs.setInt(_prefLastAsked, DateTime.now().millisecondsSinceEpoch);
      if (kDebugMode) debugPrint('[Review] In-app review gevraagd');
    } catch (e) {
      if (kDebugMode) debugPrint('[Review] Fout bij review request: $e');
    }
  }

  /// Open de Play Store / App Store pagina direct (voor een "Beoordeel ons" knop in settings).
  /// Android: gebruikt automatisch de applicationId (com.Gymies.nl).
  /// iOS: gebruikt de appStoreId parameter.
  Future<void> openStoreListing() async {
    try {
      await _inAppReview.openStoreListing(
        appStoreId: '/* iOS App Store ID hier invullen */',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Review] Kan store listing niet openen: $e');
    }
  }
}
