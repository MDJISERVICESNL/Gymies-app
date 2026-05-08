<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Admin Payout endpoints — voor het admin-scherm in de app.
 * Alleen toegankelijk voor admin-gebruikers.
 *
 * GET  admin/payouts          — openstaande uitbetalingen
 * GET  admin/payouts/history  — betaalde uitbetalingen
 * GET  admin/payouts/stats    — statistieken
 * GET  admin/payouts/{id}     — detail van één request
 * POST admin/payouts/{id}/mark-paid — markeer als betaald
 * POST admin/payouts/{id}/cancel    — annuleer (saldo terugboeken)
 */
class GymiesAdminPayoutController
{
    /**
     * GET admin/payouts — alle openstaande uitbetalingen.
     */
    public function pending(Request $request): JsonResponse
    {
        if (!$this->isAdmin($request)) {
            return response()->json(['message' => 'Geen toegang.'], 403);
        }

        GymiesPayoutService::ensureSchema();

        $query = DB::table('gymies_payout_requests as r')
            ->leftJoin('users as u', 'u.id', '=', 'r.user_id')
            ->where('r.status', 'pending')
            ->orderBy('r.created_at', 'asc');

        // Zoeken op naam
        $search = trim((string) $request->query('search', ''));
        if ($search !== '') {
            $query->where('u.name', 'LIKE', "%{$search}%");
        }

        $rows = $query->select([
            'r.id',
            'r.user_id',
            'u.name as trainer_name',
            'u.email as trainer_email',
            'r.amount_cents',
            'r.fee_cents',
            'r.net_amount_cents',
            'r.iban',
            'r.iban_name',
            'r.frequency',
            'r.status',
            'r.created_at',
        ])->get();

        return response()->json([
            'payouts' => $rows->map(fn ($r) => [
                'id' => $r->id,
                'user_id' => $r->user_id,
                'trainer_name' => $r->trainer_name ?? 'Onbekend',
                'trainer_email' => $r->trainer_email ?? '',
                'amount_cents' => (int) $r->amount_cents,
                'fee_cents' => (int) $r->fee_cents,
                'net_amount_cents' => (int) $r->net_amount_cents,
                'net_formatted' => '€' . number_format((int) $r->net_amount_cents / 100, 2, ',', '.'),
                'iban' => $r->iban,
                'iban_name' => $r->iban_name,
                'frequency' => $r->frequency,
                'status' => $r->status,
                'created_at' => $r->created_at,
            ])->values(),
            'total_count' => $rows->count(),
            'total_amount_cents' => $rows->sum('net_amount_cents'),
            'total_formatted' => '€' . number_format($rows->sum('net_amount_cents') / 100, 2, ',', '.'),
        ]);
    }

    /**
     * GET admin/payouts/history — betaalde uitbetalingen.
     */
    public function history(Request $request): JsonResponse
    {
        if (!$this->isAdmin($request)) {
            return response()->json(['message' => 'Geen toegang.'], 403);
        }

        GymiesPayoutService::ensureSchema();

        $limit = min(100, max(1, (int) ($request->query('limit') ?? 50)));
        $offset = max(0, (int) ($request->query('offset') ?? 0));

        $rows = DB::table('gymies_payout_requests as r')
            ->leftJoin('users as u', 'u.id', '=', 'r.user_id')
            ->whereIn('r.status', ['paid', 'cancelled', 'failed'])
            ->orderByDesc('r.paid_at')
            ->offset($offset)
            ->limit($limit)
            ->select([
                'r.id',
                'r.user_id',
                'u.name as trainer_name',
                'r.amount_cents',
                'r.fee_cents',
                'r.net_amount_cents',
                'r.iban',
                'r.iban_name',
                'r.frequency',
                'r.status',
                'r.paid_at',
                'r.admin_note',
                'r.created_at',
            ])->get();

        return response()->json([
            'payouts' => $rows->map(fn ($r) => [
                'id' => $r->id,
                'user_id' => $r->user_id,
                'trainer_name' => $r->trainer_name ?? 'Onbekend',
                'net_formatted' => '€' . number_format((int) $r->net_amount_cents / 100, 2, ',', '.'),
                'net_amount_cents' => (int) $r->net_amount_cents,
                'fee_cents' => (int) $r->fee_cents,
                'iban' => $r->iban,
                'frequency' => $r->frequency,
                'status' => $r->status,
                'paid_at' => $r->paid_at,
                'admin_note' => $r->admin_note,
                'created_at' => $r->created_at,
            ])->values(),
            'limit' => $limit,
            'offset' => $offset,
        ]);
    }

