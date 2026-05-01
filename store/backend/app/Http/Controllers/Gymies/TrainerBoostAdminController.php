<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Admin: trainer boost – zet trainer in top 5 van zijn stad.
 *
 * POST vault-console/trainers/{trainerUserId}/boost
 * Body: { "boosted_until": "2025-03-21T23:59:59" }  (ISO datetime)
 *
 * GET vault-console/trainers/{trainerUserId}/boost
 * Haalt huidige boost-status op.
 */
class TrainerBoostAdminController
{
    private function profileTable(): ?string
    {
        if (Schema::hasTable('gymies_trainer_profiles')) {
            return 'gymies_trainer_profiles';
        }
        return null;
    }

    private function trainerIdColumn(): string
    {
        return Schema::hasColumn('gymies_trainer_profiles', 'user_id') ? 'user_id' : 'trainer_id';
    }

    /**
     * POST trainers/{trainerUserId}/boost
     */
    public function setBoost(Request $request, string $trainerUserId): JsonResponse
    {
        $table = $this->profileTable();
        if (!$table) {
            return response()->json(['message' => 'Tabel niet gevonden.'], 500);
        }

        $boostedUntil = $request->input('boosted_until');
        if (empty($boostedUntil)) {
            return response()->json(['message' => 'boosted_until is verplicht (ISO datetime).'], 422);
        }

        $parsed = \DateTime::createFromFormat(\DateTime::ATOM, $boostedUntil)
            ?: \DateTime::createFromFormat('Y-m-d H:i:s', $boostedUntil)
            ?: \DateTime::createFromFormat('Y-m-d', $boostedUntil);

        if (!$parsed) {
            return response()->json(['message' => 'Ongeldig datumformaat voor boosted_until.'], 422);
        }

        $col = $this->trainerIdColumn();
        $updated = DB::table($table)
            ->where($col, (int) $trainerUserId)
            ->update(['boosted_until' => $parsed->format('Y-m-d H:i:s')]);

        return response()->json([
            'success' => true,
            'trainer_user_id' => $trainerUserId,
            'boosted_until' => $parsed->format('c'),
            'rows_updated' => $updated,
        ]);
    }

    /**
     * GET trainers/{trainerUserId}/boost
     */
    public function getBoost(string $trainerUserId): JsonResponse
    {
        $table = $this->profileTable();
        if (!$table) {
            return response()->json(['message' => 'Tabel niet gevonden.'], 500);
        }

        $col = $this->trainerIdColumn();
        $row = DB::table($table)
            ->where($col, (int) $trainerUserId)
            ->first(['boosted_until']);

        $boostedUntil = $row?->boosted_until ?? null;

        return response()->json([
            'trainer_user_id' => $trainerUserId,
            'boosted_until' => $boostedUntil ? (new \DateTime($boostedUntil))->format('c') : null,
            'is_boosted' => $boostedUntil && (new \DateTime($boostedUntil)) > new \DateTime(),
        ]);
    }

    /**
     * DELETE trainers/{trainerUserId}/boost
     * Verwijder boost.
     */
    public function removeBoost(string $trainerUserId): JsonResponse
    {
        $table = $this->profileTable();
        if (!$table) {
            return response()->json(['message' => 'Tabel niet gevonden.'], 500);
        }

        $col = $this->trainerIdColumn();
        $updated = DB::table($table)
            ->where($col, (int) $trainerUserId)
            ->update(['boosted_until' => null]);

        return response()->json([
            'success' => true,
            'trainer_user_id' => $trainerUserId,
            'rows_updated' => $updated,
        ]);
    }
}
