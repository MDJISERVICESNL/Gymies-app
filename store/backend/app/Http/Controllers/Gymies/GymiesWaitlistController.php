<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Services\WaitlistService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Wachtlijst / standby: klant ziet waar hij op de wachtlijst staat per trainer.
 *
 * Routes:
 * GET waitlist/me → me()
 * POST waitlist → store()
 * DELETE waitlist/{id} → destroy()
 * POST waitlist/{id}/claim → claim() [V2 only]
 *
 * Backward Compatibility:
 * - Detects whether the new V2 schema is in use (has desired_date, desired_time, position, status columns)
 * - If new columns missing, uses legacy columns (requested_for_scheduled_at, preferred_date_from, etc.)
 * - store() and destroy() work transparently with both schemas
 * - me() returns standardized response regardless of schema version
 */
class GymiesWaitlistController
{
    private WaitlistService $waitlistService;

    public function __construct(WaitlistService $waitlistService)
    {
        $this->waitlistService = $waitlistService;
    }

    /**
     * Detect which schema version is in use.
     * Returns 'v2' if new columns exist, 'legacy' otherwise.
     */
    private function getSchemaVersion(): string
    {
        if (!Schema::hasTable('gymies_waitlist')) {
            return 'none';
        }

        // Check for V2-specific columns
        if (Schema::hasColumn('gymies_waitlist', 'desired_date') &&
            Schema::hasColumn('gymies_waitlist', 'position') &&
            Schema::hasColumn('gymies_waitlist', 'status')) {
            return 'v2';
        }

        return 'legacy';
    }

    /**
     * GET waitlist/me – Get my waitlist entries.
     * Works with both V2 and legacy schemas.
     */
    public function me(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $schemaVersion = $this->getSchemaVersion();
        if ($schemaVersion === 'none') {
            return response()->json(['data' => []]);
        }

        if ($schemaVersion === 'v2') {
            return $this->me_v2($request, $user);
        }

        return $this->me_legacy($request, $user);
    }

    /**
     * GET waitlist/me – V2 Schema Implementation
     */
    private function me_v2(Request $request, object $user): JsonResponse
    {
        $rows = DB::table('gymies_waitlist as w')
            ->leftJoin('gymies_users as t', 't.id', '=', 'w.trainer_user_id')
            ->where('w.client_user_id', (int) $user->id)
            ->orderByDesc('w.created_at')
            ->get([
                'w.id',
                'w.trainer_user_id',
                'w.desired_date',
                'w.desired_time',
                'w.desired_duration_minutes',
                'w.position',
                'w.status',
                'w.offered_at',
                'w.expires_at',
                'w.claimed_booking_id',
                'w.created_at',
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
            ]);

        $data = $rows->map(function ($row) {
            $scheduledAt = "{$row->desired_date} {$row->desired_time}:00";

            return [
                'id' => (string) $row->id,
                'waitlist_id' => (string) $row->id,
                'trainer_user_id' => (string) ($row->trainer_user_id ?? ''),
                'trainer_name' => (string) ($row->trainer_name ?? 'Trainer'),
                'trainerName' => (string) ($row->trainer_name ?? 'Trainer'),
                'desired_date' => (string) ($row->desired_date ?? ''),
                'desired_time' => (string) ($row->desired_time ?? ''),
                'desired_duration_minutes' => (int) ($row->desired_duration_minutes ?? 60),
                'position' => (int) ($row->position ?? 0),
                'status' => (string) ($row->status ?? 'waiting'),
                'offered_at' => $row->offered_at,
                'expires_at' => $row->expires_at,
                'claimed_booking_id' => $row->claimed_booking_id,
                'scheduled_at' => $scheduledAt,
                'preferred_at' => $scheduledAt, // backward compat
                'preferredAt' => $scheduledAt, // backward compat
                'created_at' => $row->created_at,
            ];
        })->values()->all();

        return response()->json(['data' => $data]);
    }

