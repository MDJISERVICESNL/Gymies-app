<?php

declare(strict_types=1);

namespace App\Services;

use App\Http\Controllers\Gymies\GymiesFeatureFlags;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Carbon\Carbon;

/**
 * Gymies Trial Extension Service
 * ──────────────────────────────
 * Smart trial verlengingen door staff met activiteitsscoring.
 *
 * Staff kan kiezen uit 7, 14 of 30 dagen verlenging.
 * Activity snapshot wordt automatisch berekend en opgeslagen.
 *
 * Activity score componenten:
 * - Etalage completeness (0-100)
 * - Aantal boekingen in trial
 * - Aantal berichten verstuurd
 * - App opens (laatste 7 dagen)
 */
final class TrialExtensionService
{
    private const TABLE = 'gymies_trial_extensions';
    private const ALLOWED_DAYS = [7, 14, 30];
    private const MAX_EXTENSIONS = 3; // Max 3 verlengingen per trainer

    /**
     * Verleng trial van een trainer.
     */
    public static function extend(int $trainerId, int $staffId, int $days, ?string $reason = null): array
    {
        // Check of smart trial extension is ingeschakeld
        if (!GymiesFeatureFlags::isEnabled('smart_trial_extension')) {
            return ['success' => false, 'error' => 'Trial verlengingen zijn momenteel uitgeschakeld.'];
        }

        if (!in_array($days, self::ALLOWED_DAYS, true)) {
            return ['success' => false, 'error' => 'Ongeldige verlenging. Kies 7, 14 of 30 dagen.'];
        }

        $profile = DB::table('gymies_trainer_profiles')->where('id', $trainerId)->first();
        if (!$profile) {
            return ['success' => false, 'error' => 'Trainer niet gevonden.'];
        }

        $status = $profile->onboarding_status ?? 'incomplete';
        if (!in_array($status, ['approved', 'active'], true)) {
            return ['success' => false, 'error' => 'Trial kan alleen verlengd worden voor goedgekeurde/actieve trainers.'];
        }

        // Check max verlengingen
        if (Schema::hasTable(self::TABLE)) {
            $extensionCount = DB::table(self::TABLE)
                ->where('trainer_id', $trainerId)
                ->count();

            if ($extensionCount >= self::MAX_EXTENSIONS) {
                return ['success' => false, 'error' => 'Maximum aantal verlengingen bereikt (' . self::MAX_EXTENSIONS . ').'];
            }
        }

        $now = Carbon::now();
        $previousEnd = $profile->trial_ends_at ? Carbon::parse($profile->trial_ends_at) : $now;
        $newEnd = $previousEnd->copy()->addDays($days);

        // Activity snapshot verzamelen
        $activitySnapshot = self::getActivitySnapshot($trainerId);

        DB::beginTransaction();
        try {
            // Update trial_ends_at
            DB::table('gymies_trainer_profiles')
                ->where('id', $trainerId)
                ->update([
                    'trial_ends_at' => $newEnd,
                    'updated_at'    => $now,
                ]);

            // Log verlenging
            if (Schema::hasTable(self::TABLE)) {
                DB::table(self::TABLE)->insert([
                    'trainer_id'         => $trainerId,
                    'extended_by_id'     => $staffId,
                    'days'               => $days,
                    'reason'             => $reason,
                    'activity_snapshot'  => json_encode($activitySnapshot),
                    'previous_trial_end' => $profile->trial_ends_at,
                    'new_trial_end'      => $newEnd,
                    'created_at'         => $now,
                    'updated_at'         => $now,
                ]);
            }

            // Audit trail
            if (Schema::hasTable('gymies_staff_audit_log')) {
                DB::table('gymies_staff_audit_log')->insert([
                    'staff_id'    => $staffId,
                    'action'      => 'trial.extended',
                    'target_type' => 'TrainerProfile',
                    'target_id'   => $trainerId,
                    'metadata'    => json_encode([
                        'days'               => $days,
                        'reason'             => $reason,
                        'previous_trial_end' => $profile->trial_ends_at,
                        'new_trial_end'      => $newEnd->toIso8601String(),
                        'activity_score'     => $activitySnapshot['total_score'] ?? 0,
                    ]),
                    'ip_address'  => request()?->ip(),
                    'created_at'  => $now,
                    'updated_at'  => $now,
                ]);
            }

            // Update Mollie subscription startDate als die bestaat
            self::updateMollieSubscriptionStart($profile, $newEnd);

            DB::commit();

            // Push notificatie naar trainer (buiten transactie)
            try {
                $trainerName = DB::table('gymies_users')->where('id', $profile->user_id)->value('display_name') ?? 'Trainer';
                $notifier = new OnboardingNotificationService();
                $notifier->notifyTrialExtended($profile->user_id, $trainerName, $days, $newEnd->format('d-m-Y'));
            } catch (\Throwable $e) {
                Log::warning('TrialExtensionService@extend notification failed', ['error' => $e->getMessage()]);
            }

            return [
                'success'            => true,
                'new_trial_end'      => $newEnd->toIso8601String(),
                'previous_trial_end' => $profile->trial_ends_at,
                'days_added'         => $days,
                'activity_score'     => $activitySnapshot['total_score'] ?? 0,
                'extensions_used'    => ($extensionCount ?? 0) + 1,
                'extensions_remaining' => self::MAX_EXTENSIONS - (($extensionCount ?? 0) + 1),
            ];
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('TrialExtensionService@extend FAILED', [
                'trainer_id' => $trainerId,
                'error' => $e->getMessage(),
            ]);
            return ['success' => false, 'error' => 'Verlenging mislukt: ' . $e->getMessage()];
        }
    }

