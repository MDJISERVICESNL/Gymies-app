<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * QR Check-in systeem: "Digitale Handdruk" – ontgrendelt de uitbetaling aan de trainer.
 *
 * - QR-token vernieuwt elke 2 minuten (120s TTL; bij elke fetch na 2 min nieuw token).
 * - 6-cijferige backup-code als vangnet (GPS/camera problemen).
 * - GPS 50m radius check bij scan.
 * - Handmatige code-invoer krijgt een audit-vlag.
 */
final class GymiesCheckinController extends Controller
{
    /** Token maximaal 2 minuten geldig; daarna verplicht nieuw (screenshot-fraude). */
    private const QR_TOKEN_TTL_SECONDS = 120;
    private const QR_VISIBLE_BEFORE_MINUTES = 15;
    private const GPS_RADIUS_METERS = 50;

    /**
     * Klant: haal QR-code + backup-code op voor een boeking.
     * Alleen beschikbaar 15 min voor aanvang. Retourneert token + backup_code + TTL.
     */
    public function getCheckinQr(Request $request, string $bookingId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasColumn('gymies_bookings', 'checkin_token')) {
            GymiesSchemaEnsure::bookingsCheckinColumns();
        }
        if (!Schema::hasColumn('gymies_bookings', 'checkin_token')) {
            return response()->json(['message' => 'Check-in systeem niet beschikbaar. Draai alter_gymies_master_spec_additions.sql.'], 503);
        }

        $booking = DB::table('gymies_bookings')->where('id', (int) $bookingId)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if ((int) $booking->client_user_id !== (int) $user->id) {
            return response()->json(['message' => 'Dit is niet jouw boeking.'], 403);
        }
        if (!in_array($booking->status, ['confirmed'], true)) {
            return response()->json(['message' => 'Check-in is alleen beschikbaar voor bevestigde boekingen.'], 422);
        }
        if ($booking->check_in_at !== null) {
            return response()->json(['message' => 'Je bent al ingecheckt.'], 422);
        }

        $scheduledAt = Carbon::parse($booking->scheduled_at);
        $visibleFrom = $scheduledAt->copy()->subMinutes(self::QR_VISIBLE_BEFORE_MINUTES);

        if (now()->lt($visibleFrom)) {
            $minutesUntil = (int) ceil(now()->diffInSeconds($visibleFrom) / 60);
            return response()->json([
                'message' => "QR-code wordt {$minutesUntil} minuten voor aanvang zichtbaar.",
                'visible_from' => $visibleFrom->toIso8601String(),
                'qr_available' => false,
            ]);
        }

        // Altijd een vers token uitgeven bij elke fetch binnen het venster: screenshot ouder dan
        // de volgende poll (max. 2 min als client elke 120s ververst) is ongeldig.
        // Backup-code blijft stabiel tot succesvolle check-in (vangnet bij camera/GPS).
        $newToken = Str::random(48);
        $expiresAt = now()->addSeconds(self::QR_TOKEN_TTL_SECONDS);
        // S-004: 6-cijferige code (1M combinaties) is in seconden te bruteforcen.
        // Fix: gebruik 8 hexadecimale random bytes (2^64 ruimte) als backup-code.
        $backupCode = $booking->checkin_backup_code ?? strtoupper(bin2hex(random_bytes(8)));

        DB::table('gymies_bookings')->where('id', $booking->id)->update([
            'checkin_token' => $newToken,
            'checkin_token_expires_at' => $expiresAt,
            'checkin_backup_code' => $backupCode,
        ]);

