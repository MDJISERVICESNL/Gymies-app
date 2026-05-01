<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Traits\GymiesRequireTrainerTrait;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trainer beschikbaarheid: vaste slots + uitzonderingen.
 */
final class GymiesAvailabilityController extends Controller
{
    public function publicAvailability(Request $request, string $id): JsonResponse
    {
        $trainer = DB::table('gymies_users')
            ->where('id', $id)
            ->where('role', 'trainer')
            ->first();
        if (!$trainer) {
            return response()->json(['message' => 'Trainer niet gevonden.'], 404);
        }

        $slots = DB::table('gymies_availability_slots')
            ->where('trainer_user_id', $id)
            ->orderBy('day_of_week')
            ->orderBy('start_time')
            ->get()
            ->map(fn ($r) => [
                'id' => (string) $r->id,
                'weekday' => (int) $r->day_of_week,
                'day_of_week' => (int) $r->day_of_week,
                'start_time' => $r->start_time,
                'end_time' => $r->end_time,
                'timezone' => (string) config('app.timezone', 'UTC'),
            ])->all();

        $exceptions = DB::table('gymies_availability_exceptions')
            ->where('trainer_user_id', $id)
            ->orderBy('exception_date')
            ->orderByDesc('id')
            ->get()
            ->map(fn ($r) => [
                'id' => (string) $r->id,
                'exception_date' => $r->exception_date,
                'is_available' => (bool) $r->is_available,
                'start_time' => $r->start_time,
                'end_time' => $r->end_time,
            ])->all();

        // Deterministische prioriteit: per datum geldt de laatst aangemaakte uitzondering.
        $effectiveExceptions = collect($exceptions)
            ->unique('exception_date')
            ->sortBy('exception_date')
            ->values()
            ->all();

        $leadTimeMinutes = 240;
        $bookingMaxDaysAhead = null;
        if (\Illuminate\Support\Facades\Schema::hasTable('gymies_trainer_profiles')) {
            if (\Illuminate\Support\Facades\Schema::hasColumn('gymies_trainer_profiles', 'lead_time_minutes')) {
                $profile = DB::table('gymies_trainer_profiles')->where('user_id', $id)->value('lead_time_minutes');
                if ($profile !== null) {
                    $leadTimeMinutes = (int) $profile;
                }
            }
            if (\Illuminate\Support\Facades\Schema::hasColumn('gymies_trainer_profiles', 'booking_max_days_ahead')) {
                $bookingMaxDaysAhead = DB::table('gymies_trainer_profiles')
                    ->where('user_id', $id)
                    ->value('booking_max_days_ahead');
                if ($bookingMaxDaysAhead !== null) {
                    $bookingMaxDaysAhead = (int) $bookingMaxDaysAhead;
                }
            }
        }

        return response()->json([
            'data' => [
                'slots' => $slots,
                'exceptions' => $exceptions,
                'effective_exceptions' => $effectiveExceptions,
                'allow_outside_window_request' => true,
                'timezone' => (string) config('app.timezone', 'UTC'),
                'exception_priority' => 'latest_created_wins',
                'lead_time_minutes' => $leadTimeMinutes,
                'booking_max_days_ahead' => $bookingMaxDaysAhead,
            ],
        ]);
    }

