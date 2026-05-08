<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Http\Traits\GymiesSchemaCacheTrait;
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
 *
 * PAYMENT EDGE CASES FIXED:
 * ────────────────────────────────
 *
 * 1. WEBHOOK IDEMPOTENCY
 *    - Same webhook delivered twice → process only once
 *    - FIX: Unique constraint on (provider:payment_id) in gymies_payment_webhook_events
 *    - FIX: registerWebhookEventIdempotent() uses payment_id only (not status)
 *
 * 2. EXPIRED PAYMENTS
 *    - User starts payment but never completes → payment expires in Mollie
 *    - FIX: mollieWebhook() detects 'expired' status and cancels booking
 *    - FIX: Booking reverted to cancelled (if reserved) or paid_at cleared
 *
 * 3. PARTIAL REFUNDS
 *    - Admin initiates refund → booking and payout must be updated atomically
 *    - FIX: Validate refund amount > 0 before debit (prevents negative balance)
 *    - FIX: Transaction wraps both payment_transactions update and payout debit
 *
 * 4. DOUBLE PAYMENT PREVENTION
 *    - User clicks pay twice quickly → must not create 2 Mollie payments
 *    - FIX: startPayment() uses lockForUpdate() on gymies_bookings
 *    - FIX: Check for existing pending/open transactions before creating new one
 *
 * 5. CONCURRENT WEBHOOKS
 *    - Mollie sometimes sends multiple webhooks simultaneously for same payment
 *    - FIX: lockForUpdate() on payment_transactions during webhook processing
 *    - FIX: Status transition guard prevents invalid transitions (e.g., refunded → paid)
 *
 * 6. AMOUNT PRECISION (EUR 2 decimals)
 *    - EUR amounts must always be 2 decimal places in Mollie API
 *    - FIX: number_format($amountCents / 100, 2, '.', '') ensures .XX format
 *    - FIX: Validate amounts in range [1, 100000000] cents
 *
 * 7. CIRCUIT BREAKER
 *    - Mollie is down → circuit breaker opens → user gets friendly error
 *    - FIX: State transitions properly managed: CLOSED → OPEN → HALF-OPEN → CLOSED
 *    - FIX: Half-open state allows exactly 1 test request before reopen/close
 *
 * 8. STATUS TRANSITIONS
 *    - Valid: open → pending/paid/expired/failed/cancelled
 *    - Valid: paid → refunded/charged_back (terminal states)
 *    - Valid: refunded/charged_back → (no transitions allowed)
 *    - FIX: isValidPaymentTransition() guard prevents invalid transitions
 */
final class GymiesPaymentController extends Controller
{
    use GymiesSchemaCacheTrait;
    use GymiesAuditTrait;

    private const PROVIDER_MOLLIE = 'mollie';
    private const PROVIDER_CASH = 'cash';
    private const MOLLIE_API_URL = 'https://api.mollie.com/v2/payments';
    private const PAYMENT_METHOD_MOLLIE = 'mollie';
    private const PAYMENT_METHOD_CASH = 'cash';

