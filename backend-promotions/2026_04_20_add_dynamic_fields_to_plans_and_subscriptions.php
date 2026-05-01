<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Voegt dynamische velden toe aan gymies_plans (voor app zonder update)
 * en promo-tracking aan gymies_subscriptions.
 */
return new class extends Migration
{
    public function up(): void
    {
        // ── gymies_plans: dynamische weergave-velden ──
        Schema::table('gymies_plans', function (Blueprint $table) {
            $table->string('subtitle', 255)->nullable()->after('description');       // "Meest gekozen door trainers"
            $table->string('badge_label', 64)->nullable()->after('subtitle');        // "MEEST GEKOZEN"
            $table->string('promo_label', 255)->nullable()->after('badge_label');    // "Eerste maand gratis"
            $table->unsignedInteger('original_price_cents')->nullable()->after('promo_label'); // Doorstreepprijs bij actie
            $table->json('feature_list')->nullable()->after('original_price_cents'); // [{"label":"...", "description":"..."}]
        });

        // ── gymies_subscriptions: promo-tracking ──
        Schema::table('gymies_subscriptions', function (Blueprint $table) {
            $table->unsignedBigInteger('promotion_id')->nullable()->after('ambassador_discount_code');
            $table->string('promo_code_used', 64)->nullable()->after('promotion_id');

            $table->foreign('promotion_id')
                  ->references('id')->on('gymies_promotions')
                  ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('gymies_subscriptions', function (Blueprint $table) {
            $table->dropForeign(['promotion_id']);
            $table->dropColumn(['promotion_id', 'promo_code_used']);
        });

        Schema::table('gymies_plans', function (Blueprint $table) {
            $table->dropColumn([
                'subtitle', 'badge_label', 'promo_label',
                'original_price_cents', 'feature_list',
            ]);
        });
    }
};
