<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;

/**
 * Trait: Abonnement-betaling starten via Mollie (platform API key).
 * Geld gaat naar het Gymies-platform, niet naar de trainer.
 *
 * POST subscription/start-payment { "tier": "starter"|"pro"|"elite" }
 * Retourneert payment_url voor redirect naar Mollie checkout.
 */
trait SubscriptionPaymentTrait
{
    private const TIER_AMOUNTS_FALLBACK = [
        'starter' => 2995,
        'pro' => 5995,
        'elite' => 9995,
    ];

    /**
     * Haal amount_cents op uit gymies_plans (slug = tier).
     * Fallback naar TIER_AMOUNTS_FALLBACK als tabel/rij ontbreekt.
     */
    protected function getPlanAmountCents(string $tier): int
    {
        if (Schema::hasTable('gymies_plans')) {
            $row = DB::table('gymies_plans')
                ->where('slug', $tier)
                ->first(['amount_cents']);
            if ($row !== null && isset($row->amount_cents) && (int) $row->amount_cents > 0) {
                return (int) $row->amount_cents;
            }
        }
        return self::TIER_AMOUNTS_FALLBACK[$tier] ?? 2995;
    }

    public function startSubscriptionPayment(Request $request): JsonResponse
    {
        $user = Auth::user();
        if (!$user) {
            return response()->json(['message' => 'Unauthenticated'], 401);
        }

        $validated = $request->validate([
            'tier' => 'required|string|in:starter,pro,elite',
        ]);
        $tier = strtolower(trim($validated['tier']));

        $apiKey = $this->getSubscriptionMollieApiKey();
        if (empty($apiKey)) {
            return response()->json([
                'message' => 'Betaling is tijdelijk niet beschikbaar. Probeer later opnieuw.',
            ], 503);
        }

        $amountCents = $this->getPlanAmountCents($tier);
        $amountEur = number_format($amountCents / 100, 2, '.', '');
        $userId = (int) ($user->id ?? 0);
        if ($userId <= 0) {
            return response()->json(['message' => 'Gebruiker niet gevonden'], 400);
        }

        $baseUrl = rtrim(config('app.url') ?? env('APP_URL', 'https://www.gymies.nl'), '/');
        $webhookUrl = $baseUrl . '/api/gymies/webhooks/mollie-subscription';
        $redirectUrl = 'gymies://subscription/complete?tier=' . $tier;

        $payload = [
            'amount' => [
                'currency' => 'EUR',
                'value' => $amountEur,
            ],
            'description' => 'Gymies ' . ucfirst($tier) . ' abonnement',
            'redirectUrl' => $redirectUrl,
            'webhookUrl' => $webhookUrl,
            'metadata' => [
                'type' => 'subscription',
                'user_id' => (string) $userId,
                'tier' => $tier,
            ],
        ];

        $resp = Http::withToken($apiKey)
            ->asJson()
            ->timeout(15)
            ->post('https://api.mollie.com/v2/payments', $payload);

        if (!$resp->successful()) {
            $body = $resp->json();
            $msg = $body['detail'] ?? $body['title'] ?? $resp->body();
            return response()->json([
                'message' => 'Kon betaling niet starten: ' . (is_string($msg) ? $msg : 'Mollie fout'),
            ], 502);
        }

        $data = $resp->json();
        $paymentId = $data['id'] ?? '';
        $checkoutUrl = $data['_links']['checkout']['href'] ?? $data['checkoutUrl'] ?? '';

        if (empty($checkoutUrl)) {
            return response()->json(['message' => 'Geen betaal-URL ontvangen van Mollie'], 502);
        }

        $this->storeSubscriptionPayment($paymentId, $userId, $tier, $amountCents);

        return response()->json([
            'payment_url' => $checkoutUrl,
            'payment_id' => $paymentId,
            'tier' => $tier,
            'amount_cents' => $amountCents,
        ]);
    }

    protected function getSubscriptionMollieApiKey(): ?string
    {
        $key = config('services.mollie.key') ?? env('MOLLIE_API_KEY');
        return is_string($key) && $key !== '' ? $key : null;
    }

    protected function storeSubscriptionPayment(
        string $molliePaymentId,
        int $userId,
        string $tier,
        int $amountCents
    ): void {
        if (!Schema::hasTable('gymies_subscription_payments')) {
            return;
        }
        $now = now();
        DB::table('gymies_subscription_payments')->updateOrInsert(
            ['mollie_payment_id' => $molliePaymentId],
            [
                'user_id' => $userId,
                'tier' => $tier,
                'amount_cents' => $amountCents,
                'status' => 'open',
                'created_at' => $now,
                'updated_at' => $now,
            ]
        );
    }

    /**
     * Zoek user_id en tier op basis van mollie_payment_id (voor webhook).
     *
     * @return array{user_id: int, tier: string}|null
     */
    public static function lookupSubscriptionByMolliePaymentId(string $molliePaymentId): ?array
    {
        if (!Schema::hasTable('gymies_subscription_payments')) {
            return null;
        }
        $row = DB::table('gymies_subscription_payments')
            ->where('mollie_payment_id', $molliePaymentId)
            ->first();
        if (!$row) {
            return null;
        }
        return [
            'user_id' => (int) $row->user_id,
            'tier' => (string) $row->tier,
        ];
    }
}
