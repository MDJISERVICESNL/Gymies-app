<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Klant-favorieten: trainers als favoriet bewaren (server-driven).
 */
final class GymiesFavoritesController extends Controller
{
    /**
     * GET /me/favorites – lijst trainer_user_ids van favorieten.
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $userId = (int) $user->id;

        GymiesSchemaEnsure::favoritesTable();
        if (!Schema::hasTable('gymies_favorites')) {
            return response()->json(['trainer_ids' => [], 'total_count' => 0, 'page' => 1, 'per_page' => 50]);
        }

        // Add pagination
        $limit = min(100, max(1, (int) ($request->query('limit') ?? 50)));
        $offset = max(0, (int) ($request->query('offset') ?? 0));

        $query = DB::table('gymies_favorites')
            ->where('client_user_id', $userId);

        $totalCount = $query->count();

        $ids = $query
            ->orderByDesc('created_at')
            ->limit($limit)
            ->offset($offset)
            ->pluck('trainer_user_id')
            ->map(fn ($id) => (string) $id)
            ->all();

        return response()->json([
            'trainer_ids' => $ids,
            'total_count' => $totalCount,
            'page' => (int) ceil(($offset / $limit) + 1),
            'per_page' => $limit,
            'total_pages' => ceil($totalCount / $limit),
        ]);
    }

    /**
     * POST /me/favorites – voeg trainer toe als favoriet.
     */
    public function store(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $request->validate([
            'trainer_user_id' => 'required|exists:gymies_users,id',
        ]);
        $clientId = (int) $user->id;
        $trainerId = (int) $request->input('trainer_user_id');

        GymiesSchemaEnsure::favoritesTable();
        if (!Schema::hasTable('gymies_favorites')) {
            return response()->json(['message' => 'Favorieten nog niet beschikbaar.'], 503);
        }

        $exists = DB::table('gymies_favorites')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->exists();
        if (!$exists) {
            DB::table('gymies_favorites')->insert([
                'client_user_id' => $clientId,
                'trainer_user_id' => $trainerId,
                'created_at' => now(),
            ]);
        }

        return response()->json(['ok' => true, 'message' => 'Toegevoegd aan favorieten.']);
    }

    /**
     * DELETE /me/favorites/{trainerId} – verwijder favoriet.
     */
    public function destroy(Request $request, string $trainerId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $clientId = (int) $user->id;
        $trainerIdInt = (int) $trainerId;

        if (Schema::hasTable('gymies_favorites')) {
            // T-044 FIXED: ownership check voor favoriet verwijderen
            $exists = DB::table('gymies_favorites')
                ->where('client_user_id', $clientId)
                ->where('trainer_user_id', $trainerIdInt)
                ->exists();
            if (!$exists) {
                return response()->json(['message' => 'Favoriet niet gevonden.'], 404);
            }

            DB::table('gymies_favorites')
                ->where('client_user_id', $clientId)
                ->where('trainer_user_id', $trainerIdInt)
                ->delete();
        }

        return response()->json(['ok' => true, 'message' => 'Verwijderd uit favorieten.']);
    }
}
