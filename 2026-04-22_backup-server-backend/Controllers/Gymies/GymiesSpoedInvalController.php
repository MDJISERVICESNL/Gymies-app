<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Traits\GymiesRequireTrainerTrait;
use App\Helpers\GymiesSupportSync;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Spoed Inval: trainer vraagt invaller voor sessie(s) bij overmacht.
 * Flow: trainer kiest sessies → systeem zoekt beschikbare trainers → invaller krijgt melding → accepteert/weigert → betaling naar invaller.
 */
final class GymiesSpoedInvalController extends Controller
{
    use GymiesRequireTrainerTrait;

    private const OFFER_EXPIRY_HOURS = 24;
    private const MAX_CANDIDATES = 10;
    private const MAX_FAVORITES_BATCH0 = 3;
    private const BATCH1_DELAY_MINUTES = 5;

    /**
     * POST /trainer/spoed-inval/request
     * Trainer start spoed inval: kiest boekingen, systeem zoekt kandidaten en stuurt meldingen.
     */
    public function createRequest(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $request->validate([
            'booking_ids' => 'required|array',
            'booking_ids.*' => 'required|integer|exists:gymies_bookings,id',
            'share_lesson_plan' => 'sometimes|boolean',
        ]);

        $bookingIds = array_unique(array_map('intval', $request->input('booking_ids')));
        if (empty($bookingIds)) {
            return response()->json(['message' => 'Selecteer minimaal één sessie.'], 422);
        }

        if (!$this->ensureSpoedInvalTables()) {
            return response()->json(['message' => 'Spoed inval is nog niet beschikbaar.'], 503);
        }

        // N-015 FIXED: IDOR voorkomen — trainer kan alleen eigen gym shifts zien
        $trainerGymId = DB::table('gymies_gym_trainers')
            ->where('user_id', (int) $user->id)
            ->where('is_active', 1)
            ->value('gym_id');

        // Valideer: alle boekingen zijn van deze trainer, status confirmed of pending
        $bookings = DB::table('gymies_bookings')
            ->whereIn('id', $bookingIds)
            ->where('trainer_user_id', (int) $user->id)
            ->whereIn('status', ['pending', 'confirmed'])
            ->where('scheduled_at', '>', now());

        // Als trainer aan gym gekoppeld: voeg gym_id check toe
        if ($trainerGymId !== null) {
            $bookings->where('gym_id', $trainerGymId);
        }

        $bookings = $bookings->get();

        if ($bookings->count() !== count($bookingIds)) {
            return response()->json([
                'message' => 'Niet alle geselecteerde sessies zijn geldig of van jou. Alleen toekomstige pending/confirmed sessies.',
            ], 422);
        }

        // Check of er al een open spoed inval voor een van deze boekingen is
        $existing = DB::table('gymies_spoed_inval_booking_links as l')
            ->join('gymies_spoed_inval_requests as r', 'r.id', '=', 'l.spoed_inval_request_id')
            ->whereIn('l.booking_id', $bookingIds)
            ->whereIn('r.status', ['pending'])
            ->exists();
        if ($existing) {
            return response()->json(['message' => 'Een van deze sessies heeft al een open spoed-invalverzoek.'], 409);
        }

        $originalProfile = $this->getTrainerProfile((int) $user->id);
        $originalRegion = $originalProfile['region'] ?? '';
        $originalSpecialty = $originalProfile['specialty'] ?? '';
        $shareLessonPlan = (bool) $request->boolean('share_lesson_plan');

        // Zoek kandidaten: favorieten eerst (batch 0), dan rest (batch 1 via cron)
        $candidatesWithBatch = $this->findAvailableCandidatesWithBatch(
            (int) $user->id,
            $bookings,
            $originalRegion,
            $originalSpecialty
        );

        if (empty($candidatesWithBatch)) {
            return response()->json([
                'message' => 'Geen andere trainers gevonden die beschikbaar zijn op deze momenten. Probeer het later opnieuw of neem contact op met support.',
            ], 404);
        }

        $expiresAt = now()->addHours(self::OFFER_EXPIRY_HOURS);

        $requestId = DB::table('gymies_spoed_inval_requests')->insertGetId([
            'original_trainer_user_id' => (int) $user->id,
            'status' => 'pending',
            'expires_at' => $expiresAt,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        foreach ($bookingIds as $bid) {
            DB::table('gymies_spoed_inval_booking_links')->insert([
                'spoed_inval_request_id' => $requestId,
                'booking_id' => $bid,
            ]);
        }

        // Batch 0: alleen favorieten (max 3), direct versturen
        $batch0 = array_filter($candidatesWithBatch, fn ($c) => ($c['batch'] ?? 0) === 0);
        $batch1 = array_filter($candidatesWithBatch, fn ($c) => ($c['batch'] ?? 1) === 1);
        $offersCreated = 0;

        $hasOfferBatch = Schema::hasColumn('gymies_spoed_inval_offers', 'offer_batch');

        foreach (array_slice($batch0, 0, self::MAX_FAVORITES_BATCH0) as $c) {
            $insert = [
                'spoed_inval_request_id' => $requestId,
                'substitute_trainer_user_id' => $c['id'],
                'status' => 'pending',
                'created_at' => now(),
            ];
            if ($hasOfferBatch) {
                $insert['offer_batch'] = 0;
            }
            $offerId = DB::table('gymies_spoed_inval_offers')->insertGetId($insert);
            $this->sendSpoedInvalNotification($requestId, (int) $offerId, $c['id'], $bookings, $shareLessonPlan);
            $offersCreated++;
        }

        // Als geen favorieten of < 3: vul aan met batch 1 tot max
        $remaining = self::MAX_CANDIDATES - $offersCreated;
        if ($remaining > 0) {
            foreach (array_slice($batch1, 0, $remaining) as $c) {
                $insert = [
                    'spoed_inval_request_id' => $requestId,
                    'substitute_trainer_user_id' => $c['id'],
                    'status' => 'pending',
                    'created_at' => now(),
                ];
                if ($hasOfferBatch) {
                    $insert['offer_batch'] = 1;
                }
                $offerId = DB::table('gymies_spoed_inval_offers')->insertGetId($insert);
                $this->sendSpoedInvalNotification($requestId, (int) $offerId, $c['id'], $bookings, $shareLessonPlan);
                $offersCreated++;
            }
        }

        $this->audit($requestId, 'request_created', (int) $user->id, [
            'booking_ids' => $bookingIds,
            'candidates_count' => $offersCreated,
        ]);

        return response()->json([
            'data' => [
                'id' => (string) $requestId,
                'status' => 'pending',
                'booking_ids' => $bookingIds,
                'offers_sent' => $offersCreated,
                'expires_at' => $expiresAt->toIso8601String(),
            ],
        ], 201);
    }

    /**
     * GET /trainer/spoed-inval/requests
     * Lijst eigen spoed-invalverzoeken (als aanvrager) en aanbiedingen (als invaller).
     */
    public function index(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        if (!$this->ensureSpoedInvalTables()) {
            return response()->json(['data' => ['as_requester' => [], 'as_substitute' => []]]);
        }

        $asRequester = DB::table('gymies_spoed_inval_requests as r')
            ->leftJoin('gymies_spoed_inval_booking_links as l', 'l.spoed_inval_request_id', '=', 'r.id')
            ->where('r.original_trainer_user_id', (int) $user->id)
            ->selectRaw('r.id, r.status, r.substitute_trainer_user_id, r.expires_at, r.created_at, GROUP_CONCAT(l.booking_id) as booking_ids')
            ->groupBy('r.id', 'r.status', 'r.substitute_trainer_user_id', 'r.expires_at', 'r.created_at')
            ->orderByDesc('r.created_at')
            ->limit(20)
            ->get()
            ->map(fn ($r) => $this->formatRequestRow($r, true))
            ->all();

        $asSubstitute = DB::table('gymies_spoed_inval_offers as o')
            ->join('gymies_spoed_inval_requests as r', 'r.id', '=', 'o.spoed_inval_request_id')
            ->leftJoin('gymies_spoed_inval_booking_links as l', 'l.spoed_inval_request_id', '=', 'r.id')
            ->where('o.substitute_trainer_user_id', (int) $user->id)
            ->where('o.status', 'pending')
            ->whereIn('r.status', ['pending'])
            ->where(function ($q) {
                $q->whereNull('r.expires_at')->orWhere('r.expires_at', '>', now());
            })
            ->selectRaw('r.id, r.status, r.original_trainer_user_id, r.expires_at, r.created_at, o.id as offer_id, o.status as offer_status, GROUP_CONCAT(l.booking_id) as booking_ids')
            ->groupBy('r.id', 'r.status', 'r.original_trainer_user_id', 'r.expires_at', 'r.created_at', 'o.id', 'o.status')
            ->orderByDesc('r.created_at')
            ->limit(20)
            ->get()
            ->map(fn ($r) => $this->formatOfferRow($r))
            ->all();

        return response()->json([
            'data' => [
                'as_requester' => $asRequester,
                'as_substitute' => $asSubstitute,
            ],
        ]);
    }

    /**
     * POST /trainer/spoed-inval/offers/{offerId}/respond
     * Invaller accepteert of weigert het aanbod.
     * N-004 FIXED: TOCTOU race condition opgelost met DB::transaction + lockForUpdate
     */
    public function respondToOffer(Request $request, string $offerId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $request->validate([
            'accept' => 'required|boolean',
            'lat' => 'sometimes|numeric',
            'lng' => 'sometimes|numeric',
            'force_late_accept' => 'sometimes|boolean',
        ]);

        if (!$this->ensureSpoedInvalTables()) {
            return response()->json(['message' => 'Spoed inval is nog niet beschikbaar.'], 503);
        }

        // N-004 FIXED: Laad de offer BUITEN de transaction, maar controleer status erna
        $offer = DB::table('gymies_spoed_inval_offers as o')
            ->join('gymies_spoed_inval_requests as r', 'r.id', '=', 'o.spoed_inval_request_id')
            ->where('o.id', (int) $offerId)
            ->where('o.substitute_trainer_user_id', (int) $user->id)
            ->where('o.status', 'pending')
            ->whereIn('r.status', ['pending'])
            ->where(function ($q) {
                $q->whereNull('r.expires_at')->orWhere('r.expires_at', '>', now());
            })
            ->select('o.*', 'r.original_trainer_user_id', 'r.id as request_id')
            ->first();

        if (!$offer) {
            return response()->json(['message' => 'Aanbod niet gevonden of verlopen.'], 404);
        }

        $accept = (bool) $request->boolean('accept');
        $lat = $request->has('lat') ? (float) $request->input('lat') : null;
        $lng = $request->has('lng') ? (float) $request->input('lng') : null;
        $forceLateAccept = (bool) $request->boolean('force_late_accept');

        if ($accept) {
            $bookings = DB::table('gymies_bookings as b')
                ->join('gymies_spoed_inval_booking_links as l', 'l.booking_id', '=', 'b.id')
                ->where('l.spoed_inval_request_id', (int) $offer->spoed_inval_request_id)
                ->select('b.*')
                ->get();

            if (!$this->isTrainerAvailableForBookings((int) $user->id, $bookings)) {
                return response()->json([
                    'message' => 'Je bent niet meer beschikbaar op deze momenten. Je beschikbaarheid is mogelijk gewijzigd.',
                ], 409);
            }

            // Live Locatie Check: als lat/lng gegeven en reistijd > tijd tot aanvang → waarschuwing
            if ($lat !== null && $lng !== null && !$forceLateAccept) {
                $travelCheck = $this->checkTravelTime($lat, $lng, $bookings);
                if ($travelCheck !== null && $travelCheck['late']) {
                    return response()->json([
                        'data' => [
                            'travel_warning' => true,
                            'requires_confirmation' => true,
                            'travel_time_minutes' => $travelCheck['travel_time_minutes'],
                            'minutes_until_start' => $travelCheck['minutes_until_start'],
                            'message' => sprintf(
                                'Let op: Je komt volgens de berekening %d minuten te laat (sessie start over %d min). Wil je alsnog doorgaan?',
                                $travelCheck['travel_time_minutes'],
                                $travelCheck['minutes_until_start']
                            ),
                        ],
                    ]);
                }
            }

            // N-004 FIXED: Atomaire transactie met lockForUpdate op shift-request
            return DB::transaction(function () use ($offer, $user, $offerId, $bookings) {
                // Lock de request-rij zodat geen andere trainer tegelijk kan accepteren
                $shiftRequest = DB::table('gymies_spoed_inval_requests')
                    ->where('id', (int) $offer->spoed_inval_request_id)
                    ->lockForUpdate()
                    ->first();

                if (!$shiftRequest || $shiftRequest->status !== 'pending') {
                    // Rollen terug en fout teruggeven
                    return response()->json([
                        'message' => 'Helaas, een andere trainer was je net voor of de shift is niet meer beschikbaar.',
                    ], 409);
                }

                // Nu veilig bijwerken met lock actief
                DB::table('gymies_spoed_inval_requests')
                    ->where('id', (int) $offer->spoed_inval_request_id)
                    ->update([
                        'status' => 'accepted',
                        'substitute_trainer_user_id' => (int) $user->id,
                        'updated_at' => now(),
                    ]);
                // Andere aanbiedingen afwijzen
                DB::table('gymies_spoed_inval_offers')
                    ->where('spoed_inval_request_id', (int) $offer->spoed_inval_request_id)
                    ->where('id', '!=', (int) $offerId)
                    ->update(['status' => 'declined', 'responded_at' => now()]);

                DB::table('gymies_spoed_inval_offers')
                    ->where('id', (int) $offerId)
                    ->update(['status' => 'accepted', 'responded_at' => now()]);

                // Boekingen overdragen naar invaller + badge "Inval-docent"
                $originalTrainerId = (int) $offer->original_trainer_user_id;
                foreach ($bookings as $b) {
                    $updatePayload = [
                        'trainer_user_id' => (int) $user->id,
                        'updated_at' => now(),
                    ];
                    if (Schema::hasColumn('gymies_bookings', 'trainer_notes')) {
                        $origNote = $b->trainer_notes ?? '';
                        $updatePayload['trainer_notes'] = trim(
                            "[Spoed inval overgenomen van trainer #{$originalTrainerId}] " . $origNote
                        );
                    }
                    if (Schema::hasColumn('gymies_bookings', 'spoed_inval_original_trainer_id')) {
                        $updatePayload['spoed_inval_original_trainer_id'] = $originalTrainerId;
                    }
                    DB::table('gymies_bookings')->where('id', (int) $b->id)->update($updatePayload);
                }

                // Automatische Klant-Update: notify alle deelnemers
                $this->notifyParticipantsOfSubstitute($originalTrainerId, (int) $user->id, $bookings);

                // Support ticket aanmaken voor betalingsafhandeling
                $ticketId = $this->createSpoedInvalSupportTicket(
                    (int) $offer->original_trainer_user_id,
                    (int) $user->id,
                    (int) $offer->spoed_inval_request_id,
                    $bookings
                );

                if ($ticketId !== null) {
                    DB::table('gymies_spoed_inval_requests')
                        ->where('id', (int) $offer->spoed_inval_request_id)
                        ->update(['support_ticket_id' => $ticketId]);
                }

                $this->audit((int) $offer->spoed_inval_request_id, 'offer_accepted', (int) $user->id, [
                    'booking_ids' => $bookings->pluck('id')->all(),
                    'support_ticket_id' => $ticketId,
                ]);

                // Notificatie naar originele trainer
                $this->notifyOriginalTrainerAccepted((int) $offer->original_trainer_user_id, (int) $user->id, $bookings);

                return response()->json([
                    'data' => [
                        'status' => 'accepted',
                        'message' => 'Je hebt de spoed inval geaccepteerd. De sessies staan nu in je agenda. Support regelt de betaling.',
                    ],
                ]);
            });
        }

        // Declined
        DB::table('gymies_spoed_inval_offers')
            ->where('id', (int) $offerId)
            ->update(['status' => 'declined', 'responded_at' => now()]);

        $this->audit((int) $offer->spoed_inval_request_id, 'offer_declined', (int) $user->id, []);

        // Als alle aanbiedingen geweigerd, zet request op failed (voor backoffice)
        if (Schema::hasColumn('gymies_spoed_inval_requests', 'status')) {
            $pendingCount = DB::table('gymies_spoed_inval_offers')
                ->where('spoed_inval_request_id', (int) $offer->spoed_inval_request_id)
                ->where('status', 'pending')
                ->count();
            if ($pendingCount === 0) {
                DB::table('gymies_spoed_inval_requests')
                    ->where('id', (int) $offer->spoed_inval_request_id)
                    ->update(['status' => 'failed', 'updated_at' => now()]);
            }
        }

        return response()->json([
            'data' => [
                'status' => 'declined',
                'message' => 'Je hebt het aanbod geweigerd.',
            ],
        ]);
    }

    /**
     * POST /trainer/spoed-inval/requests/{id}/cancel
     * Originele trainer annuleert het verzoek.
     */
    public function cancelRequest(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        if (!$this->ensureSpoedInvalTables()) {
            return response()->json(['message' => 'Spoed inval is nog niet beschikbaar.'], 503);
        }

        $req = DB::table('gymies_spoed_inval_requests')
            ->where('id', (int) $id)
            ->where('original_trainer_user_id', (int) $user->id)
            ->where('status', 'pending')
            ->first();

        if (!$req) {
            return response()->json(['message' => 'Verzoek niet gevonden of kan niet meer geannuleerd worden.'], 404);
        }

        DB::table('gymies_spoed_inval_requests')
            ->where('id', (int) $id)
            ->update(['status' => 'cancelled', 'updated_at' => now()]);

        $this->audit((int) $id, 'request_cancelled', (int) $user->id, []);

        return response()->json(['data' => ['status' => 'cancelled']]);
    }

    /**
     * GET /trainer/spoed-inval/requests/{id}/lesson-plan
     * Lesplan ophalen voor invaller (alleen als share_lesson_plan en user is substitute of heeft pending offer).
     */
    public function getLessonPlan(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        if (!$this->ensureSpoedInvalTables()) {
            return response()->json(['message' => 'Spoed inval is nog niet beschikbaar.'], 503);
        }

        $req = DB::table('gymies_spoed_inval_requests as r')
            ->leftJoin('gymies_spoed_inval_offers as o', function ($j) use ($user) {
                $j->on('o.spoed_inval_request_id', '=', 'r.id')
                    ->where('o.substitute_trainer_user_id', '=', (int) $user->id);
            })
            ->where('r.id', (int) $id)
            ->select('r.id', 'r.status', 'r.substitute_trainer_user_id', 'o.id as offer_id', 'o.status as offer_status')
            ->first();

        if (!$req) {
            return response()->json(['message' => 'Verzoek niet gevonden.'], 404);
        }

        $isSubstitute = (int) $req->substitute_trainer_user_id === (int) $user->id;
        $hasPendingOffer = $req->offer_id && $req->offer_status === 'pending';
        if (!$isSubstitute && !$hasPendingOffer) {
            return response()->json(['message' => 'Geen toegang tot dit lesplan.'], 403);
        }

        $bookings = DB::table('gymies_bookings as b')
            ->join('gymies_spoed_inval_booking_links as l', 'l.booking_id', '=', 'b.id')
            ->where('l.spoed_inval_request_id', (int) $id)
            ->select('b.id', 'b.scheduled_at', 'b.duration_minutes', 'b.location_notes', 'b.lesson_plan_json', 'b.share_lesson_plan_with_substitute')
            ->get();

        $plans = [];
        foreach ($bookings as $b) {
            $share = Schema::hasColumn('gymies_bookings', 'share_lesson_plan_with_substitute')
                ? (bool) ($b->share_lesson_plan_with_substitute ?? false)
                : false;
            $json = Schema::hasColumn('gymies_bookings', 'lesson_plan_json') ? ($b->lesson_plan_json ?? null) : null;
            $plans[] = [
                'booking_id' => (int) $b->id,
                'scheduled_at' => $b->scheduled_at,
                'duration_minutes' => (int) ($b->duration_minutes ?? 60),
                'location_notes' => $b->location_notes ?? null,
                'shared' => $share,
                'lesson_plan' => $share && $json ? json_decode($json, true) : null,
            ];
        }

        return response()->json(['data' => ['sessions' => $plans]]);
    }

    /**
     * GET /trainer/favorite-colleagues
     */
    public function getFavoriteColleagues(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        if (!Schema::hasTable('gymies_trainer_favorite_colleagues')) {
            return response()->json(['data' => []]);
        }

        $rows = DB::table('gymies_trainer_favorite_colleagues as f')
            ->join('gymies_users as u', 'u.id', '=', 'f.favorite_trainer_user_id')
            ->where('f.trainer_user_id', (int) $user->id)
            ->orderBy('f.sort_order')
            ->select('u.id', 'u.display_name', 'u.email', 'f.sort_order')
            ->get();

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'display_name' => $r->display_name ?? $r->email ?? '',
            'email' => $r->email ?? null,
            'sort_order' => (int) $r->sort_order,
        ])->all();

        return response()->json(['data' => $data]);
    }

