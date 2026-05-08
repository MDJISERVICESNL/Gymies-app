<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fase E: Feature Flags uitbreiden met configureerbare waarden.
 *
 * Voegt een 'value' kolom toe zodat flags naast boolean (enabled/disabled)
 * ook numerieke en string waarden kunnen bevatten, zoals:
 * - mandaat_amount: "0.01" of "1.00" (A/B test)
 * - yearly_discount_months: "2"
 * - review_sla_hours: "48"
 * - max_referral_codes_per_trainer: "5"
 */
return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('gymies_feature_flags')) return;

        if (!Schema::hasColumn('gymies_feature_flags', 'value')) {
            Schema::table('gymies_feature_flags', function (Blueprint $table) {
                $table->string('value', 500)->nullable()->after('enabled')
                    ->comment('Configureerbare waarde (getal, string, JSON). Null = alleen boolean toggle.');
            });
        }

        if (!Schema::hasColumn('gymies_feature_flags', 'value_type')) {
            Schema::table('gymies_feature_flags', function (Blueprint $table) {
                $table->string('value_type', 20)->default('boolean')->after('value')
                    ->comment('Type: boolean, integer, float, string, json');
            });
        }

        if (!Schema::hasColumn('gymies_feature_flags', 'category')) {
            Schema::table('gymies_feature_flags', function (Blueprint $table) {
                $table->string('category', 50)->default('general')->after('value_type')
                    ->comment('Categorie voor groepering in dashboard: onboarding, billing, security, general');
            });
        }
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_feature_flags')) return;

        Schema::table('gymies_feature_flags', function (Blueprint $table) {
            if (Schema::hasColumn('gymies_feature_flags', 'value')) {
                $table->dropColumn('value');
            }
            if (Schema::hasColumn('gymies_feature_flags', 'value_type')) {
                $table->dropColumn('value_type');
            }
            if (Schema::hasColumn('gymies_feature_flags', 'category')) {
                $table->dropColumn('category');
            }
        });
    }
};
