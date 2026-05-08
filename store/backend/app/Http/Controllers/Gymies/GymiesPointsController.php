<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies API: punten balans, geschiedenis, en inlossing.
 * Tabellen: gymies_points_ledger, gymies_points_redemptions, gymies_users.
 */
final class GymiesPointsController extends Controller
{
    /**
     * GET /api/gymies/points/balance
     * Geeft huiding saldo + recente transacties van ingelogde user.
     * N-035 FIXED: integer arithmetic voor puntenberekening without float imprecision
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function balance(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_points_ledger') || !Schema::hasColumn('gymies_users', 'gymies_points')) {
            return response()->json([
                'data' => [
                    'current_balance' => 0,
                    'recent_transactions' => [],
                ],
            ]);
        }

        $userId = (int) $user->id;
        $balance = GymiesPointsService::getBalance($userId);
        $ledger = GymiesPointsService::getLedger($userId, 10);

        return response()->json([
            'data' => [
                'current_balance' => $balance,
                'recent_transactions' => $ledger,
            ],
        ]);
    }

    /**
     * GET /api/gymies/points/history
     * Volledige ledger van ingelogde user (paginated, 50 per pagina).
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function history(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_points_ledger')) {
            return response()->json([
                'data' => [],
                'pagination' => [
                    'page' => 1,
                    'limit' => 50,
                    'total' => 0,
                ],
            ]);
        }

        $userId = (int) $user->id;
        // BUG-005: Add strict pagination bounds to prevent unbounded queries
        $page = max(1, min((int) ($request->input('page') ?? 1), 10000)); // Cap max page to prevent DoS
        $limit = 50; // Fixed limit, not configurable
        $offset = ($page - 1) * $limit;

        // Haal totaal aantal transacties
        $total = \Illuminate\Support\Facades\DB::table('gymies_points_ledger')
            ->where('user_id', $userId)
            ->count();

        // Haal pagina op
        $transactions = \Illuminate\Support\Facades\DB::table('gymies_points_ledger')
            ->where('user_id', $userId)
            ->orderByDesc('created_at')
            ->offset($offset)
            ->limit($limit)
            ->get(['id', 'user_id', 'delta', 'balance_after', 'event_type', 'description', 'ref_id', 'ref_table', 'created_at'])
            ->map(fn ($row) => [
                'id' => (int) $row->id,
                'user_id' => (int) $row->user_id,
                'delta' => (int) $row->delta,
                'balance_after' => (int) $row->balance_after,
                'event_type' => (string) $row->event_type,
                'description' => $row->description ? (string) $row->description : null,
                'ref_id' => $row->ref_id ? (int) $row->ref_id : null,
                'ref_table' => $row->ref_table ? (string) $row->ref_table : null,
                'created_at' => $row->created_at,
            ])
            ->all();

        return response()->json([
            'data' => $transactions,
            'pagination' => [
                'page' => $page,
                'limit' => $limit,
                'total' => $total,
                'total_pages' => (int) ceil($total / $limit),
            ],
        ]);
    }

    /**
     * POST /api/gymies/points/redeem
     * Punten besteden voor een beloning.
     *
     * Body:
     * {
     *   "reward_type": "session_credit" | "free_session",
     *   "points_to_spend": int
     * }
     *
     * @param Request $request
     * @return JsonResponse
     */
    public function redeem(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $request->validate([
            'reward_type' => 'required|string|in:session_credit,free_session',
            'points_to_spend' => 'required|integer|min:1',
        ]);

        $userId = (int) $user->id;
        $rewardType = trim((string) $request->input('reward_type'));
        $pointsToSpend = (int) $request->input('points_to_spend');

        $result = GymiesPointsService::redeem($userId, $rewardType, $pointsToSpend);

        if (!$result['ok']) {
            return response()->json([
                'message' => $result['message'],
            ], 422);
        }

        // Haal huidig saldo op
        $newBalance = GymiesPointsService::getBalance($userId);

        return response()->json([
            'message' => $result['message'],
            'data' => [
                'redemption_id' => $result['redemption_id'],
                'reward_type' => $rewardType,
                'points_spent' => $pointsToSpend,
                'new_balance' => $newBalance,
            ],
        ]);
    }
}