    /**
     * PUT /trainer/favorite-colleagues
     * Body: { trainer_ids: [1, 2, 3] } (max 5)
     */
    public function updateFavoriteColleagues(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $request->validate([
            'trainer_ids' => 'required|array',
            'trainer_ids.*' => 'required|integer|exists:gymies_users,id',
        ]);

        $ids = array_unique(array_map('intval', $request->input('trainer_ids')));
        $ids = array_filter($ids, fn ($id) => $id !== (int) $user->id);
        $ids = array_slice($ids, 0, 5);

        if (!Schema::hasTable('gymies_trainer_favorite_colleagues')) {
            return response()->json(['data' => ['message' => 'Favorieten nog niet beschikbaar.']], 503);
        }

        DB::table('gymies_trainer_favorite_colleagues')
            ->where('trainer_user_id', (int) $user->id)
            ->delete();

        foreach ($ids as $i => $tid) {
            DB::table('gymies_trainer_favorite_colleagues')->insert([
                'trainer_user_id' => (int) $user->id,
                'favorite_trainer_user_id' => $tid,
                'sort_order' => $i,
                'created_at' => now(),
            ]);
        }

        return $this->getFavoriteColleagues($request);
    }

    /**
     * Cron: verstuur batch 1 (rest) na 5 min als favorieten niet reageren.
     * Aanroep: GET/POST /api/gymies/cron/spoed-inval-batch1?key=...
     */
    public static function processBatch1(): array
    {
        if (!Schema::hasTable('gymies_spoed_inval_requests') || !Schema::hasColumn('gymies_spoed_inval_requests', 'batch1_sent_at')) {
            return ['sent' => 0];
        }

        $cutoff = now()->subMinutes(5);
        $requests = DB::table('gymies_spoed_inval_requests')
            ->where('status', 'pending')
            ->whereNull('batch1_sent_at')
            ->where('created_at', '<=', $cutoff)
            ->get();

        $totalSent = 0;
        foreach ($requests as $req) {
            $bookings = DB::table('gymies_bookings as b')
                ->join('gymies_spoed_inval_booking_links as l', 'l.booking_id', '=', 'b.id')
                ->where('l.spoed_inval_request_id', $req->id)
                ->select('b.*')
                ->get();

            $existingOfferIds = DB::table('gymies_spoed_inval_offers')
                ->where('spoed_inval_request_id', $req->id)
                ->pluck('substitute_trainer_user_id')
                ->all();

            $controller = new self();
            $profile = $controller->getTrainerProfile((int) $req->original_trainer_user_id);
            $candidates = $controller->findAvailableCandidatesWithBatch(
                (int) $req->original_trainer_user_id,
                $bookings,
                $profile['region'] ?? '',
                $profile['specialty'] ?? ''
            );

            $batch1 = array_filter($candidates, fn ($c) => ($c['batch'] ?? 1) === 1);
            $toSend = array_filter($batch1, fn ($c) => !in_array($c['id'], $existingOfferIds, true));
            $toSend = array_slice($toSend, 0, self::MAX_CANDIDATES - count($existingOfferIds));

            $hasOfferBatch = Schema::hasColumn('gymies_spoed_inval_offers', 'offer_batch');
            $shareLessonPlan = false;
            $firstBooking = $bookings->first();
            if ($firstBooking && Schema::hasColumn('gymies_bookings', 'share_lesson_plan_with_substitute')) {
                $shareLessonPlan = (bool) ($firstBooking->share_lesson_plan_with_substitute ?? false);
            }

            foreach ($toSend as $c) {
                $insert = [
                    'spoed_inval_request_id' => $req->id,
                    'substitute_trainer_user_id' => $c['id'],
                    'status' => 'pending',
                    'created_at' => now(),
                ];
                if ($hasOfferBatch) {
                    $insert['offer_batch'] = 1;
                }
                $offerId = DB::table('gymies_spoed_inval_offers')->insertGetId($insert);
                $controller->sendSpoedInvalNotification((int) $req->id, (int) $offerId, $c['id'], $bookings, $shareLessonPlan);
                $totalSent++;
            }

            DB::table('gymies_spoed_inval_requests')
                ->where('id', $req->id)
                ->update(['batch1_sent_at' => now()]);
        }

        return ['sent' => $totalSent, 'requests_processed' => $requests->count()];
    }

