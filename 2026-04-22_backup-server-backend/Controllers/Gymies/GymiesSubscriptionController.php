<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;

final class GymiesSubscriptionController extends Controller
{
    private const MOLLIE_API = 'https://api.mollie.com/v2';

    public function availablePlans(Request $request): JsonResponse
    {
        if (!Schema::hasTable('gymies_plans')) {
            return response()->json(['plans' => []]);
        }

        // Filter op plan_type: trainers zien trainer-plans, gym eigenaren zien gym-plans
        $user = $request->attributes->get('gymies_user');
        $planType = 'trainer';
        if ($user && $user->role === 'gym_owner') {
            $planType = 'gym';
        }

        $query = DB::table('gymies_plans')
            ->where('is_active', 1)
            ->orderBy('price_cents_per_month');

        if (Schema::hasColumn('gymies_plans', 'plan_type')) {
            $query->where('plan_type', $planType);
        }

        $plans = $query->get();

        return response()->json(['plans' => $plans]);
    }

    public function mySubscription(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers hebben een abonnement.'], 403);
        }

        if (!Schema::hasTable('gymies_subscriptions')) {
            return response()->json(['subscription' => null]);
        }

        $base = DB::table('gymies_subscriptions as s')
            ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
            ->where('s.trainer_user_id', (int) $user->id)
            ->whereIn('s.status', ['active', 'trialing', 'past_due']);

        $select = [
            's.*',
            'p.name as plan_name',
            'p.slug as plan_slug',
            'p.price_cents_per_month',
            'p.max_sessions_per_month',
            'p.has_invoicing',
            'p.has_crm',
            'p.max_trainer_accounts',
        ];
        if (Schema::hasColumn('gymies_subscriptions', 'pending_plan_id')) {
            $base->leftJoin('gymies_plans as pp', 'pp.id', '=', 's.pending_plan_id');
            $select[] = 'pp.name as pending_plan_name';
            $select[] = 'pp.slug as pending_plan_slug';
            $select[] = 'pp.price_cents_per_month as pending_price_cents_per_month';
        }
        $sub = $base->select($select)->first();

        $recentPayments = DB::table('gymies_subscription_payments')
            ->where('trainer_user_id', (int) $user->id)
            ->orderByDesc('created_at')
            ->limit(12)
            ->get();