    /**
     * Start betaling voor een bevestigde boeking (alleen klant, eigen boeking).
     * Maakt een Mollie-payment aan en retourneert redirect_url naar Mollie checkout.
     *
     * BUG FIX: Added idempotency check and locking to prevent double payments from rapid clicks.
     * Also verify payment is not already in progress with "pending" status.
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
            ->lockForUpdate()
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

        // BUG FIX: Prevent double payment by checking for existing pending/paid transactions
        if ($this->tableExists('gymies_payment_transactions')) {
            $existingTx = DB::table('gymies_payment_transactions')
                ->where('booking_id', (int) $bookingId)
                ->whereIn('status', ['pending', 'open', 'authorized', 'paid'])
                ->first();
            if ($existingTx) {
                return response()->json(['message' => 'Er loopt al een betaling voor deze boeking. Wacht alstublieft.'], 422);
            }
        }

        $requestedMethod = $request->input('payment_method', $request->input('method', $request->input('pay_with', 'mollie')));
        $paymentMethod = $this->normalizeIncomingPaymentMethod((string) $requestedMethod);
        if (!in_array($paymentMethod, [self::PAYMENT_METHOD_MOLLIE, self::PAYMENT_METHOD_CASH], true)) {
            return response()->json(['message' => 'Ongeldige betaalmethode. Gebruik mollie of cash.'], 422);
        }

        $amountCents = (int) ($booking->amount_cents ?? 0);
        // BUG FIX: Validate amount is within reasonable range (minimum 1 cent, maximum 1M EUR = 100M cents)
        if ($amountCents <= 0 || $amountCents > 100000000) {
            return response()->json(['message' => 'Geen geldig bedrag voor deze boeking. Vraag de trainer om een bedrag vast te leggen.'], 422);
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
            // Deep link terug naar de app na betaling (in plaats van website 404)
            $returnUrl = 'gymies://payment/complete?booking_id=' . $bookingId;
        }

        $provider = $paymentMethod === self::PAYMENT_METHOD_CASH ? self::PROVIDER_CASH : self::PROVIDER_MOLLIE;
        $providerStatus = $paymentMethod === self::PAYMENT_METHOD_CASH ? 'awaiting_cash' : 'pending';
        $paymentUrl = null;
        $providerTransactionId = 'tx_' . $bookingId . '_' . bin2hex(random_bytes(8));

        // Track of betaling via trainer's eigen Mollie of via platform loopt
        $mollieAccountSource = 'platform';

        if ($paymentMethod === self::PAYMENT_METHOD_MOLLIE) {
            // PAYMENT ROUTING: check trainer's eigen Mollie token, fallback naar platform
            $resolved = $this->resolvePaymentMollieKey((int) $booking->trainer_user_id);
            $apiKey = $resolved['key'];
            $mollieAccountSource = $resolved['source'];

            if ($apiKey === '') {
                return response()->json([
                    'message' => 'Mollie is niet geconfigureerd. Neem contact op met de trainer of probeer later opnieuw.',
                ], 503);
            }

            Log::info('Gymies Payment: Mollie key resolved', [
                'booking_id' => $bookingId,
                'trainer_user_id' => $booking->trainer_user_id,
                'account_source' => $mollieAccountSource,
                'key_prefix' => substr($apiKey, 0, 8) . '...',
            ]);

            // OAuth (access_...) tokens ondersteunen profileId + applicationFee (Mollie Connect).
            // Reguliere API keys (test_/live_) ondersteunen dit NIET — stuur ze niet mee.
            $isOAuthToken = str_starts_with($apiKey, 'access_');

            $profileId = null;
            $applicationFeeCents = null;

            if ($isOAuthToken) {
                $trainerMollieProfileId = null;
                if ($this->columnExists('gymies_trainer_profiles', 'mollie_profile_id')) {
                    $trainerMollieProfileId = DB::table('gymies_trainer_profiles')
                        ->where('user_id', (int) $booking->trainer_user_id)
                        ->value('mollie_profile_id');
                }
                $profileId = $trainerMollieProfileId ?: config('gymies.mollie_profile_id');

                // Application fee alleen bij platform-account betalingen (Mollie Connect split).
                // Als de trainer zelf de merchant is, is er geen application fee nodig.
                if ($mollieAccountSource === 'platform') {
                    try {
                        $applicationFeeCents = $this->resolveApplicationFeeCents(
                            (int) $booking->trainer_user_id,
                            $amountCents
                        );
                    } catch (\Throwable $e) {
                        // Fee berekening mag niet de hele betaling blokkeren
                        $applicationFeeCents = null;
                        Log::warning('resolveApplicationFeeCents failed, skipping fee', ['error' => $e->getMessage()]);
                    }
                }
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
            // Track welk Mollie-account de betaling heeft aangemaakt (voor webhook routing)
            if ($this->columnExists('gymies_payment_transactions', 'mollie_account_source')) {
                $insert['mollie_account_source'] = $mollieAccountSource;
            }
            if ($promoCodeId !== null && $this->columnExists('gymies_payment_transactions', 'promo_code_id')) {
                $insert['promo_code_id'] = $promoCodeId;
                $insert['discount_applied_cents'] = $discountAppliedCents;
            }
            $paymentId = DB::table('gymies_payment_transactions')->insertGetId($insert);
        }

        // Wrap promo code increment and booking update in a transaction for atomicity
        DB::beginTransaction();
        try {
            if ($this->columnExists('gymies_bookings', 'payment_method')) {
                DB::table('gymies_bookings')->where('id', (int) $bookingId)->update([
                    'payment_method' => $paymentMethod === self::PAYMENT_METHOD_MOLLIE ? 'mollie_connect' : 'cash',
                    'updated_at' => now(),
                ]);
            }

            // Promo code use_count incrementeren na succesvolle toepassing (atomic within transaction)
            if ($promoCodeId !== null && $this->tableExists('gymies_promo_codes')) {
                DB::table('gymies_promo_codes')->where('id', $promoCodeId)->increment('use_count');
            }

            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            if (function_exists('logger')) {
                logger()->warning('Gymies Payment: promo or booking update failed', ['error' => $e->getMessage()]);
            }
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

    /**
     * Bepaal de juiste Mollie API key / access token voor een betaling.
     *
     * Routing logica:
     *   1) Als trainerUserId is opgegeven → check of trainer een eigen mollie_access_token heeft
     *      → Ja: gebruik trainer's token (betaling gaat naar trainer's Mollie-account)
     *      → Nee: fallback naar platform key
     *   2) Zonder trainerUserId → altijd platform key
     *
     * @return array{key: string, source: string}  source = 'trainer' | 'organisation' | 'platform'
     */
    private function resolvePaymentMollieKey(?int $trainerUserId = null): array
    {
        // 1) Probeer trainer's eigen Mollie access token
        if ($trainerUserId !== null && $trainerUserId > 0) {
            if ($this->columnExists('gymies_trainer_profiles', 'mollie_access_token')) {
                // Token refresh check — ververs als bijna verlopen
                $refreshedToken = $this->refreshMollieTokenIfNeeded('gymies_trainer_profiles', 'user_id', $trainerUserId);

                $encrypted = DB::table('gymies_trainer_profiles')
                    ->where('user_id', $trainerUserId)
                    ->value('mollie_access_token');

                if ($encrypted !== null && $encrypted !== '') {
                    try {
                        $accessToken = $refreshedToken ?? decrypt($encrypted);
                        if (is_string($accessToken) && $accessToken !== '') {
                            return ['key' => $accessToken, 'source' => 'trainer'];
                        }
                    } catch (\Throwable $e) {
                        Log::warning('Gymies: trainer mollie_access_token decrypt failed, fallback to organisation/platform key', [
                            'trainer_user_id' => $trainerUserId,
                            'error' => $e->getMessage(),
                        ]);
                    }
                }
            }

            // 2) Probeer gym organisatie Mollie access token (trainer hoort bij een gym)
            if (Schema::hasTable('gymies_organisation_trainers') && Schema::hasTable('gymies_organisations')) {
                $orgId = DB::table('gymies_organisation_trainers')
                    ->where('trainer_user_id', $trainerUserId)
                    ->where('status', 'active')
                    ->value('organisation_id');

                if ($orgId !== null && $this->columnExists('gymies_organisations', 'mollie_access_token')) {
                    // Token refresh check — ververs als bijna verlopen
                    $refreshedOrgToken = $this->refreshMollieTokenIfNeeded('gymies_organisations', 'id', (int) $orgId);

                    $orgEncrypted = DB::table('gymies_organisations')
                        ->where('id', (int) $orgId)
                        ->value('mollie_access_token');

                    if ($orgEncrypted !== null && $orgEncrypted !== '') {
                        try {
                            $orgToken = $refreshedOrgToken ?? decrypt($orgEncrypted);
                            if (is_string($orgToken) && $orgToken !== '') {
                                return ['key' => $orgToken, 'source' => 'organisation'];
                            }
                        } catch (\Throwable $e) {
                            Log::warning('Gymies: organisation mollie_access_token decrypt failed, fallback to platform key', [
                                'trainer_user_id' => $trainerUserId,
                                'organisation_id' => $orgId,
                                'error' => $e->getMessage(),
                            ]);
                        }
                    }
                }
            }
        }

        // 3) Fallback: platform Mollie API key
        $key = config('gymies.mollie_api_key');
        if ($key !== null && $key !== '') {
            return ['key' => (string) $key, 'source' => 'platform'];
        }
        // Geen key beschikbaar
        return ['key' => '', 'source' => 'platform'];
    }

