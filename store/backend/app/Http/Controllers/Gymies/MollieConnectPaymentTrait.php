<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;

/**
 * Trait: Mollie payment aanmaken via trainer's Mollie Connect token (on-behalf-of).
 * Betaling gaat naar het Mollie-account van de trainer, niet naar het platform.
 */
trait MollieConnectPaymentTrait
{
    /**
     * Maak Mollie payment aan via trainer's OAuth token.
     * Geld gaat naar trainer's Mollie-account.
     *
     * @param array{id: mixed, amount_cents: int, trainer_user_id?: int, scheduled_at?: string} $booking
     * @param string $accessToken Trainer's mollie_access_token (decrypted)
     */
    protected function createMolliePaymentForTrainer(
        array $booking,
        string $accessToken
    ): array {
        $bookingId = (string) ($booking['id'] ?? '');
        $amountCents = (int) ($booking['amount_cents'] ?? $booking['amountCents'] ?? 0);
        if ($amountCents <= 0) {
            throw new \InvalidArgumentException('Boeking heeft geen geldig bedrag (amount_cents).');
        }

        $baseUrl = rtrim(config('app.url') ?? env('APP_URL', 'https://www.gymies.nl'), '/');
        $webhookUrl = $baseUrl . '/api/gymies/webhooks/mollie';
        $redirectUrl = 'gymies://payment/complete?booking_id=' . $bookingId;
        $amountEur = number_format($amountCents / 100, 2, '.', '');

        $payload = [
            'amount' => [
                'currency' => 'EUR',
                'value' => $amountEur,
            ],
            'description' => 'Sessie Gymies',
            'redirectUrl' => $redirectUrl,
            'webhookUrl' => $webhookUrl,
            'metadata' => [
                'booking_id' => $bookingId,
            ],
        ];

        $resp = Http::withToken($accessToken)
            ->asJson()
            ->timeout(15)
            ->post('https://api.mollie.com/v2/payments', $payload);

        if (!$resp->successful()) {
            $body = $resp->json();
            $msg = $body['detail'] ?? $body['title'] ?? $resp->body();
            throw new \RuntimeException('Mollie payment mislukt: ' . $msg);
        }

        $data = $resp->json();
        $paymentId = $data['id'] ?? '';
        $checkoutUrl = $data['_links']['checkout']['href'] ?? $data['checkoutUrl'] ?? '';

        return [
            'payment_id' => $paymentId,
            'payment_url' => $checkoutUrl,
            'reference_id' => $paymentId,
            'status' => $data['status'] ?? 'open',
            'amount_cents' => $amountCents,
            'currency' => 'EUR',
        ];
    }

    /**
     * Sla de koppeling mollie_payment_id <-> booking_id op voor webhook-verwerking.
     */
    protected function storeBookingMolliePayment(
        string $bookingId,
        string $molliePaymentId,
        int $trainerUserId
    ): void {
        if (!Schema::hasTable('gymies_booking_mollie_payments')) {
            return;
        }
        $now = now();
        $exists = DB::table('gymies_booking_mollie_payments')->where('booking_id', $bookingId)->exists();
        if ($exists) {
            DB::table('gymies_booking_mollie_payments')->where('booking_id', $bookingId)->update([
                'mollie_payment_id' => $molliePaymentId,
                'trainer_user_id' => $trainerUserId,
                'updated_at' => $now,
            ]);
        } else {
            DB::table('gymies_booking_mollie_payments')->insert([
                'booking_id' => $bookingId,
                'mollie_payment_id' => $molliePaymentId,
                'trainer_user_id' => $trainerUserId,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
    }

    /**
     * Zoek booking_id en trainer_user_id op basis van mollie_payment_id.
     *
     * @return array{booking_id: string, trainer_user_id: int}|null
     */
    protected function lookupBookingByMolliePaymentId(string $molliePaymentId): ?array
    {
        if (!Schema::hasTable('gymies_booking_mollie_payments')) {
            return null;
        }
        $row = DB::table('gymies_booking_mollie_payments')
            ->where('mollie_payment_id', $molliePaymentId)
            ->first();
        if (!$row) {
            return null;
        }
        return [
            'booking_id' => (string) $row->booking_id,
            'trainer_user_id' => (int) $row->trainer_user_id,
        ];
    }

    /**
     * Haal Mollie payment-status op via trainer's token (voor Connect-betalingen).
     * Retourneert null als niet gevonden of geen Connect-betaling.
     */
    protected function fetchMolliePaymentStatusForConnect(string $paymentId): ?string
    {
        $lookup = $this->lookupBookingByMolliePaymentId($paymentId);
        if (!$lookup) {
            return null;
        }

        $profile = DB::table('gymies_trainer_profiles')
            ->where('user_id', $lookup['trainer_user_id'])
            ->first(['mollie_access_token']);
        $encrypted = $profile->mollie_access_token ?? null;
        if (empty($encrypted)) {
            return null;
        }

        try {
            $accessToken = decrypt($encrypted);
        } catch (\Throwable $e) {
            return null;
        }

        $resp = Http::withToken($accessToken)
            ->timeout(10)
            ->get('https://api.mollie.com/v2/payments/' . $paymentId);

        if (!$resp->successful()) {
            return null;
        }
        $status = $resp->json('status');
        return is_string($status) ? $status : null;
    }
}
