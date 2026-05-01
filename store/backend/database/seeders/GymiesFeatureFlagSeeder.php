<?php

declare(strict_types=1);

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * GymiesFeatureFlagSeeder
 * ───────────────────────
 * Zaait standaard feature flags. Draai:
 *   php artisan db:seed --class=GymiesFeatureFlagSeeder
 *
 * Bestaande flags worden NIET overschreven (updateOrInsert op key).
 */
class GymiesFeatureFlagSeeder extends Seeder
{
    public function run(): void
    {
        if (!Schema::hasTable('gymies_feature_flags')) {
            $this->command?->warn('gymies_feature_flags tabel ontbreekt. Draai migraties eerst.');
            return;
        }

        $flags = [
            [
                'key'                => 'buddy_bookings',
                'name'               => 'Buddy Boekingen',
                'description'        => 'Klanten kunnen een buddy uitnodigen voor hun sessie.',
                'enabled'            => false,
                'allowed_roles'      => json_encode(['client']),
                'allowed_user_ids'   => null,
                'rollout_percentage' => 10.00, // Start met 10% van de klanten
            ],
            [
                'key'                => 'group_sessions_v2',
                'name'               => 'Groepslessen V2',
                'description'        => 'Nieuwe groepsles-interface met wachtlijst en buddy-systeem.',
                'enabled'            => false,
                'allowed_roles'      => json_encode(['trainer', 'client']),
                'allowed_user_ids'   => null,
                'rollout_percentage' => 0.00, // Nog niet live
            ],
            [
                'key'                => 'ai_trainer_matching',
                'name'               => 'AI Trainer Matching',
                'description'        => 'Slimme trainer-suggesties gebaseerd op klantprofiel en doelen.',
                'enabled'            => false,
                'allowed_roles'      => json_encode(['client']),
                'allowed_user_ids'   => null,
                'rollout_percentage' => 0.00,
            ],
            [
                'key'                => 'advanced_analytics',
                'name'               => 'Geavanceerde Analytics',
                'description'        => 'Uitgebreide statistieken en rapporten voor Pro+ trainers.',
                'enabled'            => true,
                'allowed_roles'      => json_encode(['trainer']),
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00, // Volledig live voor trainers
            ],
            [
                'key'                => 'queue_emails',
                'name'               => 'Emails via Queue',
                'description'        => 'Verstuur emails via de queue i.p.v. sync. Verbetert API response times.',
                'enabled'            => true,
                'allowed_roles'      => null, // Alle rollen
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],
        ];

        foreach ($flags as $flag) {
            DB::table('gymies_feature_flags')->updateOrInsert(
                ['key' => $flag['key']],
                array_merge($flag, [
                    'created_at' => now(),
                    'updated_at' => now(),
                ])
            );
        }

        $this->command?->info(count($flags) . ' feature flags gezaaid.');
    }
}