    /**
     * GET admin/payouts/stats — totaaloverzicht.
     */
    public function stats(Request $request): JsonResponse
    {
        if (!$this->isAdmin($request)) {
            return response()->json(['message' => 'Geen toegang.'], 403);
        }

        GymiesPayoutService::ensureSchema();

        $pendingCount = DB::table('gymies_payout_requests')->where('status', 'pending')->count();
        $pendingAmount = (int) DB::table('gymies_payout_requests')->where('status', 'pending')->sum('net_amount_cents');

        $paidThisMonth = (int) DB::table('gymies_payout_requests')
            ->where('status', 'paid')
            ->where('paid_at', '>=', now()->startOfMonth())
            ->sum('net_amount_cents');

        $paidThisWeek = (int) DB::table('gymies_payout_requests')
            ->where('status', 'paid')
            ->where('paid_at', '>=', now()->startOfWeek())
            ->sum('net_amount_cents');

        $totalFeesThisMonth = (int) DB::table('gymies_payout_requests')
            ->where('status', 'paid')
            ->where('paid_at', '>=', now()->startOfMonth())
            ->sum('fee_cents');

        $totalPlatformFees = (int) DB::table('gymies_payout_transactions')
            ->where('type', 'platform_fee')
            ->where('created_at', '>=', now()->startOfMonth())
            ->sum(DB::raw('ABS(amount_cents)'));

        $activeTrainers = DB::table('gymies_trainer_payouts')
            ->where('payout_mode', 'gymies')
            ->where('balance_cents', '>', 0)
            ->count();

        return response()->json([
            'pending_count' => $pendingCount,
            'pending_amount_cents' => $pendingAmount,
            'pending_formatted' => '€' . number_format($pendingAmount / 100, 2, ',', '.'),
            'paid_this_week_cents' => $paidThisWeek,
            'paid_this_week_formatted' => '€' . number_format($paidThisWeek / 100, 2, ',', '.'),
            'paid_this_month_cents' => $paidThisMonth,
            'paid_this_month_formatted' => '€' . number_format($paidThisMonth / 100, 2, ',', '.'),
            'fees_earned_this_month_cents' => $totalFeesThisMonth + $totalPlatformFees,
            'fees_formatted' => '€' . number_format(($totalFeesThisMonth + $totalPlatformFees) / 100, 2, ',', '.'),
            'active_gymies_trainers' => $activeTrainers,
        ]);
    }

    /**
     * POST admin/payouts/{id}/mark-paid — markeer als betaald.
     *
     * BUG FIX: Ensure idempotency by checking status before marking and use lock.
     */
    public function markPaid(Request $request, string $id): JsonResponse
    {
        if (!$this->isAdmin($request)) {
            return response()->json(['message' => 'Geen toegang.'], 403);
        }

        GymiesPayoutService::ensureSchema();

        try {
            DB::beginTransaction();

            // Lock and verify status
            $payoutRequest = DB::table('gymies_payout_requests')
                ->where('id', (int) $id)
                ->lockForUpdate()
                ->first();

            if (!$payoutRequest) {
                DB::rollBack();
                return response()->json(['message' => 'Uitbetaling niet gevonden.'], 404);
            }

            if ($payoutRequest->status === 'paid') {
                DB::rollBack();
                return response()->json(['message' => 'Deze uitbetaling is al gemarkeerd als betaald.'], 422);
            }

            if ($payoutRequest->status !== 'pending') {
                DB::rollBack();
                return response()->json(['message' => 'Uitbetaling kan niet meer worden gewijzigd (status: ' . $payoutRequest->status . ').'], 422);
            }

            $note = trim((string) $request->input('admin_note', ''));
            $result = GymiesPayoutService::markPaid((int) $id, $note ?: null);

            DB::commit();

            if (!$result['success']) {
                return response()->json(['message' => 'Kon uitbetaling niet markeren als betaald.'], 422);
            }

            return response()->json([
                'message' => 'Uitbetaling gemarkeerd als betaald.',
                'id' => (int) $id,
                'invoice_number' => $result['invoice_number'] ?? null,
            ]);
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('Mark payout as paid failed', [
                'payout_request_id' => (int) $id,
                'error' => $e->getMessage(),
            ]);
            return response()->json(['message' => 'Fout bij markeren: ' . $e->getMessage()], 500);
        }
    }

