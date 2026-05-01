import 'package:flutter/foundation.dart';

import 'gymies_api.dart';

/// OptimisticActionService
/// ───────────────────────
/// Beheert optimistic UI updates: de UI wordt direct bijgewerkt
/// voordat de API-call voltooid is. Bij falen wordt de actie
/// teruggedraaid (rollback) en de gebruiker geïnformeerd.
///
/// Ondersteunt:
/// - Favoriet togglen (instant hartje)
/// - Review plaatsen (direct zichtbaar met "wordt verzonden")
/// - Sessie annuleren (direct uit lijst, rollback bij falen)
///
/// Gebruik:
/// ```dart
/// final optimistic = context.read<OptimisticActionService>();
///
/// // Favoriet toggle:
/// optimistic.toggleFavorite(trainerId);
///
/// // Luister naar changes:
/// optimistic.addListener(() {
///   final isFav = optimistic.isFavorite(trainerId);
/// });
/// ```
class OptimisticActionService extends ChangeNotifier {
  OptimisticActionService({required GymiesApi api}) : _api = api;

  final GymiesApi _api;

  // ── Favorieten ──────────────────────────────────────────────────────

  /// Lokale favorieten set (optimistic state).
  final Set<String> _favorites = {};

  /// Pending API calls die nog niet bevestigd zijn.
  final Set<String> _pendingFavorites = {};

  /// IDs die gefaald zijn (voor rollback indicator).
  final Set<String> _failedFavorites = {};

  bool _favoritesLoaded = false;

  bool isFavorite(String trainerUserId) => _favorites.contains(trainerUserId);
  bool isFavoritePending(String trainerUserId) =>
      _pendingFavorites.contains(trainerUserId);
  Set<String> get favorites => Set.unmodifiable(_favorites);

  /// Laad initiële favorieten van API.
  Future<void> loadFavorites() async {
    if (_favoritesLoaded) return;
    try {
      final ids = await _api.getFavoriteTrainerIds();
      _favorites.clear();
      _favorites.addAll(ids.map((e) => e.toString()));
      _favoritesLoaded = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('[Optimistic] Favorieten laden mislukt: $e');
    }
  }

  /// Toggle favoriet — direct UI update, API op achtergrond.
  Future<void> toggleFavorite(String trainerUserId) async {
    final wasAdding = !_favorites.contains(trainerUserId);

    // Optimistic update
    if (wasAdding) {
      _favorites.add(trainerUserId);
    } else {
      _favorites.remove(trainerUserId);
    }
    _pendingFavorites.add(trainerUserId);
    _failedFavorites.remove(trainerUserId);
    notifyListeners();

    try {
      if (wasAdding) {
        await _api.addFavoriteTrainer(trainerUserId);
      } else {
        await _api.removeFavoriteTrainer(trainerUserId);
      }

      _pendingFavorites.remove(trainerUserId);
      notifyListeners();

      if (kDebugMode) {
        debugPrint(
            '[Optimistic] Favoriet ${wasAdding ? "toegevoegd" : "verwijderd"}: $trainerUserId');
      }
    } catch (e) {
      // Rollback
      if (wasAdding) {
        _favorites.remove(trainerUserId);
      } else {
        _favorites.add(trainerUserId);
      }
      _pendingFavorites.remove(trainerUserId);
      _failedFavorites.add(trainerUserId);
      notifyListeners();

      if (kDebugMode) {
        debugPrint('[Optimistic] Favoriet toggle mislukt, rollback: $e');
      }
    }
  }

  // ── Optimistic Reviews ──────────────────────────────────────────────

  /// Lokale pending reviews (getoond als "wordt verzonden").
  final List<PendingReview> _pendingReviews = [];

  List<PendingReview> get pendingReviews =>
      List.unmodifiable(_pendingReviews);

  /// Plaats een review optimistisch — direct zichtbaar in UI.
  Future<bool> submitReview({
    required String bookingId,
    required int rating,
    required String comment,
    required String trainerName,
  }) async {
    final review = PendingReview(
      bookingId: bookingId,
      rating: rating,
      comment: comment,
      trainerName: trainerName,
      submittedAt: DateTime.now(),
    );

    _pendingReviews.add(review);
    notifyListeners();

    try {
      await _api.submitReview(
        bookingId: bookingId,
        rating: rating,
        message: comment,
      );

      review.status = PendingReviewStatus.confirmed;
      notifyListeners();

      // Na 3 seconden uit de pending lijst halen
      Future.delayed(const Duration(seconds: 3), () {
        _pendingReviews.remove(review);
        notifyListeners();
      });

      return true;
    } catch (e) {
      review.status = PendingReviewStatus.failed;
      notifyListeners();

      if (kDebugMode) {
        debugPrint('[Optimistic] Review submit mislukt: $e');
      }
      return false;
    }
  }

  /// Verwijder een gefaalde review uit de pending lijst.
  void dismissFailedReview(PendingReview review) {
    _pendingReviews.remove(review);
    notifyListeners();
  }

  // ── Optimistic Cancel ───────────────────────────────────────────────

  /// IDs van boekingen die optimistisch geannuleerd zijn.
  final Set<String> _optimisticallyCancelled = {};

  bool isOptimisticallyCancelled(String bookingId) =>
      _optimisticallyCancelled.contains(bookingId);

  /// Markeer boeking als geannuleerd in de UI, API op achtergrond.
  /// Retourneert true als de API ook slaagde.
  Future<bool> cancelBookingOptimistic({
    required String bookingId,
    String? reason,
    required void Function() onRollback,
  }) async {
    _optimisticallyCancelled.add(bookingId);
    notifyListeners();

    try {
      await _api.cancelBooking(bookingId: bookingId, reason: reason);
      if (kDebugMode) {
        debugPrint('[Optimistic] Boeking $bookingId geannuleerd');
      }
      return true;
    } catch (e) {
      // Rollback
      _optimisticallyCancelled.remove(bookingId);
      notifyListeners();
      onRollback();

      if (kDebugMode) {
        debugPrint('[Optimistic] Annulering mislukt, rollback: $e');
      }
      return false;
    }
  }
}

// ── Data classes ────────────────────────────────────────────────────────

enum PendingReviewStatus { sending, confirmed, failed }

class PendingReview {
  PendingReview({
    required this.bookingId,
    required this.rating,
    required this.comment,
    required this.trainerName,
    required this.submittedAt,
    this.status = PendingReviewStatus.sending,
  });

  final String bookingId;
  final int rating;
  final String comment;
  final String trainerName;
  final DateTime submittedAt;
  PendingReviewStatus status;
}
