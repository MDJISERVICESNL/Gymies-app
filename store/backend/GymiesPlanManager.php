<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * SaaS-limieten per plan technisch afdwingen. Kopieer naar app/Http/Controllers/Gymies/.
 */
final class GymiesPlanManager
{
    public const FEATURE_GROUP_SESSIONS = 'group_sessions';
    public const FEATURE_TEAM = 'team';
    public const FEATURE_INVOICE_BRANDED = 'invoice_branded';

    public static function trainerPlanSlug(int $trainerUserId): string
    {
        if (!Schema::hasTable('gymies_trainer_profiles')
            || !Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
            return 'starter';
        }
        $row = DB::table('gymies_trainer_profiles')
            ->where('user_id', $trainerUserId)
            ->first();
        if (!$row) {
            return 'starter';
        }
        if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_valid_until') && $row->subscription_valid_until !== null) {
            $validUntil = \Carbon\Carbon::parse($row->subscription_valid_until)->startOfDay();
            if ($validUntil->isPast()) {
                return 'starter';
            }
        }
        if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_pending_downgrade')
            && ($row->subscription_pending_downgrade ?? false)
            && isset($row->subscription_downgrades_at) && $row->subscription_downgrades_at !== null) {
            $downgradesAt = \Carbon\Carbon::parse($row->subscription_downgrades_at)->startOfDay();
            if ($downgradesAt->isPast() || $downgradesAt->isToday()) {
                $to = strtolower(trim((string) ($row->subscription_downgrade_to ?? 'starter')));
                if ($to === 'pro') return 'pro';
                if ($to === 'studio' || $to === 'elite') return 'studio';
                return 'starter';
            }
        }
        $plan = $row->subscription_plan ?? null;
        $p = strtolower(trim((string) ($plan ?? '')));
        if ($p === 'pro') {
            return 'pro';
        }
        if ($p === 'studio' || $p === 'elite') {
            return 'studio';
        }
        return 'starter';
    }

    public static function can(int $trainerUserId, string $feature): bool
    {
        $plan = self::trainerPlanSlug($trainerUserId);
        return match ($feature) {
            self::FEATURE_GROUP_SESSIONS => $plan === 'pro' || $plan === 'studio',
            self::FEATURE_TEAM => $plan === 'studio',
            self::FEATURE_INVOICE_BRANDED => $plan === 'pro' || $plan === 'studio',
            default => false,
        };
    }

    /** @return array{allowed: bool, message: string, upgrade_hint: string} */
    public static function assertGroupSessions(int $trainerUserId): array
    {
        if (self::can($trainerUserId, self::FEATURE_GROUP_SESSIONS)) {
            return ['allowed' => true, 'message' => '', 'upgrade_hint' => ''];
        }
        return [
            'allowed' => false,
            'message' => 'Groepslessen zijn beschikbaar vanaf Gymies Pro.',
            'upgrade_hint' => 'Je bereikt je plafond! Stap over naar Pro voor onbeperkte groepslessen en automatische facturatie.',
        ];
    }

    /** @return array{allowed: bool, message: string, upgrade_hint: string} */
    public static function assertTeam(int $trainerUserId): array
    {
        if (self::can($trainerUserId, self::FEATURE_TEAM)) {
            return ['allowed' => true, 'message' => '', 'upgrade_hint' => ''];
        }
        return [
            'allowed' => false,
            'message' => 'Teamfuncties zijn beschikbaar vanaf Studio/Elite.',
            'upgrade_hint' => 'Upgrade naar Studio om teamleden toe te voegen.',
        ];
    }
}
