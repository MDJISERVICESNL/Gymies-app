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
            // Kolom bestaat niet → log en geef pro (graceful)
            \Log::info('[PlanManager] subscription_plan kolom ontbreekt, default=pro', ['user_id' => $trainerUserId]);
            return 'pro';
        }
        $plan = DB::table('gymies_trainer_profiles')
            ->where('user_id', $trainerUserId)
            ->value('subscription_plan');
        $p = strtolower(trim((string) ($plan ?? '')));

        \Log::info('[PlanManager] Plan lookup', ['user_id' => $trainerUserId, 'raw_plan' => $plan, 'normalized' => $p]);

        // Pro varianten
        if (in_array($p, ['pro', 'pro_monthly', 'pro_yearly', 'pro_annual'], true)) {
            return 'pro';
        }
        // Pro+ / Studio / Elite varianten
        if (in_array($p, ['studio', 'elite', 'pro_plus', 'pro+', 'proplus', 'pro_plus_monthly', 'pro_plus_yearly'], true)) {
            return 'studio';
        }
        // Lege waarde of onbekend plan → default naar pro (niet blokkeren)
        if ($p === '' || $p === null) {
            \Log::info('[PlanManager] Leeg plan, default=pro', ['user_id' => $trainerUserId]);
            return 'pro';
        }

        // Onbekend plan → log maar laat door als pro
        \Log::warning('[PlanManager] Onbekend plan, default=pro', ['user_id' => $trainerUserId, 'plan' => $p]);
        return 'pro';
    }

    public static function can(int $trainerUserId, string $feature): bool
    {
        $plan = self::trainerPlanSlug($trainerUserId);
        return match ($feature) {
            self::FEATURE_GROUP_SESSIONS => $plan === 'pro' || $plan === 'studio',
            self::FEATURE_TEAM => $plan === 'studio',
            self::FEATURE_INVOICE_BRANDED => $plan === 'pro' || $plan === 'studio',
            'storefront' => $plan === 'pro' || $plan === 'studio',
            'pro_plus'   => $plan === 'studio',
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

    /** @return array{allowed: bool, message: string, upgrade_hint: string} */
    public static function assertPro(int $trainerUserId): array
    {
        $plan = self::trainerPlanSlug($trainerUserId);
        if ($plan === 'pro' || $plan === 'studio') {
            return ['allowed' => true, 'message' => '', 'upgrade_hint' => ''];
        }
        return [
            'allowed' => false,
            'message' => 'Storefront & Widget functies zijn beschikbaar vanaf Gymies Pro.',
            'upgrade_hint' => 'Upgrade naar Pro voor je eigen booking widget, QR-code en etalagepagina.',
        ];
    }

    /** @return array{allowed: bool, message: string, upgrade_hint: string} */
    public static function assertProPlus(int $trainerUserId): array
    {
        $plan = self::trainerPlanSlug($trainerUserId);
        if ($plan === 'studio') {
            return ['allowed' => true, 'message' => '', 'upgrade_hint' => ''];
        }
        return [
            'allowed' => false,
            'message' => 'Deze functie is beschikbaar vanaf Pro+/Studio.',
            'upgrade_hint' => 'Upgrade naar Studio voor geavanceerde widget-statistieken en nieuwsbrieven.',
        ];
    }
}
