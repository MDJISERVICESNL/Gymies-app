<?php

declare(strict_types=1);

namespace App\Services;

use App\Http\Controllers\Gymies\GymiesFeatureFlags;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Carbon\Carbon;

/**
 * Gymies Onboarding Service
 * ─────────────────────────
 * Beheert de volledige onboarding state machine voor trainers:
 *
 *   incomplete → pending_review → approved → active
 *                     ↓                ↓
 *                  rejected        suspended
 *                     ↓
 *              (hercorrigeer → pending_review)
 *
 * Verantwoordelijkheden:
 * - State transitions met validatie
 * - Mollie customer + mandaat aanmaken (€0,01 first payment)
 * - Mollie subscription starten na goedkeuring
 * - Trial periode berekenen
 * - Promo toepassen (launch_free_month + yearly korting)
 * - Audit trail bij elke actie
 */
final class OnboardingService
{
    // ─── Geldige state transitions ───────────────────────────────
    private const VALID_TRANSITIONS = [
        'incomplete'     => ['pending_review'],
        'pending_review' => ['approved', 'rejected'],
        'approved'       => ['active', 'suspended'],
        'rejected'       => ['pending_review'],  // Na correctie opnieuw indienen
        'active'         => ['suspended'],
        'suspended'      => ['active'],           // Reactivatie door staff
    ];

    // ─── Trial configuratie ──────────────────────────────────────
    private const DEFAULT_TRIAL_DAYS = 30;
    private const LAUNCH_PROMO_KEY = 'launch_free_month';
    private const YEARLY_FREE_MONTHS_DEFAULT = 2;  // Fallback als flag niet bestaat

    // ─── Mollie configuratie ─────────────────────────────────────
    private const MOLLIE_API = 'https://api.mollie.com/v2';
    private const MANDAAT_AMOUNT_DEFAULT = '0.01';  // Fallback als flag niet bestaat

    /**
     * Dien onboarding in voor review door staff.
     * Valideert dat alle vereiste documenten en gegevens aanwezig zijn.
     */
    public static function submitForReview(int $trainerId, ?int $userId = null): array
    {
        $profile = self::getProfile($trainerId);
        if (!$profile) {
            return ['success' => false, 'error' => 'Trainer profiel niet gevonden.'];
        }

        if (!self::canTransition($profile->onboarding_status ?? 'incomplete', 'pending_review')) {
            return ['success' => false, 'error' => 'Onboarding kan niet worden ingediend vanuit status: ' . ($profile->onboarding_status ?? 'incomplete')];
        }

        // Valideer vereiste velden
        $missing = self::validateRequiredFields($profile);
        if (!empty($missing)) {
            return ['success' => false, 'error' => 'Ontbrekende velden', 'missing' => $missing];
        }

        DB::table('gymies_trainer_profiles')
            ->where('id', $trainerId)
            ->update([
                'onboarding_status' => 'pending_review',
                'updated_at' => now(),
            ]);

        self::logAudit($userId ?? $trainerId, 'onboarding.submitted', 'TrainerProfile', $trainerId);

        // Notificatie naar staff: nieuwe aanvraag
        try {
            $trainerName = DB::table('gymies_users')->where('id', $profile->user_id)->value('display_name') ?? 'Trainer';
            $notifier = new OnboardingNotificationService();
            $notifier->notifyStaffNewRequest($trainerName, $trainerId);

            // Welkom email naar trainer
            $notifier->sendWelcomeEmail($profile->user_id, $trainerName);
        } catch (\Throwable $e) {
            Log::warning('OnboardingService@submitForReview notification failed', ['error' => $e->getMessage()]);
        }

        // Fraud check — stuur alert als er warnings zijn
        try {
            $fraudResult = FraudDetectionService::check($trainerId);
            if (!empty($fraudResult['warnings'])) {
                $trainerName = $trainerName ?? DB::table('gymies_users')->where('id', $profile->user_id)->value('display_name') ?? 'Trainer';
                $notifier = $notifier ?? new OnboardingNotificationService();
                $notifier->notifyStaffFraudAlert($trainerId, $trainerName, $fraudResult['warnings']);
            }
        } catch (\Throwable $e) {
            Log::warning('OnboardingService@submitForReview fraud check failed', ['error' => $e->getMessage()]);
        }

        return ['success' => true, 'status' => 'pending_review'];
    }

