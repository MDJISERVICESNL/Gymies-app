<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * Trait: Mollie webhook verwerken voor abonnement-betalingen.
 * Bij status "paid" wordt subscription_plan bijgewerkt in gymies_trainer_profiles.
 *
 * Gebruik in GymiesSubscriptionController::subscriptionWebhook:
 *   return $this->handleSubscriptionWebhook($request);
 */
trait SubscriptionWebhookTrait
{
    public function handleSubscriptionWebhook(Request $request): Response
    {
        $paymentId = $request->input('id');
        if (empty($paymentId) || !is_string($paymentId)) {
            // BUG FIX: Return 200 to Mollie to acknowledge receipt and stop retries
            return response('', 200);
        }

        $lookup = SubscriptionPaymentTrait::lookupSubscriptionByMolliePaymentId($paymentId);
        if (!$lookup) {
            return response('', 200);
        }

        $apiKey = $this->getSubscriptionMollieApiKey();
        if (empty($apiKey)) {
            // BUG FIX: Return 200 to Mollie (not 500) — we can't process without key, but that's not Mollie's problem
            // Log the issue for debugging but don't cause Mollie to retry
            Log::warning('SubscriptionWebhookTrait: No Mollie API key configured', [
                'payment_id' => $paymentId,
            ]);
            return response('', 200);
        }

        try {
            $resp = Http::withToken($apiKey)
                ->timeout(10)
                ->get('https://api.mollie.com/v2/payments/' . $paymentId);

            if (!$resp->successful()) {
                // BUG FIX: Return 200 to Mollie (not 500) to prevent retry loop if our API is temporarily down
                Log::warning('SubscriptionWebhookTrait: Failed to fetch payment status from Mollie', [
                    'payment_id' => $paymentId,
                    'status' => $resp->status(),
                ]);
                return response('', 200);
            }
        } catch (\Throwable $e) {
            Log::error('SubscriptionWebhookTrait: Mollie status fetch failed', [
                'payment_id' => $paymentId,
                'error' => $e->getMessage(),
            ]);
            // BUG FIX: Return 200 to Mollie even on connection error — we'll process the webhook when we can
            return response('', 200);
        }

        $status = $resp->json('status');
        if ($status !== 'paid') {
            $this->updateSubscriptionPaymentStatus($paymentId, $status ?? 'unknown');

            // Grace period bij mislukte betaling: 7 dagen voordat we suspenderen
            if (in_array($status, ['failed', 'expired', 'canceled'], true)) {
                $this->handleFailedSubscriptionPayment($lookup['user_id']);
            }

            return response('', 200);
        }

        $userId = $lookup['user_id'];
        $tier = $lookup['tier'];
        $planLabel = ucfirst($tier);

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            $this->updateSubscriptionPaymentStatus($paymentId, 'paid');
            return response('', 200);
        }

        // Wrap profile update and payment status in transaction
        DB::transaction(function () use ($userId, $planLabel, $paymentId) {
            $profile = DB::table('gymies_trainer_profiles')->where('user_id', $userId)->first();
            $updateData = [
                'subscription_plan' => $planLabel,
                'subscription_tier' => $planLabel,
                'subscription_pending_downgrade' => false,
                'subscription_downgrades_at' => null,
                'subscription_downgrade_to' => null,
                'updated_at' => now(),
            ];

            if ($profile) {
                DB::table('gymies_trainer_profiles')
                    ->where('user_id', $userId)
                    ->update($updateData);
            } else {
                $insertData = $updateData;
                $insertData['user_id'] = $userId;
                $insertData['created_at'] = now();
                DB::table('gymies_trainer_profiles')->insert($insertData);
            }

            $this->updateSubscriptionPaymentStatus($paymentId, 'paid');
        });

        return response('', 200);
    }

    protected function getSubscriptionMollieApiKey(): ?string
    {
        // BUG FIX: Config should use 'gymies.mollie_api_key' consistently with GymiesPaymentController
        $key = config('gymies.mollie_api_key') ?? config('services.mollie.key') ?? env('MOLLIE_API_KEY');
        return is_string($key) && $key !== '' ? $key : null;
    }

    protected function updateSubscriptionPaymentStatus(string $molliePaymentId, string $status): void
    {
        if (!Schema::hasTable('gymies_subscription_payments')) {
            return;
        }
        DB::table('gymies_subscription_payments')
            ->where('mollie_payment_id', $molliePaymentId)
            ->update(['status' => $status, 'updated_at' => now()]);
    }

    /**
     * Mislukte betaling: zet subscription op past_due met grace period (7 dagen).
     * Na 7 dagen wordt de subscription suspended via cron.
     *
     * BUG FIX: Use transaction to ensure atomicity and log failures.
     * Also check for multiple failures to avoid over-updating.
     */
    protected function handleFailedSubscriptionPayment(int $trainerUserId): void
    {
        GymiesSchemaEnsure::subscriptionPauseColumns();

        DB::transaction(function () use ($trainerUserId) {
            $sub = DB::table('gymies_subscriptions')
                ->where('trainer_user_id', $trainerUserId)
                ->whereIn('status', ['active', 'trialing', 'past_due'])
                ->lockForUpdate()
                ->first();

            if (!$sub) {
                return;
            }

            // Only update if not already in grace period (prevent duplicate grace period resets)
            if ((string) ($sub->status ?? '') === 'past_due' && !empty($sub->grace_period_ends_at)) {
                if (function_exists('logger')) {
                    logger()->info('Subscription already in grace period, skipping update', [
                        'trainer_user_id' => $trainerUserId,
                        'grace_period_ends_at' => $sub->grace_period_ends_at,
                    ]);
                }
                return;
            }

            $update = [
                'status' => 'past_due',
                'updated_at' => now(),
            ];
            if (Schema::hasColumn('gymies_subscriptions', 'grace_period_ends_at')) {
                $update['grace_period_ends_at'] = now()->addDays(7);
            }

            DB::table('gymies_subscriptions')->where('id', $sub->id)->update($update);

            if (function_exists('logger')) {
                logger()->warning('Subscription payment failed, grace period started', [
                    'trainer_user_id' => $trainerUserId,
                    'grace_period_ends_at' => $update['grace_period_ends_at'] ?? null,
                ]);
            }
        });
    }
}
