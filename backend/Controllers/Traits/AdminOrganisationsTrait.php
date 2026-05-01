<?php

namespace App\Http\Controllers\Gymies\Traits;

use Illuminate\Database\Schema\Builder as Schema;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Carbon;

trait AdminOrganisationsTrait
{
    public function organisations(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_organisations')) {
            return response()->json(['data' => []]);
        }
        $q = trim((string) $request->query('q', ''));
        $groupBy = ['o.id', 'o.name', 'o.status', 'o.created_at'];
        $select = 'o.id, o.name, o.status, o.created_at';
        if (Schema::hasColumn('gymies_organisations', 'contact_email')) {
            $groupBy[] = 'o.contact_email';
            $select .= ', o.contact_email';
        }
        if (Schema::hasColumn('gymies_organisations', 'payout_frequency')) {
            $groupBy[] = 'o.payout_frequency';
            $select .= ', o.payout_frequency';
        }
        if (Schema::hasColumn('gymies_organisations', 'type')) {
            $groupBy[] = 'o.type';
            $select .= ', o.type';
        }
        $query = DB::table('gymies_organisations as o')
            ->groupBy($groupBy)
            ->orderByDesc('o.id')
            ->selectRaw($select);
        if ($q !== '') {
            $query->where(function ($w) use ($q): void {
                $w->where('o.name', 'like', "%{$q}%");
                if (Schema::hasColumn('gymies_organisations', 'contact_email')) {
                    $w->orWhere('o.contact_email', 'like', "%{$q}%");
                }
            });
        }

        if (Schema::hasTable('gymies_organisation_members')) {
            $query->leftJoin('gymies_organisation_members as m', 'm.organisation_id', '=', 'o.id')
                ->selectRaw('COUNT(DISTINCT m.user_id) as members_count');
        } else {
            $query->selectRaw('0 as members_count');
        }

        if (Schema::hasTable('gymies_organisation_settlements')) {
            $query->leftJoin('gymies_organisation_settlements as s', 's.organisation_id', '=', 'o.id')
                ->selectRaw('SUM(CASE WHEN s.status IN ("draft","approved") THEN 1 ELSE 0 END) as open_settlements_count');
        } else {
            $query->selectRaw('0 as open_settlements_count');
        }

        if (Schema::hasTable('gymies_organisation_trainers')) {
            $query->leftJoin('gymies_organisation_trainers as ot', 'ot.organisation_id', '=', 'o.id')
                ->selectRaw('COUNT(DISTINCT ot.trainer_user_id) as trainers_count');
        } else {
            $query->selectRaw('0 as trainers_count');
        }

        if (Schema::hasTable('gymies_bookings') && Schema::hasColumn('gymies_bookings', 'organisation_id')) {
            $start = now()->startOfMonth()->toDateTimeString();
            $end = now()->endOfMonth()->toDateTimeString();
            $query->selectRaw('(SELECT COALESCE(SUM(b.amount_cents), 0) FROM gymies_bookings b WHERE b.organisation_id = o.id AND b.scheduled_at >= ? AND b.scheduled_at <= ? AND b.status IN ("confirmed", "completed", "no_show")) as revenue_this_month_cents', [$start, $end]);
        } else {
            $query->selectRaw('0 as revenue_this_month_cents');
        }

        $rows = $query->get();

