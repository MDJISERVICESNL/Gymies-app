<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * GYMIES Buddy System — duo-training & matchmaking.
 *
 * Invite flow (vriend uitnodigen):
 *   POST   buddy/create-invite         — maak invite aan bij duo-boeking
 *   GET    buddy/invite/{token}         — haal invite details op
 *   POST   buddy/accept                 — accepteer invite, maak buddy-booking
 *   POST   buddy/decline                — weiger invite
 *
 * Matchmaking flow (vreemden matchen):
 *   GET    buddy/pool                   — bekijk pool (optioneel)
 *   POST   buddy/pool/join              — schrijf je in met voorkeuren
 *   POST   buddy/pool/leave             — schrijf je uit
 *   GET    buddy/my-matches             — haal je matches op
 *   POST   buddy/pool/dismiss           — blokkeer een match
 */
class GymiesBuddyController
{
    // ═══════════════════════════════════════════════════════════════
    // INVITE FLOW
    // ═══════════════════════════════════════════════════════════════

    /**
     * POST buddy/create-invite — Lisa maakt een duo-invite aan.
     */
    public function createInvite(Request $request): JsonResponse
    {
        $user = $this->authUser($request);
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $request->validate([
            'booking_id'        => 'required|integer|min:1',
            'trainer_user_id'   => 'required|integer|min:1',
            'scheduled_at'      => 'required|date',
            'amount_cents'      => 'nullable|integer|min:0',
            'gender_preference' => 'nullable|in:female,male',
        ]);

        $bookingId = (int) $request->input('booking_id');
        $trainerId = (int) $request->input('trainer_user_id');

        // Controleer of de booking bestaat en van deze user is
        $booking = DB::table('gymies_bookings')
            ->where('id', $bookingId)
            ->where('client_user_id', $user->id)
            ->first();

        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        // Controleer of trainer duo-training aanbiedt
        if (Schema::hasTable('gymies_trainer_profiles') && Schema::hasColumn('gymies_trainer_profiles', 'offers_duo_training')) {
            $profile = DB::table('gymies_trainer_profiles')
                ->where('user_id', $trainerId)
                ->first(['offers_duo_training']);
            if ($profile && !(int) ($profile->offers_duo_training ?? 0)) {
                return response()->json(['message' => 'Deze trainer biedt geen duo-training aan.'], 422);
            }
        }

        // Verwijder eventuele eerdere pending invite voor deze booking
        DB::table('gymies_buddy_bookings')
            ->where('booking_id', $bookingId)
            ->where('status', 'pending')
            ->delete();

        $token = Str::random(48);
        $expiresAt = now()->addHours(24);

        $id = DB::table('gymies_buddy_bookings')->insertGetId([
            'booking_id'        => $bookingId,
            'initiator_user_id' => (int) $user->id,
            'invite_token'      => $token,
            'gender_preference' => $request->input('gender_preference'),
            'status'            => 'pending',
            'trainer_user_id'   => $trainerId,
            'scheduled_at'      => $request->input('scheduled_at'),
            'amount_cents'      => (int) ($request->input('amount_cents') ?? $booking->amount_cents ?? 0),
            'expires_at'        => $expiresAt,
            'created_at'        => now(),
            'updated_at'        => now(),
        ]);

        return response()->json([
            'data' => [
                'id'           => (string) $id,
                'invite_token' => $token,
                'invite_url'   => "gymies://buddy/join?token={$token}",
                'expires_at'   => $expiresAt->toIso8601String(),
                'status'       => 'pending',
            ],
        ]);
    }