    private function ensureSpoedInvalTables(): bool
    {
        return Schema::hasTable('gymies_spoed_inval_requests')
            && Schema::hasTable('gymies_spoed_inval_booking_links')
            && Schema::hasTable('gymies_spoed_inval_offers');
    }

    private function getTrainerProfile(int $userId): array
    {
        $p = DB::table('gymies_trainer_profiles')->where('user_id', $userId)->first();
        if (!$p) {
            return [];
        }
        return [
            'region' => $p->region ?? '',
            'specialty' => $p->specialty ?? '',
        ];
    }

    /**
     * Zoek trainers met Priority Pool: batch 0 = favorieten (max 3), batch 1 = rest.
     * Sorteer op standby, dan op batch.
     */
    private function findAvailableCandidatesWithBatch(int $excludeTrainerId, $bookings, string $region, string $specialty): array
    {
        $favoriteIds = [];
        if (Schema::hasTable('gymies_trainer_favorite_colleagues')) {
            $favoriteIds = DB::table('gymies_trainer_favorite_colleagues')
                ->where('trainer_user_id', $excludeTrainerId)
                ->orderBy('sort_order')
                ->pluck('favorite_trainer_user_id')
                ->map(fn ($id) => (int) $id)
                ->all();
        }

        $trainersQuery = DB::table('gymies_users as u')
            ->join('gymies_trainer_profiles as p', 'p.user_id', '=', 'u.id')
            ->where('u.role', 'trainer')
            ->where('u.id', '!=', $excludeTrainerId)
            ->where(function ($q) {
                $q->whereNull('p.is_available')->orWhere('p.is_available', 1);
            });

        // N-012 FIXED: LIKE wildcard injection voorkomen
        if ($region !== '') {
            $safeRegion = addcslashes($region, '%_\\');
            $trainersQuery->where(function ($q) use ($safeRegion) {
                $q->where('p.region', 'like', '%' . $safeRegion . '%')
                    ->orWhere('p.region', 'like', $safeRegion . '%');
            });
        }
        if ($specialty !== '') {
            $safeSpecialty = addcslashes($specialty, '%_\\');
            $trainersQuery->where(function ($q) use ($safeSpecialty) {
                $q->where('p.specialty', 'like', '%' . $safeSpecialty . '%')
                    ->orWhere('p.specialty', 'like', $safeSpecialty . '%');
            });
        }

        $selectCols = ['u.id'];
        if (Schema::hasColumn('gymies_trainer_profiles', 'spoed_inval_standby_date')) {
            $selectCols[] = 'p.spoed_inval_standby_date';
        }
        $trainersWithStandby = $trainersQuery->select($selectCols)->get();

        $candidates = [];
        $today = now()->format('Y-m-d');
        foreach ($trainersWithStandby as $row) {
            $tid = (int) $row->id;
            if ($this->isTrainerAvailableForBookings($tid, $bookings)) {
                $standbyDate = property_exists($row, 'spoed_inval_standby_date') ? $row->spoed_inval_standby_date : null;
                $isStandby = $standbyDate !== null && $standbyDate !== '' && (string) $standbyDate === $today;
                $batch = in_array($tid, $favoriteIds, true) ? 0 : 1;
                $candidates[] = ['id' => $tid, 'standby' => $isStandby, 'batch' => $batch];
            }
        }

        usort($candidates, function ($a, $b) {
            if ($a['batch'] !== $b['batch']) {
                return $a['batch'] <=> $b['batch'];
            }
            return ($b['standby'] ? 1 : 0) <=> ($a['standby'] ? 1 : 0);
        });

        return $candidates;
    }

