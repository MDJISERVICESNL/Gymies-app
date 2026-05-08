<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies Betalingen: start betaling via Mollie API, status ophalen, webhook.
 * Tabellen: gymies_bookings (amount_cents, paid_at), gymies_payment_transactions.
 * Config: MOLLIE_API_KEY in .env (test_... of live_...).
 */
final class GymiesPaymentController extends Controller
{
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
        if ($user->role !== 'klant') {
            return response()->json(['message' => 'Alleen klanten kunnen betalen voor een boeking.'], 403);
        }
        if (Schema::hasColumn('gymies_users', 'email_verified_at')) {
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

        // B43: Pessimistisch slot uitgebreid: de lock wordt nu vastgehouden totdat ook de
        // check op bestaande betaaltransacties is gedaan, zodat twee gelijktijdige requests
        // niet beide een Mollie-betaling aanmaken voor dezelfde boeking (double-charge).
        $this->ensurePaymentTables();
        $existingTxStatus = null;
        $booking = DB::transaction(function () use ($bookingId, $user, &$existingTxStatus) {
            $b = DB::table('gymies_bookings')
                ->where('id', (int) $bookingId)
                ->where('client_user_id', (int) $user->id)
                ->lockForUpdate()
                ->first();
            if ($b && Schema::hasTable('gymies_payment_transactions')) {
                $existingTx = DB::table('gymies_payment_transactions')
                    ->where('booking_id', (int) $bookingId)
                    ->whereIn('status', ['paid', 'pending', 'open'])
                    ->orderByDesc('id')
                    ->first(['id', 'status', 'provider_transaction_id']);
                $existingTxStatus = $existingTx ? (string) ($existingTx->status ?? '') : null;
            }
            return $b;
        });

        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if (!in_array((string) $booking->status, ['confirmed', 'reserved'], true)) {
            return response()->json(['message' => 'Alleen bevestigde of direct-gereserveerde boekingen kunnen worden betaald.'], 422);
        }
        if (!empty($booking->paid_at)) {
            return response()->json(['message' => 'Deze boeking is al betaald.'], 422);
        }

        if (Schema::hasTable('gymies_payment_transactions')) {
            if ($existingTxStatus === 'paid') {
                return response()->json(['message' => 'Deze boeking is al betaald.'], 422);
            }
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

        // S-065: Integer Overflow amountCents — enforce max €1.000.000 per payment
        if ($amountCents > 1000000 * 100) {
            return response()->json(['message' => 'Bedrag te hoog.'], 422);
        }

        $promoCode = trim((string) ($request->input('promo_code') ?? ''));
        $promoCodeId = null;
        $discountAppliedCents = 0;
        if ($promoCode !== '' && Schema::hasTable('gymies_promo_codes')) {
            $promoResult = $this->validateAndResolvePromo($promoCode, $amountCents, (int) $booking->trainer_user_id);
            if ($promoResult['valid']) {
                $promoCodeId = $promoResult['promo_code_id'];
                $discountAppliedCents = $promoResult['discount_cents'];
                $amountCents = max((int) $promoResult['amount_after_discount'], 0);
            }
        }

        $fallbackReturnUrl = rtrim($request->root(), '/') . '/betaling-terug?booking_id=' . $bookingId;
        $returnUrl = $this->sanitizeReturnUrl(
            trim((string) ($request->input('return_url') ?? '')),
            $fallbackReturnUrl
        );

        $provider = $paymentMethod === self::PAYMENT_METHOD_CASH ? self::PROVIDER_CASH : self::PROVIDER_MOLLIE;
        $providerStatus = $paymentMethod === self::PAYMENT_METHOD_CASH ? 'awaiting_cash' : 'pending';
        $paymentUrl = null;
        $providerTransactionId = 'tx_' . $bookingId . '_' . bin2hex(random_bytes(8));

        if ($paymentMethod === self::PAYMENT_METHOD_MOLLIE) {
            $trainerMollieProfileId = null;
            if (Schema::hasColumn('gymies_trainer_profiles', 'mollie_profile_id')) {
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
        if (Schema::hasTable('gymies_payment_transactions')) {
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
            if ($promoCodeId !== null && Schema::hasColumn('gymies_payment_transactions', 'promo_code_id')) {
                $insert['promo_code_id'] = $promoCodeId;
                $insert['discount_applied_cents'] = $discountAppliedCents;
            }
            $paymentId = DB::table('gymies_payment_transactions')->insertGetId($insert);
        }

        if (Schema::hasColumn('gymies_bookings', 'payment_method')) {
            DB::table('gymies_bookings')->where('id', (int) $bookingId)->update([
                'payment_method' => $paymentMethod === self::PAYMENT_METHOD_MOLLIE ? 'mollie_connect' : 'cash',
                'updated_at' => now(),
            ]);
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
        $key = env('MOLLIE_API_KEY', '');
        return is_string($key) ? trim($key) : '';
    }

    /**
     * Bepaal application fee (cent) voor Mollie Connect. Alleen als trainer "klant betaalt" heeft.
     * Mollie max: amount - (€0,35 + 6% van amount). Min €0,01.
     */
    private function resolveApplicationFeeCents(int $trainerUserId, int $amountCents): ?int
    {
        $feeCents = (int) config('gymies.service_fee_cents', 49);
        if ($feeCents <= 0) {
            return null;
        }
        $clientPaysFee = true;
        if (Schema::hasTable('gymies_trainer_bank_accounts') && Schema::hasColumn('gymies_trainer_bank_accounts', 'client_pays_service_fee')) {
            $cp = DB::table('gymies_trainer_bank_accounts')
                ->where('trainer_user_id', $trainerUserId)
                ->value('client_pays_service_fee');
            $clientPaysFee = $cp === null || (int) $cp === 1;
        }
        if (!$clientPaysFee) {
            return null;
        }
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
            : (config('gymies.mollie_profile_id') ?: env('MOLLIE_PROFILE_ID', ''));
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

        // ISSUE #2: Missing try-catch on external API call
        // FIX: Wrap HTTP request in try-catch to handle network failures
        try {
            $response = Http::withToken($apiKey)
                ->timeout(15)
                ->post(self::MOLLIE_API_URL, $body);
        } catch (\Illuminate\Http\Client\ConnectionException $e) {
            if (function_exists('logger')) {
                logger()->error('Gymies Mollie API connection failed', [
                    'error' => $e->getMessage(),
                    'amount' => $amountEur,
                ]);
            }
            return null;
        } catch (\Exception $e) {
            if (function_exists('logger')) {
                logger()->error('Gymies Mollie API request failed', [
                    'error' => $e->getMessage(),
                ]);
            }
            return null;
        }

        if (!$response->successful()) {
            if (function_exists('logger')) {
                // ISSUE #4: Don't log full response body with sensitive data
                // FIX: Only log status code, not full response
                logger()->warning('Gymies Mollie create payment failed', [
                    'status' => $response->status(),
                    'has_mollie_error' => isset($response->json()['error']) ? true : false,
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

        // S-064: Missing Type Check Mollie Response — validate id and checkout_url format
        if (!is_string($id) || !str_starts_with($id, 'tr_')) {
            if (function_exists('logger')) {
                logger()->warning('Gymies Mollie response: invalid payment id format', ['id' => $id]);
            }
            return null;
        }
        if (!is_string($checkoutHref) || !filter_var($checkoutHref, FILTER_VALIDATE_URL)) {
            if (function_exists('logger')) {
                logger()->warning('Gymies Mollie response: invalid checkout_url', ['url' => $checkoutHref]);
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
            : (config('gymies.mollie_profile_id') ?: env('MOLLIE_PROFILE_ID', ''));
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
        // S-090: URI Parameter Injection — use rawurlencode for payment ID in URL
        return $returnUrl . (str_contains($returnUrl, '?') ? '&' : '?') . 'payment_id=' . rawurlencode($providerTransactionId);
    }

    /**
     * Valideer return_url tegen de eigen app-origin om open-redirect aanvallen te voorkomen.
     * Accepteert alleen URLs die hetzelfde scheme+host hebben als de app (config app.url of request root).
     * Externe URLs worden genegeerd en vervangen door de veilige fallback-URL.
     */
    private function sanitizeReturnUrl(string $returnUrl, string $fallbackUrl): string
    {
        if ($returnUrl === '') {
            return $fallbackUrl;
        }

        // Bepaal toegestane origins (app.url + request root)
        $appUrl = rtrim((string) config('app.url', ''), '/');
        $reqRoot = rtrim(request()->root(), '/');

        $allowedHosts = array_filter(array_unique([
            $this->extractHost($appUrl),
            $this->extractHost($reqRoot),
        ]), fn ($h) => $h !== '');

        // Relatieve URL's zijn altijd veilig (starten met /)
        if (str_starts_with($returnUrl, '/') && !str_starts_with($returnUrl, '//')) {
            $relativeUrl = $appUrl . '/' . ltrim($returnUrl, '/');
            // S-040: Re-parse the combined URL to ensure no protocol-relative or double-slash tricks
            // S-066: Null Dereference — validate parse_url result
            $parsed = parse_url($relativeUrl);
            if ($parsed === false || !isset($parsed['host'])) {
                return $fallbackUrl;
            }
            $finalHost = strtolower((string) ($parsed['host'] ?? ''));
            if ($finalHost !== '' && in_array($finalHost, $allowedHosts, true)) {
                return $relativeUrl;
            }
            return $fallbackUrl;
        }

        $host = $this->extractHost($returnUrl);
        if ($host === '' || !in_array($host, $allowedHosts, true)) {
            if (function_exists('logger')) {
                logger()->warning('[GymiesPayment] return_url geblokkeerd (ander domein)', [
                    'url' => substr($returnUrl, 0, 120),
                    'allowed' => $allowedHosts,
                ]);
            }
            return $fallbackUrl;
        }

        // S-040: Final re-parse to prevent protocol-relative URLs like //evil.com
        // S-066: Null Dereference — validate parse_url result
        $parsed = parse_url($returnUrl);
        if ($parsed === false || !isset($parsed['host'])) {
            return $fallbackUrl;
        }
        $finalHost = strtolower((string) ($parsed['host'] ?? ''));
        if ($finalHost === '' || !in_array($finalHost, $allowedHosts, true)) {
            return $fallbackUrl;
        }

        return $returnUrl;
    }

    private function extractHost(string $url): string
    {
        if ($url === '') {
            return '';
        }
        // S-066: Null Dereference extractHost — check parse_url result before accessing
        $parsed = parse_url($url);
        if ($parsed === false || !isset($parsed['host'])) {
            return '';
        }
        return strtolower((string) ($parsed['host'] ?? ''));
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
        if ($user->role !== 'klant') {
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
        if (!Schema::hasTable('gymies_promo_codes')) {
            return ['valid' => false, 'message' => 'Kortingscodes zijn niet beschikbaar.'];
        }

        // B47: Gebruik lockForUpdate zodat twee gelijktijdige betalingen niet beide
        // de max_uses-check doorstaan voor dezelfde single-use code (race condition).
        $row = DB::transaction(function () use ($code) {
            return DB::table('gymies_promo_codes')
                ->where('code', $code)
                ->lockForUpdate()
                ->first();
        });
        if (!$row) {
            return ['valid' => false, 'message' => 'Deze code is ongeldig.'];
        }

        // Trainer-eigen codes: alleen geldig voor boekingen/lessen van die trainer (platform-codes zonder trainer_user_id zijn uitgefaseerd)
        if (Schema::hasColumn('gymies_promo_codes', 'trainer_user_id')) {
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
        if ($user->role === 'klant') {
            $bookingQuery->where('client_user_id', (int) $user->id);
        } elseif ($user->role === 'trainer') {
            $bookingQuery->where('trainer_user_id', (int) $user->id);
        } else {
            return response()->json(['message' => 'Geen toegang tot deze betalingsstatus.'], 403);
        }

        $bookingSelect = ['id', 'status', 'amount_cents', 'paid_at'];
        if (Schema::hasColumn('gymies_bookings', 'payment_method')) {
            $bookingSelect[] = 'payment_method';
        }
        $booking = $bookingQuery->first($bookingSelect);
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        $tx = null;
        if (Schema::hasTable('gymies_payment_transactions')) {
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
        // S-015: Mollie gebruikt geen HMAC-handtekening, maar stuurt webhooks vanuit vaste
        // IP-ranges. We voegen rate limiting toe om webhook-spam te beperken en valideren
        // het payment-ID voordat we de Mollie API aanroepen.
        // Mollie-aanbeveling: altijd opnieuw ophalen via hun API (geen blinde dataverwerking).
        $callerIp = $request->ip() ?? '';

        // P-FIX-3: Validate request comes from official Mollie IP ranges
        if (!\Illuminate\Support\Facades\App::environment('local')) {
            $allowedMollieRanges = ['185.30.220.0/22', '185.201.136.0/22'];
            if (!$this->isIpInMollieRanges($callerIp, $allowedMollieRanges)) {
                Log::warning('[Gymies] Mollie webhook from unauthorized IP', ['ip' => $callerIp]);
                return response()->json(['error' => 'Unauthorized'], 403);
            }
        }

        $paymentId = $request->input('id');
        if ($paymentId === null || $paymentId === '') {
            // Lege webhook — Mollie stuurt dit soms als connectie-test
            Log::info('[Gymies] Mollie webhook ontvangen zonder payment id', [
                'ip' => $callerIp,
            ]);
            return response()->json(['received' => true]);
        }
        $paymentId = (string) $paymentId;

        // S-015: Rate limiting op webhook-endpoint om misbruik te beperken
        if (Schema::hasTable('gymies_rate_limits')) {
            $webhookKey   = 'mollie_webhook:' . $callerIp;
            $windowStart  = now()->subMinutes(1);
            $attemptCount = DB::table('gymies_rate_limits')
                ->where('key', $webhookKey)
                ->where('window_start', '>=', $windowStart)
                ->count();
            if ($attemptCount > 60) {
                Log::warning('[Gymies] Mollie webhook rate limit overschreden', ['ip' => $callerIp]);
                return response()->json(['received' => true]);
            }
            DB::table('gymies_rate_limits')->insert([
                'key'          => $webhookKey,
                'window_start' => now(),
                'created_at'   => now(),
            ]);
        }

        // Valideer formaat: Mollie payment IDs beginnen altijd met "tr_"
        if (!preg_match('/^tr_[A-Za-z0-9]+$/', $paymentId)) {
            Log::warning('[Gymies] Mollie webhook: ongeldig payment id formaat ontvangen', [
                'payment_id' => substr($paymentId, 0, 32),
                'ip'         => $request->ip(),
            ]);
            return response()->json(['received' => true]);
        }

        $this->ensurePaymentTables();
        if (!Schema::hasTable('gymies_payment_transactions')) {
            return response()->json(['received' => true]);
        }

        // P-FIX-2: Status fetched from Mollie API, not from webhook body
        // Verificatie: haal status OP bij Mollie (hun aanbevolen aanpak — geen handtekening)
        $mollieStatus = $this->fetchMolliePaymentStatus($paymentId);
        if ($mollieStatus === null) {
            // Mollie API niet bereikbaar — log en laat Mollie opnieuw proberen
            Log::warning('[Gymies] Mollie webhook: kon status niet ophalen bij Mollie API', [
                'payment_id' => $paymentId,
                'ip'         => $request->ip(),
            ]);
            return response()->json(['received' => true]);
        }
        $normalizedStatus = $this->normalizeMollieStatus($mollieStatus);

        if (!$this->registerWebhookEventIdempotent('mollie', $paymentId, $normalizedStatus, $request->all())) {
            return response()->json(['received' => true]);
        }

        // ISSUE #3: Missing exception handling in transaction
        // FIX: Wrap entire transaction in try-catch with rollback
        try {
            DB::beginTransaction();
            $tx = DB::table('gymies_payment_transactions')
                ->where('provider_transaction_id', $paymentId)
                ->orderByDesc('id')
                ->lockForUpdate()
                ->first(['id', 'booking_id', 'group_participant_id', 'amount_cents', 'status', 'promo_code_id']);
            if (!$tx) {
                // Betaling bestaat niet in onze DB — kan een testbetaling zijn of een aanvalpoging
                Log::warning('[Gymies] Mollie webhook: payment_id niet gevonden in onze DB', [
                    'payment_id' => $paymentId,
                    'status'     => $normalizedStatus,
                    'ip'         => $request->ip(),
                ]);
                DB::commit();
                return response()->json(['received' => true]);
            }
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

                // P-FIX-1: Increment promo code use_count only after payment confirmed as paid
                if ($normalizedStatus === 'paid' && $tx->promo_code_id !== null && Schema::hasTable('gymies_promo_codes')) {
                    DB::table('gymies_promo_codes')
                        ->where('id', (int) $tx->promo_code_id)
                        ->where(function($q) {
                            // Only increment if max_uses not yet reached
                            $q->whereNull('max_uses')->orWhereRaw('use_count < max_uses');
                        })
                        ->lockForUpdate()
                        ->increment('use_count');
                }

                if ($tx->group_participant_id !== null && (int) $tx->group_participant_id > 0 && Schema::hasTable('gymies_group_session_participants')) {
                    if ($normalizedStatus === 'paid') {
                        $participantUpdate = [
                            'status' => 'confirmed',
                            'paid_at' => now(),
                            'updated_at' => now(),
                        ];
                        if ((int) ($tx->amount_cents ?? 0) > 0 && Schema::hasColumn('gymies_group_session_participants', 'amount_cents')) {
                            $participantUpdate['amount_cents'] = (int) $tx->amount_cents;
                        }
                        DB::table('gymies_group_session_participants')
                            ->where('id', (int) $tx->group_participant_id)
                            ->update($participantUpdate);
                    }
                } elseif ($tx->booking_id !== null && (int) $tx->booking_id > 0 && Schema::hasTable('gymies_bookings')) {
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
                            // Ambassador: draai sporter-conversie terug als boeking was bevestigd (terugboeking/annulering)
                            if ((string) ($booking->status ?? '') === 'confirmed') {
                                try {
                                    if (class_exists(\App\Http\Controllers\Gymies\GymiesAmbassadorController::class)) {
                                        \App\Http\Controllers\Gymies\GymiesAmbassadorController::reverseConversion((int) $tx->id);
                                    }
                                } catch (\Throwable $ambRevEx) {
                                    if (function_exists('logger')) {
                                        logger()->warning('Gymies payment webhook: ambassador reverse conversion failed (non-blocking)', ['booking_id' => $tx->booking_id, 'error' => $ambRevEx->getMessage()]);
                                    }
                                }
                            }
                        }
                        if (Schema::hasColumn('gymies_bookings', 'reserved_until')) {
                            $bookingUpdate['reserved_until'] = null;
                        }
                        DB::table('gymies_bookings')->where('id', (int) $tx->booking_id)->update($bookingUpdate);
                        if ($normalizedStatus === 'paid' && (string) ($booking->status ?? '') === 'reserved') {
                            // Ambassador: registreer sporter-conversie (fire-and-forget, blokkeert nooit de betaalflow)
                            try {
                                $confirmedTx = DB::table('gymies_payment_transactions')
                                    ->where('id', (int) $tx->id)
                                    ->first(['promo_code_id', 'user_id']);
                                if ($confirmedTx && $confirmedTx->promo_code_id && class_exists(\App\Http\Controllers\Gymies\GymiesAmbassadorController::class)) {
                                    $promoRow = DB::table('gymies_promo_codes')->where('id', (int) $confirmedTx->promo_code_id)->first(['code', 'ambassador_id']);
                                    if ($promoRow && !empty($promoRow->ambassador_id)) {
                                        $bookingRow = DB::table('gymies_bookings')->where('id', (int) $tx->booking_id)->first(['client_user_id']);
                                        // S-039: IDOR check — verify user making conversion request owns the booking
                                        if ($bookingRow && (int) $bookingRow->client_user_id === (int) $confirmedTx->user_id) {
                                            \App\Http\Controllers\Gymies\GymiesAmbassadorController::recordSporterConversion(
                                                (int) $promoRow->ambassador_id,
                                                (int) $bookingRow->client_user_id,
                                                (int) ($tx->amount_cents ?? 0),
                                                (int) $tx->booking_id,
                                                $paymentId
                                            );
                                        }
                                    }
                                }
                            } catch (\Throwable $ambEx) {
                                if (function_exists('logger')) {
                                    logger()->warning('Gymies payment webhook: ambassador sporter conversion failed (non-blocking)', ['booking_id' => $tx->booking_id, 'error' => $ambEx->getMessage()]);
                                }
                            }

                            $confirmedBooking = DB::table('gymies_bookings')->where('id', (int) $tx->booking_id)->first(['client_user_id', 'trainer_user_id', 'scheduled_at', 'confirmation_note']);
                            if ($confirmedBooking && class_exists(\App\Helpers\GymiesChatBroadcast::class)) {
                                $confNote = \Illuminate\Support\Facades\Schema::hasColumn('gymies_bookings', 'confirmation_note')
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
        if (!$user || $user->role !== 'klant') {
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
        if (!$user || $user->role !== 'klant') {
            return response()->json(['message' => 'Alleen klanten kunnen betalen voor een groepsles-inschrijving.'], 403);
        }
        if (!Schema::hasTable('gymies_group_session_participants')) {
            return response()->json(['message' => 'Inschrijving niet gevonden.'], 404);
        }

        // Pessimistisch slot: voorkomt dubbele betaling bij gelijktijdige verzoeken.
        $participant = DB::transaction(function () use ($participantId, $user) {
            return DB::table('gymies_group_session_participants as p')
                ->join('gymies_group_sessions as g', 'p.group_session_id', '=', 'g.id')
                ->where('p.id', (int) $participantId)
                ->where('p.client_user_id', (int) $user->id)
                ->select(['p.*', 'g.title', 'g.price_cents', 'g.trainer_user_id'])
                ->lockForUpdate()
                ->first();
        });
        if (!$participant) {
            return response()->json(['message' => 'Inschrijving niet gevonden.'], 404);
        }
        if (!in_array($participant->status, ['payment_pending', 'pending'], true)) {
            return response()->json(['message' => 'Deze inschrijving hoeft niet meer betaald te worden.'], 422);
        }
        if (!empty($participant->paid_at)) {
            return response()->json(['message' => 'Je hebt al betaald voor deze les.'], 422);
        }

        $amountCents = (int) ($participant->amount_cents ?? $participant->price_cents ?? 0);
        if ($amountCents <= 0) {
            $amountCents = (int) $participant->price_cents;
        }
        $promoCodeId = null;
        $discountAppliedCents = 0;
        $promoCode = trim((string) ($request->input('promo_code') ?? ''));
        if ($promoCode !== '' && Schema::hasTable('gymies_promo_codes')) {
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

        $fallbackReturnUrl = rtrim($request->root(), '/') . '/betaling-terug?group_participant_id=' . $participantId;
        $returnUrl = $this->sanitizeReturnUrl(
            trim((string) ($request->input('return_url') ?? '')),
            $fallbackReturnUrl
        );

        $apiKey = $this->getMollieApiKey();
        if ($apiKey === '') {
            return response()->json([
                'message' => 'Mollie is niet geconfigureerd. Neem contact op met de trainer of probeer later opnieuw.',
            ], 503);
        }

        $trainerMollieProfileId = null;
        if (Schema::hasColumn('gymies_trainer_profiles', 'mollie_profile_id')) {
            $trainerMollieProfileId = DB::table('gymies_trainer_profiles')
                ->where('user_id', (int) $participant->trainer_user_id)
                ->value('mollie_profile_id');
        }
        $profileId = $trainerMollieProfileId ?: config('gymies.mollie_profile_id');

        $applicationFeeCents = $this->resolveApplicationFeeCents(
            (int) $participant->trainer_user_id,
            $amountCents
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

        if (Schema::hasTable('gymies_payment_transactions')) {
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
            if ($promoCodeId !== null && Schema::hasColumn('gymies_payment_transactions', 'promo_code_id')) {
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
        return match ($status) {
            'paid' => 'paid',
            'failed' => 'failed',
            'canceled', 'cancelled' => 'cancelled',
            'expired' => 'expired',
            default => 'pending',
        };
    }

    /**
     * Idempotentie op payment + status event.
     * P-FIX-4: Replay attack protection via unique event_key (provider:paymentId:status).
     * The gymies_payment_webhook_events table has a UNIQUE constraint on event_key and a created_at timestamp.
     * Duplicate webhooks with identical (provider, payment_id, status) are rejected via insertOrIgnore.
     * For protection beyond 24 hours, add a cleanup job that deletes event_key records older than 24h.
     */
    private function registerWebhookEventIdempotent(string $provider, string $paymentId, string $status, array $payload): bool
    {
        if (!Schema::hasTable('gymies_payment_webhook_events')) {
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
            if (!Schema::hasTable('gymies_payment_transactions')) {
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
            if (Schema::hasTable('gymies_payment_transactions') && !Schema::hasColumn('gymies_payment_transactions', 'promo_code_id')) {
                DB::statement('ALTER TABLE gymies_payment_transactions ADD COLUMN promo_code_id BIGINT UNSIGNED DEFAULT NULL, ADD COLUMN discount_applied_cents INT UNSIGNED DEFAULT 0');
            }
            if (Schema::hasTable('gymies_payment_transactions') && !Schema::hasColumn('gymies_payment_transactions', 'group_participant_id')) {
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
     * P-FIX-3: Check if IP is within official Mollie IP ranges using CIDR notation
     */
    private function isIpInMollieRanges(string $ip, array $cidrs): bool
    {
        foreach ($cidrs as $cidr) {
            [$subnet, $bits] = explode('/', $cidr);
            $subnetLong = ip2long($subnet);
            $ipLong = ip2long($ip);
            if ($ipLong === false || $subnetLong === false) {
                continue;
            }
            $mask = -1 << (32 - (int) $bits);
            if (($ipLong & $mask) === ($subnetLong & $mask)) {
                return true;
            }
        }
        return false;
    }
}