    /**
     * GET buddy/invite/{token} — Karim bekijkt de invite details.
     * Publiek endpoint (ook voor niet-ingelogde gebruikers).
     */
    public function getInvite(Request $request, string $token): JsonResponse
    {
        $invite = DB::table('gymies_buddy_bookings')
            ->where('invite_token', trim($token))
            ->first();

        if (!$invite) {
            return response()->json(['message' => 'Uitnodiging niet gevonden.'], 404);
        }

        // Check of verlopen
        if ($invite->status === 'pending' && now()->isAfter($invite->expires_at)) {
            DB::table('gymies_buddy_bookings')
                ->where('id', $invite->id)
                ->update(['status' => 'expired', 'updated_at' => now()]);
            return response()->json(['message' => 'Deze uitnodiging is verlopen.'], 410);
        }

        if ($invite->status !== 'pending') {
            return response()->json([
                'message' => $invite->status === 'accepted'
                    ? 'Deze uitnodiging is al geaccepteerd.'
                    : 'Deze uitnodiging is niet meer geldig.',
                'status' => $invite->status,
            ], 410);
        }

        // Haal initiator en trainer info op
        $initiator = DB::table('gymies_users')
            ->where('id', $invite->initiator_user_id)
            ->first(['id', 'display_name', 'email', 'gender']);

        $trainer = DB::table('gymies_users')
            ->where('id', $invite->trainer_user_id)
            ->first(['id', 'display_name', 'email']);

        // Duo-korting ophalen
        $duoDiscountPercent = 0;
        if (Schema::hasTable('gymies_trainer_profiles') && Schema::hasColumn('gymies_trainer_profiles', 'duo_discount_percent')) {
            $duoDiscountPercent = (int) (DB::table('gymies_trainer_profiles')
                ->where('user_id', $invite->trainer_user_id)
                ->value('duo_discount_percent') ?? 0);
        }

        $originalCents = (int) $invite->amount_cents;
        $discountedCents = $duoDiscountPercent > 0
            ? (int) round($originalCents * (1 - $duoDiscountPercent / 100))
            : $originalCents;

        return response()->json([
            'data' => [
                'id'                   => (string) $invite->id,
                'status'               => $invite->status,
                'gender_preference'    => $invite->gender_preference,
                'scheduled_at'         => $invite->scheduled_at,
                'expires_at'           => $invite->expires_at,
                'amount_cents'         => $originalCents,
                'duo_amount_cents'     => $discountedCents,
                'duo_discount_percent' => $duoDiscountPercent,
                'initiator' => [
                    'user_id'      => (string) ($initiator->id ?? ''),
                    'display_name' => (string) ($initiator->display_name ?? 'Iemand'),
                    'gender'       => (string) ($initiator->gender ?? ''),
                ],
                'trainer' => [
                    'user_id'      => (string) ($trainer->id ?? ''),
                    'display_name' => (string) ($trainer->display_name ?? 'Trainer'),
                ],
            ],
        ]);
    }