    /**
     * GET waitlist/me – Legacy Schema Implementation
     */
    private function me_legacy(Request $request, object $user): JsonResponse
    {
        $rows = DB::table('gymies_waitlist as w')
            ->leftJoin('gymies_users as t', 't.id', '=', 'w.trainer_user_id')
            ->where('w.client_user_id', (int) $user->id)
            ->orderByDesc('w.created_at')
            ->get([
                'w.id',
                'w.trainer_user_id',
                'w.requested_for_scheduled_at',
                'w.availability_slot_id',
                'w.preferred_date_from',
                'w.preferred_date_to',
                'w.notes',
                'w.created_at',
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
            ]);

        $data = $rows->map(function ($row) {
            $preferredAt = $row->requested_for_scheduled_at
                ?? $row->preferred_date_from
                ?? $row->created_at;
            return [
                'id' => (string) $row->id,
                'waitlist_id' => (string) $row->id,
                'trainer_user_id' => (string) ($row->trainer_user_id ?? ''),
                'trainer_name' => (string) ($row->trainer_name ?? 'Trainer'),
                'trainerName' => (string) ($row->trainer_name ?? 'Trainer'),
                'preferred_at' => $preferredAt,
                'preferredAt' => $preferredAt,
                'requested_for_scheduled_at' => $row->requested_for_scheduled_at,
                'availability_slot_id' => $row->availability_slot_id,
                'note' => (string) ($row->notes ?? ''),
                'notes' => (string) ($row->notes ?? ''),
                'created_at' => $row->created_at,
            ];
        })->values()->all();

        return response()->json(['data' => $data]);
    }

    /**
     * POST waitlist – Create a new waitlist entry.
     * Works with both V2 and legacy schemas.
     *
     * V2 Request:
     * {
     *   "trainer_user_id": 123,
     *   "desired_date": "2026-05-01",
     *   "desired_time": "10:00",
     *   "desired_duration_minutes": 60
     * }
     *
     * Legacy Request (still supported):
     * {
     *   "trainer_user_id": 123,
     *   "preferred_at": "2026-05-01"
     * }
     */
    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $schemaVersion = $this->getSchemaVersion();
        if ($schemaVersion === 'none') {
            return response()->json(['message' => 'Wachtlijst niet beschikbaar.'], 503);
        }

        $request->validate([
            'trainer_user_id' => 'required|integer|min:1',
            'trainer_id' => 'nullable|integer|min:1',
            'desired_date' => 'nullable|date_format:Y-m-d',
            'desired_time' => 'nullable|date_format:H:i',
            'desired_duration_minutes' => 'nullable|integer|min:15|max:480',
            'preferred_at' => 'nullable|date', // legacy
            'note' => 'nullable|string|max:500', // legacy
        ]);

        $trainerId = (int) ($request->input('trainer_user_id') ?? $request->input('trainer_id') ?? 0);
        if ($trainerId < 1) {
            return response()->json(['message' => 'Trainer-ID ontbreekt.'], 422);
        }

        if ($schemaVersion === 'v2') {
            return $this->store_v2($request, $user, $trainerId);
        }

