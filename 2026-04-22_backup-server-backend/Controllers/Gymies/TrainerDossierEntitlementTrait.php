<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Blokkeert dossier- en session-notes-writes voor Starter-tier trainers.
 * Bij downgrade Pro→Starter blijven dossiers en doelen behouden (read-only).
 * GET blijft toegestaan.
 *
 * In GymiesTrainerOpsController: use TrainerDossierEntitlementTrait;
 * Aan het begin van clientDossierPut(): $this->abortIfDossierWriteDenied();
 * Aan het begin van clientProgressStore(): $this->abortIfDossierWriteDenied();
 * Aan het begin van de POST-handler voor trainer/clients/{id}/session-notes: $this->abortIfDossierWriteDenied();
 */
trait TrainerDossierEntitlementTrait
{
    protected function abortIfDossierWriteDenied(): void
    {
        $user = Auth::user();
        if (!$user) {
            abort(401, 'Unauthenticated');
        }
        $tier = $this->resolveTierForDossier($user);
        if ($tier === 'starter') {
            abort(403, 'Dossier bewerken vereist een Pro-abonnement. Upgrade om opnieuw te bewerken.');
        }
    }

    private function resolveTierForDossier($user): string
    {
        foreach (['subscription_tier', 'subscription_plan', 'plan', 'tier', 'plan_slug', 'plan_name'] as $k) {
            $v = $user->{$k} ?? ($user[$k] ?? null);
            if ($v !== null && trim((string) $v) !== '') {
                $t = strtolower(trim((string) $v));
                if (str_contains($t, 'elite') || str_contains($t, 'studio')) return 'elite';
                if (str_contains($t, 'pro')) return 'pro';
                if (str_contains($t, 'starter') || str_contains($t, 'basic')) return 'starter';
            }
        }
        if (Schema::hasTable('gymies_trainer_profiles')) {
            $row = DB::table('gymies_trainer_profiles')->where('user_id', $user->id ?? 0)->first();
            if ($row) {
                $profile = (array) $row;
                if ($this->isDossierSubscriptionExpired($profile)) {
                    return 'starter';
                }
                if ($this->isDossierPendingDowngradeEffective($profile)) {
                    return $this->dossierNormalizeTier($profile['subscription_downgrade_to'] ?? 'starter');
                }
                foreach (['subscription_plan', 'subscription_tier', 'plan', 'tier'] as $k) {
                    $v = $row->{$k} ?? null;
                    if ($v !== null && trim((string) $v) !== '') {
                        $t = strtolower(trim((string) $v));
                        if (str_contains($t, 'elite') || str_contains($t, 'studio')) return 'elite';
                        if (str_contains($t, 'pro')) return 'pro';
                    }
                }
            }
        }
        return 'starter';
    }

    private function isDossierSubscriptionExpired(array $profile): bool
    {
        $validUntil = $profile['subscription_valid_until'] ?? null;
        if ($validUntil === null) {
            return false;
        }
        $date = \Carbon\Carbon::parse($validUntil)->startOfDay();
        return $date->isPast();
    }

    /** Of pending downgrade al is ingegaan. */
    private function isDossierPendingDowngradeEffective(array $profile): bool
    {
        $pending = $profile['subscription_pending_downgrade'] ?? null;
        if (!$pending && $pending !== 1 && $pending !== true) {
            return false;
        }
        $downgradesAt = $profile['subscription_downgrades_at'] ?? null;
        if ($downgradesAt === null) {
            return false;
        }
        $date = \Carbon\Carbon::parse($downgradesAt)->startOfDay();
        return $date->isPast() || $date->isToday();
    }

    private function dossierNormalizeTier(?string $tier): string
    {
        if ($tier === null || trim((string) $tier) === '') {
            return 'starter';
        }
        $t = strtolower(trim((string) $tier));
        if (str_contains($t, 'elite') || str_contains($t, 'studio')) return 'elite';
        if (str_contains($t, 'pro')) return 'pro';
        return 'starter';
    }
}
