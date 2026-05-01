<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * QR Check-in Systeem – "Digitale Handdruk"
 *
 * Flow:
 * 1. Klant vraagt QR-token op (GET bookings/{id}/checkin-qr)
 *    → Backend genereert 48-char token (120s TTL) + 6-cijfer backup code
 * 2. Trainer scant QR (POST checkin/scan)
 *    → Backend valideert token, controleert GPS (50m radius), registreert check-in
 * 3. Fallback: trainer voert backup code in (POST checkin/manual)
 *    → Wordt altijd gemarkeerd met audit_flag
 *
 * Veiligheidsfeatures:
 * - Token verloopt na 120 seconden (voorkomt screenshot-fraude)
 * - GPS Haversine check: max 50 meter van gym-locatie
 * - Audit flags voor handmatige check-ins en GPS-afwijkingen
 * - Identity fraud reporting + klant blokkeren
 * - SOS noodalert met GPS-coördinaten
 * - Safe Session "dode-man-schakelaar" met overdue detectie
 *
 * Database-agnostisch: werkt met gymies_bookings/bookings en gymies_users/users.
 */
class GymiesCheckinController
{
    /** Token geldigheid in seconden */
    private const TOKEN_TTL_SECONDS = 45;

    /** Maximale afstand in meters voor GPS-validatie */
    private const MAX_DISTANCE_METERS = 50;

    // ──────────────────────────────────────────────────────────────
    // GET bookings/{id}/checkin-qr
    // ──────────────────────────────────────────────────────────────

    /**
     * Genereer QR check-in token voor een boeking.
     *
     * Alleen de klant van de boeking mag dit opvragen.
     * Token is 120 seconden geldig. Bij elke aanvraag wordt een nieuw token gegenereerd.
     * Backup code blijft hetzelfde totdat de klant incheckt.
     *
     * Response: {
     *   qr_value: "JSON string voor in QR code",
     *   token: "48-char hex token",
     *   backup_code: "123456",
     *   expires_in: 120,
     *   expires_at: "2026-04-22T14:30:00Z",
     *   booking_id: "42"
     * }
     */
    public function getCheckinQr(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $bookingsTable = $this->resolveTable(['gymies_bookings', 'bookings']);
        if (!$bookingsTable) {
            return response()->json(['message' => 'Boekingen niet beschikbaar.'], 500);
        }

        $clientCol = $this->resolveColumn($bookingsTable, ['client_user_id', 'client_id', 'user_id']);
        if (!$clientCol) {
            return response()->json(['message' => 'Database configuratie onvolledig.'], 500);
        }

        // Haal boeking op en controleer eigenaarschap
        $booking = DB::table($bookingsTable)->where('id', $id)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        $bookingClientId = $booking->{$clientCol} ?? null;
        if ((int) $bookingClientId !== (int) $user->id) {
            return response()->json(['message' => 'Dit is niet jouw boeking.'], 403);
        }

        // Controleer dat boeking niet al gechecked-in of geannuleerd is
        $statusCol = $this->resolveColumn($bookingsTable, ['status', 'booking_status', 'state']);
        if ($statusCol) {
            $status = $booking->{$statusCol} ?? '';
            if (in_array($status, ['checked_in', 'completed', 'done', 'finished'], true)) {
                return response()->json(['message' => 'Je bent al ingecheckt voor deze sessie.'], 422);
            }
            if (in_array($status, ['cancelled', 'canceled', 'no_show'], true)) {
                return response()->json(['message' => 'Deze boeking is geannuleerd.'], 422);
            }
        }

        // Controleer of boeking vandaag of binnenkort is (max 15 min van tevoren)
        $scheduledCol = $this->resolveColumn($bookingsTable, ['scheduled_at', 'session_at', 'date']);
        if ($scheduledCol && $booking->{$scheduledCol}) {
            $scheduledAt = Carbon::parse($booking->{$scheduledCol});
            $now = now();
            $minutesBefore = $now->diffInMinutes($scheduledAt, false);

            // Mag niet meer dan 60 minuten van tevoren (ruime marge)
            if ($minutesBefore > 60) {
                return response()->json([
                    'message' => 'Je kunt pas 60 minuten voor de sessie inchecken.',
                    'scheduled_at' => $scheduledAt->toIso8601String(),
                    'minutes_until' => (int) $minutesBefore,
                ], 422);
            }
            // Mag niet als sessie meer dan 2 uur geleden was
            if ($minutesBefore < -120) {
                return response()->json([
                    'message' => 'De sessie is al meer dan 2 uur geleden afgelopen.',
                ], 422);
            }
        }

        // Genereer nieuw token (elke keer vers → 120s TTL)
        $token = bin2hex(random_bytes(24)); // 48-char hex
        $expiresAt = now()->addSeconds(self::TOKEN_TTL_SECONDS);

        // Backup code: genereer alleen als er nog geen is, of hergebruik bestaande
        $hasBackupCol = Schema::hasColumn($bookingsTable, 'checkin_backup_code');
        $existingBackup = $hasBackupCol ? ($booking->checkin_backup_code ?? null) : null;
        $backupCode = $existingBackup ?: str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);

        // Sla token op in database
        $update = [];
        if (Schema::hasColumn($bookingsTable, 'checkin_token')) {
            $update['checkin_token'] = $token;
        }
        if (Schema::hasColumn($bookingsTable, 'checkin_token_expires_at')) {
            $update['checkin_token_expires_at'] = $expiresAt;
        }
        if ($hasBackupCol && !$existingBackup) {
            $update['checkin_backup_code'] = $backupCode;
        }
        if (Schema::hasColumn($bookingsTable, 'updated_at')) {
            $update['updated_at'] = now();
        }

        if (!empty($update)) {
            DB::table($bookingsTable)->where('id', $id)->update($update);
        }

