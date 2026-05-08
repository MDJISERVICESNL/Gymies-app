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
use Illuminate\Support\Facades\Schema;

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
        $textBody = $this->resolveBody($user);
        $htmlBody = null;

        // Use new branded templates for client-facing emails
        if (in_array($this->type, ['booking_confirmed', 'booking_cancelled', 'payment_received', 'session_reminder'], true)) {
            [$subject, $textBody, $htmlBody] = $this->buildClientTemplate($user);
        }

        // Onboarding-gerelateerde emails met templates
        $onboardingTypes = [
            'welcome_onboarding', 'onboarding_approved', 'onboarding_rejected',
            'trial_expiring_soon', 'payment_reminder',
            'onboarding_reminder_24h', 'onboarding_nudge_72h',
        ];
        if (in_array($this->type, $onboardingTypes, true)) {
            [$subject, $textBody, $htmlBody] = $this->buildOnboardingTemplate($user);
        }

        try {
            \App\Helpers\GymiesNotificationEmail::send(
                trim((string) $user->email),
                $subject,
                $textBody,
                $htmlBody,
            );

            Log::info("[Queue] Email verstuurd: type={$this->type} user={$this->userId}");
        } catch (\Throwable $e) {
            Log::error("[Queue] Email versturen mislukt: {$e->getMessage()}", [
                'type'    => $this->type,
                'user_id' => $this->userId,
            ]);
            throw $e; // Laat de queue het opnieuw proberen
        }
    }

    /**
     * Build branded client-facing email using GymiesMailTemplates.
     */
    private function buildClientTemplate(object $user): array
    {
        $clientName = $user->display_name ?? 'Gymies klant';
        $trainerId = (int) ($this->data['trainer_user_id'] ?? 0);
        $trainerBrand = $trainerId > 0 ? $this->getTrainerBrandingData($trainerId) : null;

        return match ($this->type) {
            'booking_confirmed' => \App\Helpers\GymiesMailTemplates::boekingBevestigd(
                $clientName,
                $this->data['trainer_name'] ?? 'Je trainer',
                $this->data['scheduled_at'] ?? now()->toDateTimeString(),
                (int) ($this->data['duration_minutes'] ?? 60),
                $trainerBrand,
            ),
            'booking_cancelled' => \App\Helpers\GymiesMailTemplates::boekingGeannuleerd(
                $clientName,
                $this->data['trainer_name'] ?? 'Je trainer',
                $this->data['reason'] ?? 'Geen reden opgegeven',
                $trainerBrand,
            ),
            'payment_received' => \App\Helpers\GymiesMailTemplates::betalingOntvangen(
                $clientName,
                $this->data['trainer_name'] ?? 'Je trainer',
                $this->data['amount'] ?? '€0,00',
                $trainerBrand,
            ),
            'session_reminder' => \App\Helpers\GymiesMailTemplates::boekingHerinnering(
                $clientName,
                $this->data['trainer_name'] ?? 'Je trainer',
                $this->data['scheduled_at'] ?? now()->toDateTimeString(),
                $trainerBrand,
            ),
            default => ['', '', null],
        };
    }

    /**
     * Build onboarding-specific email templates.
     */
    private function buildOnboardingTemplate(object $user): array
    {
        $trainerName = $this->data['trainer_name'] ?? $user->display_name ?? 'Trainer';

        return match ($this->type) {
            'welcome_onboarding'     => \App\Helpers\GymiesMailTemplates::welcomeOnboarding($trainerName),
            'onboarding_approved'    => \App\Helpers\GymiesMailTemplates::onboardingApproved($trainerName),
            'onboarding_rejected'    => \App\Helpers\GymiesMailTemplates::onboardingRejected(
                $trainerName,
                $this->data['reason'] ?? 'Geen reden opgegeven',
            ),
            'trial_expiring_soon'    => \App\Helpers\GymiesMailTemplates::trialExpiringSoon(
                $trainerName,
                (int) ($this->data['days_left'] ?? 3),
            ),
            'payment_reminder'       => \App\Helpers\GymiesMailTemplates::paymentReminder(
                $trainerName,
                (int) ($this->data['attempt'] ?? 1),
            ),
            'onboarding_reminder_24h' => \App\Helpers\GymiesMailTemplates::onboardingReminder24h($trainerName),
            'onboarding_nudge_72h'    => \App\Helpers\GymiesMailTemplates::onboardingNudge72h($trainerName),
            default                   => ['GYMIES — Notificatie', '', null],
        };
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

    /**
     * Get trainer branding data for Pro+ trainers.
     * Returns array with color, logo_url, name or null if not Pro+.
     */
    private function getTrainerBrandingData(int $trainerId): ?array
    {
        if (!Schema::hasTable('gymies_trainer_pro_plus_settings')) {
            return null;
        }
        $branding = DB::table('gymies_trainer_pro_plus_settings')
            ->where('trainer_user_id', $trainerId)
            ->first(['brand_color', 'brand_logo_url']);
        if (!$branding) {
            return null;
        }
        $color = trim((string) ($branding->brand_color ?? ''));
        $logoUrl = trim((string) ($branding->brand_logo_url ?? ''));
        if ($color === '' && $logoUrl === '') {
            return null;
        }
        $trainerName = DB::table('gymies_users')->where('id', $trainerId)->value('display_name') ?? 'Trainer';
        return [
            'color' => $color ?: '#FF8A00',
            'logo_url' => $logoUrl ?: null,
            'name' => $trainerName,
        ];
    }
}
