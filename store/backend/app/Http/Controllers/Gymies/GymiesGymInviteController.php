<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Elite: Uitnodigingslinks voor trainers.
 */
final class GymiesGymInviteController extends GymiesGymController
{
    public function index(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_invites')) {
            return response()->json(['data' => []]);
        }

        $orgId = (int) $ctx['organisation_id'];
        $rows = DB::table('gymies_gym_invites')
            ->where('organisation_id', $orgId)
            ->orderByDesc('created_at')
            ->get();

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'organisation_id' => (string) $r->organisation_id,
            'token' => (string) $r->token,
            'expires_at' => $r->expires_at,
            'max_uses' => $r->max_uses !== null ? (int) $r->max_uses : null,
            'used_count' => (int) $r->used_count,
            'created_at' => $r->created_at,
            'updated_at' => $r->updated_at,
        ])->all();

        return response()->json(['data' => $data]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_invites')) {
            return response()->json(['message' => 'Uitnodigingen niet beschikbaar.'], 422);
        }

        $request->validate([
            'expires_at' => 'nullable|date',
            'max_uses' => 'nullable|integer|min:1|max:1000',
        ]);

        $orgId = (int) $ctx['organisation_id'];
        $userId = (int) $ctx['user_id'];

        $token = Str::random(48);
        while (DB::table('gymies_gym_invites')->where('token', $token)->exists()) {
            $token = Str::random(48);
        }

        $expiresAt = $request->filled('expires_at')
            ? \Carbon\Carbon::parse((string) $request->input('expires_at'))
            : null;
        $maxUses = $request->filled('max_uses') ? (int) $request->input('max_uses') : null;

        $id = DB::table('gymies_gym_invites')->insertGetId([
            'organisation_id' => $orgId,
            'token' => $token,
            'created_by_user_id' => $userId,
            'expires_at' => $expiresAt,
            'max_uses' => $maxUses,
            'used_count' => 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $row = DB::table('gymies_gym_invites')->where('id', $id)->first();

        return response()->json([
            'data' => [
                'id' => (string) $row->id,
                'organisation_id' => (string) $row->organisation_id,
                'token' => (string) $row->token,
                'expires_at' => $row->expires_at,
                'max_uses' => $row->max_uses !== null ? (int) $row->max_uses : null,
                'used_count' => (int) $row->used_count,
                'created_at' => $row->created_at,
                'updated_at' => $row->updated_at,
            ],
        ], 201);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_invites')) {
            return response()->json(['message' => 'Uitnodigingen niet beschikbaar.'], 422);
        }

        $orgId = (int) $ctx['organisation_id'];
        $deleted = DB::table('gymies_gym_invites')
            ->where('id', $id)
            ->where('organisation_id', $orgId)
            ->delete();

        if ($deleted === 0) {
            return response()->json(['message' => 'Uitnodiging niet gevonden.'], 404);
        }

        return response()->json(['ok' => true], 200);
    }

    /**
     * Publiek: valideer invite token (query: token).
     */
    public function validateToken(Request $request): JsonResponse
    {
        $token = trim((string) $request->query('token', ''));
        if ($token === '') {
            return response()->json(['valid' => false]);
        }

        if (!Schema::hasTable('gymies_gym_invites')) {
            return response()->json(['valid' => false]);
        }

        $row = DB::table('gymies_gym_invites as i')
            ->join('gymies_organisations as o', 'o.id', '=', 'i.organisation_id')
            ->where('i.token', $token)
            ->where('o.status', 'active')
            ->select('i.id', 'i.organisation_id', 'i.expires_at', 'i.max_uses', 'i.used_count', 'o.name as organisation_name')
            ->first();

        if (!$row) {
            return response()->json(['valid' => false]);
        }

        if ($row->expires_at !== null && \Carbon\Carbon::parse((string) $row->expires_at) < now()) {
            return response()->json(['valid' => false]);
        }

        if ($row->max_uses !== null && (int) $row->used_count >= (int) $row->max_uses) {
            return response()->json(['valid' => false]);
        }

        return response()->json([
            'valid' => true,
            'organisation_id' => (string) $row->organisation_id,
            'organisation_name' => (string) $row->organisation_name,
            'expires_at' => $row->expires_at,
        ]);
    }

    /**
     * Ingelogde trainer: accepteer invite en koppel aan gym.
     * N-019 FIXED: TOCTOU race condition opgelost met atomaire transaction + lockForUpdate
     */
    public function accept(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ((string) ($user->role ?? '') !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen via een uitnodiging aan een gym deelnemen.'], 403);
        }
        if (!Schema::hasTable('gymies_gym_invites') || !Schema::hasTable('gymies_organisation_trainers')) {
            return response()->json(['message' => 'Uitnodigingen niet beschikbaar.'], 422);
        }

        $request->validate(['token' => 'required|string|min:32']);
        $token = trim((string) $request->input('token'));

        // N-019 FIXED: TOCTOU opgelost met atomaire transaction + lockForUpdate
        // Dit voorkomt race conditions waarbij twee gelijktijdige requests beiden dezelfde invite accepteren
        return DB::transaction(function () use ($token, $user) {
            $row = DB::table('gymies_gym_invites as i')
                ->join('gymies_organisations as o', 'o.id', '=', 'i.organisation_id')
                ->where('i.token', $token)
                ->where('o.status', 'active')
                ->select('i.id', 'i.organisation_id', 'i.expires_at', 'i.max_uses', 'i.used_count', 'o.name as organisation_name')
                ->lockForUpdate()
                ->first();

            if (!$row) {
                return response()->json(['message' => 'Deze uitnodiging is ongeldig.'], 404);
            }
            if ($row->expires_at !== null && \Carbon\Carbon::parse((string) $row->expires_at) < now()) {
                return response()->json(['message' => 'Deze uitnodiging is verlopen.'], 410);
            }
            if ($row->max_uses !== null && (int) $row->used_count >= (int) $row->max_uses) {
                return response()->json(['message' => 'Deze uitnodiging is al gebruikt.'], 410);
            }

            $orgId = (int) $row->organisation_id;
            $trainerId = (int) $user->id;
            $exists = DB::table('gymies_organisation_trainers')
                ->where('organisation_id', $orgId)
                ->where('trainer_user_id', $trainerId)
                ->exists();
            if ($exists) {
                return response()->json([
                    'message' => 'Je bent al gekoppeld aan deze gym.',
                    'organisation_id' => (string) $orgId,
                    'organisation_name' => (string) $row->organisation_name,
                ], 200);
            }

            DB::table('gymies_organisation_trainers')->insert([
                'organisation_id' => $orgId,
                'trainer_user_id' => $trainerId,
                'employment_type' => 'contractor',
                'payout_route' => 'direct_trainer',
                'is_primary' => 0,
                'status' => 'active',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            DB::table('gymies_gym_invites')->where('id', $row->id)->increment('used_count');

            return response()->json([
                'message' => 'Je bent nu gekoppeld aan ' . $row->organisation_name . '.',
                'organisation_id' => (string) $orgId,
                'organisation_name' => (string) $row->organisation_name,
            ], 200);
        });
    }
}
