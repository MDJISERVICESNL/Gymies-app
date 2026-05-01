<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Gymies API: wachtlijst voor trainer-beschikbaarheid.
 * Tabel: gymies_waitlist.
 *
 * Klanten kunnen zich op de wachtlijst zetten als een trainer
 * geen beschikbare slots heeft. Trainers kunnen wachtlijst-entries
 * zien en notificaties sturen als er een plek vrijkomt.
 */
final class GymiesWaitlistController extends Controller
{
    // ──────────────────────────────────────────────────────────────
    //  GET  waitlist          → alle entries van de ingelogde user
    //  GET  waitlist/me       → alias
    // ──────────────────────────────────────────────────────────────
    public function index(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');

        $entries = DB::table('gymies_waitlist')
            ->where('client_user_id', $user->id)
            ->orderByDesc('created_at')
            ->get()
            ->map(fn ($row) => $this->formatEntry($row));

        return response()->json([
            'data'    => $entries,
            'success' => true,
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    //  POST  waitlist         → klant plaatst zichzelf op wachtlijst
    // ──────────────────────────────────────────────────────────────
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'trainer_user_id' => 'required|integer|exists:gymies_users,id',
            'preferred_at'    => 'nullable|date',
            'note'            => 'nullable|string|max:500',
            'preferred_date_from' => 'nullable|date',
            'preferred_date_to'   => 'nullable|date|after_or_equal:preferred_date_from',
            'availability_slot_id' => 'nullable|integer',
        ]);

        $user      = $request->attributes->get('gymies_user');
        $trainerId = (int) ($request->input('trainer_user_id') ?? $request->input('trainer_id'));

        // Voorkom dubbele entries voor dezelfde trainer
        $existing = DB::table('gymies_waitlist')
            ->where('client_user_id', $user->id)
            ->where('trainer_user_id', $trainerId)
            ->first();

        if ($existing) {
            return response()->json([
                'message' => 'Je staat al op de wachtlijst voor deze trainer.',
                'data'    => $this->formatEntry($existing),
                'success' => true,
            ]);
        }

        $preferredAt = $request->input('preferred_at')
            ? Carbon::parse($request->input('preferred_at'))
            : null;

        $id = DB::table('gymies_waitlist')->insertGetId([
            'client_user_id'             => $user->id,
            'trainer_user_id'            => $trainerId,
            'requested_for_scheduled_at' => $preferredAt,
            'availability_slot_id'       => $request->input('availability_slot_id'),
            'preferred_date_from'        => $request->input('preferred_date_from'),
            'preferred_date_to'          => $request->input('preferred_date_to'),
            'notes'                      => $request->input('note') ?? $request->input('notes'),
            'created_at'                 => now(),
        ]);

        $entry = DB::table('gymies_waitlist')->where('id', $id)->first();

        return response()->json([
            'message' => 'Je staat nu op de wachtlijst.',
            'data'    => $this->formatEntry($entry),
            'success' => true,
        ], 201);
    }

