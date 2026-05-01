<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies\Traits;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

trait AdminFinanceTrait
{
    public function payments(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $limit = min(max((int) $request->query('limit', 200), 1), 1000);
        $rows = [];

        if (Schema::hasTable('gymies_payment_transactions')) {
            $rows = DB::table('gymies_payment_transactions')
                ->orderByDesc('id')
                ->limit($limit)
                ->get()
                ->all();
        } else {
            $rows = DB::table('gymies_bookings')
                ->orderByDesc('id')
                ->limit($limit)
                ->get([
                    'id',
                    'client_user_id',
                    'trainer_user_id',
                    'amount_cents',
                    'status',
                    'payment_provider_id',
                    'paid_at',
                    'created_at',
                ])
                ->map(static fn ($r) => [
                    'id' => (string) $r->id,
                    'booking_id' => (string) $r->id,
                    'user_id' => (string) $r->client_user_id,
                    'counterparty_user_id' => (string) $r->trainer_user_id,
                    'provider' => 'unknown',
                    'provider_transaction_id' => (string) ($r->payment_provider_id ?? ''),
                    'amount_cents' => (int) ($r->amount_cents ?? 0),
                    'status' => (string) ($r->status ?? 'unknown'),
                    'created_at' => $r->created_at,
                    'paid_at' => $r->paid_at,
                ])
                ->all();
        }

        return response()->json(['data' => $rows]);
    }

