<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Services\RecurringBookingService;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies API: Recurring (Wekelijkse) Bookings.
 *
 * Manages recurring session bookings that generate concrete bookings via RecurringBookingService.
 * Tabel: gymies_recurring_bookings
 *
 * Endpoints:
 * GET    recurring-bookings        → index()  — list user's recurring bookings
 * POST   recurring-bookings        → store()  — create new recurring booking
 * PUT    recurring-bookings/{id}/pause → pause()  — pause a recurring booking
 * PUT    recurring-bookings/{id}/resume → resume() — resume a paused recurring booking
 * DELETE recurring-bookings/{id}   → cancel() — cancel (soft delete)
 */
class GymiesRecurringBookingController
{
    private const TABLE = 'gymies_recurring_bookings';
    private const ALLOWED_DURATIONS = [45, 60, 90, 120];
    private const VALID_DAY_OF_WEEK_MIN = 1;
    private const VALID_DAY_OF_WEEK_MAX = 7;

    private RecurringBookingService $recurringBookingService;

    public function __construct(RecurringBookingService $recurringBookingService)
    {
        $this->recurringBookingService = $recurringBookingService;
    }

    /**
     * GET recurring-bookings
     * List user's recurring bookings.
     * - Clients see their own recurring bookings
     * - Trainers see recurring bookings where they are the trainer
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Ongeautoriseerd'], 401);
        }

        if (!Schema::hasTable(self::TABLE)) {
            return response()->json(['data' => []]);
        }

        $userId = (int) $user->id;
        $isTrainer = $user->role === 'trainer';

        // Build query based on user role
        $query = DB::table(self::TABLE . ' as rb')
            ->leftJoin('gymies_users as client', 'client.id', '=', 'rb.client_user_id')
            ->leftJoin('gymies_users as trainer', 'trainer.id', '=', 'rb.trainer_user_id');

        if ($isTrainer) {
            // Trainers see recurring bookings where they are the trainer
            $query->where('rb.trainer_user_id', $userId);
        } else {
            // Clients see their own recurring bookings
            $query->where('rb.client_user_id', $userId);
        }

        $rows = $query
            ->select([
                'rb.id',
                'rb.client_user_id',
                'rb.trainer_user_id',
                'rb.day_of_week',
                'rb.start_time',
                'rb.duration_minutes',
                'rb.repeat_until',
                'rb.repeat_every_weeks',
                'rb.package_id',
                'rb.status',
                'rb.generated_until',
                'rb.amount_cents',
                'rb.created_at',
                'rb.updated_at',
                DB::raw('COALESCE(client.display_name, client.email) as client_name'),
                DB::raw('COALESCE(trainer.display_name, trainer.email) as trainer_name'),
            ])
            ->orderByDesc('rb.created_at')
            ->get();

        $data = $rows->map(function ($row) {
            return [
                'id' => (string) $row->id,
                'client_user_id' => (string) $row->client_user_id,
                'trainer_user_id' => (string) $row->trainer_user_id,
                'day_of_week' => (int) $row->day_of_week,
                'start_time' => (string) $row->start_time,
                'duration_minutes' => (int) $row->duration_minutes,
                'repeat_until' => $row->repeat_until ? (string) $row->repeat_until : null,
                'repeat_every_weeks' => (int) ($row->repeat_every_weeks ?? 1),
                'package_id' => $row->package_id ? (string) $row->package_id : null,
                'status' => (string) $row->status,
                'generated_until' => $row->generated_until ? (string) $row->generated_until : null,
                'amount_cents' => (int) $row->amount_cents,
                'client_name' => (string) ($row->client_name ?? ''),
                'trainer_name' => (string) ($row->trainer_name ?? ''),
                'created_at' => $row->created_at,
                'updated_at' => $row->updated_at,
            ];
        })->values()->all();

        return response()->json(['data' => $data]);
    }

    /**
     * POST recurring-bookings
     * Create a new recurring booking.
     * Only clients can create recurring bookings.
     *
     * Request:
     * {
     *   "trainer_user_id": 123,
     *   "day_of_week": 2,              // 1-7 (Monday-Sunday, ISO)
     *   "start_time": "10:00",         // HH:MM
     *   "duration_minutes": 60,        // 45, 60, 90, or 120
     *   "repeat_until": "2026-12-31",  // optional
     *   "repeat_every_weeks": 1,       // optional, default 1
     *   "package_id": 5,               // optional
     *   "amount_cents": 5000           // optional, uses trainer's session price if omitted
     * }
     */
    public function store(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Ongeautoriseerd'], 401);
        }

