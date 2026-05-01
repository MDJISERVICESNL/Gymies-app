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
 * Studio/Elite Bird's Eye + W2W veiligheidsaudit.
 * Alle endpoints: assertTeam — alleen Studio/Elite.
 */
final class GymiesStudioAnalyticsController extends Controller
{
    use GymiesRequireTrainerTrait;

    public function performanceSummary(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $check = GymiesPlanManager::assertTeam((int) $user->id);
        if (!$check['allowed']) {
            return response()->json([
                'message' => $check['message'],
                'upgrade_hint' => $check['upgrade_hint'],
            ], 403);
        }

        // N-033 FIXED: authorization check for studio access
        $studioId = (int) $request->input('studio_id', 0);
        if ($studioId > 0) {
            $isOwner = DB::table('gymies_gyms')
                ->where('id', $studioId)
                ->where('owner_id', (int) $user->id)
                ->exists();
            if (!$isOwner) {
                return response()->json(['message' => 'Geen toegang tot deze studio analytics.'], 403);
            }
        }

        $from = $request->input('from', now()->subDays(30)->format('Y-m-d'));
        $to = $request->input('to', now()->format('Y-m-d'));
        $fromDt = $from . ' 00:00:00';
        $toDt = $to . ' 23:59:59';

        $trainerIds = [(int) $user->id];
        if (Schema::hasTable('gymies_organisation_trainers') && Schema::hasTable('gymies_organisation_members')) {
            $orgIds = DB::table('gymies_organisation_members')
                ->where('user_id', (int) $user->id)
                ->whereIn('role', ['owner', 'manager'])
                ->pluck('organisation_id');
            if ($orgIds->isNotEmpty()) {
                $teamTrainers = DB::table('gymies_organisation_trainers')
                    ->whereIn('organisation_id', $orgIds)
                    ->where('status', 'active')
                    ->pluck('trainer_user_id')
                    ->unique()
                    ->values()
                    ->all();
                if (!empty($teamTrainers)) {
                    $trainerIds = array_map('intval', $teamTrainers);
                }
            }
        }

        $trainerMetrics = [];
        $heatmap = [];
        if (Schema::hasTable('gymies_bookings')) {
            $names = DB::table('gymies_users')->whereIn('id', $trainerIds)->pluck('display_name', 'id')->all();
            foreach ($trainerIds as $tid) {
                $rows = DB::table('gymies_bookings')
                    ->where('trainer_user_id', $tid)
                    ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                    ->whereBetween('scheduled_at', [$fromDt, $toDt])
                    ->whereNotNull('paid_at')
                    ->selectRaw('status, COUNT(*) as c, SUM(COALESCE(amount_cents,0)) as revenue')
                    ->groupBy('status')
                    ->get();
                $revenue = 0;
                $noShow = 0;
                $completed = 0;
                foreach ($rows as $r) {
                    if ($r->status === 'no_show') {
                        $noShow += (int) $r->c;
                    } else {
                        $revenue += (int) ($r->revenue ?? 0);
                        if ($r->status === 'completed') {
                            $completed += (int) $r->c;
                        }
                    }
                }
                $trainerMetrics[] = [
                    'trainer_user_id' => (string) $tid,
                    'name' => (string) ($names[$tid] ?? 'Trainer ' . $tid),
                    'revenue_cents' => $revenue,
                    'completed_sessions' => $completed,
                    'no_show_count' => $noShow,
                    'retention_percent' => null,
                ];
            }

            $weekRows = DB::table('gymies_bookings')
                ->whereIn('trainer_user_id', $trainerIds)
                ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                ->whereBetween('scheduled_at', [$fromDt, $toDt])
                ->whereNotNull('paid_at')
                ->selectRaw('YEARWEEK(scheduled_at) as week_key, SUM(COALESCE(amount_cents,0)) as revenue_cents, COUNT(*) as sessions')
                ->groupBy('week_key')
                ->orderBy('week_key')
                ->get();
            foreach ($weekRows as $wr) {
                $heatmap[] = [
                    'week' => (string) $wr->week_key,
                    'revenue_cents' => (int) ($wr->revenue_cents ?? 0),
                    'sessions' => (int) ($wr->sessions ?? 0),
                ];
            }
        }

        return response()->json([
            'data' => [
                'from' => $from,
                'to' => $to,
                'heatmap' => $heatmap,
                'trainer_metrics' => $trainerMetrics,
                'capacity_alerts' => [],
            ],
        ]);
    }