    /**
     * Haversine-afstand + geschatte reistijd (30 km/u gemiddeld in stad).
     * Retourneert null als geen bestemming, anders ['travel_time_minutes', 'minutes_until_start', 'late'].
     */
    private function checkTravelTime(float $lat, float $lng, $bookings): ?array
    {
        $first = $bookings->first();
        if (!$first) {
            return null;
        }

        $destLat = null;
        $destLng = null;
        if ($first->trainer_location_id && Schema::hasTable('gymies_trainer_locations')) {
            $loc = DB::table('gymies_trainer_locations')->where('id', $first->trainer_location_id)->first(['latitude', 'longitude']);
            if ($loc && $loc->latitude !== null && $loc->longitude !== null) {
                $destLat = (float) $loc->latitude;
                $destLng = (float) $loc->longitude;
            }
        }
        if ($destLat === null || $destLng === null) {
            return null;
        }

        $km = $this->haversineDistanceKm($lat, $lng, $destLat, $destLng);
        $travelMinutes = (int) ceil(($km / 30.0) * 60);
        $startAt = \Carbon\Carbon::parse($first->scheduled_at);
        $minutesUntilStart = (int) max(0, now()->diffInMinutes($startAt, false));

        return [
            'travel_time_minutes' => $travelMinutes,
            'minutes_until_start' => $minutesUntilStart,
            'late' => $travelMinutes > $minutesUntilStart,
        ];
    }

