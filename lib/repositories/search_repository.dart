import '../services/gymies_api.dart';

/// SearchRepository — abstractie laag voor trainer zoeken.
///
/// Toekomstige uitbreidingen:
/// - Lokale cache van recente zoekresultaten
/// - Offline-first: toon gecachte trainers als geen internet
/// - Debounce/throttle logica
class SearchRepository {
  SearchRepository({required GymiesApi api}) : _api = api;

  final GymiesApi _api;

  /// Zoek trainers op basis van locatie, specialisme, etc.
  Future<List<Map<String, dynamic>>> searchTrainers({
    double? lat,
    double? lng,
    int? radiusKm,
    String? specialty,
    String? query,
    int limit = 20,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (lat != null) params['lat'] = '$lat';
    if (lng != null) params['lng'] = '$lng';
    if (radiusKm != null) params['radius_km'] = '$radiusKm';
    if (specialty != null) params['specialty'] = specialty;
    if (query != null && query.isNotEmpty) params['q'] = query;

    final response = await _api.get('trainers', queryParams: params);
    final data = response['data'] ?? response['trainers'];
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Haal een trainer profiel op via slug.
  Future<Map<String, dynamic>> getTrainerBySlug(String slug) async {
    return await _api.get('trainers/by-slug/$slug');
  }

  /// Haal een trainer profiel op via ID.
  Future<Map<String, dynamic>> getTrainerById(int id) async {
    return await _api.get('trainers/$id');
  }

  /// Haal beschikbaarheid op voor een trainer.
  Future<Map<String, dynamic>> getAvailability(int trainerId) async {
    return await _api.get('trainers/$trainerId/availability');
  }

  /// Haal specialismen op.
  Future<List<Map<String, dynamic>>> getSpecialties() async {
    final response = await _api.get('specialties');
    final data = response['data'] ?? response['specialties'];
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Log een zoekopdracht (analytics).
  Future<void> logSearch({
    required String query,
    String? city,
    double? lat,
    double? lng,
    int resultCount = 0,
  }) async {
    try {
      await _api.post('search-log', {
        'query': query,
        'city': ?city,
        'lat': ?lat,
        'lng': ?lng,
        'result_count': resultCount,
      });
    } catch (_) {
      // Search logging mag nooit falen voor de gebruiker
    }
  }
}
