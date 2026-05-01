<?php

declare(strict_types=1);

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use App\Http\Controllers\Gymies\GymiesFeatureFlags;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;

/**
 * SendGymiesNotificationEmail
 * ───────────────────────────
 * Verstuurt notificatie-emails via de queue (async).
 * Voorkomt dat API responses vertraagd worden door SMTP calls.
 *
 * Gebruik (aanbevolen — respecteert feature flag):
 *   SendGymiesNotificationEmail::sendOrQueue(
 *       $userId,
 *       'booking_confirmed',
 *       ['booking_id' => 123, 'trainer_name' => 'John']
 *   );
 *
 * Of direct via queue (negeert feature flag):
 *   SendGymiesNotificationEmail::dispatch($userId, 'booking_confirmed', [...]);
 *
 * Feature flag: 'queue_emails'
 *   AAN  → emails via async queue (PM2 worker)
 *   UIT  → emails direct/sync (fallback)
 *
 * De job probeert 3x, met 60s delay tussen retries.
 * Na 3 mislukte pogingen wordt de job in failed_jobs gezet.
 */
class SendGymiesNotificationEmail implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;
    public array $backoff = [60, 120, 300]; // 1min, 2min, 5min

    public function __construct(
        private readonly int    $userId,
        private readonly string $type,
        private readonly array  $data = [],
    ) {
        $this->onQueue('emails');
    }

    /**
     * Verstuur email direct (sync) als fallback wanneer queue_emails flag uit staat.
     * Wordt aangeroepen vanuit de dispatch-helper.
     */
    public static function sendOrQueue(int $userId, string $type, array $data = []): void
    {
        if (GymiesFeatureFlags::isEnabled('queue_emails')) {
            // Async via queue
            self::dispatch($userId, $type, $data);
        } else {
            // Sync fallback — direct versturen
            (new self($userId, $type, $data))->handle();
        }
    }

    public function handle(): void
    {
        // Haal user op
        $user = DB::table('gymies_users')->where('id', $this->userId)->first();
        if (!$user || empty($user->email)) {
            Log::warning("[Queue] SendGymiesNotificationEmail: user {$this->userId} niet gevonden of geen email");
            return;
        }

        $subject = $this->resolveSubject();
        $body    = $this->resolveBody($user);

        try {
            Mail::raw($body, function ($message) use ($user, $subject) {
                $message->to($user->email, $user->display_name ?? '')
                    ->subject($subject);
            });

            Log::info("[Queue] Email verstuurd: type={$this->type} user={$this->userId}");
        } catch (\Throwable $e) {
            Log::error("[Queue] Email versturen mislukt: {$e->getMessage()}", [
                'type'    => $this->type,
                'user_id' => $this->userId,
            ]);
            throw $e; // Laat de queue het opnieuw proberen
        }
    }

    private function resolveSubject(): string
    {
        return match ($this->type) {
            'booking_confirmed'  => 'GYMIES — Je boeking is bevestigd',
            'booking_cancelled'  => 'GYMIES — Boeking geannuleerd',
            'payment_received'   => 'GYMIES — Betaling ontvangen',
            'session_reminder'   => 'GYMIES — Sessie herinnering',
            'new_message'        => 'GYMIES — Nieuw bericht',
            'sos_alert'          => 'GYMIES — SOS Melding',
            default              => 'GYMIES — Notificatie',
        };
    }

    private function resolveBody(object $user): string
    {
        $name = $user->display_name ?? 'Gymies gebruiker';

        return match ($this->type) {
            'booking_confirmed'  => "Hoi {$name},\n\nJe boeking bij " . ($this->data['trainer_name'] ?? 'je trainer') . " is bevestigd.\n\nTot dan!\n— Team GYMIES",
            'booking_cancelled'  => "Hoi {$name},\n\nJe boeking is geannuleerd.\n\n— Team GYMIES",
            'payment_received'   => "Hoi {$name},\n\nWe hebben je betaling ontvangen. Bedankt!\n\n— Team GYMIES",
            'session_reminder'   => "Hoi {$name},\n\nHerinnering: je sessie begint binnenkort.\n\n— Team GYMIES",
            default              => "Hoi {$name},\n\nJe hebt een nieuwe notificatie in de GYMIES app.\n\n— Team GYMIES",
        };
    }
}
