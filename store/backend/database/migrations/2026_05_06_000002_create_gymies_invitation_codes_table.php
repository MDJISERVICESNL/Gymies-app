<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Invitation Codes — soft launch uitnodigingssysteem.
 *
 * Trainers kunnen alleen registreren met een geldige code.
 * Codes worden aangemaakt door staff of gegenereerd als referral.
 * Feature flag 'require_invitation_code' bepaalt of dit actief is.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_invitation_codes')) {
            return;
        }

        Schema::create('gymies_invitation_codes', function (Blueprint $table) {
            $table->id();
            $table->string('code', 30)->unique();
            $table->string('source', 30)->default('staff')
                ->comment('staff, referral, promo, partner');
            $table->unsignedInteger('max_uses')->default(1);
            $table->unsignedInteger('used_count')->default(0);
            $table->unsignedBigInteger('created_by')->nullable();
            $table->unsignedBigInteger('referred_by_trainer_id')->nullable()
                ->comment('Trainer die de referral code heeft gegenereerd');
            $table->timestamp('expires_at')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->foreign('created_by')->references('id')->on('gymies_users')->nullOnDelete();
            $table->foreign('referred_by_trainer_id')->references('id')->on('gymies_trainer_profiles')->nullOnDelete();

            $table->index('is_active', 'idx_invitation_active');
            $table->index('source', 'idx_invitation_source');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_invitation_codes');
    }
};