    /**
     * Staff keurt trainer goed.
     * Start trial periode + plant Mollie subscription.
     */
    public static function approve(int $trainerId, int $staffId, ?string $notes = null): array
    {
        $profile = self::getProfile($trainerId);
        if (!$profile) {
            return ['success' => false, 'error' => 'Trainer profiel niet gevonden.'];
        }

        if (!self::canTransition($profile->onboarding_status ?? 'incomplete', 'approved')) {
            return ['success' => false, 'error' => 'Kan niet goedkeuren vanuit status: ' . ($profile->onboarding_status ?? 'incomplete')];
        }

        $now = Carbon::now();
        $trialEnd = self::calculateTrialEnd($profile);

        DB::beginTransaction();
        try {
            // Update profiel
            DB::table('gymies_trainer_profiles')
                ->where('id', $trainerId)
                ->update([
                    'onboarding_status' => 'approved',
                    'approved_at'       => $now,
                    'approved_by'       => $staffId,
                    'trial_started_at'  => $now,
                    'trial_ends_at'     => $trialEnd,
                    'updated_at'        => $now,
                ]);

            // Onboarding review record
            if (Schema::hasTable('gymies_onboarding_reviews')) {
                DB::table('gymies_onboarding_reviews')->insert([
                    'trainer_id'  => $trainerId,
                    'reviewer_id' => $staffId,
                    'action'      => 'approved',
                    'reason'      => $notes,
                    'created_at'  => $now,
                    'updated_at'  => $now,
                ]);
            }

            self::logAudit($staffId, 'trainer.approved', 'TrainerProfile', $trainerId, [
                'trial_ends_at' => $trialEnd->toIso8601String(),
                'notes' => $notes,
            ]);

            DB::commit();

            // Push + email notificatie naar trainer (buiten transactie)
            try {
                $trainerName = DB::table('gymies_users')->where('id', $profile->user_id)->value('display_name') ?? 'Trainer';
                $notifier = new OnboardingNotificationService();
                $notifier->notifyTrainerApproved($profile->user_id, $trainerName);
            } catch (\Throwable $e) {
                Log::warning('OnboardingService@approve notification failed', ['error' => $e->getMessage()]);
            }

            // ── Sync trainer regions from KvK vestigingsplaats (buiten transactie) ──
            try {
                if (class_exists(\App\Http\Controllers\Gymies\GymiesLaunchGateService::class)) {
                    \App\Http\Controllers\Gymies\GymiesLaunchGateService::syncTrainerRegionsFromKvK($profile->user_id);
                }
            } catch (\Throwable $e) {
                Log::warning('OnboardingService@approve KvK region sync failed (non-blocking)', ['error' => $e->getMessage()]);
            }

            return [
                'success'        => true,
                'status'         => 'approved',
                'trial_ends_at'  => $trialEnd->toIso8601String(),
            ];
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('OnboardingService@approve FAILED', [
                'trainer_id' => $trainerId,
                'error' => $e->getMessage(),
            ]);
            return ['success' => false, 'error' => 'Goedkeuring mislukt: ' . $e->getMessage()];
        }
    }

    /**
     * Staff wijst trainer af.
     */
    public static function reject(int $trainerId, int $staffId, string $reason): array
    {
        $profile = self::getProfile($trainerId);
        if (!$profile) {
            return ['success' => false, 'error' => 'Trainer profiel niet gevonden.'];
        }

        if (!self::canTransition($profile->onboarding_status ?? 'incomplete', 'rejected')) {
            return ['success' => false, 'error' => 'Kan niet afwijzen vanuit status: ' . ($profile->onboarding_status ?? 'incomplete')];
        }

        $now = Carbon::now();

        DB::beginTransaction();
        try {
            DB::table('gymies_trainer_profiles')
                ->where('id', $trainerId)
                ->update([
                    'onboarding_status'  => 'rejected',
                    'rejection_reason'   => $reason,
                    'updated_at'         => $now,
                ]);

            if (Schema::hasTable('gymies_onboarding_reviews')) {
                DB::table('gymies_onboarding_reviews')->insert([
                    'trainer_id'  => $trainerId,
                    'reviewer_id' => $staffId,
                    'action'      => 'rejected',
                    'reason'      => $reason,
                    'created_at'  => $now,
                    'updated_at'  => $now,
                ]);
            }

            self::logAudit($staffId, 'trainer.rejected', 'TrainerProfile', $trainerId, [
                'reason' => $reason,
            ]);

            DB::commit();

            // Push + email notificatie naar trainer (buiten transactie)
            try {
                $trainerName = DB::table('gymies_users')->where('id', $profile->user_id)->value('display_name') ?? 'Trainer';
                $notifier = new OnboardingNotificationService();
                $notifier->notifyTrainerRejected($profile->user_id, $trainerName, $reason);
            } catch (\Throwable $e2) {
                Log::warning('OnboardingService@reject notification failed', ['error' => $e2->getMessage()]);
            }

            return ['success' => true, 'status' => 'rejected'];
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('OnboardingService@reject FAILED', ['error' => $e->getMessage()]);
            return ['success' => false, 'error' => 'Afwijzing mislukt.'];
        }
    }

