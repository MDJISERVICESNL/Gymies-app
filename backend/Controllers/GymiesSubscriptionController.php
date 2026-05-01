<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Services\SubscriptionBillingService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;

final class GymiesSubscriptionController extends Controller
{
    private const MOLLIE_API = 'https://api.mollie.com/v2';

    use AssignSubscriptionTrait;
    use ChangeSubscriptionTrait;
    use SubscriptionPaymentTrait {
        SubscriptionPaymentTrait::getSubscriptionMollieApiKey as protected getSubscriptionMollieApiKeyFromTrait;
    }
    use ExpireSubscriptionTrialsTrait;
    use SubscriptionWebhookTrait;

    public function availablePlans(Request $request): JsonResponse
    {
        if (!Schema::hasTable('gymies_plans')) {
            return response()->json(['plans' => []]);
        }

        $plans = DB::table('gymies_plans')
            ->where('is_active', 1)
            ->orderBy('price_cents_per_month')
            ->get();

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
            ->whereIn('s.status', ['active', 'trialing', 'past_due', 'paused']);

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

        $sub = DB::table('gymies_subscriptions')
            ->where('trainer_user_id', (int) $user->id)
            ->whereIn('status', ['active', 'trialing', 'past_due'])
            ->first();

        if (!$sub) {
            return response()->json(['message' => 'Geen actief abonnement gevonden.'], 404);
        }

        $request->validate(['reason' => 'nullable|string|max:500']);

        $apiKey = $this->getMollieApiKey();
        if ($apiKey !== '' && $sub->mollie_customer_id && $sub->mollie_subscription_id) {
            $response = Http::withToken($apiKey)
                ->timeout(15)
                ->delete(self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/subscriptions/{$sub->mollie_subscription_id}");

            if (!$response->successful() && $response->status() !== 404) {
                return response()->json(['message' => 'Mollie opzegging mislukt. Probeer het later opnieuw.'], 502);
            }
        }

        DB::table('gymies_subscriptions')->where('id', $sub->id)->update([
            'status' => 'cancelled',
            'cancelled_at' => now(),
            'cancel_reason' => $request->input('reason'),
            'updated_at' => now(),
        ]);

        if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
            DB::table('gymies_trainer_profiles')
                ->where('user_id', (int) $user->id)
                ->update(['subscription_plan' => null]);
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

        $request->validate(['plan_slug' => 'required|string|in:starter,pro,studio']);

        $slug = strtolower(trim((string) $request->input('plan_slug')));
        $plan = DB::table('gymies_plans')
            ->whereRaw('LOWER(TRIM(slug)) = ?', [$slug])
            ->where('is_active', 1)
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

        $apiKey = $this->getMollieApiKey();
        $hasMollie = $apiKey !== '' && $sub->mollie_customer_id && $sub->mollie_subscription_id;

        if ($hasMollie) {
            $priceCents = (int) ($plan->price_cents_per_month ?? 0);
            if ($priceCents <= 0) {
                return response()->json(['message' => 'Plan heeft geen geldige prijs.'], 400);
            }
            $amountEur = number_format($priceCents / 100, 2, '.', '');
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
        }

        if (Schema::hasColumn('gymies_subscriptions', 'pending_plan_id')) {
            DB::table('gymies_subscriptions')->where('id', $sub->id)->update([
                'pending_plan_id' => (int) $plan->id,
                'updated_at' => now(),
            ]);
        } else {
            // Fallback: direct wijzigen als pending_plan_id niet bestaat (trialing zonder Mollie)
            DB::table('gymies_subscriptions')->where('id', $sub->id)->update([
                'plan_id' => (int) $plan->id,
                'updated_at' => now(),
            ]);
            if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                DB::table('gymies_trainer_profiles')
                    ->where('user_id', (int) $user->id)
                    ->update(['subscription_plan' => $plan->slug]);
            }
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

    // ─── Pause / Resume ────────────────────────────────────────────

    /**
     * Pauzeer abonnement: Mollie subscription wordt gepauzeerd, geen incasso's meer.
     * Trainer kan pauzeren als status active of trialing is.
     */
    public function pauseSubscription(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        GymiesSchemaEnsure::subscriptionPauseColumns();

        $sub = DB::table('gymies_subscriptions')
            ->where('trainer_user_id', (int) $user->id)
            ->whereIn('status', ['active', 'trialing'])
            ->first();

        if (!$sub) {
            return response()->json(['message' => 'Geen actief abonnement gevonden om te pauzeren.'], 404);
        }

        // Check of al gepauzeerd
        if (Schema::hasColumn('gymies_subscriptions', 'paused_at') && !empty($sub->paused_at)) {
            return response()->json(['message' => 'Abonnement is al gepauzeerd.'], 422);
        }

        $apiKey = $this->getMollieApiKey();
        if ($apiKey !== '' && $sub->mollie_customer_id && $sub->mollie_subscription_id) {
            // Mollie: PATCH subscription met status=paused (beschikbaar sinds Mollie v2)
            // Alternatief: DELETE + re-create bij resume. We gebruiken cancel + bewaar state.
            $response = Http::withToken($apiKey)
                ->timeout(15)
                ->delete(self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/subscriptions/{$sub->mollie_subscription_id}");

            if (!$response->successful() && $response->status() !== 404) {
                return response()->json(['message' => 'Mollie pauzering mislukt. Probeer later opnieuw.'], 502);
            }
        }

        $update = [
            'status' => 'paused',
            'updated_at' => now(),
        ];
        if (Schema::hasColumn('gymies_subscriptions', 'paused_at')) {
            $update['paused_at'] = now();
        }
        DB::table('gymies_subscriptions')->where('id', $sub->id)->update($update);

        return response()->json([
            'ok' => true,
            'message' => 'Abonnement gepauzeerd. Er worden geen incasso\'s meer gedaan tot je hervat.',
        ]);
    }

    /**
     * Hervat gepauzeerd abonnement: maak een nieuwe Mollie subscription aan.
     */
    public function resumeSubscription(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        GymiesSchemaEnsure::subscriptionPauseColumns();

        $sub = DB::table('gymies_subscriptions')
            ->where('trainer_user_id', (int) $user->id)
            ->where('status', 'paused')
            ->first();

        if (!$sub) {
            return response()->json(['message' => 'Geen gepauzeerd abonnement gevonden.'], 404);
        }

        $plan = DB::table('gymies_plans')->where('id', (int) $sub->plan_id)->first();
        if (!$plan) {
            return response()->json(['message' => 'Plan niet gevonden.'], 404);
        }

        $apiKey = $this->getMollieApiKey();
        $newMollieSubId = null;

        if ($apiKey !== '' && $sub->mollie_customer_id && $sub->mollie_mandate_id) {
            // Maak nieuwe Mollie subscription aan
            $priceCents = (int) ($plan->price_cents_per_month ?? 0);
            $amountEur = number_format($priceCents / 100, 2, '.', '');

            $webhookUrl = rtrim(config('app.url', ''), '/') . '/api/gymies/webhooks/mollie-subscription';

            $response = Http::withToken($apiKey)
                ->timeout(15)
                ->post(self::MOLLIE_API . "/customers/{$sub->mollie_customer_id}/subscriptions", [
                    'amount' => ['currency' => 'EUR', 'value' => $amountEur],
                    'interval' => '1 month',
                    'description' => 'Gymies ' . $plan->name . ' Maandabonnement',
                    'mandateId' => $sub->mollie_mandate_id,
                    'webhookUrl' => $webhookUrl,
                ]);

            if (!$response->successful()) {
                if (function_exists('logger')) {
                    logger()->warning('Gymies subscription resume failed', ['body' => $response->json()]);
                }
                return response()->json(['message' => 'Mollie hervatting mislukt. Probeer later opnieuw.'], 502);
            }

            $newMollieSubId = $response->json()['id'] ?? null;
        }

        $update = [
            'status' => 'active',
            'current_period_start' => now(),
            'current_period_end' => now()->addMonth(),
            'updated_at' => now(),
        ];
        if ($newMollieSubId) {
            $update['mollie_subscription_id'] = $newMollieSubId;
        }
        if (Schema::hasColumn('gymies_subscriptions', 'resumed_at')) {
            $update['resumed_at'] = now();
        }
        DB::table('gymies_subscriptions')->where('id', $sub->id)->update($update);

        if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
            DB::table('gymies_trainer_profiles')
                ->where('user_id', (int) $user->id)
                ->update(['subscription_plan' => $plan->slug]);
        }

        return response()->json([
            'ok' => true,
            'message' => 'Abonnement hervat! Je hebt weer volledige toegang.',
        ]);
    }

    /**
     * Betalingshistorie: laatste 12 maanden subscription payments.
     */
    public function paymentHistory(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        if (!Schema::hasTable('gymies_subscription_payments')) {
            return response()->json(['data' => []]);
        }

        $payments = DB::table('gymies_subscription_payments')
            ->where('trainer_user_id', (int) $user->id)
            ->orderByDesc('created_at')
            ->limit(24)
            ->get();

        return response()->json([
            'data' => $payments->map(fn ($p) => [
                'id' => (string) $p->id,
                'mollie_payment_id' => $p->mollie_payment_id ?? null,
                'amount_cents' => (int) $p->amount_cents,
                'status' => $p->status,
                'failure_reason' => $p->failure_reason ?? null,
                'paid_at' => $p->paid_at,
                'created_at' => $p->created_at,
            ])->all(),
        ]);
    }

    /**
     * Mollie subscription webhook: verwerkt betalingsgebeurtenissen.
     *
     * SECURITY NOTE: Mollie webhook signature verification should be implemented to validate
     * that webhook calls truly originate from Mollie. This requires verifying the X-Mollie-Signature
     * header against the webhook request body using Mollie's public key. See:
     * https://docs.mollie.com/guides/handling-webhooks#webhook-verification
     */
    public function subscriptionWebhook(Request $request): JsonResponse
    {
        // Mollie webhook signature verificatie
        $signatureHeader = $request->header('X-Mollie-Signature');
        if ($signatureHeader) {
            $webhookSecret = config('gymies.mollie_webhook_secret', env('MOLLIE_WEBHOOK_SECRET', ''));
            if ($webhookSecret !== '') {
                $computedSignature = hash_hmac('sha256', $request->getContent(), $webhookSecret);
                if (!hash_equals($computedSignature, $signatureHeader)) {
                    if (function_exists('logger')) {
                        logger()->warning('Mollie webhook: ongeldige signature', [
                            'ip' => $request->ip(),
                            'timestamp' => now()->toIso8601String(),
                        ]);
                    }
                    return response()->json(['status' => 'invalid_signature'], 403);
                }
            }
        } else {
            // Signature header ontbreekt — in productie strenger afhandelen
            $webhookSecret = config('gymies.mollie_webhook_secret', env('MOLLIE_WEBHOOK_SECRET', ''));
            if ($webhookSecret !== '') {
                // Secret is geconfigureerd maar signature ontbreekt — verdacht
                \Log::warning('Mollie subscription webhook zonder signature terwijl secret geconfigureerd is', [
                    'ip' => $request->ip(),
                    'user_agent' => $request->userAgent(),
                    'timestamp' => now()->toIso8601String(),
                ]);
            } else {
                \Log::info('Mollie subscription webhook zonder signature (geen secret geconfigureerd)', [
                    'ip' => $request->ip(),
                ]);
            }
        }

        $paymentId = $request->input('id');
        if (!$paymentId || !is_string($paymentId)) {
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
        if (!in_array($status, ['paid', 'open', 'pending', 'failed', 'canceled', 'cancelled', 'expired', 'refunded', 'charged_back', 'authorized'], true)) {
            \Log::warning('Onbekende Mollie subscription status ontvangen', [
                'original_status' => $status,
                'payment_id' => $paymentId,
            ]);
        }
        $subscriptionId = $data['subscriptionId'] ?? null;
        $amountCents = isset($data['amount']['value']) ? (int) round((float) $data['amount']['value'] * 100) : 0;

        if (!$subscriptionId) {
            return response()->json(['status' => 'no_subscription_id']);
        }

        $sub = DB::table('gymies_subscriptions')
            ->where('mollie_subscription_id', $subscriptionId)
            ->first();

        if (!$sub) {
            return response()->json(['status' => 'subscription_not_found']);
        }

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
                }
            }
            DB::table('gymies_subscriptions')->where('id', $sub->id)->update($update);

            // Ambassador trainer-conversie: bij eerste betaalde subscriptie
            // Check of dit de eerste 'paid' payment is voor deze trainer
            try {
                $paidCount = 0;
                if (Schema::hasTable('gymies_subscription_payments')) {
                    $paidCount = DB::table('gymies_subscription_payments')
                        ->where('trainer_user_id', (int) $sub->trainer_user_id)
                        ->where('status', 'paid')
                        ->count();
                }
                // Alleen bij eerste betaling (= 1, want we hebben er net eentje geinsert)
                if ($paidCount <= 1) {
                    // Zoek of trainer een promo/referral code heeft gebruikt bij registratie
                    $trainerUser = DB::table('gymies_users')
                        ->where('id', (int) $sub->trainer_user_id)
                        ->first(['id']);
                    if ($trainerUser && Schema::hasTable('gymies_referrals')) {
                        $referral = DB::table('gymies_referrals')
                            ->where('referred_user_id', (int) $trainerUser->id)
                            ->where('status', 'completed')
                            ->first(['referral_code']);
                        if ($referral) {
                            GymiesAmbassadorController::recordTrainerConversion(
                                (string) $referral->referral_code,
                                (int) $trainerUser->id
                            );
                        }
                    }
                    // Ook checken of er een directe ambassador-link is via gymies_ambassadors
                    if ($trainerUser && Schema::hasTable('gymies_ambassadors')) {
                        // Kijk of de trainer via een ambassador-code is geregistreerd
                        $ambConvExists = Schema::hasTable('gymies_ambassador_conversions')
                            && DB::table('gymies_ambassador_conversions')
                                ->where('referred_user_id', (int) $trainerUser->id)
                                ->where('conversion_type', 'trainer_signup')
                                ->exists();
                        // Als er al een conversie is, hoeven we niks te doen
                        if (!$ambConvExists) {
                            GymiesAmbassadorController::linkUserToAmbassador((int) $trainerUser->id, '');
                        }
                    }
                }
            } catch (\Throwable $ambEx) {
                if (function_exists('logger')) {
                    logger()->warning('Subscription webhook: ambassador trainer conversion failed', ['error' => $ambEx->getMessage()]);
                }
            }
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

        return response()->json(['status' => 'processed']);
    }

    /**
     * Maak Mollie Customer + SEPA mandaat + Subscription aan voor een trainer.
     * Wordt aangeroepen vanuit de onboarding flow.
     */
    public function createSubscriptionForTrainer(int $trainerUserId, int $planId): array
    {
        try {
            return $this->createSubscriptionForTrainerInternal($trainerUserId, $planId);
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

    private function createSubscriptionForTrainerInternal(int $trainerUserId, int $planId): array
    {
        $user = DB::table('gymies_users')->where('id', $trainerUserId)->first();
        if (!$user) {
            return ['ok' => false, 'error' => 'Trainer niet gevonden.'];
        }

        $plan = DB::table('gymies_plans')->where('id', $planId)->where('is_active', 1)->first();
        if (!$plan) {
            return ['ok' => false, 'error' => 'Plan niet gevonden.'];
        }

        $planSlug = (string) ($plan->slug ?? '');
        $proTrialDays = (int) $this->getUpsellSetting('upsell_pro_trial_days', '14');
        $referralFreeMonths = (int) $this->getUpsellSetting('upsell_referral_free_months', '1');

        // Heeft deze trainer een geldige referral (uitgenodigd door collega)?
        $hasReferral = false;
        if (Schema::hasTable('gymies_referrals') && $referralFreeMonths > 0) {
            $referral = DB::table('gymies_referrals')
                ->where('referred_user_id', $trainerUserId)
                ->where('status', 'completed')
                ->first();
            $hasReferral = $referral !== null;
        }

        // Pro-trial: nieuwe trainer kiest Pro → X dagen gratis (geen Mollie, alleen DB)
        $useProTrial = ($planSlug === 'pro' && $proTrialDays > 0);
        // Referral: uitgenodigde trainer → X maanden gratis
        $useReferralFree = ($hasReferral && $referralFreeMonths > 0);

        if ($useProTrial || $useReferralFree) {
            $trialDays = $useProTrial ? $proTrialDays : 0;
            $referralDays = $useReferralFree ? ($referralFreeMonths * 30) : 0;
            $freeDays = max($trialDays, $referralDays);
            $trialEndsAt = now()->addDays($freeDays);

            $subTable = 'gymies_subscriptions';
            $columns = Schema::hasTable($subTable) ? Schema::getColumnListing($subTable) : [];
            $hasTrainerCol = in_array('trainer_user_id', $columns, true);
            $hasClientCol = in_array('client_user_id', $columns, true);
            if (!$hasTrainerCol && !$hasClientCol) {
                return ['ok' => false, 'error' => 'Tabel gymies_subscriptions mist trainer_user_id.'];
            }

            $row = [
                'plan_id' => $planId,
                'status' => 'trialing',
                'created_at' => now(),
                'updated_at' => now(),
            ];
            if ($hasTrainerCol) {
                $row['trainer_user_id'] = $trainerUserId;
            } else {
                $row['client_user_id'] = $trainerUserId;
            }
            if (in_array('trial_ends_at', $columns, true)) {
                $row['trial_ends_at'] = $trialEndsAt;
            }
            if (in_array('current_period_start', $columns, true)) {
                $row['current_period_start'] = now()->toDateString();
            }
            if (in_array('current_period_end', $columns, true)) {
                $row['current_period_end'] = $trialEndsAt->toDateString();
            }

            $subId = DB::table($subTable)->insertGetId($row);

            if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                DB::table('gymies_trainer_profiles')
                    ->where('user_id', $trainerUserId)
                    ->update(['subscription_plan' => $planSlug]);
            }

            return [
                'ok' => true,
                'subscription_id' => $subId,
                'checkout_url' => null,
                'trial_or_referral' => true,
                'trial_ends_at' => $trialEndsAt->toIso8601String(),
            ];
        }

        // Normale flow: Mollie customer + eerste betaling
        $apiKey = $this->getMollieApiKey();
        if ($apiKey === '') {
            return ['ok' => false, 'error' => 'Mollie API key niet geconfigureerd.'];
        }

        $priceCents = (int) ($plan->price_cents_per_month ?? 0);
        if ($priceCents <= 0) {
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
        $amountEur = number_format($priceCents / 100, 2, '.', '');
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

        // 3. Subscription record aanmaken — alleen kolommen die bestaan (oude schema = client_user_id)
        $subTable = 'gymies_subscriptions';
        $columns = Schema::hasTable($subTable) ? Schema::getColumnListing($subTable) : [];
        $hasTrainerCol = in_array('trainer_user_id', $columns, true);
        $hasClientCol = in_array('client_user_id', $columns, true);
        if (!$hasTrainerCol && !$hasClientCol) {
            return ['ok' => false, 'error' => 'Tabel gymies_subscriptions mist trainer_user_id — draai alter_gymies_saas_subscriptions_fix.sql'];
        }

        $row = [
            'plan_id' => $planId,
            'status' => 'trialing',
            'created_at' => now(),
            'updated_at' => now(),
        ];
        if ($hasTrainerCol) {
            $row['trainer_user_id'] = $trainerUserId;
        } elseif ($hasClientCol) {
            $row['client_user_id'] = $trainerUserId;
        }
        if (in_array('mollie_customer_id', $columns, true)) {
            $row['mollie_customer_id'] = $customerId;
        }
        if (in_array('current_period_start', $columns, true)) {
            $row['current_period_start'] = now()->toDateString();
        }
        if (in_array('current_period_end', $columns, true)) {
            $row['current_period_end'] = now()->addMonth()->toDateString();
        }
        if (in_array('started_at', $columns, true) && !isset($row['current_period_start'])) {
            $row['started_at'] = now();
        }

        $subId = DB::table($subTable)->insertGetId($row);

        if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
            DB::table('gymies_trainer_profiles')
                ->where('user_id', $trainerUserId)
                ->update(['subscription_plan' => $plan->slug]);
        }

        return [
            'ok' => true,
            'subscription_id' => $subId,
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
        $amountEur = number_format($plan->price_cents_per_month / 100, 2, '.', '');

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
}