    /**
     * POST admin/payouts/{id}/cancel — annuleer uitbetaling, saldo terugboeken.
     *
     * BUG FIX: Validate payout request record and ensure balance never goes negative.
     */
    public function cancel(Request $request, string $id): JsonResponse
    {
        if (!$this->isAdmin($request)) {
            return response()->json(['message' => 'Geen toegang.'], 403);
        }

        GymiesPayoutService::ensureSchema();

        try {
            DB::beginTransaction();

            $payoutRequest = DB::table('gymies_payout_requests')
                ->where('id', (int) $id)
                ->lockForUpdate()
                ->first();

            if (!$payoutRequest) {
                DB::rollBack();
                return response()->json(['message' => 'Uitbetaling niet gevonden.'], 404);
            }

            if ($payoutRequest->status !== 'pending') {
                DB::rollBack();
                return response()->json(['message' => 'Uitbetaling is al verwerkt en kan niet meer worden geannuleerd.'], 422);
            }

            // Validate amounts
            $netAmount = (int) ($payoutRequest->net_amount_cents ?? 0);
            $feeAmount = (int) ($payoutRequest->fee_cents ?? 0);
            if ($netAmount < 0 || $feeAmount < 0) {
                DB::rollBack();
                return response()->json(['message' => 'Ongeldige bedragen in uitbetalingsverzoek.'], 422);
            }

            // Status naar cancelled
            DB::table('gymies_payout_requests')->where('id', (int) $id)->update([
                'status' => 'cancelled',
                'admin_note' => trim((string) $request->input('reason', 'Geannuleerd door admin')),
                'updated_at' => now(),
            ]);

            // Saldo + fee terugboeken (atomic increment)
            $totalRefund = $netAmount + $feeAmount;
            DB::table('gymies_trainer_payouts')
                ->where('user_id', $payoutRequest->user_id)
                ->increment('balance_cents', $totalRefund);

            // Transacties op cancelled zetten
            DB::table('gymies_payout_transactions')
                ->where('payout_request_id', (int) $id)
                ->update(['status' => 'cancelled', 'updated_at' => now()]);

            DB::commit();

            return response()->json(['message' => 'Uitbetaling geannuleerd, saldo teruggestort.']);
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('Payout cancellation failed', [
                'payout_request_id' => (int) $id,
                'error' => $e->getMessage(),
            ]);
            return response()->json(['message' => 'Fout bij annuleren: ' . $e->getMessage()], 500);
        }
    }

    /**
     * GET admin/payouts/trainers — overzicht alle trainers met saldo.
     */
    public function trainers(Request $request): JsonResponse
    {
        if (!$this->isAdmin($request)) {
            return response()->json(['message' => 'Geen toegang.'], 403);
        }

        GymiesPayoutService::ensureSchema();

        $query = DB::table('gymies_trainer_payouts as p')
            ->leftJoin('users as u', 'u.id', '=', 'p.user_id')
            ->orderByDesc('p.balance_cents');

        $search = trim((string) $request->query('search', ''));
        if ($search !== '') {
            $query->where('u.name', 'LIKE', "%{$search}%");
        }

        $rows = $query->select([
            'p.user_id',
            'u.name as trainer_name',
            'u.email as trainer_email',
            'p.balance_cents',
            'p.payout_frequency',
            'p.payout_mode',
            'p.iban',
            'p.total_earned_cents',
            'p.total_paid_out_cents',
            'p.last_payout_at',
        ])->limit(200)->get();

        return response()->json([
            'trainers' => $rows->map(fn ($r) => [
                'user_id' => $r->user_id,
                'trainer_name' => $r->trainer_name ?? 'Onbekend',
                'trainer_email' => $r->trainer_email ?? '',
                'balance_formatted' => '€' . number_format((int) $r->balance_cents / 100, 2, ',', '.'),
                'balance_cents' => (int) $r->balance_cents,
                'payout_frequency' => $r->payout_frequency,
                'payout_mode' => $r->payout_mode,
                'has_iban' => !empty($r->iban),
                'total_earned_formatted' => '€' . number_format((int) $r->total_earned_cents / 100, 2, ',', '.'),
                'total_paid_out_formatted' => '€' . number_format((int) $r->total_paid_out_cents / 100, 2, ',', '.'),
                'last_payout_at' => $r->last_payout_at,
            ])->values(),
        ]);
    }

