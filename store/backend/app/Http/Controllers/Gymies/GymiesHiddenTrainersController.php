<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Klant: verborgen trainers — trainers die de klant niet meer wil zien in zoekresultaten.
 * Tabel: gymies_hidden_trainers (self-heal via GymiesSchemaEnsure).
 */
final class GymiesHiddenTrainersController extends Controller
{
    /**
     * GET /me/hidden-trainers – lijst trainer_user_ids die verborgen zijn.
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        GymiesSchemaEnsure::hiddenTrainersTable();
        if (!Schema::hasTable('gymies_hidden_trainers')) {
            return response()->json(['trainer_ids' => []]);
        }

        $ids = DB::table('gymies_hidden_trainers')
            ->where('client_user_id', (int) $user->id)
            ->pluck('trainer_user_id')
            ->map(fn ($id) => (string) $id)
            ->all();

        return response()->json(['trainer_ids' => $ids]);
    }

    /**
     * POST /me/hidden-trainers – verberg trainer.
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

        GymiesSchemaEnsure::hiddenTrainersTable();
        if (!Schema::hasTable('gymies_hidden_trainers')) {
            return response()->json(['message' => 'Verborgen trainers nog niet beschikbaar.'], 503);
        }

        $exists = DB::table('gymies_hidden_trainers')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->exists();
        if (!$exists) {
            DB::table('gymies_hidden_trainers')->insert([
                'client_user_id' => $clientId,
                'trainer_user_id' => $trainerId,
                'created_at' => now(),
            ]);
        }

        return response()->json(['ok' => true, 'message' => 'Trainer verborgen.']);
    }

    /**
     * DELETE /me/hidden-trainers/{trainerId} – maak trainer weer zichtbaar.
     */
    public function destroy(Request $request, string $trainerId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $clientId = (int) $user->id;
        $trainerIdInt = (int) $trainerId;

        if (Schema::hasTable('gymies_hidden_trainers')) {
            DB::table('gymies_hidden_trainers')
                ->where('client_user_id', $clientId)
                ->where('trainer_user_id', $trainerIdInt)
                ->delete();
        }

        return response()->json(['ok' => true, 'message' => 'Trainer weer zichtbaar.']);
    }
}
