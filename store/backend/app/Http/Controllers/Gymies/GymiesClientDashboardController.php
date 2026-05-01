<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Klant dashboard & workouts.
 *
 * GET api/gymies/client/progress-dashboard
 * GET api/gymies/me/workouts
 * Vereist: gymies.auth middleware (Bearer token).
 *
 * Retourneert een geaggregeerd overzicht van de klant:
 *  - sessie-statistieken (totaal, voltooid, aankomend)
 *  - recentste boekingen
 *  - actieve trainers
 *  - groepssessie-registraties
 */
final class GymiesClientDashboardController extends Controller
{
    public function progressDashboard(Request $request): JsonResponse
    {
        /** @var object|null $user */
        $user = $request->attributes->get('gymies_user');

        if (! $user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $userId = (int) $user->id;

        // ── Sessie-statistieken ───────────────────────────────────────────────
        $stats = DB::table('gymies_bookings')
            ->where('client_user_id', $userId)
            ->selectRaw("
                COUNT(*) AS total_bookings,
                SUM(CASE WHEN status = 'completed'  THEN 1 ELSE 0 END) AS completed,
                SUM(CASE WHEN status IN ('confirmed','pending') AND scheduled_at > NOW() THEN 1 ELSE 0 END) AS upcoming,
                SUM(CASE WHEN status = 'cancelled'  THEN 1 ELSE 0 END) AS cancelled,
                SUM(CASE
                    WHEN status = 'completed'
                     AND scheduled_at >= DATE_FORMAT(NOW(), '%Y-%m-01')
                    THEN 1 ELSE 0
                END) AS completed_this_month
            ")
            ->first();

        // ── Recentste boekingen (max 5) ───────────────────────────────────────
        $recentBookings = DB::table('gymies_bookings as b')
            ->join('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->where('b.client_user_id', $userId)
            ->orderByDesc('b.scheduled_at')
            ->limit(5)
            ->select([
                'b.id',
                'b.status',
                'b.scheduled_at',
                'b.duration_minutes',
                't.first_name as trainer_first_name',
                't.last_name  as trainer_last_name',
            ])
            ->get()
            ->map(fn ($row) => [
                'id'           => $row->id,
                'status'       => $row->status,
                'scheduled_at' => $row->scheduled_at,
                'duration_min' => $row->duration_minutes,
                'trainer_name' => trim($row->trainer_first_name . ' ' . $row->trainer_last_name),
            ]);

        // ── Aankomende sessie ─────────────────────────────────────────────────
        $nextSession = DB::table('gymies_bookings as b')
            ->join('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->where('b.client_user_id', $userId)
            ->whereIn('b.status', ['confirmed', 'pending'])
            ->where('b.scheduled_at', '>', now())
            ->orderBy('b.scheduled_at')
            ->select([
                'b.id',
                'b.scheduled_at',
                'b.duration_minutes',
                't.first_name as trainer_first_name',
                't.last_name  as trainer_last_name',
            ])
            ->first();

        // ── Actieve trainers (distinct trainers waarmee sessies zijn) ─────────
        // T-043 FIXED: GROUP BY consistentie verbeterd, duplicates voorkomen
        $activeTrainers = DB::table('gymies_bookings as b')
            ->join('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->where('b.client_user_id', $userId)
            ->whereIn('b.status', ['completed', 'confirmed', 'pending'])
            ->distinct()
            ->groupBy('t.id', 't.first_name', 't.last_name')
            ->select([
                't.id',
                't.first_name',
                't.last_name',
                DB::raw('COUNT(b.id) as session_count'),
            ])
            ->orderByDesc('session_count')
            ->limit(5)
            ->get()
            ->map(fn ($t) => [
                'trainer_user_id' => $t->id,
                'name'            => trim($t->first_name . ' ' . $t->last_name),
                'session_count'   => (int) $t->session_count,
            ]);

        // ── Groepssessie-registraties (aankomend) ────────────────────────────
        $groupRegistrations = [];
        if (DB::getSchemaBuilder()->hasTable('gymies_group_session_participants')) {
            $groupRegistrations = DB::table('gymies_group_session_participants as p')
                ->join('gymies_group_sessions as gs', 'gs.id', '=', 'p.group_session_id')
                ->join('gymies_users as t', 't.id', '=', 'gs.trainer_user_id')
                ->where('p.client_user_id', $userId)
                ->where('gs.scheduled_at', '>', now())
                ->whereNotIn('p.status', ['cancelled'])
                ->orderBy('gs.scheduled_at')
                ->limit(3)
                ->select([
                    'gs.id as group_session_id',
                    'gs.title',
                    'gs.scheduled_at',
                    'gs.duration_minutes',
                    't.first_name as trainer_first_name',
                    't.last_name  as trainer_last_name',
                    'p.status as participant_status',
                ])
                ->get()
                ->map(fn ($r) => [
                    'group_session_id'  => $r->group_session_id,
                    'title'             => $r->title,
                    'scheduled_at'      => $r->scheduled_at,
                    'duration_min'      => $r->duration_minutes,
                    'trainer_name'      => trim($r->trainer_first_name . ' ' . $r->trainer_last_name),
                    'status'            => $r->participant_status,
                ])
                ->values();
        }

        return response()->json([
            'stats' => [
                'total_bookings'       => (int) ($stats->total_bookings       ?? 0),
                'completed'            => (int) ($stats->completed             ?? 0),
                'upcoming'             => (int) ($stats->upcoming              ?? 0),
                'cancelled'            => (int) ($stats->cancelled             ?? 0),
                'completed_this_month' => (int) ($stats->completed_this_month  ?? 0),
            ],
            'next_session'        => $nextSession ? [
                'id'           => $nextSession->id,
                'scheduled_at' => $nextSession->scheduled_at,
                'duration_min' => $nextSession->duration_minutes,
                'trainer_name' => trim($nextSession->trainer_first_name . ' ' . $nextSession->trainer_last_name),
            ] : null,
            'recent_bookings'     => $recentBookings->values(),
            'active_trainers'     => $activeTrainers->values(),
            'group_registrations' => $groupRegistrations,
        ]);
    }

    /**
     * GET api/gymies/me/workouts
     *
     * Geeft een gepagineerde lijst van trainingen (boekingen) van de klant,
     * inclusief sessie-notities van de trainer en voortgangsmetingen.
     *
     * Query params:
     *   - page       (int, default 1)
     *   - per_page   (int, default 20, max 50)
     *   - status     (string: completed|upcoming|all, default all)
     */
    public function myWorkouts(Request $request): JsonResponse
    {
        /** @var object|null $user */
        $user = $request->attributes->get('gymies_user');

        if (! $user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $userId  = (int) $user->id;
        $page    = max(1, (int) $request->query('page', 1));
        $perPage = min(50, max(1, (int) $request->query('per_page', 20)));
        $status  = $request->query('status', 'all');

        // ── Basis query: boekingen van deze klant ────────────────────────────
        $query = DB::table('gymies_bookings as b')
            ->join('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->where('b.client_user_id', $userId);

        match ($status) {
            'completed' => $query->where('b.status', 'completed'),
            'upcoming'  => $query->whereIn('b.status', ['confirmed', 'pending'])
                                 ->where('b.scheduled_at', '>', now()),
            default     => null,   // 'all': geen extra filter
        };

        $total = (clone $query)->count();

        $bookings = $query
            ->orderByDesc('b.scheduled_at')
            ->offset(($page - 1) * $perPage)
            ->limit($perPage)
            ->select([
                'b.id',
                'b.status',
                'b.scheduled_at',
                'b.duration_minutes',
                'b.location_type',
                'b.trainer_user_id',
                't.first_name as trainer_first_name',
                't.last_name  as trainer_last_name',
            ])
            ->get();

        // ── Sessie-notities van de trainer ophalen (indien tabel bestaat) ─────
        $bookingIds = $bookings->pluck('id')->toArray();
        $notesMap   = [];

        if (! empty($bookingIds) && DB::getSchemaBuilder()->hasTable('gymies_session_notes')) {
            $notes = DB::table('gymies_session_notes')
                ->whereIn('booking_id', $bookingIds)
                ->select(['booking_id', 'note', 'created_at'])
                ->get()
                ->keyBy('booking_id');

            foreach ($notes as $bookingId => $note) {
                $notesMap[$bookingId] = [
                    'note'       => $note->note,
                    'created_at' => $note->created_at,
                ];
            }
        }

        // ── Voortgangsmetingen per trainer (meest recent) ────────────────────
        $progressMap = [];

        if (! empty($bookingIds) && DB::getSchemaBuilder()->hasTable('gymies_client_progress')) {
            $progressRows = DB::table('gymies_client_progress')
                ->where('client_user_id', $userId)
                ->whereIn('trainer_user_id', $bookings->pluck('trainer_user_id')->unique()->toArray())
                ->orderByDesc('recorded_at')
                ->select(['trainer_user_id', 'metric_key', 'metric_value', 'recorded_at'])
                ->get()
                ->groupBy('trainer_user_id');

            foreach ($progressRows as $trainerId => $rows) {
                $progressMap[$trainerId] = $rows->map(fn ($r) => [
                    'key'         => $r->metric_key,
                    'value'       => $r->metric_value,
                    'recorded_at' => $r->recorded_at,
                ])->values();
            }
        }

        // ── Response samenstellen ─────────────────────────────────────────────
        $workouts = $bookings->map(function ($b) use ($notesMap, $progressMap) {
            $trainerId = $b->trainer_user_id;
            return [
                'id'           => $b->id,
                'status'       => $b->status,
                'scheduled_at' => $b->scheduled_at,
                'duration_min' => $b->duration_minutes,
                'location_type'=> $b->location_type ?? null,
                'trainer'      => [
                    'user_id' => $trainerId,
                    'name'    => trim($b->trainer_first_name . ' ' . $b->trainer_last_name),
                ],
                'session_note' => $notesMap[$b->id] ?? null,
                'progress'     => $progressMap[$trainerId] ?? [],
            ];
        })->values();

        return response()->json([
            'data' => $workouts,
            'meta' => [
                'total'        => $total,
                'page'         => $page,
                'per_page'     => $perPage,
                'last_page'    => (int) ceil($total / $perPage),
                'status_filter'=> $status,
            ],
        ]);
    }
}