    /**
     * GET admin/payouts/invoices — alle facturen (betaalde payouts met factuurnummer).
     * Kan gefilterd worden op jaar, maand, trainer.
     */
    public function invoices(Request $request): JsonResponse
    {
        if (!$this->isAdmin($request)) {
            return response()->json(['message' => 'Geen toegang.'], 403);
        }

        GymiesPayoutService::ensureSchema();

        $query = DB::table('gymies_payout_requests as r')
            ->leftJoin('users as u', 'u.id', '=', 'r.user_id')
            ->whereNotNull('r.invoice_number')
            ->where('r.status', 'paid')
            ->orderByDesc('r.paid_at');

        // Filters
        $year = $request->query('year');
        if ($year) {
            $query->whereYear('r.paid_at', (int) $year);
        }

        $month = $request->query('month');
        if ($month) {
            $query->whereMonth('r.paid_at', (int) $month);
        }

        $trainerId = $request->query('trainer_id');
        if ($trainerId) {
            $query->where('r.user_id', (int) $trainerId);
        }

        $search = trim((string) $request->query('search', ''));
        if ($search !== '') {
            $query->where(function ($q) use ($search) {
                $q->where('r.invoice_number', 'LIKE', "%{$search}%")
                  ->orWhere('u.name', 'LIKE', "%{$search}%")
                  ->orWhere('r.iban_name', 'LIKE', "%{$search}%");
            });
        }

        $rows = $query->select([
            'r.id',
            'r.user_id',
            'u.name as trainer_name',
            'r.invoice_number',
            'r.amount_cents',
            'r.fee_cents',
            'r.net_amount_cents',
            'r.iban',
            'r.iban_name',
            'r.frequency',
            'r.paid_at',
            'r.created_at',
            'r.admin_note',
        ])->limit(500)->get();

        return response()->json([
            'invoices' => $rows->map(fn ($r) => [
                'id' => $r->id,
                'invoice_number' => $r->invoice_number,
                'trainer_name' => $r->trainer_name ?? $r->iban_name ?? 'Onbekend',
                'user_id' => $r->user_id,
                'amount_formatted' => '€' . number_format((int) $r->amount_cents / 100, 2, ',', '.'),
                'fee_formatted' => '€' . number_format((int) $r->fee_cents / 100, 2, ',', '.'),
                'net_amount_formatted' => '€' . number_format((int) $r->net_amount_cents / 100, 2, ',', '.'),
                'net_amount_cents' => (int) $r->net_amount_cents,
                'iban' => $r->iban,
                'iban_name' => $r->iban_name,
                'frequency' => $r->frequency,
                'paid_at' => $r->paid_at,
                'created_at' => $r->created_at,
                'admin_note' => $r->admin_note,
            ])->values(),
            'total_count' => $rows->count(),
            'total_net_cents' => $rows->sum(fn ($r) => (int) $r->net_amount_cents),
            'total_net_formatted' => '€' . number_format($rows->sum(fn ($r) => (int) $r->net_amount_cents) / 100, 2, ',', '.'),
        ]);
    }

    private function isAdmin(Request $request): bool
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return false;
        }
        // Check admin flag (role = admin of is_admin = true)
        if (!empty($user->is_admin) || ($user->role ?? '') === 'admin') {
            return true;
        }
        // Fallback: check gymies_admins tabel
        try {
            return DB::table('gymies_admins')->where('user_id', $user->id)->exists();
        } catch (\Throwable $e) {
            return false;
        }
    }
}
