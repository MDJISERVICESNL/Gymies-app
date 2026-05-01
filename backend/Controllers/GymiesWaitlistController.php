<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Wachtlijst / standby: klant ziet waar hij op de wachtlijst staat per trainer.
 * GET bookings/standby/me – mijn wachtlijst-inschrijvingen
 * POST bookings/standby – inschrijven op wachtlijst van trainer
 * DELETE bookings/standby/{id} – uitschrijven
 */
class GymiesWaitlistController
{
    public function me(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        if (!Schema::hasTable('gymies_waitlist')) {
            return response()->json(['data' => []]);
        }

        $rows = DB::table('gymies_waitlist as w')
            ->leftJoin('gymies_users as t', 't.id', '=', 'w.trainer_user_id')
            ->where('w.client_user_id', (int) $user->id)
            ->orderByDesc('w.created_at')
            ->get([
                'w.id',
                'w.trainer_user_id',
                'w.requested_for_scheduled_at',
                'w.availability_slot_id',
                'w.preferred_date_from',
                'w.preferred_date_to',
                'w.notes',
                'w.created_at',
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
            ]);

        $data = $rows->map(function ($row) {
            $preferredAt = $row->requested_for_scheduled_at
                ?? $row->preferred_date_from
                ?? $row->created_at;
            return [
                'id' => (string) $row->id,
                'waitlist_id' => (string) $row->id,
                'trainer_user_id' => (string) ($row->trainer_user_id ?? ''),
                'trainer_name' => (string) ($row->trainer_name ?? 'Trainer'),
                'trainerName' => (string) ($row->trainer_name ?? 'Trainer'),
                'preferred_at' => $preferredAt,
                'preferredAt' => $preferredAt,
                'requested_for_scheduled_at' => $row->requested_for_scheduled_at,
                'availability_slot_id' => $row->availability_slot_id,
                'note' => (string) ($row->notes ?? ''),
                'notes' => (string) ($row->notes ?? ''),
                'created_at' => $row->created_at,
            ];
        })->values()->all();

        return response()->json(['data' => $data]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $request->validate([
            'trainer_user_id' => 'required|integer|min:1',
            'trainer_id' => 'nullable|integer|min:1',
            'preferred_at' => 'nullable|date',
            'note' => 'nullable|string|max:500',
        ]);

        $trainerId = (int) ($request->input('trainer_user_id') ?? $request->input('trainer_id') ?? 0);
        if ($trainerId < 1) {
            return response()->json(['message' => 'Trainer-ID ontbreekt.'], 422);
        }

        if (!Schema::hasTable('gymies_waitlist')) {
            return response()->json(['message' => 'Wachtlijst niet beschikbaar.'], 503);
        }

        $preferredAt = $request->input('preferred_at');
        $preferredFrom = $preferredAt ? date('Y-m-d H:i:s', strtotime($preferredAt)) : null;
        $preferredTo = $preferredAt ? date('Y-m-d H:i:s', strtotime($preferredAt) + 86400) : null;

        $id = DB::table('gymies_waitlist')->insertGetId([
            'client_user_id' => (int) $user->id,
            'trainer_user_id' => $trainerId,
            'requested_for_scheduled_at' => $preferredFrom,
            'preferred_date_from' => $preferredFrom,
            'preferred_date_to' => $preferredTo,
            'notes' => trim((string) $request->input('note', '')),
            'created_at' => now(),
        ]);

        return response()->json([
            'data' => ['id' => (string) $id],
            'message' => 'Je staat op de wachtlijst.',
        ]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        if (!Schema::hasTable('gymies_waitlist')) {
            return response()->json(['message' => 'Wachtlijst niet beschikbaar.'], 503);
        }

        $deleted = DB::table('gymies_waitlist')
            ->where('id', (int) $id)
            ->where('client_user_id', (int) $user->id)
            ->delete();

        if ($deleted === 0) {
            return response()->json(['message' => 'Inschrijving niet gevonden.'], 404);
        }

        return response()->json(['message' => 'Uitgeschreven van wachtlijst.']);
    }
}
