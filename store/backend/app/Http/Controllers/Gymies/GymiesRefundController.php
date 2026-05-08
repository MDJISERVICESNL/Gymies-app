<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Http\Traits\GymiesSchemaCacheTrait;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies Refunds: trainer of klant initieert terugbetaling via Mollie Refunds API.
 * Houdt rekening met het annuleringsbeleid (cancellation policies) van de trainer.
 * Ondersteunt zowel 1-op-1 bookings als groepssessie participants.
 */
final class GymiesRefundController extends Controller
{
    use GymiesSchemaCacheTrait;

    private const MOLLIE_API_URL = 'https://api.mollie.com/v2';
    private const GRACE_PERIOD_MINUTES = 15;
    private const CANCELLATION_HOURS_FULL_CHOICE = 48;
    private const CANCELLATION_HOURS_CREDITS_ONLY = 24;

    // ─── 1-op-1 Booking Refund ──────────────────────────────────────

    /**
     * Preview: wat krijgt de klant terug bij een refund voor deze boeking?
     */
    public function bookingRefundPreview(Request $request, string $bookingId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $booking = DB::table('gymies_bookings')->where('id', (int) $bookingId)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        $isTrainer = (int) $booking->trainer_user_id === (int) $user->id;
        $isClient = (int) $booking->client_user_id === (int) $user->id;
        if (!$isTrainer && !$isClient) {
            return response()->json(['message' => 'Geen toegang.'], 403);
        }

        if (empty($booking->paid_at)) {
            return response()->json(['message' => 'Deze boeking is nog niet betaald. Gebruik annuleren in plaats van refund.'], 422);
        }

        $amountCents = (int) ($booking->amount_cents ?? 0);
        $outcome = $this->calculateRefundOutcome($booking, $isTrainer);

        $refundAmountCents = (int) round($amountCents * $outcome['refund_percent'] / 100);
        $cancellationFeeCents = $amountCents - $refundAmountCents;

        return response()->json([
            'data' => [
                'booking_id' => (string) $booking->id,
                'original_amount_cents' => $amountCents,
                'refund_amount_cents' => $refundAmountCents,
                'cancellation_fee_cents' => $cancellationFeeCents,
                'refund_percent' => $outcome['refund_percent'],
                'refund_method' => $outcome['refund_method'],
                'policy_message' => $outcome['cancellation_policy_message'],
                'can_refund' => $refundAmountCents > 0,
            ],
        ]);
    }

