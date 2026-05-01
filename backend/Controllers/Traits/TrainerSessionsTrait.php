<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies\Traits;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trait for handling session entries and client goals operations.
 */
trait TrainerSessionsTrait
{
    /**
     * Session Entry timeline per klant (first-class resource).
     */
    public function sessionEntriesIndex(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_session_entries')) {
            return response()->json([
                'data' => [
                    'session_entries' => [],
                    'pagination' => ['page' => 1, 'per_page' => 20, 'has_more' => false],
                ],
            ]);
        }

        $page = max((int) $request->query('page', 1), 1);
        $perPage = min(max((int) $request->query('per_page', 20), 1), 100);
        $offset = ($page - 1) * $perPage;

        $rows = DB::table('gymies_client_session_entries')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->orderByDesc('session_at')
            ->orderByDesc('id')
            ->offset($offset)
            ->limit($perPage + 1)
            ->get();

        $hasMore = $rows->count() > $perPage;
        $rows = $rows->slice(0, $perPage)->values();

        return response()->json([
            'data' => [
                'session_entries' => $rows->map(fn ($r) => $this->sessionEntryToArray($r))->all(),
                'pagination' => [
                    'page' => $page,
                    'per_page' => $perPage,
                    'has_more' => $hasMore,
                ],
            ],
        ]);
    }

    public function sessionEntriesStore(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_session_entries')) {
            return response()->json(['message' => 'Session entries tabel ontbreekt. Voer migratie uit.'], 503);
        }

        $request->validate([
            'booking_id' => 'nullable|integer|min:1',
            'session_at' => 'required|date',
            'session_type' => 'required|string|max:64',
            'attendance_status' => 'required|in:attended,no_show,cancelled,unknown',
            'focus' => 'nullable|string|max:5000',
            'positive_notes' => 'nullable|string|max:5000',
            'improve_notes' => 'nullable|string|max:5000',
            'homework' => 'nullable|string|max:5000',
            'energy_score' => 'nullable|integer|min:1|max:5',
            'performance_score' => 'nullable|numeric|min:0|max:1000000',
            'visibility' => 'nullable|in:shared,internal',
        ]);

        $bookingId = $request->input('booking_id') !== null ? (int) $request->input('booking_id') : null;
        if ($bookingId !== null) {
            $booking = DB::table('gymies_bookings')
                ->where('id', $bookingId)
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->first();
            if (!$booking) {
                return response()->json(['message' => 'Boeking hoort niet bij trainer/klant.'], 422);
            }
        }

        $id = DB::table('gymies_client_session_entries')->insertGetId([
            'trainer_user_id' => $trainerId,
            'client_user_id' => $clientId,
            'booking_id' => $bookingId,
            'session_at' => (string) $request->input('session_at'),
            'session_type' => trim((string) $request->input('session_type')),
            'attendance_status' => (string) $request->input('attendance_status'),
            'focus' => $request->input('focus'),
            'positive_notes' => $request->input('positive_notes'),
            'improve_notes' => $request->input('improve_notes'),
            'homework' => $request->input('homework'),
            'energy_score' => $request->input('energy_score'),
            'performance_score' => $request->input('performance_score'),
            'visibility' => (string) $request->input('visibility', 'internal'),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $row = DB::table('gymies_client_session_entries')->where('id', $id)->first();
        return response()->json(['data' => $this->sessionEntryToArray($row)], 201);
    }

    public function sessionEntriesPatch(Request $request, string $clientUserId, string $entryId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;

        // Verify trainer-client relationship before entry lookup (IDOR prevention)
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant.'], 403);
        }

        if (!Schema::hasTable('gymies_client_session_entries')) {
            return response()->json(['message' => 'Session entries tabel ontbreekt.'], 503);
        }
        $entry = DB::table('gymies_client_session_entries')
            ->where('id', (int) $entryId)
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->first();
        if (!$entry) {
            return response()->json(['message' => 'Session entry niet gevonden.'], 404);
        }

        $request->validate([
            'session_at' => 'sometimes|date',
            'session_type' => 'sometimes|string|max:64',
            'attendance_status' => 'sometimes|in:attended,no_show,cancelled,unknown',
            'focus' => 'sometimes|nullable|string|max:5000',
            'positive_notes' => 'sometimes|nullable|string|max:5000',
            'improve_notes' => 'sometimes|nullable|string|max:5000',
            'homework' => 'sometimes|nullable|string|max:5000',
            'energy_score' => 'sometimes|nullable|integer|min:1|max:5',
            'performance_score' => 'sometimes|nullable|numeric|min:0|max:1000000',
            'visibility' => 'sometimes|in:shared,internal',
        ]);

        $payload = ['updated_at' => now()];
        foreach ([
            'session_at',
            'session_type',
            'attendance_status',
            'focus',
            'positive_notes',
            'improve_notes',
            'homework',
            'energy_score',
            'performance_score',
            'visibility',
        ] as $key) {
            if ($request->has($key)) {
                $payload[$key] = $request->input($key);
            }
        }

        $oldVisibility = (string) ($entry->visibility ?? 'internal');
        DB::table('gymies_client_session_entries')->where('id', (int) $entryId)->update($payload);
        $fresh = DB::table('gymies_client_session_entries')->where('id', (int) $entryId)->first();
        $newVisibility = (string) ($fresh->visibility ?? 'internal');
        if ($oldVisibility !== $newVisibility) {
            $this->logAudit(
                $trainerId,
                'session_entry_visibility_changed',
                'session_entry',
                (int) $entryId,
                ['visibility' => $oldVisibility],
                ['visibility' => $newVisibility]
            );
        }

        return response()->json(['data' => $this->sessionEntryToArray($fresh)]);
    }

    public function sessionEntriesDelete(Request $request, string $clientUserId, string $entryId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if (!Schema::hasTable('gymies_client_session_entries')) {
            return response()->json(['message' => 'Session entries tabel ontbreekt.'], 503);
        }

        $affected = DB::table('gymies_client_session_entries')
            ->where('id', (int) $entryId)
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->update([
                'deleted_at' => now(),
                'updated_at' => now(),
            ]);
        if ($affected === 0) {
            return response()->json(['message' => 'Session entry niet gevonden.'], 404);
        }
        return response()->json(['data' => ['deleted' => true]]);
    }

    public function clientGoalsIndex(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_goals')) {
            return response()->json(['data' => ['goals' => []]]);
        }

        $goals = DB::table('gymies_client_goals')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->orderByDesc('created_at')
            ->get();

        $goalIds = $goals->pluck('id')->map(fn ($id) => (int) $id)->all();
        $pointsByGoal = [];
        if (!empty($goalIds) && Schema::hasTable('gymies_client_goal_progress_points')) {
            $pointsByGoal = DB::table('gymies_client_goal_progress_points')
                ->whereIn('goal_id', $goalIds)
                ->orderBy('measured_at')
                ->orderBy('id')
                ->get()
                ->groupBy('goal_id')
                ->map(fn ($items) => $items->map(fn ($p) => [
                    'id' => (string) $p->id,
                    'goal_id' => (string) $p->goal_id,
                    'value_numeric' => $p->value_numeric !== null ? (float) $p->value_numeric : null,
                    'note' => $p->note,
                    'measured_at' => $p->measured_at,
                    'created_at' => $p->created_at,
                    'updated_at' => $p->updated_at,
                ])->all())
                ->all();
        }

        return response()->json([
            'data' => [
                'goals' => $goals->map(fn ($g) => [
                    'id' => (string) $g->id,
                    'trainer_user_id' => (string) $g->trainer_user_id,
                    'client_user_id' => (string) $g->client_user_id,
                    'title' => $g->title,
                    'target_value' => $g->target_value !== null ? (float) $g->target_value : null,
                    'current_value' => $g->current_value !== null ? (float) $g->current_value : null,
                    'unit' => $g->unit,
                    'status' => $g->status,
                    'due_date' => $g->due_date,
                    'created_at' => $g->created_at,
                    'updated_at' => $g->updated_at,
                    'progress_points' => $pointsByGoal[(int) $g->id] ?? [],
                ])->all(),
            ],
        ]);
    }

    public function clientGoalsStore(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_goals')) {
            return response()->json(['message' => 'Goals tabel ontbreekt. Voer migratie uit.'], 503);
        }
        $request->validate([
            'title' => 'required|string|max:255',
            'target_value' => 'nullable|numeric',
            'current_value' => 'nullable|numeric',
            'unit' => 'nullable|string|max:40',
            'status' => 'nullable|in:active,done,paused,cancelled',
            'due_date' => 'nullable|date',
        ]);

        $id = DB::table('gymies_client_goals')->insertGetId([
            'trainer_user_id' => $trainerId,
            'client_user_id' => $clientId,
            'title' => trim((string) $request->input('title')),
            'target_value' => $request->input('target_value'),
            'current_value' => $request->input('current_value'),
            'unit' => $request->input('unit'),
            'status' => (string) $request->input('status', 'active'),
            'due_date' => $request->input('due_date'),
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $goal = DB::table('gymies_client_goals')->where('id', $id)->first();

        return response()->json([
            'data' => [
                'id' => (string) $goal->id,
                'trainer_user_id' => (string) $goal->trainer_user_id,
                'client_user_id' => (string) $goal->client_user_id,
                'title' => $goal->title,
                'target_value' => $goal->target_value !== null ? (float) $goal->target_value : null,
                'current_value' => $goal->current_value !== null ? (float) $goal->current_value : null,
                'unit' => $goal->unit,
                'status' => $goal->status,
                'due_date' => $goal->due_date,
                'created_at' => $goal->created_at,
                'updated_at' => $goal->updated_at,
                'progress_points' => [],
            ],
        ], 201);
    }

    public function clientGoalsPatch(Request $request, string $clientUserId, string $goalId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if (!Schema::hasTable('gymies_client_goals')) {
            return response()->json(['message' => 'Goals tabel ontbreekt.'], 503);
        }
        $goal = DB::table('gymies_client_goals')
            ->where('id', (int) $goalId)
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->first();
        if (!$goal) {
            return response()->json(['message' => 'Goal niet gevonden.'], 404);
        }
        $request->validate([
            'title' => 'sometimes|string|max:255',
            'target_value' => 'sometimes|nullable|numeric',
            'current_value' => 'sometimes|nullable|numeric',
            'unit' => 'sometimes|nullable|string|max:40',
            'status' => 'sometimes|in:active,done,paused,cancelled',
            'due_date' => 'sometimes|nullable|date',
        ]);

        $payload = ['updated_at' => now()];
        foreach (['title', 'target_value', 'current_value', 'unit', 'status', 'due_date'] as $key) {
            if ($request->has($key)) {
                $payload[$key] = $request->input($key);
            }
        }
        DB::table('gymies_client_goals')->where('id', (int) $goalId)->update($payload);
        $fresh = DB::table('gymies_client_goals')->where('id', (int) $goalId)->first();
        return response()->json([
            'data' => [
                'id' => (string) $fresh->id,
                'trainer_user_id' => (string) $fresh->trainer_user_id,
                'client_user_id' => (string) $fresh->client_user_id,
                'title' => $fresh->title,
                'target_value' => $fresh->target_value !== null ? (float) $fresh->target_value : null,
                'current_value' => $fresh->current_value !== null ? (float) $fresh->current_value : null,
                'unit' => $fresh->unit,
                'status' => $fresh->status,
                'due_date' => $fresh->due_date,
                'created_at' => $fresh->created_at,
                'updated_at' => $fresh->updated_at,
            ],
        ]);
    }

    public function clientGoalsProgressPointStore(Request $request, string $clientUserId, string $goalId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if (!Schema::hasTable('gymies_client_goals') || !Schema::hasTable('gymies_client_goal_progress_points')) {
            return response()->json(['message' => 'Goal-progress tabel ontbreekt. Voer migratie uit.'], 503);
        }
        $goal = DB::table('gymies_client_goals')
            ->where('id', (int) $goalId)
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->first();
        if (!$goal) {
            return response()->json(['message' => 'Goal niet gevonden.'], 404);
        }
        $request->validate([
            'value_numeric' => 'nullable|numeric',
            'note' => 'nullable|string|max:1000',
            'measured_at' => 'nullable|date',
        ]);

        $id = DB::table('gymies_client_goal_progress_points')->insertGetId([
            'goal_id' => (int) $goalId,
            'value_numeric' => $request->input('value_numeric'),
            'note' => $request->input('note'),
            'measured_at' => $request->input('measured_at') ?? now(),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        if ($request->input('value_numeric') !== null) {
            DB::table('gymies_client_goals')->where('id', (int) $goalId)->update([
                'current_value' => $request->input('value_numeric'),
                'updated_at' => now(),
            ]);
        }
        $point = DB::table('gymies_client_goal_progress_points')->where('id', $id)->first();

        return response()->json([
            'data' => [
                'id' => (string) $point->id,
                'goal_id' => (string) $point->goal_id,
                'value_numeric' => $point->value_numeric !== null ? (float) $point->value_numeric : null,
                'note' => $point->note,
                'measured_at' => $point->measured_at,
                'created_at' => $point->created_at,
                'updated_at' => $point->updated_at,
            ],
        ], 201);
    }

    /**
     * @return array<string,mixed>
     */
    private function sessionEntryToArray(object $row): array
    {
        return [
            'id' => (string) $row->id,
            'trainer_user_id' => (string) $row->trainer_user_id,
            'client_user_id' => (string) $row->client_user_id,
            'booking_id' => $row->booking_id !== null ? (string) $row->booking_id : null,
            'session_at' => $row->session_at,
            'session_type' => $row->session_type,
            'attendance_status' => $row->attendance_status,
            'focus' => $row->focus,
            'positive_notes' => $row->positive_notes,
            'improve_notes' => $row->improve_notes,
            'homework' => $row->homework,
            'energy_score' => $row->energy_score !== null ? (int) $row->energy_score : null,
            'performance_score' => $row->performance_score !== null ? (float) $row->performance_score : null,
            'visibility' => $row->visibility ?? 'internal',
            'created_at' => $row->created_at ?? null,
            'updated_at' => $row->updated_at ?? null,
        ];
    }

    /**
     * @param list<string> $dates yyyy-mm-dd
     */
    private function calculateDateStreakDays(array $dates): int
    {
        if (empty($dates)) {
            return 0;
        }
        rsort($dates);
        $streak = 1;
        $cursor = \Carbon\Carbon::parse($dates[0])->startOfDay();
        for ($i = 1; $i < count($dates); $i++) {
            $d = \Carbon\Carbon::parse($dates[$i])->startOfDay();
            if ($d->equalTo($cursor->copy()->subDay())) {
                $streak++;
                $cursor = $d;
                continue;
            }
            if ($d->equalTo($cursor)) {
                continue;
            }
            break;
        }
        return $streak;
    }
}