    /**
     * Schors een actieve trainer.
     */
    public static function suspend(int $trainerId, int $staffId, string $reason): array
    {
        $profile = self::getProfile($trainerId);
        if (!$profile) {
            return ['success' => false, 'error' => 'Trainer profiel niet gevonden.'];
        }

        $currentStatus = $profile->onboarding_status ?? 'incomplete';
        if (!self::canTransition($currentStatus, 'suspended')) {
            return ['success' => false, 'error' => 'Kan niet schorsen vanuit status: ' . $currentStatus];
        }

        $now = Carbon::now();

        DB::beginTransaction();
        try {
            DB::table('gymies_trainer_profiles')
                ->where('id', $trainerId)
                ->update([
                    'onboarding_status' => 'suspended',
                    'updated_at'        => $now,
                ]);

            if (Schema::hasTable('gymies_onboarding_reviews')) {
                DB::table('gymies_onboarding_reviews')->insert([
                    'trainer_id'  => $trainerId,
                    'reviewer_id' => $staffId,
                    'action'      => 'suspended',
                    'reason'      => $reason,
                    'created_at'  => $now,
                    'updated_at'  => $now,
                ]);
            }

            // Pauzeer Mollie subscription als die er is
            if (!empty($profile->mollie_subscription_id) && !empty($profile->mollie_customer_id)) {
                self::pauseMollieSubscription($profile->mollie_customer_id, $profile->mollie_subscription_id);
            }

            self::logAudit($staffId, 'trainer.suspended', 'TrainerProfile', $trainerId, [
                'reason' => $reason,
                'previous_status' => $currentStatus,
            ]);

            DB::commit();
            return ['success' => true, 'status' => 'suspended'];
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('OnboardingService@suspend FAILED', ['error' => $e->getMessage()]);
            return ['success' => false, 'error' => 'Schorsing mislukt.'];
        }
    }

    /**
     * Heractiveer een geschorste trainer.
     */
    public static function reactivate(int $trainerId, int $staffId, ?string $reason = null): array
    {
        $profile = self::getProfile($trainerId);
        if (!$profile) {
            return ['success' => false, 'error' => 'Trainer profiel niet gevonden.'];
        }

        if (!self::canTransition($profile->onboarding_status ?? 'incomplete', 'active')) {
            return ['success' => false, 'error' => 'Kan niet heractiveren vanuit status: ' . ($profile->onboarding_status ?? 'incomplete')];
        }

        $now = Carbon::now();

        DB::beginTransaction();
        try {
            DB::table('gymies_trainer_profiles')
                ->where('id', $trainerId)
                ->update([
                    'onboarding_status' => 'active',
                    'updated_at'        => $now,
                ]);

            if (Schema::hasTable('gymies_onboarding_reviews')) {
                DB::table('gymies_onboarding_reviews')->insert([
                    'trainer_id'  => $trainerId,
                    'reviewer_id' => $staffId,
                    'action'      => 'reactivated',
                    'reason'      => $reason,
                    'created_at'  => $now,
                    'updated_at'  => $now,
                ]);
            }

            // Heractiveer Mollie subscription
            if (!empty($profile->mollie_subscription_id) && !empty($profile->mollie_customer_id)) {
                self::resumeMollieSubscription($profile->mollie_customer_id, $profile->mollie_subscription_id);
            }

            self::logAudit($staffId, 'trainer.reactivated', 'TrainerProfile', $trainerId, [
                'reason' => $reason,
            ]);

            DB::commit();
            return ['success' => true, 'status' => 'active'];
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('OnboardingService@reactivate FAILED', ['error' => $e->getMessage()]);
            return ['success' => false, 'error' => 'Heractivatie mislukt.'];
        }
    }