    /**
     * Voer refund uit voor een betaalde boeking.
     * Trainer of klant kan dit starten; annuleringsbeleid wordt automatisch toegepast.
     */
    public function refundBooking(Request $request, string $bookingId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $request->validate([
            'reason' => 'required|string|max:500',
            'refund_method' => 'nullable|string|in:mollie,wallet',
        ]);

        $booking = DB::table('gymies_bookings')->where('id', (int) $bookingId)->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        $isTrainer = (int) $booking->trainer_user_id === (int) $user->id;
        $isClient = (int) $booking->client_user_id === (int) $user->id;
        if (!$isTrainer && !$isClient) {
            return response()->json(['message' => 'Geen toegang.'], 403);
        }

        if (empty($booking->paid_at)) {
            return response()->json(['message' => 'Deze boeking is niet betaald. Gebruik annuleren.'], 422);
        }

        GymiesSchemaEnsure::refundsTable();

        DB::beginTransaction();
        try {
            // Lock booking row to prevent concurrent refund race conditions
            $booking = DB::table('gymies_bookings')->where('id', (int) $bookingId)->lockForUpdate()->first();
            if (!$booking) {
                DB::rollBack();
                return response()->json(['message' => 'Boeking niet gevonden.'], 404);
            }

            // Check of er al een refund loopt (inside transaction with lock)
            if ($this->tableExists('gymies_refunds')) {
                $existingRefund = DB::table('gymies_refunds')
                    ->where('booking_id', (int) $bookingId)
                    ->whereIn('status', ['pending', 'processing', 'completed'])
                    ->lockForUpdate()
                    ->first();
                if ($existingRefund) {
                    DB::rollBack();
                    return response()->json(['message' => 'Er loopt al een terugbetaling voor deze boeking.'], 422);
                }
            }

            $amountCents = (int) ($booking->amount_cents ?? 0);
            $outcome = $this->calculateRefundOutcome($booking, $isTrainer);
            $refundAmountCents = (int) round($amountCents * $outcome['refund_percent'] / 100);
            $cancellationFeeCents = $amountCents - $refundAmountCents;

            if ($refundAmountCents <= 0) {
                DB::rollBack();
                return response()->json([
                    'message' => 'Geen terugbetaling mogelijk volgens het annuleringsbeleid.',
                    'policy_message' => $outcome['cancellation_policy_message'],
                ], 422);
            }

            // Bepaal refund methode
            $refundMethod = $request->input('refund_method', $outcome['refund_method']);
            if ($refundMethod === 'mollie' && $outcome['refund_method'] === 'wallet') {
                $refundMethod = 'wallet'; // kan niet naar Mollie als beleid wallet zegt
            }

            // Zoek originele Mollie transactie
            $transaction = null;
            if ($this->tableExists('gymies_payment_transactions')) {
                $transaction = DB::table('gymies_payment_transactions')
                    ->where('booking_id', (int) $bookingId)
                    ->where('status', 'paid')
                    ->where('provider', 'mollie')
                    ->first();
            }

            $mollieRefundId = null;
            $refundStatus = 'pending';
            // TODO: Wrap Mollie refund + DB insert in saga pattern with compensation on failure
            // Mollie refund aanmaken als betaald via Mollie
            if ($refundMethod === 'mollie' && $transaction && $transaction->provider_transaction_id) {
                $mollieResult = $this->createMollieRefund(
                    $transaction->provider_transaction_id,
                    $refundAmountCents,
                    $request->input('reason')
                );
                if ($mollieResult) {
                    $mollieRefundId = $mollieResult['id'];
                    $refundStatus = 'processing';
                } else {
                    // Mollie refund mislukt → fallback wallet
                    $refundMethod = 'wallet';
                }
            }

            // Wallet refund
            if ($refundMethod === 'wallet') {
                $this->processWalletRefund(
                    (int) $booking->client_user_id,
                    $refundAmountCents,
                    (int) $booking->id,
                    null,
                    $isTrainer ? 'Terugbetaling door trainer.' : 'Terugbetaling volgens annuleringsbeleid.'
                );
                $refundStatus = 'completed';
            }

            // Refund record opslaan
            $refundId = DB::table('gymies_refunds')->insertGetId([
                'booking_id' => (int) $booking->id,
                'group_participant_id' => null,
                'transaction_id' => $transaction->id ?? null,
                'initiated_by_user_id' => (int) $user->id,
                'trainer_user_id' => (int) $booking->trainer_user_id,
                'client_user_id' => (int) $booking->client_user_id,
                'mollie_refund_id' => $mollieRefundId,
                'mollie_payment_id' => $transaction->provider_transaction_id ?? null,
                'original_amount_cents' => $amountCents,
                'refund_amount_cents' => $refundAmountCents,
                'refund_percent' => $outcome['refund_percent'],
                'cancellation_fee_cents' => $cancellationFeeCents,
                'refund_method' => $refundMethod,
                'reason' => $request->input('reason'),
                'status' => $refundStatus,
                'policy_snapshot' => json_encode($outcome),
                'completed_at' => $refundStatus === 'completed' ? now() : null,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // Update booking status
            DB::table('gymies_bookings')
                ->where('id', (int) $booking->id)
                ->update([
                    'status' => 'cancelled',
                    'cancelled_at' => now(),
                    'cancelled_by_user_id' => (int) $user->id,
                    'updated_at' => now(),
                ]);

            // Update transactie status
            if ($transaction && $this->tableExists('gymies_payment_transactions')) {
                DB::table('gymies_payment_transactions')
                    ->where('id', $transaction->id)
                    ->update(['status' => 'refunded', 'updated_at' => now()]);
            }

            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            if (function_exists('logger')) {
                logger()->error('Gymies refund failed', ['error' => $e->getMessage(), 'booking' => $bookingId]);
            }
            return response()->json(['message' => 'Terugbetaling mislukt. Probeer het later opnieuw.'], 500);
        }

        return response()->json([
            'data' => [
                'refund_id' => (string) $refundId,
                'refund_amount_cents' => $refundAmountCents,
                'cancellation_fee_cents' => $cancellationFeeCents,
                'refund_method' => $refundMethod,
                'status' => $refundStatus,
                'policy_message' => $outcome['cancellation_policy_message'],
            ],
        ]);
    }

    // ─── Groepssessie Per-Participant Refund ──────────────────────────

    /**
     * Preview refund voor een groepssessie-deelnemer.
     */
    public function groupParticipantRefundPreview(Request $request, string $participantId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $result = $this->resolveGroupParticipant($participantId, $user);
        if ($result['error']) {
            return response()->json(['message' => $result['error']], $result['code']);
        }

        $participant = $result['participant'];
        $session = $result['session'];
        $isTrainer = $result['is_trainer'];

        if (empty($participant->paid_at)) {
            return response()->json(['message' => 'Deze deelnemer heeft nog niet betaald.'], 422);
        }

        $amountCents = (int) ($participant->amount_cents ?? 0);
        $outcome = $this->calculateGroupRefundOutcome($session, $participant, $isTrainer);
        $refundAmountCents = (int) round($amountCents * $outcome['refund_percent'] / 100);

        return response()->json([
            'data' => [
                'participant_id' => (string) $participant->id,
                'client_user_id' => (string) $participant->client_user_id,
                'original_amount_cents' => $amountCents,
                'refund_amount_cents' => $refundAmountCents,
                'cancellation_fee_cents' => $amountCents - $refundAmountCents,
                'refund_percent' => $outcome['refund_percent'],
                'refund_method' => $outcome['refund_method'],
                'policy_message' => $outcome['cancellation_policy_message'],
                'can_refund' => $refundAmountCents > 0,
                'session_continues' => true,
            ],
        ]);
    }

    /**
     * Voer refund uit voor één groepssessie-deelnemer.
     * De sessie gaat door voor de rest.
     */
    public function refundGroupParticipant(Request $request, string $participantId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $request->validate([
            'reason' => 'required|string|max:500',
            'refund_method' => 'nullable|string|in:mollie,wallet',
        ]);

        $result = $this->resolveGroupParticipant($participantId, $user);
        if ($result['error']) {
            return response()->json(['message' => $result['error']], $result['code']);
        }

        $participant = $result['participant'];
        $session = $result['session'];
        $isTrainer = $result['is_trainer'];

        if (empty($participant->paid_at)) {
            return response()->json(['message' => 'Deze deelnemer heeft niet betaald. Gebruik uitschrijven.'], 422);
        }

        // Check bestaande refund
        GymiesSchemaEnsure::refundsTable();
        if ($this->tableExists('gymies_refunds')) {
            $existing = DB::table('gymies_refunds')
                ->where('group_participant_id', (int) $participantId)
                ->whereIn('status', ['pending', 'processing', 'completed'])
                ->first();
            if ($existing) {
                return response()->json(['message' => 'Er loopt al een terugbetaling voor deze deelnemer.'], 422);
            }
        }

        $amountCents = (int) ($participant->amount_cents ?? 0);
        $outcome = $this->calculateGroupRefundOutcome($session, $participant, $isTrainer);
        $refundAmountCents = (int) round($amountCents * $outcome['refund_percent'] / 100);
        $cancellationFeeCents = $amountCents - $refundAmountCents;

        if ($refundAmountCents <= 0) {
            return response()->json([
                'message' => 'Geen terugbetaling mogelijk volgens het annuleringsbeleid.',
                'policy_message' => $outcome['cancellation_policy_message'],
            ], 422);
        }

        $refundMethod = $request->input('refund_method', $outcome['refund_method']);
        if ($refundMethod === 'mollie' && $outcome['refund_method'] === 'wallet') {
            $refundMethod = 'wallet';
        }

        // Zoek Mollie transactie
        $transaction = null;
        if ($this->tableExists('gymies_payment_transactions')) {
            $transaction = DB::table('gymies_payment_transactions')
                ->where('group_participant_id', (int) $participantId)
                ->where('status', 'paid')
                ->where('provider', 'mollie')
                ->first();
        }

        $mollieRefundId = null;
        $refundStatus = 'pending';

        DB::beginTransaction();
        try {
            // Mollie refund
            if ($refundMethod === 'mollie' && $transaction && $transaction->provider_transaction_id) {
                $mollieResult = $this->createMollieRefund(
                    $transaction->provider_transaction_id,
                    $refundAmountCents,
                    $request->input('reason')
                );
                if ($mollieResult) {
                    $mollieRefundId = $mollieResult['id'];
                    $refundStatus = 'processing';
                } else {
                    $refundMethod = 'wallet';
                }
            }

            // Wallet refund
            if ($refundMethod === 'wallet') {
                $this->processWalletRefund(
                    (int) $participant->client_user_id,
                    $refundAmountCents,
                    null,
                    (int) $participant->id,
                    $isTrainer ? 'Terugbetaling groepsles door trainer.' : 'Terugbetaling groepsles volgens beleid.'
                );
                $refundStatus = 'completed';
            }

            // Refund record
            $refundId = DB::table('gymies_refunds')->insertGetId([
                'booking_id' => null,
                'group_participant_id' => (int) $participant->id,
                'transaction_id' => $transaction->id ?? null,
                'initiated_by_user_id' => (int) $user->id,
                'trainer_user_id' => (int) $session->trainer_user_id,
                'client_user_id' => (int) $participant->client_user_id,
                'mollie_refund_id' => $mollieRefundId,
                'mollie_payment_id' => $transaction->provider_transaction_id ?? null,
                'original_amount_cents' => $amountCents,
                'refund_amount_cents' => $refundAmountCents,
                'refund_percent' => $outcome['refund_percent'],
                'cancellation_fee_cents' => $cancellationFeeCents,
                'refund_method' => $refundMethod,
                'reason' => $request->input('reason'),
                'status' => $refundStatus,
                'policy_snapshot' => json_encode($outcome),
                'completed_at' => $refundStatus === 'completed' ? now() : null,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // Update participant status → refunded (sessie gaat door voor de rest)
            DB::table('gymies_group_session_participants')
                ->where('id', (int) $participant->id)
                ->update(['status' => 'refunded', 'updated_at' => now()]);

            // Update transactie status
            if ($transaction && $this->tableExists('gymies_payment_transactions')) {
                DB::table('gymies_payment_transactions')
                    ->where('id', $transaction->id)
                    ->update(['status' => 'refunded', 'updated_at' => now()]);
            }

            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            if (function_exists('logger')) {
                logger()->error('Gymies group refund failed', ['error' => $e->getMessage(), 'participant' => $participantId]);
            }
            return response()->json(['message' => 'Terugbetaling mislukt. Probeer het later opnieuw.'], 500);
        }

        // Hoeveel deelnemers nog actief na deze refund?
        $remainingCount = (int) DB::table('gymies_group_session_participants')
            ->where('group_session_id', (int) $session->id)
            ->whereIn('status', ['pending', 'registered', 'payment_pending', 'confirmed'])
            ->count();

        return response()->json([
            'data' => [
                'refund_id' => (string) $refundId,
                'participant_id' => (string) $participant->id,
                'refund_amount_cents' => $refundAmountCents,
                'cancellation_fee_cents' => $cancellationFeeCents,
                'refund_method' => $refundMethod,
                'status' => $refundStatus,
                'policy_message' => $outcome['cancellation_policy_message'],
                'session_continues' => true,
                'remaining_participants' => $remainingCount,
            ],
        ]);
    }

    // ─── Trainer: betalingsoverzicht groepssessie ────────────────────

    /**
     * Trainer ziet wie betaald heeft per groepssessie.
     */
    public function groupSessionPaymentOverview(Request $request, string $sessionId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers.'], 403);
        }

        $session = DB::table('gymies_group_sessions')
            ->where('id', (int) $sessionId)
            ->where('trainer_user_id', (int) $user->id)
            ->first();
        if (!$session) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }

        $participants = DB::table('gymies_group_session_participants as p')
            ->leftJoin('gymies_users as u', 'p.client_user_id', '=', 'u.id')
            ->where('p.group_session_id', (int) $sessionId)
            ->select([
                'p.id as participant_id',
                'p.client_user_id',
                'u.display_name',
                'p.status',
                'p.amount_cents',
                'p.paid_at',
                'p.created_at as registered_at',
            ])
            ->orderBy('p.created_at')
            ->get();

        $totalPaid = $participants->whereNotNull('paid_at')->sum('amount_cents');
        $totalExpected = $participants->whereIn('status', ['pending', 'registered', 'payment_pending', 'confirmed'])->count()
            * (int) ($session->price_per_participant_cents ?? $session->price_cents ?? 0);
        $paidCount = $participants->whereNotNull('paid_at')->count();
        $totalCount = $participants->whereIn('status', ['pending', 'registered', 'payment_pending', 'confirmed', 'refunded'])->count();

        return response()->json([
            'data' => [
                'session_id' => (string) $session->id,
                'title' => $session->title,
                'summary' => "{$paidCount}/{$totalCount} betaald",
                'total_paid_cents' => (int) $totalPaid,
                'total_expected_cents' => $totalExpected,
                'participants' => $participants->map(fn ($p) => [
                    'participant_id' => (string) $p->participant_id,
                    'client_user_id' => (string) $p->client_user_id,
                    'display_name' => $p->display_name ?? 'Onbekend',
                    'status' => $p->status,
                    'amount_cents' => (int) ($p->amount_cents ?? 0),
                    'paid' => !empty($p->paid_at),
                    'paid_at' => $p->paid_at,
                    'registered_at' => $p->registered_at,
                ])->values()->all(),
            ],
        ]);
    }

    // ─── Refund history ──────────────────────────────────────────────

    /**
     * Lijst van refunds voor een trainer.
     */
    public function trainerRefunds(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers.'], 403);
        }

        GymiesSchemaEnsure::refundsTable();
        if (!$this->tableExists('gymies_refunds')) {
            return response()->json(['data' => []]);
        }

        $refunds = DB::table('gymies_refunds as r')
            ->leftJoin('gymies_users as u', 'r.client_user_id', '=', 'u.id')
            ->where('r.trainer_user_id', (int) $user->id)
            ->select([
                'r.*',
                'u.display_name as client_name',
            ])
            ->orderByDesc('r.created_at')
            ->limit(50)
            ->get();

        return response()->json([
            'data' => $refunds->map(fn ($r) => [
                'id' => (string) $r->id,
                'booking_id' => $r->booking_id ? (string) $r->booking_id : null,
                'group_participant_id' => $r->group_participant_id ? (string) $r->group_participant_id : null,
                'client_name' => $r->client_name ?? 'Onbekend',
                'original_amount_cents' => (int) $r->original_amount_cents,
                'refund_amount_cents' => (int) $r->refund_amount_cents,
                'refund_percent' => (int) $r->refund_percent,
                'cancellation_fee_cents' => (int) $r->cancellation_fee_cents,
                'refund_method' => $r->refund_method,
                'reason' => $r->reason,
                'status' => $r->status,
                'created_at' => $r->created_at,
            ])->all(),
        ]);
    }

    // ─── Private helpers ─────────────────────────────────────────────

    /**
     * Berekent refund outcome op basis van het annuleringsbeleid voor een booking.
     */
    private function calculateRefundOutcome(object $booking, bool $isTrainer): array
    {
        $scheduledAt = Carbon::parse($booking->scheduled_at);
        $hoursUntil = $scheduledAt->isFuture() ? $scheduledAt->diffInSeconds(now()) / 3600.0 : 0.0;

        return $this->applyCancellationPolicy(
            $hoursUntil,
            $isTrainer,
            (int) $booking->trainer_user_id,
            $booking->created_at ?? null
        );
    }

    /**
     * Berekent refund outcome voor een groepssessie-deelnemer.
     */
    private function calculateGroupRefundOutcome(object $session, object $participant, bool $isTrainer): array
    {
        $scheduledAt = Carbon::parse($session->scheduled_at);
        $hoursUntil = $scheduledAt->isFuture() ? $scheduledAt->diffInSeconds(now()) / 3600.0 : 0.0;

        return $this->applyCancellationPolicy(
            $hoursUntil,
            $isTrainer,
            (int) $session->trainer_user_id,
            $participant->created_at ?? null
        );
    }

    /**
     * Herbruikbare annuleringsbeleid-berekening (zelfde logica als GymiesBookingController::cancellationOutcome).
     */
    private function applyCancellationPolicy(float $hoursUntil, bool $isTrainer, int $trainerUserId, ?string $createdAt = null): array
    {
        // Bedenktijd: klant binnen 15 min na boeking → 100% Mollie/bank
        if (!$isTrainer && $createdAt !== null) {
            $minutesSinceBooking = Carbon::parse($createdAt)->diffInSeconds(now()) / 60.0;
            if ($minutesSinceBooking <= self::GRACE_PERIOD_MINUTES) {
                return [
                    'refund_percent' => 100,
                    'refund_method' => 'mollie',
                    'cancellation_policy_message' => 'Bedenktijd: binnen 15 minuten. 100% terug, geen kosten.',
                    'grace_period' => true,
                ];
            }
        }

        // Laad trainer-specifieke annuleringsregels
        $policies = collect();
        if ($this->tableExists('gymies_cancellation_policies')) {
            $policies = DB::table('gymies_cancellation_policies')
                ->where('trainer_user_id', $trainerUserId)
                ->orderBy('hours_before', 'desc')
                ->limit(50)
                ->get();
        }

        // Trainer initieert refund → altijd 100%
        if ($isTrainer) {
            $fullChoiceThreshold = $policies->isNotEmpty()
                ? (int) $policies->first()->hours_before
                : self::CANCELLATION_HOURS_FULL_CHOICE;
            return [
                'refund_percent' => 100,
                'refund_method' => $hoursUntil >= $fullChoiceThreshold ? 'mollie' : 'wallet',
                'cancellation_policy_message' => 'Trainer start terugbetaling. Klant krijgt 100% terug.',
                'grace_period' => false,
            ];
        }

        // Klant: trainer-regels
        if ($policies->isNotEmpty()) {
            foreach ($policies as $i => $policy) {
                if ($hoursUntil >= (int) $policy->hours_before) {
                    $isTopTier = ($i === 0);
                    $refundPercent = (int) $policy->refund_percent;
                    $method = $isTopTier && $refundPercent > 0 ? 'mollie' : ($refundPercent > 0 ? 'wallet' : 'none');
                    return [
                        'refund_percent' => $refundPercent,
                        'refund_method' => $method,
                        'cancellation_policy_message' => "Annuleringsbeleid: {$refundPercent}% terug (>{$policy->hours_before}u voor aanvang).",
                        'grace_period' => false,
                    ];
                }
            }
            $shortestHours = (int) $policies->last()->hours_before;
            return [
                'refund_percent' => 0,
                'refund_method' => 'none',
                'cancellation_policy_message' => "Binnen {$shortestHours} uur voor aanvang: geen terugbetaling mogelijk.",
                'grace_period' => false,
            ];
        }

        // Fallback platformbeleid
        if ($hoursUntil >= self::CANCELLATION_HOURS_FULL_CHOICE) {
            return [
                'refund_percent' => 100,
                'refund_method' => 'mollie',
                'cancellation_policy_message' => 'Meer dan 48 uur voor aanvang: 100% terug via originele betaalmethode.',
                'grace_period' => false,
            ];
        }
        if ($hoursUntil >= self::CANCELLATION_HOURS_CREDITS_ONLY) {
            return [
                'refund_percent' => 100,
                'refund_method' => 'wallet',
                'cancellation_policy_message' => '24-48 uur voor aanvang: 100% terug als Gymies Credits.',
                'grace_period' => false,
            ];
        }
        return [
            'refund_percent' => 0,
            'refund_method' => 'none',
            'cancellation_policy_message' => 'Binnen 24 uur voor aanvang: geen terugbetaling mogelijk.',
            'grace_period' => false,
        ];
    }

    /**
     * Maak Mollie refund aan via de Refunds API.
     */
    private function createMollieRefund(string $molliePaymentId, int $amountCents, ?string $description = null): ?array
    {
        $apiKey = trim((string) config('gymies.mollie_api_key', env('MOLLIE_API_KEY', '')));
        if ($apiKey === '') {
            return null;
        }

        $amountEur = number_format($amountCents / 100, 2, '.', '');
        $body = [
            'amount' => [
                'currency' => 'EUR',
                'value' => $amountEur,
            ],
        ];
        if ($description) {
            $body['description'] = mb_substr($description, 0, 140);
        }

        $response = Http::withToken($apiKey)
            ->timeout(15)
            ->post(self::MOLLIE_API_URL . "/payments/{$molliePaymentId}/refunds", $body);

        if (!$response->successful()) {
            if (function_exists('logger')) {
                logger()->warning('Gymies Mollie refund failed', [
                    'payment_id' => $molliePaymentId,
                    'status' => $response->status(),
                    'body' => $response->json(),
                ]);
            }
            return null;
        }

        $data = $response->json();
        return [
            'id' => $data['id'] ?? null,
            'status' => $data['status'] ?? 'pending',
            'amount' => $data['amount'] ?? null,
        ];
    }

    /**
     * Verwerk wallet refund (Gymies Credits).
     */
    private function processWalletRefund(int $clientUserId, int $amountCents, ?int $bookingId, ?int $participantId, string $reason): void
    {
        if (!$this->tableExists('gymies_wallet_transactions') || !$this->columnExists('gymies_users', 'wallet_balance_cents')) {
            return;
        }

        DB::table('gymies_users')->where('id', $clientUserId)->increment('wallet_balance_cents', $amountCents);
        $newBalance = (int) (DB::table('gymies_users')->where('id', $clientUserId)->value('wallet_balance_cents') ?? 0);

        $insert = [
            'user_id' => $clientUserId,
            'amount_cents' => $amountCents,
            'balance_after_cents' => $newBalance,
            'booking_id' => $bookingId,
            'reason' => $reason,
            'reference_type' => 'refund',
            'admin_user_id' => null,
            'created_at' => now(),
        ];
        if ($this->columnExists('gymies_wallet_transactions', 'expires_at')) {
            $insert['expires_at'] = now()->addYear()->toDateString();
        }
        DB::table('gymies_wallet_transactions')->insert($insert);
    }

    /**
     * Resolve groepssessie-deelnemer + autorisatiecheck.
     */
    private function resolveGroupParticipant(string $participantId, object $user): array
    {
        if (!Schema::hasTable('gymies_group_session_participants')) {
            return ['error' => 'Deelnemers niet beschikbaar.', 'code' => 404, 'participant' => null, 'session' => null, 'is_trainer' => false];
        }

        $participant = DB::table('gymies_group_session_participants')
            ->where('id', (int) $participantId)
            ->first();

        if (!$participant) {
            return ['error' => 'Deelnemer niet gevonden.', 'code' => 404, 'participant' => null, 'session' => null, 'is_trainer' => false];
        }

        $session = DB::table('gymies_group_sessions')
            ->where('id', (int) $participant->group_session_id)
            ->first();

        if (!$session) {
            return ['error' => 'Groepsles niet gevonden.', 'code' => 404, 'participant' => null, 'session' => null, 'is_trainer' => false];
        }

        $isTrainer = (int) $session->trainer_user_id === (int) $user->id;
        $isClient = (int) $participant->client_user_id === (int) $user->id;

        if (!$isTrainer && !$isClient) {
            return ['error' => 'Geen toegang.', 'code' => 403, 'participant' => null, 'session' => null, 'is_trainer' => false];
        }

        return [
            'error' => null,
            'code' => 200,
            'participant' => $participant,
            'session' => $session,
            'is_trainer' => $isTrainer,
        ];
    }
}