    /**
     * POST buddy/accept — Karim accepteert de invite.
     */
    public function accept(Request $request): JsonResponse
    {
        $user = $this->authUser($request);
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $request->validate([
            'invite_token'   => 'required|string',
            'payment_method' => 'nullable|in:mollie,cash,online',
        ]);

        $token = trim((string) $request->input('invite_token'));

        $invite = DB::table('gymies_buddy_bookings')
            ->where('invite_token', $token)
            ->first();

        if (!$invite) {
            return response()->json(['message' => 'Uitnodiging niet gevonden.'], 404);
        }

        if ($invite->status !== 'pending') {
            return response()->json(['message' => 'Deze uitnodiging is niet meer geldig.', 'status' => $invite->status], 410);
        }

        if (now()->isAfter($invite->expires_at)) {
            DB::table('gymies_buddy_bookings')
                ->where('id', $invite->id)
                ->update(['status' => 'expired', 'updated_at' => now()]);
            return response()->json(['message' => 'Deze uitnodiging is verlopen.'], 410);
        }

        // Kan niet je eigen invite accepteren
        if ((int) $invite->initiator_user_id === (int) $user->id) {
            return response()->json(['message' => 'Je kunt je eigen uitnodiging niet accepteren.'], 422);
        }

        // Gender preference check
        if ($invite->gender_preference !== null) {
            $buddyGender = $user->gender ?? null;
            if ($buddyGender !== null && $buddyGender !== $invite->gender_preference) {
                $label = $invite->gender_preference === 'female' ? 'dames' : 'heren';
                return response()->json([
                    'message' => "Deze uitnodiging is alleen voor {$label}.",
                    'gender_mismatch' => true,
                ], 403);
            }
        }

        // Duo-korting berekenen
        $duoDiscountPercent = 0;
        if (Schema::hasTable('gymies_trainer_profiles') && Schema::hasColumn('gymies_trainer_profiles', 'duo_discount_percent')) {
            $duoDiscountPercent = (int) (DB::table('gymies_trainer_profiles')
                ->where('user_id', $invite->trainer_user_id)
                ->value('duo_discount_percent') ?? 0);
        }

        $originalCents = (int) $invite->amount_cents;
        $buddyAmountCents = $duoDiscountPercent > 0
            ? (int) round($originalCents * (1 - $duoDiscountPercent / 100))
            : $originalCents;

        $paymentMethod = trim((string) ($request->input('payment_method') ?? 'online'));
        if ($paymentMethod === 'online') $paymentMethod = 'mollie_connect';

        // Maak buddy booking aan
        $buddyBookingData = [
            'client_user_id'   => (int) $user->id,
            'trainer_user_id'  => (int) $invite->trainer_user_id,
            'scheduled_at'     => $invite->scheduled_at,
            'duration_minutes' => 60,
            'amount_cents'     => $buddyAmountCents,
            'status'           => $paymentMethod === 'cash' ? 'reserved' : 'reserved',
            'created_at'       => now(),
            'updated_at'       => now(),
        ];

        if (Schema::hasColumn('gymies_bookings', 'payment_method')) {
            $buddyBookingData['payment_method'] = $paymentMethod === 'cash' ? 'cash' : 'mollie_connect';
        }
        if (Schema::hasColumn('gymies_bookings', 'booking_type')) {
            $buddyBookingData['booking_type'] = 'duo';
        }

        $buddyBookingId = DB::table('gymies_bookings')->insertGetId($buddyBookingData);

        // Update de invite
        DB::table('gymies_buddy_bookings')
            ->where('id', $invite->id)
            ->update([
                'buddy_booking_id' => $buddyBookingId,
                'buddy_user_id'    => (int) $user->id,
                'status'           => 'accepted',
                'accepted_at'      => now(),
                'updated_at'       => now(),
            ]);

        // Update initiator's booking type als kolom bestaat
        if (Schema::hasColumn('gymies_bookings', 'booking_type')) {
            DB::table('gymies_bookings')
                ->where('id', $invite->booking_id)
                ->update(['booking_type' => 'duo', 'updated_at' => now()]);
        }

        // Pas duo-korting ook toe op de initiator als die er nog niet op zit
        if ($duoDiscountPercent > 0) {
            DB::table('gymies_bookings')
                ->where('id', $invite->booking_id)
                ->update([
                    'amount_cents' => $buddyAmountCents,
                    'updated_at'   => now(),
                ]);
        }

        return response()->json([
            'data' => [
                'buddy_booking_id' => (string) $buddyBookingId,
                'amount_cents'     => $buddyAmountCents,
                'payment_method'   => $paymentMethod === 'cash' ? 'cash' : 'online',
                'status'           => 'accepted',
            ],
            'message' => 'Duo-sessie bevestigd! Je traint samen.',
        ]);
    }

    /**
     * POST buddy/decline — Karim weigert de invite.
     */
    public function decline(Request $request): JsonResponse
    {
        $user = $this->authUser($request);
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $request->validate(['invite_token' => 'required|string']);
        $token = trim((string) $request->input('invite_token'));

        $invite = DB::table('gymies_buddy_bookings')
            ->where('invite_token', $token)
            ->where('status', 'pending')
            ->first();

        if (!$invite) {
            return response()->json(['message' => 'Uitnodiging niet gevonden of niet meer geldig.'], 404);
        }

        DB::table('gymies_buddy_bookings')
            ->where('id', $invite->id)
            ->update(['status' => 'declined', 'updated_at' => now()]);

        return response()->json(['message' => 'Uitnodiging afgewezen.']);
    }

    // ═══════════════════════════════════════════════════════════════
    // MATCHMAKING FLOW
    // ═══════════════════════════════════════════════════════════════