    /**
     * Capaciteitsplanner: bezetting per dag/slot (Studio-only).
     */
    public function capacityWeek(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $check = GymiesPlanManager::assertTeam((int) $user->id);
        if (!$check['allowed']) {
            return response()->json(['message' => $check['message']], 403);
        }

        $weekStart = $request->input('week_start', now()->startOfWeek()->format('Y-m-d'));
        $start = $weekStart . ' 00:00:00';
        $end = date('Y-m-d', strtotime($weekStart . ' +6 days')) . ' 23:59:59';

        $trainerIds = [(int) $user->id];
        if (Schema::hasTable('gymies_organisation_trainers') && Schema::hasTable('gymies_organisation_members')) {
            $orgIds = DB::table('gymies_organisation_members')
                ->where('user_id', (int) $user->id)
                ->whereIn('role', ['owner', 'manager'])
                ->pluck('organisation_id');
            if ($orgIds->isNotEmpty()) {
                $teamTrainers = DB::table('gymies_organisation_trainers')
                    ->whereIn('organisation_id', $orgIds)
                    ->where('status', 'active')
                    ->pluck('trainer_user_id')
                    ->unique()
                    ->values()
                    ->all();
                if (!empty($teamTrainers)) {
                    $trainerIds = array_map('intval', $teamTrainers);
                }
            }
        }

        $slots = [];
        if (Schema::hasTable('gymies_bookings')) {
            $rows = DB::table('gymies_bookings')
                ->whereIn('trainer_user_id', $trainerIds)
                ->whereIn('status', ['confirmed', 'completed'])
                ->whereBetween('scheduled_at', [$start, $end])
                ->selectRaw('DATE(scheduled_at) as day, HOUR(scheduled_at) as hour, SUM(COALESCE(duration_minutes,60)) as minutes, COUNT(*) as bookings')
                ->groupBy('day', 'hour')
                ->get();
            $maxMinutesPerSlot = 60 * count($trainerIds);
            foreach ($rows as $r) {
                $day = (string) $r->day;
                $hour = (int) $r->hour;
                $minutes = (int) ($r->minutes ?? 0);
                $bookings = (int) ($r->bookings ?? 0);
                $utilPercent = $maxMinutesPerSlot > 0 ? min(100, (int) round(($minutes / $maxMinutesPerSlot) * 100)) : 0;
                $slots[] = [
                    'day' => $day,
                    'hour' => $hour,
                    'minutes_booked' => $minutes,
                    'bookings_count' => $bookings,
                    'utilization_percent' => $utilPercent,
                    'alert' => $utilPercent >= 90 ? 'high' : ($utilPercent >= 70 ? 'medium' : null),
                ];
            }
        }

        return response()->json([
            'data' => [
                'week_start' => $weekStart,
                'slots' => $slots,
            ],
        ]);
    }

    /**
     * W2W veiligheidslog: SOS + safe-session overdue events (Studio-eigenaar audit).
     */
    public function safetyLog(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $check = GymiesPlanManager::assertTeam((int) $user->id);
        if (!$check['allowed']) {
            return response()->json(['message' => $check['message']], 403);
        }

        $items = [];
        if (Schema::hasTable('gymies_sos_alerts')) {
            $alerts = DB::table('gymies_sos_alerts')
                ->orderByDesc('created_at')
                ->limit(50)
                ->get();
            foreach ($alerts as $a) {
                $items[] = [
                    'type' => 'sos',
                    'id' => (string) $a->id,
                    'user_id' => (string) $a->user_id,
                    'booking_id' => $a->booking_id !== null ? (string) $a->booking_id : null,
                    'status' => (string) ($a->status ?? ''),
                    'created_at' => $a->created_at ?? null,
                ];
            }
        }

        return response()->json(['data' => ['items' => $items]]);
    }
}
