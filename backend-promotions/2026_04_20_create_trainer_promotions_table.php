<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Koppeltabel: welke trainer heeft welke promotie actief/gebruikt.
 * Gebruikt trainer_user_id (bigint unsigned) → gymies_users.id,
 * aansluitend op gymies_subscriptions.trainer_user_id.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('gymies_trainer_promotions', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('trainer_user_id');         // → gymies_users.id
            $table->unsignedBigInteger('promotion_id');            // → gymies_promotions.id
            $table->unsignedInteger('plan_id')->nullable();        // → gymies_plans.id

            // ── Status ──
            $table->enum('status', [
                'active',       // Promotie loopt momenteel
                'expired',      // Verlopen (maanden op, trial voorbij)
                'cancelled',    // Trainer geannuleerd tijdens promo
                'converted',    // Trial → betaald
            ])->default('active');

            // ── Timing ──
            $table->timestamp('activated_at')->useCurrent();
            $table->timestamp('expires_at')->nullable();
            $table->timestamp('converted_at')->nullable();

            // ── Welk plan ──
            $table->string('applied_slug', 32)->nullable();        // plan slug (pro, pro_plus)
            $table->unsignedInteger('original_price_cents')->nullable();
            $table->unsignedInteger('discounted_price_cents')->nullable();

            // ── Tracking ──
            $table->unsignedInteger('months_remaining')->nullable();
            $table->unsignedInteger('months_used')->default(0);
            $table->string('code_used', 64)->nullable();

            // ── Mollie ──
            $table->string('mollie_subscription_id', 64)->nullable();
            $table->string('mollie_mandate_id', 64)->nullable();

            $table->timestamps();

            // Foreign keys
            $table->foreign('trainer_user_id')
                  ->references('id')->on('gymies_users')
                  ->cascadeOnDelete();
            $table->foreign('promotion_id')
                  ->references('id')->on('gymies_promotions')
                  ->cascadeOnDelete();
            $table->foreign('plan_id')
                  ->references('id')->on('gymies_plans')
                  ->nullOnDelete();

            // Indexen
            $table->index(['trainer_user_id', 'status']);
            $table->index(['promotion_id', 'status']);
            $table->unique(['trainer_user_id', 'promotion_id'], 'trainer_promo_unique');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_trainer_promotions');
    }
};