    /**
     * Activeer trainer na succesvolle €0,01 mandaat betaling.
     * Wordt aangeroepen door de Mollie webhook.
     */
    public static function activateAfterMandaat(int $trainerId): array
    {
        $profile = self::getProfile($trainerId);
        if (!$profile) {
            return ['success' => false, 'error' => 'Trainer niet gevonden.'];
        }

        if (($profile->onboarding_status ?? '') !== 'approved') {
            return ['success' => false, 'error' => 'Trainer moet eerst goedgekeurd zijn.'];
        }

        $now = Carbon::now();

        DB::beginTransaction();
        try {
            // Start Mollie subscription met startDate = trial_ends_at
            $subscriptionResult = self::createMollieSubscription($profile);

            $updateData = [
                'onboarding_status' => 'active',
                'updated_at'        => $now,
            ];

            if (!empty($subscriptionResult['subscription_id'])) {
                $updateData['mollie_subscription_id'] = $subscriptionResult['subscription_id'];
            }

            DB::table('gymies_trainer_profiles')
                ->where('id', $trainerId)
                ->update($updateData);

            self::logAudit($trainerId, 'trainer.activated', 'TrainerProfile', $trainerId, [
                'subscription_id' => $subscriptionResult['subscription_id'] ?? null,
                'trial_ends_at' => $profile->trial_ends_at,
            ]);

            DB::commit();
            return ['success' => true, 'status' => 'active'];
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('OnboardingService@activateAfterMandaat FAILED', ['error' => $e->getMessage()]);
            return ['success' => false, 'error' => 'Activatie mislukt.'];
        }
    }

    // ─── Mollie Mandaat Flow ─────────────────────────────────────

    /**
     * Maak een Mollie customer aan en initieer €0,01 first payment voor SEPA mandaat.
     * Returns checkout URL voor de trainer.
     */
    public static function createMollieMandaat(int $trainerId): array
    {
        $profile = self::getProfile($trainerId);
        if (!$profile) {
            return ['success' => false, 'error' => 'Trainer niet gevonden.'];
        }

        $apiKey = self::getMollieApiKey();
        if (empty($apiKey)) {
            return ['success' => false, 'error' => 'Mollie API key niet geconfigureerd.'];
        }

        try {
            // Stap 1: Mollie Customer aanmaken (of bestaande ophalen)
            $customerId = $profile->mollie_customer_id;
            if (empty($customerId)) {
                $customerId = self::createMollieCustomer($profile, $apiKey);
                DB::table('gymies_trainer_profiles')
                    ->where('id', $trainerId)
                    ->update(['mollie_customer_id' => $customerId, 'updated_at' => now()]);
            }

            // Stap 2: €0,01 first payment voor SEPA mandaat
            $baseUrl = rtrim(config('app.url') ?? env('APP_URL', 'https://www.gymies.nl'), '/');
            $payment = Http::withToken($apiKey)
                ->asJson()
                ->timeout(15)
                ->post(self::MOLLIE_API . '/payments', [
                    'amount' => [
                        'currency' => 'EUR',
                        'value'    => self::getMandaatAmount(),
                    ],
                    'customerId'   => $customerId,
                    'sequenceType' => 'first',
                    'description'  => 'Gymies — SEPA machtiging',
                    'redirectUrl'  => $baseUrl . '/api/gymies/onboarding/mandaat-callback?trainer_id=' . $trainerId,
                    'webhookUrl'   => $baseUrl . '/api/gymies/webhooks/mandaat',
                    'metadata'     => [
                        'trainer_id' => $trainerId,
                        'type'       => 'mandaat_first_payment',
                    ],
                ]);

            if (!$payment->successful()) {
                $body = $payment->json();
                throw new \RuntimeException($body['detail'] ?? $body['title'] ?? 'Mollie error');
            }

            $paymentData = $payment->json();
            $checkoutUrl = $paymentData['_links']['checkout']['href'] ?? '';

            self::logAudit($trainerId, 'mandaat.initiated', 'TrainerProfile', $trainerId, [
                'payment_id'  => $paymentData['id'] ?? null,
                'customer_id' => $customerId,
            ]);

            return [
                'success'      => true,
                'checkout_url' => $checkoutUrl,
                'payment_id'   => $paymentData['id'] ?? null,
                'customer_id'  => $customerId,
            ];
        } catch (\Throwable $e) {
            Log::error('OnboardingService@createMollieMandaat FAILED', [
                'trainer_id' => $trainerId,
                'error' => $e->getMessage(),
            ]);
            return ['success' => false, 'error' => 'Mandaat aanmaken mislukt: ' . $e->getMessage()];
        }
    }

