<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Fallback token-tabel voor Gymies auth wanneer Sanctum's personal_access_tokens
 * niet bestaat. Gebruikt door GymiesAuthController en EnsureGymiesUserFromToken.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_personal_access_tokens')) {
            return;
        }

        Schema::create('gymies_personal_access_tokens', function (Blueprint $table) {
            $table->id();
            $table->string('tokenable_type');
            $table->unsignedBigInteger('tokenable_id');
            $table->string('name', 100);
            $table->string('token', 64)->unique();
            $table->text('abilities')->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();

            $table->index(['tokenable_type', 'tokenable_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_personal_access_tokens');
    }
};