        return $this->store_legacy($request, $user, $trainerId);
    }

    /**
     * POST waitlist – V2 Schema Implementation
     */
    private function store_v2(Request $request, object $user, int $trainerId): JsonResponse
    {
        $desiredDate = $request->input('desired_date');
        $desiredTime = $request->input('desired_time');
        $durationMinutes = (int) ($request->input('desired_duration_minutes') ?? 60);

        if (!$desiredDate || !$desiredTime) {
            return response()->json([
                'message' => 'desired_date en desired_time zijn vereist voor V2 wachtlijst.'
            ], 422);
        }

        $result = $this->waitlistService->joinWaitlist(
            clientUserId: (int) $user->id,
            trainerUserId: $trainerId,
            desiredDate: $desiredDate,
            desiredTime: $desiredTime,
            durationMinutes: $durationMinutes,
        );

        if (!$result['success']) {
            return response()->json([
                'message' => $result['message'],
                'position' => $result['position'],
            ], $result['position'] > 0 ? 409 : 422);
        }

        return response()->json([
            'data' => [
                'position' => $result['position'],
            ],
            'message' => $result['message'],
        ], 201);
    }

    /**
     * POST waitlist – Legacy Schema Implementation
     */
    private function store_legacy(Request $request, object $user, int $trainerId): JsonResponse
    {
        $preferredAt = $request->input('preferred_at');
        $preferredFrom = $preferredAt ? date('Y-m-d H:i:s', strtotime($preferredAt)) : null;
        $preferredTo = $preferredAt ? date('Y-m-d H:i:s', strtotime($preferredAt) + 86400) : null;

        $id = DB::table('gymies_waitlist')->insertGetId([
            'client_user_id' => (int) $user->id,
            'trainer_user_id' => $trainerId,
            'requested_for_scheduled_at' => $preferredFrom,
            'preferred_date_from' => $preferredFrom,
            'preferred_date_to' => $preferredTo,
            'notes' => trim((string) $request->input('note', '')),
            'created_at' => now(),
        ]);

        return response()->json([
            'data' => ['id' => (string) $id],
            'message' => 'Je staat op de wachtlijst.',
        ], 201);
    }

    /**
     * DELETE waitlist/{id} – Remove a waitlist entry.
     * Works with both V2 and legacy schemas.
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        if (!Schema::hasTable('gymies_waitlist')) {
            return response()->json(['message' => 'Wachtlijst niet beschikbaar.'], 503);
        }

        $deleted = DB::table('gymies_waitlist')
            ->where('id', (int) $id)
            ->where('client_user_id', (int) $user->id)
            ->delete();

        if ($deleted === 0) {
            return response()->json(['message' => 'Inschrijving niet gevonden.'], 404);
        }

        return response()->json(['message' => 'Uitgeschreven van wachtlijst.']);
    }

    /**
     * POST waitlist/{id}/claim – Claim a V2 waitlist offer.
     *
     * This endpoint is V2-only. It uses the WaitlistService to:
     * 1. Verify the offer is still valid (not expired)
     * 2. Check for slot conflicts
     * 3. Create a new booking
     * 4. Mark waitlist entry as claimed
     *
     * Request: {} (empty body)
     *
     * Response on success:
     * {
     *   "success": true,
     *   "message": "Sessie geboekt via de wachtlijst!",
     *   "booking_id": 42
     * }
     *
     * Response on error:
     * {
     *   "success": false,
     *   "message": "Aanbod is verlopen. Het slot gaat naar de volgende op de wachtlijst."
     * }
     */
    public function claim(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $schemaVersion = $this->getSchemaVersion();
        if ($schemaVersion !== 'v2') {
            return response()->json([
                'message' => 'Het waitlist claim systeem is niet beschikbaar. Upgrade naar V2.'
            ], 503);
        }

        // Verify the waitlist entry exists and belongs to the user
        $entry = DB::table('gymies_waitlist')
            ->where('id', (int) $id)
            ->where('client_user_id', (int) $user->id)
            ->first();

        if (!$entry) {
            return response()->json(['message' => 'Wachtlijst-inschrijving niet gevonden.'], 404);
        }

        if ($entry->status !== 'offered') {
            return response()->json([
                'message' => 'Dit aanbod is niet actief. Status: ' . $entry->status
            ], 409);
        }

        // Use WaitlistService to handle the claim
        $result = $this->waitlistService->claimOffer(
            waitlistId: (int) $entry->id,
            clientUserId: (int) $user->id,
        );

        if (!$result['success']) {
            return response()->json([
                'message' => $result['message'],
            ], 409);
        }

        return response()->json([
            'success' => true,
            'message' => $result['message'],
            'booking_id' => $result['booking_id'],
        ]);
    }
}