    /**
     * POST buddy/pool/join — Schrijf jezelf in op de matchmaking pool.
     */
    public function joinPool(Request $request): JsonResponse
    {
        $user = $this->authUser($request);
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $request->validate([
            'gender_preference' => 'nullable|in:female,male',
            'fitness_level'     => 'nullable|in:beginner,intermediate,advanced',
            'fitness_goal'      => 'nullable|in:weight_loss,muscle,cardio',
            'time_preference'   => 'nullable|in:morning,afternoon,evening',
            'city'              => 'nullable|string|max:100',
        ]);

        // Stad uit profiel als niet meegegeven
        $city = $request->input('city') ?? $user->city ?? null;
        if ($city) $city = trim((string) $city);

        // Verwijder eerdere actieve pool entry
        DB::table('gymies_buddy_pool')
            ->where('user_id', $user->id)
            ->whereIn('status', ['searching', 'matched'])
            ->update(['status' => 'inactive', 'updated_at' => now()]);

        $id = DB::table('gymies_buddy_pool')->insertGetId([
            'user_id'           => (int) $user->id,
            'gender_preference' => $request->input('gender_preference'),
            'fitness_level'     => $request->input('fitness_level'),
            'fitness_goal'      => $request->input('fitness_goal'),
            'time_preference'   => $request->input('time_preference'),
            'city'              => $city,
            'status'            => 'searching',
            'created_at'        => now(),
            'updated_at'        => now(),
        ]);

        // Direct matchen proberen
        $match = $this->tryMatch($user, $id);

        if ($match) {
            return response()->json([
                'data' => [
                    'pool_id' => (string) $id,
                    'status'  => 'matched',
                    'match'   => $match,
                ],
                'message' => 'Direct een match gevonden!',
            ]);
        }

        return response()->json([
            'data' => [
                'pool_id' => (string) $id,
                'status'  => 'searching',
            ],
            'message' => 'Je staat op de matchlijst. We laten je weten zodra er een match is.',
        ]);
    }

    /**
     * POST buddy/pool/leave — Schrijf jezelf uit.
     */
    public function leavePool(Request $request): JsonResponse
    {
        $user = $this->authUser($request);
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        DB::table('gymies_buddy_pool')
            ->where('user_id', $user->id)
            ->where('status', 'searching')
            ->update(['status' => 'inactive', 'updated_at' => now()]);

        return response()->json(['message' => 'Uitgeschreven van de matchlijst.']);
    }

    /**
     * GET buddy/my-matches — Haal je matches op.
     */
    public function myMatches(Request $request): JsonResponse
    {
        $user = $this->authUser($request);
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $entries = DB::table('gymies_buddy_pool as p')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'p.matched_user_id')
            ->where('p.user_id', $user->id)
            ->where('p.status', 'matched')
            ->orderByDesc('p.matched_at')
            ->get([
                'p.id as pool_id',
                'p.matched_user_id',
                'p.matched_at',
                'p.fitness_level',
                'p.fitness_goal',
                'p.time_preference',
                'p.city',
                DB::raw('COALESCE(u.display_name, u.email) as match_name'),
                'u.gender as match_gender',
            ]);

        $data = $entries->map(function ($e) {
            return [
                'pool_id'         => (string) $e->pool_id,
                'matched_user_id' => (string) ($e->matched_user_id ?? ''),
                'match_name'      => (string) ($e->match_name ?? ''),
                'match_gender'    => (string) ($e->match_gender ?? ''),
                'matched_at'      => $e->matched_at,
                'fitness_level'   => $e->fitness_level,
                'fitness_goal'    => $e->fitness_goal,
                'time_preference' => $e->time_preference,
                'city'            => $e->city,
            ];
        })->values()->all();

