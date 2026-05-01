<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Http\Traits\GymiesSchemaCacheTrait;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies Betalingen: start betaling via Mollie API, status ophalen, webhook.
 * Tabellen: gymies_bookings (amount_cents, paid_at), gymies_payment_transactions.
 * Config: MOLLIE_API_KEY in .env (test_... of live_...).
 */
final class GymiesPaymentController extends Controller
{
    use GymiesSchemaCacheTrait;

    private const PROVIDER_MOLLIE = 'mollie';
    private const PROVIDER_CASH = 'cash';
    private const MOLLIE_API_URL = 'https://api.mollie.com/v2/payments';
    private const PAYMENT_METHOD_MOLLIE = 'mollie';
    private const PAYMENT_METHOD_CASH = 'cash';

    /**
     * Start betaling voor een bevestigde boeking (alleen klant, eigen boeking).
     * Maakt een Mollie-payment aan en retourneert redirect_url naar Mollie checkout.
     */
    public function startPayment(Request $request, string $bookingId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten kunnen betalen voor een boeking.'], 403);
        }
        if ($this->columnExists('gymies_users', 'email_verified_at')) {
            $verified = $user->email_verified_at ?? null;
            if ($verified === null || $verified === '') {
                return response()->json([
                    'message' => 'Verifieer eerst je e-mailadres voordat je kunt betalen.',
                    'requires_email_verification' => true,
                ], 422);
            }
        }
        if (!ctype_digit($bookingId) || (int) $bookingId < 1) {
            return response()->json(['message' => 'Ongeldige boeking.'], 422);
        }

        $booking = DB::table('gymies_bookings')
            ->where('id', (int) $bookingId)
            ->where('client_user_id', (int) $user->id)
            ->first();

        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if (!in_array((string) $booking->status, ['confirmed', 'reserved'], true)) {
            return response()->json(['message' => 'Alleen bevestigde of direct-gereserveerde boekingen kunnen worden betaald.'], 422);
        }
        if (!empty($booking->paid_at)) {
            return response()->json(['message' => 'Deze boeking is al betaald.'], 422);
        }

        $requestedMethod = $request->input('payment_method', $request->input('method', $request->input('pay_with', 'mollie')));
        $paymentMethod = $this->normalizeIncomingPaymentMethod((string) $requestedMethod);
        if (!in_array($paymentMethod, [self::PAYMENT_METHOD_MOLLIE, self::PAYMENT_METHOD_CASH], true)) {
            return response()->json(['message' => 'Ongeldige betaalmethode. Gebruik mollie of cash.'], 422);
        }

        $amountCents = (int) ($booking->amount_cents ?? 0);
        if ($amountCents <= 0) {
            return response()->json(['message' => 'Geen bedrag bekend voor deze boeking. Vraag de trainer om een bedrag vast te leggen.'], 422);
        }

        $promoCode = trim((string) ($request->input('promo_code') ?? ''));
        $promoCodeId = null;
        $discountAppliedCents = 0;
        if ($promoCode !== '' && $this->tableExists('gymies_promo_codes')) {
            $promoResult = $this->validateAndResolvePromo($promoCode, $amountCents, (int) $booking->trainer_user_id);
            if ($promoResult['valid']) {
                $promoCodeId = $promoResult['promo_code_id'];
                $discountAppliedCents = $promoResult['discount_cents'];
                $amountCents = max((int) $promoResult['amount_after_discount'], 0);
            }
        }

        $this->ensurePaymentTables();

        $returnUrl = trim((string) ($request->input('return_url') ?? ''));
        if ($returnUrl === '') {
            $returnUrl = rtrim($request->root(), '/') . '/betaling-terug?booking_id=' . $bookingId;
        }

        $provider = $paymentMethod === self::PAYMENT_METHOD_CASH ? self::PROVIDER_CASH : self::PROVIDER_MOLLIE;
        $providerStatus = $paymentMethod === self::PAYMENT_METHOD_CASH ? 'awaiting_cash' : 'pending';
        $paymentUrl = null;
        $providerTransactionId = 'tx_' . $bookingId . '_' . bin2hex(random_bytes(8));

        if ($paymentMethod === self::PAYMENT_METHOD_MOLLIE) {
            $trainerMollieProfileId = null;
            if ($this->columnExists('gymies_trainer_profiles', 'mollie_profile_id')) {
                $trainerMollieProfileId = DB::table('gymies_trainer_profiles')
                    ->where('user_id', (int) $booking->trainer_user_id)
                    ->value('mollie_profile_id');
            }
            $profileId = $trainerMollieProfileId ?: config('gymies.mollie_profile_id');

            $applicationFeeCents = $this->resolveApplicationFeeCents(
                (int) $booking->trainer_user_id,
                $amountCents
            );

            $apiKey = $this->getMollieApiKey();
            if ($apiKey === '') {
                return response()->json([
                    'message' => 'Mollie is niet geconfigureerd. Neem contact op met de trainer of probeer later opnieuw.',
                ], 503);
            }
            $webhookUrl = rtrim($request->root(), '/') . '/api/gymies/webhooks/mollie';
            $createResult = $this->createMolliePayment($apiKey, $amountCents, $bookingId, $returnUrl, $webhookUrl, $profileId, $applicationFeeCents);
            if ($createResult === null) {
                return response()->json([
                    'message' => 'Betaling kon niet worden gestart. Probeer het later opnieuw of neem contact op met de trainer.',
                ], 502);
            }
            $providerTransactionId = (string) $createResult['id'];
            $paymentUrl = (string) $createResult['checkout_url'];
        }

        $paymentId = null;
        if ($this->tableExists('gymies_payment_transactions')) {
            $insert = [
                'booking_id' => (int) $bookingId,
                'user_id' => (int) $user->id,
                'counterparty_user_id' => (int) $booking->trainer_user_id,
                'provider' => $provider,
                'provider_transaction_id' => $providerTransactionId,
                'amount_cents' => $amountCents,
                'status' => $providerStatus,
                'payment_method' => $paymentMethod,
                'paid_at' => null,
                'created_at' => now(),
                'updated_at' => now(),
            ];
            if ($promoCodeId !== null && $this->columnExists('gymies_payment_transactions', 'promo_code_id')) {
                $insert['promo_code_id'] = $promoCodeId;
                $insert['discount_applied_cents'] = $discountAppliedCents;
            }
            $paymentId = DB::table('gymies_payment_transactions')->insertGetId($insert);
        }