    private function haversineDistanceKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $r = 6371;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;
        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));
        return $r * $c;
    }

    private function notifyParticipantsOfSubstitute(int $originalTrainerId, int $substituteId, $bookings): void
    {
        if (!Schema::hasTable('gymies_notification_queue')) {
            return;
        }

        $original = DB::table('gymies_users')->where('id', $originalTrainerId)->first(['display_name', 'email']);
        $substitute = DB::table('gymies_users')->where('id', $substituteId)->first(['display_name', 'email']);
        $originalName = $original->display_name ?? $original->email ?? 'Je trainer';
        $substituteName = $substitute->display_name ?? $substitute->email ?? 'een invaller';

        $participantIds = $bookings->pluck('client_user_id')->unique()->filter()->all();
        foreach ($participantIds as $clientId) {
            DB::table('gymies_notification_queue')->insert([
                'user_id' => $clientId,
                'channel' => 'in_app',
                'event_type' => 'spoed_inval_substitute_notify',
                'payload_json' => json_encode([
                    'original_trainer_user_id' => (string) $originalTrainerId,
                    'original_trainer_name' => $originalName,
                    'substitute_trainer_user_id' => (string) $substituteId,
                    'substitute_trainer_name' => $substituteName,
                    'message' => "Trainer {$originalName} is wegens omstandigheden verhinderd. {$substituteName} kijkt ernaar uit om de les over te nemen!",
                ]),
                'scheduled_for' => now(),
                'created_at' => now(),
            ]);
        }
    }

    private function isTrainerAvailableForBookings(int $trainerId, $bookings): bool
    {
        foreach ($bookings as $b) {
            $start = \Carbon\Carbon::parse($b->scheduled_at);
            $duration = (int) ($b->duration_minutes ?? 60);
            $end = $start->copy()->addMinutes($duration);

            $overlap = DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerId)
                ->whereIn('status', ['pending', 'confirmed', 'reserved'])
                ->where('id', '!=', (int) $b->id)
                ->where(function ($q) use ($start, $end) {
                    $q->whereBetween('scheduled_at', [$start->toDateTimeString(), $end->toDateTimeString()])
                        ->orWhereRaw(
                            'DATE_ADD(scheduled_at, INTERVAL COALESCE(duration_minutes, 60) MINUTE) > ? AND scheduled_at < ?',
                            [$start->toDateTimeString(), $end->toDateTimeString()]
                        );
                })
                ->exists();

            if ($overlap) {
                return false;
            }

            // Check beschikbaarheid (slots + exceptions)
            if (!$this->isSlotAvailableForTrainer($trainerId, $b->scheduled_at, $duration)) {
                return false;
            }
        }
        return true;
    }

    private function isSlotAvailableForTrainer(int $trainerId, string $scheduledAt, int $durationMinutes): bool
    {
        $dt = \Carbon\Carbon::parse($scheduledAt);
        $dayOfWeek = $dt->dayOfWeekIso;
        $time = $dt->format('H:i');
        $endTime = $dt->copy()->addMinutes($durationMinutes)->format('H:i');
        $date = $dt->format('Y-m-d');

        if (Schema::hasTable('gymies_availability_exceptions')) {
            $exception = DB::table('gymies_availability_exceptions')
                ->where('trainer_user_id', $trainerId)
                ->where('exception_date', $date)
                ->orderByDesc('id')
                ->first();
            if ($exception) {
                if (!$exception->is_available) {
                    return false;
                }
                if ($exception->start_time && $exception->end_time) {
                    if ($time < $exception->start_time || $endTime > $exception->end_time) {
                        return false;
                    }
                }
            }
        }

        if (Schema::hasTable('gymies_availability_slots')) {
            $hasSlots = DB::table('gymies_availability_slots')
                ->where('trainer_user_id', $trainerId)
                ->exists();
            if ($hasSlots) {
                $slot = DB::table('gymies_availability_slots')
                    ->where('trainer_user_id', $trainerId)
                    ->where('day_of_week', $dayOfWeek)
                    ->where('start_time', '<=', $time)
                    ->where('end_time', '>=', $endTime)
                    ->first();
                if (!$slot) {
                    return false;
                }
            }
        }

        return true;
    }

    private function sendSpoedInvalNotification(int $requestId, int $offerId, int $substituteTrainerId, $bookings, bool $shareLessonPlan = false): void
    {
        if (!Schema::hasTable('gymies_notification_queue')) {
            return;
        }

        $first = $bookings->first();
        $destLat = null;
        $destLng = null;
        if ($first && $first->trainer_location_id && Schema::hasTable('gymies_trainer_locations')) {
            $loc = DB::table('gymies_trainer_locations')->where('id', $first->trainer_location_id)->first(['latitude', 'longitude']);
            if ($loc && $loc->latitude !== null && $loc->longitude !== null) {
                $destLat = (float) $loc->latitude;
                $destLng = (float) $loc->longitude;
            }
        }

        $sessions = $bookings->map(function ($b) {
            $loc = trim(($b->location_notes ?? '') ?: '');
            if ($loc === '' && !empty($b->location_type)) {
                $loc = $b->location_type === 'gym' ? 'Sportschool' : ($b->location_type === 'on_site' ? 'Op locatie' : 'Online');
            }
            // N-031 FIXED: strip HTML tags and escape output from shift description
            $locClean = strip_tags($loc);
            $locClean = htmlspecialchars($locClean, ENT_QUOTES | ENT_HTML5, 'UTF-8');
            return [
                'scheduled_at' => $b->scheduled_at,
                'duration_minutes' => (int) ($b->duration_minutes ?? 60),
                'location' => $locClean ?: null,
                'location_type' => $b->location_type ?? null,
                'amount_cents' => $b->amount_cents ?? null,
                'trainer_payout_cents' => $b->trainer_payout_cents ?? $b->amount_cents ?? null,
            ];
        })->all();
        $totalCents = $bookings->sum(fn ($b) => (int) ($b->trainer_payout_cents ?? $b->amount_cents ?? 0));

        $payload = [
            'spoed_inval_request_id' => (string) $requestId,
            'spoed_inval_offer_id' => (string) $offerId,
            'original_trainer_user_id' => (string) ($first ? $first->trainer_user_id : ''),
            'booking_ids' => $bookings->pluck('id')->map(fn ($id) => (string) $id)->all(),
            'scheduled_at' => $first ? $first->scheduled_at : null,
            'count' => $bookings->count(),
            'sessions' => $sessions,
            'total_payout_cents' => $totalCents,
            'destination_lat' => $destLat,
            'destination_lng' => $destLng,
            'share_lesson_plan' => $shareLessonPlan,
        ];

        DB::table('gymies_notification_queue')->insert([
            'user_id' => $substituteTrainerId,
            'channel' => 'in_app',
            'event_type' => 'spoed_inval_offer',
            'payload_json' => json_encode($payload),
            'scheduled_for' => now(),
            'created_at' => now(),
        ]);
    }

    private function notifyOriginalTrainerAccepted(int $originalTrainerId, int $substituteId, $bookings): void
    {
        if (!Schema::hasTable('gymies_notification_queue')) {
            return;
        }

        $substitute = DB::table('gymies_users')->where('id', $substituteId)->first(['display_name', 'email']);
        $name = $substitute->display_name ?? $substitute->email ?? 'Een trainer';

        DB::table('gymies_notification_queue')->insert([
            'user_id' => $originalTrainerId,
            'channel' => 'in_app',
            'event_type' => 'spoed_inval_accepted',
            'payload_json' => json_encode([
                'substitute_trainer_user_id' => (string) $substituteId,
                'substitute_display_name' => $name,
                'booking_ids' => $bookings->pluck('id')->map(fn ($id) => (string) $id)->all(),
                'count' => $bookings->count(),
            ]),
            'scheduled_for' => now(),
            'created_at' => now(),
        ]);
    }

    private function createSpoedInvalSupportTicket(
        int $originalTrainerId,
        int $substituteTrainerId,
        int $requestId,
        $bookings
    ): ?int {
        if (!Schema::hasTable('gymies_support_tickets') || !Schema::hasTable('gymies_support_ticket_messages')) {
            return null;
        }

        $original = DB::table('gymies_users')->where('id', $originalTrainerId)->first(['display_name', 'email']);
        $substitute = DB::table('gymies_users')->where('id', $substituteTrainerId)->first(['display_name', 'email']);

        $lines = [
            '[SPOED INVAL - Betalingsoverdracht]',
            '',
            'Originele trainer: ' . ($original->display_name ?? $original->email ?? '') . ' (user_id: ' . $originalTrainerId . ')',
            'Invaller: ' . ($substitute->display_name ?? $substitute->email ?? '') . ' (user_id: ' . $substituteTrainerId . ')',
            'Spoed inval request_id: ' . $requestId,
            '',
            'Boekingen overgedragen:',
        ];
        foreach ($bookings as $b) {
            $amount = $b->amount_cents ?? $b->trainer_payout_cents ?? 0;
            $lines[] = sprintf(
                '  - Boeking #%d: %s, %d min, %d cent (trainer_payout)',
                $b->id,
                $b->scheduled_at,
                (int) ($b->duration_minutes ?? 60),
                $amount
            );
        }
        $lines[] = '';
        $lines[] = 'Actie: Verplaats betaling van originele trainer naar invaller.';

        $message = implode("\n", $lines);

        $insert = [
            'user_id' => $originalTrainerId,
            'subject' => 'Spoed Inval – betalingsoverdracht naar invaller',
            'category' => 'payment',
            'priority' => 'high',
            'status' => 'new',
            'created_at' => now(),
            'updated_at' => now(),
        ];
        if (Schema::hasColumn('gymies_support_tickets', 'submitter_name')) {
            $insert['submitter_name'] = $original->display_name ?? $original->email ?? '';
            $insert['submitter_email'] = $original->email ?? '';
        }
        $ticketId = DB::table('gymies_support_tickets')->insertGetId($insert);

        DB::table('gymies_support_ticket_messages')->insert([
            'ticket_id' => $ticketId,
            'author_user_id' => $originalTrainerId,
            'message' => $message,
            'is_internal' => 0,
            'created_at' => now(),
        ]);

        if (class_exists(GymiesSupportSync::class)) {
            GymiesSupportSync::ensureSupportConversationForTicket($ticketId, $originalTrainerId, $message);
        }

        return $ticketId;
    }

    private function audit(int $requestId, string $action, ?int $actorId, array $payload): void
    {
        if (!Schema::hasTable('gymies_spoed_inval_audit')) {
            return;
        }
        DB::table('gymies_spoed_inval_audit')->insert([
            'spoed_inval_request_id' => $requestId,
            'action' => $action,
            'actor_user_id' => $actorId,
            'payload_json' => json_encode($payload),
            'created_at' => now(),
        ]);
    }

    private function formatRequestRow($r, bool $includeSubstitute): array
    {
        $bookingIds = $r->booking_ids ? array_map('intval', explode(',', $r->booking_ids)) : [];
        $data = [
            'id' => (string) $r->id,
            'status' => (string) $r->status,
            'booking_ids' => $bookingIds,
            'expires_at' => $r->expires_at,
            'created_at' => $r->created_at,
        ];
        if ($includeSubstitute && $r->substitute_trainer_user_id) {
            $data['substitute_trainer_user_id'] = (string) $r->substitute_trainer_user_id;
        }
        return $data;
    }

    private function formatOfferRow($r): array
    {
        $bookingIds = $r->booking_ids ? array_map('intval', explode(',', $r->booking_ids)) : [];
        return [
            'request_id' => (string) $r->id,
            'offer_id' => (string) $r->offer_id,
            'status' => (string) $r->status,
            'offer_status' => (string) $r->offer_status,
            'original_trainer_user_id' => (string) $r->original_trainer_user_id,
            'booking_ids' => $bookingIds,
            'expires_at' => $r->expires_at,
            'created_at' => $r->created_at,
        ];
    }
}