        return response()->json(['data' => $rows]);
    }

    /** Organisatie (gym) bewerken: naam, contactmail, status, payout-frequentie. */
    public function updateOrganisation(Request $request, string $orgId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($orgId)) {
            return response()->json(['message' => 'Ongeldige organisatie id.'], 422);
        }
        $request->validate([
            'name' => 'nullable|string|max:255',
            'contact_email' => 'nullable|email|max:255',
            'status' => 'nullable|in:active,inactive,suspended',
            'payout_frequency' => 'nullable|in:weekly,biweekly,monthly',
        ]);
        if (!Schema::hasTable('gymies_organisations')) {
            return response()->json(['message' => 'Organisaties niet beschikbaar.'], 503);
        }
        $id = (int) $orgId;
        $org = DB::table('gymies_organisations')->where('id', $id)->first();
        if (!$org) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }
        $update = ['updated_at' => now()];
        if ($request->has('name')) {
            $update['name'] = trim((string) $request->input('name'));
        }
        if (Schema::hasColumn('gymies_organisations', 'contact_email') && $request->has('contact_email')) {
            $update['contact_email'] = trim((string) $request->input('contact_email')) ?: null;
        }
        if ($request->has('status')) {
            $update['status'] = (string) $request->input('status');
        }
        if ($request->has('payout_frequency')) {
            $update['payout_frequency'] = (string) $request->input('payout_frequency');
        }
        DB::table('gymies_organisations')->where('id', $id)->update($update);
        $this->audit((int) $admin->id, 'admin_organisation_updated', 'organisation', $id, $update);
        return response()->json(['ok' => true]);
    }

    public function organisationMembers(Request $request, string $orgId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($orgId)) {
            return response()->json(['message' => 'Ongeldige organisatie id.'], 422);
        }
        $rows = DB::table('gymies_organisation_members as m')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'm.user_id')
            ->where('m.organisation_id', (int) $orgId)
            ->orderByDesc('m.id')
            ->get([
                'm.id',
                'm.user_id',
                'u.email',
                'u.display_name',
                'm.role',
                'm.status',
                'm.invited_at',
                'm.joined_at',
            ]);

        return response()->json(['data' => $rows]);
    }

    public function updateOrganisationMember(Request $request, string $orgId, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($orgId) || !$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige id.'], 422);
        }
        $request->validate([
            'role' => 'nullable|in:owner,manager,viewer',
            'status' => 'nullable|in:active,inactive',
            'reason' => 'required|string|max:500',
        ]);
        $member = DB::table('gymies_organisation_members')
            ->where('organisation_id', (int) $orgId)
            ->where('user_id', (int) $userId)
            ->first();
        if (!$member) {
            return response()->json(['message' => 'Teamlid niet gevonden.'], 404);
        }

        $update = ['updated_at' => now()];
        if ($request->filled('role')) {
            $update['role'] = (string) $request->input('role');
        }
        if ($request->filled('status')) {
            $update['status'] = (string) $request->input('status');
        }
        DB::table('gymies_organisation_members')
            ->where('id', (int) $member->id)
            ->update($update);
        $this->audit((int) $admin->id, 'admin_organisation_member_updated', 'organisation_member', (int) $member->id, [
            'reason' => (string) $request->input('reason'),
            'changes' => $update,
        ]);

        return response()->json(['ok' => true]);
    }

    /** Financieel overzicht voor een organisatie: omzet, commissie, netto (optioneel periode). */
    public function organisationSettlementOverview(Request $request, string $orgId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($orgId) || !Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }
        $id = (int) $orgId;
        $org = DB::table('gymies_organisations')->where('id', $id)->first();
        if (!$org) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }
        $periodStart = trim((string) $request->query('period_start', ''));
        $periodEnd = trim((string) $request->query('period_end', ''));
        $start = $periodStart !== '' ? Carbon::parse($periodStart . ' 00:00:00') : now()->startOfMonth();
        $end = $periodEnd !== '' ? Carbon::parse($periodEnd . ' 23:59:59') : now()->endOfMonth();

        $baseQuery = fn () => DB::table('gymies_bookings')->where('organisation_id', $id)->whereBetween('scheduled_at', [$start, $end]);
        $bookingsCount = $baseQuery()->count();
        $grossCents = (int) $baseQuery()->whereIn('status', ['confirmed', 'completed', 'no_show'])->sum('amount_cents');
        $platformFeeCents = (int) round($grossCents * 0.12);
        $netCents = max($grossCents - $platformFeeCents, 0);

        return response()->json([
            'data' => [
                'organisation_id' => (string) $id,
                'organisation_name' => (string) $org->name,
                'period_start' => $start->toDateString(),
                'period_end' => $end->toDateString(),
                'bookings_count' => $bookingsCount,
                'gross_cents' => $grossCents,
                'platform_fee_cents' => $platformFeeCents,
                'net_cents' => $netCents,
            ],
        ]);
    }

    /** Settlement rapport: boekingen in periode voor één organisatie (één-klik overzicht). */
    public function organisationSettlementReport(Request $request, string $orgId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.organisations.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($orgId) || !Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }
        $id = (int) $orgId;
        $org = DB::table('gymies_organisations')->where('id', $id)->first();
        if (!$org) {
            return response()->json(['message' => 'Organisatie niet gevonden.'], 404);
        }
        $periodStart = trim((string) $request->query('period_start', ''));
        $periodEnd = trim((string) $request->query('period_end', ''));
        if ($periodStart === '' || $periodEnd === '') {
            return response()->json(['message' => 'period_start en period_end zijn verplicht.'], 422);
        }
        $start = Carbon::parse($periodStart . ' 00:00:00');
        $end = Carbon::parse($periodEnd . ' 23:59:59');

        $rows = DB::table('gymies_bookings as b')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->where('b.organisation_id', $id)
            ->whereBetween('b.scheduled_at', [$start, $end])
            ->orderBy('b.scheduled_at')
            ->get([
                'b.id',
                'b.scheduled_at',
                'b.status',
                'b.amount_cents',
                DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
            ]);

        $bookings = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'scheduled_at' => $r->scheduled_at,
            'status' => $r->status,
            'amount_cents' => (int) ($r->amount_cents ?? 0),
            'client_name' => $r->client_name ?? '',
            'trainer_name' => $r->trainer_name ?? '',
        ])->all();
        $revenueRows = $rows->filter(fn ($r) => in_array((string) $r->status, ['confirmed', 'completed', 'no_show'], true));
        $grossCents = (int) $revenueRows->sum('amount_cents');
        $feeCents = (int) round($grossCents * 0.12);
        $netCents = max($grossCents - $feeCents, 0);

        return response()->json([
            'data' => [
                'organisation_id' => (string) $id,
                'organisation_name' => (string) $org->name,
                'period_start' => $periodStart,
                'period_end' => $periodEnd,
                'bookings' => $bookings,
                'summary' => [
                    'bookings_count' => count($bookings),
                    'gross_cents' => $grossCents,
                    'platform_fee_cents' => $feeCents,
                    'net_cents' => $netCents,
                ],
            ],
        ]);
    }
}