        // Only clients can create recurring bookings
        if ($user->role === 'trainer') {
            return response()->json(['message' => 'Trainers kunnen geen wekelijkse boekingen aanmaken'], 403);
        }

        if (!Schema::hasTable(self::TABLE)) {
            return response()->json(['message' => 'Wekelijkse boekingen niet beschikbaar'], 503);
        }

        // Validate input
        $validated = $request->validate([
            'trainer_user_id' => 'required|integer|min:1',
            'day_of_week' => 'required|integer|min:1|max:7',
            'start_time' => 'required|date_format:H:i',
            'duration_minutes' => 'required|integer|in:45,60,90,120',
            'repeat_until' => 'nullable|date_format:Y-m-d|after_or_equal:today',
            'repeat_every_weeks' => 'nullable|integer|min:1|max:52',
            'package_id' => 'nullable|integer|min:1',
            'amount_cents' => 'nullable|integer|min:0',
        ]);

        $trainerId = (int) $validated['trainer_user_id'];
        $dayOfWeek = (int) $validated['day_of_week'];
        $startTime = trim($validated['start_time']);
        $durationMinutes = (int) $validated['duration_minutes'];
        $repeatUntil = $validated['repeat_until'] ?? null;
        $repeatEveryWeeks = (int) ($validated['repeat_every_weeks'] ?? 1);
        $packageId = $validated['package_id'] ? (int) $validated['package_id'] : null;
        $amountCents = (int) ($validated['amount_cents'] ?? 0);

        // Validate day_of_week is ISO (1-7)
        if ($dayOfWeek < self::VALID_DAY_OF_WEEK_MIN || $dayOfWeek > self::VALID_DAY_OF_WEEK_MAX) {
            return response()->json([
                'message' => 'Dag van de week moet tussen 1 en 7 zijn (ISO: 1=Maandag, 7=Zondag)'
            ], 422);
        }

        // Validate duration_minutes is in allowed list
        if (!in_array($durationMinutes, self::ALLOWED_DURATIONS, true)) {
            return response()->json([
                'message' => 'Duur moet 45, 60, 90 of 120 minuten zijn'
            ], 422);
        }

        // Check: trainer exists
        if (!$this->trainerExists($trainerId)) {
            return response()->json(['message' => 'Trainer niet gevonden'], 404);
        }

        // Check: no active recurring booking on same trainer+day+time
        if ($this->hasConflictingRecurring((int) $user->id, $trainerId, $dayOfWeek, $startTime)) {
            return response()->json([
                'message' => 'Je hebt al een actieve wekelijkse boeking met deze trainer op dit moment'
            ], 409);
        }

        // Determine amount_cents if not provided
        if ($amountCents === 0) {
            $amountCents = $this->getTrainerSessionPrice($trainerId);
        }

        // Create recurring booking
        try {
            $id = DB::table(self::TABLE)->insertGetId([
                'client_user_id' => (int) $user->id,
                'trainer_user_id' => $trainerId,
                'day_of_week' => $dayOfWeek,
                'start_time' => $startTime,
                'duration_minutes' => $durationMinutes,
                'repeat_until' => $repeatUntil,
                'repeat_every_weeks' => $repeatEveryWeeks,
                'package_id' => $packageId,
                'status' => 'active',
                'generated_until' => null,
                'amount_cents' => $amountCents,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        } catch (\Throwable $e) {
            return response()->json([
                'message' => 'Fout bij aanmaken wekelijkse boeking: ' . $e->getMessage(),
            ], 500);
        }

        return response()->json([
            'data' => [
                'id' => (string) $id,
                'message' => 'Wekelijkse boeking aangemaakt',
            ]
        ], 201);
    }

    /**
     * PUT recurring-bookings/{id}/pause
     * Pause a recurring booking (does not cancel existing generated bookings).
     */
    public function pause(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Ongeautoriseerd'], 401);
        }

        if (!Schema::hasTable(self::TABLE)) {
            return response()->json(['message' => 'Wekelijkse boekingen niet beschikbaar'], 503);
        }

        $recurringId = (int) $id;
        $userId = (int) $user->id;

        // Fetch the recurring booking
        $recurring = DB::table(self::TABLE)
            ->where('id', $recurringId)
            ->first();

        if (!$recurring) {
            return response()->json(['message' => 'Wekelijkse boeking niet gevonden'], 404);
        }

        // Check authorization: clients own their bookings, trainers see bookings where they are trainer
        if ($user->role === 'trainer') {
            if ((int) $recurring->trainer_user_id !== $userId) {
                return response()->json(['message' => 'Niet geautoriseerd'], 403);
            }
        } else {
            if ((int) $recurring->client_user_id !== $userId) {
                return response()->json(['message' => 'Niet geautoriseerd'], 403);
            }
        }

        // Update status to 'paused'
        DB::table(self::TABLE)
            ->where('id', $recurringId)
            ->update([
                'status' => 'paused',
                'updated_at' => now(),
            ]);

        return response()->json(['message' => 'Wekelijkse boeking onderbroken']);
    }

