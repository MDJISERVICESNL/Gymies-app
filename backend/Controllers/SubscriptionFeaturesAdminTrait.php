<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trait voor GymiesAdminController – subscription features beheer (database).
 * Voeg toe: use SubscriptionFeaturesAdminTrait;
 */
trait SubscriptionFeaturesAdminTrait
{
    private const FEATURES_TABLE = 'gymies_subscription_features';

    /** GET vault-console/subscription-features – feature matrix. */
    public function subscriptionFeatures(): JsonResponse
    {
        $features = $this->getFeaturesFromDb();
        if (empty($features)) {
            $this->seedDefaultFeatures();
            $features = $this->getFeaturesFromDb();
        }

        return response()->json([
            'features' => $features,
            'tiers' => ['starter', 'pro', 'elite'],
        ]);
    }

    /** PUT vault-console/subscription-features – feature matrix opslaan. */
    public function updateSubscriptionFeatures(Request $request): JsonResponse
    {
        $request->validate(['features' => 'required|array']);
        $tiers = ['starter', 'pro', 'elite'];

        if (!Schema::hasTable(self::FEATURES_TABLE)) {
            return response()->json(['message' => 'Table not found. Run migration.'], 500);
        }

        DB::transaction(function () use ($request) {
            foreach ($request->input('features') as $i => $f) {
                $key = $f['key'] ?? 'feature_' . $i;
                DB::table(self::FEATURES_TABLE)->updateOrInsert(
                    ['key' => $key],
                    [
                        'label' => $f['label'] ?? $key,
                        'enabled_from' => $f['enabled_from'] ?? 'starter',
                        'type' => $f['type'] ?? 'boolean',
                        'limit_starter' => $f['limit_starter'] ?? null,
                        'limit_pro' => $f['limit_pro'] ?? null,
                        'limit_elite' => $f['limit_elite'] ?? null,
                        'sort_order' => $i,
                        'updated_at' => now(),
                    ]
                );
            }
        });

        return response()->json([
            'features' => $this->getFeaturesFromDb(),
            'tiers' => $tiers,
        ]);
    }

    private function getFeaturesFromDb(): array
    {
        if (!Schema::hasTable(self::FEATURES_TABLE)) {
            return [];
        }
        $rows = DB::table(self::FEATURES_TABLE)->orderBy('sort_order')->get();
        $out = [];
        foreach ($rows as $r) {
            $arr = [
                'key' => $r->key,
                'label' => $r->label,
                'enabled_from' => $r->enabled_from,
                'type' => $r->type ?? 'boolean',
            ];
            if ($r->limit_starter !== null) $arr['limit_starter'] = (int) $r->limit_starter;
            if ($r->limit_pro !== null) $arr['limit_pro'] = (int) $r->limit_pro;
            if ($r->limit_elite !== null) $arr['limit_elite'] = (int) $r->limit_elite;
            $out[] = $arr;
        }
        return $out;
    }

    private function seedDefaultFeatures(): void
    {
        $defaults = $this->defaultSubscriptionFeatures();
        foreach ($defaults as $i => $f) {
            DB::table(self::FEATURES_TABLE)->updateOrInsert(
                ['key' => $f['key']],
                [
                    'label' => $f['label'],
                    'enabled_from' => $f['enabled_from'],
                    'type' => $f['type'] ?? 'boolean',
                    'limit_starter' => $f['limit_starter'] ?? null,
                    'limit_pro' => $f['limit_pro'] ?? null,
                    'limit_elite' => $f['limit_elite'] ?? null,
                    'sort_order' => $i,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]
            );
        }
    }

    /** Default feature matrix – zie SUBSCRIPTION_FEATURES.md. */
    private function defaultSubscriptionFeatures(): array
    {
        return [
            ['key' => 'sessions', 'label' => 'Sessiebeheer', 'enabled_from' => 'starter', 'type' => 'boolean'],
            ['key' => 'messages', 'label' => 'Berichten (1-op-1 chat)', 'enabled_from' => 'starter', 'type' => 'boolean'],
            ['key' => 'agenda', 'label' => 'Agenda', 'enabled_from' => 'starter', 'type' => 'boolean'],
            ['key' => 'invoice', 'label' => 'Factuur opstellen', 'enabled_from' => 'starter', 'type' => 'boolean'],
            ['key' => 'documents', 'label' => 'Documenten', 'enabled_from' => 'starter', 'type' => 'boolean'],
            ['key' => 'income', 'label' => 'Inkomstenoverzicht', 'enabled_from' => 'starter', 'type' => 'boolean'],
            ['key' => 'checkin', 'label' => 'Check-in scanner', 'enabled_from' => 'starter', 'type' => 'boolean'],
            ['key' => 'waitlist', 'label' => 'Wachtlijst / standby', 'enabled_from' => 'starter', 'type' => 'boolean'],
            ['key' => 'dossier', 'label' => 'Dossier opstellen per klant', 'enabled_from' => 'pro', 'type' => 'boolean'],
            ['key' => 'goals', 'label' => 'Doelen instellen per klant', 'enabled_from' => 'pro', 'type' => 'boolean'],
            ['key' => 'health_score', 'label' => 'Client health score', 'enabled_from' => 'pro', 'type' => 'boolean'],
            ['key' => 'upsell', 'label' => 'Upsell suggesties', 'enabled_from' => 'pro', 'type' => 'boolean'],
            ['key' => 'rebook', 'label' => 'Herboek suggesties', 'enabled_from' => 'pro', 'type' => 'boolean'],
            ['key' => 'priority_support', 'label' => 'Priority support lane', 'enabled_from' => 'pro', 'type' => 'boolean'],
            ['key' => 'bulk_message', 'label' => 'Bulk bericht naar klanten', 'enabled_from' => 'pro', 'type' => 'boolean'],
            ['key' => 'client_tags', 'label' => 'Klanttags/labels', 'enabled_from' => 'pro', 'type' => 'boolean'],
            ['key' => 'advanced_reporting', 'label' => 'Geavanceerde rapportage', 'enabled_from' => 'elite', 'type' => 'boolean'],
            ['key' => 'suite_tools', 'label' => 'Organisatie Elite mode', 'enabled_from' => 'elite', 'type' => 'boolean'],
            ['key' => 'promoted_profile', 'label' => 'Promoted profiel', 'enabled_from' => 'elite', 'type' => 'boolean'],
            ['key' => 'profile_videos', 'label' => 'Videos op profiel', 'enabled_from' => 'pro', 'type' => 'limit', 'limit_pro' => 1, 'limit_elite' => -1],
            ['key' => 'profile_stories', 'label' => 'Story-achtig op profiel', 'enabled_from' => 'pro', 'type' => 'limit', 'limit_pro' => 1, 'limit_elite' => -1],
            ['key' => 'max_clients', 'label' => 'Aantal actieve klanten', 'enabled_from' => 'starter', 'type' => 'limit', 'limit_starter' => -1, 'limit_pro' => -1, 'limit_elite' => -1],
        ];
    }
}