    /**
     * Geblokkeerde tijdslots voor een trainer (pending + confirmed boekingen).
     * Double-entry: klanten zien deze tijden niet als beschikbaar.
     * Query: from (Y-m-d), to (Y-m-d).
     */
    public function blockedSlots(Request $request, string $id): JsonResponse
    {
        $trainer = DB::table('gymies_users')
            ->where('id', $id)
            ->where('role', 'trainer')
            ->first();
        if (!$trainer) {
            return response()->json(['message' => 'Trainer niet gevonden.'], 404);
        }

        $from = $request->input('from');
        $to = $request->input('to');
        if (!$from || !$to) {
            return response()->json([
                'message' => 'Parameters from en to (Y-m-d) zijn verplicht.',
            ], 422);
        }

        try {
            $fromDate = \Carbon\Carbon::parse($from)->startOfDay();
            $toDate = \Carbon\Carbon::parse($to)->endOfDay();
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Ongeldige datum (gebruik Y-m-d).'], 422);
        }

        // N-013 FIXED: date range beperkt tot maximaal 90 dagen
        if ($fromDate->gt($toDate) || $fromDate->diffInDays($toDate) > 90) {
            return response()->json(['message' => 'Datumbereik mag maximaal 90 dagen zijn.'], 422);
        }

        if (!DB::getSchemaBuilder()->hasTable('gymies_bookings')) {
            return response()->json(['data' => ['blocked' => []]]);
        }

        $statuses = ['pending', 'confirmed', 'reserved'];
        $query = DB::table('gymies_bookings')
            ->where('trainer_user_id', $id)
            ->whereIn('status', $statuses)
            ->where('scheduled_at', '>=', $fromDate->toDateTimeString())
            ->where('scheduled_at', '<=', $toDate->toDateTimeString());
        if (DB::getSchemaBuilder()->hasColumn('gymies_bookings', 'reserved_until')) {
            $query->where(function ($q) {
                $q->whereIn('status', ['pending', 'confirmed'])
                    ->orWhere(function ($q2) {
                        $q2->where('status', 'reserved')->where(function ($q3) {
                            $q3->whereNull('reserved_until')->orWhere('reserved_until', '>', now());
                        });
                    });
            });
        }
        $rows = $query->orderBy('scheduled_at')->get(['scheduled_at', 'duration_minutes', 'status']);

        $blocked = $rows->map(fn ($r) => [
            'scheduled_at' => $r->scheduled_at,
            'duration_minutes' => (int) ($r->duration_minutes ?? 60),
            'status' => $r->status,
        ])->all();

        return response()->json(['data' => ['blocked' => $blocked]]);
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers hebben toegang.'], 403);
        }

        $slots = DB::table('gymies_availability_slots')
            ->where('trainer_user_id', $user->id)
            ->orderBy('day_of_week')
            ->orderBy('start_time')
            ->get()
            ->map(fn ($r) => [
                'id' => (string) $r->id,
                'weekday' => (int) $r->day_of_week,
                'day_of_week' => (int) $r->day_of_week,
                'start_time' => $r->start_time,
                'end_time' => $r->end_time,
                'timezone' => (string) config('app.timezone', 'UTC'),
            ])->all();

        $exceptions = DB::table('gymies_availability_exceptions')
            ->where('trainer_user_id', $user->id)
            ->orderBy('exception_date')
            ->orderBy('start_time')
            ->get()
            ->map(fn ($r) => [
                'id' => (string) $r->id,
                'exception_date' => $r->exception_date,
                'is_available' => (bool) $r->is_available,
                'start_time' => $r->start_time,
                'end_time' => $r->end_time,
            ])->all();

