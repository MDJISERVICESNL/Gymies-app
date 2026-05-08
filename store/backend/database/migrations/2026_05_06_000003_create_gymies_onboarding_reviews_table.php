<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Onboarding Reviews — staff beoordelingen van trainer aanvragen.
 *
 * Elke keer dat een staff member een trainer goedkeurt of afwijst
 * wordt hier een record aangemaakt. Een trainer kan meerdere reviews
 * hebben (bijv. afgewezen → gecorrigeerd → goedgekeurd).
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_onboarding_reviews')) {
            return;
        }

        Schema::create('gymies_onboarding_reviews', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('trainer_id');
            $table->unsignedBigInteger('reviewer_id');
            $table->string('action', 20)->comment('approved, rejected, suspended, reactivated');
            $table->text('reason')->nullable();
            $table->json('checklist')->nullable()
                ->comment('{"kvk_valid":true,"vog_uploaded":true,"iban_verified":true,...}');
            $table->timestamps();

            $table->foreign('trainer_id')->references('id')->on('gymies_trainer_profiles')->cascadeOnDelete();
            $table->foreign('reviewer_id')->references('id')->on('gymies_users')->cascadeOnDelete();

            $table->index('trainer_id', 'idx_review_trainer');
            $table->index(['trainer_id', 'action'], 'idx_review_trainer_action');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_onboarding_reviews');
    }
};