        if ($this->columnExists('gymies_bookings', 'payment_method')) {
            DB::table('gymies_bookings')->where('id', (int) $bookingId)->update([
                'payment_method' => $paymentMethod === self::PAYMENT_METHOD_MOLLIE ? 'mollie_connect' : 'cash',
                'updated_at' => now(),
            ]);
        }

        // Promo code use_count incrementeren na succesvolle toepassing
        if ($promoCodeId !== null && $this->tableExists('gymies_promo_codes')) {
            DB::table('gymies_promo_codes')->where('id', $promoCodeId)->increment('use_count');
        }

        $canonicalStatus = $this->canonicalPaymentStatus($providerStatus, $paymentMethod);

        return response()->json([
            'data' => [
                'payment_id' => $paymentId ? (string) $paymentId : $providerTransactionId,
                'payment_url' => $paymentUrl,
                'redirect_url' => $paymentUrl,
                'reference_id' => $providerTransactionId,
                'status' => $canonicalStatus,
                'status_raw' => $providerStatus,
                'payment_method' => $paymentMethod,
                'amount_cents' => $amountCents,
                'currency' => 'EUR',
                'discount_applied_cents' => $discountAppliedCents,
            ],
        ]);
    }

    private function getMollieApiKey(): string
    {
        $key = config('gymies.mollie_api_key');
        if ($key !== null && $key !== '') {
            return (string) $key;
        }
        // Fallback via config — NOOIT env() direct (breekt na config:cache)
        return '';
    }

    /**
     * Bepaal application fee (cent) voor Mollie Connect.
     * Volgorde: 1) gymies_fee_settings per trainer → 2) per plan → 3) env fallback
     * @param int|null $groupTotalParticipants  Bij groepssessie: verdeel fee over deelnemers
     */
    private function resolveApplicationFeeCents(int $trainerUserId, int $amountCents, ?int $groupTotalParticipants = null): ?int
    {
        GymiesSchemaEnsure::feeSettingsTable();

        $feeCents = null;
        $clientPaysFee = true;

        // 1) Trainer-specifieke fee setting
        if ($this->tableExists('gymies_fee_settings')) {
            $trainerSetting = DB::table('gymies_fee_settings')
                ->where('trainer_user_id', $trainerUserId)
                ->where('is_active', 1)
                ->first();

            if (!$trainerSetting) {
                // 2) Plan-based fee setting
                $planSlug = null;
                if ($this->tableExists('gymies_subscriptions') && $this->tableExists('gymies_plans')) {
                    $planSlug = DB::table('gymies_subscriptions as s')
                        ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
                        ->where('s.trainer_user_id', $trainerUserId)
                        ->whereIn('s.status', ['active', 'trialing'])
                        ->value('p.slug');
                }
                if ($planSlug) {
                    $trainerSetting = DB::table('gymies_fee_settings')
                        ->whereNull('trainer_user_id')
                        ->where('plan_slug', $planSlug)
                        ->where('is_active', 1)
                        ->first();
                }
                // 3) Globale default
                if (!$trainerSetting) {
                    $trainerSetting = DB::table('gymies_fee_settings')
                        ->whereNull('trainer_user_id')
                        ->whereNull('plan_slug')
                        ->where('is_active', 1)
                        ->first();
                }
            }

            if ($trainerSetting) {
                $clientPaysFee = (int) $trainerSetting->client_pays === 1;
                if ($trainerSetting->fee_type === 'percent') {
                    // fee_value = basispunten (250 = 2.5%)
                    $feeCents = (int) round($amountCents * (int) $trainerSetting->fee_value / 10000);
                } else {
                    $feeCents = (int) $trainerSetting->fee_value;
                }
            }
        }

        // Fallback naar env
        if ($feeCents === null) {
            $feeCents = (int) config('gymies.service_fee_cents', 49);
        }

        // Override client_pays via trainer_bank_accounts
        if ($this->tableExists('gymies_trainer_bank_accounts') && $this->columnExists('gymies_trainer_bank_accounts', 'client_pays_service_fee')) {
            $cp = DB::table('gymies_trainer_bank_accounts')
                ->where('trainer_user_id', $trainerUserId)
                ->value('client_pays_service_fee');
            if ($cp !== null) {
                $clientPaysFee = (int) $cp === 1;
            }
        }

        if (!$clientPaysFee || $feeCents <= 0) {
            return null;
        }

        // Groepssessie: verdeel fee over deelnemers
        if ($groupTotalParticipants !== null && $groupTotalParticipants > 1) {
            $feeCents = (int) max(1, ceil($feeCents / $groupTotalParticipants));
        }

        // Mollie max fee constraint
        $maxFeeCents = (int) floor($amountCents * 0.94 - 35);
        if ($maxFeeCents < $feeCents) {
            return null;
        }
        return $feeCents;
    }

    /**
     * @return array{id: string, checkout_url: string}|null
     */
    private function createMolliePayment(string $apiKey, int $amountCents, string $bookingId, string $returnUrl, string $webhookUrl, ?string $trainerProfileId = null, ?int $applicationFeeCents = null): ?array
    {
        $amountEur = number_format($amountCents / 100, 2, '.', '');
        $body = [
            'amount' => [
                'currency' => 'EUR',
                'value' => $amountEur,
            ],
            'description' => 'Boeking #' . $bookingId,
            'redirectUrl' => $returnUrl,
            'webhookUrl' => $webhookUrl,
        ];

        // Mollie Connect: betaling gaat direct naar trainer's Mollie-account; anders platform-profile
        $profileId = ($trainerProfileId !== null && $trainerProfileId !== '')
            ? $trainerProfileId
            : config('gymies.mollie_profile_id', '');
        if ($profileId !== null && $profileId !== '') {
            $body['profileId'] = $profileId;
            $body['testmode'] = (bool) config('gymies.mollie_testmode', str_starts_with($apiKey, 'test_'));
            if ($applicationFeeCents !== null && $applicationFeeCents >= 1) {
                $feeEur = number_format($applicationFeeCents / 100, 2, '.', '');
                $body['applicationFee'] = [
                    'amount' => ['currency' => 'EUR', 'value' => $feeEur],
                    'description' => 'Gymies servicekosten',
                ];
            }
        }

        $response = Http::withToken($apiKey)
            ->timeout(15)
            ->post(self::MOLLIE_API_URL, $body);

        if (!$response->successful()) {
            if (function_exists('logger')) {
                logger()->warning('Gymies Mollie create payment failed', [
                    'status' => $response->status(),
                    'body' => $response->json(),
                ]);
            }
            return null;
        }

        $data = $response->json();
        $id = $data['id'] ?? null;
        $checkoutHref = $data['_links']['checkout']['href'] ?? null;
        if ($id === null || $checkoutHref === null) {
            if (function_exists('logger')) {
                logger()->warning('Gymies Mollie response missing id or checkout link', ['data' => $data]);
            }
            return null;
        }

        return ['id' => (string) $id, 'checkout_url' => (string) $checkoutHref];
    }

    /**
     * Mollie-payment voor groepsles-inschrijving.
     * @return array{id: string, checkout_url: string}|null
     */
    private function createMolliePaymentForGroupParticipant(
        string $apiKey,
        int $amountCents,
        string $participantId,
        string $returnUrl,
        string $webhookUrl,
        ?string $trainerProfileId = null,
        ?int $applicationFeeCents = null
    ): ?array {
        $amountEur = number_format($amountCents / 100, 2, '.', '');
        $body = [
            'amount' => [
                'currency' => 'EUR',
                'value' => $amountEur,
            ],
            'description' => 'Groepsles inschrijving #' . $participantId,
            'redirectUrl' => $returnUrl,
            'webhookUrl' => $webhookUrl,
            'metadata' => [
                'group_participant_id' => $participantId,
            ],
        ];

        $profileId = ($trainerProfileId !== null && $trainerProfileId !== '')
            ? $trainerProfileId
            : config('gymies.mollie_profile_id', '');
        if ($profileId !== null && $profileId !== '') {
            $body['profileId'] = $profileId;
            $body['testmode'] = (bool) config('gymies.mollie_testmode', str_starts_with($apiKey, 'test_'));
            if ($applicationFeeCents !== null && $applicationFeeCents >= 1) {
                $feeEur = number_format($applicationFeeCents / 100, 2, '.', '');
                $body['applicationFee'] = [
                    'amount' => ['currency' => 'EUR', 'value' => $feeEur],
                    'description' => 'Gymies servicekosten',
                ];
            }
        }

        $response = Http::withToken($apiKey)
            ->timeout(15)
            ->post(self::MOLLIE_API_URL, $body);

        if (!$response->successful()) {
            if (function_exists('logger')) {
                logger()->warning('Gymies Mollie group payment failed', [
                    'status' => $response->status(),
                    'body' => $response->json(),
                ]);
            }
            return null;
        }

        $data = $response->json();
        $id = $data['id'] ?? null;
        $checkoutHref = $data['_links']['checkout']['href'] ?? null;
        if ($id === null || $checkoutHref === null) {
            return null;
        }

        return ['id' => (string) $id, 'checkout_url' => (string) $checkoutHref];
    }

    private function createStubRedirectUrl(string $returnUrl, string $providerTransactionId): string
    {
        return $returnUrl . (str_contains($returnUrl, '?') ? '&' : '?') . 'payment_id=' . urlencode($providerTransactionId);
    }

    /**
     * Valideer kortingscode voor een boeking (bedrag bekend). Voor tonen in UI vóór betalen.
     */
    public function validatePromo(Request $request, string $bookingId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten kunnen een kortingscode gebruiken.'], 403);
        }
        if (!ctype_digit($bookingId) || (int) $bookingId < 1) {
            return response()->json(['message' => 'Ongeldige boeking.'], 422);
        }

        $booking = DB::table('gymies_bookings')
            ->where('id', (int) $bookingId)
            ->where('client_user_id', (int) $user->id)
            ->first(['id', 'amount_cents', 'trainer_user_id']);
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        $amountCents = (int) ($booking->amount_cents ?? 0);
        $code = trim((string) ($request->input('promo_code') ?? ''));
        if ($code === '') {
            return response()->json([
                'data' => ['valid' => false, 'message' => 'Voer een code in.'],
            ]);
        }

        $trainerUserId = (int) ($booking->trainer_user_id ?? 0);
        $result = $this->validateAndResolvePromo($code, $amountCents, $trainerUserId);
        return response()->json([
            'data' => [
                'valid' => $result['valid'],
                'message' => $result['message'],
                'discount_cents' => $result['valid'] ? $result['discount_cents'] : 0,
                'amount_after_discount' => $result['valid'] ? $result['amount_after_discount'] : $amountCents,
            ],
        ]);
    }

    /**
     * @return array{valid: bool, message: string, promo_code_id?: int, discount_cents?: int, amount_after_discount?: int}
     */
    private function validateAndResolvePromo(string $code, int $amountCents, int $counterpartyTrainerUserId = 0): array
    {
        if (!$this->tableExists('gymies_promo_codes')) {
            return ['valid' => false, 'message' => 'Kortingscodes zijn niet beschikbaar.'];
        }

        $row = DB::table('gymies_promo_codes')
            ->where('code', $code)
            ->first();
        if (!$row) {
            return ['valid' => false, 'message' => 'Deze code is ongeldig.'];
        }

        // Trainer-eigen codes: alleen geldig voor boekingen/lessen van die trainer (platform-codes zonder trainer_user_id zijn uitgefaseerd)
        if ($this->columnExists('gymies_promo_codes', 'trainer_user_id')) {
            $ownerTrainerId = $row->trainer_user_id !== null ? (int) $row->trainer_user_id : null;
            if ($ownerTrainerId === null) {
                return ['valid' => false, 'message' => 'Deze code is niet meer geldig. Vraag je trainer om een actiecode.'];
            }
            if ($counterpartyTrainerUserId > 0 && $ownerTrainerId !== $counterpartyTrainerUserId) {
                return ['valid' => false, 'message' => 'Deze code hoort bij een andere trainer.'];
            }
            if ($counterpartyTrainerUserId <= 0) {
                return ['valid' => false, 'message' => 'Deze code kan alleen bij een boeking van je trainer worden gebruikt.'];
            }
        }

        $now = now()->toDateString();
        if ($row->valid_from !== null && $now < $row->valid_from) {
            return ['valid' => false, 'message' => 'Deze code is nog niet geldig.'];
        }
        if ($row->valid_until !== null && $now > $row->valid_until) {
            return ['valid' => false, 'message' => 'Deze code is verlopen.'];
        }
        if ($row->max_uses !== null && (int) $row->use_count >= (int) $row->max_uses) {
            return ['valid' => false, 'message' => 'Deze code is niet meer geldig (max. gebruik bereikt).'];
        }

        $value = (int) $row->value_cents;
        $discountCents = 0;
        if ($row->discount_type === 'percent') {
            $discountCents = (int) round($amountCents * $value / 100);
        } else {
            $discountCents = $value;
        }
        if ($discountCents > $amountCents) {
            $discountCents = $amountCents;
        }
        $amountAfterDiscount = $amountCents - $discountCents;

        return [
            'valid' => true,
            'message' => $discountCents > 0 ? 'Korting toegepast.' : 'Code geldig.',
            'promo_code_id' => (int) $row->id,
            'discount_cents' => $discountCents,
            'amount_after_discount' => $amountAfterDiscount,
        ];
    }

    /**
     * Betalingsstatus voor een boeking ophalen (klant: eigen boeking).
     */
    public function paymentStatus(Request $request, string $bookingId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!ctype_digit($bookingId) || (int) $bookingId < 1) {
            return response()->json(['message' => 'Ongeldige boeking.'], 422);
        }

        $bookingQuery = DB::table('gymies_bookings')->where('id', (int) $bookingId);
        if (in_array($user->role, ['klant', 'client'], true)) {
            $bookingQuery->where('client_user_id', (int) $user->id);
        } elseif ($user->role === 'trainer') {
            $bookingQuery->where('trainer_user_id', (int) $user->id);
        } else {
            return response()->json(['message' => 'Geen toegang tot deze betalingsstatus.'], 403);
        }

        $bookingSelect = ['id', 'status', 'amount_cents', 'paid_at'];
        if ($this->columnExists('gymies_bookings', 'payment_method')) {
            $bookingSelect[] = 'payment_method';
        }
        $booking = $bookingQuery->first($bookingSelect);
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        $tx = null;
        if ($this->tableExists('gymies_payment_transactions')) {
            $tx = DB::table('gymies_payment_transactions')
                ->where('booking_id', (int) $bookingId)
                ->orderByDesc('id')
                ->first(['id', 'status', 'paid_at', 'amount_cents', 'payment_method', 'provider', 'provider_transaction_id']);
        }

        if ($tx && $this->storedPaymentMethodToCanonical((string) ($tx->payment_method ?? ''), (string) ($tx->provider ?? '')) === self::PAYMENT_METHOD_MOLLIE) {
            $latestMollieStatus = $this->fetchMolliePaymentStatus((string) ($tx->provider_transaction_id ?? ''));
            if ($latestMollieStatus !== null) {
                $normalized = $this->normalizeMollieStatus($latestMollieStatus);
                if ($normalized !== (string) ($tx->status ?? '')) {
                    $txPaidAt = $normalized === 'paid' ? now() : null;
                    DB::table('gymies_payment_transactions')
                        ->where('id', (int) $tx->id)
                        ->update([
                            'status' => $normalized,
                            'paid_at' => $txPaidAt,
                            'updated_at' => now(),
                        ]);
                    if ($normalized === 'paid') {
                        DB::table('gymies_bookings')->where('id', (int) $bookingId)->update([
                            'paid_at' => now(),
                            'updated_at' => now(),
                        ]);
                    }
                    $tx->status = $normalized;
                    $tx->paid_at = $txPaidAt;
                }
            }
        }

        $bookingMethod = property_exists($booking, 'payment_method') ? (string) ($booking->payment_method ?? '') : '';
        $paymentMethod = $tx
            ? $this->storedPaymentMethodToCanonical((string) ($tx->payment_method ?? ''), (string) ($tx->provider ?? ''))
            : $this->storedPaymentMethodToCanonical($bookingMethod, '');

        $rawStatus = $tx ? (string) ($tx->status ?? 'pending') : (!empty($booking->paid_at) ? 'paid' : 'pending');
        $canonicalStatus = $this->canonicalPaymentStatus($rawStatus, $paymentMethod, (string) ($booking->status ?? ''));
        $paidAt = $tx && !empty($tx->paid_at) ? $tx->paid_at : ($booking->paid_at ?? null);
        $referenceId = $tx ? (string) ($tx->provider_transaction_id ?? '') : null;
        $amountCents = $tx ? (int) ($tx->amount_cents ?? 0) : (int) ($booking->amount_cents ?? 0);

        return response()->json([
            'data' => [
                'booking_id' => (string) $bookingId,
                'status' => $canonicalStatus,
                'payment_method' => $paymentMethod,
                'reference_id' => $referenceId !== '' ? $referenceId : null,
                'paid_at' => $paidAt,
                'amount_cents' => $amountCents,
                'currency' => 'EUR',
                'status_raw' => $rawStatus,
            ],
        ]);
    }

    /**
     * GET + POST op webhooks/mollie. GET = vriendelijke 200 (bijv. in browser). POST = echte webhook van Mollie.
     */
    public function mollieWebhookHandler(Request $request): JsonResponse
    {
        if ($request->isMethod('GET')) {
            return response()->json([
                'message' => 'Mollie webhook accepts POST only. Use POST for payment notifications.',
            ]);
        }
        return $this->mollieWebhook($request);
    }

    /**
     * Webhook voor Mollie: bij geslaagde betaling boeking op "Betaald" zetten.
     * Cruciaal als de klant het tabblad sluit vóór de return-URL (voorkomt dubbele betaling).
     * Mollie stuurt o.a. "id" (payment id) – wij zoeken op provider_transaction_id.
     * Altijd 200 retourneren zodat Mollie stopt met opnieuw proberen.
     */
    public function mollieWebhook(Request $request): JsonResponse
    {
        $paymentId = $request->input('id');
        if ($paymentId === null || $paymentId === '') {
            return response()->json(['received' => true]);
        }
        $paymentId = (string) $paymentId;

        // Basis-verificatie: Mollie stuurt altijd een 'id' in format tr_XXXXX.
        // Blokkeer duidelijk ongeldige ID's om fake webhook calls te stoppen.
        if (!preg_match('/^tr_[a-zA-Z0-9]{8,35}$/', $paymentId)) {
            if (function_exists('logger')) {
                logger()->warning('Gymies Mollie webhook: invalid payment ID format', ['id' => $paymentId, 'ip' => $request->ip()]);
            }
            return response()->json(['received' => true]);
        }

        $this->ensurePaymentTables();
        if (!$this->tableExists('gymies_payment_transactions')) {
            return response()->json(['received' => true]);
        }

        $mollieStatus = $this->fetchMolliePaymentStatus($paymentId);
        if ($mollieStatus === null) {
            return response()->json(['received' => true]);
        }
        $normalizedStatus = $this->normalizeMollieStatus($mollieStatus);

        if (!$this->registerWebhookEventIdempotent('mollie', $paymentId, $normalizedStatus, $request->all())) {
            return response()->json(['received' => true]);
        }

        DB::beginTransaction();
        try {
            $tx = DB::table('gymies_payment_transactions')
                ->where('provider_transaction_id', $paymentId)
                ->orderByDesc('id')
                ->lockForUpdate()
                ->first(['id', 'booking_id', 'group_participant_id', 'amount_cents', 'status']);
            if ($tx) {
                $paidAt = $normalizedStatus === 'paid' ? now() : null;
                DB::table('gymies_payment_transactions')
                    ->where('id', (int) $tx->id)
                    ->update([
                        'status' => $normalizedStatus,
                        'payment_method' => self::PAYMENT_METHOD_MOLLIE,
                        'paid_at' => $paidAt,
                        'updated_at' => now(),
                    ]);

                if ($tx->group_participant_id !== null && (int) $tx->group_participant_id > 0 && $this->tableExists('gymies_group_session_participants')) {
                    if ($normalizedStatus === 'paid') {
                        $participantUpdate = [
                            'status' => 'confirmed',
                            'paid_at' => now(),
                            'updated_at' => now(),
                        ];
                        if ((int) ($tx->amount_cents ?? 0) > 0 && $this->columnExists('gymies_group_session_participants', 'amount_cents')) {
                            $participantUpdate['amount_cents'] = (int) $tx->amount_cents;
                        }
                        DB::table('gymies_group_session_participants')
                            ->where('id', (int) $tx->group_participant_id)
                            ->update($participantUpdate);
                    }
                } elseif ($tx->booking_id !== null && (int) $tx->booking_id > 0 && $this->tableExists('gymies_bookings')) {
                    $booking = DB::table('gymies_bookings')
                        ->where('id', (int) $tx->booking_id)
                        ->lockForUpdate()
                        ->first(['id', 'status']);
                    if ($booking) {
                        $bookingUpdate = ['updated_at' => now()];
                        if ($normalizedStatus === 'paid') {
                            $bookingUpdate['paid_at'] = now();
                            if ((string) ($booking->status ?? '') === 'reserved') {
                                $bookingUpdate['status'] = 'confirmed';
                            }
                        } else {
                            $bookingUpdate['paid_at'] = null;
                            if ((string) ($booking->status ?? '') === 'reserved') {
                                $bookingUpdate['status'] = 'cancelled';
                            }
                        }
                        if ($this->columnExists('gymies_bookings', 'reserved_until')) {
                            $bookingUpdate['reserved_until'] = null;
                        }
                        DB::table('gymies_bookings')->where('id', (int) $tx->booking_id)->update($bookingUpdate);
                        if ($normalizedStatus === 'paid' && (string) ($booking->status ?? '') === 'reserved') {
                            $confirmedBooking = DB::table('gymies_bookings')->where('id', (int) $tx->booking_id)->first(['client_user_id', 'trainer_user_id', 'scheduled_at', 'confirmation_note']);
                            if ($confirmedBooking && class_exists(\App\Helpers\GymiesChatBroadcast::class)) {
                                $confNote = $this->columnExists('gymies_bookings', 'confirmation_note')
                                    ? ($confirmedBooking->confirmation_note ?? null)
                                    : null;
                                \App\Helpers\GymiesChatBroadcast::sendTrainerConfirmationToClient(
                                    (int) $confirmedBooking->client_user_id,
                                    (int) $confirmedBooking->trainer_user_id,
                                    (string) $confirmedBooking->scheduled_at,
                                    $confNote !== null && trim((string) $confNote) !== '' ? trim((string) $confNote) : null,
                                    (int) $tx->booking_id,
                                );
                            }
                        }
                    }
                }
            }
            DB::commit();

            // Ambassador conversie-tracking: als boeking betaald is en promo-code een ambassador-code was
            if ($normalizedStatus === 'paid' && $tx && $tx->booking_id !== null) {
                try {
                    $bookingForAmb = DB::table('gymies_bookings')
                        ->where('id', (int) $tx->booking_id)
                        ->first(['client_user_id', 'trainer_user_id']);
                    $txForAmb = DB::table('gymies_payment_transactions')
                        ->where('id', (int) $tx->id)
                        ->first(['promo_code_id']);

                    if ($bookingForAmb && $txForAmb && $txForAmb->promo_code_id) {
                        $promoRow = DB::table('gymies_promo_codes')
                            ->where('id', (int) $txForAmb->promo_code_id)
                            ->first(['code']);
                        if ($promoRow) {
                            GymiesAmbassadorController::recordSporterConversion(
                                (string) $promoRow->code,
                                (int) $bookingForAmb->client_user_id,
                                (int) $tx->id,
                                $request->ip(),
                                (int) $bookingForAmb->trainer_user_id
                            );
                        }
                    }
                } catch (\Throwable $ambEx) {
                    if (function_exists('logger')) {
                        logger()->warning('Gymies Mollie webhook: ambassador conversion failed', ['error' => $ambEx->getMessage()]);
                    }
                }
            }

            // Ambassador refund: als betaling is teruggedraaid (refunded/charged_back)
            if (in_array($normalizedStatus, ['refunded', 'charged_back'], true) && $tx) {
                try {
                    GymiesAmbassadorController::reverseConversion((int) $tx->id);
                } catch (\Throwable $revEx) {
                    if (function_exists('logger')) {
                        logger()->warning('Gymies Mollie webhook: ambassador reverse failed', ['error' => $revEx->getMessage()]);
                    }
                }
            }
        } catch (\Throwable $e) {
            DB::rollBack();
            if (function_exists('logger')) {
                logger()->error('Gymies Mollie webhook: failed to mark paid', ['id' => $paymentId, 'error' => $e->getMessage()]);
            }
        }

        return response()->json(['received' => true]);
    }

    /**
     * Valideer kortingscode voor een groepsles-inschrijving (voor tonen in UI vóór betalen).
     */
    public function validatePromoForGroupParticipant(Request $request, string $participantId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten kunnen een kortingscode gebruiken.'], 403);
        }

        $participant = DB::table('gymies_group_session_participants as p')
            ->join('gymies_group_sessions as g', 'p.group_session_id', '=', 'g.id')
            ->where('p.id', (int) $participantId)
            ->where('p.client_user_id', (int) $user->id)
            ->select(['p.amount_cents as p_amount', 'g.price_cents', 'g.trainer_user_id'])
            ->first();
        if (!$participant) {
            return response()->json(['message' => 'Inschrijving niet gevonden.'], 404);
        }

        $amountCents = (int) ($participant->p_amount ?? $participant->price_cents ?? 0);
        if ($amountCents <= 0) {
            $amountCents = (int) $participant->price_cents;
        }
        $code = trim((string) ($request->input('promo_code') ?? ''));
        if ($code === '') {
            return response()->json([
                'data' => ['valid' => false, 'message' => 'Voer een code in.'],
            ]);
        }

        $trainerUserId = (int) ($participant->trainer_user_id ?? 0);
        $result = $this->validateAndResolvePromo($code, $amountCents, $trainerUserId);
        return response()->json([
            'data' => [
                'valid' => $result['valid'],
                'message' => $result['message'],
                'discount_cents' => $result['valid'] ? $result['discount_cents'] : 0,
                'amount_after_discount' => $result['valid'] ? $result['amount_after_discount'] : $amountCents,
            ],
        ]);
    }

    /**
     * Start betaling voor een groepsles-inschrijving (klant, status payment_pending).
     * Optioneel: promo_code voor korting; amount_cents wordt dan het bedrag na korting.
     */
    public function startGroupParticipantPayment(Request $request, string $participantId): JsonResponse
    {
        $this->ensurePaymentTables();
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten kunnen betalen voor een groepsles-inschrijving.'], 403);
        }
        if (!$this->tableExists('gymies_group_session_participants')) {
            return response()->json(['message' => 'Inschrijving niet gevonden.'], 404);
        }

        $selectCols = ['p.*', 'g.title', 'g.price_cents', 'g.trainer_user_id', 'g.max_participants'];
        if (Schema::hasColumn('gymies_group_sessions', 'price_per_participant_cents')) {
            $selectCols[] = 'g.price_per_participant_cents';
        }
        $participant = DB::table('gymies_group_session_participants as p')
            ->join('gymies_group_sessions as g', 'p.group_session_id', '=', 'g.id')
            ->where('p.id', (int) $participantId)
            ->where('p.client_user_id', (int) $user->id)
            ->select($selectCols)
            ->first();
        if (!$participant) {
            return response()->json(['message' => 'Inschrijving niet gevonden.'], 404);
        }
        if (!in_array($participant->status, ['payment_pending', 'pending'], true)) {
            return response()->json(['message' => 'Deze inschrijving hoeft niet meer betaald te worden.'], 422);
        }
        if (!empty($participant->paid_at)) {
            return response()->json(['message' => 'Je hebt al betaald voor deze les.'], 422);
        }

        // Prijs per deelnemer: participant.amount_cents → session.price_per_participant_cents → session.price_cents
        $amountCents = (int) ($participant->amount_cents ?? 0);
        if ($amountCents <= 0 && property_exists($participant, 'price_per_participant_cents') && $participant->price_per_participant_cents !== null) {
            $amountCents = (int) $participant->price_per_participant_cents;
        }
        if ($amountCents <= 0) {
            $amountCents = (int) $participant->price_cents;
        }
        $promoCodeId = null;
        $discountAppliedCents = 0;
        $promoCode = trim((string) ($request->input('promo_code') ?? ''));
        if ($promoCode !== '' && $this->tableExists('gymies_promo_codes')) {
            $promoResult = $this->validateAndResolvePromo(
                $promoCode,
                $amountCents,
                (int) $participant->trainer_user_id
            );
            if ($promoResult['valid']) {
                $promoCodeId = $promoResult['promo_code_id'];
                $discountAppliedCents = $promoResult['discount_cents'];
                $amountCents = $promoResult['amount_after_discount'];
            }
        }
        if ($amountCents <= 0) {
            return response()->json(['message' => 'Geen bedrag bekend voor deze inschrijving.'], 422);
        }

        $returnUrl = trim((string) ($request->input('return_url') ?? ''));
        if ($returnUrl === '') {
            $returnUrl = rtrim($request->root(), '/') . '/betaling-terug?group_participant_id=' . $participantId;
        }

        $apiKey = $this->getMollieApiKey();
        if ($apiKey === '') {
            return response()->json([
                'message' => 'Mollie is niet geconfigureerd. Neem contact op met de trainer of probeer later opnieuw.',
            ], 503);
        }

        $trainerMollieProfileId = null;
        if ($this->columnExists('gymies_trainer_profiles', 'mollie_profile_id')) {
            $trainerMollieProfileId = DB::table('gymies_trainer_profiles')
                ->where('user_id', (int) $participant->trainer_user_id)
                ->value('mollie_profile_id');
        }
        $profileId = $trainerMollieProfileId ?: config('gymies.mollie_profile_id');

        // Bepaal totaal aantal deelnemers voor fee verdeling
        $groupTotalParticipants = (int) DB::table('gymies_group_session_participants')
            ->where('group_session_id', (int) $participant->group_session_id)
            ->whereIn('status', ['pending', 'registered', 'payment_pending', 'confirmed'])
            ->count();
        if ($groupTotalParticipants < 1) {
            $groupTotalParticipants = (int) ($participant->max_participants ?? 1);
        }

        $applicationFeeCents = $this->resolveApplicationFeeCents(
            (int) $participant->trainer_user_id,
            $amountCents,
            $groupTotalParticipants
        );

        $webhookUrl = rtrim($request->root(), '/') . '/api/gymies/webhooks/mollie';
        $createResult = $this->createMolliePaymentForGroupParticipant(
            $apiKey,
            $amountCents,
            (string) $participantId,
            $returnUrl,
            $webhookUrl,
            $profileId,
            $applicationFeeCents
        );
        if ($createResult === null) {
            return response()->json([
                'message' => 'Betaling kon niet worden gestart. Probeer het later opnieuw.',
            ], 502);
        }

        $providerTransactionId = (string) $createResult['id'];
        $paymentUrl = (string) $createResult['checkout_url'];

        // Promo code use_count incrementeren na succesvolle toepassing
        if ($promoCodeId !== null && $this->tableExists('gymies_promo_codes')) {
            DB::table('gymies_promo_codes')->where('id', $promoCodeId)->increment('use_count');
        }

        $this->ensurePaymentTables();
        if ($this->tableExists('gymies_payment_transactions')) {
            $insert = [
                'booking_id' => null,
                'group_participant_id' => (int) $participantId,
                'user_id' => (int) $user->id,
                'counterparty_user_id' => (int) $participant->trainer_user_id,
                'provider' => self::PROVIDER_MOLLIE,
                'provider_transaction_id' => $providerTransactionId,
                'amount_cents' => $amountCents,
                'status' => 'pending',
                'payment_method' => self::PAYMENT_METHOD_MOLLIE,
                'paid_at' => null,
                'created_at' => now(),
                'updated_at' => now(),
            ];
            if ($promoCodeId !== null && $this->columnExists('gymies_payment_transactions', 'promo_code_id')) {
                $insert['promo_code_id'] = $promoCodeId;
                $insert['discount_applied_cents'] = $discountAppliedCents;
            }
            DB::table('gymies_payment_transactions')->insert($insert);
        }

        return response()->json([
            'data' => [
                'redirect_url' => $paymentUrl,
                'amount_cents' => $amountCents,
            ],
        ]);
    }

    /**
     * Betalingsstatus groepsles-inschrijving.
     */
    public function groupParticipantPaymentStatus(Request $request, string $participantId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $participant = DB::table('gymies_group_session_participants')
            ->where('id', (int) $participantId)
            ->where('client_user_id', (int) $user->id)
            ->first(['id', 'status', 'paid_at', 'amount_cents']);
        if (!$participant) {
            return response()->json(['message' => 'Inschrijving niet gevonden.'], 404);
        }
        $status = !empty($participant->paid_at) ? 'paid' : 'pending';
        return response()->json([
            'data' => [
                'participant_id' => $participantId,
                'status' => $status,
                'paid_at' => $participant->paid_at,
                'amount_cents' => (int) ($participant->amount_cents ?? 0),
            ],
        ]);
    }

    private function normalizeIncomingPaymentMethod(string $method): string
    {
        $m = strtolower(trim($method));
        return match ($m) {
            'mollie', 'online', 'method_mollie', 'pay_mollie', 'mollie_connect' => self::PAYMENT_METHOD_MOLLIE,
            'cash', 'contant' => self::PAYMENT_METHOD_CASH,
            default => $m,
        };
    }

    private function storedPaymentMethodToCanonical(string $storedMethod, string $provider): string
    {
        $m = strtolower(trim($storedMethod));
        $p = strtolower(trim($provider));
        if ($m === self::PAYMENT_METHOD_CASH || $p === self::PROVIDER_CASH) {
            return self::PAYMENT_METHOD_CASH;
        }
        return self::PAYMENT_METHOD_MOLLIE;
    }

    private function canonicalPaymentStatus(string $rawStatus, string $paymentMethod, string $bookingStatus = ''): string
    {
        $raw = strtolower(trim($rawStatus));
        $booking = strtolower(trim($bookingStatus));

        if (in_array($raw, ['paid', 'mollie_paid', 'paid_mollie'], true)) {
            return 'paid';
        }
        if ($paymentMethod === self::PAYMENT_METHOD_CASH && in_array($raw, ['cash', 'paid_cash'], true)) {
            return 'cash';
        }
        if ($paymentMethod === self::PAYMENT_METHOD_CASH && $raw === 'paid') {
            return 'cash';
        }
        if (in_array($raw, ['cancelled', 'canceled', 'failed', 'expired'], true) || $booking === 'cancelled') {
            return 'cancelled';
        }
        if (in_array($raw, ['open', 'pending', 'unpaid', 'awaiting_cash'], true) || $raw === '') {
            return 'open';
        }

        return 'open';
    }

    private function fetchMolliePaymentStatus(string $paymentId): ?string
    {
        $paymentId = trim($paymentId);
        if ($paymentId === '') {
            return null;
        }
        $apiKey = $this->getMollieApiKey();
        if ($apiKey === '') {
            return null;
        }

        try {
            $response = Http::withToken($apiKey)
                ->timeout(10)
                ->get("https://api.mollie.com/v2/payments/{$paymentId}");
            if (!$response->successful()) {
                return null;
            }
            $status = $response->json('status');
            return is_string($status) ? $status : null;
        } catch (\Throwable $e) {
            return null;
        }
    }

    private function normalizeMollieStatus(string $mollieStatus): string
    {
        $status = strtolower(trim($mollieStatus));
        $normalized = match ($status) {
            'paid' => 'paid',
            'open', 'pending' => 'pending',
            'failed' => 'failed',
            'canceled', 'cancelled' => 'cancelled',
            'expired' => 'expired',
            'refunded' => 'refunded',
            'charged_back', 'chargedback' => 'charged_back',
            'authorized' => 'authorized',
            default => null,
        };
        if ($normalized === null) {
            \Log::warning('Onbekende Mollie status ontvangen, mapped naar pending', [
                'original_status' => $mollieStatus,
            ]);
            return 'pending';
        }
        return $normalized;
    }

    /**
     * Idempotentie op payment + status event.
     */
    private function registerWebhookEventIdempotent(string $provider, string $paymentId, string $status, array $payload): bool
    {
        if (!$this->tableExists('gymies_payment_webhook_events')) {
            return true;
        }
        $eventKey = strtolower(trim($provider)) . ':' . $paymentId . ':' . $status;
        $inserted = DB::table('gymies_payment_webhook_events')->insertOrIgnore([
            'provider' => strtolower(trim($provider)),
            'payment_id' => $paymentId,
            'event_key' => $eventKey,
            'status' => $status,
            'payload_json' => json_encode($payload, JSON_UNESCAPED_UNICODE),
            'created_at' => now(),
        ]);
        return (int) $inserted > 0;
    }

    private function ensurePaymentTables(): void
    {
        try {
            if (!$this->tableExists('gymies_payment_transactions')) {
                DB::statement("
                    CREATE TABLE IF NOT EXISTS gymies_payment_transactions (
                        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                        booking_id BIGINT UNSIGNED DEFAULT NULL,
                        group_participant_id BIGINT UNSIGNED DEFAULT NULL,
                        user_id BIGINT UNSIGNED DEFAULT NULL,
                        counterparty_user_id BIGINT UNSIGNED DEFAULT NULL,
                        provider VARCHAR(64) NOT NULL DEFAULT 'mollie',
                        provider_transaction_id VARCHAR(255) DEFAULT NULL,
                        amount_cents INT NOT NULL DEFAULT 0,
                        status VARCHAR(40) NOT NULL DEFAULT 'pending',
                        payment_method VARCHAR(64) DEFAULT NULL,
                        paid_at TIMESTAMP NULL DEFAULT NULL,
                        promo_code_id BIGINT UNSIGNED DEFAULT NULL,
                        discount_applied_cents INT UNSIGNED DEFAULT 0,
                        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                        PRIMARY KEY (id),
                        KEY gymies_payment_transactions_booking_idx (booking_id),
                        KEY gymies_payment_transactions_status_idx (status)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            }
            if ($this->tableExists('gymies_payment_transactions') && !$this->columnExists('gymies_payment_transactions', 'promo_code_id')) {
                DB::statement('ALTER TABLE gymies_payment_transactions ADD COLUMN promo_code_id BIGINT UNSIGNED DEFAULT NULL, ADD COLUMN discount_applied_cents INT UNSIGNED DEFAULT 0');
            }
            if ($this->tableExists('gymies_payment_transactions') && !$this->columnExists('gymies_payment_transactions', 'group_participant_id')) {
                DB::statement('ALTER TABLE gymies_payment_transactions ADD COLUMN group_participant_id BIGINT UNSIGNED DEFAULT NULL');
            }
            DB::statement("
                CREATE TABLE IF NOT EXISTS gymies_payment_webhook_events (
                    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    provider VARCHAR(64) NOT NULL,
                    payment_id VARCHAR(255) NOT NULL,
                    event_key VARCHAR(255) NOT NULL,
                    status VARCHAR(64) NOT NULL,
                    payload_json LONGTEXT NULL,
                    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY gymies_payment_webhook_events_event_key_unique (event_key),
                    KEY gymies_payment_webhook_events_payment_idx (payment_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            // Fail-open
        }
    }

    /**
     * GET promo/active — retourneert actieve promotie voor huidige gebruiker (indien aanwezig).
     */
    public function activePromo(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!$this->tableExists('gymies_promotions')) {
            return response()->json(['data' => null]);
        }
        $promo = DB::table('gymies_promotions')
            ->where('is_active', true)
            ->where(function ($q) {
                $q->whereNull('valid_until')->orWhere('valid_until', '>=', now());
            })
            ->orderByDesc('created_at')
            ->first();
        return response()->json(['data' => $promo]);
    }

    /**
     * POST promo/activate — activeer een promotie voor de huidige gebruiker.
     */
    public function activatePromo(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $promotionId = $request->input('promotion_id');
        $code = $request->input('code');
        $tier = $request->input('tier');
        if (!$promotionId && !$code) {
            return response()->json(['message' => 'promotion_id of code is verplicht.'], 422);
        }
        if (!$this->tableExists('gymies_promotions')) {
            return response()->json(['message' => 'Promoties niet beschikbaar.'], 404);
        }
        $query = DB::table('gymies_promotions')->where('is_active', true);
        if ($promotionId) {
            $query->where('id', $promotionId);
        } elseif ($code) {
            $query->where('code', $code);
        }
        $promo = $query->first();
        if (!$promo) {
            return response()->json(['message' => 'Promotie niet gevonden of niet actief.'], 404);
        }
        return response()->json(['data' => $promo, 'message' => 'Promotie geactiveerd.']);
    }
}
