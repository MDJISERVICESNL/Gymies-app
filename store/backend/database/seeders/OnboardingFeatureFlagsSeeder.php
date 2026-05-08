<?php

declare(strict_types=1);

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Seed feature flags voor het nieuwe onboarding systeem.
 *
 * php artisan db:seed --class=OnboardingFeatureFlagsSeeder
 */
class OnboardingFeatureFlagsSeeder extends Seeder
{
    public function run(): void
    {
        if (!Schema::hasTable('gymies_feature_flags')) {
            $this->command->warn('gymies_feature_flags tabel bestaat niet. Draai eerst de migraties.');
            return;
        }

        $flags = [
            // ─── Boolean Flags ────────────────────────────────────────
            [
                'key'                => 'launch_promo_free_month',
                'name'               => 'Launch Promo: Eerste Maand Gratis',
                'description'        => 'Nieuwe trainers krijgen hun eerste maand gratis (stapelbaar met jaarabonnement korting). Handmatig uit te zetten via admin.',
                'enabled'            => true,
                'value'              => null,
                'value_type'         => 'boolean',
                'category'           => 'onboarding',
                'allowed_roles'      => json_encode(['trainer']),
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],
            [
                'key'                => 'require_invitation_code',
                'name'               => 'Uitnodigingscode Vereist',
                'description'        => 'Trainers kunnen alleen registreren met een geldige uitnodigingscode (soft launch). Uitzetten voor open registratie.',
                'enabled'            => true,
                'value'              => null,
                'value_type'         => 'boolean',
                'category'           => 'onboarding',
                'allowed_roles'      => json_encode(['trainer']),
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],
            [
                'key'                => 'smart_trial_extension',
                'name'               => 'Smart Trial Verlenging',
                'description'        => 'Staff kan trials slim verlengen op basis van activiteitsscoring. Uit = verlengoptie niet beschikbaar.',
                'enabled'            => true,
                'value'              => null,
                'value_type'         => 'boolean',
                'category'           => 'onboarding',
                'allowed_roles'      => json_encode(['admin', 'staff', 'medewerker']),
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],
            [
                'key'                => 'staff_dashboard',
                'name'               => 'Medewerkers Dashboard',
                'description'        => 'Toegang tot het staff dashboard in de app voor het afhandelen van onboarding aanvragen, trial verlengingen en uitnodigingscodes.',
                'enabled'            => true,
                'value'              => null,
                'value_type'         => 'boolean',
                'category'           => 'general',
                'allowed_roles'      => json_encode(['admin', 'staff', 'medewerker']),
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],
            [
                'key'                => 'gymies_connect_payments',
                'name'               => 'Gymies Connect Betalingen',
                'description'        => 'Gymies int betalingen van klanten en betaalt trainers uit (minus commissie). Standaard route voor nieuwe trainers.',
                'enabled'            => true,
                'value'              => null,
                'value_type'         => 'boolean',
                'category'           => 'billing',
                'allowed_roles'      => json_encode(['trainer']),
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],
            [
                'key'                => 'fraud_detection',
                'name'               => 'Fraude Detectie',
                'description'        => 'Automatische checks op duplicate KvK, IBAN en ID documenten bij onboarding review.',
                'enabled'            => true,
                'value'              => null,
                'value_type'         => 'boolean',
                'category'           => 'security',
                'allowed_roles'      => null,
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],

            // ─── Configureerbare Flags (met value) ────────────────────
            [
                'key'                => 'yearly_discount_months',
                'name'               => 'Jaarlijkse Korting: Gratis Maanden',
                'description'        => 'Aantal gratis maanden bij jaarabonnement. Standaard 2 (betaal 10, krijg 12). Zet op 0 om korting uit te schakelen.',
                'enabled'            => true,
                'value'              => '2',
                'value_type'         => 'integer',
                'category'           => 'billing',
                'allowed_roles'      => null,
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],
            [
                'key'                => 'mandaat_amount',
                'name'               => 'Mandaat Bedrag (EUR)',
                'description'        => 'Bedrag voor de eerste SEPA mandaat betaling. Standaard 0.01 (1 cent). Zet op 1.00 voor A/B test met hoger bedrag.',
                'enabled'            => true,
                'value'              => '0.01',
                'value_type'         => 'float',
                'category'           => 'billing',
                'allowed_roles'      => null,
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],
            [
                'key'                => 'review_sla_hours',
                'name'               => 'Review SLA (uren)',
                'description'        => 'Maximaal aantal uren voor staff om een onboarding review af te handelen. Na deze tijd wordt een SLA waarschuwing verstuurd.',
                'enabled'            => true,
                'value'              => '48',
                'value_type'         => 'integer',
                'category'           => 'onboarding',
                'allowed_roles'      => null,
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],
            [
                'key'                => 'max_referral_codes_per_trainer',
                'name'               => 'Max Referral Codes per Trainer',
                'description'        => 'Maximum aantal verwijzingscodes dat een trainer kan aanmaken. Standaard 5.',
                'enabled'            => true,
                'value'              => '5',
                'value_type'         => 'integer',
                'category'           => 'onboarding',
                'allowed_roles'      => null,
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],
            [
                'key'                => 'ticket_auto_assign',
                'name'               => 'Ticket Auto-assign',
                'description'        => 'Wanneer ingeschakeld kunnen staff leden onbeheerde tickets automatisch round-robin verdelen over beschikbare medewerkers.',
                'enabled'            => false,
                'value'              => 'true',
                'value_type'         => 'boolean',
                'category'           => 'support',
                'allowed_roles'      => null,
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],

            // ─── Founding Partner Badge ──────────────────────────────────
            [
                'key'                => 'founding_partner_badge_enabled',
                'name'               => 'Founding Partner Badge',
                'description'        => 'Toon de Founding Partner badge bij trainers die zich vóór de cutoff datum hebben geregistreerd. Zet uit om de badge voor iedereen te verbergen.',
                'enabled'            => true,
                'value'              => null,
                'value_type'         => 'boolean',
                'category'           => 'general',
                'allowed_roles'      => json_encode(['trainer']),
                'allowed_user_ids'   => null,
                'rollout_percentage' => 100.00,
            ],
            [
                'key'                => 'founding_partner_cutoff_date',
                'name'               => 'Founding Partner Cutoff Datum',
                'description'        => 'Trainers geregistreerd vóór deze datum krijgen de Founding Partner badge. Formaat: YYYY-MM-DD (bijv. 2026-09-01).',
                'enabled'            => true,
                'value'              => '2026-09-01',
                'value_type'         => 'string',
                'category'           => 'general',
                'allowed_roles'      => null,
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

        $this->command->info('✓ ' . count($flags) . ' onboarding feature flags geseeded.');
    }
}