    /**
     * Verwerk Mollie mandaat webhook — sla mandate_id op als betaling geslaagd.
     */
    public static function handleMandaatWebhook(string $paymentId): array
    {
        $apiKey = self::getMollieApiKey();
        if (empty($apiKey)) {
            return ['success' => false, 'error' => 'Geen API key.'];
        }

        try {
            $resp = Http::withToken($apiKey)
                ->timeout(15)
                ->get(self::MOLLIE_API . '/payments/' . $paymentId);

            if (!$resp->successful()) {
                return ['success' => false, 'error' => 'Payment niet gevonden.'];
            }

            $data = $resp->json();
            $trainerId = (int) ($data['metadata']['trainer_id'] ?? 0);
            $status = $data['status'] ?? '';

            if ($trainerId <= 0 || ($data['metadata']['type'] ?? '') !== 'mandaat_first_payment') {
                return ['success' => false, 'error' => 'Geen mandaat payment.'];
            }

            if ($status !== 'paid') {
                Log::info('Mandaat payment niet betaald', ['status' => $status, 'trainer_id' => $trainerId]);
                return ['success' => false, 'error' => 'Payment status: ' . $status];
            }

            // Haal mandate op
            $mandateId = $data['mandateId'] ?? null;
            if (empty($mandateId)) {
                // Probeer mandates op te halen via customer
                $customerId = $data['customerId'] ?? null;
                if ($customerId) {
                    $mandates = Http::withToken($apiKey)
                        ->timeout(15)
                        ->get(self::MOLLIE_API . '/customers/' . $customerId . '/mandates');
                    if ($mandates->successful()) {
                        $mandateList = $mandates->json()['_embedded']['mandates'] ?? [];
                        foreach ($mandateList as $m) {
                            if (($m['status'] ?? '') === 'valid') {
                                $mandateId = $m['id'];
                                break;
                            }
                        }
                    }
                }
            }

            DB::table('gymies_trainer_profiles')
                ->where('id', $trainerId)
                ->update([
                    'mollie_mandate_id' => $mandateId,
                    'updated_at'        => now(),
                ]);

            self::logAudit($trainerId, 'mandaat.completed', 'TrainerProfile', $trainerId, [
                'payment_id' => $paymentId,
                'mandate_id' => $mandateId,
            ]);

            // Activeer trainer automatisch
            $activationResult = self::activateAfterMandaat($trainerId);

            return [
                'success'    => true,
                'mandate_id' => $mandateId,
                'activated'  => $activationResult['success'] ?? false,
            ];
        } catch (\Throwable $e) {
            Log::error('OnboardingService@handleMandaatWebhook FAILED', [
                'payment_id' => $paymentId,
                'error' => $e->getMessage(),
            ]);
            return ['success' => false, 'error' => $e->getMessage()];
        }
    }

    // ─── Trial Berekening ────────────────────────────────────────

    /**
     * Bereken trial einddatum op basis van promo's.
     * - Standaard: 30 dagen
     * - Launch promo (launch_free_month): +30 dagen = 60 dagen totaal
     * - Stapelbaar: launch promo is altijd bovenop standaard trial
     */
    public static function calculateTrialEnd(object $profile): Carbon
    {
        $baseDays = self::DEFAULT_TRIAL_DAYS;
        $bonusDays = 0;

        // Launch promo check (alleen als flag ook actief is)
        $promoApplied = $profile->promo_applied ?? null;
        if ($promoApplied === self::LAUNCH_PROMO_KEY && self::isLaunchPromoActive()) {
            $bonusDays += 30; // Extra maand gratis
        }

        return Carbon::now()->addDays($baseDays + $bonusDays);
    }

