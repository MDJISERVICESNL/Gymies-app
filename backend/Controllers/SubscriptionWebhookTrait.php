<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
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
            return response('', 400);
        }

        $lookup = SubscriptionPaymentTrait::lookupSubscriptionByMolliePaymentId($paymentId);
        if (!$lookup) {
            return response('', 200);
        }

        $apiKey = $this->getSubscriptionMollieApiKey();
        if (empty($apiKey)) {
            return response('', 500);
        }

        $resp = Http::withToken($apiKey)
            ->timeout(10)
            ->get('https://api.mollie.com/v2/payments/' . $paymentId);

        if (!$resp->successful()) {
            return response('', 500);
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
            $updateData['user_id'] = $userId;
            $updateData['created_at'] = now();
            DB::table('gymies_trainer_profiles')->insert($updateData);
        }

        $this->updateSubscriptionPaymentStatus($paymentId, 'paid');

        return response('', 200);
    }

    protected function getSubscriptionMollieApiKey(): ?string
    {
        $key = config('services.mollie.key') ?? env('MOLLIE_API_KEY');
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
     */
    protected function handleFailedSubscriptionPayment(int $trainerUserId): void
    {
        GymiesSchemaEnsure::subscriptionPauseColumns();

        $sub = DB::table('gymies_subscriptions')
            ->where('trainer_user_id', $trainerUserId)
            ->whereIn('status', ['active', 'trialing'])
            ->first();

        if (!$sub) {
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
    }
}