        return response()->json(['data' => ['slots' => $slots, 'exceptions' => $exceptions]]);
    }

    public function storeSlot(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $request->validate([
            'day_of_week' => 'required|integer|min:1|max:7',
            'start_time' => 'required|date_format:H:i',
            'end_time' => 'required|date_format:H:i|after:start_time',
        ]);

        $id = DB::table('gymies_availability_slots')->insertGetId([
            'trainer_user_id' => $user->id,
            'day_of_week' => (int) $request->input('day_of_week'),
            'start_time' => $request->input('start_time'),
            'end_time' => $request->input('end_time'),
            'created_at' => now(),
        ]);

        $this->notifyFavoritesOfNewSlots((int) $user->id);

        return response()->json(['data' => ['id' => (string) $id]], 201);
    }

    public function updateSlot(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $request->validate([
            'day_of_week' => 'required|integer|min:1|max:7',
            'start_time' => 'required|date_format:H:i',
            'end_time' => 'required|date_format:H:i|after:start_time',
        ]);

        $affected = DB::table('gymies_availability_slots')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->update([
                'day_of_week' => (int) $request->input('day_of_week'),
                'start_time' => $request->input('start_time'),
                'end_time' => $request->input('end_time'),
            ]);
        if ($affected === 0) {
            return response()->json(['message' => 'Slot niet gevonden.'], 404);
        }
        return response()->json(['message' => 'Slot bijgewerkt']);
    }

    public function deleteSlot(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $deleted = DB::table('gymies_availability_slots')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->delete();
        if ($deleted === 0) {
            return response()->json(['message' => 'Slot niet gevonden.'], 404);
        }
        return response()->json(['message' => 'Slot verwijderd']);
    }

    public function storeException(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $request->validate([
            'exception_date' => 'required|date',
            'is_available' => 'required|boolean',
            'start_time' => 'nullable|date_format:H:i',
            'end_time' => 'nullable|date_format:H:i',
        ]);

        $isAvailable = (bool) $request->boolean('is_available');
        $startTime = $request->input('start_time');
        $endTime = $request->input('end_time');
        if ($isAvailable && (!$startTime || !$endTime || $endTime <= $startTime)) {
            return response()->json(['message' => 'Bij extra beschikbaarheid zijn geldige start/eindtijd verplicht.'], 422);
        }

        $id = DB::table('gymies_availability_exceptions')->insertGetId([
            'trainer_user_id' => $user->id,
            'exception_date' => $request->input('exception_date'),
            'is_available' => $isAvailable ? 1 : 0,
            'start_time' => $isAvailable ? $startTime : null,
            'end_time' => $isAvailable ? $endTime : null,
            'created_at' => now(),
        ]);

        if ($isAvailable) {
            $this->notifyFavoritesOfNewSlots((int) $user->id);
        }

        return response()->json(['data' => ['id' => (string) $id]], 201);
    }

    public function updateException(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $request->validate([
            'exception_date' => 'required|date',
            'is_available' => 'required|boolean',
            'start_time' => 'nullable|date_format:H:i',
            'end_time' => 'nullable|date_format:H:i',
        ]);

        $isAvailable = (bool) $request->boolean('is_available');
        $startTime = $request->input('start_time');
        $endTime = $request->input('end_time');
        if ($isAvailable && (!$startTime || !$endTime || $endTime <= $startTime)) {
            return response()->json(['message' => 'Bij extra beschikbaarheid zijn geldige start/eindtijd verplicht.'], 422);
        }

        $affected = DB::table('gymies_availability_exceptions')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->update([
                'exception_date' => $request->input('exception_date'),
                'is_available' => $isAvailable ? 1 : 0,
                'start_time' => $isAvailable ? $startTime : null,
                'end_time' => $isAvailable ? $endTime : null,
            ]);
        if ($affected === 0) {
            return response()->json(['message' => 'Uitzondering niet gevonden.'], 404);
        }
        return response()->json(['message' => 'Uitzondering bijgewerkt']);
    }

    public function deleteException(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $deleted = DB::table('gymies_availability_exceptions')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->delete();
        if ($deleted === 0) {
            return response()->json(['message' => 'Uitzondering niet gevonden.'], 404);
        }
        return response()->json(['message' => 'Uitzondering verwijderd']);
    }

    /**
     * Notificeer klanten die deze trainer als favoriet hebben: nieuwe beschikbaarheid.
     * Max 1x per 24u per trainer per klant (dedupe).
     */
    private function notifyFavoritesOfNewSlots(int $trainerId): void
    {
        if (!Schema::hasTable('gymies_favorites') || !Schema::hasTable('gymies_notification_queue')) {
            return;
        }
        $trainerName = (string) (DB::table('gymies_users')->where('id', $trainerId)->value('display_name') ?? 'Je favoriete trainer');
        $clientIds = DB::table('gymies_favorites')
            ->where('trainer_user_id', $trainerId)
            ->pluck('client_user_id')
            ->map(fn ($id) => (int) $id)
            ->all();
        if (empty($clientIds)) {
            return;
        }
        $cutoff = now()->subHours(24);
        $payloadBase = json_encode([
            'trainer_user_id' => (string) $trainerId,
            'trainer_name' => $trainerName,
            'action_url' => "/boeken?trainerId={$trainerId}",
        ], JSON_UNESCAPED_UNICODE);
        $now = now();
        foreach ($clientIds as $clientId) {
            // Gebruik transaction+lock om race condition (dubbele notificatie) te voorkomen
            DB::transaction(function () use ($clientId, $trainerId, $cutoff, $payloadBase, $now): void {
                $already = DB::table('gymies_notification_queue')
                    ->where('user_id', $clientId)
                    ->where('event_type', 'favorite_trainer_new_slots')
                    ->where('payload_json', 'like', '%"trainer_user_id":"' . $trainerId . '"%')
                    ->where('created_at', '>=', $cutoff)
                    ->lockForUpdate()
                    ->exists();
                if ($already) {
                    return;
                }
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => $clientId,
                    'channel' => 'in_app',
                    'event_type' => 'favorite_trainer_new_slots',
                    'payload_json' => $payloadBase,
                    'scheduled_for' => $now,
                    'created_at' => $now,
                ]);
            });
        }
    }
}