        return response()->json([
            'qr_available' => true,
            'checkin_token' => $newToken,
            'backup_code' => $backupCode,
            'token_expires_at' => $expiresAt->toIso8601String(),
            'token_ttl_seconds' => self::QR_TOKEN_TTL_SECONDS,
            'booking_id' => (int) $booking->id,
            'scheduled_at' => $booking->scheduled_at,
        ]);
    }

    /**
     * Trainer: scan QR-code (token) om klant in te checken.
     * Verplicht: GPS-coördinaten van de trainer. Systeem checkt 50m radius.
     */
    public function scanCheckin(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen inchecken.'], 403);
        }

        $request->validate([
            'checkin_token' => 'required|string|size:48',
            'trainer_lat' => 'required|numeric|between:-90,90',
            'trainer_lng' => 'required|numeric|between:-180,180',
        ]);

        if (!Schema::hasColumn('gymies_bookings', 'checkin_token')) {
            GymiesSchemaEnsure::bookingsCheckinColumns();
        }
        if (!Schema::hasColumn('gymies_bookings', 'checkin_token')) {
            return response()->json(['message' => 'Check-in systeem niet beschikbaar. Draai alter_gymies_master_spec_additions.sql.'], 503);
        }

        $token = (string) $request->input('checkin_token');
        $trainerLat = (float) $request->input('trainer_lat');
        $trainerLng = (float) $request->input('trainer_lng');

        // B35: lockForUpdate voorkomt race condition waarbij twee gelijktijdige scan-verzoeken
        // beide de whereNull('check_in_at') check doorstaan en dubbel inchecken.
        DB::beginTransaction();
        try {
            $booking = DB::table('gymies_bookings')
                ->where('checkin_token', $token)
                ->where('status', 'confirmed')
                ->whereNull('check_in_at')
                ->lockForUpdate()
                ->first();

            if (!$booking) {
                DB::rollBack();
                return response()->json(['message' => 'Ongeldige of verlopen QR-code. Vraag de klant om de code te vernieuwen.'], 404);
            }

            if ((int) $booking->trainer_user_id !== (int) $user->id) {
                DB::rollBack();
                return response()->json(['message' => 'Dit is niet jouw boeking.'], 403);
            }

            if ($booking->checkin_token_expires_at !== null && Carbon::parse($booking->checkin_token_expires_at)->isPast()) {
                DB::rollBack();
                return response()->json(['message' => 'QR-code is verlopen. Vraag de klant om een nieuwe te genereren.'], 410);
            }
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        // GPS radius check (buiten transactie — geen DB-schrijfoperaties)
        $distanceMeters = $this->calculateGpsDistance($booking, $trainerLat, $trainerLng);

        $update = [
            'check_in_at' => now(),
            'check_in_method' => 'qr_scan',
            'check_in_lat' => $trainerLat,
            'check_in_lng' => $trainerLng,
            'check_in_distance_meters' => $distanceMeters,
            'check_in_audit_flag' => ($distanceMeters !== null && $distanceMeters > self::GPS_RADIUS_METERS) ? 1 : 0,
            'checkin_token' => null,
            'checkin_token_expires_at' => null,
        ];

        DB::table('gymies_bookings')->where('id', $booking->id)->update($update);
        DB::commit();

        $warning = null;
        if ($distanceMeters !== null && $distanceMeters > self::GPS_RADIUS_METERS) {
            $warning = "Check-in gelukt, maar je bent {$distanceMeters}m van de locatie (max " . self::GPS_RADIUS_METERS . "m). Dit is gemarkeerd voor review.";
        }

        return response()->json([
            'ok' => true,
            'message' => 'Check-in geslaagd!',
            'booking_id' => (int) $booking->id,
            'check_in_at' => now()->toIso8601String(),
            'distance_meters' => $distanceMeters,
            'audit_flag' => $update['check_in_audit_flag'] === 1,
            'warning' => $warning,
        ]);
    }

    /**
     * Trainer: handmatige backup-code invoeren (als QR/camera niet werkt).
     * Altijd audit-vlag.
     */
    public function manualCheckin(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen inchecken.'], 403);
        }

        $request->validate([
            'booking_id' => 'required|integer|min:1',
            'backup_code' => 'required|string|size:6',
            'trainer_lat' => 'nullable|numeric|between:-90,90',
            'trainer_lng' => 'nullable|numeric|between:-180,180',
        ]);

        if (!Schema::hasColumn('gymies_bookings', 'checkin_backup_code')) {
            GymiesSchemaEnsure::bookingsCheckinColumns();
        }
        if (!Schema::hasColumn('gymies_bookings', 'checkin_backup_code')) {
            return response()->json(['message' => 'Check-in systeem niet beschikbaar. Draai alter_gymies_master_spec_additions.sql.'], 503);
        }

        $bookingId = (int) $request->input('booking_id');
        $code = (string) $request->input('backup_code');

        // B36: lockForUpdate voorkomt race condition bij gelijktijdige backup-code check-ins.
        DB::beginTransaction();
        try {
            $booking = DB::table('gymies_bookings')
                ->where('id', $bookingId)
                ->where('status', 'confirmed')
                ->whereNull('check_in_at')
                ->lockForUpdate()
                ->first();

            if (!$booking) {
                DB::rollBack();
                return response()->json(['message' => 'Boeking niet gevonden of al ingecheckt.'], 404);
            }
            if ((int) $booking->trainer_user_id !== (int) $user->id) {
                DB::rollBack();
                return response()->json(['message' => 'Dit is niet jouw boeking.'], 403);
            }
            // S-004/S-051: Gebruik hash_equals voor constante-tijd vergelijking (timing attack preventie).
            if ($booking->checkin_backup_code === null || !hash_equals((string) $booking->checkin_backup_code, $code)) {
                DB::rollBack();
                return response()->json(['message' => 'Ongeldige backup-code.'], 422);
            }
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        $trainerLat = $request->input('trainer_lat') !== null ? (float) $request->input('trainer_lat') : null;
        $trainerLng = $request->input('trainer_lng') !== null ? (float) $request->input('trainer_lng') : null;
        $distanceMeters = ($trainerLat !== null && $trainerLng !== null)
            ? $this->calculateGpsDistance($booking, $trainerLat, $trainerLng)
            : null;

        DB::table('gymies_bookings')->where('id', $booking->id)->update([
            'check_in_at' => now(),
            'check_in_method' => 'manual_code',
            'check_in_lat' => $trainerLat,
            'check_in_lng' => $trainerLng,
            'check_in_distance_meters' => $distanceMeters,
            'check_in_audit_flag' => 1,
            'checkin_token' => null,
            'checkin_token_expires_at' => null,
            'checkin_backup_code' => null,
        ]);

        DB::commit();
        return response()->json([
            'ok' => true,
            'message' => 'Handmatige check-in geslaagd. Gemarkeerd voor admin review.',
            'booking_id' => (int) $booking->id,
            'check_in_at' => now()->toIso8601String(),
            'audit_flag' => true,
        ]);
    }

    /**
     * Haversine: afstand in meters tussen trainer en gym/locatie van de boeking.
     */
    private function calculateGpsDistance(object $booking, float $trainerLat, float $trainerLng): ?int
    {
        $gymLat = null;
        $gymLng = null;

        // Try organisation location first
        if (isset($booking->organisation_id) && $booking->organisation_id && Schema::hasTable('gymies_organisations')) {
            $org = DB::table('gymies_organisations')
                ->where('id', (int) $booking->organisation_id)
                ->first(['latitude', 'longitude']);
            if ($org && $org->latitude && $org->longitude) {
                $gymLat = (float) $org->latitude;
                $gymLng = (float) $org->longitude;
            }
        }

        // Fallback: trainer location
        if ($gymLat === null && Schema::hasTable('gymies_trainer_locations')) {
            $loc = DB::table('gymies_trainer_locations')
                ->where('trainer_user_id', (int) $booking->trainer_user_id)
                ->first(['latitude', 'longitude']);
            if ($loc && $loc->latitude && $loc->longitude) {
                $gymLat = (float) $loc->latitude;
                $gymLng = (float) $loc->longitude;
            }
        }

        if ($gymLat === null || $gymLng === null) {
            return null;
        }

        $earthRadius = 6371000;
        $dLat = deg2rad($trainerLat - $gymLat);
        $dLng = deg2rad($trainerLng - $gymLng);
        $a = sin($dLat / 2) ** 2 + cos(deg2rad($gymLat)) * cos(deg2rad($trainerLat)) * sin($dLng / 2) ** 2;
        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));

        return (int) round($earthRadius * $c);
    }

    /**
     * Trainer: rapporteer identiteitsfraude ("er staat een man voor me maar de boeking is op naam van een vrouw").
     * Sessie wordt geannuleerd, trainer krijgt 100%, klant 0%, account wordt gesuspend.
     */
    public function reportIdentityFraud(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen fraude rapporteren.'], 403);
        }

        $request->validate([
            'booking_id' => 'required|integer|min:1',
            'reason' => 'required|string|max:500',
            'evidence_url' => 'nullable|string|max:1000',
        ]);

        $bookingId = (int) $request->input('booking_id');
        $booking = DB::table('gymies_bookings')->where('id', $bookingId)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if ((int) $booking->trainer_user_id !== (int) $user->id) {
            return response()->json(['message' => 'Dit is niet jouw boeking.'], 403);
        }
        if (!in_array($booking->status, ['confirmed', 'reserved'], true)) {
            return response()->json(['message' => 'Boeking kan niet meer worden gemeld.'], 422);
        }

        $clientUserId = (int) $booking->client_user_id;

        DB::beginTransaction();
        try {
            // Cancel booking; trainer keeps the money (no refund)
            DB::table('gymies_bookings')->where('id', $bookingId)->update([
                'status' => 'cancelled',
                'cancelled_at' => now(),
                'cancelled_by_user_id' => (int) $user->id,
                'updated_at' => now(),
            ]);

            // S-003: Directe account-suspensie door trainer zonder admin-goedkeuring is een
            // authorization-bypass: elke trainer kon willekeurige klanten blokkeren.
            // Fix: zet account op "pending_review" (zichtbaar voor admin, klant behoudt toegang)
            // totdat een admin de suspensie bevestigt of afwijst.
            if (Schema::hasColumn('gymies_users', 'is_suspended') && Schema::hasColumn('gymies_users', 'suspended_reason')) {
                DB::table('gymies_users')->where('id', $clientUserId)->update([
                    'suspended_reason' => 'Identiteitsfraude gemeld door trainer (wacht op admin-review). Booking #' . $bookingId,
                    'suspended_at' => now(),
                    // is_suspended blijft 0 — admin moet dit handmatig bevestigen
                ]);
            }

            // Log the fraud report
            if (Schema::hasTable('gymies_identity_fraud_reports')) {
                DB::table('gymies_identity_fraud_reports')->insert([
                    'booking_id' => $bookingId,
                    'reporter_user_id' => (int) $user->id,
                    'reported_user_id' => $clientUserId,
                    'reason' => (string) $request->input('reason'),
                    'evidence_url' => $request->input('evidence_url'),
                    'status' => 'pending',
                    'created_at' => now(),
                ]);
            }

            // Admin notification
            if (Schema::hasTable('gymies_notification_queue')) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => $clientUserId,
                    'channel' => 'in_app',
                    'event_type' => 'identity_fraud_reported',
                    'payload_json' => json_encode([
                        'booking_id' => (string) $bookingId,
                        'reporter_id' => (string) $user->id,
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => now(),
                    'created_at' => now(),
                ]);
            }

            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        return response()->json([
            'ok' => true,
            'message' => 'Identiteitsfraude gemeld. Sessie geannuleerd. Trainer ontvangt 100%. Account klant is geblokkeerd voor onderzoek.',
            'booking_id' => $bookingId,
            'client_suspended' => true,
        ]);
    }

    /**
     * Trainer: SOS-noodknop. Stuurt GPS-locatie direct naar Admin/Control Tower.
     */
    public function sosAlert(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $request->validate([
            'latitude' => 'required|numeric|between:-90,90',
            'longitude' => 'required|numeric|between:-180,180',
            'booking_id' => 'nullable|integer|min:1',
        ]);

        if (!Schema::hasTable('gymies_sos_alerts')) {
            GymiesSchemaEnsure::sosAlertsTable();
        }
        if (!Schema::hasTable('gymies_sos_alerts')) {
            return response()->json(['message' => 'SOS-systeem niet beschikbaar. Draai alter_gymies_womens_safety.sql.'], 503);
        }

        $alertId = DB::table('gymies_sos_alerts')->insertGetId([
            'user_id' => (int) $user->id,
            'booking_id' => $request->input('booking_id') ? (int) $request->input('booking_id') : null,
            'latitude' => (float) $request->input('latitude'),
            'longitude' => (float) $request->input('longitude'),
            'status' => 'active',
            'created_at' => now(),
        ]);

        // Notify all admins
        if (Schema::hasTable('gymies_notification_queue')) {
            $admins = DB::table('gymies_users')
                ->where('is_admin', 1)
                ->pluck('id');
            foreach ($admins as $adminId) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $adminId,
                    'channel' => 'in_app',
                    'event_type' => 'sos_alert_triggered',
                    'payload_json' => json_encode([
                        'alert_id' => $alertId,
                        'user_id' => (string) $user->id,
                        'user_name' => $user->display_name ?? $user->email,
                        'latitude' => (float) $request->input('latitude'),
                        'longitude' => (float) $request->input('longitude'),
                        'booking_id' => $request->input('booking_id'),
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => now(),
                    'created_at' => now(),
                ]);
            }
        }

        return response()->json([
            'ok' => true,
            'alert_id' => $alertId,
            'message' => 'SOS-melding verzonden. Help is onderweg.',
        ]);
    }

    /**
     * Trainer: start Safe-Session (timer loopt; auto-melding als niet uitcheckt na sessie).
     */
    public function startSafeSession(Request $request, string $bookingId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen Safe-Session starten.'], 403);
        }

        $booking = DB::table('gymies_bookings')->where('id', (int) $bookingId)->first();
        if (!$booking || (int) $booking->trainer_user_id !== (int) $user->id) {
            return response()->json(['message' => 'Boeking niet gevonden of niet van jou.'], 404);
        }

        if (!Schema::hasColumn('gymies_bookings', 'safe_session_active')) {
            GymiesSchemaEnsure::bookingsSafeSessionColumns();
        }
        if (!Schema::hasColumn('gymies_bookings', 'safe_session_active')) {
            return response()->json(['message' => 'Safe-Session niet beschikbaar. Draai alter_gymies_womens_safety.sql.'], 503);
        }

        DB::table('gymies_bookings')->where('id', (int) $bookingId)->update([
            'safe_session_active' => 1,
            'safe_session_started_at' => now(),
        ]);

        return response()->json([
            'ok' => true,
            'message' => 'Safe-Session gestart. Je locatie wordt bewaakt tot je uitcheckt.',
        ]);
    }

    /**
     * Trainer: checkout na sessie (stopt Safe-Session timer).
     */
    public function checkOut(Request $request, string $bookingId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen uitchecken.'], 403);
        }

        $booking = DB::table('gymies_bookings')->where('id', (int) $bookingId)->first();
        if (!$booking || (int) $booking->trainer_user_id !== (int) $user->id) {
            return response()->json(['message' => 'Boeking niet gevonden of niet van jou.'], 404);
        }

        $update = ['updated_at' => now()];
        if (Schema::hasColumn('gymies_bookings', 'check_out_at')) {
            $update['check_out_at'] = now();
        }
        if (Schema::hasColumn('gymies_bookings', 'safe_session_active')) {
            $update['safe_session_active'] = 0;
        }

        DB::table('gymies_bookings')->where('id', (int) $bookingId)->update($update);

        return response()->json([
            'ok' => true,
            'message' => 'Uitcheckt! Safe-Session gestopt.',
        ]);
    }
}
