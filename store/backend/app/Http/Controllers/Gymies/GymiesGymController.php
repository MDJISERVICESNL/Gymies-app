<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Log;

class GymiesGymController extends Controller
{
    public function membership(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager', 'viewer', 'trainer']);
        if ($ctx instanceof JsonResponse) {
            return response()->json([
                'data' => [
                    'has_gym_access' => false,
                ],
            ]);
        }

        return response()->json([
            'data' => [
                'has_gym_access' => true,
                'organisation_id' => (string) $ctx['organisation_id'],
                'organisation_name' => (string) $ctx['organisation_name'],
                'member_role' => (string) $ctx['member_role'],
                'dashboard_route' => '/gym',
            ],
        ]);
    }

    public function dashboard(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $orgId = (int) $ctx['organisation_id'];

        $activeTrainers = DB::table('gymies_organisation_trainers')
            ->where('organisation_id', $orgId)
            ->where('status', 'active')
            ->count();

        $weekStart = now()->startOfWeek();
        $weekEnd = now()->endOfWeek();
        $bookingsWeek = DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->whereBetween('scheduled_at', [$weekStart, $weekEnd])
            ->count();

        $grossCents = (int) DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->whereIn('status', ['confirmed', 'completed'])
            ->whereNotNull('paid_at')
            ->sum('amount_cents');

        $platformFeeCents = (int) round($grossCents * 0.12);
        $netCents = max($grossCents - $platformFeeCents, 0);

        $openSettlements = Schema::hasTable('gymies_organisation_settlements')
            ? DB::table('gymies_organisation_settlements')
                ->where('organisation_id', $orgId)
                ->whereIn('status', ['draft', 'approved'])
                ->count()
            : 0;

        return response()->json([
            'data' => [
                'organisation_id' => (string) $orgId,
                'organisation_name' => (string) $ctx['organisation_name'],
                'member_role' => (string) $ctx['member_role'],
                'active_trainers_count' => $activeTrainers,
                'bookings_this_week_count' => $bookingsWeek,
                'gross_cents' => $grossCents,
                'platform_fee_cents' => $platformFeeCents,
                'net_cents' => $netCents,
                'open_settlements_count' => $openSettlements,
            ],
        ]);
    }

