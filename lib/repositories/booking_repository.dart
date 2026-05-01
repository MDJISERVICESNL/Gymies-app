import '../services/gymies_api.dart';

/// BookingRepository — abstractie laag tussen UI en API voor boekingen.
///
/// Voordelen:
/// - Screens hoeven niet te weten hoe API calls werken
/// - Makkelijk te mocken voor tests
/// - Cache-laag kan hier toegevoegd worden
/// - Offline-first met queue kan hier geïmplementeerd worden
///
/// Gebruik:
/// ```dart
/// final repo = BookingRepository(api: context.read<GymiesApi>());
/// final bookings = await repo.getMyBookings();
/// ```
class BookingRepository {
  BookingRepository({required GymiesApi api}) : _api = api;

  final GymiesApi _api;

  /// Haal boekingen op voor de ingelogde gebruiker.
  Future<List<Map<String, dynamic>>> getMyBookings({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (status != null) params['status'] = status;

    final response = await _api.get('bookings', queryParams: params);
    final data = response['data'];
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Maak een nieuwe boeking aan.
  Future<Map<String, dynamic>> createBooking({
    required int trainerUserId,
    required String date,
    required String timeStart,
    required String timeEnd,
    String paymentMethod = 'mollie',
    int? packageId,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'trainer_user_id': trainerUserId,
      'date': date,
      'time_start': timeStart,
      'time_end': timeEnd,
      'payment_method': paymentMethod,
    };
    if (packageId != null) body['package_id'] = packageId;
    if (notes != null) body['notes'] = notes;

    return await _api.post('bookings', body);
  }

  /// Annuleer een boeking.
  Future<Map<String, dynamic>> cancelBooking(int bookingId, {String? reason}) async {
    return await _api.post('bookings/$bookingId/cancel', {
      if (reason != null) 'reason': reason,
    });
  }

  /// Bevestig cash betaling (trainer).
  Future<Map<String, dynamic>> confirmCashPayment(int bookingId) async {
    return await _api.post('bookings/$bookingId/confirm-cash', {
      'confirmed': true,
    });
  }

  /// Haal een specifieke boeking op.
  Future<Map<String, dynamic>> getBooking(int bookingId) async {
    return await _api.get('bookings/$bookingId');
  }
}
