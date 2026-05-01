<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * GET trainers/{id}/reviews – publieke lijst van reviews voor een trainer.
 * Retourneert rating, message, is_anonymous, client_name (of "Anoniem"), created_at.
 */
class GymiesTrainerReviewsController
{
    public function index(Request $request, string $id): JsonResponse
    {
        $trainerId = (int) $id;
        if ($trainerId <= 0) {
            return response()->json(['data' => [], 'rating_avg' => null, 'count' => 0], 200);
        }

        $table = 'gymies_booking_reviews';
        if (!Schema::hasTable($table)) {
            return response()->json(['data' => [], 'rating_avg' => null, 'count' => 0], 200);
        }

        $reviews = DB::table($table)
            ->where('trainer_user_id', $trainerId)
            ->orderByDesc('created_at')
            ->get()
            ->map(function ($row) {
                $clientName = ($row->is_anonymous ?? false) ? 'Anoniem' : null;
                if ($clientName === null) {
                    $clientName = $this->resolveClientName((int) ($row->client_user_id ?? 0));
                }
                return [
                    'id' => $row->id,
                    'rating' => (int) ($row->rating ?? 0),
                    'message' => $row->message ? (string) $row->message : null,
                    'is_anonymous' => (bool) ($row->is_anonymous ?? false),
                    'client_name' => $clientName,
                    'photo_url' => isset($row->photo_url) ? (string) $row->photo_url : null,
                    'created_at' => $row->created_at ? (\Carbon\Carbon::parse($row->created_at)->toIso8601String()) : null,
                ];
            })
            ->values()
            ->all();

        $avg = DB::table($table)
            ->where('trainer_user_id', $trainerId)
            ->avg('rating');
        $count = count($reviews);

        return response()->json([
            'data' => $reviews,
            'rating_avg' => $avg !== null ? round((float) $avg, 1) : null,
            'count' => $count,
        ]);
    }

    private function resolveUsersTable(): string
    {
        return Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
    }

    private function resolveClientName(int $userId): string
    {
        if ($userId <= 0) {
            return 'Anoniem';
        }
        $usersTable = $this->resolveUsersTable();
        $user = DB::table($usersTable)->where('id', $userId)->first();
        if (!$user) {
            return 'Anoniem';
        }
        $name = trim((string) ($user->display_name ?? $user->first_name ?? $user->name ?? ''));
        if ($name !== '') {
            return explode(' ', $name)[0] ?? $name; // Alleen voornaam
        }
        $email = trim($user->email ?? '');
        if ($email !== '') {
            $part = explode('@', $email)[0] ?? '';
            return $part !== '' ? $part : 'Anoniem';
        }
        return 'Anoniem';
    }
}