        // QR payload: dit is wat in de QR-code staat
        $qrPayload = json_encode([
            'type' => 'gymies_checkin',
            'booking_id' => (string) $id,
            'token' => $token,
            'v' => 2, // versie voor forward-compatibility
        ], JSON_UNESCAPED_SLASHES);

        return response()->json([
            'qr_value' => $qrPayload,
            'token' => $token,
            'backup_code' => $backupCode,
            'booking_id' => (string) $id,
            'expires_in' => self::TOKEN_TTL_SECONDS,
            'expires_at' => $expiresAt->toIso8601String(),
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    // POST checkin/scan
    // ──────────────────────────────────────────────────────────────

    /**
     * Trainer scant QR-code van klant.
     *
     * Request body:
     *   - token (string, required): het 48-char hex token uit de QR
     *   - trainer_lat (float, optional): GPS latitude van trainer
     *   - trainer_lng (float, optional): GPS longitude van trainer
     *   - payload (string, optional): raw QR payload voor logging
     *
     * Valideert:
     * 1. Token bestaat en is niet verlopen (120s window)
     * 2. Boeking hoort bij deze trainer
     * 3. GPS-afstand ≤ 50m (indien coördinaten beschikbaar)
     *
     * Response: { ok, message, booking_id, client_name, distance_meters, audit_flag }
     */
    public function scanCheckin(Request $request): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $token = trim($request->input('token', ''));
        if (empty($token)) {
            return response()->json(['message' => 'QR token ontbreekt.'], 422);
        }

        $bookingsTable = $this->resolveTable(['gymies_bookings', 'bookings']);
        $usersTable = $this->resolveTable(['gymies_users', 'users']);
        if (!$bookingsTable) {
            return response()->json(['message' => 'Boekingen niet beschikbaar.'], 500);
        }

        // Zoek boeking op basis van token
        if (!Schema::hasColumn($bookingsTable, 'checkin_token')) {
            return response()->json(['message' => 'Check-in niet geconfigureerd.'], 500);
        }

        $booking = DB::table($bookingsTable)
            ->where('checkin_token', $token)
            ->first();

        if (!$booking) {
            return response()->json([
                'message' => 'Ongeldige QR-code. Vraag de klant een nieuwe code op te vragen.',
                'error_code' => 'INVALID_TOKEN',
            ], 422);
        }

        // Token verlopen?
        if (Schema::hasColumn($bookingsTable, 'checkin_token_expires_at')) {
            $expiresAt = $booking->checkin_token_expires_at
                ? Carbon::parse($booking->checkin_token_expires_at)
                : null;
            if ($expiresAt && $expiresAt->isPast()) {
                return response()->json([
                    'message' => 'QR-code is verlopen. Vraag de klant een nieuwe code op te vragen.',
                    'error_code' => 'TOKEN_EXPIRED',
                    'expired_seconds_ago' => (int) $expiresAt->diffInSeconds(now()),
                ], 422);
            }
        }

        // Trainer-eigenaarschap check
        $trainerCol = $this->resolveColumn($bookingsTable, ['trainer_user_id', 'trainer_id']);
        if ($trainerCol) {
            $bookingTrainerId = $booking->{$trainerCol} ?? null;
            if ((int) $bookingTrainerId !== (int) $trainer->id) {
                return response()->json([
                    'message' => 'Deze boeking hoort niet bij jou.',
                    'error_code' => 'WRONG_TRAINER',
                ], 403);
            }
        }

        // Al ingecheckt?
        if (Schema::hasColumn($bookingsTable, 'check_in_at') && $booking->check_in_at) {
            return response()->json([
                'message' => 'Klant is al ingecheckt.',
                'error_code' => 'ALREADY_CHECKED_IN',
                'check_in_at' => $booking->check_in_at,
            ], 422);
        }

        // GPS-afstand berekenen
        $trainerLat = $request->input('trainer_lat');
        $trainerLng = $request->input('trainer_lng');
        $distanceMeters = null;
        $auditFlag = false;
        $auditReasons = [];

        if ($trainerLat && $trainerLng) {
            // Haal gym-locatie op (vanuit trainer profiel of locatie-tabel)
            $gymLocation = $this->resolveGymLocation($booking, $bookingsTable);
            if ($gymLocation) {
                $distanceMeters = $this->haversineDistance(
                    (float) $trainerLat,
                    (float) $trainerLng,
                    $gymLocation['lat'],
                    $gymLocation['lng']
                );
                if ($distanceMeters > self::MAX_DISTANCE_METERS) {
                    $auditFlag = true;
                    $auditReasons[] = "GPS afstand {$distanceMeters}m > " . self::MAX_DISTANCE_METERS . "m";
                }
            }
        }

        // Registreer check-in
        $update = [];
        if (Schema::hasColumn($bookingsTable, 'check_in_at')) {
            $update['check_in_at'] = now();
        }
        if (Schema::hasColumn($bookingsTable, 'check_in_method')) {
            $update['check_in_method'] = 'qr_scan';
        }
        if (Schema::hasColumn($bookingsTable, 'check_in_lat') && $trainerLat) {
            $update['check_in_lat'] = (float) $trainerLat;
        }
        if (Schema::hasColumn($bookingsTable, 'check_in_lng') && $trainerLng) {
            $update['check_in_lng'] = (float) $trainerLng;
        }
        if (Schema::hasColumn($bookingsTable, 'check_in_distance_meters') && $distanceMeters !== null) {
            $update['check_in_distance_meters'] = (int) round($distanceMeters);
        }
        if (Schema::hasColumn($bookingsTable, 'check_in_audit_flag')) {
            $update['check_in_audit_flag'] = $auditFlag;
        }
        // Invalideer token na gebruik (one-time use)
        if (Schema::hasColumn($bookingsTable, 'checkin_token')) {
            $update['checkin_token'] = null;
        }
        if (Schema::hasColumn($bookingsTable, 'checkin_token_expires_at')) {
            $update['checkin_token_expires_at'] = null;
        }
        // Update status naar checked_in
        $statusCol = $this->resolveColumn($bookingsTable, ['status', 'booking_status', 'state']);
        if ($statusCol) {
            $update[$statusCol] = 'checked_in';
        }
        if (Schema::hasColumn($bookingsTable, 'updated_at')) {
            $update['updated_at'] = now();
        }

        DB::table($bookingsTable)->where('id', $booking->id)->update($update);

        // Klant-naam ophalen voor response
        $clientName = 'Klant';
        $clientCol = $this->resolveColumn($bookingsTable, ['client_user_id', 'client_id', 'user_id']);
        if ($clientCol && $usersTable) {
            $clientId = $booking->{$clientCol} ?? null;
            if ($clientId) {
                $client = DB::table($usersTable)->where('id', $clientId)->first();
                if ($client) {
                    $clientName = $client->display_name ?? $client->name ?? $client->email ?? 'Klant';
                }
            }
        }

        // Push-notificatie naar klant: "Je bent ingecheckt!"
        $this->notifyClient($booking, $bookingsTable, 'check_in', [
            'title' => 'Ingecheckt! ✓',
            'body' => "Je bent ingecheckt voor je sessie. Veel succes!",
        ]);

        return response()->json([
            'ok' => true,
            'message' => "Check-in geregistreerd voor {$clientName}.",
            'booking_id' => (string) $booking->id,
            'client_name' => $clientName,
            'check_in_at' => now()->toIso8601String(),
            'distance_meters' => $distanceMeters !== null ? (int) round($distanceMeters) : null,
            'audit_flag' => $auditFlag,
            'audit_reasons' => $auditReasons,
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    // POST checkin/manual
    // ──────────────────────────────────────────────────────────────

    /**
     * Handmatige check-in met 6-cijferige backup code.
     * Wordt altijd gemarkeerd met audit_flag.
     *
     * Request body:
     *   - booking_id (string, required)
     *   - backup_code (string, required): 6 cijfers
     *   - trainer_lat (float, optional)
     *   - trainer_lng (float, optional)
     */
    public function manualCheckin(Request $request): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $bookingId = trim($request->input('booking_id', ''));
        $backupCode = trim($request->input('backup_code', ''));

        if (empty($bookingId)) {
            return response()->json(['message' => 'Booking ID ontbreekt.'], 422);
        }
        if (empty($backupCode) || !preg_match('/^\d{6}$/', $backupCode)) {
            return response()->json(['message' => 'Backup code moet 6 cijfers zijn.'], 422);
        }

        $bookingsTable = $this->resolveTable(['gymies_bookings', 'bookings']);
        $usersTable = $this->resolveTable(['gymies_users', 'users']);
        if (!$bookingsTable) {
            return response()->json(['message' => 'Boekingen niet beschikbaar.'], 500);
        }

        $booking = DB::table($bookingsTable)->where('id', $bookingId)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        // Trainer-eigenaarschap check
        $trainerCol = $this->resolveColumn($bookingsTable, ['trainer_user_id', 'trainer_id']);
        if ($trainerCol) {
            $bookingTrainerId = $booking->{$trainerCol} ?? null;
            if ((int) $bookingTrainerId !== (int) $trainer->id) {
                return response()->json(['message' => 'Deze boeking hoort niet bij jou.'], 403);
            }
        }

        // Al ingecheckt?
        if (Schema::hasColumn($bookingsTable, 'check_in_at') && $booking->check_in_at) {
            return response()->json(['message' => 'Klant is al ingecheckt.'], 422);
        }

        // Backup code valideren
        if (!Schema::hasColumn($bookingsTable, 'checkin_backup_code')) {
            return response()->json(['message' => 'Backup codes niet geconfigureerd.'], 500);
        }

        $storedCode = $booking->checkin_backup_code ?? '';
        if ($storedCode !== $backupCode) {
            return response()->json([
                'message' => 'Ongeldige backup code.',
                'error_code' => 'INVALID_BACKUP_CODE',
            ], 422);
        }

        // GPS check (zelfde logica als scanCheckin)
        $trainerLat = $request->input('trainer_lat');
        $trainerLng = $request->input('trainer_lng');
        $distanceMeters = null;
        $auditReasons = ['Handmatige check-in (backup code)'];

        if ($trainerLat && $trainerLng) {
            $gymLocation = $this->resolveGymLocation($booking, $bookingsTable);
            if ($gymLocation) {
                $distanceMeters = $this->haversineDistance(
                    (float) $trainerLat,
                    (float) $trainerLng,
                    $gymLocation['lat'],
                    $gymLocation['lng']
                );
                if ($distanceMeters > self::MAX_DISTANCE_METERS) {
                    $auditReasons[] = "GPS afstand {$distanceMeters}m > " . self::MAX_DISTANCE_METERS . "m";
                }
            }
        }

        // Registreer check-in (altijd audit_flag = true bij handmatig)
        $update = [];
        if (Schema::hasColumn($bookingsTable, 'check_in_at')) {
            $update['check_in_at'] = now();
        }
        if (Schema::hasColumn($bookingsTable, 'check_in_method')) {
            $update['check_in_method'] = 'manual_code';
        }
        if (Schema::hasColumn($bookingsTable, 'check_in_lat') && $trainerLat) {
            $update['check_in_lat'] = (float) $trainerLat;
        }
        if (Schema::hasColumn($bookingsTable, 'check_in_lng') && $trainerLng) {
            $update['check_in_lng'] = (float) $trainerLng;
        }
        if (Schema::hasColumn($bookingsTable, 'check_in_distance_meters') && $distanceMeters !== null) {
            $update['check_in_distance_meters'] = (int) round($distanceMeters);
        }
        if (Schema::hasColumn($bookingsTable, 'check_in_audit_flag')) {
            $update['check_in_audit_flag'] = true; // Altijd true bij handmatig
        }
        // Invalideer backup code na gebruik
        if (Schema::hasColumn($bookingsTable, 'checkin_backup_code')) {
            $update['checkin_backup_code'] = null;
        }
        if (Schema::hasColumn($bookingsTable, 'checkin_token')) {
            $update['checkin_token'] = null;
        }
        if (Schema::hasColumn($bookingsTable, 'checkin_token_expires_at')) {
            $update['checkin_token_expires_at'] = null;
        }
        $statusCol = $this->resolveColumn($bookingsTable, ['status', 'booking_status', 'state']);
        if ($statusCol) {
            $update[$statusCol] = 'checked_in';
        }
        if (Schema::hasColumn($bookingsTable, 'updated_at')) {
            $update['updated_at'] = now();
        }

        DB::table($bookingsTable)->where('id', $booking->id)->update($update);

        // Klant-naam
        $clientName = 'Klant';
        $clientCol = $this->resolveColumn($bookingsTable, ['client_user_id', 'client_id', 'user_id']);
        if ($clientCol && $usersTable) {
            $clientId = $booking->{$clientCol} ?? null;
            if ($clientId) {
                $client = DB::table($usersTable)->where('id', $clientId)->first();
                if ($client) {
                    $clientName = $client->display_name ?? $client->name ?? $client->email ?? 'Klant';
                }
            }
        }

        $this->notifyClient($booking, $bookingsTable, 'check_in', [
            'title' => 'Ingecheckt! ✓',
            'body' => "Je bent ingecheckt voor je sessie. Veel succes!",
        ]);

        return response()->json([
            'ok' => true,
            'message' => "Check-in geregistreerd voor {$clientName} (handmatig).",
            'booking_id' => (string) $booking->id,
            'client_name' => $clientName,
            'check_in_at' => now()->toIso8601String(),
            'audit_flag' => true,
            'audit_reasons' => $auditReasons,
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    // POST checkin/report-fraud
    // ──────────────────────────────────────────────────────────────

    /**
     * Meld identiteitsfraude: de persoon die zich meldt is niet de klant.
     * Trainer kan een klant als verdacht markeren.
     *
     * Request body:
     *   - booking_id (string, required)
     *   - reason (string, required): reden van de melding
     *   - evidence_url (string, optional): foto/bewijs URL
     */
    public function reportIdentityFraud(Request $request): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $bookingId = trim($request->input('booking_id', ''));
        $reason = trim($request->input('reason', ''));

        if (empty($bookingId)) {
            return response()->json(['message' => 'Booking ID ontbreekt.'], 422);
        }
        if (empty($reason)) {
            return response()->json(['message' => 'Reden voor melding is verplicht.'], 422);
        }

        $bookingsTable = $this->resolveTable(['gymies_bookings', 'bookings']);
        if (!$bookingsTable) {
            return response()->json(['message' => 'Boekingen niet beschikbaar.'], 500);
        }

        $booking = DB::table($bookingsTable)->where('id', $bookingId)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        // Sla fraude-melding op in audit log tabel
        $auditTable = $this->resolveTable(['gymies_audit_logs', 'audit_logs']);
        if ($auditTable) {
            try {
                $insert = [
                    'type' => 'identity_fraud_report',
                    'booking_id' => $bookingId,
                    'reporter_user_id' => (int) $trainer->id,
                    'created_at' => now(),
                ];
                if (Schema::hasColumn($auditTable, 'details')) {
                    $insert['details'] = json_encode([
                        'reason' => $reason,
                        'evidence_url' => $request->input('evidence_url'),
                    ]);
                }
                if (Schema::hasColumn($auditTable, 'data')) {
                    $insert['data'] = json_encode([
                        'reason' => $reason,
                        'evidence_url' => $request->input('evidence_url'),
                    ]);
                }
                DB::table($auditTable)->insert($insert);
            } catch (\Throwable) {
                // Audit log insert faalde, maar melding moet doorgaan
            }
        }

        // Markeer boeking als frauduleus
        $update = [];
        if (Schema::hasColumn($bookingsTable, 'check_in_audit_flag')) {
            $update['check_in_audit_flag'] = true;
        }
        $statusCol = $this->resolveColumn($bookingsTable, ['status', 'booking_status', 'state']);
        if ($statusCol) {
            $update[$statusCol] = 'fraud_reported';
        }
        if (Schema::hasColumn($bookingsTable, 'updated_at')) {
            $update['updated_at'] = now();
        }
        if (!empty($update)) {
            DB::table($bookingsTable)->where('id', $bookingId)->update($update);
        }

        // Notificeer admin/platform
        $this->notifyAdmin('identity_fraud', [
            'booking_id' => $bookingId,
            'trainer_id' => (int) $trainer->id,
            'trainer_name' => $trainer->display_name ?? $trainer->name ?? 'Trainer',
            'reason' => $reason,
        ]);

        return response()->json([
            'ok' => true,
            'message' => 'Fraude-melding geregistreerd. We nemen contact op.',
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    // POST sos/alert
    // ──────────────────────────────────────────────────────────────

    /**
     * SOS noodalert – voor zowel klanten als trainers.
     *
     * Request body:
     *   - booking_id (string, optional): gekoppelde boeking
     *   - latitude (float, optional): GPS latitude
     *   - longitude (float, optional): GPS longitude
     *   - note (string, optional): extra informatie
     *
     * Acties:
     * 1. Opslaan in audit_logs/sos_alerts tabel
     * 2. Push-notificatie naar platform admin
     * 3. Push-notificatie naar noodcontact van de gebruiker (indien ingesteld)
     * 4. E-mail naar platform veiligheidscontact
     */
    public function sosAlert(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $bookingId = $request->input('booking_id');
        $latitude = $request->input('latitude');
        $longitude = $request->input('longitude');
        $note = trim($request->input('note', ''));

        // Opslaan in sos_alerts of audit_logs tabel
        $sosTable = $this->resolveTable(['gymies_sos_alerts', 'sos_alerts']);
        $auditTable = $this->resolveTable(['gymies_audit_logs', 'audit_logs']);

        $alertData = [
            'user_id' => (int) $user->id,
            'user_name' => $user->display_name ?? $user->name ?? 'Gebruiker',
            'booking_id' => $bookingId,
            'latitude' => $latitude,
            'longitude' => $longitude,
            'note' => $note,
        ];

        if ($sosTable) {
            try {
                $insert = array_merge($alertData, [
                    'status' => 'active',
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
                // Alleen kolommen inserten die bestaan
                $filtered = [];
                foreach ($insert as $col => $val) {
                    if (Schema::hasColumn($sosTable, $col)) {
                        $filtered[$col] = $val;
                    }
                }
                if (!empty($filtered)) {
                    DB::table($sosTable)->insert($filtered);
                }
            } catch (\Throwable) {
                // SOS tabel insert faalde, log in audit
            }
        }

        if ($auditTable) {
            try {
                $insert = [
                    'type' => 'sos_alert',
                    'created_at' => now(),
                ];
                if (Schema::hasColumn($auditTable, 'reporter_user_id')) {
                    $insert['reporter_user_id'] = (int) $user->id;
                }
                if (Schema::hasColumn($auditTable, 'user_id')) {
                    $insert['user_id'] = (int) $user->id;
                }
                if (Schema::hasColumn($auditTable, 'details')) {
                    $insert['details'] = json_encode($alertData);
                }
                if (Schema::hasColumn($auditTable, 'data')) {
                    $insert['data'] = json_encode($alertData);
                }
                if (Schema::hasColumn($auditTable, 'booking_id') && $bookingId) {
                    $insert['booking_id'] = $bookingId;
                }
                DB::table($auditTable)->insert($insert);
            } catch (\Throwable) {
                // Audit faalde maar SOS moet doorgaan
            }
        }

        // Noodcontact ophalen en notificeren
        $this->notifyEmergencyContact($user, $alertData);

        // Platform admin notificeren
        $this->notifyAdmin('sos_alert', $alertData);

        // Als er een booking is: notificeer de andere partij
        if ($bookingId) {
            $this->notifyOtherParty($user, $bookingId, $alertData);
        }

        return response()->json([
            'ok' => true,
            'message' => 'SOS-alert verstuurd. We hebben je noodcontact en het platform op de hoogte gesteld.',
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    // POST bookings/{id}/safe-session/start
    // ──────────────────────────────────────────────────────────────

    /**
     * Start een Safe Session – "dode-man-schakelaar".
     *
     * Na het starten loopt er een timer. Als de trainer niet uitcheckt
     * binnen de verwachte sessieduur + 30 min marge, wordt automatisch
     * een alert gestuurd (via cron/safe-session-overdue).
     *
     * Request body:
     *   - note (string, optional): reden/notitie
     *
     * Wat er gebeurt:
     * 1. safe_session_active = true op de boeking
     * 2. safe_session_started_at = now()
     * 3. Push-notificatie naar klant: "Veiligheidssessie gestart"
     * 4. Als noodcontact is ingesteld: stille notificatie dat sessie loopt
     */
    public function startSafeSession(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $bookingsTable = $this->resolveTable(['gymies_bookings', 'bookings']);
        if (!$bookingsTable) {
            return response()->json(['message' => 'Boekingen niet beschikbaar.'], 500);
        }

        $booking = DB::table($bookingsTable)->where('id', $id)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        // Controleer dat boeking ingecheckt is
        $isCheckedIn = false;
        if (Schema::hasColumn($bookingsTable, 'check_in_at') && $booking->check_in_at) {
            $isCheckedIn = true;
        }
        $statusCol = $this->resolveColumn($bookingsTable, ['status', 'booking_status', 'state']);
        if ($statusCol && ($booking->{$statusCol} ?? '') === 'checked_in') {
            $isCheckedIn = true;
        }

        if (!$isCheckedIn) {
            return response()->json([
                'message' => 'Klant moet eerst ingecheckt zijn voordat een safe session gestart kan worden.',
            ], 422);
        }

        // Al actief?
        if (Schema::hasColumn($bookingsTable, 'safe_session_active') && $booking->safe_session_active) {
            return response()->json([
                'message' => 'Safe session is al actief.',
                'started_at' => $booking->safe_session_started_at ?? null,
            ], 422);
        }

        // Bereken verwachte eindtijd (sessieduur + 30 min marge)
        $durationMinutes = 60; // default
        if (Schema::hasColumn($bookingsTable, 'duration_minutes') && $booking->duration_minutes) {
            $durationMinutes = (int) $booking->duration_minutes;
        } elseif (Schema::hasColumn($bookingsTable, 'duration') && $booking->duration) {
            $durationMinutes = (int) $booking->duration;
        }
        $expectedEndAt = now()->addMinutes($durationMinutes + 30); // +30 min marge

        // Update boeking
        $update = [];
        if (Schema::hasColumn($bookingsTable, 'safe_session_active')) {
            $update['safe_session_active'] = true;
        }
        if (Schema::hasColumn($bookingsTable, 'safe_session_started_at')) {
            $update['safe_session_started_at'] = now();
        }
        if (Schema::hasColumn($bookingsTable, 'safe_session_expected_end_at')) {
            $update['safe_session_expected_end_at'] = $expectedEndAt;
        }
        if (Schema::hasColumn($bookingsTable, 'updated_at')) {
            $update['updated_at'] = now();
        }

        if (!empty($update)) {
            DB::table($bookingsTable)->where('id', $id)->update($update);
        }

        // Push-notificatie naar klant
        $this->notifyClient($booking, $bookingsTable, 'safe_session_start', [
            'title' => 'Veiligheidssessie gestart',
            'body' => 'De trainer heeft een veiligheidssessie gestart. Je wordt automatisch beschermd.',
        ]);

        // Stille notificatie naar noodcontact
        $clientCol = $this->resolveColumn($bookingsTable, ['client_user_id', 'client_id', 'user_id']);
        if ($clientCol) {
            $clientId = $booking->{$clientCol} ?? null;
            if ($clientId) {
                $usersTable = $this->resolveTable(['gymies_users', 'users']);
                if ($usersTable) {
                    $client = DB::table($usersTable)->where('id', $clientId)->first();
                    if ($client) {
                        $this->notifyEmergencyContact($client, [
                            'type' => 'safe_session_started',
                            'user_name' => $client->display_name ?? $client->name ?? 'Klant',
                            'booking_id' => $id,
                            'expected_end_at' => $expectedEndAt->toIso8601String(),
                        ]);
                    }
                }
            }
        }

        return response()->json([
            'ok' => true,
            'message' => 'Safe session gestart.',
            'safe_session_started_at' => now()->toIso8601String(),
            'expected_end_at' => $expectedEndAt->toIso8601String(),
            'duration_minutes' => $durationMinutes,
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    // POST bookings/{id}/checkout
    // ──────────────────────────────────────────────────────────────

    /**
     * Sessie beëindigen / uitchecken.
     * Stopt ook de safe session als die actief was.
     */
    public function checkOut(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $bookingsTable = $this->resolveTable(['gymies_bookings', 'bookings']);
        if (!$bookingsTable) {
            return response()->json(['message' => 'Boekingen niet beschikbaar.'], 500);
        }

        $booking = DB::table($bookingsTable)->where('id', $id)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        $update = [];
        if (Schema::hasColumn($bookingsTable, 'check_out_at')) {
            $update['check_out_at'] = now();
        }
        if (Schema::hasColumn($bookingsTable, 'safe_session_active')) {
            $update['safe_session_active'] = false;
        }
        $statusCol = $this->resolveColumn($bookingsTable, ['status', 'booking_status', 'state']);
        if ($statusCol) {
            $update[$statusCol] = 'completed';
        }
        if (Schema::hasColumn($bookingsTable, 'updated_at')) {
            $update['updated_at'] = now();
        }

        if (!empty($update)) {
            DB::table($bookingsTable)->where('id', $id)->update($update);
        }

        // Notificeer klant
        $this->notifyClient($booking, $bookingsTable, 'checkout', [
            'title' => 'Sessie afgerond',
            'body' => 'Je sessie is afgerond. Goed gedaan!',
        ]);

        return response()->json([
            'ok' => true,
            'message' => 'Sessie afgerond.',
            'check_out_at' => now()->toIso8601String(),
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    // POST bookings/{id}/safe-session/heartbeat
    // ──────────────────────────────────────────────────────────────

    /**
     * Klant bevestigt "Ik ben OK" – reset de overdue timer.
     *
     * Bij elke heartbeat wordt safe_session_expected_end_at verlengd
     * met de resterende sessieduur (of minimaal 30 minuten).
     * Dit voorkomt valse alarmen als een sessie iets langer duurt.
     */
    public function safeSessionHeartbeat(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $bookingsTable = $this->resolveTable(['gymies_bookings', 'bookings']);
        if (!$bookingsTable) {
            return response()->json(['message' => 'Boekingen niet beschikbaar.'], 500);
        }

        $booking = DB::table($bookingsTable)->where('id', $id)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        // Controleer dat safe session actief is
        $isActive = Schema::hasColumn($bookingsTable, 'safe_session_active')
            && $booking->safe_session_active;
        if (!$isActive) {
            return response()->json(['message' => 'Geen actieve safe session.'], 422);
        }

        // Verleng expected end met 30 minuten
        $newExpectedEnd = now()->addMinutes(30);
        $update = [];
        if (Schema::hasColumn($bookingsTable, 'safe_session_expected_end_at')) {
            $update['safe_session_expected_end_at'] = $newExpectedEnd;
        }
        if (Schema::hasColumn($bookingsTable, 'safe_session_last_heartbeat_at')) {
            $update['safe_session_last_heartbeat_at'] = now();
        }
        if (Schema::hasColumn($bookingsTable, 'updated_at')) {
            $update['updated_at'] = now();
        }

        if (!empty($update)) {
            DB::table($bookingsTable)->where('id', $id)->update($update);
        }

        return response()->json([
            'ok' => true,
            'message' => 'Heartbeat ontvangen. Timer verlengd.',
            'expected_end_at' => $newExpectedEnd->toIso8601String(),
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    // GET bookings/{id}/safe-session/status
    // ──────────────────────────────────────────────────────────────

    /**
     * Haal de huidige safe session status op.
     * Gebruikt door zowel klant als trainer om te zien of een safe session actief is.
     */
    public function safeSessionStatus(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $bookingsTable = $this->resolveTable(['gymies_bookings', 'bookings']);
        if (!$bookingsTable) {
            return response()->json(['message' => 'Boekingen niet beschikbaar.'], 500);
        }

        $booking = DB::table($bookingsTable)->where('id', $id)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        $active = Schema::hasColumn($bookingsTable, 'safe_session_active')
            ? (bool) $booking->safe_session_active
            : false;

        $startedAt = Schema::hasColumn($bookingsTable, 'safe_session_started_at')
            ? $booking->safe_session_started_at
            : null;

        $expectedEndAt = Schema::hasColumn($bookingsTable, 'safe_session_expected_end_at')
            ? $booking->safe_session_expected_end_at
            : null;

        $lastHeartbeat = Schema::hasColumn($bookingsTable, 'safe_session_last_heartbeat_at')
            ? ($booking->safe_session_last_heartbeat_at ?? null)
            : null;

        $minutesRemaining = null;
        $escalation = 'none';

        if ($active && $expectedEndAt) {
            $end = Carbon::parse($expectedEndAt);
            $minutesRemaining = (int) max(0, now()->diffInMinutes($end, false));

            if ($minutesRemaining <= 0) {
                $overMinutes = abs($minutesRemaining);
                if ($overMinutes > 90) {
                    $escalation = 'critical';
                } elseif ($overMinutes > 30) {
                    $escalation = 'emergency';
                } else {
                    $escalation = 'warning';
                }
            }
        }

        return response()->json([
            'data' => [
                'active' => $active,
                'started_at' => $startedAt,
                'expected_end_at' => $expectedEndAt,
                'last_heartbeat_at' => $lastHeartbeat,
                'minutes_remaining' => $minutesRemaining,
                'escalation' => $escalation,
                'check_in_at' => $booking->check_in_at ?? null,
                'check_out_at' => $booking->check_out_at ?? null,
            ],
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    // Private helpers
    // ──────────────────────────────────────────────────────────────

    /**
     * Haversine-formule: afstand in meters tussen twee GPS-coördinaten.
     */
    private function haversineDistance(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earthRadius = 6371000; // meters
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);

        $a = sin($dLat / 2) * sin($dLat / 2)
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2))
            * sin($dLng / 2) * sin($dLng / 2);

        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));

        return $earthRadius * $c;
    }

    /**
     * Probeer gym-locatie op te halen voor GPS-check.
     * Kijkt in: boeking zelf, trainer profiel, locatie-tabel.
     */
    private function resolveGymLocation(object $booking, string $bookingsTable): ?array
    {
        // 1. Locatie op de boeking zelf
        if (Schema::hasColumn($bookingsTable, 'location_lat') && Schema::hasColumn($bookingsTable, 'location_lng')) {
            $lat = $booking->location_lat ?? null;
            $lng = $booking->location_lng ?? null;
            if ($lat && $lng) {
                return ['lat' => (float) $lat, 'lng' => (float) $lng];
            }
        }

        // 2. Via locatie-tabel (gym_location_id op boeking)
        if (Schema::hasColumn($bookingsTable, 'gym_location_id') && $booking->gym_location_id) {
            $locTable = $this->resolveTable(['gymies_locations', 'locations', 'gym_locations']);
            if ($locTable) {
                $loc = DB::table($locTable)->where('id', $booking->gym_location_id)->first();
                if ($loc) {
                    $lat = $loc->latitude ?? $loc->lat ?? null;
                    $lng = $loc->longitude ?? $loc->lng ?? null;
                    if ($lat && $lng) {
                        return ['lat' => (float) $lat, 'lng' => (float) $lng];
                    }
                }
            }
        }

        // 3. Trainer profiel locatie
        $trainerCol = $this->resolveColumn($bookingsTable, ['trainer_user_id', 'trainer_id']);
        if ($trainerCol) {
            $trainerId = $booking->{$trainerCol} ?? null;
            if ($trainerId) {
                $usersTable = $this->resolveTable(['gymies_users', 'users']);
                if ($usersTable) {
                    $trainer = DB::table($usersTable)->where('id', $trainerId)->first();
                    if ($trainer) {
                        $lat = $trainer->latitude ?? $trainer->location_lat ?? null;
                        $lng = $trainer->longitude ?? $trainer->location_lng ?? null;
                        if ($lat && $lng) {
                            return ['lat' => (float) $lat, 'lng' => (float) $lng];
                        }
                    }
                }
            }
        }

        return null; // Geen locatie gevonden → GPS check overslaan
    }

    /**
     * Stuur push-notificatie naar de klant van een boeking.
     */
    private function notifyClient(object $booking, string $bookingsTable, string $type, array $data): void
    {
        try {
            $clientCol = $this->resolveColumn($bookingsTable, ['client_user_id', 'client_id', 'user_id']);
            if (!$clientCol) return;

            $clientId = $booking->{$clientCol} ?? null;
            if (!$clientId) return;

            // Gebruik het bestaande notificatie-systeem
            $notificationsTable = $this->resolveTable(['notifications']);
            if (!$notificationsTable) return;

            $usersTable = $this->resolveTable(['gymies_users', 'users']);
            $notifiableType = 'App\Models\User';
            if ($usersTable === 'gymies_users') {
                $notifiableType = 'App\Models\GymiesUser';
            }

            DB::table($notificationsTable)->insert([
                'id' => Str::uuid()->toString(),
                'type' => 'App\Notifications\GymiesNotification',
                'notifiable_type' => $notifiableType,
                'notifiable_id' => (int) $clientId,
                'data' => json_encode(array_merge($data, [
                    'notification_type' => $type,
                    'booking_id' => (string) $booking->id,
                ])),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // FCM push als device tokens beschikbaar zijn
            if (class_exists(FcmPushHelper::class)) {
                FcmPushHelper::sendToUser((int) $clientId, $data['title'] ?? '', $data['body'] ?? '', [
                    'type' => $type,
                    'booking_id' => (string) $booking->id,
                ]);
            }
        } catch (\Throwable) {
            // Notificatie faalde, maar check-in flow mag niet breken
        }
    }

    /**
     * Notificeer het noodcontact van een gebruiker.
     */
    private function notifyEmergencyContact(object $user, array $alertData): void
    {
        try {
            $usersTable = $this->resolveTable(['gymies_users', 'users']);
            if (!$usersTable) return;

            // Noodcontact ophalen uit gebruikersprofiel
            $emergencyEmail = null;
            $emergencyPhone = null;
            $emergencyName = null;

            if (Schema::hasColumn($usersTable, 'emergency_contact_email')) {
                $dbUser = DB::table($usersTable)->where('id', $user->id)->first();
                $emergencyEmail = $dbUser->emergency_contact_email ?? null;
                $emergencyPhone = $dbUser->emergency_contact_phone ?? null;
                $emergencyName = $dbUser->emergency_contact_name ?? null;
            }

            if (!$emergencyEmail && !$emergencyPhone) {
                return; // Geen noodcontact ingesteld
            }

            $userName = $user->display_name ?? $user->name ?? 'Gebruiker';

            // E-mail naar noodcontact
            if ($emergencyEmail) {
                try {
                    \Illuminate\Support\Facades\Mail::raw(
                        "Dit is een automatisch noodbericht van Gymies.\n\n"
                        . "{$userName} heeft een noodmelding verstuurd via de Gymies app.\n\n"
                        . ($alertData['latitude'] ?? false
                            ? "Locatie: https://maps.google.com/?q={$alertData['latitude']},{$alertData['longitude']}\n\n"
                            : '')
                        . ($alertData['note'] ?? false ? "Bericht: {$alertData['note']}\n\n" : '')
                        . "Neem indien nodig contact op met {$userName} of bel 112.\n\n"
                        . "– Gymies Veiligheidssysteem",
                        function ($message) use ($emergencyEmail, $emergencyName, $userName) {
                            $message->to($emergencyEmail, $emergencyName ?? 'Noodcontact');
                            $message->subject("NOODMELDING: {$userName} heeft hulp nodig");
                        }
                    );
                } catch (\Throwable) {
                    // E-mail faalde, maar alert is al opgeslagen
                }
            }
        } catch (\Throwable) {
            // Noodcontact notificatie faalde
        }
    }

    /**
     * Notificeer platform admin over een veiligheidsincident.
     */
    private function notifyAdmin(string $type, array $data): void
    {
        try {
            // Platform admin e-mail (uit config of env)
            $adminEmail = config('gymies.admin_email', env('GYMIES_ADMIN_EMAIL', 'safety@gymies.nl'));

            if ($adminEmail) {
                $subject = match ($type) {
                    'sos_alert' => 'SOS ALERT: Noodmelding van gebruiker',
                    'identity_fraud' => 'FRAUDE MELDING: Identiteitsfraude gerapporteerd',
                    'safe_session_overdue' => 'ALERT: Safe session overschreden',
                    default => "ALERT: {$type}",
                };

                \Illuminate\Support\Facades\Mail::raw(
                    "Type: {$type}\n\n" . json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE),
                    function ($message) use ($adminEmail, $subject) {
                        $message->to($adminEmail);
                        $message->subject("[Gymies Safety] {$subject}");
                    }
                );
            }

            // In-app notificatie voor admins
            $notificationsTable = $this->resolveTable(['notifications']);
            if ($notificationsTable) {
                // Stuur naar alle admin users
                $usersTable = $this->resolveTable(['gymies_users', 'users']);
                if ($usersTable && Schema::hasColumn($usersTable, 'role')) {
                    $admins = DB::table($usersTable)
                        ->whereIn('role', ['admin', 'super_admin', 'platform_admin'])
                        ->limit(10)
                        ->get();

                    $notifiableType = $usersTable === 'gymies_users'
                        ? 'App\Models\GymiesUser'
                        : 'App\Models\User';

                    foreach ($admins as $admin) {
                        DB::table($notificationsTable)->insert([
                            'id' => Str::uuid()->toString(),
                            'type' => 'App\Notifications\GymiesSafetyAlert',
                            'notifiable_type' => $notifiableType,
                            'notifiable_id' => (int) $admin->id,
                            'data' => json_encode(array_merge($data, ['alert_type' => $type])),
                            'created_at' => now(),
                            'updated_at' => now(),
                        ]);
                    }
                }
            }
        } catch (\Throwable) {
            // Admin notificatie mag nooit de hoofdflow breken
        }
    }

    /**
     * Bij SOS: notificeer de andere partij (als klant SOS stuurt → notificeer trainer, en vice versa).
     */
    private function notifyOtherParty(object $user, string $bookingId, array $alertData): void
    {
        try {
            $bookingsTable = $this->resolveTable(['gymies_bookings', 'bookings']);
            if (!$bookingsTable) return;

            $booking = DB::table($bookingsTable)->where('id', $bookingId)->first();
            if (!$booking) return;

            $trainerCol = $this->resolveColumn($bookingsTable, ['trainer_user_id', 'trainer_id']);
            $clientCol = $this->resolveColumn($bookingsTable, ['client_user_id', 'client_id', 'user_id']);
            if (!$trainerCol || !$clientCol) return;

            $trainerId = $booking->{$trainerCol} ?? null;
            $clientId = $booking->{$clientCol} ?? null;

            // Wie is de andere partij?
            $otherPartyId = ((int) $user->id === (int) $trainerId) ? $clientId : $trainerId;
            if (!$otherPartyId) return;

            $notificationsTable = $this->resolveTable(['notifications']);
            if (!$notificationsTable) return;

            $usersTable = $this->resolveTable(['gymies_users', 'users']);
            $notifiableType = ($usersTable === 'gymies_users')
                ? 'App\Models\GymiesUser'
                : 'App\Models\User';

            DB::table($notificationsTable)->insert([
                'id' => Str::uuid()->toString(),
                'type' => 'App\Notifications\GymiesSafetyAlert',
                'notifiable_type' => $notifiableType,
                'notifiable_id' => (int) $otherPartyId,
                'data' => json_encode([
                    'notification_type' => 'sos_alert',
                    'title' => 'Noodmelding ontvangen',
                    'body' => 'Er is een noodmelding verstuurd voor jullie sessie. Neem contact op.',
                    'booking_id' => $bookingId,
                ]),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // FCM push
            if (class_exists(FcmPushHelper::class)) {
                FcmPushHelper::sendToUser(
                    (int) $otherPartyId,
                    'Noodmelding ontvangen',
                    'Er is een noodmelding verstuurd voor jullie sessie.',
                    ['type' => 'sos_alert', 'booking_id' => $bookingId]
                );
            }
        } catch (\Throwable) {
            // Mag niet breken
        }
    }

    // ──────────────────────────────────────────────────────────────
    // Database resolve helpers (zelfde patroon als andere controllers)
    // ──────────────────────────────────────────────────────────────

    private function resolveTable(array $candidates): ?string
    {
        foreach ($candidates as $t) {
            if (Schema::hasTable($t)) {
                return $t;
            }
        }
        return null;
    }

    private function resolveColumn(string $table, array $candidates): ?string
    {
        foreach ($candidates as $c) {
            if (Schema::hasColumn($table, $c)) {
                return $c;
            }
        }
        return null;
    }
}
