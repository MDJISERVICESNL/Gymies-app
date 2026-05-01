<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Services\SlotEngine;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\Rule;

/**
 * Trainer beschikbaarheid: slots, uitzonderingen, instellingen.
 * GET  trainer/availability – slots + exceptions
 * GET  trainer/availability-settings – instellingen (boeken van tevoren, betaalmethode)
 * PATCH trainer/availability-settings – instellingen opslaan
 * POST trainer/availability/slots – slot toevoegen
 * PUT  trainer/availability/slots/{id} – slot bijwerken
 * DELETE trainer/availability/slots/{id} – slot verwijderen
 * POST trainer/availability/exceptions – uitzondering toevoegen
 * PUT  trainer/availability/exceptions/{id} – uitzondering bijwerken
 * DELETE trainer/availability/exceptions/{id} – uitzondering verwijderen
 * GET  trainers/{id}/availability – publieke beschikbaarheid
 * GET  trainers/{id}/blocked-slots – geblokkeerde slots
 */
class GymiesAvailabilityController
{
    private const PAYMENT_METHODS = ['transfer_only', 'transfer_and_cash', 'cash_only'];

    public function settings(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $data = $this->loadSettings((int) $user->id);
        return response()->json(['data' => $data]);
    }

    public function updateSettings(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $validated = $request->validate([
            'booking_advance_days' => ['nullable', 'integer', 'min:1', 'max:365'],
            'payment_method' => ['nullable', 'string', Rule::in(self::PAYMENT_METHODS)],
        ]);

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Trainerprofiel-tabel ontbreekt.'], 500);
        }

        $update = [];
        if (array_key_exists('booking_advance_days', $validated) && $validated['booking_advance_days'] !== null) {
            $update['booking_advance_days'] = (int) $validated['booking_advance_days'];
        }
        if (array_key_exists('payment_method', $validated) && $validated['payment_method'] !== null) {
            $update['payment_method'] = trim($validated['payment_method']);
        }

        if (empty($update)) {
            $data = $this->loadSettings((int) $user->id);
            return response()->json(['data' => $data]);
        }

        $existingColumns = Schema::getColumnListing('gymies_trainer_profiles');
        $allowedUpdate = [];
        foreach ($update as $col => $value) {
            if (in_array($col, $existingColumns, true)) {
                $allowedUpdate[$col] = $value;
            }
        }

        if (!empty($allowedUpdate)) {
            $allowedUpdate['updated_at'] = now();
            $profile = DB::table('gymies_trainer_profiles')->where('user_id', (int) $user->id)->first();
            if ($profile) {
                DB::table('gymies_trainer_profiles')
                    ->where('user_id', (int) $user->id)
                    ->update($allowedUpdate);
            } else {
                $allowedUpdate['user_id'] = (int) $user->id;
                $allowedUpdate['created_at'] = now();
                DB::table('gymies_trainer_profiles')->insert($allowedUpdate);
            }
        }