        return response()->json(['data' => $data]);
    }

    /**
     * POST buddy/pool/dismiss — "Niet mijn match" → blokkeer persoon.
     */
    public function dismiss(Request $request): JsonResponse
    {
        $user = $this->authUser($request);
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $request->validate(['matched_user_id' => 'required|integer|min:1']);
        $dismissedId = (int) $request->input('matched_user_id');

        // Haal huidige pool entry op
        $entry = DB::table('gymies_buddy_pool')
            ->where('user_id', $user->id)
            ->where('status', 'matched')
            ->where('matched_user_id', $dismissedId)
            ->first();

        if (!$entry) {
            return response()->json(['message' => 'Match niet gevonden.'], 404);
        }

        // Voeg toe aan dismissed lijst
        $dismissed = json_decode($entry->dismissed_user_ids ?? '[]', true) ?: [];
        if (!in_array($dismissedId, $dismissed)) {
            $dismissed[] = $dismissedId;
        }

        // Reset deze entry naar searching
        DB::table('gymies_buddy_pool')
            ->where('id', $entry->id)
            ->update([
                'status'             => 'searching',
                'matched_user_id'    => null,
                'matched_at'         => null,
                'dismissed_user_ids' => json_encode($dismissed),
                'updated_at'         => now(),
            ]);

        // Reset ook de andere kant naar searching
        DB::table('gymies_buddy_pool')
            ->where('user_id', $dismissedId)
            ->where('matched_user_id', $user->id)
            ->where('status', 'matched')
            ->update([
                'status'          => 'searching',
                'matched_user_id' => null,
                'matched_at'      => null,
                'updated_at'      => now(),
            ]);

        // Probeer direct een nieuwe match
        $newMatch = $this->tryMatch($user, $entry->id);

        return response()->json([
            'message'   => 'Match afgewezen. We zoeken verder.',
            'new_match' => $newMatch,
        ]);
    }

    // ═══════════════════════════════════════════════════════════════
    // MATCHMAKING LOGICA
    // ═══════════════════════════════════════════════════════════════

    /**
     * Probeer een match te vinden voor de gegeven user.
     */
    private function tryMatch(object $user, int $poolEntryId): ?array
    {
        $entry = DB::table('gymies_buddy_pool')->where('id', $poolEntryId)->first();
        if (!$entry || $entry->status !== 'searching') return null;

        $dismissed = json_decode($entry->dismissed_user_ids ?? '[]', true) ?: [];
        $dismissed[] = (int) $user->id; // Sluit jezelf uit

        $query = DB::table('gymies_buddy_pool as p')
            ->join('gymies_users as u', 'u.id', '=', 'p.user_id')
            ->where('p.status', 'searching')
            ->where('p.user_id', '!=', $user->id)
            ->whereNotIn('p.user_id', $dismissed);

        // Zelfde stad
        if ($entry->city) {
            $query->where(function ($q) use ($entry) {
                $q->whereRaw('LOWER(p.city) = ?', [mb_strtolower($entry->city)])
                  ->orWhereNull('p.city');
            });
        }

        // Gender preference check (bidirectioneel):
        // A wil dames → B moet vrouw zijn
        // B wil heren → A moet man zijn
        $myGender = $user->gender ?? null;

        if ($entry->gender_preference !== null) {
            $query->where('u.gender', $entry->gender_preference);
        }
        if ($myGender !== null) {
            $query->where(function ($q) use ($myGender) {
                $q->whereNull('p.gender_preference')
                  ->orWhere('p.gender_preference', $myGender);
            });
        }

        // Score-based matching: hoe meer overlap, hoe beter
        $candidate = $query
            ->orderByRaw("
                (CASE WHEN p.fitness_goal = ? THEN 2 ELSE 0 END) +
                (CASE WHEN p.fitness_level = ? THEN 2 ELSE 0 END) +
                (CASE WHEN p.time_preference = ? THEN 1 ELSE 0 END)
                DESC
            ", [$entry->fitness_goal, $entry->fitness_level, $entry->time_preference])
            ->first([
                'p.id as pool_id',
                'p.user_id',
                'u.display_name',
                'u.gender',
                'p.fitness_level',
                'p.fitness_goal',
                'p.time_preference',
                'p.city',
            ]);

        if (!$candidate) return null;

        $now = now();

        // Update beide kanten
        DB::table('gymies_buddy_pool')
            ->where('id', $poolEntryId)
            ->update([
                'status'          => 'matched',
                'matched_user_id' => $candidate->user_id,
                'matched_at'      => $now,
                'updated_at'      => $now,
            ]);

        DB::table('gymies_buddy_pool')
            ->where('id', $candidate->pool_id)
            ->update([
                'status'          => 'matched',
                'matched_user_id' => $user->id,
                'matched_at'      => $now,
                'updated_at'      => $now,
            ]);

        return [
            'matched_user_id' => (string) $candidate->user_id,
            'match_name'      => (string) ($candidate->display_name ?? ''),
            'match_gender'    => (string) ($candidate->gender ?? ''),
            'fitness_level'   => $candidate->fitness_level,
            'fitness_goal'    => $candidate->fitness_goal,
            'time_preference' => $candidate->time_preference,
            'city'            => $candidate->city,
            'matched_at'      => $now->toIso8601String(),
        ];
    }

    // ═══════════════════════════════════════════════════════════════
    // CRON: Verlopen invites
    // ═══════════════════════════════════════════════════════════════

    /**
     * POST buddy/cron/expire-invites
     * Markeert alle verlopen buddy invites als 'expired'.
     * Bedoeld om periodiek aangeroepen te worden (bijv. elk uur).
     */
    public function expireInvites(Request $request): JsonResponse
    {
        if (!Schema::hasTable('gymies_buddy_bookings')) {
            return response()->json(['message' => 'Table not found.'], 404);
        }

        $expired = DB::table('gymies_buddy_bookings')
            ->where('status', 'pending')
            ->where('expires_at', '<', now())
            ->update([
                'status'     => 'expired',
                'updated_at' => now(),
            ]);

        return response()->json([
            'message' => "Expired {$expired} buddy invites.",
            'count'   => $expired,
        ]);
    }

    // ═══════════════════════════════════════════════════════════════
    // DUO SETTINGS (trainer)
    // ═══════════════════════════════════════════════════════════════

    /**
     * GET trainer/duo-settings
     * Haal de duo training instellingen op voor de ingelogde trainer.
     */
    public function getDuoSettings(Request $request): JsonResponse
    {
        $user = $this->authUser($request);
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        // Probeer uit users tabel (of trainers tabel)
        $fields = ['offers_duo_training', 'duo_discount_percent', 'duo_price_cents'];
        $data = [];
        foreach ($fields as $field) {
            try {
                $val = DB::table('users')->where('id', $user->id)->value($field);
                $data[$field] = $val;
            } catch (\Throwable $e) {
                $data[$field] = null;
            }
        }

        return response()->json([
            'data' => [
                'offers_duo_training'  => (bool) ($data['offers_duo_training'] ?? false),
                'duo_discount_percent' => $data['duo_discount_percent'] ?? 25,
                'duo_price_cents'      => $data['duo_price_cents'],
            ],
        ]);
    }

    /**
     * PUT trainer/duo-settings
     * Update de duo training instellingen voor de ingelogde trainer.
     */
    public function updateDuoSettings(Request $request): JsonResponse
    {
        $user = $this->authUser($request);
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $validated = $request->validate([
            'offers_duo_training'  => 'required|boolean',
            'duo_discount_percent' => 'nullable|integer|min:0|max:50',
            'duo_price_cents'      => 'nullable|integer|min:0',
        ]);

        $update = ['offers_duo_training' => $validated['offers_duo_training']];
        if (isset($validated['duo_discount_percent'])) {
            $update['duo_discount_percent'] = $validated['duo_discount_percent'];
        }
        if (array_key_exists('duo_price_cents', $validated)) {
            $update['duo_price_cents'] = $validated['duo_price_cents'];
        }
        $update['updated_at'] = now();

        try {
            DB::table('users')->where('id', $user->id)->update($update);
        } catch (\Throwable $e) {
            // Kolommen bestaan mogelijk nog niet — probeer via alter of negeer
            return response()->json([
                'message' => 'Instellingen konden niet worden opgeslagen: ' . $e->getMessage(),
            ], 500);
        }

        return response()->json([
            'data' => array_merge($update, ['offers_duo_training' => (bool) $update['offers_duo_training']]),
            'message' => 'Duo instellingen opgeslagen.',
        ]);
    }

    // ═══════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════

    private function authUser(Request $request): ?object
    {
        $user = $request->user();
        if ($user && $user->id) return $user;
        return null;
    }
}