        return response()->json([
            'subscription' => $sub,
            'recent_payments' => $recentPayments,
        ]);
    }

    public function cancelSubscription(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        // S-035: Rate limit cancelSubscription — max 3 cancellations per hour per user
        if (Schema::hasTable('gymies_rate_limits')) {
            $cancelKey = 'cancel_sub:' . (int) $user->id;
            $windowStart = now()->subMinutes(60);
            $cancelCount = DB::table('gymies_rate_limits')
                ->where('key', $cancelKey)
                ->where('window_start', '>=', $windowStart)
                ->count();
            if ($cancelCount >= 3) {
                return response()->json(['message' => 'Te veel annuleringspogingen. Probeer het later opnieuw.'], 429);
            }
            DB::table('gymies_rate_limits')->insert([
                'key'          => $cancelKey,
                'window_start' => now(),
                'created_at'   => now(),
            ]);
        }

        $sub = DB::table('gymies_subscriptions')
            ->where('trainer_user_id', (int) $user->id)
            ->whereIn('status', ['active', 'trialing', 'past_due'])
            ->first();

        if (!$sub) {
            return response()->json(['message' => 'Geen actief abonnement gevonden.'], 404);
        }

        $request->validate(['reason' => 'nullable|string|max:500']);

        // P-FIX-2: Mollie API call BEFORE transaction (cannot be rolled back)
        $mollieResult = null;
        $apiKey = $this->getMollieApiKey();
        if ($apiKey !== '' && $sub->mollie_customer_id && $sub->mollie_subscription_id) {
            $response = Http::withToken($apiKey)
                ->timeout(15)
                ->delete(self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/subscriptions/{$sub->mollie_subscription_id}");

            if (!$response->successful() && $response->status() !== 404) {
                return response()->json(['message' => 'Mollie opzegging mislukt. Probeer het later opnieuw.'], 502);
            }
            $mollieResult = ['status' => $response->status()];
        }

        // P-FIX-2: Atomic DB transaction for cancellation
        try {
            DB::transaction(function() use ($sub, $user) {
                DB::table('gymies_subscriptions')->where('id', $sub->id)->update([
                    'status' => 'cancelled',
                    'cancelled_at' => now(),
                    'cancel_reason' => request()->input('reason'),
                    'updated_at' => now(),
                ]);

                if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                    DB::table('gymies_trainer_profiles')
                        ->where('user_id', (int) $user->id)
                        ->update(['subscription_plan' => null]);
                }
            });
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->critical('cancelSubscription DB transaction failed after Mollie cancellation', [
                    'subscription_id' => $sub->id,
                    'mollie_result' => $mollieResult,
                    'error' => $e->getMessage(),
                ]);
            }
            return response()->json(['message' => 'Database update mislukt. Contacteer support.'], 500);
        }

        return response()->json(['ok' => true, 'message' => 'Abonnement opgezegd. Je hebt toegang tot het einde van de huidige periode.']);
    }

    /**
     * Plan wijzigen: gaat pas in bij de volgende factuurdatum.
     */
    public function changePlan(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $request->validate(['plan_slug' => 'required|string|in:starter,pro,pro_plus,studio']);

        $slug = strtolower(trim((string) $request->input('plan_slug')));

        // Bepaal welk plan_type de gebruiker mag kiezen
        $allowedType = ($user->role === 'gym_owner') ? 'gym' : 'trainer';

        $plan = DB::table('gymies_plans')
            ->whereRaw('LOWER(TRIM(slug)) = ?', [$slug])
            ->where('is_active', 1)
            ->when(Schema::hasColumn('gymies_plans', 'plan_type'), fn ($q) => $q->where('plan_type', $allowedType))
            ->first();

        if (!$plan) {
            return response()->json(['message' => 'Plan niet gevonden.'], 404);
        }

        $sub = DB::table('gymies_subscriptions')
            ->where('trainer_user_id', (int) $user->id)
            ->whereIn('status', ['active', 'trialing', 'past_due'])
            ->first();

        if (!$sub) {
            return response()->json(['message' => 'Geen actief abonnement gevonden.'], 404);
        }

        if ((int) $sub->plan_id === (int) $plan->id) {
            return response()->json(['message' => 'Je hebt al dit plan.'], 422);
        }

        // S-011: Voorkom plan-switch misbruik om trial-periodes te verlengen.
        // Maximaal 3 plan-wijzigingen per 30 dagen toegestaan.
        if (Schema::hasTable('gymies_rate_limits')) {
            $switchKey   = 'plan_change:' . (int) $user->id;
            $windowStart = now()->subDays(30);
            $switchCount = DB::table('gymies_rate_limits')
                ->where('key', $switchKey)
                ->where('window_start', '>=', $windowStart)
                ->count();
            if ($switchCount >= 3) {
                return response()->json(['message' => 'Te veel plan-wijzigingen. Probeer het later opnieuw.'], 429);
            }
            DB::table('gymies_rate_limits')->insert([
                'key'          => $switchKey,
                'window_start' => now(),
                'created_at'   => now(),
            ]);
        }

        $apiKey = $this->getMollieApiKey();
        $hasMollie = $apiKey !== '' && $sub->mollie_customer_id && $sub->mollie_subscription_id;

        // P-FIX-1: Mollie API call BEFORE transaction (cannot be rolled back)
        $mollieResult = null;
        if ($hasMollie) {
            $priceCents = (int) ($plan->price_cents_per_month ?? 0);
            if ($priceCents <= 0) {
                return response()->json(['message' => 'Plan heeft geen geldige prijs.'], 400);
            }
            $amountEur = $this->centsToCurrencyString($priceCents);
            $response = Http::withToken($apiKey)
                ->timeout(15)
                ->patch(
                    self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/subscriptions/{$sub->mollie_subscription_id}",
                    [
                        'amount' => ['currency' => 'EUR', 'value' => $amountEur],
                        'description' => 'Gymies ' . $plan->name . ' Maandabonnement',
                    ]
                );

            if (!$response->successful()) {
                return response()->json(['message' => 'Mollie-abonnement wijzigen mislukt. Probeer later opnieuw.'], 502);
            }
            $mollieResult = $response->json();
        }

        // P-FIX-1: Atomic DB transaction for subscription update
        // FIX-2026-04-20: Bij trialing ALTIJD direct plan_id + subscription_plan updaten,
        // want er is geen Mollie-webhook die pending_plan_id activeert tijdens trial.
        try {
            DB::transaction(function() use ($sub, $plan, $user) {
                $isTrialing = strtolower(trim((string) ($sub->status ?? ''))) === 'trialing';

                if (!$isTrialing && Schema::hasColumn('gymies_subscriptions', 'pending_plan_id')) {
                    // Actief abonnement met Mollie: pending_plan_id gebruiken (wordt geactiveerd bij volgende betaling)
                    DB::table('gymies_subscriptions')->where('id', $sub->id)->update([
                        'pending_plan_id' => (int) $plan->id,
                        'updated_at' => now(),
                    ]);
                } else {
                    // Trialing of geen pending_plan_id kolom: direct wijzigen
                    DB::table('gymies_subscriptions')->where('id', $sub->id)->update([
                        'plan_id' => (int) $plan->id,
                        'pending_plan_id' => null, // Clear eventuele pending
                        'updated_at' => now(),
                    ]);
                    if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                        DB::table('gymies_trainer_profiles')
                            ->where('user_id', (int) $user->id)
                            ->update(['subscription_plan' => $plan->slug]);
                    }
                }

                // PRO+: Auto-create ProPlusSettings when upgrading to pro_plus
                if ($plan->slug === 'pro_plus' || $plan->slug === 'pro+') {
                    if (Schema::hasTable('gymies_trainer_pro_plus_settings')) {
                        $existing = DB::table('gymies_trainer_pro_plus_settings')
                            ->where('trainer_user_id', (int) $user->id)
                            ->exists();
                        if (!$existing) {
                            DB::table('gymies_trainer_pro_plus_settings')->insert([
                                'trainer_user_id' => (int) $user->id,
                                'created_at' => now(),
                                'updated_at' => now(),
                            ]);
                        }
                    }
                }
            });
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->critical('changePlan DB transaction failed after Mollie update', [
                    'subscription_id' => $sub->id,
                    'plan_id' => $plan->id,
                    'mollie_result' => $mollieResult,
                    'error' => $e->getMessage(),
                ]);
            }
            return response()->json(['message' => 'Database update mislukt. Contacteer support.'], 500);
        }

        $periodEnd = $sub->current_period_end ?? '';
        return response()->json([
            'ok' => true,
            'message' => $hasMollie
                ? 'Abonnement gewijzigd naar ' . $plan->name . '. De wijziging gaat in op ' . ($periodEnd ?: 'de volgende factuurdatum') . '.'
                : 'Abonnement gewijzigd naar ' . $plan->name . '.',
            'current_period_end' => $periodEnd,
        ]);
    }

    /**
     * Mollie subscription webhook: verwerkt betalingsgebeurtenissen.
     */
    public function subscriptionWebhook(Request $request): JsonResponse
    {
        $paymentId = $request->input('id');
        if (!$paymentId || !is_string($paymentId)) {
            return response()->json(['status' => 'ignored']);
        }

        // S-012: Valideer Mollie payment ID formaat om willekeurige API-aanroepen te voorkomen.
        // Mollie subscription payment IDs beginnen met "tr_".
        if (!preg_match('/^tr_[A-Za-z0-9]+$/', $paymentId)) {
            Log::warning('[Gymies] Subscription webhook: ongeldig payment ID formaat', [
                'id' => substr($paymentId, 0, 32),
                'ip' => $request->ip(),
            ]);
            return response()->json(['status' => 'ignored']);
        }

        $apiKey = $this->getMollieApiKey();
        if ($apiKey === '') {
            return response()->json(['status' => 'no_api_key']);
        }

        $response = Http::withToken($apiKey)
            ->timeout(15)
            ->get(self::MOLLIE_API . "/payments/{$paymentId}");

        if (!$response->successful()) {
            return response()->json(['status' => 'fetch_failed'], 502);
        }

        $data = $response->json();
        $status = $data['status'] ?? 'unknown';
        $subscriptionId = $data['subscriptionId'] ?? null;
        // S-067: Float Precision Loss BTW — use integer arithmetic instead of float rounding
        // Convert EUR string to cents using intdiv for exact integer result (e.g., €12.34 = 1234 cents)
        $amountCents = 0;
        if (isset($data['amount']['value'])) {
            $eurValue = (string) $data['amount']['value'];
            // Parse EUR value: "12.34" -> remove dot -> 1234
            $parts = explode('.', $eurValue);
            if (count($parts) === 2) {
                $euros = (int) $parts[0];
                $cents = (int) str_pad($parts[1], 2, '0', STR_PAD_RIGHT);
                $amountCents = $euros * 100 + $cents;
            } else {
                $amountCents = (int) $parts[0] * 100;
            }
        }

        // Zoek subscription: via mollie_subscription_id (recurring) OF via metadata (eerste betaling)
        $sub = null;
        $isFirstPayment = false;

        if ($subscriptionId) {
            $sub = DB::table('gymies_subscriptions')
                ->where('mollie_subscription_id', $subscriptionId)
                ->first();
        }

        // Geen subscriptionId = eerste betaling uit onboarding → zoek via metadata of customerId
        if (!$sub) {
            $metadata = $data['metadata'] ?? [];
            $customerId = $data['customerId'] ?? null;

            if (!empty($metadata['subscription_id'])) {
                $sub = DB::table('gymies_subscriptions')
                    ->where('id', (int) $metadata['subscription_id'])
                    ->first();
                $isFirstPayment = true;
            } elseif ($customerId) {
                $sub = DB::table('gymies_subscriptions')
                    ->where('mollie_customer_id', $customerId)
                    ->whereIn('status', ['pending', 'trialing'])
                    ->first();
                $isFirstPayment = true;
            }
        }

        if (!$sub) {
            return response()->json(['status' => 'subscription_not_found']);
        }

        // P-FIX-4: Verify customer ID matches to prevent webhook spoofing
        $webhookCustomerId = $data['customerId'] ?? null;
        if ($webhookCustomerId && $sub->mollie_customer_id !== $webhookCustomerId) {
            if (function_exists('logger')) {
                logger()->warning('Subscription webhook customer ID mismatch (potential spoofing attempt)', [
                    'subscription_id' => $sub->id,
                    'expected' => $sub->mollie_customer_id,
                    'received' => $webhookCustomerId,
                    'ip' => request()->ip(),
                ]);
            }
            return response()->json(['error' => 'Customer mismatch'], 403);
        }

        // P-FIX-3: Wrap payment record + subscription status in atomic transaction
        try {
            DB::transaction(function() use ($sub, $status, $data, $paymentId, $amountCents) {
                if (Schema::hasTable('gymies_subscription_payments')) {
                    $existing = DB::table('gymies_subscription_payments')
                        ->where('mollie_payment_id', $paymentId)
                        ->first();

                    if (!$existing) {
                        DB::table('gymies_subscription_payments')->insert([
                            'subscription_id' => (int) $sub->id,
                            'trainer_user_id' => (int) $sub->trainer_user_id,
                            'mollie_payment_id' => $paymentId,
                            'amount_cents' => $amountCents,
                            'status' => $status === 'paid' ? 'paid' : ($status === 'failed' ? 'failed' : 'pending'),
                            'failure_reason' => $status === 'failed' ? ($data['details']['failureReason'] ?? 'Onbekend') : null,
                            'paid_at' => $status === 'paid' ? now() : null,
                            'created_at' => now(),
                        ]);
                    } else {
                        DB::table('gymies_subscription_payments')->where('id', $existing->id)->update([
                            'status' => $status === 'paid' ? 'paid' : ($status === 'failed' ? 'failed' : 'pending'),
                            'failure_reason' => $status === 'failed' ? ($data['details']['failureReason'] ?? null) : null,
                            'paid_at' => $status === 'paid' ? now() : $existing->paid_at,
                        ]);
                    }
                }

                if ($status === 'paid') {
                    $newPeriodEnd = now()->addMonth()->toDateString();
                    $update = [
                        'status' => 'active',
                        'current_period_start' => now()->toDateString(),
                        'current_period_end' => $newPeriodEnd,
                        'updated_at' => now(),
                    ];
                    if (Schema::hasColumn('gymies_subscriptions', 'pending_plan_id') && $sub->pending_plan_id) {
                        $update['plan_id'] = (int) $sub->pending_plan_id;
                        $update['pending_plan_id'] = null;
                        $pendingPlan = DB::table('gymies_plans')->where('id', $sub->pending_plan_id)->first();
                        if ($pendingPlan && Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                            DB::table('gymies_trainer_profiles')
                                ->where('user_id', (int) $sub->trainer_user_id)
                                ->update(['subscription_plan' => $pendingPlan->slug]);

                            // PRO+: Auto-create ProPlusSettings when upgrading to pro_plus
                            if (($pendingPlan->slug === 'pro_plus' || $pendingPlan->slug === 'pro+')
                                && Schema::hasTable('gymies_trainer_pro_plus_settings')) {
                                $existing = DB::table('gymies_trainer_pro_plus_settings')
                                    ->where('trainer_user_id', (int) $sub->trainer_user_id)
                                    ->exists();
                                if (!$existing) {
                                    DB::table('gymies_trainer_pro_plus_settings')->insert([
                                        'trainer_user_id' => (int) $sub->trainer_user_id,
                                        'created_at' => now(),
                                        'updated_at' => now(),
                                    ]);
                                }
                            }
                        }
                    }
                    DB::table('gymies_subscriptions')->where('id', $sub->id)->update($update);
                } elseif ($status === 'failed') {
                    DB::table('gymies_subscriptions')->where('id', $sub->id)->update([
                        'status' => 'past_due',
                        'updated_at' => now(),
                    ]);

                    if (Schema::hasTable('gymies_notification_queue')) {
                        DB::table('gymies_notification_queue')->insert([
                            'user_id' => (int) $sub->trainer_user_id,
                            'channel' => 'in_app',
                            'event_type' => 'subscription_payment_failed',
                            'payload_json' => json_encode([
                                'message' => 'Je abonnementsbetaling is mislukt. Controleer je bankgegevens.',
                            ], JSON_UNESCAPED_UNICODE),
                            'scheduled_for' => now(),
                            'created_at' => now(),
                        ]);
                    }
                }
            });
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->critical('subscriptionWebhook DB transaction failed', [
                    'subscription_id' => $sub->id,
                    'payment_id' => $paymentId,
                    'status' => $status,
                    'error' => $e->getMessage(),
                ]);
            }
            return response()->json(['status' => 'transaction_failed'], 500);
        }

        // Na succesvolle EERSTE betaling: recurring Mollie subscription aanmaken
        if ($status === 'paid' && $isFirstPayment && $sub->mollie_customer_id && !$sub->mollie_subscription_id) {
            try {
                $recurringResult = $this->activateRecurringSubscription((int) $sub->id);
                if ($recurringResult['ok']) {
                    logger()->info('Recurring subscription aangemaakt na eerste betaling', [
                        'subscription_id' => $sub->id,
                        'mollie_subscription_id' => $recurringResult['mollie_subscription_id'] ?? null,
                    ]);
                } else {
                    logger()->warning('Recurring subscription aanmaken mislukt na eerste betaling', [
                        'subscription_id' => $sub->id,
                        'error' => $recurringResult['error'] ?? 'Onbekend',
                    ]);
                }
            } catch (\Throwable $recEx) {
                logger()->error('Recurring subscription exception na eerste betaling', [
                    'subscription_id' => $sub->id,
                    'error' => $recEx->getMessage(),
                ]);
            }
        }

        // Ambassador: registreer trainer-conversie bij eerste betaling (fire-and-forget, AFTER transaction)
        if ($status === 'paid') {
            try {
                if (class_exists(\App\Http\Controllers\Gymies\GymiesAmbassadorController::class) &&
                    \Illuminate\Support\Facades\Schema::hasColumn('gymies_subscriptions', 'ambassador_discount_code')) {
                    $ambCode = trim((string) ($sub->ambassador_discount_code ?? ''));
                    if ($ambCode !== '') {
                        \App\Http\Controllers\Gymies\GymiesAmbassadorController::recordTrainerConversion(
                            $ambCode,
                            (int) $sub->trainer_user_id
                        );
                    }
                }
            } catch (\Throwable $ambEx) {
                if (function_exists('logger')) {
                    logger()->warning('Gymies subscription webhook: ambassador trainer conversion failed (non-blocking)', [
                        'subscription_id' => $sub->id,
                        'error' => $ambEx->getMessage(),
                    ]);
                }
            }
        }

        return response()->json(['status' => 'processed']);
    }

    /**
     * Maak Mollie Customer + SEPA mandaat + Subscription aan voor een trainer.
     * Wordt aangeroepen vanuit de onboarding flow.
     */
    public function createSubscriptionForTrainer(int $trainerUserId, int $planId, string $ambassadorCode = ''): array
    {
        try {
            return $this->createSubscriptionForTrainerInternal($trainerUserId, $planId, $ambassadorCode);
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('createSubscriptionForTrainer exception', [
                    'trainer_user_id' => $trainerUserId,
                    'plan_id' => $planId,
                    'error' => $e->getMessage(),
                ]);
            }
            return ['ok' => false, 'error' => 'Abonnement aanmaken mislukt. Controleer Mollie-configuratie en database-migraties.'];
        }
    }

    private function getUpsellSetting(string $key, string $default): string
    {
        if (!Schema::hasTable('gymies_system_settings')) {
            return $default;
        }
        $row = DB::table('gymies_system_settings')->where('setting_key', $key)->first();
        return $row ? (string) $row->setting_value : $default;
    }

    /**
     * STAP 1 — Controleer of deze trainer al ooit een subscription record heeft gehad
     * (trial, active, expired, cancelled — doet er niet toe).
     * Als ja: return fout. Elke trainer mag maar 1x trialen.
     */
    private function createSubscriptionForTrainerInternal(int $trainerUserId, int $planId, string $ambassadorCode = ''): array
    {
        $user = DB::table('gymies_users')->where('id', $trainerUserId)->first();
        if (!$user) {
            return ['ok' => false, 'error' => 'Trainer niet gevonden.'];
        }

        $plan = DB::table('gymies_plans')->where('id', $planId)->where('is_active', 1)->first();
        if (!$plan) {
            return ['ok' => false, 'error' => 'Plan niet gevonden.'];
        }

        // --- STAP 1: Check op actieve/lopende subscriptions ---
        // Voorkom dubbele actieve subscriptions. Cancelled/expired mag opnieuw subscriben.
        if (Schema::hasTable('gymies_subscriptions')) {
            $existingSubscription = DB::table('gymies_subscriptions')
                ->where('trainer_user_id', $trainerUserId)
                ->whereIn('status', ['active', 'trialing', 'pending'])
                ->first();

            if ($existingSubscription) {
                return ['ok' => false, 'error' => 'Je hebt al een actief of lopend abonnement.'];
            }
        }

        $planSlug = (string) ($plan->slug ?? '');

        // --- STAP 2: trial_source en trial_days bepalen (CASCADE) ---
        $trialDays = 0;
        $trialSource = 'standard';

        // Partner check
        $isPartner = (int) ($user->is_partner ?? 0) === 1;
        if ($isPartner) {
            $partnerTrialDays = (int) $this->getUpsellSetting('upsell_partner_trial_days', '90');
            $trialDays = $partnerTrialDays > 0 ? $partnerTrialDays : (int) $this->getUpsellSetting('upsell_standard_trial_days', '30');
            $trialSource = 'partner';
        } else {
            // Referral check
            $hasReferral = false;
            if (Schema::hasTable('gymies_referrals')) {
                $referral = DB::table('gymies_referrals')
                    ->where('referred_user_id', $trainerUserId)
                    ->where('status', 'completed')
                    ->first();
                $hasReferral = $referral !== null;
            }

            if ($hasReferral) {
                $standardTrialDays = (int) $this->getUpsellSetting('upsell_standard_trial_days', '30');
                $referralBonusDays = (int) $this->getUpsellSetting('upsell_referral_bonus_days', '30');
                $trialDays = $standardTrialDays + $referralBonusDays;
                $trialSource = 'referral';
            } else {
                // Pro plan check
                $proTrialDays = (int) $this->getUpsellSetting('upsell_pro_trial_days', '14');
                $standardTrialDays = (int) $this->getUpsellSetting('upsell_standard_trial_days', '30');

                if ($planSlug === 'pro' && $proTrialDays > 0) {
                    $trialDays = max($proTrialDays, $standardTrialDays);
                    $trialSource = 'pro_trial';
                } else {
                    $trialDays = $standardTrialDays;
                    $trialSource = 'standard';
                }
            }
        }

        // --- STAP 3: Subscription record aanmaken ---
        $trialEndsAt = now()->addDays($trialDays);

        $subTable = 'gymies_subscriptions';
        $columns = Schema::hasTable($subTable) ? Schema::getColumnListing($subTable) : [];
        $hasTrainerCol = in_array('trainer_user_id', $columns, true);
        $hasClientCol = in_array('client_user_id', $columns, true);
        if (!$hasTrainerCol && !$hasClientCol) {
            return ['ok' => false, 'error' => 'Tabel gymies_subscriptions mist trainer_user_id.'];
        }

        // Status begint als 'pending' — wordt 'active' na Mollie betaling
        $row = [
            'plan_id' => (int) $planId,
            'status' => 'pending',
            'created_at' => now(),
            'updated_at' => now(),
        ];

        if ($hasTrainerCol) {
            $row['trainer_user_id'] = (int) $trainerUserId;
        } elseif ($hasClientCol) {
            $row['client_user_id'] = (int) $trainerUserId;
        }

        // Zet trial_source in het record (nieuwe kolom)
        if (in_array('trial_source', $columns, true)) {
            $row['trial_source'] = $trialSource;
        }

        // Zet trial_ends_at
        if (in_array('trial_ends_at', $columns, true)) {
            $row['trial_ends_at'] = $trialEndsAt;
        }

        // Zet current_period_start en current_period_end
        if (in_array('current_period_start', $columns, true)) {
            $row['current_period_start'] = now()->toDateString();
        }
        if (in_array('current_period_end', $columns, true)) {
            $row['current_period_end'] = now()->addMonth()->toDateString();
        }

        // Ambassador-kortingscode opslaan (self-healing: alleen als kolom bestaat)
        // S-037: IDOR check — code moet gekoppeld zijn aan de trainer of platform-brede code zijn
        $cleanCode = strtoupper(trim($ambassadorCode));
        if ($cleanCode !== '' && in_array('ambassador_discount_code', $columns, true)) {
            if (\Illuminate\Support\Facades\Schema::hasTable('gymies_ambassadors')) {
                $ambRow = DB::table('gymies_ambassadors')
                    ->where('discount_code', $cleanCode)
                    ->where('is_active', 1)
                    ->first();
                if ($ambRow) {
                    // Check: als trainer_user_id kolom bestaat, moet het NULL (platform-brede) OF overeenkomt met trainer
                    $trainerIdCol = \Illuminate\Support\Facades\Schema::hasColumn('gymies_ambassadors', 'trainer_user_id')
                        ? (int) ($ambRow->trainer_user_id ?? 0)
                        : 0;
                    if ($trainerIdCol === 0 || $trainerIdCol === (int) $trainerUserId) {
                        $row['ambassador_discount_code'] = $cleanCode;
                    }
                }
            }
        }

        $subId = DB::table($subTable)->insertGetId($row);

        // Update trainer profiel met het plan
        if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
            DB::table('gymies_trainer_profiles')
                ->where('user_id', (int) $trainerUserId)
                ->update(['subscription_plan' => $planSlug]);
        }

        // --- STAP 4: Mollie checkout starten voor directe betaling ---
        $apiKey = $this->getMollieApiKey();
        if ($apiKey === '') {
            // Fallback: geen Mollie key → trial starten
            DB::table($subTable)->where('id', $subId)->update(['status' => 'trialing']);
            return [
                'ok' => true,
                'subscription_id' => (int) $subId,
                'checkout_url' => null,
                'trial_or_referral' => true,
                'trial_source' => $trialSource,
                'trial_days' => (int) $trialDays,
                'trial_ends_at' => $trialEndsAt->toIso8601String(),
            ];
        }

        $priceCents = (int) ($plan->price_cents_per_month ?? 0);
        if ($priceCents < 1 || $priceCents > 100000 * 100) {
            DB::table($subTable)->where('id', $subId)->update(['status' => 'trialing']);
            return [
                'ok' => true,
                'subscription_id' => (int) $subId,
                'checkout_url' => null,
                'trial_or_referral' => true,
                'trial_source' => $trialSource,
                'trial_days' => (int) $trialDays,
                'trial_ends_at' => $trialEndsAt->toIso8601String(),
            ];
        }

        // 4a. Mollie Customer aanmaken
        try {
            $customerResponse = Http::withToken($apiKey)->timeout(15)->post(self::MOLLIE_API . '/customers', [
                'name' => $user->display_name ?? (($user->first_name ?? '') . ' ' . ($user->last_name ?? '')),
                'email' => $user->email ?? '',
            ]);

            if (!$customerResponse->successful()) {
                logger()->error('Mollie customer aanmaken mislukt (onboarding)', [
                    'trainer_user_id' => $trainerUserId,
                    'response' => $customerResponse->body(),
                ]);
                // Fallback trial
                DB::table($subTable)->where('id', $subId)->update(['status' => 'trialing']);
                return [
                    'ok' => true,
                    'subscription_id' => (int) $subId,
                    'checkout_url' => null,
                    'trial_or_referral' => true,
                    'trial_source' => $trialSource,
                    'trial_days' => (int) $trialDays,
                    'trial_ends_at' => $trialEndsAt->toIso8601String(),
                ];
            }

            $customerId = $customerResponse->json('id');

            // 4b. Eerste betaling met mandaat (iDEAL/SEPA) voor recurring
            $amountEur = $this->centsToCurrencyString($priceCents);
            // Redirect naar Flutter web app (gymiesapp.nl), webhook naar API (gymies.nl)
            $appDomain = rtrim(config('gymies.flutter_web_url', env('GYMIES_APP_URL', 'https://gymiesapp.nl')), '/');
            $apiDomain = rtrim(config('app.url', 'https://www.gymies.nl'), '/');
            $redirectUrl = $appDomain . '/trainer?payment=success';
            $webhookUrl = $apiDomain . '/api/gymies/webhooks/mollie-subscription';

            $firstPaymentResponse = Http::withToken($apiKey)->timeout(15)->post(self::MOLLIE_API . '/payments', [
                'amount' => ['currency' => 'EUR', 'value' => $amountEur],
                'customerId' => $customerId,
                'sequenceType' => 'first',
                'description' => 'Gymies ' . ($plan->name ?? $planSlug) . ' - Eerste maandbetaling',
                'redirectUrl' => $redirectUrl,
                'webhookUrl' => $webhookUrl,
                'metadata' => [
                    'subscription_id' => (int) $subId,
                    'trainer_user_id' => (int) $trainerUserId,
                    'plan_id' => (int) $planId,
                    'plan_slug' => $planSlug,
                ],
            ]);

            if (!$firstPaymentResponse->successful()) {
                logger()->error('Mollie eerste betaling mislukt (onboarding)', [
                    'trainer_user_id' => $trainerUserId,
                    'response' => $firstPaymentResponse->body(),
                ]);
                // Fallback trial
                DB::table($subTable)->where('id', $subId)->update(['status' => 'trialing']);
                return [
                    'ok' => true,
                    'subscription_id' => (int) $subId,
                    'checkout_url' => null,
                    'trial_or_referral' => true,
                    'trial_source' => $trialSource,
                    'trial_days' => (int) $trialDays,
                    'trial_ends_at' => $trialEndsAt->toIso8601String(),
                ];
            }

            $paymentData = $firstPaymentResponse->json();
            $checkoutUrl = $paymentData['_links']['checkout']['href'] ?? null;
            $molliePaymentId = $paymentData['id'] ?? null;

            // 4c. Subscription record bijwerken met Mollie info
            $updateData = [
                'mollie_customer_id' => $customerId,
                'updated_at' => now(),
            ];
            if (in_array('mollie_customer_id', $columns, true)) {
                DB::table($subTable)->where('id', $subId)->update($updateData);
            }

            logger()->info('Mollie checkout gestart voor trainer onboarding', [
                'trainer_user_id' => $trainerUserId,
                'plan' => $planSlug,
                'amount' => $amountEur,
                'mollie_customer_id' => $customerId,
                'mollie_payment_id' => $molliePaymentId,
                'checkout_url' => $checkoutUrl,
            ]);

            return [
                'ok' => true,
                'subscription_id' => (int) $subId,
                'checkout_url' => $checkoutUrl,
                'trial_or_referral' => false,
                'trial_source' => $trialSource,
                'trial_days' => (int) $trialDays,
                'mollie_payment_id' => $molliePaymentId,
            ];

        } catch (\Throwable $e) {
            logger()->error('Mollie onboarding checkout exception', [
                'trainer_user_id' => $trainerUserId,
                'error' => $e->getMessage(),
            ]);
            // Fallback: trial starten als Mollie helemaal faalt
            DB::table($subTable)->where('id', $subId)->update(['status' => 'trialing']);
            return [
                'ok' => true,
                'subscription_id' => (int) $subId,
                'checkout_url' => null,
                'trial_or_referral' => true,
                'trial_source' => $trialSource,
                'trial_days' => (int) $trialDays,
                'trial_ends_at' => $trialEndsAt->toIso8601String(),
            ];
        }
    }

    /**
     * Wordt aangeroepen NADAT de trial verloopt.
     * Zet Mollie customer + eerste betaling op.
     */
    private function createMollieSubscriptionForTrainer(int $trainerUserId, int $planId): array
    {
        $user = DB::table('gymies_users')->where('id', $trainerUserId)->first();
        if (!$user) {
            return ['ok' => false, 'error' => 'Trainer niet gevonden.'];
        }

        $plan = DB::table('gymies_plans')->where('id', $planId)->where('is_active', 1)->first();
        if (!$plan) {
            return ['ok' => false, 'error' => 'Plan niet gevonden.'];
        }

        $apiKey = $this->getMollieApiKey();
        if ($apiKey === '') {
            return ['ok' => false, 'error' => 'Mollie API key niet geconfigureerd.'];
        }

        $priceCents = (int) ($plan->price_cents_per_month ?? 0);
        // S-038: Validate amount — no negative or excessive amounts (max €100.000/month)
        if ($priceCents < 1 || $priceCents > 100000 * 100) {
            return ['ok' => false, 'error' => 'Plan heeft geen geldige prijs (price_cents_per_month).'];
        }

        // 1. Mollie Customer aanmaken
        $customerResponse = Http::withToken($apiKey)->timeout(15)->post(self::MOLLIE_API . '/customers', [
            'name' => $user->display_name ?? ($user->first_name . ' ' . $user->last_name),
            'email' => $user->email,
        ]);

        if (!$customerResponse->successful()) {
            return ['ok' => false, 'error' => 'Mollie customer aanmaken mislukt.'];
        }

        $customerId = $customerResponse->json('id');

        // 2. Eerste betaling met mandaat (SEPA of iDEAL) om mandaat te verkrijgen
        // P-FIX-5: Use robust conversion helper
        $amountEur = $this->centsToCurrencyString($priceCents);
        $firstPaymentResponse = Http::withToken($apiKey)->timeout(15)->post(self::MOLLIE_API . '/payments', [
            'amount' => ['currency' => 'EUR', 'value' => $amountEur],
            'customerId' => $customerId,
            'sequenceType' => 'first',
            'description' => 'Gymies ' . $plan->name . ' - Eerste betaling',
            'redirectUrl' => rtrim(config('app.url', ''), '/') . '/trainer',
            'webhookUrl' => rtrim(config('app.url', ''), '/') . '/api/gymies/webhooks/mollie-subscription',
        ]);

        if (!$firstPaymentResponse->successful()) {
            return ['ok' => false, 'error' => 'Eerste betaling aanmaken mislukt.'];
        }

        $firstPaymentData = $firstPaymentResponse->json();
        $checkoutUrl = $firstPaymentData['_links']['checkout']['href'] ?? null;

        // 3. Subscription record updaten met Mollie info
        $subTable = 'gymies_subscriptions';
        $columns = Schema::hasTable($subTable) ? Schema::getColumnListing($subTable) : [];

        $updateData = [
            'mollie_customer_id' => $customerId,
            'updated_at' => now(),
        ];

        if (in_array('current_period_start', $columns, true)) {
            $updateData['current_period_start'] = now()->toDateString();
        }
        if (in_array('current_period_end', $columns, true)) {
            $updateData['current_period_end'] = now()->addMonth()->toDateString();
        }

        DB::table($subTable)
            ->where('trainer_user_id', (int) $trainerUserId)
            ->where('plan_id', (int) $planId)
            ->where('status', 'trialing')
            ->update($updateData);

        return [
            'ok' => true,
            'mollie_customer_id' => $customerId,
            'checkout_url' => $checkoutUrl,
        ];
    }

    /**
     * Na succesvolle eerste betaling: maak recurring subscription aan.
     */
    public function activateRecurringSubscription(int $subscriptionId): array
    {
        $sub = DB::table('gymies_subscriptions')->where('id', $subscriptionId)->first();
        if (!$sub || !$sub->mollie_customer_id) {
            return ['ok' => false, 'error' => 'Subscription niet gevonden.'];
        }

        $plan = DB::table('gymies_plans')->where('id', $sub->plan_id)->first();
        if (!$plan) {
            return ['ok' => false, 'error' => 'Plan niet gevonden.'];
        }

        $apiKey = $this->getMollieApiKey();
        // P-FIX-5: Use robust conversion helper
        $amountEur = $this->centsToCurrencyString((int) $plan->price_cents_per_month);

        $response = Http::withToken($apiKey)->timeout(15)->post(
            self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/subscriptions",
            [
                'amount' => ['currency' => 'EUR', 'value' => $amountEur],
                'interval' => '1 month',
                'description' => 'Gymies ' . $plan->name . ' Maandabonnement',
                'webhookUrl' => rtrim(config('app.url', ''), '/') . '/api/gymies/webhooks/mollie-subscription',
            ]
        );

        if (!$response->successful()) {
            return ['ok' => false, 'error' => 'Recurring subscription aanmaken mislukt bij Mollie.'];
        }

        $mollieSubId = $response->json('id');

        $mandates = Http::withToken($apiKey)->timeout(15)
            ->get(self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/mandates");
        $mandateId = $mandates->json('_embedded.mandates.0.id') ?? null;

        DB::table('gymies_subscriptions')->where('id', $subscriptionId)->update([
            'mollie_subscription_id' => $mollieSubId,
            'mollie_mandate_id' => $mandateId,
            'status' => 'active',
            'updated_at' => now(),
        ]);

        return ['ok' => true, 'mollie_subscription_id' => $mollieSubId];
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
     * P-FIX-5: Robust conversion from cents (integer) to EUR currency string.
     * Example: 1234 cents → "12.34"
     */
    private function centsToCurrencyString(int $cents): string
    {
        return number_format($cents / 100, 2, '.', '');
    }

    /**
     * P-FIX-5: Robust conversion from EUR currency string to cents (integer).
     * Handles strings like "12.34", "12", "12.3", etc.
     * Example: "12.34" → 1234 cents
     */
    private function currencyStringToCents(string $amount): int
    {
        return (int) round((float) $amount * 100);
    }
}