    /**
     * PUT recurring-bookings/{id}/resume
     * Resume a paused recurring booking.
     */
    public function resume(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Ongeautoriseerd'], 401);
        }

        if (!Schema::hasTable(self::TABLE)) {
            return response()->json(['message' => 'Wekelijkse boekingen niet beschikbaar'], 503);
        }

        $recurringId = (int) $id;
        $userId = (int) $user->id;

        // Fetch the recurring booking
        $recurring = DB::table(self::TABLE)
            ->where('id', $recurringId)
            ->first();

        if (!$recurring) {
            return response()->json(['message' => 'Wekelijkse boeking niet gevonden'], 404);
        }

        // Check authorization
        if ($user->role === 'trainer') {
            if ((int) $recurring->trainer_user_id !== $userId) {
                return response()->json(['message' => 'Niet geautoriseerd'], 403);
            }
        } else {
            if ((int) $recurring->client_user_id !== $userId) {
                return response()->json(['message' => 'Niet geautoriseerd'], 403);
            }
        }

        // Can only resume if currently paused
        if ($recurring->status !== 'paused') {
            return response()->json([
                'message' => 'Deze boeking kan niet worden hervat (status: ' . $recurring->status . ')'
            ], 409);
        }

        // Update status back to 'active'
        DB::table(self::TABLE)
            ->where('id', $recurringId)
            ->update([
                'status' => 'active',
                'updated_at' => now(),
            ]);

        return response()->json(['message' => 'Wekelijkse boeking hervat']);
    }

    /**
     * DELETE recurring-bookings/{id}
     * Cancel a recurring booking (soft delete: set status = 'cancelled').
     */
    public function cancel(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Ongeautoriseerd'], 401);
        }

        if (!Schema::hasTable(self::TABLE)) {
            return response()->json(['message' => 'Wekelijkse boekingen niet beschikbaar'], 503);
        }

        $recurringId = (int) $id;
        $userId = (int) $user->id;

        // Fetch the recurring booking
        $recurring = DB::table(self::TABLE)
            ->where('id', $recurringId)
            ->first();

        if (!$recurring) {
            return response()->json(['message' => 'Wekelijkse boeking niet gevonden'], 404);
        }

        // Check authorization
        if ($user->role === 'trainer') {
            if ((int) $recurring->trainer_user_id !== $userId) {
                return response()->json(['message' => 'Niet geautoriseerd'], 403);
            }
        } else {
            if ((int) $recurring->client_user_id !== $userId) {
                return response()->json(['message' => 'Niet geautoriseerd'], 403);
            }
        }

        // Soft delete: set status to 'cancelled'
        DB::table(self::TABLE)
            ->where('id', $recurringId)
            ->update([
                'status' => 'cancelled',
                'updated_at' => now(),
            ]);

        return response()->json(['message' => 'Wekelijkse boeking geannuleerd']);
    }

    /**
     * Check if a trainer exists in gymies_users.
     */
    private function trainerExists(int $trainerId): bool
    {
        if (!Schema::hasTable('gymies_users')) {
            return true; // Assume exists if table unavailable
        }

        return DB::table('gymies_users')
            ->where('id', $trainerId)
            ->where('role', 'trainer')
            ->exists();
    }

    /**
     * Check for conflicting active recurring bookings.
     * Returns true if there's already an active recurring booking for the same
     * client+trainer+day_of_week+start_time.
     */
    private function hasConflictingRecurring(
        int $clientId,
        int $trainerId,
        int $dayOfWeek,
        string $startTime
    ): bool {
        return DB::table(self::TABLE)
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->where('day_of_week', $dayOfWeek)
            ->where('start_time', $startTime)
            ->where('status', 'active')
            ->exists();
    }

    /**
     * Get trainer's session price from gymies_trainer_profiles.
     * Defaults to 0 if not found.
     */
    private function getTrainerSessionPrice(int $trainerId): int
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return 0;
        }

        if (!Schema::hasColumn('gymies_trainer_profiles', 'session_price_cents')) {
            return 0;
        }

        $profile = DB::table('gymies_trainer_profiles')
            ->where('user_id', $trainerId)
            ->first(['session_price_cents']);

        return $profile ? (int) ($profile->session_price_cents ?? 0) : 0;
    }
}
