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
    public const FEATURE_BRANDING = 'branding';
    public const FEATURE_NEWSLETTER = 'newsletter';
    public const FEATURE_WIDGET = 'widget';
    public const FEATURE_QR_CODE = 'qr_code';
    public const FEATURE_ADVANCED_ANALYTICS = 'advanced_analytics';
    public const FEATURE_GYM = 'gym';

    public static function trainerPlanSlug(int $trainerUserId): string
    {
        if (!Schema::hasTable('gymies_trainer_profiles')
            || !Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
            return 'starter';
        }
        $plan = DB::table('gymies_trainer_profiles')
            ->where('user_id', $trainerUserId)
            ->value('subscription_plan');
        $p = strtolower(trim((string) ($plan ?? '')));
        if ($p === 'pro_plus' || $p === 'pro+') {
            return 'pro_plus';
        }
        if ($p === 'pro') {
            return 'pro';
        }
        if ($p === 'studio' || $p === 'elite') {
            return 'studio';
        }
        return 'starter';
    }

    /**
     * Zet plan slug naar tier number: starter=0, pro=1, pro_plus=2, studio=3
     */
    public static function planToTier(string $plan): int
    {
        $p = strtolower(trim($plan));
        return match ($p) {
            'starter', 'basic' => 0,
            'pro' => 1,
            'pro_plus', 'pro+' => 2,
            'studio', 'elite' => 3,
            default => 0,
        };
    }

    /**
     * Haal tier voor trainer op
     */
    public static function trainerPlanTier(int $trainerUserId): int
    {
        return self::planToTier(self::trainerPlanSlug($trainerUserId));
    }

    public static function can(int $trainerUserId, string $feature): bool
    {
        $tier = self::trainerPlanTier($trainerUserId);
        return match ($feature) {
            // Pro+ (tier 2) features
            self::FEATURE_BRANDING => $tier >= 2,
            self::FEATURE_NEWSLETTER => $tier >= 2,
            self::FEATURE_WIDGET => $tier >= 2,
            self::FEATURE_QR_CODE => $tier >= 2,
            self::FEATURE_ADVANCED_ANALYTICS => $tier >= 2,
            // Pro (tier 1) features
            self::FEATURE_GROUP_SESSIONS => $tier >= 1,
            self::FEATURE_INVOICE_BRANDED => $tier >= 1,
            // Studio (tier 3) features only
            self::FEATURE_TEAM => $tier >= 3,
            self::FEATURE_GYM => $tier >= 3,
            default => false,
        };
    }

    // T-046 FIXED: downgrade check — actieve groepslessen blokkeren downgrade
    public static function canDowngrade(int $trainerUserId, string $newPlanSlug): bool
    {
        $currentPlan = self::trainerPlanSlug($trainerUserId);
        // Pro/studio → starter: check actieve groepslessen
        $groupFeaturePlans = ['pro', 'studio'];
        $starterPlans = ['starter', 'basic'];
        if (in_array($currentPlan, $groupFeaturePlans, true) && in_array($newPlanSlug, $starterPlans, true)) {
            $hasActiveSessions = DB::table('gymies_group_sessions')
                ->where('trainer_user_id', $trainerUserId)
                ->whereIn('status', ['collecting', 'confirmed', 'auto_confirmed'])
                ->where('scheduled_at', '>=', now())
                ->exists();
            if ($hasActiveSessions) {
                return false; // T-046: downgrade geblokkeerd
            }
        }
        return true;
    }

    /**
     * Assert dat de trainer minimaal Pro (tier 1) heeft.
     * Gebruikt voor: promo-codes, CRM/dossier, sessie-notities, storefront CMS.
     * @return array{allowed: bool, message: string, upgrade_hint: string}
     */
    public static function assertPro(int $trainerUserId): array
    {
        if (self::trainerPlanTier($trainerUserId) >= 1) {
            return ['allowed' => true, 'message' => '', 'upgrade_hint' => ''];
        }
        return [
            'allowed' => false,
            'message' => 'Deze functie is beschikbaar vanaf Gymies Pro.',
            'upgrade_hint' => 'Upgrade naar Pro om promo-codes, CRM, sessie-notities en meer te gebruiken.',
        ];
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

    /** @return array{allowed: bool, message: string, upgrade_hint: string} */
    public static function assertProPlus(int $trainerUserId): array
    {
        if (self::can($trainerUserId, self::FEATURE_BRANDING)) {
            return ['allowed' => true, 'message' => '', 'upgrade_hint' => ''];
        }
        return [
            'allowed' => false,
            'message' => 'Deze functie vereist een Pro+ abonnement.',
            'upgrade_hint' => 'Upgrade naar Pro+ om custom branding, newsletter en meer te ontgrendelen.',
        ];
    }
}