    /**
     * Ruimtebezetting: per locatie status (vrij/bezet) voor een tijdsinterval.
     * Voor dashboard-widget: GET gym/occupancy?start_at=&end_at=
     */
    public function occupancy(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager', 'viewer', 'trainer']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gym_locations')) {
            return response()->json(['data' => []]);
        }

        $request->validate([
            'start_at' => 'required|date',
            'end_at' => 'required|date|after:start_at',
        ]);
        $startAt = $request->input('start_at');
        $endAt = $request->input('end_at');
        $orgId = (int) $ctx['organisation_id'];

        $locations = DB::table('gym_locations')
            ->where('organisation_id', $orgId)
            ->orderBy('sort_order')
            ->orderBy('name')
            ->get(['id', 'name', 'location_type', 'capacity']);

        $locationIds = $locations->pluck('id')->all();

        // Batch-fetch alle conflicten in 3 queries ipv 3×N
        $blocksByLoc = collect();
        if (Schema::hasTable('gym_location_blocks') && count($locationIds) > 0) {
            $blocksByLoc = DB::table('gym_location_blocks')
                ->whereIn('location_id', $locationIds)
                ->where('start_at', '<', $endAt)
                ->where('end_at', '>', $startAt)
                ->get()
                ->groupBy('location_id');
        }

        $sessionsByLoc = collect();
        if (Schema::hasColumn('gymies_group_sessions', 'gym_location_id') && count($locationIds) > 0) {
            $sessionsByLoc = DB::table('gymies_group_sessions')
                ->whereIn('gym_location_id', $locationIds)
                ->whereIn('status', ['scheduled', 'published', 'crowdfund'])
                ->where('scheduled_at', '<', $endAt)
                ->whereRaw('DATE_ADD(scheduled_at, INTERVAL COALESCE(duration_minutes, 60) MINUTE) > ?', [$startAt])
                ->get(['id', 'gym_location_id', 'title', 'scheduled_at', 'duration_minutes'])
                ->groupBy('gym_location_id');
        }

        $bookingsByLoc = collect();
        if (Schema::hasColumn('gymies_bookings', 'gym_location_id') && count($locationIds) > 0) {
            $bookingsByLoc = DB::table('gymies_bookings')
                ->whereIn('gym_location_id', $locationIds)
                ->whereIn('status', ['pending', 'confirmed', 'reserved'])
                ->where('scheduled_at', '<', $endAt)
                ->whereRaw('DATE_ADD(scheduled_at, INTERVAL COALESCE(duration_minutes, 60) MINUTE) > ?', [$startAt])
                ->get(['id', 'gym_location_id', 'scheduled_at', 'duration_minutes'])
                ->groupBy('gym_location_id');
        }

        $data = [];
        foreach ($locations as $loc) {
            $conflicts = [];
            foreach ($blocksByLoc->get($loc->id, []) as $b) {
                $conflicts[] = ['type' => 'block', 'start_at' => $b->start_at, 'end_at' => $b->end_at, 'reason' => $b->reason ?? null];
            }
            foreach ($sessionsByLoc->get($loc->id, []) as $s) {
                $conflicts[] = ['type' => 'group_session', 'id' => (string) $s->id, 'title' => $s->title ?? '', 'start_at' => $s->scheduled_at];
            }
            foreach ($bookingsByLoc->get($loc->id, []) as $b) {
                $conflicts[] = ['type' => 'booking', 'id' => (string) $b->id, 'start_at' => $b->scheduled_at, 'duration_minutes' => (int) $b->duration_minutes];
            }
            $data[] = [
                'id' => (string) $loc->id,
                'name' => (string) $loc->name,
                'location_type' => (string) ($loc->location_type ?? 'zaal'),
                'capacity' => $loc->capacity !== null ? (int) $loc->capacity : null,
                'status' => count($conflicts) === 0 ? 'vrij' : 'bezet',
                'conflicts' => $conflicts,
            ];
        }

        return response()->json([
            'data' => $data,
            'start_at' => $startAt,
            'end_at' => $endAt,
        ]);
    }

    public function dashboardStats(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $orgId = (int) $ctx['organisation_id'];
        $period = trim((string) $request->query('period', 'month'));
        if (!in_array($period, ['week', 'month', 'year'], true)) {
            $period = 'month';
        }
        $compare = $request->boolean('compare', true);

        [$currentStart, $currentEnd] = $this->periodBounds($period, now());
        [$prevStart, $prevEnd] = $this->previousPeriodBounds($currentStart, $currentEnd);

        $current = $this->collectBookingStats($orgId, $currentStart, $currentEnd);
        $previous = $compare ? $this->collectBookingStats($orgId, $prevStart, $prevEnd) : null;

        $growth = null;
        if ($previous !== null) {
            $growth = [
                'gross_pct' => $this->percentGrowth((int) $current['gross_cents'], (int) $previous['gross_cents']),
                'bookings_pct' => $this->percentGrowth((int) $current['bookings_count'], (int) $previous['bookings_count']),
                'net_pct' => $this->percentGrowth((int) $current['net_cents'], (int) $previous['net_cents']),
            ];
        }

        $topTrainers = DB::table('gymies_bookings as b')
            ->join('gymies_users as u', 'u.id', '=', 'b.trainer_user_id')
            ->where('b.organisation_id', $orgId)
            ->whereBetween('b.scheduled_at', [$currentStart, $currentEnd])
            ->whereIn('b.status', ['confirmed', 'completed', 'no_show'])
            ->whereNotNull('b.paid_at')
            ->groupBy('b.trainer_user_id', 'u.display_name', 'u.email')
            ->selectRaw('b.trainer_user_id')
            ->selectRaw('COALESCE(u.display_name, u.email, "Trainer") as trainer_name')
            ->selectRaw('COUNT(*) as lessons_count')
            ->selectRaw('COALESCE(SUM(b.amount_cents), 0) as gross_cents')
            ->orderByDesc('gross_cents')
            ->limit(5)
            ->get()
            ->map(fn ($row) => [
                'trainer_user_id' => (string) $row->trainer_user_id,
                'trainer_name' => (string) $row->trainer_name,
                'lessons_count' => (int) $row->lessons_count,
                'gross_cents' => (int) $row->gross_cents,
                'platform_fee_cents' => (int) round(((int) $row->gross_cents) * 0.12),
                'net_cents' => max((int) $row->gross_cents - (int) round(((int) $row->gross_cents) * 0.12), 0),
            ])
            ->values()
            ->all();

        $now = now();
        $todayStart = $now->copy()->startOfDay();
        $todayEnd = $now->copy()->endOfDay();
        $todayRows = DB::table('gymies_bookings as b')
            ->join('gymies_users as trainer', 'trainer.id', '=', 'b.trainer_user_id')
            ->join('gymies_users as client', 'client.id', '=', 'b.client_user_id')
            ->where('b.organisation_id', $orgId)
            ->whereBetween('b.scheduled_at', [$todayStart, $todayEnd])
            ->orderBy('b.scheduled_at')
            ->get([
                'b.id',
                'b.trainer_user_id',
                'b.client_user_id',
                'b.scheduled_at',
                'b.duration_minutes',
                'b.status',
                'b.amount_cents',
                'b.paid_at',
                DB::raw('COALESCE(trainer.display_name, trainer.email, "Trainer") as trainer_name'),
                'trainer.phone as trainer_phone',
                DB::raw('COALESCE(client.display_name, client.email, "Klant") as client_name'),
            ]);

        $trainersLiveNow = $todayRows->filter(function ($row) use ($now): bool {
            if (!in_array((string) $row->status, ['pending', 'confirmed', 'completed'], true)) {
                return false;
            }
            $start = \Illuminate\Support\Carbon::parse((string) $row->scheduled_at);
            $end = $start->copy()->addMinutes((int) $row->duration_minutes);

            return $now->between($start, $end);
        })->pluck('trainer_user_id')->unique()->count();

        $todayRevenue = (int) $todayRows
            ->filter(fn ($r) => in_array((string) $r->status, ['confirmed', 'completed', 'no_show'], true) && !empty($r->paid_at))
            ->sum('amount_cents');
        $todayNoShows = $todayRows->where('status', 'no_show')->count();

        $openSettlements = Schema::hasTable('gymies_organisation_settlements')
            ? (int) DB::table('gymies_organisation_settlements')
                ->where('organisation_id', $orgId)
                ->whereIn('status', ['draft', 'approved'])
                ->count()
            : 0;

        $noShowFollowups = (int) DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->where('status', 'no_show')
            ->where('scheduled_at', '>=', now()->copy()->subDays(14))
            ->count();

        $trainersWithoutAvailability = (int) DB::table('gymies_organisation_trainers as ot')
            ->leftJoin('gymies_trainer_profiles as p', 'p.user_id', '=', 'ot.trainer_user_id')
            ->where('ot.organisation_id', $orgId)
            ->where('ot.status', 'active')
            ->where(function ($q): void {
                $q->whereNull('p.is_available')->orWhere('p.is_available', 0);
            })
            ->count();

        $this->ensureAlertStateTable();
        $alertRows = Schema::hasTable('gymies_organisation_alert_states')
            ? DB::table('gymies_organisation_alert_states')
                ->where('organisation_id', $orgId)
                ->get(['alert_key', 'status'])
            : collect();
        $alertMap = [];
        foreach ($alertRows as $alertRow) {
            $alertMap[(string) $alertRow->alert_key] = (string) $alertRow->status;
        }
        $actionCenter = [
            [
                'key' => 'open_settlements',
                'title' => 'Open settlements',
                'priority' => $openSettlements > 0 ? 'high' : 'low',
                'count' => $openSettlements,
            ],
            [
                'key' => 'no_show_followups',
                'title' => 'No-show follow-ups',
                'priority' => $noShowFollowups > 0 ? 'high' : 'low',
                'count' => $noShowFollowups,
            ],
            [
                'key' => 'trainers_without_availability',
                'title' => 'Trainers zonder beschikbaarheid',
                'priority' => $trainersWithoutAvailability > 0 ? 'medium' : 'low',
                'count' => $trainersWithoutAvailability,
            ],
            [
                'key' => 'expired_payment_method',
                'title' => 'Verlopen betaalmethode',
                'priority' => 'low',
                'count' => 0,
            ],
        ];
        $actionCenter = array_map(function (array $item) use ($alertMap): array {
            $status = $alertMap[$item['key']] ?? 'open';
            $item['status'] = $status;

            return $item;
        }, $actionCenter);

        $trainerScorecards = DB::table('gymies_organisation_trainers as ot')
            ->join('gymies_users as u', 'u.id', '=', 'ot.trainer_user_id')
            ->where('ot.organisation_id', $orgId)
            ->get(['ot.trainer_user_id', DB::raw('COALESCE(u.display_name, u.email, "Trainer") as trainer_name')])
            ->map(function ($trainer) use ($orgId, $currentStart, $currentEnd, $prevStart, $prevEnd): array {
                $trainerId = (int) $trainer->trainer_user_id;
                $currentRows = DB::table('gymies_bookings')
                    ->where('organisation_id', $orgId)
                    ->where('trainer_user_id', $trainerId)
                    ->whereBetween('scheduled_at', [$currentStart, $currentEnd])
                    ->get(['status', 'amount_cents', 'paid_at']);
                $previousRows = DB::table('gymies_bookings')
                    ->where('organisation_id', $orgId)
                    ->where('trainer_user_id', $trainerId)
                    ->whereBetween('scheduled_at', [$prevStart, $prevEnd])
                    ->get(['status', 'amount_cents', 'paid_at']);

                $lessons = $currentRows->count();
                $revenueRows = $currentRows->filter(fn ($r) => in_array((string) $r->status, ['confirmed', 'completed', 'no_show'], true) && !empty($r->paid_at));
                $gross = (int) $revenueRows->sum('amount_cents');
                $cancelRate = $lessons > 0 ? round(($currentRows->where('status', 'cancelled')->count() / $lessons) * 100, 2) : 0.0;
                $noShowRate = $lessons > 0 ? round(($currentRows->where('status', 'no_show')->count() / $lessons) * 100, 2) : 0.0;
                $avgReview = 4.6;

                $previousGross = (int) $previousRows
                    ->filter(fn ($r) => in_array((string) $r->status, ['confirmed', 'completed', 'no_show'], true) && !empty($r->paid_at))
                    ->sum('amount_cents');
                $trend = $this->percentGrowth($gross, $previousGross);

                return [
                    'trainer_user_id' => (string) $trainerId,
                    'trainer_name' => (string) $trainer->trainer_name,
                    'lessons_count' => $lessons,
                    'gross_cents' => $gross,
                    'cancel_rate_pct' => $cancelRate,
                    'no_show_rate_pct' => $noShowRate,
                    'avg_review' => $avgReview,
                    'trend_pct' => $trend,
                ];
            })
            ->sortByDesc('gross_cents')
            ->values()
            ->all();

        $heatRows = DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->whereBetween('scheduled_at', [now()->copy()->subDays(30), now()->copy()->addDays(30)])
            ->get(['scheduled_at', 'status']);
        $heatmap = [];
        foreach ($heatRows as $heatRow) {
            $dt = \Illuminate\Support\Carbon::parse((string) $heatRow->scheduled_at);
            $key = $dt->dayOfWeek . '-' . $dt->hour;
            $heatmap[$key] = ($heatmap[$key] ?? 0) + 1;
        }
        arsort($heatmap);
        $capacitySuggestions = [];
        foreach (array_slice($heatmap, 0, 3, true) as $slot => $count) {
            [$day, $hour] = explode('-', $slot);
            $capacitySuggestions[] = [
                'slot' => $slot,
                'day_of_week' => (int) $day,
                'hour' => (int) $hour,
                'bookings_count' => (int) $count,
                'suggestion' => 'Zet extra trainer op dit piekblok.',
            ];
        }

        $clientAggRows = DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->groupBy('client_user_id')
            ->selectRaw('client_user_id')
            ->selectRaw('MIN(scheduled_at) as first_booking_at')
            ->selectRaw('MAX(scheduled_at) as last_booking_at')
            ->selectRaw('COUNT(*) as bookings_count')
            ->get();
        $newClients = 0;
        $returningClients = 0;
        $inactiveOver30 = 0;
        foreach ($clientAggRows as $clientAgg) {
            $first = \Illuminate\Support\Carbon::parse((string) $clientAgg->first_booking_at);
            $last = \Illuminate\Support\Carbon::parse((string) $clientAgg->last_booking_at);
            if ($first->between($currentStart, $currentEnd)) {
                $newClients++;
            } else {
                $returningClients++;
            }
            if ($last->lt(now()->copy()->subDays(30))) {
                $inactiveOver30++;
            }
        }

        $bookingQuality = [
            'requested_count' => (int) ($current['bookings_count'] ?? 0),
            'pending_count' => (int) ($current['pending_count'] ?? 0),
            'confirmed_count' => (int) ($current['confirmed_count'] ?? 0),
            'completed_count' => (int) ($current['completed_count'] ?? 0),
            'cancelled_count' => (int) ($current['cancelled_count'] ?? 0),
            'no_show_count' => (int) ($current['no_show_count'] ?? 0),
            'cancel_no_show_breakdown' => [
                ['reason' => 'cancelled', 'count' => (int) ($current['cancelled_count'] ?? 0)],
                ['reason' => 'no_show', 'count' => (int) ($current['no_show_count'] ?? 0)],
            ],
        ];

        $locationOccupancy = [];
        if (Schema::hasTable('gym_locations')) {
            $locMap = [];
            if (Schema::hasColumn('gymies_bookings', 'gym_location_id')) {
                $locRows = DB::table('gymies_bookings as b')
                    ->leftJoin('gym_locations as gl', 'b.gym_location_id', '=', 'gl.id')
                    ->where('b.organisation_id', $orgId)
                    ->whereBetween('b.scheduled_at', [$currentStart, $currentEnd])
                    ->whereIn('b.status', ['confirmed', 'completed', 'no_show', 'pending'])
                    ->groupBy('b.gym_location_id', 'gl.name')
                    ->selectRaw('b.gym_location_id')
                    ->selectRaw('COALESCE(gl.name, "Geen locatie") as location_name')
                    ->selectRaw('COUNT(*) as bookings_count')
                    ->get();
                foreach ($locRows as $lr) {
                    $key = $lr->gym_location_id ?? 'none';
                    $locMap[$key] = [
                        'gym_location_id' => $lr->gym_location_id ? (string) $lr->gym_location_id : null,
                        'location_name' => (string) $lr->location_name,
                        'bookings_count' => (int) $lr->bookings_count,
                        'group_sessions_count' => 0,
                    ];
                }
            }
            if (Schema::hasTable('gymies_group_sessions') && Schema::hasColumn('gymies_group_sessions', 'gym_location_id')) {
                $gsRows = DB::table('gymies_group_sessions as gs')
                    ->leftJoin('gym_locations as gl', 'gs.gym_location_id', '=', 'gl.id')
                    ->where('gs.organisation_id', $orgId)
                    ->whereBetween('gs.scheduled_at', [$currentStart, $currentEnd])
                    ->groupBy('gs.gym_location_id', 'gl.name')
                    ->selectRaw('gs.gym_location_id')
                    ->selectRaw('COALESCE(gl.name, "Geen locatie") as location_name')
                    ->selectRaw('COUNT(*) as group_sessions_count')
                    ->get();
                foreach ($gsRows as $gs) {
                    $key = $gs->gym_location_id ?? 'none';
                    if (!isset($locMap[$key])) {
                        $locMap[$key] = [
                            'gym_location_id' => $gs->gym_location_id ? (string) $gs->gym_location_id : null,
                            'location_name' => (string) $gs->location_name,
                            'bookings_count' => 0,
                            'group_sessions_count' => 0,
                        ];
                    }
                    $locMap[$key]['group_sessions_count'] = (int) $gs->group_sessions_count;
                }
            }
            $locationOccupancy = array_values($locMap);
            usort($locationOccupancy, fn ($a, $b) => ($b['bookings_count'] + $b['group_sessions_count']) <=> ($a['bookings_count'] + $a['group_sessions_count']));
        }

        return response()->json([
            'data' => [
                'period' => $period,
                'period_start' => $currentStart->toDateTimeString(),
                'period_end' => $currentEnd->toDateTimeString(),
                'current' => $current,
                'previous' => $previous,
                'growth' => $growth,
                'top_trainers' => $topTrainers,
                'today_overview' => [
                    'sessions_count' => $todayRows->count(),
                    'no_show_count' => $todayNoShows,
                    'revenue_cents' => $todayRevenue,
                    'trainers_live_now' => $trainersLiveNow,
                ],
                'today_bookings' => $todayRows->map(fn ($b) => [
                    'id' => (string) $b->id,
                    'trainer_user_id' => (string) $b->trainer_user_id,
                    'trainer_name' => (string) $b->trainer_name,
                    'trainer_phone' => $b->trainer_phone ? (string) $b->trainer_phone : null,
                    'client_user_id' => (string) $b->client_user_id,
                    'client_name' => (string) $b->client_name,
                    'scheduled_at' => (string) $b->scheduled_at,
                    'duration_minutes' => (int) $b->duration_minutes,
                    'status' => (string) $b->status,
                    'amount_cents' => $b->amount_cents ? (int) $b->amount_cents : 0,
                ])->values()->all(),
                'action_center' => $actionCenter,
                'trainer_scorecards' => $trainerScorecards,
                'capacity_heatmap' => $heatmap,
                'capacity_suggestions' => $capacitySuggestions,
                'client_retention' => [
                    'new_clients_count' => $newClients,
                    'returning_clients_count' => $returningClients,
                    'inactive_30d_count' => $inactiveOver30,
                ],
                'booking_quality' => $bookingQuality,
                'location_occupancy' => $locationOccupancy,
            ],
        ]);
    }

    public function trainers(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        $orgId = (int) $ctx['organisation_id'];

        $rows = DB::table('gymies_organisation_trainers as ot')
            ->join('gymies_users as u', 'u.id', '=', 'ot.trainer_user_id')
            ->leftJoin('gymies_trainer_profiles as p', 'p.user_id', '=', 'u.id')
            ->where('ot.organisation_id', $orgId)
            ->orderByDesc('ot.is_primary')
            ->orderBy('u.display_name')
            ->select(
                'ot.id',
                'ot.trainer_user_id',
                'ot.status',
                'ot.is_primary',
                'ot.employment_type',
                'ot.payout_route',
                'ot.active_from',
                'ot.active_until',
                'u.display_name',
                'u.email',
                'p.specialty',
                'p.region',
                'p.is_available',
                'p.avatar_url'
            )
            ->get();

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'trainer_user_id' => (string) $r->trainer_user_id,
            'display_name' => (string) ($r->display_name ?? $r->email ?? 'Trainer'),
            'email' => (string) ($r->email ?? ''),
            'specialty' => $r->specialty,
            'region' => $r->region,
            'avatar_url' => $r->avatar_url,
            'is_available' => $r->is_available === null ? null : (bool) $r->is_available,
            'status' => (string) $r->status,
            'is_primary' => (bool) $r->is_primary,
            'employment_type' => (string) $r->employment_type,
            'payout_route' => (string) $r->payout_route,
            'active_from' => $r->active_from,
            'active_until' => $r->active_until,
        ])->all();

        return response()->json(['data' => $data]);
    }

    public function updateTrainerStatus(Request $request, string $trainerUserId): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!$this->isPositiveIntegerId($trainerUserId)) {
            return response()->json(['message' => 'Ongeldige trainer id.'], 422);
        }

        $request->validate([
            'status' => 'required|in:active,inactive',
        ]);

        $orgId = (int) $ctx['organisation_id'];
        $trainerId = (int) $trainerUserId;
        $targetStatus = (string) $request->input('status');

        $membership = DB::table('gymies_organisation_trainers')
            ->where('organisation_id', $orgId)
            ->where('trainer_user_id', $trainerId)
            ->first();
        if (!$membership) {
            return response()->json(['message' => 'Trainer niet gevonden binnen deze organisatie.'], 404);
        }

        $currentStatus = (string) $membership->status;
        if ($currentStatus === $targetStatus) {
            return response()->json([
                'data' => [
                    'trainer_user_id' => (string) $trainerId,
                    'status' => $targetStatus,
                ],
            ]);
        }

        $updatePayload = [
            'status' => $targetStatus,
            'updated_at' => now(),
        ];
        if ($targetStatus === 'active') {
            $updatePayload['active_from'] = now()->toDateString();
            $updatePayload['active_until'] = null;
        } else {
            $updatePayload['active_until'] = now()->toDateString();
        }

        DB::table('gymies_organisation_trainers')
            ->where('organisation_id', $orgId)
            ->where('trainer_user_id', $trainerId)
            ->update($updatePayload);

        if (Schema::hasTable('gymies_trainer_profiles')) {
            DB::table('gymies_trainer_profiles')
                ->where('user_id', $trainerId)
                ->update([
                    'is_available' => $targetStatus === 'active' ? 1 : 0,
                    'updated_at' => now(),
                ]);
        }

        $this->logAudit((int) $ctx['user_id'], 'gym_trainer_status_updated', 'organisation_trainer', (int) $membership->id, [
            'status' => $currentStatus,
        ], [
            'status' => $targetStatus,
            'trainer_user_id' => $trainerId,
            'organisation_id' => $orgId,
        ]);

        return response()->json([
            'data' => [
                'trainer_user_id' => (string) $trainerId,
                'status' => $targetStatus,
            ],
        ]);
    }

    public function addTrainer(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $request->validate([
            'trainer_user_id' => 'nullable|integer|min:1',
            'email' => 'nullable|email|max:255',
            'display_name' => 'nullable|string|max:255',
            'employment_type' => 'nullable|in:employee,contractor',
            'payout_route' => 'nullable|in:direct_trainer,via_organisation',
            'is_primary' => 'nullable|boolean',
        ]);
        if (!$request->filled('trainer_user_id') && !$request->filled('email')) {
            return response()->json(['message' => 'trainer_user_id of email is verplicht.'], 422);
        }

        $orgId = (int) $ctx['organisation_id'];
        $now = now();

        $trainerUserId = null;
        if ($request->filled('trainer_user_id')) {
            $trainerUserId = (int) $request->input('trainer_user_id');
        } else {
            $email = strtolower(trim((string) $request->input('email')));
            $user = DB::table('gymies_users')->where('email', $email)->first();
            if ($user) {
                $trainerUserId = (int) $user->id;
                if ((string) $user->role !== 'trainer') {
                    DB::table('gymies_users')->where('id', $trainerUserId)->update([
                        'role' => 'trainer',
                        'updated_at' => $now,
                    ]);
                }
            } else {
                $randomPass = bin2hex(random_bytes(6)) . 'A!';
                $trainerUserId = (int) DB::table('gymies_users')->insertGetId([
                    'email' => $email,
                    'password_hash' => password_hash($randomPass, PASSWORD_BCRYPT),
                    'role' => 'trainer',
                    'display_name' => trim((string) $request->input('display_name', $email)),
                    'email_verified_at' => $now,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            }
        }

        $existing = DB::table('gymies_organisation_trainers')
            ->where('organisation_id', $orgId)
            ->where('trainer_user_id', $trainerUserId)
            ->first();
        $payload = [
            'employment_type' => (string) $request->input('employment_type', 'employee'),
            'payout_route' => (string) $request->input('payout_route', 'via_organisation'),
            'is_primary' => $request->boolean('is_primary', false) ? 1 : 0,
            'status' => 'active',
            'active_from' => $now->toDateString(),
            'active_until' => null,
            'updated_at' => $now,
        ];

        if ($existing) {
            DB::table('gymies_organisation_trainers')
                ->where('id', $existing->id)
                ->update($payload);
        } else {
            DB::table('gymies_organisation_trainers')->insert([
                'organisation_id' => $orgId,
                'trainer_user_id' => $trainerUserId,
                'employment_type' => $payload['employment_type'],
                'payout_route' => $payload['payout_route'],
                'is_primary' => $payload['is_primary'],
                'status' => 'active',
                'active_from' => $payload['active_from'],
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        $this->logAudit((int) $ctx['user_id'], 'gym_trainer_added', 'organisation', $orgId, null, [
            'trainer_user_id' => $trainerUserId,
            'employment_type' => $payload['employment_type'],
            'payout_route' => $payload['payout_route'],
            'is_primary' => (bool) $payload['is_primary'],
        ]);

        return response()->json([
            'data' => [
                'trainer_user_id' => (string) $trainerUserId,
                'status' => 'active',
            ],
        ], 201);
    }

    public function inviteMember(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        $request->validate([
            'email' => 'required|email|max:255',
            'display_name' => 'nullable|string|max:255',
            'role' => 'required|in:owner,manager,viewer',
        ]);
        if ((string) $ctx['member_role'] !== 'owner' && (string) $request->input('role') === 'owner') {
            return response()->json(['message' => 'Alleen owners mogen owner rechten toekennen.'], 403);
        }

        $orgId = (int) $ctx['organisation_id'];
        $email = strtolower(trim((string) $request->input('email')));
        $role = (string) $request->input('role');
        $now = now();

        $user = DB::table('gymies_users')->where('email', $email)->first();
        if (!$user) {
            $randomPass = bin2hex(random_bytes(6)) . 'A!';
            $userId = (int) DB::table('gymies_users')->insertGetId([
                'email' => $email,
                'password_hash' => password_hash($randomPass, PASSWORD_BCRYPT),
                'role' => 'klant',
                'display_name' => trim((string) $request->input('display_name', $email)),
                'email_verified_at' => $now,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        } else {
            $userId = (int) $user->id;
        }

        $existing = DB::table('gymies_organisation_members')
            ->where('organisation_id', $orgId)
            ->where('user_id', $userId)
            ->first();
        if ($existing) {
            DB::table('gymies_organisation_members')
                ->where('id', $existing->id)
                ->update([
                    'role' => $role,
                    'status' => 'active',
                    'updated_at' => $now,
                ]);
        } else {
            DB::table('gymies_organisation_members')->insert([
                'organisation_id' => $orgId,
                'user_id' => $userId,
                'role' => $role,
                'status' => 'active',
                'invited_at' => $now,
                'joined_at' => $now,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        return response()->json([
            'data' => [
                'user_id' => (string) $userId,
                'email' => $email,
                'role' => $role,
                'status' => 'active',
            ],
        ], 201);
    }

    public function updateMemberRole(Request $request, string $userId): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!$this->isPositiveIntegerId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $request->validate([
            'role' => 'required|in:owner,manager,viewer',
        ]);
        $orgId = (int) $ctx['organisation_id'];
        $memberUserId = (int) $userId;
        $targetRole = (string) $request->input('role');

        if ((string) $ctx['member_role'] !== 'owner' && $targetRole === 'owner') {
            return response()->json(['message' => 'Alleen owners mogen owner rechten toekennen.'], 403);
        }

        $member = DB::table('gymies_organisation_members')
            ->where('organisation_id', $orgId)
            ->where('user_id', $memberUserId)
            ->first();
        if (!$member) {
            return response()->json(['message' => 'Teamlid niet gevonden.'], 404);
        }

        DB::table('gymies_organisation_members')
            ->where('id', $member->id)
            ->update([
                'role' => $targetRole,
                'updated_at' => now(),
            ]);

        return response()->json([
            'data' => [
                'user_id' => (string) $memberUserId,
                'role' => $targetRole,
            ],
        ]);
    }

    public function updateMemberStatus(Request $request, string $userId): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!$this->isPositiveIntegerId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $request->validate([
            'status' => 'required|in:active,inactive',
        ]);
        $orgId = (int) $ctx['organisation_id'];
        $memberUserId = (int) $userId;
        $targetStatus = (string) $request->input('status');

        $member = DB::table('gymies_organisation_members')
            ->where('organisation_id', $orgId)
            ->where('user_id', $memberUserId)
            ->first();
        if (!$member) {
            return response()->json(['message' => 'Teamlid niet gevonden.'], 404);
        }

        if ((string) $member->role === 'owner' && $targetStatus === 'inactive') {
            $activeOwners = DB::table('gymies_organisation_members')
                ->where('organisation_id', $orgId)
                ->where('role', 'owner')
                ->where('status', 'active')
                ->count();
            if ($activeOwners <= 1) {
                return response()->json(['message' => 'Minimaal één actieve owner is verplicht.'], 422);
            }
        }

        DB::table('gymies_organisation_members')
            ->where('id', $member->id)
            ->update([
                'status' => $targetStatus,
                'updated_at' => now(),
            ]);

        return response()->json([
            'data' => [
                'user_id' => (string) $memberUserId,
                'status' => $targetStatus,
            ],
        ]);
    }

    public function bookings(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $orgId = (int) $ctx['organisation_id'];
        $status = trim((string) $request->query('status', ''));
        $trainerUserId = trim((string) $request->query('trainer_user_id', ''));
        $clientSearch = trim((string) $request->query('client_search', ''));
        $periodStart = trim((string) $request->query('period_start', ''));
        $periodEnd = trim((string) $request->query('period_end', ''));
        $limit = (int) $request->query('limit', 200);
        if ($limit < 1) {
            $limit = 50;
        }
        if ($limit > 500) {
            $limit = 500;
        }

        $query = DB::table('gymies_bookings as b')
            ->join('gymies_users as trainer', 'trainer.id', '=', 'b.trainer_user_id')
            ->join('gymies_users as client', 'client.id', '=', 'b.client_user_id')
            ->where('b.organisation_id', $orgId)
            ->select(
                'b.id',
                'b.client_user_id',
                'b.trainer_user_id',
                'b.scheduled_at',
                'b.duration_minutes',
                'b.status',
                'b.amount_cents',
                'b.paid_at',
                'b.payout_route',
                'trainer.display_name as trainer_name',
                'client.display_name as client_name'
            )
            ->orderByDesc('b.scheduled_at');

        if ($status !== '') {
            $query->where('b.status', $status);
        }
        if ($trainerUserId !== '') {
            $query->where('b.trainer_user_id', $trainerUserId);
        }
        if ($clientSearch !== '') {
            $query->where(function ($q) use ($clientSearch): void {
                $q->where('client.display_name', 'like', '%' . $clientSearch . '%')
                    ->orWhere('client.email', 'like', '%' . $clientSearch . '%');
            });
        }
        if ($periodStart !== '') {
            $query->where('b.scheduled_at', '>=', $periodStart . ' 00:00:00');
        }
        if ($periodEnd !== '') {
            $query->where('b.scheduled_at', '<=', $periodEnd . ' 23:59:59');
        }

        $rows = $query->limit($limit)->get();
        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'client_user_id' => (string) $r->client_user_id,
            'trainer_user_id' => (string) $r->trainer_user_id,
            'trainer_name' => $r->trainer_name ?? 'Trainer',
            'client_name' => $r->client_name ?? 'Klant',
            'scheduled_at' => $r->scheduled_at,
            'duration_minutes' => (int) $r->duration_minutes,
            'status' => $r->status,
            'amount_cents' => $r->amount_cents ? (int) $r->amount_cents : null,
            'paid_at' => $r->paid_at,
            'payout_route' => $r->payout_route ?? 'direct_trainer',
        ])->all();

        return response()->json(['data' => $data]);
    }

    public function bookingsStats(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        $orgId = (int) $ctx['organisation_id'];

        $periodStart = trim((string) $request->query('period_start', ''));
        $periodEnd = trim((string) $request->query('period_end', ''));
        $start = $periodStart !== '' ? date_create($periodStart . ' 00:00:00') : now()->startOfMonth();
        $end = $periodEnd !== '' ? date_create($periodEnd . ' 23:59:59') : now()->endOfMonth();
        if (!$start || !$end) {
            return response()->json(['message' => 'Ongeldige periode.'], 422);
        }
        $startTs = \Illuminate\Support\Carbon::parse($start);
        $endTs = \Illuminate\Support\Carbon::parse($end);

        $stats = $this->collectBookingStats($orgId, $startTs, $endTs);

        return response()->json([
            'data' => [
                'period_start' => $startTs->toDateTimeString(),
                'period_end' => $endTs->toDateTimeString(),
                'bookings_count' => $stats['bookings_count'],
                'pending_count' => $stats['pending_count'],
                'confirmed_count' => $stats['confirmed_count'],
                'completed_count' => $stats['completed_count'],
                'cancelled_count' => $stats['cancelled_count'],
                'no_show_count' => $stats['no_show_count'],
                'gross_cents' => $stats['gross_cents'],
                'platform_fee_cents' => $stats['platform_fee_cents'],
                'net_cents' => $stats['net_cents'],
                'average_booking_cents' => $stats['average_booking_cents'],
                'cancellation_rate_pct' => $stats['cancellation_rate_pct'],
                'location_type_counts' => $stats['location_type_counts'],
            ],
        ]);
    }

    public function bookingDetail(Request $request, string $id): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        $orgId = (int) $ctx['organisation_id'];

        $row = DB::table('gymies_bookings as b')
            ->join('gymies_users as trainer', 'trainer.id', '=', 'b.trainer_user_id')
            ->join('gymies_users as client', 'client.id', '=', 'b.client_user_id')
            ->where('b.id', $id)
            ->where('b.organisation_id', $orgId)
            ->select(
                'b.*',
                'trainer.display_name as trainer_name',
                'trainer.email as trainer_email',
                'client.display_name as client_name',
                'client.email as client_email'
            )
            ->first();
        if (!$row) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        return response()->json([
            'data' => [
                'id' => (string) $row->id,
                'client_user_id' => (string) $row->client_user_id,
                'client_name' => (string) ($row->client_name ?? $row->client_email ?? 'Klant'),
                'client_email' => (string) ($row->client_email ?? ''),
                'trainer_user_id' => (string) $row->trainer_user_id,
                'trainer_name' => (string) ($row->trainer_name ?? $row->trainer_email ?? 'Trainer'),
                'trainer_email' => (string) ($row->trainer_email ?? ''),
                'scheduled_at' => $row->scheduled_at,
                'duration_minutes' => (int) $row->duration_minutes,
                'status' => (string) $row->status,
                'amount_cents' => $row->amount_cents ? (int) $row->amount_cents : null,
                'paid_at' => $row->paid_at,
                'payout_route' => $row->payout_route ?? 'direct_trainer',
                'location_type' => $row->location_type,
                'location_notes' => $row->location_notes,
                'client_notes' => $row->client_notes,
                'trainer_notes' => $row->trainer_notes,
            ],
        ]);
    }

    public function settlements(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        $orgId = (int) $ctx['organisation_id'];
        if (!Schema::hasTable('gymies_organisation_settlements')) {
            return response()->json(['data' => []]);
        }

        $rows = DB::table('gymies_organisation_settlements')
            ->where('organisation_id', $orgId)
            ->orderByDesc('period_start')
            ->limit(50)
            ->get();

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'period_start' => (string) $r->period_start,
            'period_end' => (string) $r->period_end,
            'gross_cents' => (int) $r->gross_cents,
            'fee_cents' => (int) $r->fee_cents,
            'adjustments_cents' => (int) $r->adjustments_cents,
            'net_cents' => (int) $r->net_cents,
            'status' => (string) $r->status,
            'approved_at' => $r->approved_at,
            'paid_at' => $r->paid_at,
            'reconciled_at' => $r->reconciled_at,
            'payout_reference' => $r->payout_reference,
        ])->all();

        return response()->json(['data' => $data]);
    }

    public function settlementDetail(Request $request, string $id): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        $orgId = (int) $ctx['organisation_id'];
        if (!Schema::hasTable('gymies_organisation_settlements')) {
            return response()->json(['message' => 'Settlement tabel ontbreekt op deze omgeving.'], 422);
        }

        $settlement = DB::table('gymies_organisation_settlements')
            ->where('id', $id)
            ->where('organisation_id', $orgId)
            ->first();
        if (!$settlement) {
            return response()->json(['message' => 'Settlement niet gevonden.'], 404);
        }

        $lines = [];
        $byTrainer = [];
        if (Schema::hasTable('gymies_organisation_settlement_lines')) {
            $lineRows = DB::table('gymies_organisation_settlement_lines as l')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'l.trainer_user_id')
                ->where('l.settlement_id', $id)
                ->select(
                    'l.id',
                    'l.booking_id',
                    'l.trainer_user_id',
                    'l.line_type',
                    'l.gross_cents',
                    'l.platform_fee_cents',
                    'l.adjustment_cents',
                    'l.net_cents',
                    'l.metadata_json',
                    'l.created_at',
                    DB::raw('COALESCE(u.display_name, u.email, "Trainer") as trainer_name')
                )
                ->orderByDesc('l.id')
                ->get();

            $lines = $lineRows->map(fn ($l) => [
                'id' => (string) $l->id,
                'booking_id' => $l->booking_id ? (string) $l->booking_id : null,
                'trainer_user_id' => $l->trainer_user_id ? (string) $l->trainer_user_id : null,
                'trainer_name' => $l->trainer_name,
                'line_type' => (string) $l->line_type,
                'gross_cents' => (int) $l->gross_cents,
                'platform_fee_cents' => (int) $l->platform_fee_cents,
                'adjustment_cents' => (int) $l->adjustment_cents,
                'net_cents' => (int) $l->net_cents,
                'metadata_json' => $l->metadata_json,
                'created_at' => $l->created_at,
            ])->all();

            $byTrainerRows = DB::table('gymies_organisation_settlement_lines as l')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'l.trainer_user_id')
                ->where('l.settlement_id', $id)
                ->whereNotNull('l.trainer_user_id')
                ->groupBy('l.trainer_user_id', 'u.display_name', 'u.email')
                ->selectRaw('l.trainer_user_id')
                ->selectRaw('COALESCE(u.display_name, u.email, "Trainer") as trainer_name')
                ->selectRaw('COALESCE(SUM(l.gross_cents), 0) as gross_cents')
                ->selectRaw('COALESCE(SUM(l.platform_fee_cents), 0) as platform_fee_cents')
                ->selectRaw('COALESCE(SUM(l.adjustment_cents), 0) as adjustment_cents')
                ->selectRaw('COALESCE(SUM(l.net_cents), 0) as net_cents')
                ->get();

            $byTrainer = $byTrainerRows->map(fn ($r) => [
                'trainer_user_id' => (string) $r->trainer_user_id,
                'trainer_name' => (string) $r->trainer_name,
                'gross_cents' => (int) $r->gross_cents,
                'platform_fee_cents' => (int) $r->platform_fee_cents,
                'adjustment_cents' => (int) $r->adjustment_cents,
                'net_cents' => (int) $r->net_cents,
            ])->all();
        }

        return response()->json([
            'data' => [
                'id' => (string) $settlement->id,
                'period_start' => (string) $settlement->period_start,
                'period_end' => (string) $settlement->period_end,
                'gross_cents' => (int) $settlement->gross_cents,
                'fee_cents' => (int) $settlement->fee_cents,
                'adjustments_cents' => (int) $settlement->adjustments_cents,
                'net_cents' => (int) $settlement->net_cents,
                'status' => (string) $settlement->status,
                'approved_at' => $settlement->approved_at,
                'paid_at' => $settlement->paid_at,
                'reconciled_at' => $settlement->reconciled_at,
                'payout_reference' => $settlement->payout_reference,
                'lines' => $lines,
                'by_trainer' => $byTrainer,
            ],
        ]);
    }

    public function trainerStats(Request $request, string $trainerUserId): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        $orgId = (int) $ctx['organisation_id'];
        $trainerId = (int) $trainerUserId;

        $membership = DB::table('gymies_organisation_trainers')
            ->where('organisation_id', $orgId)
            ->where('trainer_user_id', $trainerId)
            ->first();
        if (!$membership) {
            return response()->json(['message' => 'Trainer niet gevonden binnen deze organisatie.'], 404);
        }

        $periodStart = trim((string) $request->query('period_start', ''));
        $periodEnd = trim((string) $request->query('period_end', ''));
        $start = $periodStart !== '' ? date_create($periodStart . ' 00:00:00') : now()->startOfMonth();
        $end = $periodEnd !== '' ? date_create($periodEnd . ' 23:59:59') : now()->endOfMonth();
        if (!$start || !$end) {
            return response()->json(['message' => 'Ongeldige periode.'], 422);
        }
        $startTs = \Illuminate\Support\Carbon::parse($start);
        $endTs = \Illuminate\Support\Carbon::parse($end);

        $rows = DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->where('trainer_user_id', $trainerId)
            ->whereBetween('scheduled_at', [$startTs, $endTs])
            ->get(['status', 'amount_cents', 'paid_at']);

        $all = $rows->count();
        $completed = $rows->where('status', 'completed')->count();
        $confirmed = $rows->where('status', 'confirmed')->count();
        $cancelled = $rows->where('status', 'cancelled')->count();
        $revenueRows = $rows->filter(fn ($r) => in_array((string) $r->status, ['confirmed', 'completed', 'no_show'], true) && !empty($r->paid_at));
        $gross = (int) $revenueRows->sum('amount_cents');
        $fee = (int) round($gross * 0.12);
        $net = max($gross - $fee, 0);

        $completionRate = ($all > 0) ? round(($completed / $all) * 100, 2) : 0.0;
        $cancellationRate = ($all > 0) ? round(($cancelled / $all) * 100, 2) : 0.0;
        $avgBooking = $revenueRows->count() > 0 ? (int) round($gross / $revenueRows->count()) : 0;

        $trainer = DB::table('gymies_users')->where('id', $trainerId)->first(['display_name', 'email']);

        return response()->json([
            'data' => [
                'trainer_user_id' => (string) $trainerId,
                'trainer_name' => (string) ($trainer->display_name ?? $trainer->email ?? 'Trainer'),
                'period_start' => $startTs->toDateTimeString(),
                'period_end' => $endTs->toDateTimeString(),
                'bookings_total' => $all,
                'bookings_confirmed' => $confirmed,
                'bookings_completed' => $completed,
                'bookings_cancelled' => $cancelled,
                'gross_cents' => $gross,
                'platform_fee_cents' => $fee,
                'net_cents' => $net,
                'average_booking_cents' => $avgBooking,
                'completion_rate_pct' => $completionRate,
                'cancellation_rate_pct' => $cancellationRate,
            ],
        ]);
    }

    public function createSettlementDraft(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $request->validate([
            'period_start' => 'required|date',
            'period_end' => 'required|date|after_or_equal:period_start',
        ]);
        if (!Schema::hasTable('gymies_organisation_settlements') || !Schema::hasTable('gymies_organisation_settlement_lines')) {
            return response()->json(['message' => 'Settlement tabellen ontbreken op deze omgeving.'], 422);
        }

        $orgId = (int) $ctx['organisation_id'];
        $periodStart = (string) $request->input('period_start');
        $periodEnd = (string) $request->input('period_end');

        $existing = DB::table('gymies_organisation_settlements')
            ->where('organisation_id', $orgId)
            ->where('period_start', $periodStart)
            ->where('period_end', $periodEnd)
            ->first();
        if ($existing) {
            return response()->json(['message' => 'Voor deze periode bestaat al een settlement.'], 422);
        }

        $bookings = DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->whereBetween('scheduled_at', [$periodStart . ' 00:00:00', $periodEnd . ' 23:59:59'])
            ->whereIn('status', ['confirmed', 'completed'])
            ->whereNotNull('paid_at')
            ->get(['id', 'trainer_user_id', 'amount_cents']);

        $gross = (int) $bookings->sum('amount_cents');
        $fee = (int) round($gross * 0.12);
        $adjustments = 0;
        $net = max($gross - $fee + $adjustments, 0);

        $settlementId = DB::table('gymies_organisation_settlements')->insertGetId([
            'organisation_id' => $orgId,
            'period_start' => $periodStart,
            'period_end' => $periodEnd,
            'gross_cents' => $gross,
            'fee_cents' => $fee,
            'adjustments_cents' => $adjustments,
            'net_cents' => $net,
            'status' => 'draft',
            'created_by_user_id' => (int) $ctx['user_id'],
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        foreach ($bookings as $booking) {
            $lineGross = (int) ($booking->amount_cents ?? 0);
            $lineFee = (int) round($lineGross * 0.12);
            $lineNet = max($lineGross - $lineFee, 0);
            DB::table('gymies_organisation_settlement_lines')->insert([
                'settlement_id' => $settlementId,
                'booking_id' => (int) $booking->id,
                'trainer_user_id' => (int) $booking->trainer_user_id,
                'line_type' => 'booking',
                'gross_cents' => $lineGross,
                'platform_fee_cents' => $lineFee,
                'adjustment_cents' => 0,
                'net_cents' => $lineNet,
                'metadata_json' => json_encode(['source' => 'booking'], JSON_UNESCAPED_UNICODE),
                'created_at' => now(),
            ]);
        }

        $this->logAudit((int) $ctx['user_id'], 'gym_settlement_draft_created', 'organisation_settlement', $settlementId, null, [
            'organisation_id' => $orgId,
            'period_start' => $periodStart,
            'period_end' => $periodEnd,
        ]);

        return response()->json(['data' => ['id' => (string) $settlementId]], 201);
    }

    public function transitionSettlement(Request $request, string $id): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!$this->isPositiveIntegerId($id)) {
            return response()->json(['message' => 'Ongeldige settlement id.'], 422);
        }

        $request->validate([
            'action' => 'required|in:approve,pay,reconcile',
            'payout_reference' => 'nullable|string|max:255',
        ]);
        if (!Schema::hasTable('gymies_organisation_settlements')) {
            return response()->json(['message' => 'Settlement tabel ontbreekt op deze omgeving.'], 422);
        }

        $orgId = (int) $ctx['organisation_id'];
        $action = (string) $request->input('action');

        $settlement = DB::table('gymies_organisation_settlements')
            ->where('id', $id)
            ->where('organisation_id', $orgId)
            ->first();
        if (!$settlement) {
            return response()->json(['message' => 'Settlement niet gevonden.'], 404);
        }

        $current = (string) $settlement->status;
        $target = $current;
        $payload = ['updated_at' => now()];

        if ($action === 'approve' && $current === 'draft') {
            $target = 'approved';
            $payload['status'] = 'approved';
            $payload['approved_at'] = now();
        } elseif ($action === 'pay' && $current === 'approved') {
            $target = 'paid';
            $payload['status'] = 'paid';
            $payload['paid_at'] = now();
            if ($request->filled('payout_reference')) {
                $payload['payout_reference'] = (string) $request->input('payout_reference');
            }
        } elseif ($action === 'reconcile' && $current === 'paid') {
            $target = 'reconciled';
            $payload['status'] = 'reconciled';
            $payload['reconciled_at'] = now();
        } else {
            return response()->json(['message' => 'Ongeldige state-overgang.'], 422);
        }

        DB::table('gymies_organisation_settlements')
            ->where('id', $id)
            ->update($payload);

        $this->logAudit((int) $ctx['user_id'], 'gym_settlement_transition', 'organisation_settlement', (int) $id, [
            'status' => $current,
        ], [
            'status' => $target,
            'action' => $action,
        ]);

        return response()->json([
            'data' => [
                'id' => (string) $id,
                'status' => $target,
            ],
        ]);
    }

    public function addSettlementAdjustment(Request $request, string $id): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!$this->isPositiveIntegerId($id)) {
            return response()->json(['message' => 'Ongeldige settlement id.'], 422);
        }

        $request->validate([
            'line_type' => 'required|in:refund,chargeback,manual_adjustment',
            'gross_cents' => 'nullable|integer|min:0|max:100000000',
            'platform_fee_cents' => 'nullable|integer|min:0|max:100000000',
            'adjustment_cents' => 'required|integer|min:-100000000|max:100000000',
            'metadata' => 'nullable|array',
        ]);
        if (!Schema::hasTable('gymies_organisation_settlements') || !Schema::hasTable('gymies_organisation_settlement_lines')) {
            return response()->json(['message' => 'Settlement tabellen ontbreken op deze omgeving.'], 422);
        }

        $settlement = DB::table('gymies_organisation_settlements')
            ->where('id', $id)
            ->where('organisation_id', (int) $ctx['organisation_id'])
            ->first();
        if (!$settlement) {
            return response()->json(['message' => 'Settlement niet gevonden.'], 404);
        }
        if ((string) $settlement->status !== 'draft') {
            return response()->json(['message' => 'Alleen draft settlements mogen correctieposten krijgen.'], 422);
        }

        $gross = (int) $request->input('gross_cents', 0);
        $fee = (int) $request->input('platform_fee_cents', 0);
        $adjustment = (int) $request->input('adjustment_cents', 0);
        $net = $gross - $fee + $adjustment;

        DB::table('gymies_organisation_settlement_lines')->insert([
            'settlement_id' => (int) $id,
            'booking_id' => null,
            'trainer_user_id' => null,
            'line_type' => (string) $request->input('line_type'),
            'gross_cents' => $gross,
            'platform_fee_cents' => $fee,
            'adjustment_cents' => $adjustment,
            'net_cents' => $net,
            'metadata_json' => json_encode((array) $request->input('metadata', []), JSON_UNESCAPED_UNICODE),
            'created_at' => now(),
        ]);

        $totals = DB::table('gymies_organisation_settlement_lines')
            ->where('settlement_id', $id)
            ->selectRaw('COALESCE(SUM(gross_cents), 0) as gross_total')
            ->selectRaw('COALESCE(SUM(platform_fee_cents), 0) as fee_total')
            ->selectRaw('COALESCE(SUM(adjustment_cents), 0) as adjustment_total')
            ->selectRaw('COALESCE(SUM(net_cents), 0) as net_total')
            ->first();

        DB::table('gymies_organisation_settlements')
            ->where('id', $id)
            ->update([
                'gross_cents' => (int) ($totals->gross_total ?? 0),
                'fee_cents' => (int) ($totals->fee_total ?? 0),
                'adjustments_cents' => (int) ($totals->adjustment_total ?? 0),
                'net_cents' => (int) ($totals->net_total ?? 0),
                'updated_at' => now(),
            ]);

        $this->logAudit((int) $ctx['user_id'], 'gym_settlement_adjustment_added', 'organisation_settlement', (int) $id, null, [
            'line_type' => (string) $request->input('line_type'),
            'gross_cents' => $gross,
            'platform_fee_cents' => $fee,
            'adjustment_cents' => $adjustment,
            'net_cents' => $net,
        ]);

        return response()->json(['ok' => true], 201);
    }

    public function settings(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $orgId = (int) $ctx['organisation_id'];
        $org = DB::table('gymies_organisations')
            ->where('id', $orgId)
            ->first();
        if (!$org) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }

        $members = DB::table('gymies_organisation_members as m')
            ->join('gymies_users as u', 'u.id', '=', 'm.user_id')
            ->where('m.organisation_id', $orgId)
            ->orderByDesc(DB::raw("m.role = 'owner'"))
            ->orderBy('u.display_name')
            ->get(['m.user_id', 'm.role', 'm.status', 'u.display_name', 'u.email']);

        $orgData = [
            'id' => (string) $org->id,
            'name' => (string) $org->name,
            'type' => (string) $org->type,
            'status' => (string) $org->status,
            'contact_email' => $org->contact_email,
            'payout_frequency' => $org->payout_frequency,
            'payout_minimum_cents' => (int) $org->payout_minimum_cents,
        ];
        if (Schema::hasColumn('gymies_organisations', 'logo_url')) {
            $orgData['logo_url'] = $org->logo_url ? (string) $org->logo_url : null;
        }
        if (Schema::hasColumn('gymies_organisations', 'opening_hours_json')) {
            $orgData['opening_hours_json'] = $org->opening_hours_json;
        }
        if (Schema::hasColumn('gymies_organisations', 'default_location_id')) {
            $orgData['default_location_id'] = $org->default_location_id ? (string) $org->default_location_id : null;
        }
        return response()->json([
            'data' => [
                'organisation' => $orgData,
                'members' => $members->map(fn ($m) => [
                    'user_id' => (string) $m->user_id,
                    'display_name' => (string) ($m->display_name ?? $m->email),
                    'email' => (string) $m->email,
                    'role' => (string) $m->role,
                    'status' => (string) $m->status,
                ])->all(),
            ],
        ]);
    }

    public function updateSettings(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $request->validate([
            'name' => 'nullable|string|max:255',
            'contact_email' => 'nullable|email|max:255',
            'payout_frequency' => 'nullable|in:weekly,biweekly,monthly',
            'payout_minimum_cents' => 'nullable|integer|min:0|max:100000000',
            'logo_url' => 'nullable|string|max:512',
            'opening_hours_json' => 'nullable|array',
            'default_location_id' => 'nullable|integer|min:1',
        ]);

        $orgId = (int) $ctx['organisation_id'];
        $payload = [];
        foreach (['name', 'contact_email', 'payout_frequency', 'payout_minimum_cents'] as $key) {
            if ($request->has($key)) {
                $payload[$key] = $request->input($key);
            }
        }
        if (Schema::hasColumn('gymies_organisations', 'logo_url') && $request->has('logo_url')) {
            $payload['logo_url'] = $request->filled('logo_url') ? trim((string) $request->input('logo_url')) : null;
        }
        if (Schema::hasColumn('gymies_organisations', 'opening_hours_json') && $request->has('opening_hours_json')) {
            $val = $request->input('opening_hours_json');
            $payload['opening_hours_json'] = is_array($val) ? json_encode($val, JSON_UNESCAPED_UNICODE) : null;
        }
        if (Schema::hasColumn('gymies_organisations', 'default_location_id') && $request->has('default_location_id')) {
            $locId = $request->filled('default_location_id') ? (int) $request->input('default_location_id') : null;
            if ($locId !== null && Schema::hasTable('gym_locations')) {
                $loc = DB::table('gym_locations')->where('id', $locId)->where('organisation_id', $orgId)->first();
                $payload['default_location_id'] = $loc ? $locId : null;
            } else {
                $payload['default_location_id'] = null;
            }
        }

        if (empty($payload)) {
            return $this->settings($request);
        }

        $before = DB::table('gymies_organisations')
            ->where('id', $orgId)
            ->first();
        if (!$before) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }

        $payload['updated_at'] = now();
        DB::table('gymies_organisations')
            ->where('id', $orgId)
            ->update($payload);

        $this->logAudit((int) $ctx['user_id'], 'gym_settings_updated', 'organisation', $orgId, null, $payload);

        $renamed = array_key_exists('name', $payload)
            && trim((string) ($payload['name'] ?? '')) !== trim((string) ($before->name ?? ''));
        if ($renamed) {
            $this->writeCacheInvalidationEvent(
                (int) $ctx['user_id'],
                $orgId,
                'organisation_renamed',
                [
                    'previous_name' => (string) ($before->name ?? ''),
                    'new_name' => (string) ($payload['name'] ?? ''),
                    'trigger' => 'update_settings',
                ]
            );
        }

        return $this->settings($request);
    }

    public function clients(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        $orgId = (int) $ctx['organisation_id'];
        $query = trim((string) $request->query('query', ''));

        $clients = DB::table('gymies_bookings as b')
            ->join('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->where('b.organisation_id', $orgId)
            ->when($query !== '', function ($q) use ($query): void {
                $q->where(function ($nested) use ($query): void {
                    $nested->where('c.display_name', 'like', '%' . $query . '%')
                        ->orWhere('c.email', 'like', '%' . $query . '%');
                });
            })
            ->groupBy('b.client_user_id', 'c.display_name', 'c.email')
            ->selectRaw('b.client_user_id')
            ->selectRaw('COALESCE(c.display_name, c.email, "Klant") as client_name')
            ->selectRaw('c.email as client_email')
            ->selectRaw('COUNT(*) as bookings_count')
            ->selectRaw('COALESCE(SUM(CASE WHEN b.status IN ("confirmed","completed","no_show") AND b.paid_at IS NOT NULL THEN b.amount_cents ELSE 0 END), 0) as gross_cents')
            ->selectRaw('MAX(b.scheduled_at) as last_booking_at')
            ->orderByDesc('last_booking_at')
            ->limit(500)
            ->get();

        return response()->json([
            'data' => $clients->map(fn ($c) => [
                'client_user_id' => (string) $c->client_user_id,
                'client_name' => (string) $c->client_name,
                'client_email' => (string) ($c->client_email ?? ''),
                'bookings_count' => (int) $c->bookings_count,
                'gross_cents' => (int) $c->gross_cents,
                'last_booking_at' => $c->last_booking_at,
            ])->all(),
        ]);
    }

    public function exportBookingsCsv(Request $request): Response
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        $orgId = (int) $ctx['organisation_id'];
        $rows = DB::table('gymies_bookings as b')
            ->join('gymies_users as trainer', 'trainer.id', '=', 'b.trainer_user_id')
            ->join('gymies_users as client', 'client.id', '=', 'b.client_user_id')
            ->where('b.organisation_id', $orgId)
            ->orderByDesc('b.scheduled_at')
            ->limit(5000)
            ->get([
                'b.id',
                'b.scheduled_at',
                'b.status',
                'b.amount_cents',
                'b.duration_minutes',
                'b.payout_route',
                DB::raw('COALESCE(trainer.display_name, trainer.email, "Trainer") as trainer_name'),
                DB::raw('COALESCE(client.display_name, client.email, "Klant") as client_name'),
            ]);

        $csv = $this->toCsv(
            ['booking_id', 'scheduled_at', 'status', 'duration_minutes', 'amount_cents', 'payout_route', 'trainer_name', 'client_name'],
            $rows->map(fn ($r) => [
                (string) $r->id,
                (string) $r->scheduled_at,
                (string) $r->status,
                (string) $r->duration_minutes,
                (string) ((int) ($r->amount_cents ?? 0)),
                (string) ($r->payout_route ?? ''),
                (string) $r->trainer_name,
                (string) $r->client_name,
            ])->all()
        );

        return response($csv, 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="gym-bookings.csv"',
        ]);
    }

    public function exportRevenueCsv(Request $request): Response
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        $orgId = (int) $ctx['organisation_id'];
        $rows = DB::table('gymies_bookings as b')
            ->join('gymies_users as u', 'u.id', '=', 'b.trainer_user_id')
            ->where('b.organisation_id', $orgId)
            ->whereIn('b.status', ['confirmed', 'completed', 'no_show'])
            ->whereNotNull('b.paid_at')
            ->groupBy('b.trainer_user_id', 'u.display_name', 'u.email')
            ->selectRaw('b.trainer_user_id')
            ->selectRaw('COALESCE(u.display_name, u.email, "Trainer") as trainer_name')
            ->selectRaw('COUNT(*) as lessons_count')
            ->selectRaw('COALESCE(SUM(b.amount_cents), 0) as gross_cents')
            ->orderByDesc('gross_cents')
            ->get();

        $csv = $this->toCsv(
            ['trainer_user_id', 'trainer_name', 'lessons_count', 'gross_cents', 'platform_fee_cents', 'net_cents'],
            $rows->map(function ($r): array {
                $gross = (int) $r->gross_cents;
                $fee = (int) round($gross * 0.12);
                $net = max($gross - $fee, 0);

                return [
                    (string) $r->trainer_user_id,
                    (string) $r->trainer_name,
                    (string) ((int) $r->lessons_count),
                    (string) $gross,
                    (string) $fee,
                    (string) $net,
                ];
            })->all()
        );

        return response($csv, 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="gym-revenue.csv"',
        ]);
    }

    public function exportTrainersCsv(Request $request): Response
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        $orgId = (int) $ctx['organisation_id'];

        $rows = DB::table('gymies_organisation_trainers as ot')
            ->join('gymies_users as u', 'u.id', '=', 'ot.trainer_user_id')
            ->where('ot.organisation_id', $orgId)
            ->orderBy('u.display_name')
            ->get([
                'ot.trainer_user_id',
                'ot.status',
                'ot.employment_type',
                'ot.payout_route',
                'ot.is_primary',
                'ot.active_from',
                'ot.active_until',
                DB::raw('COALESCE(u.display_name, u.email, "Trainer") as trainer_name'),
                'u.email as trainer_email',
            ]);

        $csv = $this->toCsv(
            ['trainer_user_id', 'trainer_name', 'trainer_email', 'status', 'employment_type', 'payout_route', 'is_primary', 'active_from', 'active_until'],
            $rows->map(fn ($r) => [
                (string) $r->trainer_user_id,
                (string) $r->trainer_name,
                (string) $r->trainer_email,
                (string) $r->status,
                (string) $r->employment_type,
                (string) $r->payout_route,
                ((int) $r->is_primary) === 1 ? '1' : '0',
                (string) ($r->active_from ?? ''),
                (string) ($r->active_until ?? ''),
            ])->all()
        );

        return response($csv, 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="gym-trainers.csv"',
        ]);
    }

    public function logCacheInvalidationEvent(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $request->validate([
            'reason' => 'required|string|max:128',
            'metadata' => 'nullable|array',
        ]);

        $this->writeCacheInvalidationEvent(
            (int) $ctx['user_id'],
            (int) $ctx['organisation_id'],
            (string) $request->input('reason'),
            (array) $request->input('metadata', [])
        );

        return response()->json(['ok' => true], 201);
    }

    public function completeDashboardAlert(Request $request, string $alertKey): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager', 'viewer']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!$this->isAllowedAlertKey($alertKey)) {
            return response()->json(['message' => 'Ongeldige alert key.'], 422);
        }
        $request->validate([
            'status' => 'nullable|in:open,done',
        ]);

        $orgId = (int) $ctx['organisation_id'];
        $status = (string) $request->input('status', 'done');
        $this->ensureAlertStateTable();
        if (!Schema::hasTable('gymies_organisation_alert_states')) {
            return response()->json(['message' => 'Alert state tabel niet beschikbaar.'], 422);
        }

        DB::table('gymies_organisation_alert_states')->updateOrInsert(
            [
                'organisation_id' => $orgId,
                'alert_key' => $alertKey,
            ],
            [
                'status' => $status,
                'handled_by' => (int) $ctx['user_id'],
                'handled_at' => now(),
                'updated_at' => now(),
                'created_at' => now(),
            ]
        );

        return response()->json([
            'data' => [
                'alert_key' => $alertKey,
                'status' => $status,
            ],
        ]);
    }

    public function sendBookingReminder(Request $request, string $bookingId): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager', 'viewer']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!$this->isPositiveIntegerId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        $orgId = (int) $ctx['organisation_id'];
        $booking = DB::table('gymies_bookings')
            ->where('id', $bookingId)
            ->where('organisation_id', $orgId)
            ->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        $this->logAudit((int) $ctx['user_id'], 'gym_booking_reminder_requested', 'booking', (int) $bookingId, null, [
            'organisation_id' => $orgId,
        ]);

        return response()->json([
            'data' => [
                'booking_id' => (string) $bookingId,
                'queued' => true,
            ],
        ]);
    }

    public function sendClientReengagement(Request $request, string $clientUserId): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager', 'viewer']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!$this->isPositiveIntegerId($clientUserId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $orgId = (int) $ctx['organisation_id'];
        $clientId = (int) $clientUserId;
        $exists = DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->where('client_user_id', $clientId)
            ->exists();
        if (!$exists) {
            return response()->json(['message' => 'Klant niet gevonden binnen deze organisatie.'], 404);
        }

        $this->logAudit((int) $ctx['user_id'], 'gym_client_reengagement_requested', 'user', $clientId, null, [
            'organisation_id' => $orgId,
        ]);

        return response()->json([
            'data' => [
                'client_user_id' => (string) $clientId,
                'queued' => true,
            ],
        ]);
    }

    protected function requireGymMember(Request $request, array $allowedRoles = ['owner', 'manager', 'viewer'])
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_organisation_members')) {
            return response()->json(['message' => 'Gym module niet geactiveerd op deze omgeving.'], 422);
        }

        $membership = DB::table('gymies_organisation_members as m')
            ->join('gymies_organisations as o', 'o.id', '=', 'm.organisation_id')
            ->where('m.user_id', $user->id)
            ->where('m.status', 'active')
            ->where('o.status', 'active')
            ->orderByDesc(DB::raw("m.role = 'owner'"))
            ->orderByDesc(DB::raw("m.role = 'manager'"))
            ->first([
                'm.organisation_id',
                'm.role',
                'o.name as organisation_name',
            ]);

        if (!$membership && Schema::hasTable('gymies_organisation_trainers') && (string) ($user->role ?? '') === 'trainer') {
            $trainerLink = DB::table('gymies_organisation_trainers as t')
                ->join('gymies_organisations as o', 'o.id', '=', 't.organisation_id')
                ->where('t.trainer_user_id', $user->id)
                ->where('t.status', 'active')
                ->where('o.status', 'active')
                ->first(['t.organisation_id', 'o.name as organisation_name']);
            if ($trainerLink) {
                $membership = (object) [
                    'organisation_id' => $trainerLink->organisation_id,
                    'role' => 'trainer',
                    'organisation_name' => $trainerLink->organisation_name,
                ];
            }
        }

        if (!$membership) {
            return response()->json(['message' => 'Geen actieve gym-toegang gevonden.'], 403);
        }
        $role = (string) $membership->role;
        if (!in_array($role, $allowedRoles, true)) {
            return response()->json(['message' => 'Onvoldoende rechten voor deze actie.'], 403);
        }

        return [
            'user_id' => (int) $user->id,
            'organisation_id' => (int) $membership->organisation_id,
            'organisation_name' => (string) $membership->organisation_name,
            'member_role' => $role,
        ];
    }

    /**
     * @param array<string,mixed> $metadata
     */
    private function writeCacheInvalidationEvent(int $userId, int $organisationId, string $reason, array $metadata): void
    {
        $payload = [
            'reason' => $reason,
            'organisation_id' => $organisationId,
            'metadata' => $metadata,
            'requested_at' => now()->toIso8601String(),
        ];

        if (DB::getSchemaBuilder()->hasTable('gymies_api_error_logs')) {
            DB::table('gymies_api_error_logs')->insert([
                'user_id' => $userId,
                'endpoint' => 'gym/cache-invalidation-event',
                'error_code' => 'GYM_CACHE_INVALIDATION_EVENT',
                'message' => 'Gym cache invalidation event logged',
                'context_json' => json_encode($payload, JSON_UNESCAPED_UNICODE),
                'created_at' => now(),
            ]);
        }

        $this->logAudit(
            $userId,
            'gym_cache_invalidation_event',
            'organisation',
            $organisationId,
            null,
            $payload
        );
    }

    /**
     * @return array{0:\Illuminate\Support\Carbon,1:\Illuminate\Support\Carbon}
     */
    private function periodBounds(string $period, \Illuminate\Support\Carbon $anchor): array
    {
        if ($period === 'week') {
            return [$anchor->copy()->startOfWeek(), $anchor->copy()->endOfWeek()];
        }
        if ($period === 'year') {
            return [$anchor->copy()->startOfYear(), $anchor->copy()->endOfYear()];
        }

        return [$anchor->copy()->startOfMonth(), $anchor->copy()->endOfMonth()];
    }

    /**
     * @return array{0:\Illuminate\Support\Carbon,1:\Illuminate\Support\Carbon}
     */
    private function previousPeriodBounds(\Illuminate\Support\Carbon $start, \Illuminate\Support\Carbon $end): array
    {
        $durationSeconds = $end->diffInSeconds($start) + 1;
        $prevEnd = $start->copy()->subSecond();
        $prevStart = $prevEnd->copy()->subSeconds($durationSeconds - 1);

        return [$prevStart, $prevEnd];
    }

    /**
     * @return array<string,mixed>
     */
    private function collectBookingStats(int $orgId, \Illuminate\Support\Carbon $start, \Illuminate\Support\Carbon $end): array
    {
        $rows = DB::table('gymies_bookings')
            ->where('organisation_id', $orgId)
            ->whereBetween('scheduled_at', [$start, $end])
            ->get(['status', 'amount_cents', 'paid_at', 'location_type']);

        $bookingsCount = $rows->count();
        $confirmed = $rows->where('status', 'confirmed')->count();
        $completed = $rows->where('status', 'completed')->count();
        $cancelled = $rows->where('status', 'cancelled')->count();
        $pending = $rows->where('status', 'pending')->count();
        $noShow = $rows->where('status', 'no_show')->count();

        $revenueRows = $rows->filter(fn ($r) => in_array((string) $r->status, ['confirmed', 'completed', 'no_show'], true) && !empty($r->paid_at));
        $gross = (int) $revenueRows->sum('amount_cents');
        $fee = (int) round($gross * 0.12);
        $net = max($gross - $fee, 0);

        $avgBooking = $revenueRows->count() > 0 ? (int) round($gross / $revenueRows->count()) : 0;
        $cancellationRate = $bookingsCount > 0 ? round(($cancelled / $bookingsCount) * 100, 2) : 0.0;

        $locationCounts = [
            'online' => $rows->where('location_type', 'online')->count(),
            'gym' => $rows->where('location_type', 'gym')->count(),
            'on_site' => $rows->where('location_type', 'on_site')->count(),
        ];

        return [
            'bookings_count' => $bookingsCount,
            'pending_count' => $pending,
            'confirmed_count' => $confirmed,
            'completed_count' => $completed,
            'cancelled_count' => $cancelled,
            'no_show_count' => $noShow,
            'gross_cents' => $gross,
            'platform_fee_cents' => $fee,
            'net_cents' => $net,
            'average_booking_cents' => $avgBooking,
            'cancellation_rate_pct' => $cancellationRate,
            'location_type_counts' => $locationCounts,
        ];
    }

    private function ensureAlertStateTable(): void
    {
        if (Schema::hasTable('gymies_organisation_alert_states')) {
            return;
        }
        try {
            DB::statement('CREATE TABLE IF NOT EXISTS gymies_organisation_alert_states (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                organisation_id BIGINT UNSIGNED NOT NULL,
                alert_key VARCHAR(128) NOT NULL,
                status VARCHAR(16) NOT NULL DEFAULT "open",
                handled_by BIGINT UNSIGNED DEFAULT NULL,
                handled_at TIMESTAMP NULL DEFAULT NULL,
                created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY gymies_org_alert_unique (organisation_id, alert_key),
                KEY gymies_org_alert_status (organisation_id, status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
        } catch (\Throwable $e) {
            // Keep dashboard functional even if table creation fails.
        }
    }

    /**
     * @param list<string> $headers
     * @param list<list<string>> $rows
     */
    private function toCsv(array $headers, array $rows): string
    {
        $stream = fopen('php://temp', 'r+');
        if ($stream === false) {
            return '';
        }

        fputcsv($stream, $headers);
        foreach ($rows as $row) {
            fputcsv($stream, $row);
        }

        rewind($stream);
        $csv = stream_get_contents($stream);
        fclose($stream);

        return (string) $csv;
    }

    private function percentGrowth(int $current, int $previous): float
    {
        if ($previous === 0) {
            return $current > 0 ? 100.0 : 0.0;
        }

        return round((($current - $previous) / $previous) * 100, 2);
    }

    /**
     * @param array<string,mixed>|null $oldValues
     * @param array<string,mixed>|null $newValues
     */
    private function logAudit(int $userId, string $action, string $entityType, int $entityId, ?array $oldValues, ?array $newValues): void
    {
        if (!DB::getSchemaBuilder()->hasTable('gymies_audit_log')) {
            return;
        }
        $oldValues = $this->sanitizeAuditPayload($oldValues);
        $newValues = $this->sanitizeAuditPayload($newValues);
        DB::table('gymies_audit_log')->insert([
            'user_id' => $userId,
            'action' => $action,
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'old_values' => $oldValues ? json_encode($oldValues, JSON_UNESCAPED_UNICODE) : null,
            'new_values' => $newValues ? json_encode($newValues, JSON_UNESCAPED_UNICODE) : null,
            'ip_address' => request()->ip(),
            'created_at' => now(),
        ]);
    }

    private function isPositiveIntegerId(string $value): bool
    {
        return ctype_digit($value) && (int) $value > 0;
    }

    private function isAllowedAlertKey(string $alertKey): bool
    {
        return in_array($alertKey, [
            'open_settlements',
            'no_show_followups',
            'trainers_without_availability',
            'expired_payment_method',
        ], true);
    }

    /**
     * @param array<string,mixed>|null $payload
     * @return array<string,mixed>|null
     */
    private function sanitizeAuditPayload(?array $payload): ?array
    {
        if ($payload === null) {
            return null;
        }
        $deny = [
            'password',
            'password_hash',
            'token',
            'authorization',
            'iban',
            'iban_masked',
            'iban_last4',
            'payout_reference',
            'metadata_json',
        ];
        $out = [];
        foreach ($payload as $key => $value) {
            $k = mb_strtolower((string) $key);
            if (in_array($k, $deny, true)) {
                $out[$key] = '[REDACTED]';
                continue;
            }
            if (is_array($value)) {
                $out[$key] = $this->sanitizeAuditPayload($value);
                continue;
            }
            if (is_string($value) && strlen($value) > 500) {
                $out[$key] = mb_substr($value, 0, 500) . '...';
                continue;
            }
            $out[$key] = $value;
        }

        return $out;
    }

    // ══════════════════════════════════════════════════════
    // GYM MOLLIE & PAYOUT METHODS
    // ══════════════════════════════════════════════════════

    /**
     * GET gym/mollie-status — Mollie Connect status voor deze gym.
     */
    public function mollieStatus(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) return $ctx;
        $orgId = (int) $ctx['organisation_id'];

        $this->ensureGymMollieSchema();

        $org = DB::table('gymies_organisations')->where('id', $orgId)->first();
        $hasToken = false;
        $mollieOrgId = null;
        if ($org) {
            if (!empty($org->mollie_access_token ?? null)) {
                try {
                    $token = decrypt($org->mollie_access_token);
                    $hasToken = is_string($token) && $token !== '';
                } catch (\Throwable $e) {
                    $hasToken = false;
                }
            }
            $mollieOrgId = $org->mollie_organization_id ?? null;
        }

        return response()->json([
            'connected' => $hasToken,
            'mollie_organization_id' => $mollieOrgId,
            'can_receive_payments' => $hasToken,
        ]);
    }

    /**
     * POST gym/mollie-disconnect — Verwijder Mollie koppeling.
     */
    public function mollieDisconnect(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner']);
        if ($ctx instanceof JsonResponse) return $ctx;
        $orgId = (int) $ctx['organisation_id'];

        $update = ['updated_at' => now()];
        $columns = Schema::getColumnListing('gymies_organisations');
        if (in_array('mollie_access_token', $columns)) $update['mollie_access_token'] = null;
        if (in_array('mollie_refresh_token', $columns)) $update['mollie_refresh_token'] = null;
        if (in_array('mollie_organization_id', $columns)) $update['mollie_organization_id'] = null;
        if (in_array('mollie_token_expires_at', $columns)) $update['mollie_token_expires_at'] = null;

        DB::table('gymies_organisations')->where('id', $orgId)->update($update);

        return response()->json(['message' => 'Mollie koppeling verwijderd.']);
    }

    /**
     * GET gym/payout-settings — IBAN, frequentie, modus.
     */
    public function payoutSettings(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) return $ctx;
        $orgId = (int) $ctx['organisation_id'];

        $org = DB::table('gymies_organisations')->where('id', $orgId)->first();

        return response()->json([
            'iban' => $org->payout_iban ?? '',
            'iban_name' => $org->payout_iban_name ?? '',
            'payout_frequency' => $org->payout_frequency ?? 'monthly',
            'payout_minimum_cents' => (int) ($org->payout_minimum_cents ?? 5000),
            'payout_mode' => $org->payout_mode ?? 'platform',
            'mollie_connected' => !empty($org->mollie_access_token ?? null),
        ]);
    }

    /**
     * PUT gym/payout-settings — Update IBAN, frequentie.
     */
    public function updatePayoutSettings(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner']);
        if ($ctx instanceof JsonResponse) return $ctx;
        $orgId = (int) $ctx['organisation_id'];

        $update = ['updated_at' => now()];
        $columns = Schema::getColumnListing('gymies_organisations');

        $iban = trim($request->input('iban', ''));
        if ($iban !== '' && in_array('payout_iban', $columns)) {
            // Validate IBAN using GymiesPayoutService
            if (!GymiesPayoutService::validateIban($iban)) {
                return response()->json(['message' => 'IBAN is ongeldig. Controleer het IBAN-formaat.'], 422);
            }
            $update['payout_iban'] = $iban;
        }

        $ibanName = trim($request->input('iban_name', ''));
        if ($iban !== '' && empty($ibanName)) {
            return response()->json(['message' => 'Naam voor IBAN-houder is verplicht wanneer IBAN is opgegeven.'], 422);
        }
        if ($ibanName !== '' && in_array('payout_iban_name', $columns)) $update['payout_iban_name'] = $ibanName;

        $freq = $request->input('payout_frequency');
        if (in_array($freq, ['monthly', 'weekly', 'daily'], true) && in_array('payout_frequency', $columns)) {
            $update['payout_frequency'] = $freq;
        }

        $mode = $request->input('payout_mode');
        if (in_array($mode, ['platform', 'mollie_connect'], true) && in_array('payout_mode', $columns)) {
            $update['payout_mode'] = $mode;
        }

        DB::table('gymies_organisations')->where('id', $orgId)->update($update);

        return response()->json(['message' => 'Instellingen bijgewerkt.']);
    }

    /**
     * GET gym/settlements — Alle uitbetalingen/settlements.
     */
    public function gymPayouts(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) return $ctx;
        $orgId = (int) $ctx['organisation_id'];

        if (!Schema::hasTable('gymies_organisation_settlements')) {
            return response()->json(['settlements' => []]);
        }

        $settlements = DB::table('gymies_organisation_settlements')
            ->where('organisation_id', $orgId)
            ->orderByDesc('created_at')
            ->limit(100)
            ->get();

        return response()->json([
            'settlements' => $settlements->map(fn ($s) => [
                'id' => $s->id,
                'status' => $s->status ?? 'draft',
                'gross_cents' => (int) ($s->gross_cents ?? 0),
                'fee_cents' => (int) ($s->fee_cents ?? 0),
                'net_cents' => (int) ($s->net_cents ?? 0),
                'net_formatted' => '€' . number_format((int) ($s->net_cents ?? 0) / 100, 2, ',', '.'),
                'period_start' => $s->period_start ?? null,
                'period_end' => $s->period_end ?? null,
                'invoice_number' => $s->invoice_number ?? null,
                'invoice_path' => $s->invoice_path ?? null,
                'has_pdf' => !empty($s->invoice_path),
                'paid_at' => $s->paid_at ?? null,
                'created_at' => $s->created_at ?? null,
            ])->values(),
        ]);
    }

    /**
     * GET gym/settlements/{id}/download — Download settlement factuur PDF.
     */
    public function downloadSettlementInvoice(Request $request, string $id): \Illuminate\Http\Response|JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) return $ctx;
        $orgId = (int) $ctx['organisation_id'];

        if (!Schema::hasTable('gymies_organisation_settlements')) {
            return response()->json(['message' => 'Settlements niet beschikbaar.'], 404);
        }

        $settlement = DB::table('gymies_organisation_settlements')
            ->where('id', (int) $id)
            ->where('organisation_id', $orgId)
            ->first();

        if (!$settlement) {
            return response()->json(['message' => 'Settlement niet gevonden.'], 404);
        }

        try {
            // Generate PDF if not yet generated
            if (empty($settlement->invoice_path)) {
                $pdf = GymiesInvoiceGenerator::getGymSettlementInvoicePdf((int) $id);
                if (!$pdf) {
                    return response()->json(['message' => 'Factuur kon niet worden gegenereerd.'], 500);
                }
                $content = $pdf;
            } else {
                if (!\Illuminate\Support\Facades\Storage::disk('local')->exists($settlement->invoice_path)) {
                    return response()->json(['message' => 'PDF niet gevonden op schijf.'], 404);
                }
                $content = \Illuminate\Support\Facades\Storage::disk('local')->get($settlement->invoice_path);
            }

            $filename = ($settlement->invoice_number ?? 'settlement-' . $id) . '.pdf';

            $contentType = str_starts_with(trim($content), '<!DOCTYPE') || str_starts_with(trim($content), '<html')
                ? 'text/html' : 'application/pdf';
            if ($contentType === 'text/html') {
                $filename = str_replace('.pdf', '.html', $filename);
            }

            return response($content, 200)
                ->header('Content-Type', $contentType)
                ->header('Content-Disposition', "attachment; filename=\"{$filename}\"");
        } catch (\Throwable $e) {
            \Illuminate\Support\Facades\Log::error('Gym settlement invoice download failed', [
                'org_id' => $orgId,
                'settlement_id' => (int) $id,
                'error' => $e->getMessage(),
            ]);
            return response()->json(['message' => 'Fout bij downloaden.'], 500);
        }
    }

    /**
     * POST gym/settlements/request-now — Vraag direct settlement aan.
     * Controleert: payout_mode=gymies, IBAN ingesteld, geen pending settlement.
     * Berekent beschikbare bedrag en maakt settlement record met status 'pending'.
     */
    public function requestSettlementNow(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) return $ctx;
        $orgId = (int) $ctx['organisation_id'];

        if (!Schema::hasTable('gymies_organisation_settlements') || !Schema::hasTable('gymies_organisations')) {
            return response()->json(['message' => 'Settlement tabellen ontbreken.'], 422);
        }

        if (!Schema::hasTable('gymies_payment_transactions')) {
            return response()->json(['message' => 'Payment transactions tabel ontbreekt.'], 422);
        }

        // Haal organisatie op
        $org = DB::table('gymies_organisations')->where('id', $orgId)->first();
        if (!$org) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }

        // Check payout_mode
        if ($org->payout_mode !== 'gymies') {
            return response()->json([
                'message' => 'Settlement alleen beschikbaar voor payout_mode=gymies.',
                'current_mode' => $org->payout_mode ?? 'none',
            ], 422);
        }

        // Check IBAN ingesteld
        if (empty($org->payout_iban)) {
            return response()->json(['message' => 'IBAN is niet ingesteld. Stel eerst payout-instellingen in.'], 422);
        }

        // Check geen pending settlement
        $hasPending = DB::table('gymies_organisation_settlements')
            ->where('organisation_id', $orgId)
            ->where('status', 'pending')
            ->exists();

        if ($hasPending) {
            return response()->json(['message' => 'Er is al een openstaande settlement. Wacht op verwerking.'], 422);
        }

        try {
            // Bereken beschikbare bedrag: alle payments met mollie_account_source='organisation'
            // die nog niet in een paid settlement zitten
            $transactions = DB::table('gymies_payment_transactions')
                ->where('organisation_id', $orgId)
                ->where('mollie_account_source', 'organisation')
                ->whereIn('status', ['success', 'paid'])
                ->get(['id', 'amount_cents']);

            $grossCents = (int) $transactions->sum('amount_cents');
            $numBookings = $transactions->count();

            if ($grossCents <= 0) {
                return response()->json([
                    'message' => 'Geen beschikbare inkomsten voor settlement.',
                    'gross_cents' => 0,
                ], 422);
            }

            $feeCents = $numBookings * GymiesPayoutService::BOOKING_FEE_CENTS;
            $netAmountCents = max($grossCents - $feeCents, 0);

            // Maak settlement record
            $settlementId = DB::transaction(function () use ($orgId, $grossCents, $feeCents, $netAmountCents, $ctx) {
                return DB::table('gymies_organisation_settlements')->insertGetId([
                    'organisation_id' => $orgId,
                    'amount_cents' => $grossCents,
                    'fee_cents' => $feeCents,
                    'net_amount_cents' => $netAmountCents,
                    'status' => 'pending',
                    'period_start' => now()->toDateString(),
                    'period_end' => now()->toDateString(),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            });

            $this->logAudit((int) $ctx['user_id'], 'gym_settlement_request_now', 'organisation_settlement', $settlementId, null, [
                'organisation_id' => $orgId,
                'gross_cents' => $grossCents,
                'fee_cents' => $feeCents,
            ]);

            return response()->json([
                'data' => [
                    'settlement_id' => (string) $settlementId,
                    'status' => 'pending',
                    'gross_cents' => $grossCents,
                    'fee_cents' => $feeCents,
                    'net_amount_cents' => $netAmountCents,
                    'net_formatted' => '€' . number_format($netAmountCents / 100, 2, ',', '.'),
                    'num_transactions' => $numBookings,
                ]
            ], 201);
        } catch (\Throwable $e) {
            Log::error('Settlement request failed', [
                'organisation_id' => $orgId,
                'error' => $e->getMessage(),
            ]);
            if (app()->bound('sentry')) {
                app('sentry')->captureException($e);
            }
            return response()->json(['message' => 'Fout bij aanmaken settlement.'], 500);
        }
    }

    /**
     * Ensure gym organisations table has the Mollie + payout columns.
     */
    public static function ensureGymMollieSchema(): void
    {
        if (!Schema::hasTable('gymies_organisations')) return;

        $columns = Schema::getColumnListing('gymies_organisations');
        $needed = [
            'mollie_access_token' => 'TEXT NULL',
            'mollie_refresh_token' => 'TEXT NULL',
            'mollie_organization_id' => 'VARCHAR(50) NULL',
            'mollie_token_expires_at' => 'TIMESTAMP NULL',
            'payout_iban' => 'VARCHAR(40) NULL',
            'payout_iban_name' => 'VARCHAR(255) NULL',
            'payout_mode' => "VARCHAR(20) DEFAULT 'platform'",
        ];

        foreach ($needed as $col => $definition) {
            if (!in_array($col, $columns)) {
                try {
                    DB::statement("ALTER TABLE gymies_organisations ADD COLUMN {$col} {$definition}");
                } catch (\Throwable $e) {
                    // Column might already exist via concurrent request
                }
            }
        }
    }

}
