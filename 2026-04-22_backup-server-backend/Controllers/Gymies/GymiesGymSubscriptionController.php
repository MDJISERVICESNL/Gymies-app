<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;

/**
 * Gym Subscription Controller
 *
 * Beheert abonnementen voor gym-organisaties (niet trainers).
 * Gebruikt gymies_gym_subscriptions tabel met organisation_id.
 * Volgt dezelfde Mollie-patronen als GymiesSubscriptionController maar
 * is gescheiden omdat:
 * - Andere tabel (gymies_gym_subscriptions vs gymies_subscriptions)
 * - Organisation-based i.p.v. trainer-based
 * - Andere plan_type ('gym' vs 'trainer')
 * - Jaarlijkse billing optie
 * - Alleen owners mogen subscription beheren
 */
final class GymiesGymSubscriptionController extends Controller
{
    private const MOLLIE_API = 'https://api.mollie.com/v2';

    // ─── 1. Huidig abonnement opvragen ─────────────────────────────────

    /**
     * GET gym/subscription
     * Retourneert het actieve gym-abonnement van de organisatie.
     */
    public function myGymSubscription(Request $request): JsonResponse
    {
        $ctx = $this->requireGymOwner($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $orgId = (int) $ctx['organisation_id'];

        if (!Schema::hasTable('gymies_gym_subscriptions')) {
            return response()->json(['subscription' => null]);
        }

        $sub = DB::table('gymies_gym_subscriptions as s')
            ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
            ->where('s.organisation_id', $orgId)
            ->whereIn('s.status', ['active', 'trialing', 'past_due'])
            ->select([
                's.id',
                's.organisation_id',
                's.plan_id',
                's.status',
                's.billing_cycle',
                's.trial_ends_at',
                's.current_period_start',
                's.current_period_end',
                's.cancelled_at',
                's.created_at',
                'p.name as plan_name',
                'p.slug as plan_slug',
                'p.price_cents_per_month',
                'p.price_cents_per_year',
                'p.has_invoicing',
                'p.has_crm',
                'p.max_trainer_accounts',
            ])
            ->first();

        // Recente betalingen ophalen
        $recentPayments = [];
        if ($sub && Schema::hasTable('gymies_gym_subscription_payments')) {
            $recentPayments = DB::table('gymies_gym_subscription_payments')
                ->where('organisation_id', $orgId)
                ->orderByDesc('created_at')
                ->limit(10)
                ->get()
                ->toArray();
        }

        // Bereken resterende trialdagen
        $trialDaysRemaining = null;
        if ($sub && $sub->status === 'trialing' && $sub->trial_ends_at) {
            $trialEnd = \Carbon\Carbon::parse($sub->trial_ends_at);
            $trialDaysRemaining = max(0, (int) now()->diffInDays($trialEnd, false));
        }

        return response()->json([
            'subscription' => $sub,
            'recent_payments' => $recentPayments,
            'trial_days_remaining' => $trialDaysRemaining,
        ]);
    }

    // ─── 2. Abonnement starten (trial) ─────────────────────────────────

    /**
     * POST gym/subscription/start
     * Start een trial-abonnement voor de gym-organisatie.
     *
     * Body:
     *   plan_id: int (verplicht)
     *   billing_cycle: 'monthly'|'yearly' (optioneel, default: 'monthly')
     */
    public function startGymSubscription(Request $request): JsonResponse
    {
        $ctx = $this->requireGymOwner($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $orgId = (int) $ctx['organisation_id'];
        $userId = (int) $ctx['user_id'];
        $planId = (int) $request->input('plan_id', 0);
        $billingCycle = in_array($request->input('billing_cycle'), ['monthly', 'yearly'], true)
            ? $request->input('billing_cycle')
            : 'monthly';

        if ($planId < 1) {
            return response()->json(['message' => 'Plan ID is verplicht.'], 422);
        }

        // Valideer plan (moet gym-type zijn en actief)
        $plan = DB::table('gymies_plans')
            ->where('id', $planId)
            ->where('is_active', 1)
            ->first();

        if (!$plan) {
            return response()->json(['message' => 'Plan niet gevonden of niet actief.'], 404);
        }

        // S-GYM-001: Plan moet van type 'gym' zijn
        if (Schema::hasColumn('gymies_plans', 'plan_type') && ($plan->plan_type ?? 'trainer') !== 'gym') {
            return response()->json(['message' => 'Dit plan is niet beschikbaar voor gym-organisaties.'], 422);
        }

        // S-GYM-002: Check of organisatie al ooit een subscription record heeft gehad
        // Elke organisatie mag maar 1x trialen (zelfde patroon als trainer S-011)
        if (Schema::hasTable('gymies_gym_subscriptions')) {
            $existingSub = DB::table('gymies_gym_subscriptions')
                ->where('organisation_id', $orgId)
                ->first();

            if ($existingSub) {
                // Als er al een actieve/trialing sub is → blokkeer
                if (in_array($existingSub->status, ['active', 'trialing', 'past_due'], true)) {
                    return response()->json([
                        'message' => 'Je organisatie heeft al een actief abonnement.',
                        'existing_status' => $existingSub->status,
                    ], 409);
                }

                // Als er een verlopen/cancelled sub is → ook blokkeer (1x trial)
                return response()->json([
                    'message' => 'Je organisatie heeft al eerder een trial gehad. Neem contact op voor heractivering.',
                    'existing_status' => $existingSub->status,
                ], 409);
            }
        }

        // Valideer prijs
        $priceCentsMonth = (int) ($plan->price_cents_per_month ?? 0);
        $priceCentsYear = (int) ($plan->price_cents_per_year ?? 0);

        // S-GYM-003: Prijs validatie (zelfde als S-038)
        $activePrice = $billingCycle === 'yearly' && $priceCentsYear > 0
            ? $priceCentsYear
            : $priceCentsMonth;

        if ($activePrice < 1 || $activePrice > 100000 * 100) {
            return response()->json(['message' => 'Plan heeft geen geldige prijs.'], 422);
        }

        // Trial configuratie: gym's krijgen standaard 14 dagen trial
        $trialDays = 14;
        if (Schema::hasTable('gymies_system_settings')) {
            $setting = DB::table('gymies_system_settings')
                ->where('setting_key', 'gym_trial_days')
                ->first();
            if ($setting) {
                $trialDays = max(1, (int) $setting->setting_value);
            }
        }

        $trialEndsAt = now()->addDays($trialDays);

        // Subscription aanmaken in DB
        try {
            $subId = DB::table('gymies_gym_subscriptions')->insertGetId([
                'organisation_id' => $orgId,
                'plan_id' => $planId,
                'status' => 'trialing',
                'billing_cycle' => $billingCycle,
                'trial_ends_at' => $trialEndsAt,
                'current_period_start' => now(),
                'current_period_end' => $trialEndsAt,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('Gym subscription aanmaken mislukt', [
                    'organisation_id' => $orgId,
                    'plan_id' => $planId,
                    'error' => $e->getMessage(),
                ]);
            }
            return response()->json(['message' => 'Abonnement aanmaken mislukt. Probeer het opnieuw.'], 500);
        }

        if (function_exists('logger')) {
            logger()->info('Gym trial subscription gestart', [
                'subscription_id' => $subId,
                'organisation_id' => $orgId,
                'plan_id' => $planId,
                'billing_cycle' => $billingCycle,
                'trial_days' => $trialDays,
                'started_by_user_id' => $userId,
            ]);
        }

        return response()->json([
            'ok' => true,
            'subscription_id' => (int) $subId,
            'status' => 'trialing',
            'billing_cycle' => $billingCycle,
            'trial_days' => $trialDays,
            'trial_ends_at' => $trialEndsAt->toIso8601String(),
            'checkout_url' => null, // Mollie komt pas na trial
        ]);
    }

    // ─── 3. Mollie betaling starten (na trial) ─────────────────────────

    /**
     * POST gym/subscription/activate
     * Start Mollie-betaalflow nadat trial verloopt.
     * Maakt Mollie customer + eerste betaling aan (mandaat).
     */
    public function activateGymSubscription(Request $request): JsonResponse
    {
        $ctx = $this->requireGymOwner($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $orgId = (int) $ctx['organisation_id'];

        if (!Schema::hasTable('gymies_gym_subscriptions')) {
            return response()->json(['message' => 'Abonnementen module niet actief.'], 422);
        }

        $sub = DB::table('gymies_gym_subscriptions')
            ->where('organisation_id', $orgId)
            ->whereIn('status', ['trialing', 'past_due'])
            ->first();

        if (!$sub) {
            return response()->json(['message' => 'Geen trial of openstaand abonnement gevonden.'], 404);
        }

        $plan = DB::table('gymies_plans')
            ->where('id', $sub->plan_id)
            ->where('is_active', 1)
            ->first();

        if (!$plan) {
            return response()->json(['message' => 'Plan niet meer beschikbaar.'], 404);
        }

        $apiKey = $this->getMollieApiKey();
        if ($apiKey === '') {
            return response()->json(['message' => 'Betalingssysteem niet geconfigureerd.'], 500);
        }

        // Bepaal prijs op basis van billing cycle
        $billingCycle = $sub->billing_cycle ?? 'monthly';
        if ($billingCycle === 'yearly' && (int) ($plan->price_cents_per_year ?? 0) > 0) {
            $priceCents = (int) $plan->price_cents_per_year;
            $interval = '12 months';
            $description = 'Gymies ' . $plan->name . ' - Jaarabonnement';
        } else {
            $priceCents = (int) $plan->price_cents_per_month;
            $interval = '1 month';
            $description = 'Gymies ' . $plan->name . ' - Maandabonnement';
        }

        // S-GYM-003: Bedrag validatie
        if ($priceCents < 1 || $priceCents > 100000 * 100) {
            return response()->json(['message' => 'Ongeldige prijsconfiguratie.'], 422);
        }

        $amountEur = $this->centsToCurrencyString($priceCents);

        // Haal organisatie + owner info op voor Mollie customer
        $org = DB::table('gymies_organisations')->where('id', $orgId)->first();
        $ownerUser = DB::table('gymies_users')->where('id', (int) $ctx['user_id'])->first();

        $customerName = $org ? ($org->name ?? 'Gym') : 'Gym';
        $customerEmail = $ownerUser ? ($ownerUser->email ?? '') : '';

        // 1. Mollie Customer aanmaken (of hergebruiken)
        $customerId = $sub->mollie_customer_id ?? null;

        if (!$customerId) {
            $customerResponse = Http::withToken($apiKey)->timeout(15)->post(self::MOLLIE_API . '/customers', [
                'name' => $customerName,
                'email' => $customerEmail,
            ]);

            if (!$customerResponse->successful()) {
                if (function_exists('logger')) {
                    logger()->error('Mollie customer aanmaken mislukt (gym)', [
                        'organisation_id' => $orgId,
                        'http_status' => $customerResponse->status(),
                        'response' => $customerResponse->body(),
                    ]);
                }
                return response()->json(['message' => 'Betaalaccount aanmaken mislukt. Probeer het later opnieuw.'], 502);
            }

            $customerId = $customerResponse->json('id');

            // Sla customer ID op
            DB::table('gymies_gym_subscriptions')
                ->where('id', $sub->id)
                ->update([
                    'mollie_customer_id' => $customerId,
                    'updated_at' => now(),
                ]);
        }

        // 2. Eerste betaling met mandaat (sequenceType: first)
        $redirectUrl = rtrim(config('app.url', ''), '/') . '/gym/subscription';
        $webhookUrl = rtrim(config('app.url', ''), '/') . '/api/gymies/webhooks/mollie-gym-subscription';

        $firstPaymentResponse = Http::withToken($apiKey)->timeout(15)->post(self::MOLLIE_API . '/payments', [
            'amount' => ['currency' => 'EUR', 'value' => $amountEur],
            'customerId' => $customerId,
            'sequenceType' => 'first',
            'description' => $description . ' - Eerste betaling',
            'redirectUrl' => $redirectUrl,
            'webhookUrl' => $webhookUrl,
            'metadata' => [
                'gym_subscription_id' => (string) $sub->id,
                'organisation_id' => (string) $orgId,
                'type' => 'gym_subscription_first',
            ],
        ]);

        if (!$firstPaymentResponse->successful()) {
            if (function_exists('logger')) {
                logger()->error('Mollie eerste betaling aanmaken mislukt (gym)', [
                    'organisation_id' => $orgId,
                    'customer_id' => $customerId,
                    'http_status' => $firstPaymentResponse->status(),
                    'response' => $firstPaymentResponse->body(),
                ]);
            }
            return response()->json(['message' => 'Betaling starten mislukt. Probeer het later opnieuw.'], 502);
        }

        $paymentData = $firstPaymentResponse->json();
        $checkoutUrl = $paymentData['_links']['checkout']['href'] ?? null;
        $molliePaymentId = $paymentData['id'] ?? null;

        // Payment record opslaan
        if (Schema::hasTable('gymies_gym_subscription_payments') && $molliePaymentId) {
            DB::table('gymies_gym_subscription_payments')->insert([
                'gym_subscription_id' => (int) $sub->id,
                'organisation_id' => $orgId,
                'amount_cents' => $priceCents,
                'currency' => 'EUR',
                'status' => 'pending',
                'mollie_payment_id' => $molliePaymentId,
                'description' => $description . ' - Eerste betaling',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        if (function_exists('logger')) {
            logger()->info('Gym Mollie eerste betaling gestart', [
                'subscription_id' => $sub->id,
                'organisation_id' => $orgId,
                'mollie_customer_id' => $customerId,
                'mollie_payment_id' => $molliePaymentId,
                'amount_eur' => $amountEur,
            ]);
        }

        return response()->json([
            'ok' => true,
            'checkout_url' => $checkoutUrl,
            'mollie_payment_id' => $molliePaymentId,
        ]);
    }

    // ─── 4. Mollie Webhook (gym abonnementen) ──────────────────────────

    /**
     * POST webhooks/mollie-gym-subscription
     * Verwerkt betalingsupdates van Mollie voor gym-abonnementen.
     * Publiek endpoint — geen auth, maar wel validatie.
     */
    public function mollieGymWebhook(Request $request): JsonResponse
    {
        $paymentId = $request->input('id');

        // S-012: Payment ID format validatie
        if (!$paymentId || !preg_match('/^tr_[A-Za-z0-9]+$/', (string) $paymentId)) {
            return response()->json(['status' => 'invalid_payment_id'], 422);
        }

        $apiKey = $this->getMollieApiKey();
        if ($apiKey === '') {
            return response()->json(['status' => 'config_error'], 500);
        }

        // P-FIX-2: Haal betalingsstatus op van Mollie API (niet uit webhook body)
        $paymentResponse = Http::withToken($apiKey)->timeout(15)
            ->get(self::MOLLIE_API . "/payments/{$paymentId}");

        if (!$paymentResponse->successful()) {
            if (function_exists('logger')) {
                logger()->warning('Gym webhook: Mollie payment ophalen mislukt', [
                    'payment_id' => $paymentId,
                    'http_status' => $paymentResponse->status(),
                ]);
            }
            return response()->json(['status' => 'payment_fetch_failed'], 502);
        }

        $payment = $paymentResponse->json();
        $mollieStatus = $payment['status'] ?? 'unknown';
        $customerId = $payment['customerId'] ?? null;
        $metadata = $payment['metadata'] ?? [];
        $gymSubId = (int) ($metadata['gym_subscription_id'] ?? 0);
        $orgId = (int) ($metadata['organisation_id'] ?? 0);

        if ($gymSubId < 1) {
            // Probeer via customerId te matchen
            if ($customerId) {
                $sub = DB::table('gymies_gym_subscriptions')
                    ->where('mollie_customer_id', $customerId)
                    ->first();
                if ($sub) {
                    $gymSubId = (int) $sub->id;
                    $orgId = (int) $sub->organisation_id;
                }
            }
        }

        if ($gymSubId < 1) {
            if (function_exists('logger')) {
                logger()->warning('Gym webhook: geen subscription match gevonden', [
                    'payment_id' => $paymentId,
                    'customer_id' => $customerId,
                ]);
            }
            return response()->json(['status' => 'no_subscription_match']);
        }

        // P-FIX-4: Customer ID mismatch detectie
        $sub = DB::table('gymies_gym_subscriptions')->where('id', $gymSubId)->first();
        if (!$sub) {
            return response()->json(['status' => 'subscription_not_found'], 404);
        }

        if ($sub->mollie_customer_id && $customerId && $sub->mollie_customer_id !== $customerId) {
            if (function_exists('logger')) {
                logger()->error('Gym webhook: customer ID mismatch — mogelijke spoofing', [
                    'subscription_id' => $gymSubId,
                    'expected_customer' => $sub->mollie_customer_id,
                    'received_customer' => $customerId,
                    'payment_id' => $paymentId,
                ]);
            }
            return response()->json(['status' => 'customer_mismatch'], 403);
        }

        // Idempotency check
        $eventKey = "mollie_gym:{$paymentId}:{$mollieStatus}";
        if (Schema::hasTable('gymies_webhook_events')) {
            $exists = DB::table('gymies_webhook_events')
                ->where('event_key', $eventKey)
                ->exists();
            if ($exists) {
                return response()->json(['status' => 'already_processed']);
            }
            try {
                DB::table('gymies_webhook_events')->insert([
                    'event_key' => $eventKey,
                    'created_at' => now(),
                ]);
            } catch (\Throwable $e) {
                // UNIQUE constraint → al verwerkt (race condition)
                return response()->json(['status' => 'already_processed']);
            }
        }

        // S-067: Bedrag uit Mollie response (integer arithmetic, geen floats)
        $amountCents = 0;
        $amountStr = $payment['amount']['value'] ?? '0.00';
        if (strpos($amountStr, '.') !== false) {
            [$euros, $cents] = explode('.', $amountStr, 2);
            $amountCents = ((int) $euros) * 100 + (int) str_pad(substr($cents, 0, 2), 2, '0');
        } else {
            $amountCents = ((int) $amountStr) * 100;
        }

        // Verwerk betaling
        DB::beginTransaction();
        try {
            // Update/insert payment record
            if (Schema::hasTable('gymies_gym_subscription_payments')) {
                $existingPayment = DB::table('gymies_gym_subscription_payments')
                    ->where('mollie_payment_id', $paymentId)
                    ->first();

                if ($existingPayment) {
                    DB::table('gymies_gym_subscription_payments')
                        ->where('id', $existingPayment->id)
                        ->update([
                            'status' => $mollieStatus === 'paid' ? 'paid' : ($mollieStatus === 'failed' ? 'failed' : 'pending'),
                            'paid_at' => $mollieStatus === 'paid' ? now() : null,
                            'updated_at' => now(),
                        ]);
                } else {
                    DB::table('gymies_gym_subscription_payments')->insert([
                        'gym_subscription_id' => $gymSubId,
                        'organisation_id' => (int) $sub->organisation_id,
                        'amount_cents' => $amountCents,
                        'currency' => 'EUR',
                        'status' => $mollieStatus === 'paid' ? 'paid' : ($mollieStatus === 'failed' ? 'failed' : 'pending'),
                        'mollie_payment_id' => $paymentId,
                        'paid_at' => $mollieStatus === 'paid' ? now() : null,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ]);
                }
            }

            // Update subscription status
            if ($mollieStatus === 'paid') {
                $billingCycle = $sub->billing_cycle ?? 'monthly';
                $periodEnd = $billingCycle === 'yearly'
                    ? now()->addYear()
                    : now()->addMonth();

                $updateData = [
                    'status' => 'active',
                    'current_period_start' => now(),
                    'current_period_end' => $periodEnd,
                    'updated_at' => now(),
                ];

                DB::table('gymies_gym_subscriptions')
                    ->where('id', $gymSubId)
                    ->update($updateData);

                // Na eerste succesvolle betaling: maak recurring subscription aan
                if (!$sub->mollie_subscription_id && $sub->mollie_customer_id) {
                    $this->createRecurringGymSubscription($sub, $apiKey);
                }
            } elseif ($mollieStatus === 'failed') {
                DB::table('gymies_gym_subscriptions')
                    ->where('id', $gymSubId)
                    ->update([
                        'status' => 'past_due',
                        'updated_at' => now(),
                    ]);
            }

            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            if (function_exists('logger')) {
                logger()->error('Gym webhook: DB transaction mislukt', [
                    'subscription_id' => $gymSubId,
                    'payment_id' => $paymentId,
                    'error' => $e->getMessage(),
                ]);
            }
            return response()->json(['status' => 'db_error'], 500);
        }

        if (function_exists('logger')) {
            logger()->info('Gym webhook verwerkt', [
                'subscription_id' => $gymSubId,
                'payment_id' => $paymentId,
                'mollie_status' => $mollieStatus,
                'amount_cents' => $amountCents,
            ]);
        }

        return response()->json(['status' => 'processed']);
    }

    // ─── 5. Abonnement opzeggen ─────────────────────────────────────────

    /**
     * POST gym/subscription/cancel
     * Zegt het gym-abonnement op. Toegang loopt door tot einde periode.
     *
     * Body:
     *   cancel_reason: string (optioneel)
     */
    public function cancelGymSubscription(Request $request): JsonResponse
    {
        $ctx = $this->requireGymOwner($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $orgId = (int) $ctx['organisation_id'];
        $cancelReason = trim((string) $request->input('cancel_reason', ''));

        if (!Schema::hasTable('gymies_gym_subscriptions')) {
            return response()->json(['message' => 'Abonnementen module niet actief.'], 422);
        }

        $sub = DB::table('gymies_gym_subscriptions')
            ->where('organisation_id', $orgId)
            ->whereIn('status', ['active', 'trialing', 'past_due'])
            ->first();

        if (!$sub) {
            return response()->json(['message' => 'Geen actief abonnement gevonden om op te zeggen.'], 404);
        }

        // S-035: Rate limiting — max 3 opzeggingen per uur per organisatie
        if (Schema::hasTable('gymies_rate_limits')) {
            $rateKey = "gym_cancel:{$orgId}";
            $windowStart = now()->subHour();
            $recentCancels = DB::table('gymies_rate_limits')
                ->where('key', $rateKey)
                ->where('window_start', '>=', $windowStart)
                ->count();

            if ($recentCancels >= 3) {
                return response()->json(['message' => 'Te veel opzeggingsverzoeken. Probeer het over een uur opnieuw.'], 429);
            }

            try {
                DB::table('gymies_rate_limits')->insert([
                    'key' => $rateKey,
                    'window_start' => now(),
                ]);
            } catch (\Throwable $e) {
                // Non-blocking
            }
        }

        $apiKey = $this->getMollieApiKey();

        // Fase 1: Mollie subscription verwijderen (VOOR DB transactie — P-FIX-1)
        $mollieDeleted = false;
        if ($apiKey !== '' && $sub->mollie_customer_id && $sub->mollie_subscription_id) {
            try {
                $deleteResponse = Http::withToken($apiKey)->timeout(15)->delete(
                    self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/subscriptions/{$sub->mollie_subscription_id}"
                );
                $mollieDeleted = $deleteResponse->successful() || $deleteResponse->status() === 404;

                if (!$mollieDeleted) {
                    if (function_exists('logger')) {
                        logger()->error('Mollie gym subscription verwijderen mislukt', [
                            'subscription_id' => $sub->id,
                            'mollie_sub_id' => $sub->mollie_subscription_id,
                            'http_status' => $deleteResponse->status(),
                        ]);
                    }
                    // Ga toch door met DB update — Mollie kan later handmatig opgeruimd worden
                }
            } catch (\Throwable $e) {
                if (function_exists('logger')) {
                    logger()->error('Mollie gym subscription verwijderen exception', [
                        'subscription_id' => $sub->id,
                        'error' => $e->getMessage(),
                    ]);
                }
            }
        }

        // Fase 2: DB transactie
        try {
            DB::beginTransaction();

            $updateData = [
                'status' => 'cancelled',
                'cancelled_at' => now(),
                'updated_at' => now(),
            ];

            DB::table('gymies_gym_subscriptions')
                ->where('id', $sub->id)
                ->update($updateData);

            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            if (function_exists('logger')) {
                logger()->critical('Gym subscription DB cancel mislukt NA Mollie delete', [
                    'subscription_id' => $sub->id,
                    'mollie_deleted' => $mollieDeleted,
                    'error' => $e->getMessage(),
                ]);
            }
            return response()->json(['message' => 'Opzeggen mislukt door een technische fout. Neem contact op met support.'], 500);
        }

        if (function_exists('logger')) {
            logger()->info('Gym subscription opgezegd', [
                'subscription_id' => $sub->id,
                'organisation_id' => $orgId,
                'cancel_reason' => $cancelReason,
                'mollie_deleted' => $mollieDeleted,
                'access_until' => $sub->current_period_end,
            ]);
        }

        return response()->json([
            'ok' => true,
            'message' => 'Abonnement opgezegd. Je behoudt toegang tot ' . ($sub->current_period_end
                ? \Carbon\Carbon::parse($sub->current_period_end)->format('d-m-Y')
                : 'het einde van de huidige periode') . '.',
            'access_until' => $sub->current_period_end,
        ]);
    }

    // ─── 6. Billing cycle wijzigen ──────────────────────────────────────

    /**
     * POST gym/subscription/billing-cycle
     * Wijzig van maandelijks naar jaarlijks of andersom.
     * Gaat in bij de volgende betaalperiode.
     *
     * Body:
     *   billing_cycle: 'monthly'|'yearly'
     */
    public function changeBillingCycle(Request $request): JsonResponse
    {
        $ctx = $this->requireGymOwner($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $orgId = (int) $ctx['organisation_id'];
        $newCycle = $request->input('billing_cycle');

        if (!in_array($newCycle, ['monthly', 'yearly'], true)) {
            return response()->json(['message' => 'Ongeldige billing cycle. Kies "monthly" of "yearly".'], 422);
        }

        $sub = DB::table('gymies_gym_subscriptions')
            ->where('organisation_id', $orgId)
            ->whereIn('status', ['active', 'trialing'])
            ->first();

        if (!$sub) {
            return response()->json(['message' => 'Geen actief abonnement gevonden.'], 404);
        }

        if (($sub->billing_cycle ?? 'monthly') === $newCycle) {
            return response()->json(['message' => 'Billing cycle is al ' . $newCycle . '.'], 422);
        }

        // Plan moet jaarprijs hebben als we naar yearly switchen
        if ($newCycle === 'yearly') {
            $plan = DB::table('gymies_plans')->where('id', $sub->plan_id)->first();
            if (!$plan || (int) ($plan->price_cents_per_year ?? 0) < 1) {
                return response()->json(['message' => 'Jaarabonnement niet beschikbaar voor dit plan.'], 422);
            }
        }

        // Als er een actieve Mollie subscription is, moet die geüpdatet worden
        $apiKey = $this->getMollieApiKey();
        if ($apiKey !== '' && $sub->mollie_customer_id && $sub->mollie_subscription_id) {
            $plan = DB::table('gymies_plans')->where('id', $sub->plan_id)->first();
            $newPriceCents = $newCycle === 'yearly'
                ? (int) ($plan->price_cents_per_year ?? 0)
                : (int) ($plan->price_cents_per_month ?? 0);
            $newInterval = $newCycle === 'yearly' ? '12 months' : '1 month';
            $newAmountEur = $this->centsToCurrencyString($newPriceCents);

            // Oude subscription stoppen, nieuwe aanmaken (Mollie ondersteunt geen interval-wijziging via PATCH)
            try {
                Http::withToken($apiKey)->timeout(15)->delete(
                    self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/subscriptions/{$sub->mollie_subscription_id}"
                );

                $newSubResponse = Http::withToken($apiKey)->timeout(15)->post(
                    self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/subscriptions",
                    [
                        'amount' => ['currency' => 'EUR', 'value' => $newAmountEur],
                        'interval' => $newInterval,
                        'description' => 'Gymies Studio ' . ($newCycle === 'yearly' ? 'Jaarabonnement' : 'Maandabonnement'),
                        'webhookUrl' => rtrim(config('app.url', ''), '/') . '/api/gymies/webhooks/mollie-gym-subscription',
                    ]
                );

                if ($newSubResponse->successful()) {
                    $newMollieSubId = $newSubResponse->json('id');
                    DB::table('gymies_gym_subscriptions')
                        ->where('id', $sub->id)
                        ->update([
                            'billing_cycle' => $newCycle,
                            'mollie_subscription_id' => $newMollieSubId,
                            'updated_at' => now(),
                        ]);
                } else {
                    if (function_exists('logger')) {
                        logger()->error('Mollie gym subscription cycle-change: nieuwe sub aanmaken mislukt', [
                            'subscription_id' => $sub->id,
                            'http_status' => $newSubResponse->status(),
                        ]);
                    }
                    return response()->json(['message' => 'Billing cycle wijzigen mislukt bij betaalprovider.'], 502);
                }
            } catch (\Throwable $e) {
                if (function_exists('logger')) {
                    logger()->error('Mollie gym subscription cycle-change exception', [
                        'subscription_id' => $sub->id,
                        'error' => $e->getMessage(),
                    ]);
                }
                return response()->json(['message' => 'Billing cycle wijzigen mislukt. Probeer het later opnieuw.'], 502);
            }
        } else {
            // Geen actieve Mollie sub (trial) → alleen DB updaten
            DB::table('gymies_gym_subscriptions')
                ->where('id', $sub->id)
                ->update([
                    'billing_cycle' => $newCycle,
                    'updated_at' => now(),
                ]);
        }

        if (function_exists('logger')) {
            logger()->info('Gym billing cycle gewijzigd', [
                'subscription_id' => $sub->id,
                'organisation_id' => $orgId,
                'old_cycle' => $sub->billing_cycle ?? 'monthly',
                'new_cycle' => $newCycle,
            ]);
        }

        return response()->json([
            'ok' => true,
            'billing_cycle' => $newCycle,
            'message' => $newCycle === 'yearly'
                ? 'Overgestapt naar jaarabonnement. Je bespaart 15% per jaar!'
                : 'Overgestapt naar maandabonnement.',
        ]);
    }

    // ─── 7. Beschikbare gym plannen ─────────────────────────────────────

    /**
     * GET gym/plans
     * Retourneert alle actieve gym-plannen (publiek, geen auth nodig binnen gym context).
     */
    public function availableGymPlans(Request $request): JsonResponse
    {
        if (!Schema::hasTable('gymies_plans')) {
            return response()->json(['plans' => []]);
        }

        $query = DB::table('gymies_plans')
            ->where('is_active', 1)
            ->orderBy('price_cents_per_month');

        if (Schema::hasColumn('gymies_plans', 'plan_type')) {
            $query->where('plan_type', 'gym');
        }

        $plans = $query->get()->map(function ($plan) {
            return [
                'id' => (int) $plan->id,
                'name' => $plan->name,
                'slug' => $plan->slug ?? null,
                'price_cents_per_month' => (int) ($plan->price_cents_per_month ?? 0),
                'price_cents_per_year' => (int) ($plan->price_cents_per_year ?? 0),
                'price_display_month' => '€' . number_format(((int) ($plan->price_cents_per_month ?? 0)) / 100, 2, ',', '.'),
                'price_display_year' => (int) ($plan->price_cents_per_year ?? 0) > 0
                    ? '€' . number_format(((int) $plan->price_cents_per_year) / 100, 2, ',', '.')
                    : null,
                'has_invoicing' => (bool) ($plan->has_invoicing ?? false),
                'has_crm' => (bool) ($plan->has_crm ?? false),
                'max_trainer_accounts' => $plan->max_trainer_accounts ?? null,
                'description' => $plan->description ?? null,
            ];
        });

        return response()->json(['plans' => $plans]);
    }

    // ─── 8. Betalingsgeschiedenis ───────────────────────────────────────

    /**
     * GET gym/subscription/payments
     * Retourneert betalingsgeschiedenis voor het gym-abonnement.
     */
    public function paymentHistory(Request $request): JsonResponse
    {
        $ctx = $this->requireGymOwner($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $orgId = (int) $ctx['organisation_id'];

        if (!Schema::hasTable('gymies_gym_subscription_payments')) {
            return response()->json(['payments' => [], 'total' => 0]);
        }

        $page = max(1, (int) $request->input('page', 1));
        $perPage = min(50, max(1, (int) $request->input('per_page', 20)));

        $query = DB::table('gymies_gym_subscription_payments')
            ->where('organisation_id', $orgId)
            ->orderByDesc('created_at');

        $total = (clone $query)->count();

        $payments = $query
            ->offset(($page - 1) * $perPage)
            ->limit($perPage)
            ->get();

        return response()->json([
            'payments' => $payments,
            'total' => $total,
            'page' => $page,
            'per_page' => $perPage,
        ]);
    }

    // ═══════════════════════════════════════════════════════════════════
    // PRIVATE HELPERS
    // ═══════════════════════════════════════════════════════════════════

    /**
     * Valideer dat de ingelogde gebruiker gym-owner is.
     * Retourneert context array of JsonResponse bij fout.
     */
    private function requireGymOwner(Request $request): array|JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_organisation_members')) {
            return response()->json(['message' => 'Gym module niet geactiveerd.'], 422);
        }

        // Zoek actief owner-membership
        $membership = DB::table('gymies_organisation_members as m')
            ->join('gymies_organisations as o', 'o.id', '=', 'm.organisation_id')
            ->where('m.user_id', $user->id)
            ->where('m.role', 'owner')
            ->where('m.status', 'active')
            ->where('o.status', 'active')
            ->first(['m.organisation_id', 'o.name as organisation_name']);

        if (!$membership) {
            return response()->json(['message' => 'Alleen de gym-eigenaar kan het abonnement beheren.'], 403);
        }

        return [
            'user_id' => (int) $user->id,
            'organisation_id' => (int) $membership->organisation_id,
            'organisation_name' => (string) $membership->organisation_name,
        ];
    }

    /**
     * Na succesvolle eerste betaling: maak recurring Mollie subscription aan.
     */
    private function createRecurringGymSubscription(object $sub, string $apiKey): void
    {
        $plan = DB::table('gymies_plans')->where('id', $sub->plan_id)->first();
        if (!$plan) {
            return;
        }

        $billingCycle = $sub->billing_cycle ?? 'monthly';
        if ($billingCycle === 'yearly' && (int) ($plan->price_cents_per_year ?? 0) > 0) {
            $priceCents = (int) $plan->price_cents_per_year;
            $interval = '12 months';
            $cycleLabel = 'Jaarabonnement';
        } else {
            $priceCents = (int) $plan->price_cents_per_month;
            $interval = '1 month';
            $cycleLabel = 'Maandabonnement';
        }

        $amountEur = $this->centsToCurrencyString($priceCents);

        try {
            $response = Http::withToken($apiKey)->timeout(15)->post(
                self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/subscriptions",
                [
                    'amount' => ['currency' => 'EUR', 'value' => $amountEur],
                    'interval' => $interval,
                    'description' => 'Gymies ' . $plan->name . ' ' . $cycleLabel,
                    'webhookUrl' => rtrim(config('app.url', ''), '/') . '/api/gymies/webhooks/mollie-gym-subscription',
                ]
            );

            if ($response->successful()) {
                $mollieSubId = $response->json('id');

                // Haal mandaat op
                $mandates = Http::withToken($apiKey)->timeout(15)
                    ->get(self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/mandates");
                $mandateId = $mandates->json('_embedded.mandates.0.id') ?? null;

                DB::table('gymies_gym_subscriptions')->where('id', $sub->id)->update([
                    'mollie_subscription_id' => $mollieSubId,
                    'mollie_mandate_id' => $mandateId,
                    'updated_at' => now(),
                ]);
            } else {
                if (function_exists('logger')) {
                    logger()->error('Recurring gym subscription aanmaken mislukt', [
                        'subscription_id' => $sub->id,
                        'http_status' => $response->status(),
                        'response' => $response->body(),
                    ]);
                }
            }
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('Recurring gym subscription exception', [
                    'subscription_id' => $sub->id,
                    'error' => $e->getMessage(),
                ]);
            }
        }
    }

    private function getMollieApiKey(): string
    {
        $key = config('gymies.mollie_api_key');
        if ($key !== null && $key !== '') {
            return (string) $key;
        }
        $key = env('MOLLIE_API_KEY');
        return is_string($key) ? trim($key) : '';
    }

    /**
     * P-FIX-5: Robuuste conversie van centen (int) naar EUR string.
     * 9999 → "99.99"
     */
    private function centsToCurrencyString(int $cents): string
    {
        return number_format($cents / 100, 2, '.', '');
    }
}