    /**
     * Haal activiteitsscore op voor een trainer.
     */
    public static function getActivitySnapshot(int $trainerId): array
    {
        $profile = DB::table('gymies_trainer_profiles')->where('id', $trainerId)->first();
        $userId = $profile->user_id ?? 0;

        $snapshot = [
            'etalage_score'  => self::calculateEtalageScore($profile),
            'bookings_count' => self::countBookings($trainerId),
            'messages_count' => self::countMessages((int) $userId),
            'app_opens_7d'   => self::countAppOpens((int) $userId),
        ];

        // Totaalscore (gewogen gemiddelde)
        $snapshot['total_score'] = (int) round(
            ($snapshot['etalage_score'] * 0.30) +
            (min($snapshot['bookings_count'] * 10, 100) * 0.30) +
            (min($snapshot['messages_count'] * 5, 100) * 0.20) +
            (min($snapshot['app_opens_7d'] * 3, 100) * 0.20)
        );

        return $snapshot;
    }

    /**
     * Haal verlengingshistorie op voor een trainer.
     */
    public static function getHistory(int $trainerId): array
    {
        if (!Schema::hasTable(self::TABLE)) {
            return [];
        }

        return DB::table(self::TABLE)
            ->where('trainer_id', $trainerId)
            ->orderByDesc('created_at')
            ->get()
            ->map(function ($row) {
                $row->activity_snapshot = json_decode($row->activity_snapshot ?? '{}', true);
                return $row;
            })
            ->toArray();
    }

    /**
     * Check of een trainer in aanmerking komt voor verlenging.
     */
    public static function canExtend(int $trainerId): array
    {
        if (!GymiesFeatureFlags::isEnabled('smart_trial_extension')) {
            return ['can_extend' => false, 'reason' => 'Trial verlengingen zijn momenteel uitgeschakeld.'];
        }

        $profile = DB::table('gymies_trainer_profiles')->where('id', $trainerId)->first();
        if (!$profile) {
            return ['can_extend' => false, 'reason' => 'Trainer niet gevonden.'];
        }

        $status = $profile->onboarding_status ?? 'incomplete';
        if (!in_array($status, ['approved', 'active'], true)) {
            return ['can_extend' => false, 'reason' => 'Trainer is niet goedgekeurd of actief.'];
        }

        $extensionCount = 0;
        if (Schema::hasTable(self::TABLE)) {
            $extensionCount = DB::table(self::TABLE)->where('trainer_id', $trainerId)->count();
        }

        if ($extensionCount >= self::MAX_EXTENSIONS) {
            return ['can_extend' => false, 'reason' => 'Maximum verlengingen bereikt.', 'used' => $extensionCount, 'max' => self::MAX_EXTENSIONS];
        }

        $trialEnd = $profile->trial_ends_at ? Carbon::parse($profile->trial_ends_at) : null;

        return [
            'can_extend'           => true,
            'extensions_used'      => $extensionCount,
            'extensions_remaining' => self::MAX_EXTENSIONS - $extensionCount,
            'current_trial_end'    => $trialEnd?->toIso8601String(),
            'trial_expired'        => $trialEnd ? $trialEnd->isPast() : false,
            'activity_score'       => self::getActivitySnapshot($trainerId),
        ];
    }