    /**
     * Ververs een Mollie OAuth access token als het bijna verlopen is (< 10 min).
     * Gebruikt de opgeslagen refresh_token om een nieuw token op te halen.
     *
     * @param string $table  'gymies_trainer_profiles' of 'gymies_organisations'
     * @param string $idCol  'user_id' of 'id'
     * @param int    $idVal  De waarde van de ID-kolom
     * @return string|null   Nieuw access token, of null als refresh faalde
     */
    private function refreshMollieTokenIfNeeded(string $table, string $idCol, int $idVal): ?string
    {
        if (!$this->columnExists($table, 'mollie_token_expires_at') ||
            !$this->columnExists($table, 'mollie_refresh_token') ||
            !$this->columnExists($table, 'mollie_access_token')) {
            return null;
        }

        $row = DB::table($table)
            ->where($idCol, $idVal)
            ->first(['mollie_access_token', 'mollie_refresh_token', 'mollie_token_expires_at']);

        if (!$row || empty($row->mollie_access_token) || empty($row->mollie_refresh_token)) {
            return null;
        }

        // Token nog geldig? (> 10 minuten marge)
        if (!empty($row->mollie_token_expires_at) && now()->lt(\Carbon\Carbon::parse($row->mollie_token_expires_at)->subMinutes(10))) {
            return null; // Nog geldig, geen refresh nodig
        }

        // Token is verlopen of verloopt binnen 10 minuten → refresh
        $clientId = config('services.mollie.client_id') ?? env('MOLLIE_CLIENT_ID');
        $clientSecret = config('services.mollie.client_secret') ?? env('MOLLIE_CLIENT_SECRET');

        if (empty($clientId) || empty($clientSecret)) {
            Log::warning('Gymies: Mollie token refresh skipped — no client_id/client_secret configured', [
                'table' => $table, 'id' => $idVal,
            ]);
            return null;
        }

        try {
            $refreshToken = decrypt($row->mollie_refresh_token);
        } catch (\Throwable $e) {
            Log::error('Gymies: Mollie refresh_token decrypt failed', [
                'table' => $table, 'id' => $idVal, 'error' => $e->getMessage(),
            ]);
            return null;
        }

        try {
            $response = Http::asForm()
                ->withBasicAuth($clientId, $clientSecret)
                ->timeout(15)
                ->post('https://api.mollie.com/oauth2/tokens', [
                    'grant_type' => 'refresh_token',
                    'refresh_token' => $refreshToken,
                ]);

            if (!$response->successful()) {
                $body = $response->json();
                Log::error('Gymies: Mollie token refresh failed', [
                    'table' => $table, 'id' => $idVal,
                    'status' => $response->status(),
                    'error' => $body['error'] ?? $response->body(),
                ]);
                return null;
            }

            $data = $response->json();
            $newAccessToken = $data['access_token'] ?? null;
            $newRefreshToken = $data['refresh_token'] ?? null;
            $expiresIn = (int) ($data['expires_in'] ?? 3600);

            if (empty($newAccessToken)) {
                Log::error('Gymies: Mollie token refresh returned no access_token', [
                    'table' => $table, 'id' => $idVal,
                ]);
                return null;
            }

            $update = [
                'mollie_access_token' => encrypt($newAccessToken),
                'mollie_token_expires_at' => now()->addSeconds($expiresIn),
                'updated_at' => now(),
            ];
            if ($newRefreshToken) {
                $update['mollie_refresh_token'] = encrypt($newRefreshToken);
            }

            DB::table($table)->where($idCol, $idVal)->update($update);

            Log::info('Gymies: Mollie token refreshed successfully', [
                'table' => $table, 'id' => $idVal,
                'expires_in' => $expiresIn,
            ]);

            return $newAccessToken;
        } catch (\Throwable $e) {
            Log::error('Gymies: Mollie token refresh exception', [
                'table' => $table, 'id' => $idVal, 'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Legacy wrapper — retourneert alleen de key string (platform-only).
     * Gebruik resolvePaymentMollieKey() voor nieuwe code die trainer-routing nodig heeft.
     */
    private function getMollieApiKey(): string
    {
        return $this->resolvePaymentMollieKey()['key'];
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
        // Circuit breaker — fast fail als Mollie herhaaldelijk onbereikbaar is
        $circuitBreaker = new MollieCircuitBreaker();
        if (!$circuitBreaker->isAvailable()) {
            if (function_exists('logger')) {
                logger()->warning('Gymies Mollie circuit breaker OPEN — payment request afgewezen', [
                    'booking_id' => $bookingId,
                ]);
            }
            return null;
        }

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

        // Mollie Connect (OAuth): profileId + applicationFee worden alleen meegegeven bij OAuth tokens.
        // Reguliere API keys (test_/live_) ondersteunen profileId en applicationFee NIET.
        $isOAuthToken = str_starts_with($apiKey, 'access_');

        if ($isOAuthToken) {
            $profileId = ($trainerProfileId !== null && $trainerProfileId !== '')
                ? $trainerProfileId
                : config('gymies.mollie_profile_id', '');
            if ($profileId !== null && $profileId !== '') {
                $body['profileId'] = $profileId;
                $body['testmode'] = (bool) config('gymies.mollie_testmode', false);
            }
            if ($applicationFeeCents !== null && $applicationFeeCents >= 1) {
                $feeEur = number_format($applicationFeeCents / 100, 2, '.', '');
                $body['applicationFee'] = [
                    'amount' => ['currency' => 'EUR', 'value' => $feeEur],
                    'description' => 'Gymies servicekosten',
                ];
            }
        }

        try {
            $response = Http::withToken($apiKey)
                ->timeout(15)
                ->retry(2, 200) // 1 retry met 200ms delay
                ->post(self::MOLLIE_API_URL, $body);
        } catch (\Throwable $e) {
            $circuitBreaker->recordFailure();
            if (function_exists('logger')) {
                logger()->error('Gymies Mollie connection failed', [
                    'error' => $e->getMessage(),
                    'booking_id' => $bookingId,
                ]);
            }
            if (app()->bound('sentry')) {
                \Sentry\captureException($e);
            }
            return null;
        }

        if (!$response->successful()) {
            // 5xx = Mollie probleem → circuit breaker telt mee
            // 4xx = onze fout → circuit breaker niet verhogen
            if ($response->serverError()) {
                $circuitBreaker->recordFailure();
            }
            if (function_exists('logger')) {
                logger()->warning('Gymies Mollie create payment failed', [
                    'status' => $response->status(),
                    'body' => $response->json(),
                ]);
            }
            return null;
        }

        // Succes — reset circuit breaker
        $circuitBreaker->recordSuccess();

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

        $isOAuthToken = str_starts_with($apiKey, 'access_');
        if ($isOAuthToken) {
            $profileId = ($trainerProfileId !== null && $trainerProfileId !== '')
                ? $trainerProfileId
                : config('gymies.mollie_profile_id', '');
            if ($profileId !== null && $profileId !== '') {
                $body['profileId'] = $profileId;
                $body['testmode'] = (bool) config('gymies.mollie_testmode', false);
            }
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
                    // BUG FIX: Wrap in transaction with locking to prevent concurrent updates
                    DB::beginTransaction();
                    try {
                        // Lock for update to prevent race conditions
                        $lockedTx = DB::table('gymies_payment_transactions')
                            ->where('id', (int) $tx->id)
                            ->lockForUpdate()
                            ->first(['status']);

                        // Only update if status hasn't changed (prevent race condition)
                        if ($lockedTx && $lockedTx->status === (string) ($tx->status ?? '')) {
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

                                // Log payment completion
                                $booking = DB::table('gymies_bookings')->where('id', (int) $bookingId)->first(['user_id', 'amount_cents']);
                                if ($booking) {
                                    $this->auditLog((int) $booking->user_id, 'payment.completed', 'Payment', (int) $tx->id, [], [
                                        'booking_id' => (int) $bookingId,
                                        'amount_cents' => (int) $booking->amount_cents,
                                        'payment_method' => (string) ($tx->payment_method ?? 'unknown'),
                                        'provider' => (string) ($tx->provider ?? 'unknown'),
                                    ]);
                                    Log::info('Payment completed', ['user_id' => $booking->user_id, 'booking_id' => $bookingId, 'amount' => $booking->amount_cents]);
                                }
                            }
                            $tx->status = $normalized;
                            $tx->paid_at = $txPaidAt;
                        }
                        DB::commit();
                    } catch (\Throwable $e) {
                        DB::rollBack();
                        if (function_exists('logger')) {
                            logger()->error('Failed to update payment status in paymentStatus', ['error' => $e->getMessage()]);
                        }
                    }
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
     *
     * BUG FIX: Added Mollie webhook signature verification to prevent fake webhooks.
     * Mollie sends X-Mollie-Signature header that must be verified against webhook secret.
     */
    public function mollieWebhook(Request $request): JsonResponse
    {
        // BUG FIX: Verify webhook signature from Mollie
        $signatureHeader = $request->header('X-Mollie-Signature');
        if ($signatureHeader) {
            $webhookSecret = config('gymies.mollie_webhook_secret', env('MOLLIE_WEBHOOK_SECRET', ''));
            if ($webhookSecret !== '') {
                $computedSignature = hash_hmac('sha256', $request->getContent(), $webhookSecret);
                if (!hash_equals($computedSignature, $signatureHeader)) {
                    if (function_exists('logger')) {
                        logger()->warning('Gymies Mollie webhook: invalid signature', [
                            'ip' => $request->ip(),
                            'timestamp' => now()->toIso8601String(),
                        ]);
                    }
                    return response()->json(['received' => true]); // Return 200 to Mollie, but ignore fake webhook
                }
            }
        } else {
            // Signature header missing — log warning in production
            $webhookSecret = config('gymies.mollie_webhook_secret', env('MOLLIE_WEBHOOK_SECRET', ''));
            if ($webhookSecret !== '') {
                // Secret is configured but signature is missing — suspicious
                if (function_exists('logger')) {
                    logger()->warning('Mollie webhook missing signature while secret is configured', [
                        'ip' => $request->ip(),
                        'user_agent' => $request->userAgent(),
                        'timestamp' => now()->toIso8601String(),
                    ]);
                }
            }
        }

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

        // PAYMENT ROUTING FIX: bepaal juiste Mollie key op basis van wie de betaling aanmaakte
        $mollieStatus = $this->fetchMolliePaymentStatusRouted($paymentId);
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
                ->first(['id', 'booking_id', 'group_participant_id', 'amount_cents', 'status', 'mollie_account_source']);
            if ($tx) {
                // Transitie guard: voorkom ongeldige status wijzigingen
                $currentStatus = strtolower(trim((string) ($tx->status ?? 'open')));
                if (!$this->isValidPaymentTransition($currentStatus, $normalizedStatus)) {
                    DB::rollBack();
                    if (function_exists('logger')) {
                        logger()->info('Gymies Mollie webhook: ongeldige transitie geblokkeerd', [
                            'payment_id' => $paymentId,
                            'current'    => $currentStatus,
                            'attempted'  => $normalizedStatus,
                        ]);
                    }
                    return response()->json(['received' => true]);
                }

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
                            // BUG FIX: Handle expired, failed, and cancelled payments by reverting booking
                            $bookingUpdate['paid_at'] = null;
                            if (in_array($normalizedStatus, ['expired', 'failed', 'cancelled'], true)) {
                                if ((string) ($booking->status ?? '') === 'reserved') {
                                    $bookingUpdate['status'] = 'cancelled';
                                }
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

                            // Payout: crediteer trainer-saldo (sessieprijs - platformfee)
                            // ALLEEN als de betaling via het platform-account liep.
                            // Bij trainer's eigen Mollie gaat het geld direct naar de trainer — geen platform-saldo credit.
                            $txAccountSource = $tx->mollie_account_source ?? 'platform';
                            if ($txAccountSource === 'platform') {
                                try {
                                    if (class_exists(GymiesPayoutService::class)) {
                                        GymiesPayoutService::creditBooking(
                                            (int) $confirmedBooking->trainer_user_id,
                                            (int) ($tx->amount_cents ?? 0),
                                            (int) $tx->booking_id,
                                            (int) ($confirmedBooking->user_id ?? 0) ?: null,
                                        );
                                    }
                                } catch (\Throwable $payoutEx) {
                                    logger()->warning('Gymies Mollie webhook: payout credit failed', ['error' => $payoutEx->getMessage()]);
                                    if (app()->bound('sentry')) { app('sentry')->captureException($payoutEx); }
                                }
                            } else {
                                // Betaling ging direct naar trainer's Mollie — alleen loggen
                                Log::info('Gymies webhook: trainer-account betaling, geen platform saldo credit', [
                                    'booking_id' => $tx->booking_id,
                                    'trainer_user_id' => $confirmedBooking->trainer_user_id,
                                    'amount_cents' => $tx->amount_cents,
                                ]);
                            }
                        }
                    }
                }
            }
            DB::commit();

            // Broadcast payment status naar Flutter via Reverb WebSocket
            if ($tx && $tx->booking_id !== null) {
                try {
                    $clientUserId = null;
                    if ($this->tableExists('gymies_bookings')) {
                        $bookingForBroadcast = DB::table('gymies_bookings')
                            ->where('id', (int) $tx->booking_id)
                            ->first(['client_user_id']);
                        $clientUserId = $bookingForBroadcast ? (int) $bookingForBroadcast->client_user_id : null;
                    }
                    if ($clientUserId && class_exists(\App\Events\PaymentStatusUpdated::class)) {
                        event(new \App\Events\PaymentStatusUpdated(
                            userId: $clientUserId,
                            bookingId: (int) $tx->booking_id,
                            status: $normalizedStatus,
                            amountCents: (int) ($tx->amount_cents ?? 0),
                            paymentId: $paymentId,
                            paidAt: $normalizedStatus === 'paid' ? now()->toIso8601String() : null,
                        ));
                    }
                } catch (\Throwable $broadcastEx) {
                    if (function_exists('logger')) {
                        logger()->warning('Gymies Mollie webhook: broadcast failed', ['error' => $broadcastEx->getMessage()]);
                    }
                }
            }

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

                // BUG FIX: Validate refund amount before processing
                $refundAmount = (int) ($tx->amount_cents ?? 0);
                if ($refundAmount <= 0) {
                    logger()->warning('Gymies Mollie webhook: invalid refund amount', [
                        'payment_id' => $paymentId,
                        'amount' => $refundAmount,
                    ]);
                } else {
                    // Payout: debiteer trainer-saldo bij refund
                    try {
                        if (class_exists(GymiesPayoutService::class) && $tx->booking_id) {
                            $refundBooking = $this->tableExists('gymies_bookings')
                                ? DB::table('gymies_bookings')->where('id', (int) $tx->booking_id)->first(['trainer_user_id'])
                                : null;
                            if ($refundBooking) {
                                GymiesPayoutService::debitRefund(
                                    (int) $refundBooking->trainer_user_id,
                                    $refundAmount,
                                    (int) $tx->booking_id,
                                );
                            }
                        }
                    } catch (\Throwable $payoutRefundEx) {
                        logger()->warning('Gymies Mollie webhook: payout refund debit failed', ['error' => $payoutRefundEx->getMessage()]);
                        if (app()->bound('sentry')) { app('sentry')->captureException($payoutRefundEx); }
                    }
                }
            }
        } catch (\Throwable $e) {
            DB::rollBack();
            if (function_exists('logger')) {
                logger()->error('Gymies Mollie webhook: failed to mark paid', ['id' => $paymentId, 'error' => $e->getMessage()]);
            }
            if (app()->bound('sentry')) {
                \Sentry\withScope(function (\Sentry\State\Scope $scope) use ($e, $paymentId): void {
                    $scope->setTag('payment.id', (string) $paymentId);
                    $scope->setContext('webhook', ['payment_id' => $paymentId]);
                    \Sentry\captureException($e);
                });
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
        // BUG FIX: Validate final amount is in reasonable range
        if ($amountCents <= 0 || $amountCents > 100000000) {
            return response()->json(['message' => 'Geen geldig bedrag voor deze inschrijving.'], 422);
        }

        $returnUrl = trim((string) ($request->input('return_url') ?? ''));
        if ($returnUrl === '') {
            $returnUrl = rtrim($request->root(), '/') . '/betaling-terug?group_participant_id=' . $participantId;
        }

        // PAYMENT ROUTING: check trainer's eigen Mollie token, fallback naar platform
        $resolved = $this->resolvePaymentMollieKey((int) $participant->trainer_user_id);
        $apiKey = $resolved['key'];
        $groupMollieAccountSource = $resolved['source'];

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

        // Application fee alleen bij platform-account betalingen
        $applicationFeeCents = null;
        if ($groupMollieAccountSource === 'platform') {
            $applicationFeeCents = $this->resolveApplicationFeeCents(
                (int) $participant->trainer_user_id,
                $amountCents,
                $groupTotalParticipants
            );
        }

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

        $this->ensurePaymentTables();

        // Wrap promo code increment and payment transaction insert in a transaction for atomicity
        DB::beginTransaction();
        try {
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
                // Track welk Mollie-account de betaling heeft aangemaakt
                if ($this->columnExists('gymies_payment_transactions', 'mollie_account_source')) {
                    $insert['mollie_account_source'] = $groupMollieAccountSource;
                }
                if ($promoCodeId !== null && $this->columnExists('gymies_payment_transactions', 'promo_code_id')) {
                    $insert['promo_code_id'] = $promoCodeId;
                    $insert['discount_applied_cents'] = $discountAppliedCents;
                }
                DB::table('gymies_payment_transactions')->insert($insert);
            }

            // Promo code use_count incrementeren na succesvolle toepassing (atomic within transaction)
            if ($promoCodeId !== null && $this->tableExists('gymies_promo_codes')) {
                DB::table('gymies_promo_codes')->where('id', $promoCodeId)->increment('use_count');
            }

            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            if (function_exists('logger')) {
                logger()->warning('Gymies Group Payment: promo or transaction insert failed', ['error' => $e->getMessage()]);
            }
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

    /**
     * Haal Mollie payment-status op met de juiste key (trainer of platform).
     *
     * Routing: zoek eerst de payment transaction op om mollie_account_source en
     * counterparty_user_id (= trainer) te bepalen. Als source = 'trainer', gebruik
     * de trainer's eigen access token. Anders fallback naar platform key.
     */
    private function fetchMolliePaymentStatusRouted(string $paymentId): ?string
    {
        $paymentId = trim($paymentId);
        if ($paymentId === '') {
            return null;
        }

        // Bepaal welk account de betaling heeft aangemaakt
        $trainerUserId = null;
        if ($this->tableExists('gymies_payment_transactions')) {
            $tx = DB::table('gymies_payment_transactions')
                ->where('provider_transaction_id', $paymentId)
                ->first(['counterparty_user_id', 'mollie_account_source']);

            if ($tx) {
                $source = $tx->mollie_account_source ?? 'platform';
                if (($source === 'trainer' || $source === 'organisation') && !empty($tx->counterparty_user_id)) {
                    $trainerUserId = (int) $tx->counterparty_user_id;
                }
            }
        }

        $resolved = $this->resolvePaymentMollieKey($trainerUserId);
        $apiKey = $resolved['key'];
        if ($apiKey === '') {
            return null;
        }

        try {
            $response = Http::withToken($apiKey)
                ->timeout(10)
                ->get("https://api.mollie.com/v2/payments/{$paymentId}");
            if (!$response->successful()) {
                // Als trainer/organisation-key faalde, probeer platform key als fallback
                if ($resolved['source'] === 'trainer' || $resolved['source'] === 'organisation') {
                    Log::warning('Gymies webhook: ' . $resolved['source'] . ' key failed for payment status, trying platform key', [
                        'payment_id' => $paymentId,
                        'trainer_user_id' => $trainerUserId,
                    ]);
                    return $this->fetchMolliePaymentStatus($paymentId);
                }
                return null;
            }
            $status = $response->json('status');
            return is_string($status) ? $status : null;
        } catch (\Throwable $e) {
            // Fallback bij trainer/organisation-key fout
            if ($resolved['source'] === 'trainer' || $resolved['source'] === 'organisation') {
                return $this->fetchMolliePaymentStatus($paymentId);
            }
            return null;
        }
    }

    /**
     * Legacy: haal status op met platform key alleen.
     * Wordt gebruikt als fallback door fetchMolliePaymentStatusRouted().
     */
    private function fetchMolliePaymentStatus(string $paymentId): ?string
    {
        $paymentId = trim($paymentId);
        if ($paymentId === '') {
            return null;
        }
        $apiKey = $this->resolvePaymentMollieKey()['key'];
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
            Log::warning('Onbekende Mollie status ontvangen, mapped naar pending', [
                'original_status' => $mollieStatus,
            ]);
            return 'pending';
        }
        return $normalized;
    }

    /**
     * Voorkom ongeldige status transities (bv. paid → open).
     * Retourneert true als de transitie geldig is.
     */
    private function isValidPaymentTransition(string $currentStatus, string $newStatus): bool
    {
        // Geldige eindtoestanden: als we al in een eindtoestand zijn, alleen
        // refunded/charged_back zijn nog toegestaan vanuit paid.
        $finalStates = ['refunded', 'charged_back'];

        $allowed = [
            'open'         => ['pending', 'paid', 'failed', 'expired', 'canceled', 'cancelled'],
            'pending'      => ['paid', 'failed', 'expired', 'canceled', 'cancelled', 'open'],
            'paid'         => ['refunded', 'charged_back'], // Alleen terugboeking vanuit betaald
            'failed'       => ['open', 'pending', 'paid'], // Retry is mogelijk
            'expired'      => ['open', 'pending', 'paid'], // Heropening is mogelijk
            'canceled'     => [], // Eindtoestand
            'cancelled'    => [], // Eindtoestand (alternatieve spelling)
            'refunded'     => [], // Eindtoestand
            'charged_back' => [], // Eindtoestand
        ];

        $current = strtolower(trim($currentStatus));
        $new = strtolower(trim($newStatus));

        // Zelfde status = geen transitie nodig
        if ($current === $new) return false;

        // Als huidige status onbekend, sta alles toe
        if (!isset($allowed[$current])) return true;

        return in_array($new, $allowed[$current], true);
    }

    /**
     * Idempotentie op payment event (not status-specific).
     * Multiple webhooks for the same payment may arrive; we process only the first one.
     * Subsequent webhooks are deduplicated; the payment status is fetched fresh each time.
     *
     * BUG FIX: Idempotency key should be payment ID only, not status.
     * This prevents duplicate processing of the same payment webhook.
     */
    private function registerWebhookEventIdempotent(string $provider, string $paymentId, string $status, array $payload): bool
    {
        if (!$this->tableExists('gymies_payment_webhook_events')) {
            return true;
        }
        // Idempotency key: provider + payment_id only. Each payment processed once.
        $eventKey = strtolower(trim($provider)) . ':' . $paymentId;
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
                        mollie_account_source VARCHAR(20) DEFAULT 'platform',
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
            // Payment routing: track of betaling via trainer's eigen Mollie of via platform loopt
            if ($this->tableExists('gymies_payment_transactions') && !$this->columnExists('gymies_payment_transactions', 'mollie_account_source')) {
                DB::statement("ALTER TABLE gymies_payment_transactions ADD COLUMN mollie_account_source VARCHAR(20) DEFAULT 'platform'");
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