        $data = $this->loadSettings((int) $user->id);
        return response()->json(['data' => $data]);
    }

    private function loadSettings(int $userId): array
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return [
                'booking_advance_days' => 28,
                'payment_method' => 'transfer_and_cash',
            ];
        }

        $profile = DB::table('gymies_trainer_profiles')->where('user_id', $userId)->first();
        if (!$profile) {
            return [
                'booking_advance_days' => 28,
                'payment_method' => 'transfer_and_cash',
            ];
        }

        $row = (array) $profile;
        $days = $row['booking_advance_days'] ?? 28;
        $method = $row['payment_method'] ?? 'transfer_and_cash';
        if (!in_array($method, self::PAYMENT_METHODS, true)) {
            $method = 'transfer_and_cash';
        }

        return [
            'booking_advance_days' => is_numeric($days) ? (int) $days : 28,
            'payment_method' => $method,
        ];
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $slots = $this->loadSlots((int) $user->id);
        $exceptions = $this->loadExceptions((int) $user->id);
        $settings = $this->loadSettings((int) $user->id);

        return response()->json([
            'slots' => $slots,
            'exceptions' => $exceptions,
            'booking_advance_days' => $settings['booking_advance_days'],
            'payment_method' => $settings['payment_method'],
        ]);
    }

    public function storeSlot(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $validated = $request->validate([
            'weekday' => ['required', 'integer', 'min:1', 'max:7'],
            'start_time' => ['required', 'string', 'regex:/^\d{2}:\d{2}$/'],
            'end_time' => ['required', 'string', 'regex:/^\d{2}:\d{2}$/'],
            'slot_date' => ['nullable', 'date', 'date_format:Y-m-d'],
        ]);

        $table = $this->slotsTable();
        if (!$table) {
            return response()->json(['message' => 'Beschikbaarheid-tabel ontbreekt.'], 500);
        }

        $userIdCol = $this->slotsUserIdColumn();
        $existingColumns = Schema::getColumnListing($table);

        // Bereken week_number en day_of_week automatisch als slot_date meegegeven is
        $slotDate = $validated['slot_date'] ?? null;
        $weekday = (int) $validated['weekday'];
        $weekNumber = null;
        if ($slotDate) {
            $dateObj = new \DateTime($slotDate);
            $weekday = (int) $dateObj->format('N');    // ISO weekdag (1=ma, 7=zo)
            $weekNumber = (int) $dateObj->format('W'); // ISO weeknummer
        }

        $row = [
            $userIdCol => (int) $user->id,
            'start_time' => $validated['start_time'],
            'end_time' => $validated['end_time'],
            'created_at' => now(),
            'updated_at' => now(),
        ];

        // Voeg kolommen toe alleen als ze bestaan
        if (in_array('day_of_week', $existingColumns)) $row['day_of_week'] = $weekday;
        if (in_array('weekday', $existingColumns))     $row['weekday'] = $weekday;
        if (in_array('slot_date', $existingColumns) && $slotDate) $row['slot_date'] = $slotDate;
        if (in_array('week_number', $existingColumns) && $weekNumber !== null) $row['week_number'] = $weekNumber;

        DB::table($table)->insert($row);

        $slots = $this->loadSlots((int) $user->id);
        return response()->json(['slots' => $slots]);
    }

    public function updateSlot(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $validated = $request->validate([
            'weekday' => ['required', 'integer', 'min:1', 'max:7'],
            'start_time' => ['required', 'string', 'regex:/^\d{2}:\d{2}$/'],
            'end_time' => ['required', 'string', 'regex:/^\d{2}:\d{2}$/'],
            'slot_date' => ['nullable', 'date', 'date_format:Y-m-d'],
        ]);

        $table = $this->slotsTable();
        if (!$table) {
            return response()->json(['message' => 'Beschikbaarheid-tabel ontbreekt.'], 500);
        }

        $existingColumns = Schema::getColumnListing($table);
        $slotDate = $validated['slot_date'] ?? null;
        $weekday = (int) $validated['weekday'];
        $weekNumber = null;
        if ($slotDate) {
            $dateObj = new \DateTime($slotDate);
            $weekday = (int) $dateObj->format('N');
            $weekNumber = (int) $dateObj->format('W');
        }

        $update = [
            'start_time' => $validated['start_time'],
            'end_time' => $validated['end_time'],
            'updated_at' => now(),
        ];

        if (in_array('day_of_week', $existingColumns)) $update['day_of_week'] = $weekday;
        if (in_array('weekday', $existingColumns))     $update['weekday'] = $weekday;
        if (in_array('slot_date', $existingColumns))   $update['slot_date'] = $slotDate;
        if (in_array('week_number', $existingColumns) && $weekNumber !== null) $update['week_number'] = $weekNumber;

        $userIdCol = $this->slotsUserIdColumn();
        $idCol = $this->slotsIdColumn();
        $updated = DB::table($table)
            ->where($idCol, $id)
            ->where($userIdCol, (int) $user->id)
            ->update($update);

        if ($updated === 0) {
            return response()->json(['message' => 'Slot niet gevonden.'], 404);
        }

        $slots = $this->loadSlots((int) $user->id);
        return response()->json(['slots' => $slots]);
    }

    public function deleteSlot(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $table = $this->slotsTable();
        if (!$table) {
            return response()->json(['message' => 'Beschikbaarheid-tabel ontbreekt.'], 500);
        }

        $userIdCol = $this->slotsUserIdColumn();
        $idCol = $this->slotsIdColumn();
        $deleted = DB::table($table)
            ->where($idCol, $id)
            ->where($userIdCol, (int) $user->id)
            ->delete();

        if ($deleted === 0) {
            return response()->json(['message' => 'Slot niet gevonden.'], 404);
        }

        return response()->json(['message' => 'Slot verwijderd.']);
    }

    public function storeException(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $validated = $request->validate([
            'date' => ['required', 'date'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        $table = $this->exceptionsTable();
        if (!$table) {
            return response()->json(['message' => 'Uitzonderingen-tabel ontbreekt.'], 500);
        }

        $userIdCol = $this->exceptionsUserIdColumn();
        $dateCol = $this->exceptionsDateColumn();
        DB::table($table)->insert([
            $userIdCol => (int) $user->id,
            $dateCol => $validated['date'],
            'reason' => $validated['reason'] ?? null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $exceptions = $this->loadExceptions((int) $user->id);
        return response()->json(['exceptions' => $exceptions]);
    }

    public function updateException(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $validated = $request->validate([
            'date' => ['required', 'date'],
            'reason' => ['nullable', 'string', 'max:500'],
        ]);

        $table = $this->exceptionsTable();
        if (!$table) {
            return response()->json(['message' => 'Uitzonderingen-tabel ontbreekt.'], 500);
        }

        $userIdCol = $this->exceptionsUserIdColumn();
        $idCol = $this->exceptionsIdColumn();
        $dateCol = $this->exceptionsDateColumn();
        $updated = DB::table($table)
            ->where($idCol, $id)
            ->where($userIdCol, (int) $user->id)
            ->update([
                $dateCol => $validated['date'],
                'reason' => $validated['reason'] ?? null,
                'updated_at' => now(),
            ]);

        if ($updated === 0) {
            return response()->json(['message' => 'Uitzondering niet gevonden.'], 404);
        }

        $exceptions = $this->loadExceptions((int) $user->id);
        return response()->json(['exceptions' => $exceptions]);
    }

    public function deleteException(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $table = $this->exceptionsTable();
        if (!$table) {
            return response()->json(['message' => 'Uitzonderingen-tabel ontbreekt.'], 500);
        }

        $userIdCol = $this->exceptionsUserIdColumn();
        $idCol = $this->exceptionsIdColumn();
        $deleted = DB::table($table)
            ->where($idCol, $id)
            ->where($userIdCol, (int) $user->id)
            ->delete();

        if ($deleted === 0) {
            return response()->json(['message' => 'Uitzondering niet gevonden.'], 404);
        }

        return response()->json(['message' => 'Uitzondering verwijderd.']);
    }

    public function publicAvailability(Request $request, string $id): JsonResponse
    {
        $trainerId = (int) $id;
        if ($trainerId <= 0) {
            return response()->json(['data' => []]);
        }

        // Load raw slots for backward compatibility
        $slots = $this->loadSlotsForTrainer($trainerId);
        $exceptions = $this->loadExceptionsForTrainer($trainerId);

        // Parse date range parameters (defaults: today to +28 days)
        $fromDate = $request->query('from')
            ? \Carbon\Carbon::parse($request->query('from'))->format('Y-m-d')
            : \Carbon\Carbon::now()->format('Y-m-d');

        $toDate = $request->query('to')
            ? \Carbon\Carbon::parse($request->query('to'))->format('Y-m-d')
            : \Carbon\Carbon::now()->addDays(28)->format('Y-m-d');

        // Use SlotEngine to compute bookable slots
        $slotEngine = new SlotEngine();
        $bookableSlots = $slotEngine->getBookableSlots($trainerId, $fromDate, $toDate, filterBooked: true);

        // Load trainer settings for the response
        $trainerSettings = $slotEngine->loadTrainerSettings($trainerId);
        $settings = [
            'session_duration' => $trainerSettings['session_duration_min'],
            'buffer' => $trainerSettings['buffer_minutes'],
            'timezone' => $trainerSettings['timezone'],
            'lead_time_minutes' => $trainerSettings['lead_time_minutes'],
            'max_advance_days' => $trainerSettings['max_advance_days'],
        ];

        return response()->json([
            'data' => $slots,
            'availability' => $slots,
            'slots' => $slots,
            'exceptions' => $exceptions,
            'bookable_slots' => $bookableSlots,
            'settings' => $settings,
        ]);
    }

    public function blockedSlots(Request $request, string $id): JsonResponse
    {
        $trainerId = (int) $id;
        if ($trainerId <= 0) {
            return response()->json(['data' => []]);
        }

        $exceptions = $this->loadExceptionsForTrainer($trainerId);
        return response()->json(['data' => $exceptions]);
    }

    private function loadSlots(int $userId): array
    {
        $table = $this->slotsTable();
        if (!$table) {
            return [];
        }

        $userIdCol = $this->slotsUserIdColumn();
        $idCol = $this->slotsIdColumn();
        $existingColumns = Schema::getColumnListing($table);

        // Sorteer op datum (als beschikbaar), anders weekdag
        $orderCol = in_array('slot_date', $existingColumns) ? 'slot_date' : 'day_of_week';
        $rows = DB::table($table)
            ->where($userIdCol, $userId)
            ->orderBy($orderCol)
            ->orderBy('start_time')
            ->get();

        $slots = [];
        foreach ($rows as $row) {
            $r = (array) $row;
            $weekday = $r['weekday'] ?? $r['day_of_week'] ?? 1;
            $slot = [
                'id' => (string) ($r[$idCol] ?? $r['id'] ?? ''),
                'weekday' => (int) $weekday,
                'day_of_week' => (int) $weekday,
                'start_time' => $r['start_time'] ?? '09:00',
                'end_time' => $r['end_time'] ?? '17:00',
                'is_active' => ($r['is_active'] ?? true) !== false,
            ];

            // Voeg datum- en weekvelden toe als ze bestaan
            if (isset($r['slot_date']) && $r['slot_date']) {
                $slot['date'] = $r['slot_date'];
                $slot['slot_date'] = $r['slot_date'];
            }
            if (isset($r['week_number'])) {
                $slot['week_number'] = (int) $r['week_number'];
            }

            $slots[] = $slot;
        }
        return $slots;
    }

    private function loadSlotsForTrainer(int $trainerId): array
    {
        return $this->loadSlots($trainerId);
    }

    private function loadExceptions(int $userId): array
    {
        $table = $this->exceptionsTable();
        if (!$table) {
            return [];
        }

        try {
            $userIdCol = $this->exceptionsUserIdColumn();
            $idCol = $this->exceptionsIdColumn();
            $dateCol = $this->exceptionsDateColumn();

            // Verify the date column actually exists before querying
            $cols = Schema::getColumnListing($table);
            if (!in_array($dateCol, $cols)) {
                // No valid date column found — skip exceptions silently
                return [];
            }

            $rows = DB::table($table)
                ->where($userIdCol, $userId)
                ->orderBy($dateCol)
                ->get();

            $exceptions = [];
            foreach ($rows as $row) {
                $r = (array) $row;
                $date = $r[$dateCol] ?? $r['blocked_date'] ?? $r['date'] ?? null;
                if ($date) {
                    $exceptions[] = [
                        'id' => (string) ($r[$idCol] ?? $r['id'] ?? ''),
                        'date' => is_string($date) ? $date : ($date instanceof \DateTimeInterface ? $date->format('Y-m-d') : ''),
                        'reason' => $r['reason'] ?? null,
                    ];
                }
            }
            return $exceptions;
        } catch (\Throwable $e) {
            // Log but don't crash — exceptions table issues shouldn't break availability
            \Log::warning('GymiesAvailabilityController: loadExceptions failed', [
                'error' => $e->getMessage(),
                'userId' => $userId,
            ]);
            return [];
        }
    }

    private function loadExceptionsForTrainer(int $trainerId): array
    {
        return $this->loadExceptions($trainerId);
    }

    private function slotsTable(): ?string
    {
        if (Schema::hasTable('gymies_availability_slots')) {
            return 'gymies_availability_slots';
        }
        return null;
    }

    private function slotsUserIdColumn(): string
    {
        $cols = $this->slotsTable() ? Schema::getColumnListing($this->slotsTable()) : [];
        return in_array('trainer_user_id', $cols) ? 'trainer_user_id' : 'user_id';
    }

    private function slotsIdColumn(): string
    {
        return 'id';
    }

    private function exceptionsTable(): ?string
    {
        if (Schema::hasTable('gymies_availability_exceptions')) {
            return 'gymies_availability_exceptions';
        }
        return null;
    }

    private function exceptionsUserIdColumn(): string
    {
        $cols = $this->exceptionsTable() ? Schema::getColumnListing($this->exceptionsTable()) : [];
        return in_array('trainer_user_id', $cols) ? 'trainer_user_id' : 'user_id';
    }

    private function exceptionsDateColumn(): string
    {
        $cols = $this->exceptionsTable() ? Schema::getColumnListing($this->exceptionsTable()) : [];
        if (in_array('blocked_date', $cols)) return 'blocked_date';
        if (in_array('exception_date', $cols)) return 'exception_date';
        if (in_array('date', $cols)) return 'date';
        // Fallback: als geen kolom gevonden, geef 'blocked_date' (meest waarschijnlijk)
        return 'blocked_date';
    }

    private function exceptionsIdColumn(): string
    {
        return 'id';
    }
}