    /**
     * Bereken maandbedrag in EUR op basis van plan + billing cycle.
     * Yearly: betaal 10 maanden, krijg 12 (effectief 2 maanden gratis).
     */
    public static function calculateSubscriptionAmount(string $planSlug, string $billingCycle): array
    {
        $plans = self::getPlanPrices();
        $monthlyPrice = $plans[$planSlug] ?? 0;

        if ($billingCycle === 'yearly') {
            $freeMonths = self::getYearlyDiscountMonths();
            $paidMonths = 12 - $freeMonths;
            $yearlyTotal = $monthlyPrice * $paidMonths;
            $effectiveMonthly = round($yearlyTotal / 12, 2);
            return [
                'monthly_price'    => $monthlyPrice,
                'effective_monthly' => $effectiveMonthly,
                'interval'         => '12 months',
                'amount'           => number_format($yearlyTotal, 2, '.', ''),
                'savings_months'   => $freeMonths,
            ];
        }

        return [
            'monthly_price'    => $monthlyPrice,
            'effective_monthly' => $monthlyPrice,
            'interval'         => '1 month',
            'amount'           => number_format($monthlyPrice, 2, '.', ''),
            'savings_months'   => 0,
        ];
    }

    // ─── Private Helpers ─────────────────────────────────────────