    /**
     * Overzicht van alle trainers met actieve/verlopen trials (voor staff dashboard).
     */
    public static function trialOverview(int $page = 1, int $perPage = 25): array
    {
        $query = DB::table('gymies_trainer_profiles')
            ->whereNotNull('trial_ends_at')
            ->whereIn('onboarding_status', ['approved', 'active'])
            ->orderBy('trial_ends_at');

        $total = $query->count();
        $data = $query->offset(($page - 1) * $perPage)->limit($perPage)->get();

        $now = Carbon::now();
        $enriched = $data->map(function ($profile) use ($now) {
            $trialEnd = Carbon::parse($profile->trial_ends_at);
            $profile->trial_expired = $trialEnd->isPast();
            $profile->days_remaining = $trialEnd->isPast() ? 0 : $now->diffInDays($trialEnd);
            $profile->urgency = match (true) {
                $trialEnd->isPast()           => 'expired',
                $profile->days_remaining <= 3 => 'critical',
                $profile->days_remaining <= 7 => 'warning',
                default                       => 'ok',
            };
            // Verrijk met trainernaam
            $user = DB::table('gymies_users')->where('id', $profile->user_id ?? 0)->first();
            $profile->user_name = trim(($user->first_name ?? '') . ' ' . ($user->last_name ?? ''));
            $profile->user_email = $user->email ?? '';
            // Activity score preview
            $snapshot = self::getActivitySnapshot((int) ($profile->id ?? 0));
            $profile->activity_score = $snapshot['total_score'] ?? 0;
            return $profile;
        });

        return ['data' => $enriched, 'total' => $total, 'page' => $page, 'per_page' => $perPage];
    }

    // ─── Private Helpers ─────────────────────────────────────────

    private static function calculateEtalageScore(?object $profile): int
    {
        if (!$profile) return 0;

        $score = 0;
        $checks = [
            'company_name' => 10,
            'kvk_number' => 10,
            'trainer_address_line1' => 10,
            'trainer_postcode' => 5,
            'trainer_city' => 5,
            'profile_slug' => 10,
            'bio' => 15,
            'profile_photo_url' => 15,
            'specialties' => 10,
            'diploma_urls' => 10,
        ];

        foreach ($checks as $field => $points) {
            $value = $profile->$field ?? null;
            if (!empty($value) && $value !== '[]' && $value !== 'null') {
                $score += $points;
            }
        }

        return min($score, 100);
    }

    private static function countBookings(int $trainerId): int
    {
        if (!Schema::hasTable('gymies_bookings')) return 0;

        try {
            return (int) DB::table('gymies_bookings')
                ->where('trainer_id', $trainerId)
                ->where('created_at', '>=', Carbon::now()->subDays(30))
                ->count();
        } catch (\Throwable) {
            return 0;
        }
    }

    private static function countMessages(int $userId): int
    {
        if (!Schema::hasTable('gymies_messages')) return 0;

        try {
            return (int) DB::table('gymies_messages')
                ->where('sender_id', $userId)
                ->where('created_at', '>=', Carbon::now()->subDays(30))
                ->count();
        } catch (\Throwable) {
            return 0;
        }
    }

    private static function countAppOpens(int $userId): int
    {
        if (!Schema::hasTable('gymies_sessions')) return 0;

        try {
            return (int) DB::table('gymies_sessions')
                ->where('user_id', $userId)
                ->where('last_activity_at', '>=', Carbon::now()->subDays(7))
                ->count();
        } catch (\Throwable) {
            return 0;
        }
    }

    private static function updateMollieSubscriptionStart(object $profile, Carbon $newEnd): void
    {
        $subscriptionId = $profile->mollie_subscription_id ?? null;
        $customerId = $profile->mollie_customer_id ?? null;

        if (empty($subscriptionId) || empty($customerId)) {
            return;
        }

        $apiKey = config('gymies.mollie_api_key');
        if (empty($apiKey)) return;

        try {
            // Mollie subscription update met nieuwe startDate
            \Illuminate\Support\Facades\Http::withToken($apiKey)
                ->timeout(15)
                ->patch("https://api.mollie.com/v2/customers/{$customerId}/subscriptions/{$subscriptionId}", [
                    'startDate' => $newEnd->format('Y-m-d'),
                ]);
        } catch (\Throwable $e) {
            Log::warning('Mollie subscription startDate update mislukt', [
                'subscription_id' => $subscriptionId,
                'error' => $e->getMessage(),
            ]);
        }
    }
}
