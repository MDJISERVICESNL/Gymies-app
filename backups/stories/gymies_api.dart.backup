import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/booking.dart';
import '../models/trainer.dart';
import '../models/trainer_summary.dart';
import '../models/trainer_models.dart';
import 'api_client.dart';

/// Gymies API: trainers, bookings, etc.
class GymiesApi {
  GymiesApi({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  // ── Broadcasting / Pusher ───────────────────────────────────
  /// GET broadcasting/config — haalt Reverb/Pusher config op (key, host, port, scheme).
  /// Wordt gebruikt door PusherWebSocketService om te verbinden.
  Future<Map<String, dynamic>> getBroadcastConfig() async {
    final res = await _api.get('broadcasting/config');
    return _asMap(res) ?? <String, dynamic>{};
  }

  /// POST broadcasting/auth — authenticeert een private channel.
  /// Stuurt socket_id + channel_name, ontvangt { auth: "key:signature" }.
  Future<String?> authenticateBroadcastChannel(
    String socketId,
    String channelName,
  ) async {
    final res = await _api.post('broadcasting/auth', {
      'socket_id': socketId,
      'channel_name': channelName,
    });
    final auth = res['auth'] ?? (res['data'] is Map ? res['data']['auth'] : null);
    return auth?.toString();
  }

  // ── WebSocket Ticket ─────────────────────────────────────────
  /// Vraag een kortstondig WebSocket ticket op bij de backend.
  /// Het ticket vervangt het access_token in de WS query string
  /// zodat het lange-termijn token niet wordt blootgesteld.
  /// Verwacht response: { "ticket": "<short-lived-token>" }
  /// Fallback: geeft null terug als het endpoint (nog) niet bestaat.
  Future<String?> getWsTicket() async {
    try {
      final res = await _api.post('ws-ticket', {});
      final ticket = res['ticket'] ?? res['data']?['ticket'];
      if (ticket is String && ticket.isNotEmpty) return ticket;
      return null;
    } catch (_) {
      // Endpoint bestaat nog niet op de backend — fallback naar token
      return null;
    }
  }

  // ── Specialties ─────────────────────────────────────────

  /// GET specialties — publieke lijst van alle beschikbare specialiteiten.
  Future<List<Map<String, dynamic>>> getSpecialties() async {
    final res = await _api.get('specialties');
    final raw = res['data'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET trainer/specialties — specialiteiten van ingelogde trainer + selected IDs.
  Future<Map<String, dynamic>> getTrainerSpecialties() async {
    return await _api.get('trainer/specialties');
  }

  /// PUT trainer/specialties — trainer kiest specialiteiten.
  Future<Map<String, dynamic>> updateTrainerSpecialties(List<int> specialtyIds) async {
    return await _api.put('trainer/specialties', {
      'specialty_ids': specialtyIds,
    });
  }

  /// POST trainer/specialties/request — vraag nieuwe specialiteit aan.
  Future<Map<String, dynamic>> requestNewSpecialty(String name) async {
    return await _api.post('trainer/specialties/request', {
      'name': name,
    });
  }

  // ── Trainers ──────────────────────────────────────────

  /// GET trainers?query=...&lat=...&lng=...
  /// Pass lat/lng voor afstandsberekening (distance_km per trainer).
  Future<List<Trainer>> getTrainers({
    String? query,
    double? lat,
    double? lng,
  }) async {
    final params = <String, String>{};
    if (query != null && query.trim().isNotEmpty) {
      params['query'] = query.trim();
    }
    if (lat != null && lng != null) {
      params['lat'] = lat.toString();
      params['lng'] = lng.toString();
    }
    final res = await _api.get(
      'trainers',
      queryParams: params.isEmpty ? null : params,
    );

    // Laravel: { data: [...] } of direct array
    dynamic raw = res['data'];
    raw ??= res['trainers'] ?? res;
    if (raw is! List) return <Trainer>[];

    return raw
        .map((e) {
          final map = _asMap(e);
          if (map != null) return Trainer.fromJson(map);
          return null;
        })
        .whereType<Trainer>()
        .toList();
  }

  /// GET trainers/{id}
  Future<Trainer?> getTrainerById(String trainerId) async {
    final res = await _api.get('trainers/$trainerId');
    final map = _asMap(res['data'] ?? res['trainer'] ?? res);
    if (map == null) return null;
    return Trainer.fromJson(map);
  }

  /// GET trainers/by-slug/{slug} – volgt redirect naar trainers/{id}
  Future<Trainer?> getTrainerBySlug(String slug) async {
    final trimmed = slug.trim();
    if (trimmed.isEmpty) return null;
    final res = await _api.get('trainers/by-slug/$trimmed');
    final map = _asMap(res['data'] ?? res['trainer'] ?? res);
    if (map == null) return null;
    return Trainer.fromJson(map);
  }

  /// GET trainers/{id}/availability
  Future<List<Map<String, dynamic>>> getTrainerPublicAvailability(
    String trainerId,
  ) async {
    final res = await _api.get('trainers/$trainerId/availability');
    // API kan slots retourneren als:
    //   { data: [ ... ] }                 — platte array
    //   { data: { slots: [ ... ] } }      — genest object
    //   { slots: [ ... ] }                — direct
    //   { availability: [ ... ] }         — alias
    dynamic raw = res['data'] ?? res['availability'] ?? res['slots'] ?? res;
    // Als data een object is met een slots-key, pak die
    if (raw is Map) {
      raw = raw['slots'] ?? raw['availability'] ?? raw['data'] ?? [];
    }
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET trainers/{id}/packages
  Future<List<Map<String, dynamic>>> getTrainerPublicPackages(
    String trainerId,
  ) async {
    final res = await _api.get('trainers/$trainerId/packages');
    final raw = res['data'] ?? res['packages'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET trainers/{id}/media – publieke media voor klanten.
  Future<Map<String, dynamic>> getTrainerPublicMedia(String trainerId) async {
    try {
      final res = await _api.get('trainers/$trainerId/media');
      return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
    } on ApiException catch (e) {
      if (e.statusCode == 404) return <String, dynamic>{};
      rethrow;
    }
  }

  /// GET trainer/media – eigen media (trainer).
  Future<List<Map<String, dynamic>>> getTrainerMedia() async {
    try {
      final res = await _api.get('trainer/media');
      final raw = res['data'] ?? res['media'] ?? res['items'] ?? res;
      if (raw is! List) return [];
      return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
    } on ApiException catch (e) {
      if (e.statusCode == 404) return [];
      rethrow;
    }
  }

  /// POST trainer/media – nieuw media-item uploaden.
  Future<Map<String, dynamic>> postTrainerMedia({
    required String filePath,
    required String type,
    required String usage,
    String? category,
    int? sortOrder,
  }) async {
    final fields = <String, String>{
      'type': type,
      'media_type': type,
      'usage': usage,
      if (category != null && category.trim().isNotEmpty) 'category': category,
      if (sortOrder != null) 'sort_order': sortOrder.toString(),
    };
    final file = await http.MultipartFile.fromPath('file', filePath);
    final res = await _api.postMultipart(
      'trainer/media',
      fileField: 'file',
      file: file,
      fields: fields,
    );
    return _asMap(res['data'] ?? res['media'] ?? res) ?? res;
  }

  /// PUT trainer/media/{id} – media-item bijwerken (categorie, volgorde, etc.).
  Future<Map<String, dynamic>> updateTrainerMedia(
    String id, {
    String? usage,
    String? category,
    int? sortOrder,
  }) async {
    final body = <String, dynamic>{};
    if (usage != null) body['usage'] = usage;
    if (category != null) body['category'] = category;
    if (sortOrder != null) body['sort_order'] = sortOrder;
    final res = await _api.put('trainer/media/$id', body);
    return _asMap(res['data'] ?? res['media'] ?? res) ?? res;
  }

  /// DELETE trainer/media/{id}
  Future<void> deleteTrainerMedia(String id) async {
    await _api.delete('trainer/media/$id');
  }


  /// POST trainer/media/{mediaId}/featured – set media as featured.
  Future<void> setFeaturedMedia(String mediaId) async {
    await _api.post('trainer/media/$mediaId/featured', {});
  }

  /// POST trainer/media/bulk-delete – delete multiple media items.
  Future<void> deleteTrainerMediaBulk(List<String> mediaIds) async {
    await _api.post('trainer/media/bulk-delete', {'media_ids': mediaIds});
  }
  /// GET trainer/storefront-cms – etalage (stories, gallery, SEO).
  Future<Map<String, dynamic>> getTrainerStorefrontCms() async {
    final res = await _api.get('trainer/storefront-cms');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// PUT trainer/storefront-cms – etalage bijwerken.
  Future<Map<String, dynamic>> updateTrainerStorefrontCms(
    Map<String, dynamic> body,
  ) async {
    final res = await _api.put('trainer/storefront-cms', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST bookings/direct-book (fallback: bookings)
  Future<Map<String, dynamic>> createDirectBooking({
    required String trainerUserId,
    required DateTime scheduledAt,
    String? packageId,
    String? note,
    String? availabilitySlotId,
    String? holdId,
    String? holdToken,
  }) async {
    final body = <String, dynamic>{
      'trainer_user_id': trainerUserId,
      'trainer_id': trainerUserId,
      'scheduled_at': scheduledAt.toIso8601String(),
      if (packageId != null && packageId.trim().isNotEmpty)
        'package_id': packageId.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (note != null && note.trim().isNotEmpty) 'notes': note.trim(),
      if (availabilitySlotId != null && availabilitySlotId.trim().isNotEmpty)
        'availability_slot_id': availabilitySlotId.trim(),
      if (availabilitySlotId != null && availabilitySlotId.trim().isNotEmpty)
        'slot_id': availabilitySlotId.trim(),
      if (holdId != null && holdId.trim().isNotEmpty) 'hold_id': holdId.trim(),
      if (holdToken != null && holdToken.trim().isNotEmpty)
        'hold_token': holdToken.trim(),
      'slot_date': scheduledAt.toIso8601String().substring(0, 10),
      'day_of_week': scheduledAt.weekday,
      'week_number': _isoWeekNumber(scheduledAt),
    };
    try {
      final res = await _api.post('bookings/direct-book', body);
      return _asMap(res['data'] ?? res['booking'] ?? res) ??
          <String, dynamic>{};
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      final res = await _api.post('bookings', body);
      return _asMap(res['data'] ?? res['booking'] ?? res) ??
          <String, dynamic>{};
    }
  }

  /// POST hold a public trainer slot to prevent race conditions.
  /// Backend creates a temporary hold (5 min) so no one else can book the same slot.
  Future<Map<String, dynamic>> holdTrainerPublicSlot({
    required String trainerUserId,
    required DateTime scheduledAt,
    String? availabilitySlotId,
  }) async {
    final body = <String, dynamic>{
      'trainer_user_id': trainerUserId.trim(),
      'trainer_id': trainerUserId.trim(),
      'scheduled_at': scheduledAt.toIso8601String(),
      if (availabilitySlotId != null && availabilitySlotId.trim().isNotEmpty)
        'availability_slot_id': availabilitySlotId.trim(),
      if (availabilitySlotId != null && availabilitySlotId.trim().isNotEmpty)
        'slot_id': availabilitySlotId.trim(),
      'slot_date': scheduledAt.toIso8601String().substring(0, 10),
      'day_of_week': scheduledAt.weekday,
      'week_number': _isoWeekNumber(scheduledAt),
    };
    try {
      final res = await _api.post('bookings/hold-slot', body);
      return _asMap(res['data'] ?? res['hold'] ?? res) ?? <String, dynamic>{};
    } on ApiException catch (e) {
      // Fallback als hold endpoint nog niet live is op backend
      if (e.statusCode == 404) return <String, dynamic>{};
      rethrow;
    }
  }

  /// DELETE release a held slot (when user navigates away without booking).
  Future<void> releaseSlotHold(String holdId) async {
    try {
      await _api.delete('bookings/hold-slot/$holdId');
    } catch (_) {
      // Best-effort: als release faalt, verloopt de hold automatisch na 5 min
    }
  }

  /// POST extend a slot hold to prevent timeout during slow connections.
  Future<Map<String, dynamic>> extendSlotHold(String holdId) async {
    try {
      final res = await _api.post('bookings/hold-slot/$holdId/extend', {});
      return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 410) {
        // Hold not found or expired — caller should handle
        return <String, dynamic>{'error': true, 'status': e.statusCode};
      }
      rethrow;
    }
  }

  /// GET bookings voor ingelogde klant.
  Future<List<Booking>> getBookings() async {
    final res = await _api.get('bookings');

    dynamic raw = res['data'];
    raw ??= res['bookings'] ?? res;
    if (raw is! List) return <Booking>[];

    return raw
        .map((e) {
          final map = _asMap(e);
          if (map != null) return Booking.fromJson(map);
          return null;
        })
        .whereType<Booking>()
        .toList();
  }

  /// GET bookings/{id}/payment-status
  Future<Map<String, dynamic>> getBookingPaymentStatus(String bookingId) async {
    final res = await _api.get('bookings/$bookingId/payment-status');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST bookings/{id}/payments/start
  Future<Map<String, dynamic>> startBookingPayment({
    required String bookingId,
    String? promoCode,
    String? paymentMethod,
  }) async {
    final body = <String, dynamic>{
      // Deep link return URL: na Mollie betaling terug naar de app
      'return_url': 'gymies://payment/complete?booking_id=$bookingId',
    };
    if (promoCode != null && promoCode.trim().isNotEmpty) {
      body['promo_code'] = promoCode.trim();
      body['code'] = promoCode.trim();
    }
    if (paymentMethod != null && paymentMethod.trim().isNotEmpty) {
      body['payment_method'] = paymentMethod.trim();
      body['method'] = paymentMethod.trim();
      body['pay_with'] = paymentMethod.trim();
    }
    final res = await _api.post('bookings/$bookingId/payments/start', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET bookings/{id}/cancellation-preview
  Future<Map<String, dynamic>> getBookingCancellationPreview(
    String bookingId,
  ) async {
    final res = await _api.get('bookings/$bookingId/cancellation-preview');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST bookings/{id}/cancel
  Future<void> cancelBooking({
    required String bookingId,
    String? reason,
  }) async {
    final body = <String, dynamic>{
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    };
    await _api.post('bookings/$bookingId/cancel', body);
  }

  /// POST bookings/{id}/reschedule-request
  Future<void> requestBookingReschedule({
    required String bookingId,
    required DateTime requestedAt,
    String? note,
  }) async {
    await _api.post('bookings/$bookingId/reschedule-request', {
      'requested_at': requestedAt.toIso8601String(),
      'scheduled_at': requestedAt.toIso8601String(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (note != null && note.trim().isNotEmpty) 'reason': note.trim(),
    });
  }

  /// POST bookings/{id}/reschedule-respond – verzetverzoek beantwoorden (akkoord/afwijzen/ander voorstel).
  Future<Map<String, dynamic>> respondToRescheduleRequest({
    required String bookingId,
    required String action,
    DateTime? requestedAt,
    String? note,
  }) async {
    final body = <String, dynamic>{
      'action': action.trim().toLowerCase(),
      if (requestedAt != null) 'requested_at': requestedAt.toIso8601String(),
      if (requestedAt != null) 'scheduled_at': requestedAt.toIso8601String(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
    final res = await _api.post('bookings/$bookingId/reschedule-respond', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET bookings/{id}/checkin-qr – QR check-in token ophalen voor klant.
  /// Backend: GymiesCheckinController@getCheckinQr
  /// Returns: { qr_value, token, backup_code, expires_in, expires_at, booking_id }
  Future<Map<String, dynamic>> getBookingCheckInQr(String bookingId) async {
    final res = await _api.get('bookings/$bookingId/checkin-qr');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST checkin/scan – trainer scant QR-code van klant.
  /// Backend: GymiesCheckinController@scanCheckin
  /// Stuurt token + optioneel GPS-coördinaten.
  Future<void> markBookingCheckedIn({
    required String bookingId,
    String? qrToken,
    String? payload,
    String source = 'trainer_scan',
    double? trainerLat,
    double? trainerLng,
  }) async {
    final body = <String, dynamic>{
      if (qrToken != null && qrToken.trim().isNotEmpty) 'token': qrToken.trim(),
      if (payload != null && payload.trim().isNotEmpty)
        'payload': payload.trim(),
      'source': source,
      if (trainerLat != null) 'trainer_lat': trainerLat,
      if (trainerLng != null) 'trainer_lng': trainerLng,
    };
    await _api.post('checkin/scan', body);
  }

  /// POST checkin/manual – handmatige check-in met 6-cijferige backup code.
  /// Backend: GymiesCheckinController@manualCheckin
  Future<void> manualCheckin({
    String? bookingId,
    required String backupCode,
    double? trainerLat,
    double? trainerLng,
  }) async {
    final body = <String, dynamic>{
      'backup_code': backupCode.trim(),
      if (bookingId != null && bookingId.trim().isNotEmpty)
        'booking_id': bookingId.trim(),
      if (trainerLat != null) 'trainer_lat': trainerLat,
      if (trainerLng != null) 'trainer_lng': trainerLng,
    };
    await _api.post('checkin/manual', body);
  }

  /// POST checkin/report-fraud – identiteitsfraude melden.
  /// Backend: GymiesCheckinController@reportIdentityFraud
  Future<void> reportIdentityFraud({
    required String bookingId,
    required String reason,
    String? evidenceUrl,
  }) async {
    final body = <String, dynamic>{
      'booking_id': bookingId.trim(),
      'reason': reason.trim(),
      if (evidenceUrl != null && evidenceUrl.trim().isNotEmpty)
        'evidence_url': evidenceUrl.trim(),
    };
    await _api.post('checkin/report-fraud', body);
  }

  /// POST bookings/{id}/safe-session/start – safe session starten.
  /// Backend: GymiesCheckinController@startSafeSession
  Future<void> startSafeSession({
    required String bookingId,
    String? note,
  }) async {
    final body = <String, dynamic>{
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
    await _api.post('bookings/$bookingId/safe-session/start', body);
  }

  /// POST bookings/{id}/safe-session/heartbeat – klant bevestigt "Ik ben OK".
  /// Backend: GymiesCheckinController@safeSessionHeartbeat
  /// Reset de overdue timer zodat het noodcontact niet onnodig gewaarschuwd wordt.
  Future<void> safeSessionHeartbeat({required String bookingId}) async {
    await _api.post('bookings/$bookingId/safe-session/heartbeat', {});
  }

  /// GET bookings/{id}/safe-session/status – huidige safe session status ophalen.
  /// Backend: GymiesCheckinController@safeSessionStatus
  /// Returns: { active, started_at, expected_end_at, minutes_remaining, escalation }
  Future<Map<String, dynamic>> getSafeSessionStatus(String bookingId) async {
    final res = await _api.get('bookings/$bookingId/safe-session/status');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST bookings/{id}/checkout – sessie afronden (safe session stop).
  /// Backend: GymiesCheckinController@checkOut
  Future<void> checkoutBooking(String bookingId) async {
    await _api.post('bookings/$bookingId/checkout', {});
  }

  /// POST sos/alert – SOS-noodalert met optioneel GPS en booking.
  /// Backend: GymiesCheckinController@sosAlert
  /// Notificeert: noodcontact, platform admin, en andere partij.
  Future<void> sendSosAlert({
    String? bookingId,
    String? note,
    double? latitude,
    double? longitude,
  }) async {
    final body = <String, dynamic>{
      if (bookingId != null && bookingId.trim().isNotEmpty)
        'booking_id': bookingId.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
    };
    await _api.post('sos/alert', body);
  }

  /// POST trainer booking no-show with reason + optional evidence.
  /// Backend route: POST bookings/{id}/report-trainer-no-show
  Future<void> markTrainerBookingNoShow({
    required String bookingId,
    required String reason,
    String? note,
    String? evidenceUrl,
  }) async {
    final body = <String, dynamic>{
      'status': 'no_show',
      'no_show_reason': reason.trim(),
      if (note != null && note.trim().isNotEmpty) 'no_show_note': note.trim(),
      if (evidenceUrl != null && evidenceUrl.trim().isNotEmpty)
        'no_show_evidence_url': evidenceUrl.trim(),
    };
    await _api.post('bookings/$bookingId/report-trainer-no-show', body);
  }

  /// GET me - klant/profiel data.
  /// [explicitToken] – gebruik dit token voor deze request (bypass shared state, bv. direct na login).
  Future<Map<String, dynamic>> getMe({String? explicitToken}) async {
    final res = explicitToken != null && explicitToken.isNotEmpty
        ? await _api.get('me', explicitToken: explicitToken)
        : await _api.get('me');
    return _asMap(res['data'] ?? res['user'] ?? res) ?? <String, dynamic>{};
  }

  /// Debug: controleer of server de token ontvangt en in DB vindt (geen auth nodig).
  Future<Map<String, dynamic>> debugTokenCheck({String? explicitToken}) async {
    final res = explicitToken != null && explicitToken.isNotEmpty
        ? await _api.get('debug-token-check', explicitToken: explicitToken)
        : await _api.get('debug-token-check');
    return _asMap(res) ?? <String, dynamic>{};
  }

  /// PUT/POST me - profiel bijwerken (incl. noodcontact).
  /// Velden moeten exact matchen met backend GymiesAuthController::updateMe()
  /// validatie: display_name, phone, city, gender, first_name, last_name,
  /// date_of_birth, address_line1, postcode, country, emergency_contact_*.
  Future<Map<String, dynamic>> updateMe({
    String? displayName,
    String? phone,
    String? city,
    String? gender,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactEmail,
    String? onboardingCompletedAt,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null && displayName.trim().isNotEmpty) {
      body['display_name'] = displayName.trim();
    }
    if (phone != null) body['phone'] = phone.trim();
    if (city != null) body['city'] = city.trim();
    if (gender != null && gender.trim().isNotEmpty) {
      body['gender'] = gender.trim();
    }
    if (emergencyContactName != null) {
      body['emergency_contact_name'] = emergencyContactName.trim();
    }
    if (emergencyContactPhone != null) {
      body['emergency_contact_phone'] = emergencyContactPhone.trim();
    }
    if (emergencyContactEmail != null) {
      body['emergency_contact_email'] = emergencyContactEmail.trim();
    }
    if (onboardingCompletedAt != null) {
      body['onboarding_completed_at'] = onboardingCompletedAt;
    }
    try {
      final res = await _api.put('me', body);
      return _asMap(res['data'] ?? res['user'] ?? res) ?? <String, dynamic>{};
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      final res = await _api.post('me', body);
      return _asMap(res['data'] ?? res['user'] ?? res) ?? <String, dynamic>{};
    }
  }

  /// POST auth/change-password – wachtwoord wijzigen (ingelogde gebruiker).
  /// Backend verwacht: current_password, password, password_confirmation.
  Future<void> changeMyPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final body = <String, dynamic>{
      'current_password': currentPassword,
      'password': newPassword,
      'password_confirmation': newPassword,
    };
    await _api.post('auth/change-password', body);
  }

  /// POST auth/forgot-password – verstuur reset-link naar e-mail.
  Future<void> requestForgotPassword(String email) async {
    final body = <String, dynamic>{
      'email': email.trim(),
    };
    await _api.post('auth/forgot-password', body);
  }

  /// POST auth/reset-password – nieuw wachtwoord instellen via token uit e-mail.
  Future<void> resetPassword({
    required String token,
    required String newPassword,
    String? email,
  }) async {
    final body = <String, dynamic>{
      'token': token.trim(),
      'password': newPassword.trim(),
      'password_confirmation': newPassword.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    };
    await _api.post('auth/reset-password', body);
  }

  /// GET client/progress-dashboard – klant statistieken & aankomende sessie.
  /// Retourneert: stats (total_bookings, completed, upcoming, cancelled, completed_this_month),
  ///              next_session, recent_bookings, active_trainers, group_registrations.
  Future<Map<String, dynamic>> getClientStats() async {
    final res = await _api.get('client/progress-dashboard');
    // Flatten: voeg stats-subobject samen met top-level voor makkelijkere mapping.
    final stats = _asMap(res['stats']) ?? <String, dynamic>{};
    final result = <String, dynamic>{
      'total_sessions': stats['total_bookings'] ?? stats['completed'] ?? 0,
      'sessions_count': stats['completed'] ?? 0,
      'upcoming': stats['upcoming'] ?? 0,
      'completed_this_month': stats['completed_this_month'] ?? 0,
    };
    // Volgende sessie dag
    final next = _asMap(res['next_session']);
    if (next != null && next['scheduled_at'] != null) {
      result['next_session'] = next['scheduled_at'].toString();
      result['next_session_day'] = next['scheduled_at'].toString();
    }
    return result;
  }

  // ── Account & Privacy (AVG/GDPR) ─────────────────────────────

  /// POST account/delete — dient een account-verwijderaanvraag in.
  /// Backend moet re-authenticatie afdwingen en bevestigingsmail sturen.
  Future<void> requestAccountDeletion() async {
    await _api.post('account/delete', {});
  }

  /// POST account/export-data — vraagt een data-export aan (AVG Art. 15).
  /// Backend stuurt de export per e-mail naar de gebruiker.
  Future<void> requestDataExport() async {
    await _api.post('account/export-data', {});
  }

  /// GET invoices/client
  Future<List<Map<String, dynamic>>> getClientInvoices() async {
    final res = await _api.get('invoices/client');
    final raw = res['data'] ?? res['invoices'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET payment receipt for booking/invoice.
  /// NB: Geen dedicated backend route — caller moet graceful omgaan met 404.
  Future<Map<String, dynamic>> getPaymentReceipt({
    String? bookingId,
    String? invoiceId,
  }) async {
    final path = bookingId != null && bookingId.trim().isNotEmpty
        ? 'bookings/${bookingId.trim()}/receipt'
        : invoiceId != null && invoiceId.trim().isNotEmpty
            ? 'invoices/${invoiceId.trim()}/receipt'
            : null;
    if (path == null) {
      throw ApiException(400, 'Booking of invoice ID vereist voor betaalbewijs.');
    }
    final res = await _api.get(path);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET support/tickets – support tickets ophalen.
  /// Backend route: GET support/tickets
  Future<List<Map<String, dynamic>>> getSupportTickets() async {
    final res = await _api.get('support/tickets');
    final raw = res['data'] ?? res['tickets'] ?? res['items'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST support/tickets – support ticket aanmaken.
  /// Backend route: POST support/tickets
  Future<Map<String, dynamic>> createSupportTicket({
    required String type,
    required String subject,
    required String message,
    String? bookingId,
    String? invoiceId,
  }) async {
    final normalizedType = type.trim().toLowerCase();
    final isDispute =
        normalizedType == 'dispute' || normalizedType == 'incident';
    final body = <String, dynamic>{
      'type': normalizedType,
      'is_dispute': isDispute,
      'subject': subject.trim(),
      'message': message.trim(),
      if (bookingId != null && bookingId.trim().isNotEmpty)
        'booking_id': bookingId.trim(),
      if (invoiceId != null && invoiceId.trim().isNotEmpty)
        'invoice_id': invoiceId.trim(),
    };
    final res = await _api.post('support/tickets', body);
    return _asMap(res['data'] ?? res['ticket'] ?? res) ?? <String, dynamic>{};
  }

  /// GET support/tickets/{id} – detail van 1 support ticket.
  /// Backend route: GET support/tickets/{id}
  Future<Map<String, dynamic>> getSupportTicketDetail(String ticketId) async {
    final id = ticketId.trim();
    if (id.isEmpty) return <String, dynamic>{};
    final res = await _api.get('support/tickets/$id');
    return _asMap(res['data'] ?? res['ticket'] ?? res) ?? <String, dynamic>{};
  }

  /// POST support/tickets/{id}/messages – reply op support ticket.
  /// Backend route: POST support/tickets/{id}/messages
  Future<Map<String, dynamic>> sendSupportTicketReply({
    required String ticketId,
    required String message,
  }) async {
    final id = ticketId.trim();
    final bodyText = message.trim();
    if (id.isEmpty || bodyText.isEmpty) return <String, dynamic>{};
    final body = <String, dynamic>{
      'message': bodyText,
    };
    final res = await _api.post('support/tickets/$id/messages', body);
    return _asMap(res['data'] ?? res['message'] ?? res['reply'] ?? res) ??
        <String, dynamic>{};
  }

  /// POST invoice request from client to trainer.
  /// NB: Geen dedicated backend route — wordt als support ticket aangemaakt
  /// door de caller als deze methode faalt.
  Future<Map<String, dynamic>> requestInvoiceFromTrainer({
    required String bookingId,
    String? message,
  }) async {
    final id = bookingId.trim();
    final body = <String, dynamic>{
      'booking_id': id,
      if (message != null && message.trim().isNotEmpty)
        'message': message.trim(),
      'type': 'invoice_request',
    };
    final res = await _api.post('bookings/$id/invoice-request', body);
    return _asMap(res['data'] ?? res['request'] ?? res) ?? <String, dynamic>{};
  }

  /// GET me/progress – client progress snapshot.
  /// Backend route: GET me/progress
  Future<Map<String, dynamic>> getMyProgressSnapshot() async {
    final res = await _api.get('me/progress');
    return _asMap(res['data'] ?? res['progress'] ?? res) ?? <String, dynamic>{};
  }

  /// GET me/session-notes – coach notes voor huidige client.
  /// NB: Geen dedicated client-side route — trainer-side is
  /// GET trainer/clients/{clientUserId}/session-notes
  Future<List<Map<String, dynamic>>> getMyCoachNotes() async {
    final res = await _api.get('me/session-notes');
    final raw = res['data'] ?? res['notes'] ?? res['items'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET me/shared-dossier – gedeeld dossier van trainer(s).
  Future<Map<String, dynamic>> getMySharedDossier() async {
    final res = await _api.get('me/shared-dossier');
    return _asMap(res['data'] ?? res['dossier'] ?? res) ?? <String, dynamic>{};
  }

  /// GET waitlist/me – mijn wachtlijst entries.
  /// Backend routes: GET waitlist/me, GET bookings/standby/me (zelfde controller)
  Future<List<Map<String, dynamic>>> getMyWaitlistEntries() async {
    final res = await _api.get('waitlist/me');
    final raw = res['data'] ?? res['waitlist'] ?? res['items'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST waitlist – wachtlijst aanmelding.
  /// Backend route: POST waitlist (ook POST bookings/standby)
  Future<void> joinTrainerWaitlist({
    required String trainerUserId,
    DateTime? preferredAt,
    String? note,
  }) async {
    final body = <String, dynamic>{
      'trainer_user_id': trainerUserId,
      if (preferredAt != null) 'preferred_at': preferredAt.toIso8601String(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
    await _api.post('waitlist', body);
  }

  /// DELETE waitlist/{id} – wachtlijst afmelding.
  /// Backend route: DELETE waitlist/{id} (ook DELETE bookings/standby/{id})
  Future<void> leaveWaitlistEntry(String waitlistId) async {
    final id = waitlistId.trim();
    if (id.isEmpty) return;
    await _api.delete('waitlist/$id');
  }

  /// POST notify standby/waitlist users about a newly available slot.
  Future<void> notifyWaitlistForBooking(String bookingId) async {
    final id = bookingId.trim();
    if (id.isEmpty) return;
    final body = <String, dynamic>{
      'booking_id': id,
      'source': 'trainer_cancel',
    };
    // NB: Geen dedicated backend route
    await _api.post('bookings/$id/waitlist/notify', body);
  }

  /// POST accept standby/waitlist offer by ID.
  Future<Map<String, dynamic>> acceptWaitlistOffer(String offerId) async {
    final id = offerId.trim();
    if (id.isEmpty) {
      throw ApiException(400, 'Standby offer-ID ontbreekt.');
    }
    final body = <String, dynamic>{'offer_id': id};
    // NB: Geen dedicated backend route
    final res = await _api.post('waitlist/offers/$id/accept', body);
    return _asMap(res['data'] ?? res['booking'] ?? res) ??
        <String, dynamic>{};
  }

  /// POST bookings/{id}/review – review plaatsen voor een voltooide sessie.
  /// Ondersteunt optionele foto-upload via multipart.
  Future<Map<String, dynamic>> submitReview({
    required String bookingId,
    required int rating,
    String? message,
    bool isAnonymous = false,
    String? photoPath,
  }) async {
    final id = bookingId.trim();
    if (id.isEmpty) return {};

    // Met foto → multipart, zonder foto → gewone JSON POST
    if (photoPath != null && photoPath.isNotEmpty) {
      final fields = <String, String>{
        'rating': rating.clamp(1, 5).toString(),
        'is_anonymous': isAnonymous ? '1' : '0',
        if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
      };
      final file = await http.MultipartFile.fromPath('photo', photoPath);
      final res = await _api.postMultipart(
        'bookings/$id/review',
        fileField: 'photo',
        file: file,
        fields: fields,
      );
      return _asMap(res['data'] ?? res) ?? {};
    }

    final body = <String, dynamic>{
      'rating': rating.clamp(1, 5),
      'is_anonymous': isAnonymous,
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
    };
    final res = await _api.post('bookings/$id/review', body);
    return _asMap(res['data'] ?? res) ?? {};
  }

  /// GET trainers/{id}/reviews – publieke lijst van reviews voor een trainer.
  Future<Map<String, dynamic>> getTrainerReviews(String trainerId) async {
    final id = trainerId.trim();
    if (id.isEmpty) return {'data': [], 'rating_avg': null, 'count': 0};
    final res = await _api.get('trainers/$id/reviews');
    final data = res['data'] ?? res['reviews'] ?? [];
    final list = data is List ? data : [];
    return {
      'data': list.map((e) => _asMap(e) ?? <String, dynamic>{}).toList(),
      'rating_avg': res['rating_avg'],
      'count': res['count'] ?? list.length,
    };
  }

  /// GET client referral program info.
  Future<Map<String, dynamic>> getMyReferralProgram() async {
    final res = await _api.get('referral/my-code');
    return _asMap(res['data'] ?? res['referral'] ?? res) ??
        <String, dynamic>{};
  }

  /// GET notifications
  Future<List<Map<String, dynamic>>> getNotifications() async {
    final res = await _api.get('notifications');
    final raw = res['data'] ?? res['notifications'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST notifications/register-device – registreer FCM/APNs token voor push.
  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    await _api.post('notifications/register-device', {
      'fcm_token': token,
      'platform': platform,
    });
  }

  /// GET notifications/unread-count
  Future<int> getNotificationUnreadCount() async {
    final res = await _api.get('notifications/unread-count');
    final raw = res['data'] ?? res;
    final map = _asMap(raw) ?? <String, dynamic>{};
    final v = map['unread_count'] ?? map['count'] ?? map['total'] ?? 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  /// POST notifications/mark-read
  Future<void> markNotificationsRead({String? notificationId}) async {
    final body = <String, dynamic>{};
    if (notificationId != null && notificationId.trim().isNotEmpty) {
      body['notification_id'] = notificationId.trim();
      body['id'] = notificationId.trim();
    }
    await _api.post('notifications/mark-read', body);
  }

  /// GET notifications/preferences
  Future<Map<String, dynamic>> getNotificationPreferences() async {
    final res = await _api.get('notifications/preferences');
    return _asMap(res['data'] ?? res['preferences'] ?? res) ??
        <String, dynamic>{};
  }

  /// PUT/POST notifications/preferences
  Future<Map<String, dynamic>> updateNotificationPreferences(
    Map<String, dynamic> preferences,
  ) async {
    try {
      final res = await _api.put('notifications/preferences', preferences);
      return _asMap(res['data'] ?? res['preferences'] ?? res) ??
          <String, dynamic>{};
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      final res = await _api.post('notifications/preferences', preferences);
      return _asMap(res['data'] ?? res['preferences'] ?? res) ??
          <String, dynamic>{};
    }
  }

  // ─── Favorieten (server-driven) ───

  /// GET me/favorites – lijst van favoriete trainer IDs.
  Future<List<String>> getFavoriteTrainerIds() async {
    final res = await _api.get('me/favorites');
    final raw = res['trainer_ids'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return <String>[];
  }

  /// POST me/favorites – trainer toevoegen als favoriet.
  Future<void> addFavoriteTrainer(String trainerUserId) async {
    await _api.post('me/favorites', {'trainer_user_id': trainerUserId});
  }

  /// DELETE me/favorites/{id} – favoriet verwijderen.
  Future<void> removeFavoriteTrainer(String trainerUserId) async {
    await _api.delete('me/favorites/$trainerUserId');
  }

  // ─── Verborgen trainers (server-driven) ───

  /// GET me/hidden-trainers – lijst van verborgen trainer IDs.
  Future<List<String>> getHiddenTrainerIds() async {
    final res = await _api.get('me/hidden-trainers');
    final raw = res['trainer_ids'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return <String>[];
  }

  /// POST me/hidden-trainers – trainer verbergen.
  Future<void> hideTrainer(String trainerUserId) async {
    await _api.post('me/hidden-trainers', {'trainer_user_id': trainerUserId});
  }

  /// DELETE me/hidden-trainers/{id} – trainer weer tonen.
  Future<void> unhideTrainer(String trainerUserId) async {
    await _api.delete('me/hidden-trainers/$trainerUserId');
  }

  // ─── Intake (goals / week_goal) ───

  /// GET me/intake – klant intake formulier data.
  Future<Map<String, dynamic>> getIntake() async {
    final res = await _api.get('me/intake');
    return _asMap(res['data'] ?? res['intake'] ?? res) ?? <String, dynamic>{};
  }

  /// PUT me/intake – intake bijwerken (goals_text, training_frequency_preferred, etc.).
  Future<Map<String, dynamic>> updateIntake(Map<String, dynamic> data) async {
    try {
      final res = await _api.put('me/intake', data);
      return _asMap(res['data'] ?? res['intake'] ?? res) ?? <String, dynamic>{};
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      final res = await _api.post('me/intake', data);
      return _asMap(res['data'] ?? res['intake'] ?? res) ?? <String, dynamic>{};
    }
  }

  /// GET trainer/summary – voor trainer-dashboard.
  Future<TrainerSummary> getTrainerSummary() async {
    final res = await _api.get('trainer/summary');

    dynamic raw = res['data'];
    raw ??= res;

    final map = _asMap(raw);
    if (map != null) {
      return TrainerSummary.fromJson(map);
    }
    return const TrainerSummary(
      pendingCount: 0,
      upcomingCount: 0,
      thisWeekCount: 0,
      completedCount: 0,
      revenueCents: 0,
      upcomingBookings: [],
    );
  }

  /// GET trainer/bookings – alle boekingen van de trainer.
  Future<List<Booking>> getTrainerBookings() async {
    Map<String, dynamic> res;
    try {
      // Volgens contract gebruikt trainer ook bookings endpoints.
      res = await _api.get('bookings');
    } on ApiException catch (e) {
      // Backward compatibility met oudere trainer route.
      if (e.statusCode != 404) rethrow;
      res = await _api.get('trainer/bookings');
    }
    dynamic raw = res['data'] ?? res['bookings'] ?? res;
    if (raw is! List) return [];
    return raw
        .map((e) {
          final map = _asMap(e);
          return map != null ? Booking.fromJson(map) : null;
        })
        .whereType<Booking>()
        .toList();
  }

  /// POST trainer/bookings/:id/confirm
  Future<void> confirmTrainerBooking(String id) async {
    try {
      await _api.post('bookings/$id/confirm', {});
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _api.post('trainer/bookings/$id/confirm', {});
    }
  }

  /// POST trainer/bookings/:id/reject
  Future<void> rejectTrainerBooking(String id) async {
    await _api.post('trainer/bookings/$id/reject', {});
  }

  /// GET trainer/revenue
  Future<TrainerRevenue> getTrainerRevenue({
    DateTime? from,
    DateTime? to,
    String? status,
  }) async {
    final queryParams = <String, String>{};
    if (from != null) {
      queryParams['from'] = from.toIso8601String().split('T').first;
    }
    if (to != null) {
      queryParams['to'] = to.toIso8601String().split('T').first;
    }
    if (status != null && status.trim().isNotEmpty && status != 'all') {
      queryParams['status'] = status;
    }
    if (kDebugMode) debugPrint('[GymiesApi] GET trainer/revenue (params=$queryParams) …');
    final res = await _api.get(
      'trainer/revenue',
      queryParams: queryParams.isEmpty ? null : queryParams,
    );
    if (kDebugMode) debugPrint('[GymiesApi] trainer/revenue OK – keys: ${(res is Map ? res.keys.toList() : res.runtimeType)}');
    final raw = res['data'] ?? res;
    final map = _asMap(raw);
    if (map != null) return TrainerRevenue.fromJson(map);
    return TrainerRevenue.fromJson({});
  }

  /// GET trainer/conversations
  Future<List<TrainerConversation>> getTrainerConversations() async {
    final res = await _api.get('trainer/conversations');
    dynamic raw = res['data'] ?? res['conversations'] ?? res;
    if (raw is! List) return [];
    return raw
        .map((e) {
          final map = _asMap(e);
          return map != null ? TrainerConversation.fromJson(map) : null;
        })
        .whereType<TrainerConversation>()
        .toList();
  }

  /// GET trainer/profile
  Future<Map<String, dynamic>> getTrainerProfile() async {
    try {
      if (kDebugMode) debugPrint('[GymiesApi] GET trainer/me …');
      final res = await _api.get('trainer/me');
      if (kDebugMode) debugPrint('[GymiesApi] trainer/me OK – keys: ${(res is Map ? res.keys.toList() : res.runtimeType)}');
      return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[GymiesApi] trainer/me FAILED ${e.statusCode}: ${e.message}');
      if (e.statusCode != 404) rethrow;
      if (kDebugMode) debugPrint('[GymiesApi] Fallback → GET trainer/profile …');
      final res = await _api.get('trainer/profile');
      if (kDebugMode) debugPrint('[GymiesApi] trainer/profile OK – keys: ${(res is Map ? res.keys.toList() : res.runtimeType)}');
      return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
    }
  }

  /// PATCH trainer/profile
  Future<Map<String, dynamic>> updateTrainerProfile({
    required String displayName,
    String? specialty,
    String? region,
    String? bio,
    int? hourlyRateCents,
    List<String>? visibleBadgeIds,
    String? profileSlug,
    String? instagramUrl,
    String? snapchatUsername,
    String? facebookUrl,
    String? avatarUrl,
  }) async {
    final body = <String, dynamic>{'display_name': displayName.trim()};
    if (specialty != null) body['specialty'] = specialty.trim();
    if (region != null) body['region'] = region.trim();
    if (bio != null) body['bio'] = bio.trim();
    if (hourlyRateCents != null) body['hourly_rate_cents'] = hourlyRateCents;
    if (visibleBadgeIds != null) body['visible_badges'] = visibleBadgeIds;
    if (profileSlug != null) {
      final slug = profileSlug.trim();
      body['profile_slug'] = slug.isEmpty ? null : slug;
    }
    if (instagramUrl != null) body['instagram_url'] = instagramUrl.trim().isEmpty ? null : instagramUrl.trim();
    if (snapchatUsername != null) body['snapchat_username'] = snapchatUsername.trim().isEmpty ? null : snapchatUsername.trim();
    if (facebookUrl != null) body['facebook_url'] = facebookUrl.trim().isEmpty ? null : facebookUrl.trim();
    if (avatarUrl != null) body['avatar_url'] = avatarUrl.trim();
    try {
      final res = await _api.put('trainer/me', body);
      return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      final res = await _api.patch('trainer/profile', body);
      return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
    }
  }

  /// GET trainer documents/company settings for invoicing & compliance.
  Future<Map<String, dynamic>> getTrainerDocuments() async {
    Map<String, dynamic> normalize(Map<String, dynamic> source) {
      final doc = <String, dynamic>{};
      dynamic pick(List<String> keys) {
        for (final k in keys) {
          if (source.containsKey(k) && source[k] != null) return source[k];
        }
        return null;
      }

      final nestedCandidates = <Map<String, dynamic>>[];
      for (final k in const [
        'documents',
        'documenten',
        'company',
        'company_profile',
        'companyProfile',
        'trainer_documents',
      ]) {
        final v = source[k];
        if (v is Map<String, dynamic>) nestedCandidates.add(v);
        if (v is Map) nestedCandidates.add(Map<String, dynamic>.from(v));
      }
      for (final nested in nestedCandidates) {
        nested.forEach((key, value) {
          doc.putIfAbsent(key, () => value);
        });
      }
      source.forEach((key, value) => doc.putIfAbsent(key, () => value));

      final normalized = <String, dynamic>{
        ...doc,
        if (pick(['company_name', 'companyName', 'business_name']) != null)
          'company_name': pick([
            'company_name',
            'companyName',
            'business_name',
          ]),
        if (pick(['kvk_number', 'kvk', 'chamber_of_commerce']) != null)
          'kvk_number': pick(['kvk_number', 'kvk', 'chamber_of_commerce']),
        if (pick(['vat_number', 'vat', 'btw_number']) != null)
          'vat_number': pick(['vat_number', 'vat', 'btw_number']),
        if (pick(['trainer_address_line1', 'address_line1', 'address']) != null)
          'trainer_address_line1': pick([
            'trainer_address_line1',
            'address_line1',
            'address',
          ]),
        if (pick(['trainer_postcode', 'postcode', 'zip']) != null)
          'trainer_postcode': pick(['trainer_postcode', 'postcode', 'zip']),
        if (pick(['trainer_city', 'city', 'town']) != null)
          'trainer_city': pick(['trainer_city', 'city', 'town']),
        if (pick(['trainer_country', 'country', 'country_code']) != null)
          'trainer_country': pick([
            'trainer_country',
            'country',
            'country_code',
          ]),
        if (pick(['vog_url', 'vog_document_url']) != null)
          'vog_url': pick(['vog_url', 'vog_document_url']),
        if (pick(['diploma_urls', 'diplomas', 'diploma_url']) != null)
          'diploma_urls': pick(['diploma_urls', 'diplomas', 'diploma_url']),
      };
      return normalized;
    }

    final res = await _api.get('trainer/documents');
    final top =
        _asMap(res['data'] ?? res['documents'] ?? res['company'] ?? res) ??
        <String, dynamic>{};
    return normalize(top);
  }

  /// PUT/PATCH trainer documents/company settings.
  Future<Map<String, dynamic>> updateTrainerDocuments(
    Map<String, dynamic> body,
  ) async {
    final normalized = <String, dynamic>{
      ...body,
      if (body['company_name'] != null) 'companyName': body['company_name'],
      if (body['kvk_number'] != null) 'kvk': body['kvk_number'],
      if (body['vat_number'] != null) 'vat': body['vat_number'],
      if (body['trainer_address_line1'] != null)
        'address_line1': body['trainer_address_line1'],
      if (body['trainer_address_line1'] != null)
        'address': body['trainer_address_line1'],
      if (body['trainer_postcode'] != null)
        'postcode': body['trainer_postcode'],
      if (body['trainer_city'] != null) 'city': body['trainer_city'],
      if (body['trainer_country'] != null) 'country': body['trainer_country'],
      if (body['diploma_urls'] is List &&
          (body['diploma_urls'] as List).isNotEmpty)
        'diploma_url': (body['diploma_urls'] as List).first.toString(),
    };
    // Use simple payload structure for trainer/documents endpoint
    final res = await _api.put('trainer/documents', normalized);
    return _asMap(
          res['data'] ?? res['documents'] ?? res['company'] ?? res,
        ) ??
        <String, dynamic>{};
  }

  /// GET trainer/conversations/:id/messages
  Future<List<TrainerMessage>> getTrainerConversationMessages(
    String conversationId,
  ) async {
    final res = await _api.get(
      'trainer/conversations/$conversationId/messages',
    );
    final raw = res['data'] ?? res['messages'] ?? res;
    if (raw is! List) return [];
    return raw
        .map((e) {
          final map = _asMap(e);
          return map != null ? TrainerMessage.fromJson(map) : null;
        })
        .whereType<TrainerMessage>()
        .toList();
  }

  /// POST trainer/conversations/:id/messages
  Future<TrainerMessage?> sendTrainerMessage(
    String conversationId,
    String body,
  ) async {
    final res = await _api.post(
      'trainer/conversations/$conversationId/messages',
      {'body': body.trim()},
    );
    final raw = res['data'] ?? res['message'];
    final map = _asMap(raw);
    if (map != null) {
      return TrainerMessage.fromJson(map);
    }
    return null;
  }

  /// POST trainer/conversations/:id/read
  Future<void> markTrainerConversationAsRead(String conversationId) async {
    try {
      await _api.post('trainer/conversations/$conversationId/mark-read', {});
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _api.post('trainer/conversations/$conversationId/read', {});
    }
  }

  /// DELETE trainer/conversations/{id}
  /// Verwijdert een gesprek permanent voor de trainer.
  Future<void> deleteTrainerConversation(String conversationId) async {
    await _api.delete('trainer/conversations/$conversationId');
  }

  /// GET trainer/conversations/{id}/context – context (reschedule-card etc.)
  Future<Map<String, dynamic>> getTrainerConversationContext(
    String conversationId,
  ) async {
    try {
      final res =
          await _api.get('trainer/conversations/$conversationId/context');
      return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
    } on ApiException catch (e) {
      if (e.statusCode == 404) return <String, dynamic>{};
      rethrow;
    }
  }

  /// GET conversations (client)
  Future<List<Map<String, dynamic>>> getClientConversations() async {
    final res = await _api.get('conversations');
    final raw = res['data'] ?? res['conversations'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST conversations/ensure (client)
  Future<Map<String, dynamic>> ensureClientConversation({
    required String trainerUserId,
  }) async {
    final res = await _api.post('conversations/ensure', {
      'trainer_user_id': trainerUserId,
      'trainer_id': trainerUserId,
    });
    return _asMap(res['data'] ?? res['conversation'] ?? res) ??
        <String, dynamic>{};
  }

  /// GET conversations/{id}/messages (client)
  Future<List<Map<String, dynamic>>> getClientConversationMessages(
    String conversationId,
  ) async {
    final res = await _api.get('conversations/$conversationId/messages');
    final raw = res['data'] ?? res['messages'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST conversations/{id}/messages (client)
  Future<Map<String, dynamic>> sendClientMessage(
    String conversationId,
    String body,
  ) async {
    final res = await _api.post('conversations/$conversationId/messages', {
      'body': body.trim(),
    });
    return _asMap(res['data'] ?? res['message'] ?? res) ?? <String, dynamic>{};
  }

  /// POST conversations/{id}/mark-read (client)
  Future<void> markClientConversationAsRead(String conversationId) async {
    await _api.post('conversations/$conversationId/mark-read', {});
  }

  /// DELETE conversations/{id} (client)
  /// Verwijdert een gesprek permanent voor de huidige gebruiker.
  /// Als de backend dit endpoint nog niet ondersteunt, vangt de caller
  /// de ApiException op en valt terug op lokale verwijdering.
  Future<void> deleteClientConversation(String conversationId) async {
    await _api.delete('conversations/$conversationId');
  }

  /// GET conversations/{id}/context – context (reschedule-card etc.)
  Future<Map<String, dynamic>> getClientConversationContext(
    String conversationId,
  ) async {
    try {
      final res = await _api.get('conversations/$conversationId/context');
      return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
    } on ApiException catch (e) {
      if (e.statusCode == 404) return <String, dynamic>{};
      rethrow;
    }
  }

  /// GET trainer/availability-settings
  Future<Map<String, dynamic>> getTrainerAvailabilitySettings() async {
    try {
      final res = await _api.get('trainer/availability-settings');
      final data = _asMap(res['data'] ?? res);
      return data ?? <String, dynamic>{};
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      try {
        final profile = await getTrainerProfile();
        return {
          'booking_advance_days': profile['booking_advance_days'] ?? 28,
          'payment_method': profile['payment_method'] ?? 'transfer_and_cash',
        };
      } on ApiException {
        return {
          'booking_advance_days': 28,
          'payment_method': 'transfer_and_cash',
        };
      }
    }
  }

  /// PATCH trainer/availability-settings
  Future<void> updateTrainerAvailabilitySettings({
    int? bookingAdvanceDays,
    String? paymentMethod,
  }) async {
    final body = <String, dynamic>{};
    if (bookingAdvanceDays != null) body['booking_advance_days'] = bookingAdvanceDays;
    if (paymentMethod != null) body['payment_method'] = paymentMethod;
    if (body.isEmpty) return;
    try {
      await _api.patch('trainer/availability-settings', body);
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _api.patch('trainer/profile', body);
    }
  }

  /// GET trainer/availability
  Future<List<TrainerAvailabilitySlot>> getTrainerAvailabilitySlots() async {
    final res = await _api.get('trainer/availability');
    final raw = res['slots'] ?? res['data']?['slots'] ?? res['data'] ?? res;
    if (raw is! List) return [];
    return raw
        .map((e) {
          final map = _asMap(e);
          return map != null ? TrainerAvailabilitySlot.fromJson(map) : null;
        })
        .whereType<TrainerAvailabilitySlot>()
        .toList();
  }

  /// POST trainer/availability
  Future<void> createTrainerAvailabilitySlot({
    required int weekday,
    required String startTime,
    required String endTime,
  }) async {
    try {
      await _api.post('trainer/availability/slots', {
        'weekday': weekday,
        'start_time': startTime,
        'end_time': endTime,
      });
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _api.post('trainer/availability', {
        'weekday': weekday,
        'start_time': startTime,
        'end_time': endTime,
      });
    }
  }

  /// PATCH trainer/availability/:id
  Future<void> updateTrainerAvailabilitySlot({
    required String slotId,
    required int weekday,
    required String startTime,
    required String endTime,
  }) async {
    try {
      await _api.put('trainer/availability/slots/$slotId', {
        'weekday': weekday,
        'start_time': startTime,
        'end_time': endTime,
      });
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _api.patch('trainer/availability/$slotId', {
        'weekday': weekday,
        'start_time': startTime,
        'end_time': endTime,
      });
    }
  }

  /// DELETE trainer/availability/:id
  Future<void> deleteTrainerAvailabilitySlot(String slotId) async {
    try {
      await _api.delete('trainer/availability/slots/$slotId');
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _api.delete('trainer/availability/$slotId');
    }
  }

  /// GET trainer/availability/exceptions
  Future<List<TrainerAvailabilityException>>
  getTrainerAvailabilityExceptions() async {
    Map<String, dynamic> res;
    try {
      // Contract: uitzonderingen zitten onder trainer/availability payload.
      res = await _api.get('trainer/availability');
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      res = await _api.get('trainer/availability/exceptions');
    }
    final raw =
        res['exceptions'] ??
        res['data']?['exceptions'] ??
        res['data'] ??
        res['exceptions_data'] ??
        const [];
    if (raw is! List) return [];
    return raw
        .map((e) {
          final map = _asMap(e);
          return map != null
              ? TrainerAvailabilityException.fromJson(map)
              : null;
        })
        .whereType<TrainerAvailabilityException>()
        .toList();
  }

  /// POST trainer/availability/exceptions
  Future<void> createTrainerAvailabilityException({
    required DateTime date,
    String? reason,
  }) async {
    await _api.post('trainer/availability/exceptions', {
      'date': date.toIso8601String().split('T').first,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  /// PUT trainer/availability/exceptions/:id
  Future<void> updateTrainerAvailabilityException({
    required String exceptionId,
    required DateTime date,
    String? reason,
  }) async {
    await _api.put('trainer/availability/exceptions/$exceptionId', {
      'date': date.toIso8601String().split('T').first,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
  }

  /// DELETE trainer/availability/exceptions/:id
  Future<void> deleteTrainerAvailabilityException(String exceptionId) async {
    await _api.delete('trainer/availability/exceptions/$exceptionId');
  }

  /// POST trainer/bookings/:id/cancel
  Future<void> cancelTrainerBooking(String id) async {
    try {
      await _api.post('bookings/$id/cancel', {});
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _api.post('trainer/bookings/$id/cancel', {});
    }
  }

  /// POST trainer/bookings/:id/complete
  Future<void> completeTrainerBooking(String id) async {
    try {
      await _api.post('bookings/$id/session-status', {'status': 'completed'});
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _api.post('trainer/bookings/$id/complete', {});
    }
  }

  /// POST trainer/bookings/:id/reschedule
  Future<void> rescheduleTrainerBooking(String id, DateTime scheduledAt) async {
    try {
      await _api.post('bookings/$id/reschedule', {
        'scheduled_at': scheduledAt.toIso8601String(),
      });
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _api.post('trainer/bookings/$id/reschedule', {
        'scheduled_at': scheduledAt.toIso8601String(),
      });
    }
  }

  /// GET trainer/packages
  Future<List<Map<String, dynamic>>> getTrainerPackages() async {
    final res = await _api.get('trainer/packages');
    final raw = res['data'] ?? res['packages'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST trainer/packages
  Future<void> createTrainerPackage({
    required String name,
    required int sessionsCount,
    required int priceCents,
    String lessonType = 'personal',
    int validityDays = 30,
    String? description,
  }) async {
    await _api.post('trainer/packages', {
      'name': name.trim(),
      'sessions_count': sessionsCount,
      'price_cents': priceCents,
      'lesson_type': lessonType,
      'validity_days': validityDays,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
  }

  /// PUT trainer/packages/:id
  Future<void> updateTrainerPackage({
    required String id,
    required String name,
    required int sessionsCount,
    required int priceCents,
    String lessonType = 'personal',
    int validityDays = 30,
    String? description,
  }) async {
    await _api.put('trainer/packages/$id', {
      'id': id,
      'name': name.trim(),
      'sessions_count': sessionsCount,
      'price_cents': priceCents,
      'lesson_type': lessonType,
      'validity_days': validityDays,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
  }

  /// DELETE trainer/packages/:id
  Future<void> deleteTrainerPackage(String id) async {
    await _api.delete('trainer/packages/$id', body: {'id': id});
  }

  /// GET trainer/promo-codes
  Future<List<Map<String, dynamic>>> getTrainerPromoCodes() async {
    final res = await _api.get('trainer/promo-codes');
    final raw = res['data'] ?? res['promo_codes'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST trainer/promo-codes
  Future<void> createTrainerPromoCode({
    required String code,
    required String discountType,
    required int valueCents,
    int? maxRedemptions,
    String? validUntil,
  }) async {
    final body = <String, dynamic>{
      'code': code.trim(),
      'discount_type': discountType,
      'value_cents': valueCents,
    };
    if (maxRedemptions != null && maxRedemptions > 0) {
      body['max_redemptions'] = maxRedemptions;
    }
    if (validUntil != null && validUntil.trim().isNotEmpty) {
      body['valid_until'] = validUntil.trim();
    }
    await _api.post('trainer/promo-codes', body);
  }

  /// PUT trainer/promo-codes/:id
  Future<void> updateTrainerPromoCode({
    required String id,
    required String code,
    required String discountType,
    required int valueCents,
    int? maxRedemptions,
    String? validUntil,
  }) async {
    final body = <String, dynamic>{
      'id': id,
      'code': code.trim(),
      'discount_type': discountType,
      'value_cents': valueCents,
    };
    if (maxRedemptions != null && maxRedemptions > 0) {
      body['max_redemptions'] = maxRedemptions;
    }
    if (validUntil != null && validUntil.trim().isNotEmpty) {
      body['valid_until'] = validUntil.trim();
    }
    await _api.put('trainer/promo-codes/$id', body);
  }

  /// DELETE trainer/promo-codes/:id
  Future<void> deleteTrainerPromoCode(String id) async {
    await _api.delete('trainer/promo-codes/$id', body: {'id': id});
  }

  /// GET trainer/promo-codes/stats
  Future<Map<String, dynamic>> getPromoCodeStats() async {
    final res = await _api.get('trainer/promo-codes/stats');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET trainer/revenue-forecast
  Future<Map<String, dynamic>> getTrainerRevenueForecast() async {
    final res = await _api.get('trainer/revenue-forecast');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET trainer/payout-settings
  Future<Map<String, dynamic>> getTrainerPayoutSettings() async {
    final res = await _api.get('trainer/payout-settings');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// PUT trainer/payout-settings
  Future<void> updateTrainerPayoutSettings({
    required String method,
    String? iban,
    String? accountName,
  }) async {
    await _api.put('trainer/payout-settings', {
      'method': method,
      if (iban != null && iban.trim().isNotEmpty) 'iban': iban.trim(),
      if (accountName != null && accountName.trim().isNotEmpty)
        'account_name': accountName.trim(),
    });
  }

  /// GET trainer/payout-preview
  Future<Map<String, dynamic>> getTrainerPayoutPreview() async {
    final res = await _api.get('trainer/payout-preview');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET trainer/payout-calendar
  Future<List<Map<String, dynamic>>> getTrainerPayoutCalendar() async {
    final res = await _api.get('trainer/payout-calendar');
    final raw = res['data'] ?? res['calendar'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET trainer/payouts
  Future<List<Map<String, dynamic>>> getTrainerPayouts() async {
    final res = await _api.get('trainer/payouts');
    final raw = res['data'] ?? res['payouts'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST trainer/payouts/request-now
  Future<void> requestTrainerPayoutNow() async {
    await _api.post('trainer/payouts/request-now', {});
  }

  /// GET invoices/trainer
  Future<List<Map<String, dynamic>>> getTrainerInvoices() async {
    final res = await _api.get('invoices/trainer');
    final raw = res['data'] ?? res['invoices'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST create trainer invoice for a specific booking.
  Future<Map<String, dynamic>> createTrainerInvoiceForBooking({
    required String bookingId,
    int? priceIncVatCents,
    String? serviceType,
    DateTime? serviceDate,
    DateTime? dueDate,
    String currency = 'EUR',
  }) async {
    final baseBody = <String, dynamic>{
      'booking_id': bookingId.trim(),
      if (priceIncVatCents != null && priceIncVatCents > 0)
        'price_inc_vat_cents': priceIncVatCents,
      if (priceIncVatCents != null && priceIncVatCents > 0)
        'total_cents': priceIncVatCents,
      if (priceIncVatCents != null && priceIncVatCents > 0)
        'amount_cents': priceIncVatCents,
      if (serviceType != null && serviceType.trim().isNotEmpty)
        'service_type': serviceType.trim(),
      if (serviceDate != null)
        'service_date': serviceDate.toIso8601String().split('T').first,
      if (dueDate != null)
        'due_date': dueDate.toIso8601String().split('T').first,
      'currency': currency,
      'type': 'invoice',
      'invoice_type': 'session',
      'document_type': 'invoice',
      'category': 'invoice',
    };
    // NB: Geen dedicated backend route — using baseBody directly
    final res = await _api.post('trainer/invoices', baseBody);
    return _asMap(res['data'] ?? res['invoice'] ?? res) ??
        <String, dynamic>{};
  }

  /// POST send trainer invoice to client.
  Future<Map<String, dynamic>> sendTrainerInvoice({
    required String invoiceId,
  }) async {
    final body = <String, dynamic>{'send_now': true};
    final id = invoiceId.trim();
    // NB: Geen dedicated backend route
    final res = await _api.post('invoices/$id/send', body);
    return _asMap(res['data'] ?? res['invoice'] ?? res) ??
        <String, dynamic>{};
  }

  /// GET invoices/trainer/quarter-zip
  Future<Map<String, dynamic>> getTrainerInvoicesQuarterZip() async {
    final res = await _api.get('invoices/trainer/quarter-zip');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET group-sessions – publieke lijst groepslessen.
  Future<List<Map<String, dynamic>>> getPublicGroupSessions({
    String? query,
    DateTime? from,
    DateTime? to,
  }) async {
    final params = <String, String>{};
    if (query != null && query.trim().isNotEmpty) params['query'] = query.trim();
    if (from != null) params['from'] = from.toIso8601String().split('T').first;
    if (to != null) params['to'] = to.toIso8601String().split('T').first;
    final res = await _api.get(
      'group-sessions',
      queryParams: params.isEmpty ? null : params,
    );
    final raw = res['data'] ?? res['group_sessions'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET group-sessions/{id} – publiek detail van een groepsles.
  Future<Map<String, dynamic>> getPublicGroupSession(String id) async {
    final res = await _api.get('group-sessions/$id');
    return _asMap(res['data'] ?? res['group_session'] ?? res) ??
        <String, dynamic>{};
  }

  /// POST group-sessions/{id}/register – inschrijven voor groepsles.
  Future<Map<String, dynamic>> registerForGroupSession(
    String groupSessionId, {
    String? promoCode,
  }) async {
    final body = <String, dynamic>{
      if (promoCode != null && promoCode.trim().isNotEmpty)
        'promo_code': promoCode.trim(),
    };
    final res = await _api.post('group-sessions/$groupSessionId/register', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST group-sessions/{id}/cancel-registration – inschrijving annuleren.
  Future<void> cancelGroupSessionRegistration(String groupSessionId) async {
    await _api.post('group-sessions/$groupSessionId/cancel-registration', {});
  }

  /// GET my-group-registrations – mijn inschrijvingen groepslessen.
  Future<List<Map<String, dynamic>>> getMyGroupRegistrations() async {
    final res = await _api.get('my-group-registrations');
    final raw = res['data'] ?? res['registrations'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST group-session-participants/{participantId}/payments/start – betaling starten voor groepsles.
  Future<Map<String, dynamic>> startGroupParticipantPayment(
    String participantId, {
    String? promoCode,
  }) async {
    final body = <String, dynamic>{
      // Deep link return URL zodat Mollie na betaling terug naar de app stuurt
      'return_url': 'gymies://group-payment/complete?participant_id=$participantId',
      if (promoCode != null && promoCode.trim().isNotEmpty)
        'promo_code': promoCode.trim(),
    };
    final res = await _api.post(
      'group-session-participants/$participantId/payments/start',
      body,
    );
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET trainer/group-sessions
  Future<List<Map<String, dynamic>>> getTrainerGroupSessions() async {
    final res = await _api.get('trainer/group-sessions');
    final raw = res['data'] ?? res['group_sessions'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST trainer/group-sessions
  Future<void> createTrainerGroupSession({
    required String title,
    required String startsAtIso,
    required int capacity,
    int? pricePerParticipantCents,
    int? minParticipants,
    int? durationMinutes,
    int? confirmationDeadlineHours,
  }) async {
    final body = <String, dynamic>{
      'title': title.trim(),
      'scheduled_at': startsAtIso,
      'starts_at': startsAtIso,
      'capacity': capacity,
      'max_participants': capacity,
      'duration_minutes': durationMinutes ?? 60,
    };
    if (pricePerParticipantCents != null && pricePerParticipantCents > 0) {
      body['price_per_participant_cents'] = pricePerParticipantCents;
      body['price_cents'] = pricePerParticipantCents * capacity;
    }
    if (minParticipants != null && minParticipants > 0) {
      body['min_participants'] = minParticipants;
    }
    if (confirmationDeadlineHours != null && confirmationDeadlineHours > 0) {
      body['confirmation_deadline_hours'] = confirmationDeadlineHours;
    }
    await _api.post('trainer/group-sessions', body);
  }

  /// PUT trainer/group-sessions/:id
  Future<void> updateTrainerGroupSession({
    required String id,
    required String title,
    required String startsAtIso,
    required int capacity,
    int? pricePerParticipantCents,
    int? minParticipants,
    int? durationMinutes,
    int? confirmationDeadlineHours,
  }) async {
    final body = <String, dynamic>{
      'id': id,
      'title': title.trim(),
      'scheduled_at': startsAtIso,
      'starts_at': startsAtIso,
      'capacity': capacity,
      'max_participants': capacity,
      'duration_minutes': durationMinutes ?? 60,
    };
    if (pricePerParticipantCents != null && pricePerParticipantCents > 0) {
      body['price_per_participant_cents'] = pricePerParticipantCents;
      body['price_cents'] = pricePerParticipantCents * capacity;
    }
    if (minParticipants != null && minParticipants > 0) {
      body['min_participants'] = minParticipants;
    }
    if (confirmationDeadlineHours != null && confirmationDeadlineHours > 0) {
      body['confirmation_deadline_hours'] = confirmationDeadlineHours;
    }
    await _api.put('trainer/group-sessions/$id', body);
  }

  /// POST trainer/group-sessions/:id/publish
  Future<void> publishTrainerGroupSession(String id) async {
    await _api.post('trainer/group-sessions/$id/publish', {'id': id});
  }

  /// POST trainer/group-sessions/:id/cancel
  Future<void> cancelTrainerGroupSession(String id) async {
    await _api.post('trainer/group-sessions/$id/cancel', {'id': id});
  }

  /// GET trainer/group-sessions/:id/participants
  Future<List<Map<String, dynamic>>> getTrainerGroupSessionParticipants(
    String id,
  ) async {
    final res = await _api.get('trainer/group-sessions/$id/participants');
    final raw = res['data'] ?? res['participants'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST trainer/group-sessions/:id/participants/:participantId/attended
  Future<void> markGroupParticipantAttended({
    required String groupSessionId,
    required String participantId,
  }) async {
    await _api.post(
      'trainer/group-sessions/$groupSessionId/participants/$participantId/attended',
      {'group_session_id': groupSessionId, 'participant_id': participantId},
    );
  }

  /// POST trainer/group-sessions/:sessionId/waitlist/:clientUserId/promote
  Future<void> promoteFromWaitlist({
    required String sessionId,
    required String clientUserId,
  }) async {
    await _api.post('trainer/group-sessions/$sessionId/waitlist/$clientUserId/promote', {});
  }

  /// GET trainer/retention/sleeping-clients
  Future<List<Map<String, dynamic>>> getTrainerSleepingClients() async {
    final res = await _api.get('trainer/retention/sleeping-clients');
    final raw = res['data'] ?? res['clients'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET trainer/clients/:id/progress
  Future<Map<String, dynamic>> getTrainerClientProgress(
    String clientUserId,
  ) async {
    final res = await _api.get('trainer/clients/$clientUserId/progress');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST trainer/clients/:id/progress
  Future<void> saveTrainerClientProgress({
    required String clientUserId,
    required Map<String, dynamic> progress,
  }) async {
    await _api.post('trainer/clients/$clientUserId/progress', progress);
  }

  /// GET trainer/clients/:id/dossier
  Future<Map<String, dynamic>> getTrainerClientDossier(
    String clientUserId,
  ) async {
    final res = await _api.get('trainer/clients/$clientUserId/dossier');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// PUT trainer/clients/:id/dossier
  Future<void> updateTrainerClientDossier({
    required String clientUserId,
    required Map<String, dynamic> dossier,
  }) async {
    await _api.put('trainer/clients/$clientUserId/dossier', dossier);
  }

  /// GET trainer/clients/:id/payments
  Future<List<Map<String, dynamic>>> getTrainerClientPayments(
    String clientUserId,
  ) async {
    final res = await _api.get('trainer/clients/$clientUserId/payments');
    final raw = res['data'] ?? res['payments'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET trainer/clients/:id/session-notes
  Future<List<Map<String, dynamic>>> getTrainerClientSessionNotes(
    String clientUserId,
  ) async {
    final res = await _api.get('trainer/clients/$clientUserId/session-notes');
    final raw = res['data'] ?? res['notes'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET trainer/clients/:id/videos – per-klant instructievideo's
  Future<List<Map<String, dynamic>>> getTrainerClientVideos(
    String clientUserId,
  ) async {
    try {
      final res = await _api.get('trainer/clients/$clientUserId/videos');
      final raw = res['data'] ?? res['videos'] ?? res;
      if (raw is! List) return [];
      return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
    } on ApiException catch (e) {
      if (e.statusCode == 404) return [];
      rethrow;
    }
  }

  /// POST trainer/clients/:id/videos – video uploaden voor klant
  Future<Map<String, dynamic>> postTrainerClientVideo({
    required String clientUserId,
    required String filePath,
    String? title,
  }) async {
    final file = await http.MultipartFile.fromPath('file', filePath);
    final fields = <String, String>{
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
    };
    final res = await _api.postMultipart(
      'trainer/clients/$clientUserId/videos',
      fileField: 'file',
      file: file,
      fields: fields,
    );
    return _asMap(res['data'] ?? res['video'] ?? res) ?? <String, dynamic>{};
  }

  /// DELETE trainer/clients/:id/videos/:videoId
  Future<void> deleteTrainerClientVideo({
    required String clientUserId,
    required String videoId,
  }) async {
    await _api.delete('trainer/clients/$clientUserId/videos/$videoId');
  }

  /// GET me/client-videos – video's van trainers voor huidige klant
  Future<List<Map<String, dynamic>>> getMyClientVideos() async {
    try {
      final res = await _api.get('me/client-videos');
      final raw = res['data'] ?? res['videos'] ?? res;
      if (raw is! List) return [];
      return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
    } on ApiException {
      return [];
    }
  }

  /// POST trainer/clients/:id/session-notes
  Future<void> createTrainerClientSessionNote({
    required String clientUserId,
    required String body,
    String? title,
  }) async {
    await _api.post('trainer/clients/$clientUserId/session-notes', {
      'body': body.trim(),
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
    });
  }

  /// POST trainer/clients/bulk-message
  Future<void> sendTrainerBulkMessage({
    required List<String> clientUserIds,
    required String body,
  }) async {
    await _api.post('trainer/clients/bulk-message', {
      'client_user_ids': clientUserIds,
      'body': body.trim(),
    });
  }

  /// GET trainer/pro/client-health
  Future<List<Map<String, dynamic>>> getTrainerClientHealthScores() async {
    final res = await _api.get('trainer/pro/client-health');
    final raw = res['data'] ?? res['items'] ?? res['clients'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET trainer/pro/upsell-suggestions
  Future<List<Map<String, dynamic>>> getTrainerUpsellSuggestions() async {
    final res = await _api.get('trainer/pro/upsell-suggestions');
    final raw = res['data'] ?? res['items'] ?? res['suggestions'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST trainer/pro/upsell-suggestions/:id/send
  Future<void> sendTrainerUpsellSuggestion({
    required String suggestionId,
    String? clientUserId,
    String? packageId,
  }) async {
    final id = suggestionId.trim();
    final body = <String, dynamic>{
      'suggestion_id': id,
      if (clientUserId != null && clientUserId.trim().isNotEmpty)
        'client_user_id': clientUserId.trim(),
      if (packageId != null && packageId.trim().isNotEmpty)
        'package_id': packageId.trim(),
    };
    await _api.post('trainer/pro/upsell-suggestions/$id/send', body);
  }

  /// GET trainer/pro/rebook-suggestions
  Future<List<Map<String, dynamic>>> getTrainerRebookSuggestions() async {
    final res = await _api.get('trainer/pro/rebook-suggestions');
    final raw = res['data'] ?? res['items'] ?? res['suggestions'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST trainer/pro/rebook-suggestions/:id/send
  Future<void> sendTrainerRebookSuggestion({
    required String suggestionId,
    String? clientUserId,
    String? bookingId,
  }) async {
    final id = suggestionId.trim();
    final body = <String, dynamic>{
      'suggestion_id': id,
      if (clientUserId != null && clientUserId.trim().isNotEmpty)
        'client_user_id': clientUserId.trim(),
      if (bookingId != null && bookingId.trim().isNotEmpty)
        'booking_id': bookingId.trim(),
    };
    await _api.post('trainer/pro/rebook-suggestions/$id/send', body);
  }

  /// GET trainer/settings
  Future<Map<String, dynamic>> getTrainerSettings() async {
    try {
      final res = await _api.get('trainer/settings');
      return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
    } catch (e) {
      if (kDebugMode) debugPrint('[GymiesApi] getTrainerSettings fallback: $e');
      return <String, dynamic>{};
    }
  }

  /// PATCH trainer/settings
  Future<void> updateTrainerSettings(Map<String, dynamic> settings) async {
    await _api.patch('trainer/settings', settings);
  }

  /// GET trainer/pro/packages/expiring-soon
  Future<List<dynamic>> getTrainerPackageExpiringSoon() async {
    try {
      final res = await _api.get('trainer/pro/packages/expiring-soon');
      final raw = res['data'] ?? res['items'] ?? res;
      if (raw is! List) return [];
      return raw;
    } catch (e) {
      if (kDebugMode) debugPrint('[GymiesApi] getTrainerPackageExpiringSoon fallback: $e');
      return [];
    }
  }

  /// GET trainer/studio/performance-summary
  Future<Map<String, dynamic>> getTrainerStudioPerformanceSummary() async {
    final res = await _api.get('trainer/studio/performance-summary');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET trainer/studio/safety-log
  Future<List<Map<String, dynamic>>> getTrainerStudioSafetyLog() async {
    final res = await _api.get('trainer/studio/safety-log');
    final raw = res['data'] ?? res['items'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET onboarding/status
  Future<Map<String, dynamic>> getOnboardingStatus() async {
    final res = await _api.get('onboarding/status');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST onboarding/upload-document – upload document voor onboarding
  Future<void> uploadOnboardingDocument({
    required String category,
    required List<int> fileBytes,
    required String fileName,
  }) async {
    final mf = http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: fileName,
    );
    await _api.postMultipart(
      'onboarding/upload-document',
      fileField: 'file',
      file: mf,
      fields: {'document_category': category},
    );
  }

  /// POST onboarding/mollie-connect/start
  Future<Map<String, dynamic>> startOnboardingMollieConnect() async {
    final res = await _api.post('onboarding/mollie-connect/start', {});
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST onboarding/select-plan
  Future<void> selectOnboardingPlan(String planId) async {
    await _api.post('onboarding/select-plan', {'plan_id': planId});
  }

  /// GET subscription/my
  Future<Map<String, dynamic>> getMySubscription() async {
    final res = await _api.get('subscription/my');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST subscription/cancel
  Future<void> cancelMySubscription() async {
    await _api.post('subscription/cancel', {});
  }

  /// POST subscription/change – wijzig abonnement naar nieuw tier (ingaat bij volgende factuurdatum).
  /// tier: starter | pro | pro_plus | studio
  Future<void> changeSubscription(String tier) async {
    final t = tier.trim().toLowerCase();
    if (t.isEmpty) return;
    await _api.post('subscription/change', {'tier': t});
  }

  /// POST subscription/start-payment – start Mollie checkout voor abonnement.
  /// Retourneert { payment_url, payment_id, tier }.
  Future<Map<String, dynamic>> startSubscriptionPayment(String tier) async {
    final t = tier.trim().toLowerCase();
    if (t.isEmpty) throw ArgumentError('tier is verplicht');
    final res = await _api.post('subscription/start-payment', {'tier': t});
    final data = res['data'] ?? res;
    return data is Map<String, dynamic> ? data : _asMap(data) ?? <String, dynamic>{};
  }

  /// GET plans
  Future<List<Map<String, dynamic>>> getPlans() async {
    final res = await _api.get('plans');
    final raw = res['data'] ?? res['plans'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  // ─── Promoties ──────────────────────────────────────────────────────────

  /// POST promo/validate – valideer een promo-code voor een tier.
  Future<Map<String, dynamic>> validatePromoCode({
    required String code,
    required String tier,
  }) async {
    final res = await _api.post('promo/validate', {
      'code': code.trim(),
      'tier': tier.trim().toLowerCase(),
    });
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET promo/active – haal actieve promotie op voor de ingelogde trainer.
  Future<Map<String, dynamic>> getActivePromotion() async {
    final res = await _api.get('promo/active');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST promo/activate – activeer een promotie.
  Future<Map<String, dynamic>> activatePromotion({
    required int promotionId,
    required String tier,
    String? code,
  }) async {
    final body = <String, dynamic>{
      'promotion_id': promotionId,
      'tier': tier.trim().toLowerCase(),
      if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
    };
    final res = await _api.post('promo/activate', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST subscription/start-payment met optionele promotie.
  Future<Map<String, dynamic>> startSubscriptionPaymentWithPromo(
    String tier, {
    int? promotionId,
    String? promoCode,
  }) async {
    final t = tier.trim().toLowerCase();
    if (t.isEmpty) throw ArgumentError('tier is verplicht');
    final body = <String, dynamic>{
      'tier': t,
      if (promotionId != null) 'promotion_id': promotionId,
      if (promoCode != null && promoCode.trim().isNotEmpty)
        'promo_code': promoCode.trim(),
    };
    final res = await _api.post('subscription/start-payment', body);
    final data = res['data'] ?? res;
    return data is Map<String, dynamic> ? data : _asMap(data) ?? <String, dynamic>{};
  }

  // ─── Gym (Studio) ─────────────────────────────────────────────────────────
  static const _gymPrefix = 'gym';

  /// GET gym/dashboard
  Future<Map<String, dynamic>> getGymDashboard() async {
    final res = await _api.get('$_gymPrefix/dashboard');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET gym/dashboard-stats
  Future<Map<String, dynamic>> getGymDashboardStats() async {
    final res = await _api.get('$_gymPrefix/dashboard-stats');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET gym/trainers
  Future<List<Map<String, dynamic>>> getGymTrainers() async {
    final res = await _api.get('$_gymPrefix/trainers');
    final raw = res['data'] ?? res['trainers'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET gym/bookings
  Future<List<Map<String, dynamic>>> getGymBookings({
    String? status,
    DateTime? from,
    DateTime? to,
  }) async {
    final params = <String, String>{};
    if (status != null && status.trim().isNotEmpty) params['status'] = status;
    if (from != null) params['from'] = from.toIso8601String().split('T').first;
    if (to != null) params['to'] = to.toIso8601String().split('T').first;
    final res = await _api.get(
      '$_gymPrefix/bookings',
      queryParams: params.isEmpty ? null : params,
    );
    final raw = res['data'] ?? res['bookings'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET gym/bookings/{id}
  Future<Map<String, dynamic>> getGymBookingDetail(String id) async {
    final res = await _api.get('$_gymPrefix/bookings/$id');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET gym/settlements
  Future<List<Map<String, dynamic>>> getGymSettlements() async {
    final res = await _api.get('$_gymPrefix/settlements');
    final raw = res['data'] ?? res['settlements'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET gym/settlements/{id}
  Future<Map<String, dynamic>> getGymSettlementDetail(String id) async {
    final res = await _api.get('$_gymPrefix/settlements/$id');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET gym/clients
  Future<List<Map<String, dynamic>>> getGymClients() async {
    final res = await _api.get('$_gymPrefix/clients');
    final raw = res['data'] ?? res['clients'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET gym/settings
  Future<Map<String, dynamic>> getGymSettings() async {
    final res = await _api.get('$_gymPrefix/settings');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// PUT gym/settings
  Future<Map<String, dynamic>> updateGymSettings(
    Map<String, dynamic> body,
  ) async {
    final res = await _api.put('$_gymPrefix/settings', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST gym/members/invite
  Future<Map<String, dynamic>> inviteGymMember({
    required String email,
    String? role,
  }) async {
    final res = await _api.post('$_gymPrefix/members/invite', {
      'email': email.trim(),
      if (role != null && role.trim().isNotEmpty) 'role': role.trim(),
    });
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET gym/membership
  Future<Map<String, dynamic>> getGymMembership() async {
    final res = await _api.get('$_gymPrefix/membership');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  // ─── Admin (vault-console) ───────────────────────────────────────────────
  static const _adminPrefix = 'vault-console';

  /// GET vault-console/inbox – actiepunten voor admin.
  Future<Map<String, dynamic>> getAdminInbox() async {
    return _api.get('$_adminPrefix/inbox');
  }

  /// GET vault-console/overview – KPI's en overzicht.
  Future<Map<String, dynamic>> getAdminOverview() async {
    return _api.get('$_adminPrefix/overview');
  }

  /// GET vault-console/search – zoek gebruikers.
  Future<Map<String, dynamic>> adminSearch({String? query}) async {
    final params =
        query != null && query.trim().isNotEmpty ? {'q': query.trim()} : null;
    return _api.get('$_adminPrefix/search', queryParams: params);
  }

  /// GET vault-console/users/{userId} – gebruiker detail.
  Future<Map<String, dynamic>> getAdminUserDetail(String userId) async {
    final id = userId.toString().trim();
    if (id.isEmpty) return <String, dynamic>{};
    final res = await _api.get('$_adminPrefix/users/$id');
    return _asMap(res['data'] ?? res['user'] ?? res) ?? <String, dynamic>{};
  }

  /// GET vault-console/users/{userId}/notes – admin notities.
  Future<List<Map<String, dynamic>>> getAdminUserNotes(String userId) async {
    final res = await _api.get('$_adminPrefix/users/${userId.trim()}/notes');
    final raw = res['data'] ?? res['notes'] ?? res['items'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET vault-console/tickets – support tickets.
  /// role: 'client' of 'trainer' om te filteren op auteur.
  Future<List<Map<String, dynamic>>> getAdminTickets({
    String? status,
    String? role,
    int? page,
  }) async {
    final params = <String, String>{};
    if (status != null && status.trim().isNotEmpty) {
      params['status'] = status.trim();
    }
    if (role != null && role.trim().isNotEmpty) {
      params['role'] = role.trim();
      params['author_role'] = role.trim();
    }
    if (page != null && page > 0) params['page'] = page.toString();
    final res = await _api.get(
      '$_adminPrefix/tickets',
      queryParams: params.isEmpty ? null : params,
    );
    final raw = res['data'] ?? res['tickets'] ?? res['items'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST vault-console/tickets/{id} – ticketstatus bijwerken.
  Future<Map<String, dynamic>> updateAdminTicket(
    String ticketId,
    Map<String, dynamic> updates,
  ) async {
    return _api.post('$_adminPrefix/tickets/${ticketId.trim()}', updates);
  }

  /// GET vault-console/tickets/{id}/messages – ticketberichten.
  Future<List<Map<String, dynamic>>> getAdminTicketMessages(
    String ticketId,
  ) async {
    final res = await _api.get(
      '$_adminPrefix/tickets/${ticketId.trim()}/messages',
    );
    final raw = res['data'] ?? res['messages'] ?? res['items'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// POST vault-console/tickets/{id}/messages – bericht toevoegen.
  Future<Map<String, dynamic>> addAdminTicketMessage(
    String ticketId,
    String body,
  ) async {
    return _api.post(
      '$_adminPrefix/tickets/${ticketId.trim()}/messages',
      {'body': body.trim(), 'message': body.trim()},
    );
  }

  /// GET vault-console/subscription-features – feature matrix beheer.
  Future<List<Map<String, dynamic>>> getAdminSubscriptionFeatures() async {
    final res = await _api.get('$_adminPrefix/subscription-features');
    final raw = res['data'] ?? res['features'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// PUT vault-console/subscription-features – feature matrix opslaan.
  Future<List<Map<String, dynamic>>> updateAdminSubscriptionFeatures(
    List<Map<String, dynamic>> features,
  ) async {
    final res = await _api.put(
      '$_adminPrefix/subscription-features',
      {'features': features},
    );
    final raw = res['data'] ?? res['features'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET subscription/features – voor trainer app: welke features actief zijn (o.b.v. tier).
  /// Val terug op null bij 404; app gebruikt dan fallback/defaults.
  Future<Map<String, dynamic>?> getSubscriptionFeatures() async {
    try {
      return await _api.get('subscription/features');
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  // ─── Pro+ Features ────────────────────────────────────────────────────
  // Branding-instellingen zitten in storefront-cms (dezelfde backend route).
  // Logo/banner uploads gaan via trainer/media met usage type.
  // Widget code en QR worden client-side gegenereerd.

  /// GET trainer/storefront-cms – Haal branding-instellingen op.
  /// Branding-velden (brand_color, custom_slug, intro_video_url, brand_logo_url,
  /// brand_banner_url) zijn onderdeel van de storefront CMS data.
  Future<Map<String, dynamic>> getProPlusSettings() async {
    final res = await _api.get('trainer/storefront-cms');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// PUT trainer/storefront-cms – Sla branding-instellingen op.
  Future<Map<String, dynamic>> updateProPlusSettings(Map<String, dynamic> body) async {
    final res = await _api.put('trainer/storefront-cms', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST trainer/media – Upload brand logo via media-route met usage 'branding_logo'.
  Future<Map<String, dynamic>> uploadProPlusLogo(String filePath) async {
    final res = await _api.postMultipart(
      'trainer/media',
      fileField: 'file',
      file: filePath,
      fields: {'type': 'photo', 'usage': 'branding_logo'},
    );
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST trainer/media – Upload brand banner via media-route met usage 'branding_banner'.
  Future<Map<String, dynamic>> uploadProPlusBanner(String filePath) async {
    final res = await _api.postMultipart(
      'trainer/media',
      fileField: 'file',
      file: filePath,
      fields: {'type': 'photo', 'usage': 'branding_banner'},
    );
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET trainer/pro-plus/newsletters – Haal verstuurde nieuwsbrieven op.
  Future<List<Map<String, dynamic>>> getNewsletters() async {
    final res = await _api.get('trainer/pro-plus/newsletters');
    final raw = res['data'] ?? res['newsletters'] ?? res;
    if (raw is List) {
      return raw
          .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  /// POST trainer/pro-plus/newsletter – Verstuur nieuwsbrief naar actieve klanten.
  /// Response: { ok, message, sent_to }
  Future<Map<String, dynamic>> sendNewsletter({
    required String subject,
    required String body,
  }) async {
    final res = await _api.post('trainer/pro-plus/newsletter', {
      'subject': subject.trim(),
      'body': body.trim(),
    });
    return _asMap(res['data'] ?? res) ?? res;
  }

  /// GET trainer/pro-plus/newsletters – Haal geschiedenis van verzonden nieuwsbrieven op.
  /// Response: List of { subject, sent_at, recipient_count, open_rate, click_rate }
  Future<List<Map<String, dynamic>>> getTrainerNewsletterHistory() async {
    final res = await _api.get('trainer/pro-plus/newsletters');
    final data = res['data'] ?? res;
    if (data is List) {
      return data
          .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  /// POST trainer/pro-plus/newsletters/schedule – Plan een nieuwsbrief in voor toekomstig versturen.
  /// Response: { ok, message, scheduled_at }
  Future<Map<String, dynamic>> scheduleNewsletter({
    required String subject,
    required String body,
    required DateTime scheduledAt,
  }) async {
    final res = await _api.post('trainer/pro-plus/newsletters/schedule', {
      'subject': subject.trim(),
      'body': body.trim(),
      'scheduled_at': scheduledAt.toIso8601String(),
    });
    return _asMap(res['data'] ?? res) ?? res;
  }

  /// Genereer widget embed code client-side vanuit trainer slug.
  /// Geen backend call nodig – de slug komt uit storefront-cms of trainer/me.
  Future<Map<String, dynamic>> getWidgetCode() async {
    final cms = await getTrainerStorefrontCms();
    final slug = (cms['custom_slug'] as String?) ??
        (cms['slug'] as String?) ??
        '';
    final profileUrl = slug.isNotEmpty
        ? 'https://gymies.nl/t/$slug'
        : '';
    final widgetUrl = slug.isNotEmpty
        ? 'https://gymies.nl/widget/$slug'
        : '';
    final embedCode = slug.isNotEmpty
        ? '<iframe src="$widgetUrl" width="100%" height="600" '
          'frameborder="0" style="border:none;border-radius:12px;" '
          'loading="lazy"></iframe>'
        : '';
    return {
      'embed_code': embedCode,
      'widget_url': widgetUrl,
      'profile_url': profileUrl,
      'slug': slug,
    };
  }

  /// Genereer QR-code data client-side vanuit trainer slug.
  /// QR-code wordt gerenderd door qr_flutter in de UI.
  Future<Map<String, dynamic>> getQRCode() async {
    final cms = await getTrainerStorefrontCms();
    final slug = (cms['custom_slug'] as String?) ??
        (cms['slug'] as String?) ??
        '';
    final profileUrl = slug.isNotEmpty
        ? 'https://gymies.nl/t/$slug'
        : '';
    return {
      'profile_url': profileUrl,
      'slug': slug,
      'url': profileUrl,
      'custom_slug': slug,
    };
  }

  /// PATCH trainer/pro-plus/widget/settings – Update widget customization settings.
  /// Backend route: PATCH trainer/pro-plus/widget/settings
  Future<void> updateWidgetSettings(Map<String, dynamic> settings) async {
    await _api.patch('trainer/pro-plus/widget/settings', settings);
  }

  /// GET trainer/pro-plus/widget/stats – Fetch widget statistics.
  /// Backend route: GET trainer/pro-plus/widget/stats
  /// Returns: {total_views, total_bookings, conversion_rate}
  /// Graceful fallback with empty map if API not ready
  Future<Map<String, dynamic>> getWidgetStats() async {
    try {
      final res = await _api.get('trainer/pro-plus/widget/stats');
      return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
    } catch (e) {
      // Graceful fallback if API endpoint not available
      return <String, dynamic>{};
    }
  }

  /// GET trainer/pro/client-health – Klant analytics via bestaande Pro Hub route.
  /// Combineert client-health data (actief/risico/inactief segmentatie).
  Future<Map<String, dynamic>> getClientAnalytics() async {
    final res = await _api.get('trainer/pro/client-health');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET trainer/pro-plus/analytics/export – Export klant analytics als CSV.
  Future<String> exportClientAnalyticsCsv() async {
    final res = await _api.get('trainer/pro-plus/analytics/export');
    return (res['csv'] ?? res['data'] ?? '').toString();
  }

  // ── Groepslessen (Pro+) ─────────────────────────────────────

  /// GET trainer/group-sessions – Alle groepslessen van de trainer.
  Future<List<Map<String, dynamic>>> getGroupClasses() async {
    final res = await _api.get('trainer/group-sessions');
    final raw = res['data'] ?? res['group_sessions'] ?? res;
    if (raw is List) {
      return raw
          .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  /// POST trainer/group-sessions – Maak een nieuwe groepsles aan.
  Future<Map<String, dynamic>> createGroupClass({
    required String name,
    required int maxParticipants,
    required int durationMinutes,
    required DateTime scheduledAt,
    String? description,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'max_participants': maxParticipants,
      'duration_minutes': durationMinutes,
      'scheduled_at': scheduledAt.toUtc().toIso8601String(),
    };
    if (description != null && description.isNotEmpty) {
      body['description'] = description;
    }
    final res = await _api.post('trainer/group-sessions', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  // ── Refunds ─────────────────────────────────────────────────

  /// GET bookings/:id/refund-preview
  Future<Map<String, dynamic>> getBookingRefundPreview(String bookingId) async {
    final res = await _api.get('bookings/$bookingId/refund-preview');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST bookings/:id/refund
  Future<Map<String, dynamic>> refundBooking(String bookingId, {String? reason}) async {
    final body = <String, dynamic>{};
    if (reason != null && reason.isNotEmpty) body['reason'] = reason;
    final res = await _api.post('bookings/$bookingId/refund', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET group-session-participants/:participantId/refund-preview
  Future<Map<String, dynamic>> getGroupParticipantRefundPreview(String participantId) async {
    final res = await _api.get('group-session-participants/$participantId/refund-preview');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST group-session-participants/:participantId/refund
  Future<Map<String, dynamic>> refundGroupParticipant(String participantId, {String? reason}) async {
    final body = <String, dynamic>{};
    if (reason != null && reason.isNotEmpty) body['reason'] = reason;
    final res = await _api.post('group-session-participants/$participantId/refund', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET trainer/refunds
  Future<List<Map<String, dynamic>>> getTrainerRefunds() async {
    final res = await _api.get('trainer/refunds');
    final raw = res['data'] ?? res['refunds'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  /// GET trainer/group-sessions/:id/payment-overview
  Future<Map<String, dynamic>> getGroupSessionPaymentOverview(String sessionId) async {
    final res = await _api.get('trainer/group-sessions/$sessionId/payment-overview');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  // ── Subscription management ─────────────────────────────────

  /// POST subscription/pause
  Future<Map<String, dynamic>> pauseSubscription() async {
    final res = await _api.post('subscription/pause', {});
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST subscription/resume
  Future<Map<String, dynamic>> resumeSubscription() async {
    final res = await _api.post('subscription/resume', {});
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET subscription/payment-history
  Future<List<Map<String, dynamic>>> getSubscriptionPaymentHistory() async {
    final res = await _api.get('subscription/payment-history');
    final raw = res['data'] ?? res['payments'] ?? res;
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  // ── Fee-beheer (admin) ──────────────────────────────────────

  /// GET vault-console/fees — alle fee settings ophalen.
  Future<Map<String, dynamic>> getAdminFees() async {
    final res = await _api.get('$_adminPrefix/fees');
    return {
      'defaults': _asList(res['defaults']),
      'overrides': _asList(res['overrides']),
      'env_fallback': _asMap(res['env_fallback']) ?? <String, dynamic>{},
    };
  }

  /// POST vault-console/fees — nieuwe fee setting aanmaken.
  Future<Map<String, dynamic>> createAdminFee({
    int? trainerUserId,
    String? planSlug,
    required String feeType,
    required int feeValue,
    required bool clientPays,
  }) async {
    final body = <String, dynamic>{
      'fee_type': feeType,
      'fee_value': feeValue,
      'client_pays': clientPays,
      if (trainerUserId != null) 'trainer_user_id': trainerUserId,
      if (planSlug != null) 'plan_slug': planSlug,
    };
    final res = await _api.post('$_adminPrefix/fees', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// PUT vault-console/fees/{id} — fee setting bijwerken.
  Future<Map<String, dynamic>> updateAdminFee(
    int id, {
    String? feeType,
    int? feeValue,
    bool? clientPays,
    bool? isActive,
  }) async {
    final body = <String, dynamic>{
      if (feeType != null) 'fee_type': feeType,
      if (feeValue != null) 'fee_value': feeValue,
      if (clientPays != null) 'client_pays': clientPays,
      if (isActive != null) 'is_active': isActive,
    };
    final res = await _api.put('$_adminPrefix/fees/$id', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// DELETE vault-console/fees/{id} — fee setting verwijderen.
  Future<void> deleteAdminFee(int id) async {
    await _api.delete('$_adminPrefix/fees/$id');
  }

  List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => _asMap(e) ?? <String, dynamic>{}).toList();
  }

  // ── Wallet / Points ─────────────────────────────────────────

  /// GET points/balance — saldo + recente transacties.
  Future<Map<String, dynamic>> getPointsBalance() async {
    final res = await _api.get('points/balance');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET points/history?page=N — volledige transactiegeschiedenis.
  Future<Map<String, dynamic>> getPointsHistory({int page = 1}) async {
    final res = await _api.get('points/history', queryParams: {'page': page.toString()});
    return {
      'data': _asList(res['data']),
      'pagination': _asMap(res['pagination']) ?? <String, dynamic>{},
    };
  }

  /// POST points/redeem — punten inwisselen voor beloning.
  Future<Map<String, dynamic>> redeemPoints({
    required String rewardType,
    required int pointsToSpend,
  }) async {
    final res = await _api.post('points/redeem', {
      'reward_type': rewardType,
      'points_to_spend': pointsToSpend,
    });
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  // ── Disputes / Geschillen ───────────────────────────────────

  /// POST bookings/{id}/dispute — geschil indienen.
  Future<Map<String, dynamic>> raiseDispute({
    required String bookingId,
    required String reason,
    String? details,
  }) async {
    final body = <String, dynamic>{
      'reason': reason,
      if (details != null && details.trim().isNotEmpty) 'details': details.trim(),
    };
    final res = await _api.post('bookings/${bookingId.trim()}/dispute', body);
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET my-disputes — lijst van eigen geschillen.
  Future<List<Map<String, dynamic>>> getMyDisputes() async {
    final res = await _api.get('my-disputes');
    return _asList(res['data'] ?? res['disputes'] ?? res);
  }

  /// GET disputes/{id} — geschil detail met berichten.
  Future<Map<String, dynamic>> getDisputeDetail(String disputeId) async {
    final res = await _api.get('my-disputes/$disputeId');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// POST disputes/{id}/message — bericht toevoegen aan geschil.
  Future<Map<String, dynamic>> addDisputeMessage({
    required String disputeId,
    required String message,
  }) async {
    final res = await _api.post('my-disputes/$disputeId/message', {
      'message': message.trim(),
    });
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  // ── Insights ────────────────────────────────────────────────────────

  /// GET insights/smart-schedule — trainingspatroon suggesties voor client.
  Future<Map<String, dynamic>> getSmartSchedule() async {
    final res = await _api.get('insights/smart-schedule');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET insights/trainer — natuurlijke taal statistieken voor trainer.
  Future<Map<String, dynamic>> getTrainerInsights() async {
    final res = await _api.get('insights/trainer');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET insights/pricing — marktpositionering voor trainer.
  Future<Map<String, dynamic>> getPricingInsight() async {
    final res = await _api.get('insights/pricing');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// GET insights/reschedule-options/{bookingId} — alternatieven bij annulering.
  Future<Map<String, dynamic>> getRescheduleOptions(String bookingId) async {
    final res = await _api.get('insights/reschedule-options/$bookingId');
    return _asMap(res['data'] ?? res) ?? <String, dynamic>{};
  }

  /// ISO 8601 weeknummer berekenen
  static int _isoWeekNumber(DateTime date) {
    final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
    final jan1 = DateTime(thursday.year, 1, 1);
    return ((thursday.difference(jan1).inDays) / 7).ceil() + 1;
  }
}