    // ──────────────────────────────────────────────────────────────
    //  DELETE  waitlist/{id}  → klant verwijdert zichzelf van wachtlijst
    // ──────────────────────────────────────────────────────────────
    public function destroy(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');

        // N-032 FIXED: validate user ownership before deletion
        $entry = DB::table('gymies_waitlist')
            ->where('id', (int) $id)
            ->where('client_user_id', $user->id)
            ->first();

        if (!$entry) {
            return response()->json([
                'message' => 'Wachtlijst-entry niet gevonden of geen toegang.',
                'success' => false,
            ], 403);
        }

        $deleted = DB::table('gymies_waitlist')
            ->where('id', (int) $id)
            ->where('client_user_id', $user->id)
            ->delete();

        if (! $deleted) {
            return response()->json([
                'message' => 'Wachtlijst-entry niet gevonden of al verwijderd.',
                'success' => false,
            ], 404);
        }

        return response()->json([
            'message' => 'Je bent van de wachtlijst verwijderd.',
            'success' => true,
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    //  POST  bookings/{id}/waitlist/notify  → trainer notificeert wachtlijst
    // ──────────────────────────────────────────────────────────────
    public function notify(Request $request, string $bookingId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');

        // Zoek de booking om trainer te verifiëren
        $booking = DB::table('gymies_bookings')
            ->where('id', (int) $bookingId)
            ->first();

        if (! $booking) {
            return response()->json([
                'message' => 'Boeking niet gevonden.',
                'success' => false,
            ], 404);
        }

        // Alleen de trainer mag notificaties sturen
        if ((int) $booking->trainer_user_id !== (int) $user->id) {
            return response()->json([
                'message' => 'Alleen de trainer kan wachtlijst-notificaties sturen.',
                'success' => false,
            ], 403);
        }

        // Haal wachtlijst-entries op voor deze trainer
        $entries = DB::table('gymies_waitlist')
            ->where('trainer_user_id', $user->id)
            ->get();

        if ($entries->isEmpty()) {
            return response()->json([
                'message' => 'Geen klanten op de wachtlijst.',
                'success' => true,
                'notified_count' => 0,
            ]);
        }

        // Stuur notificatie naar elke wachtlijst-klant
        foreach ($entries as $entry) {
            DB::table('gymies_notifications')->insert([
                'user_id'    => $entry->client_user_id,
                'event_type' => 'waitlist_slot_available',
                'title'      => 'Plek vrijgekomen!',
                'body'       => 'Er is een plek vrijgekomen bij je trainer. Boek snel een sessie!',
                'payload'    => json_encode([
                    'booking_id'      => (int) $bookingId,
                    'trainer_user_id' => $user->id,
                    'source'          => $request->input('source', 'trainer_cancel'),
                ]),
                'read_at'    => null,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        return response()->json([
            'message'        => $entries->count() . ' klant(en) genotificeerd.',
            'success'        => true,
            'notified_count' => $entries->count(),
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    //  POST  waitlist/{id}/accept  → klant accepteert wachtlijst-aanbod
    // ──────────────────────────────────────────────────────────────
    public function accept(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');

        $entry = DB::table('gymies_waitlist')
            ->where('id', (int) $id)
            ->where('client_user_id', $user->id)
            ->first();

        if (! $entry) {
            return response()->json([
                'message' => 'Wachtlijst-entry niet gevonden.',
                'success' => false,
            ], 404);
        }

        // Verwijder de entry van de wachtlijst (klant gaat boeken)
        DB::table('gymies_waitlist')->where('id', (int) $id)->delete();

        return response()->json([
            'message' => 'Wachtlijst-aanbod geaccepteerd. Je kunt nu een sessie boeken.',
            'data'    => [
                'trainer_user_id'   => $entry->trainer_user_id,
                'slot_id'           => $entry->availability_slot_id,
                'preferred_at'      => $entry->requested_for_scheduled_at,
            ],
            'success' => true,
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    //  GET  trainer/waitlist  → trainer bekijkt eigen wachtlijst
    // ──────────────────────────────────────────────────────────────
    public function trainerIndex(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');

        $entries = DB::table('gymies_waitlist as w')
            ->join('gymies_users as u', 'u.id', '=', 'w.client_user_id')
            ->where('w.trainer_user_id', $user->id)
            ->orderByDesc('w.created_at')
            ->select([
                'w.*',
                'u.first_name',
                'u.last_name',
                'u.email',
                'u.profile_photo',
            ])
            ->get()
            ->map(function ($row) {
                $formatted = $this->formatEntry($row);
                $formatted['client'] = [
                    'first_name'    => $row->first_name ?? null,
                    'last_name'     => $row->last_name ?? null,
                    'email'         => $row->email ?? null,
                    'profile_photo' => $row->profile_photo ?? null,
                ];
                return $formatted;
            });

        return response()->json([
            'data'    => $entries,
            'success' => true,
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────────────────────
    private function formatEntry(object $row): array
    {
        return [
            'id'                         => (int) $row->id,
            'client_user_id'             => (int) $row->client_user_id,
            'trainer_user_id'            => (int) $row->trainer_user_id,
            'requested_for_scheduled_at' => $row->requested_for_scheduled_at ?? null,
            'availability_slot_id'       => $row->availability_slot_id ? (int) $row->availability_slot_id : null,
            'preferred_date_from'        => $row->preferred_date_from ?? null,
            'preferred_date_to'          => $row->preferred_date_to ?? null,
            'notes'                      => $row->notes ?? null,
            'created_at'                 => $row->created_at ?? null,
        ];
    }
}