    private static function getProfile(int $trainerId): ?object
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return null;
        }
        return DB::table('gymies_trainer_profiles')->where('id', $trainerId)->first();
    }

    private static function canTransition(string $currentStatus, string $targetStatus): bool
    {
        $allowed = self::VALID_TRANSITIONS[$currentStatus] ?? [];
        return in_array($targetStatus, $allowed, true);
    }

    private static function validateRequiredFields(object $profile): array
    {
        $missing = [];
        $required = ['company_name', 'kvk_number', 'trainer_address_line1', 'trainer_postcode', 'trainer_city'];

        foreach ($required as $field) {
            if (empty($profile->$field ?? null)) {
                $missing[] = $field;
            }
        }

        // Plan moet gekozen zijn
        if (empty($profile->selected_plan_slug ?? null)) {
            $missing[] = 'selected_plan_slug';
        }

        return $missing;
    }

    private static function createMollieCustomer(object $profile, string $apiKey): string
    {
        // Haal user email op
        $user = DB::table('gymies_users')->where('id', $profile->user_id ?? 0)->first();
        $email = $user->email ?? '';
        $name = trim(($user->first_name ?? '') . ' ' . ($user->last_name ?? ''));

        $resp = Http::withToken($apiKey)
            ->asJson()
            ->timeout(15)
            ->post(self::MOLLIE_API . '/customers', [
                'name'  => $name ?: 'Trainer #' . $profile->id,
                'email' => $email,
                'metadata' => [
                    'trainer_id' => $profile->id,
                    'platform'   => 'gymies',
                ],
            ]);

        if (!$resp->successful()) {
            throw new \RuntimeException('Mollie customer aanmaken mislukt: ' . $resp->body());
        }

        return $resp->json()['id'] ?? '';
    }

    /**
     * Maak Mollie subscription aan met uitgestelde startDate (na trial).
     */
    private static function createMollieSubscription(object $profile): array
    {
        $apiKey = self::getMollieApiKey();
        $customerId = $profile->mollie_customer_id ?? '';
        $planSlug = $profile->selected_plan_slug ?? 'starter';
        $billingCycle = $profile->billing_cycle ?? 'monthly';

        if (empty($apiKey) || empty($customerId)) {
            return ['subscription_id' => null];
        }

        $pricing = self::calculateSubscriptionAmount($planSlug, $billingCycle);
        $startDate = $profile->trial_ends_at
            ? Carbon::parse($profile->trial_ends_at)->format('Y-m-d')
            : Carbon::now()->addDays(self::DEFAULT_TRIAL_DAYS)->format('Y-m-d');

        try {
            $resp = Http::withToken($apiKey)
                ->asJson()
                ->timeout(15)
                ->post(self::MOLLIE_API . '/customers/' . $customerId . '/subscriptions', [
                    'amount' => [
                        'currency' => 'EUR',
                        'value'    => $pricing['amount'],
                    ],
                    'interval'    => $pricing['interval'],
                    'startDate'   => $startDate,
                    'description' => 'Gymies ' . ucfirst(str_replace('_', ' ', $planSlug)) . ' abonnement',
                    'webhookUrl'  => rtrim(config('app.url', ''), '/') . '/api/gymies/webhooks/subscription',
                    'metadata'    => [
                        'trainer_id'    => $profile->id,
                        'plan_slug'     => $planSlug,
                        'billing_cycle' => $billingCycle,
                    ],
                ]);

            if (!$resp->successful()) {
                Log::warning('Mollie subscription aanmaken mislukt', ['body' => $resp->body()]);
                return ['subscription_id' => null];
            }

            return ['subscription_id' => $resp->json()['id'] ?? null];
        } catch (\Throwable $e) {
            Log::error('createMollieSubscription FAILED', ['error' => $e->getMessage()]);
            return ['subscription_id' => null];
        }
    }

    private static function pauseMollieSubscription(string $customerId, string $subscriptionId): void
    {
        try {
            Http::withToken(self::getMollieApiKey())
                ->timeout(15)
                ->delete(self::MOLLIE_API . '/customers/' . $customerId . '/subscriptions/' . $subscriptionId);
        } catch (\Throwable $e) {
            Log::warning('Mollie subscription pauzeren mislukt', ['error' => $e->getMessage()]);
        }
    }

    private static function resumeMollieSubscription(string $customerId, string $subscriptionId): void
    {
        // Mollie heeft geen resume; we moeten een nieuwe subscription aanmaken
        Log::info('Mollie subscription resume: nieuwe subscription nodig na reactivatie', [
            'customer_id' => $customerId,
            'old_subscription_id' => $subscriptionId,
        ]);
    }

    private static function getMollieApiKey(): string
    {
        $key = config('gymies.mollie_api_key');
        if (is_string($key) && trim($key) !== '') {
            return trim($key);
        }
        return trim((string) env('MOLLIE_API_KEY', ''));
    }

    private static function getPlanPrices(): array
    {
        // Haal uit database als beschikbaar, anders fallback
        if (Schema::hasTable('gymies_plans')) {
            $plans = DB::table('gymies_plans')
                ->whereNotNull('slug')
                ->pluck('price_monthly_eur', 'slug')
                ->toArray();
            if (!empty($plans)) {
                return $plans;
            }
        }

        // Fallback prijzen
        return [
            'starter'  => 29.00,
            'pro'      => 49.00,
            'pro_plus' => 79.00,
        ];
    }

    // ─── Feature Flag Helpers ───────────────────────────────────

    /**
     * Mandaat bedrag uit feature flag (voor A/B test €0,01 vs €1,00).
     */
    private static function getMandaatAmount(): string
    {
        $val = GymiesFeatureFlags::getValue('mandaat_amount', self::MANDAAT_AMOUNT_DEFAULT);
        // Zorg dat het een geldig bedrag is (2 decimalen)
        return number_format((float) $val, 2, '.', '');
    }

    /**
     * Aantal gratis maanden bij jaarabonnement uit feature flag.
     */
    private static function getYearlyDiscountMonths(): int
    {
        $months = GymiesFeatureFlags::getInt('yearly_discount_months', self::YEARLY_FREE_MONTHS_DEFAULT);
        return max(0, min(6, $months)); // Begrensd 0-6
    }

    /**
     * Check of launch promo actief is.
     */
    public static function isLaunchPromoActive(): bool
    {
        return GymiesFeatureFlags::isEnabled('launch_promo_free_month');
    }

    private static function logAudit(int $userId, string $action, string $targetType, int $targetId, ?array $metadata = null): void
    {
        if (!Schema::hasTable('gymies_staff_audit_log')) {
            return;
        }
        try {
            DB::table('gymies_staff_audit_log')->insert([
                'staff_id'    => $userId,
                'action'      => $action,
                'target_type' => $targetType,
                'target_id'   => $targetId,
                'metadata'    => $metadata ? json_encode($metadata) : null,
                'ip_address'  => request()?->ip(),
                'created_at'  => now(),
                'updated_at'  => now(),
            ]);
        } catch (\Throwable $e) {
            Log::warning('Audit log schrijven mislukt: ' . $e->getMessage());
        }
    }
}
