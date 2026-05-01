import 'package:flutter/foundation.dart';

import '../models/promotion.dart';
import 'gymies_api.dart';

/// Service voor het beheren van promoties in de app.
/// Houdt de actieve promo bij, valideert codes, en levert promo-data aan de UI.
class PromotionService extends ChangeNotifier {
  PromotionService({required GymiesApi api}) : _api = api;

  final GymiesApi _api;

  TrainerActivePromotion? _activePromotion;
  bool _loading = false;
  String? _error;

  // ─── Getters ───

  TrainerActivePromotion? get activePromotion => _activePromotion;
  bool get isLoading => _loading;
  String? get error => _error;

  /// Heeft de trainer een actieve promotie?
  bool get hasActivePromotion =>
      _activePromotion != null && _activePromotion!.isActive;

  /// Is de trainer in een proefperiode?
  bool get isInTrial =>
      _activePromotion != null &&
      _activePromotion!.isTrial &&
      _activePromotion!.isActive;

  /// Is de trial bijna voorbij? (voor waarschuwingsbanner)
  bool get isTrialEndingSoon =>
      _activePromotion != null && _activePromotion!.isTrialEndingSoon;

  /// Dagen resterende trial (of null)
  int? get trialDaysRemaining =>
      isInTrial ? _activePromotion!.daysRemaining : null;

  /// Korte tekst voor de UI (bijv. "Proefperiode: nog 5 dagen")
  String? get promotionSummary =>
      hasActivePromotion ? _activePromotion!.summaryText : null;

  // ─── Laden ───

  /// Haal de actieve promotie op van de backend.
  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await _api.getActivePromotion();
      final hasPromo = res['has_active_promotion'] == true;
      final promoData = res['promotion'];

      if (hasPromo && promoData is Map<String, dynamic>) {
        _activePromotion = TrainerActivePromotion.fromJson(promoData);
      } else {
        _activePromotion = null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[PromotionService] Fout bij laden: $e');
      // Geen error tonen aan gebruiker — promo is optioneel
      _activePromotion = null;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ─── Code valideren ───

  /// Valideer een promo-code voor een specifiek tier.
  /// Retourneert een AvailablePromotion bij succes, of een error string.
  Future<({AvailablePromotion? promotion, String? error})> validateCode(
    String code,
    String tier,
  ) async {
    try {
      final res = await _api.validatePromoCode(code: code, tier: tier);
      final valid = res['valid'] == true;

      if (!valid) {
        final errorMsg = (res['error'] ?? 'Deze code is niet geldig.').toString();
        return (promotion: null, error: errorMsg);
      }

      final promoData = res['promotion'];
      if (promoData is Map<String, dynamic>) {
        return (
          promotion: AvailablePromotion.fromJson(promoData),
          error: null,
        );
      }

      return (promotion: null, error: 'Ongeldig antwoord van server.');
    } catch (e) {
      return (promotion: null, error: 'Kon code niet valideren. Probeer opnieuw.');
    }
  }

  // ─── Activeren ───

  /// Activeer een promotie na succesvolle betaling/trial start.
  Future<bool> activate({
    required int promotionId,
    required String tier,
    String? code,
  }) async {
    try {
      final res = await _api.activatePromotion(
        promotionId: promotionId,
        tier: tier,
        code: code,
      );

      if (res['success'] == true) {
        final promoData = res['promotion'];
        if (promoData is Map<String, dynamic>) {
          _activePromotion = TrainerActivePromotion.fromJson(promoData);
          notifyListeners();
        }
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('[PromotionService] Activatie mislukt: $e');
      return false;
    }
  }

  /// Reset (bijv. bij uitloggen).
  void clear() {
    _activePromotion = null;
    _error = null;
    _loading = false;
    notifyListeners();
  }
}
