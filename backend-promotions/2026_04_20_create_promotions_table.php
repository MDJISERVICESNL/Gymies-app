<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies platform-promoties voor abonnementen.
 * Ondersteunt 4 types: discount_months, coupon, campaign, trial.
 *
 * Dit is NIET gymies_promo_codes (dat zijn trainer → klant promo's voor boekingen).
 * Dit is voor abonnement-promoties die Gymies zelf draait.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('gymies_promotions', function (Blueprint $table) {
            $table->id();
            $table->string('name');                                // Interne naam (bijv. "Zomeractie 2026")
            $table->string('slug', 64)->unique();                  // Unieke slug (bijv. "zomeractie-2026")
            $table->enum('type', [
                'discount_months',  // Eerste X maanden korting
                'coupon',           // Kortingscode
                'campaign',         // Tijdelijke actieprijs voor iedereen
                'trial',            // Gratis proefperiode
            ]);

            // ── Kortingswaarden ──
            $table->enum('discount_type', ['percent', 'fixed'])->default('percent'); // Aansluitend op gymies_promo_codes
            $table->unsignedInteger('value_cents')->default(0);    // 50 = 50% of 5000 = €50,00 (bij fixed)
            $table->unsignedInteger('discount_months')->nullable(); // Hoeveel maanden korting geldt
            $table->unsignedInteger('trial_days')->nullable();     // Proefperiode in dagen (type=trial)

            // ── Actieprijs (campaign) ──
            $table->unsignedInteger('campaign_price_cents')->nullable(); // Vaste actieprijs in centen

            // ── Geldigheid ──
            $table->date('valid_from')->nullable();                // Aansluitend op gymies_promo_codes naamgeving
            $table->date('valid_until')->nullable();
            $table->boolean('is_active')->default(true);

            // ── Beperkingen ──
            $table->unsignedInteger('max_uses')->nullable();       // Max totaal gebruik (null = onbeperkt)
            $table->unsignedInteger('use_count')->default(0);      // Aansluitend op gymies_promo_codes
            $table->unsignedInteger('max_uses_per_trainer')->default(1);

            // ── Code (coupon type) ──
            $table->string('code', 64)->nullable()->unique();      // Kortingscode (bijv. "GYMIES50")

            // ── Toepasbaarheid ──
            $table->json('applicable_plan_ids')->nullable();       // [1, 2, 3] = welke gymies_plans.id's
            $table->json('applicable_slugs')->nullable();          // ["pro", "pro_plus"] = welke plan slugs
            $table->boolean('new_subscriptions_only')->default(true);

            // ── Weergave (dynamisch in app) ──
            $table->string('display_label', 255)->nullable();      // "50% korting eerste 3 maanden"
            $table->string('display_badge', 64)->nullable();       // "ZOMERACTIE"
            $table->text('description')->nullable();

            // ── Mollie ──
            $table->string('mollie_coupon_id', 64)->nullable();

            $table->timestamps();
            $table->softDeletes();

            $table->index('type');
            $table->index('is_active');
            $table->index(['valid_from', 'valid_until']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_promotions');
    }
};
