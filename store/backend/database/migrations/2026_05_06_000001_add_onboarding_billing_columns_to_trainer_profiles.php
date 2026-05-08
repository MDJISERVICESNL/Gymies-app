<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

/**
 * Onboarding & Billing Systeem — trainer_profiles uitbreiden.
 *
 * Nieuwe kolommen:
 * - onboarding_status       → state machine: incomplete → pending_review → approved → active (of rejected/suspended)
 * - billing_cycle            → maandelijks of jaarlijks
 * - selected_plan_slug       → gekozen plan (starter/pro/pro_plus)
 * - payment_route            → gymies_connect (standaard) of own_mollie
 * - mollie_customer_id       → Mollie klant-ID (Gymies Connect)
 * - mollie_mandate_id        → SEPA mandaat na €0,01 betaling
 * - mollie_subscription_id   → Actieve Mollie subscription
 * - trial_started_at         → Start trial periode
 * - trial_ends_at            → Einde trial periode
 * - promo_applied            → Welke promo is toegepast (bijv. 'launch_free_month')
 * - approved_at              → Wanneer goedgekeurd door staff
 * - approved_by              → Welke staff member heeft goedgekeurd
 * - rejection_reason         → Reden bij afwijzing
 * - invitation_code_used     → Welke uitnodigingscode gebruikt bij registratie
 */
return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        // Eerst de ENUM type aanmaken als die nog niet bestaat
        DB::statement("DO $$ BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'onboarding_status_enum') THEN
                CREATE TYPE onboarding_status_enum AS ENUM ('incomplete', 'pending_review', 'approved', 'rejected', 'active', 'suspended');
            END IF;
        END $$;");

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            // Onboarding status
            if (!Schema::hasColumn('gymies_trainer_profiles', 'onboarding_status')) {
                $table->string('onboarding_status', 20)->default('incomplete')
                    ->comment('State: incomplete|pending_review|approved|rejected|active|suspended');
            }

            // Billing & plan keuze
            if (!Schema::hasColumn('gymies_trainer_profiles', 'billing_cycle')) {
                $table->string('billing_cycle', 10)->default('monthly')
                    ->comment('monthly of yearly');
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'selected_plan_slug')) {
                $table->string('selected_plan_slug', 30)->nullable()
                    ->comment('starter, pro, pro_plus');
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'payment_route')) {
                $table->string('payment_route', 20)->default('gymies_connect')
                    ->comment('gymies_connect of own_mollie');
            }

            // Mollie koppelingen (Gymies Connect route)
            if (!Schema::hasColumn('gymies_trainer_profiles', 'mollie_customer_id')) {
                $table->string('mollie_customer_id', 50)->nullable()
                    ->comment('Mollie customer ID voor Gymies Connect');
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'mollie_mandate_id')) {
                $table->string('mollie_mandate_id', 50)->nullable()
                    ->comment('SEPA mandaat ID na €0,01 betaling');
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'mollie_subscription_id')) {
                $table->string('mollie_subscription_id', 50)->nullable()
                    ->comment('Actieve Mollie subscription ID');
            }

            // Trial periode
            if (!Schema::hasColumn('gymies_trainer_profiles', 'trial_started_at')) {
                $table->timestamp('trial_started_at')->nullable();
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'trial_ends_at')) {
                $table->timestamp('trial_ends_at')->nullable();
            }

            // Promo & goedkeuring
            if (!Schema::hasColumn('gymies_trainer_profiles', 'promo_applied')) {
                $table->string('promo_applied', 50)->nullable()
                    ->comment('bijv. launch_free_month');
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'approved_at')) {
                $table->timestamp('approved_at')->nullable();
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'approved_by')) {
                $table->unsignedBigInteger('approved_by')->nullable();
                $table->foreign('approved_by')->references('id')->on('gymies_users')->nullOnDelete();
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'rejection_reason')) {
                $table->text('rejection_reason')->nullable();
            }

            // Uitnodigingscode tracking
            if (!Schema::hasColumn('gymies_trainer_profiles', 'invitation_code_used')) {
                $table->string('invitation_code_used', 30)->nullable()
                    ->comment('Code gebruikt bij registratie');
            }
        });

        // Indexen voor veelgebruikte queries
        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            $table->index('onboarding_status', 'idx_trainer_onboarding_status');
            $table->index('trial_ends_at', 'idx_trainer_trial_ends_at');
            $table->index('mollie_customer_id', 'idx_trainer_mollie_customer_id');
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            // Drop indexes
            $table->dropIndex('idx_trainer_onboarding_status');
            $table->dropIndex('idx_trainer_trial_ends_at');
            $table->dropIndex('idx_trainer_mollie_customer_id');

            // Drop foreign key
            if (Schema::hasColumn('gymies_trainer_profiles', 'approved_by')) {
                $table->dropForeign(['approved_by']);
            }
        });

        $columns = [
            'onboarding_status', 'billing_cycle', 'selected_plan_slug', 'payment_route',
            'mollie_customer_id', 'mollie_mandate_id', 'mollie_subscription_id',
            'trial_started_at', 'trial_ends_at', 'promo_applied',
            'approved_at', 'approved_by', 'rejection_reason', 'invitation_code_used',
        ];

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) use ($columns) {
            foreach ($columns as $col) {
                if (Schema::hasColumn('gymies_trainer_profiles', $col)) {
                    $table->dropColumn($col);
                }
            }
        });

        DB::statement("DROP TYPE IF EXISTS onboarding_status_enum;");
    }
};