    public function promoCodes(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_promo_codes')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_promo_codes')
            ->orderByDesc('id')
            ->get()
            ->map(static fn ($r) => [
                'id' => (string) $r->id,
                'code' => (string) $r->code,
                'discount_type' => (string) $r->discount_type,
                'value_cents' => (int) $r->value_cents,
                'valid_from' => $r->valid_from,
                'valid_until' => $r->valid_until,
                'max_uses' => $r->max_uses !== null ? (int) $r->max_uses : null,
                'use_count' => (int) ($r->use_count ?? 0),
                'created_at' => $r->created_at,
            ])
            ->all();
        return response()->json(['data' => $rows]);
    }

    public function storePromoCode(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'code' => 'required|string|max:64',
            'discount_type' => 'required|string|in:percent,fixed',
            'value_cents' => 'required|integer|min:1',
            'valid_from' => 'nullable|date',
            'valid_until' => 'nullable|date',
            'max_uses' => 'nullable|integer|min:1',
        ]);
        if (!Schema::hasTable('gymies_promo_codes')) {
            return response()->json(['message' => 'Tabel gymies_promo_codes ontbreekt.'], 500);
        }
        $code = strtoupper(trim((string) $request->input('code')));
        $exists = DB::table('gymies_promo_codes')->where('code', $code)->exists();
        if ($exists) {
            return response()->json(['message' => 'Deze code bestaat al.'], 422);
        }
        $valueCents = (int) $request->input('value_cents');
        if ($request->input('discount_type') === 'percent' && ($valueCents < 1 || $valueCents > 100)) {
            return response()->json(['message' => 'Percentage moet tussen 1 en 100 liggen.'], 422);
        }
        $id = DB::table('gymies_promo_codes')->insertGetId([
            'code' => $code,
            'discount_type' => $request->input('discount_type'),
            'value_cents' => $valueCents,
            'valid_from' => $request->input('valid_from') ?: null,
            'valid_until' => $request->input('valid_until') ?: null,
            'max_uses' => $request->input('max_uses') ? (int) $request->input('max_uses') : null,
            'use_count' => 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $row = DB::table('gymies_promo_codes')->where('id', $id)->first();
        return response()->json([
            'data' => [
                'id' => (string) $row->id,
                'code' => (string) $row->code,
                'discount_type' => (string) $row->discount_type,
                'value_cents' => (int) $row->value_cents,
                'valid_from' => $row->valid_from,
                'valid_until' => $row->valid_until,
                'max_uses' => $row->max_uses ? (int) $row->max_uses : null,
                'use_count' => (int) $row->use_count,
            ],
        ], 201);
    }

    public function payouts(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payouts.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_payouts')) {
            return response()->json(['data' => []]);
        }
        $status = trim((string) $request->query('status', ''));
        $dateFrom = trim((string) $request->query('date_from', ''));
        $dateTo = trim((string) $request->query('date_to', ''));
        $limit = min(max((int) $request->query('limit', 200), 1), 1000);
        $hasGrossCents = Schema::hasColumn('gymies_payouts', 'gross_cents');
        $hasFeeCents = Schema::hasColumn('gymies_payouts', 'fee_cents');
        $hasReference = Schema::hasColumn('gymies_payouts', 'reference');
        $hasRequestedAt = Schema::hasColumn('gymies_payouts', 'requested_at');
        $hasPaidAt = Schema::hasColumn('gymies_payouts', 'paid_at');

        $query = DB::table('gymies_payouts as p')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'p.trainer_user_id')
            ->orderByDesc('p.id');
        if ($status !== '') {
            $query->where('p.status', $status);
        }
        if ($dateFrom !== '' && Schema::hasColumn('gymies_payouts', 'created_at')) {
            $query->where('p.created_at', '>=', $dateFrom);
        }
        if ($dateTo !== '') {
            $query->where('p.created_at', '<=', $dateTo . ' 23:59:59');
        }
        $rows = $query->limit($limit)->get([
                'p.id',
                'p.trainer_user_id',
                'u.email as trainer_email',
                'u.display_name as trainer_name',
                'p.amount_cents',
                $hasGrossCents ? 'p.gross_cents' : DB::raw('0 as gross_cents'),
                $hasFeeCents ? 'p.fee_cents' : DB::raw('0 as fee_cents'),
                'p.status',
                $hasReference ? 'p.reference' : DB::raw('NULL as reference'),
                $hasRequestedAt ? 'p.requested_at' : DB::raw('NULL as requested_at'),
                $hasPaidAt ? 'p.paid_at' : DB::raw('NULL as paid_at'),
            ]);

        return response()->json(['data' => $rows]);
    }

    public function updatePayoutStatus(Request $request, string $payoutId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payouts.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($payoutId)) {
            return response()->json(['message' => 'Ongeldige payout id.'], 422);
        }
        $request->validate([
            'status' => 'required|in:pending,paid,failed',
            'reason' => 'required|string|max:500',
            'reference' => 'nullable|string|max:255',
            'paid_at' => 'nullable|date',
        ]);
        if (!Schema::hasTable('gymies_payouts')) {
            return response()->json(['message' => 'Payout tabel ontbreekt.'], 422);
        }
        $id = (int) $payoutId;
        $p = DB::table('gymies_payouts')->where('id', $id)->first();
        if (!$p) {
            return response()->json(['message' => 'Payout niet gevonden.'], 404);
        }
        $status = (string) $request->input('status');
        $update = ['status' => $status, 'updated_at' => now()];
        if ($status === 'paid') {
            $update['paid_at'] = $request->input('paid_at') ? $request->input('paid_at') : now();
            if (Schema::hasColumn('gymies_payouts', 'reference')) {
                $ref = trim((string) $request->input('reference', ''));
                $update['reference'] = $ref !== '' ? $ref : null;
            }
        }
        if (Schema::hasColumn('gymies_payouts', 'reference') && $status !== 'paid') {
            $ref = trim((string) $request->input('reference', ''));
            if ($ref !== '') {
                $update['reference'] = $ref;
            }
        }
        DB::table('gymies_payouts')->where('id', $id)->update($update);

        $this->audit((int) $admin->id, 'admin_payout_status_updated', 'payout', $id, [
            'old_status' => (string) $p->status,
            'new_status' => $status,
            'reason' => (string) $request->input('reason'),
        ]);

        return response()->json(['ok' => true]);
    }

    public function trainersWithPendingPayout(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payouts.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_payouts')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_payouts as p')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'p.trainer_user_id')
            ->where('p.status', 'pending')
            ->select(['p.id', 'p.trainer_user_id', 'p.amount_cents', 'p.created_at', 'u.email as trainer_email', 'u.display_name as trainer_name'])
            ->get()
            ->all();
        return response()->json(['data' => $rows]);
    }

    public function bulkPayoutsStatus(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payouts.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_payouts')) {
            return response()->json(['message' => 'Payouts niet beschikbaar.'], 422);
        }
        $request->validate([
            'payout_ids' => 'required|array',
            'payout_ids.*' => 'integer|min:1',
            'status' => 'required|in:pending,processing,paid,failed,cancelled',
            'reason' => 'required|string|max:500',
        ]);
        $ids = array_unique(array_filter(array_map('intval', $request->input('payout_ids', []))));
        if (count($ids) > 50) {
            return response()->json(['message' => 'Maximaal 50 payouts per bulkactie.'], 422);
        }
        $status = (string) $request->input('status');
        $reason = (string) $request->input('reason');
        $update = ['status' => $status, 'updated_at' => now()];
        if ($status === 'paid' && Schema::hasColumn('gymies_payouts', 'paid_at')) {
            $update['paid_at'] = now();
        }
        $updated = DB::table('gymies_payouts')->whereIn('id', $ids)->update($update);
        foreach ($ids as $id) {
            $this->audit((int) $admin->id, 'admin_bulk_payout_status', 'payout', $id, ['status' => $status, 'reason' => $reason]);
        }
        return response()->json(['ok' => true, 'updated' => $updated]);
    }

    public function subscriptions(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_subscriptions')) {
            return response()->json(['subscriptions' => []]);
        }

        $subs = DB::table('gymies_subscriptions as s')
            ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
            ->join('gymies_users as u', 'u.id', '=', 's.trainer_user_id')
            ->select('s.*', 'p.name as plan_name', 'p.slug as plan_slug', 'p.price_cents_per_month',
                'u.display_name as trainer_name', 'u.email as trainer_email')
            ->orderByDesc('s.created_at')
            ->get();

        return response()->json(['subscriptions' => $subs]);
    }

    public function subscriptionRevenue(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_subscriptions')) {
            return response()->json(['mrr_cents' => 0, 'arr_cents' => 0, 'active_count' => 0]);
        }

        $activeSubs = DB::table('gymies_subscriptions as s')
            ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
            ->whereIn('s.status', ['active', 'trialing'])
            ->select('p.price_cents_per_month', DB::raw('COUNT(*) as cnt'))
            ->groupBy('p.price_cents_per_month')
            ->get();

        $mrrCents = 0;
        $activeCount = 0;
        foreach ($activeSubs as $row) {
            $mrrCents += (int) $row->price_cents_per_month * (int) $row->cnt;
            $activeCount += (int) $row->cnt;
        }

        $pastDueCount = (int) DB::table('gymies_subscriptions')->where('status', 'past_due')->count();
        $cancelledThisMonth = (int) DB::table('gymies_subscriptions')
            ->where('status', 'cancelled')
            ->whereMonth('cancelled_at', now()->month)
            ->whereYear('cancelled_at', now()->year)
            ->count();

        $planBreakdown = DB::table('gymies_subscriptions as s')
            ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
            ->whereIn('s.status', ['active', 'trialing'])
            ->select('p.slug', 'p.name', 'p.price_cents_per_month', DB::raw('COUNT(*) as active_count'))
            ->groupBy('p.slug', 'p.name', 'p.price_cents_per_month')
            ->get();

        return response()->json([
            'mrr_cents' => $mrrCents,
            'arr_cents' => $mrrCents * 12,
            'active_count' => $activeCount,
            'past_due_count' => $pastDueCount,
            'cancelled_this_month' => $cancelledThisMonth,
            'plan_breakdown' => $planBreakdown,
        ]);
    }
}
