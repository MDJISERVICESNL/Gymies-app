<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Sessietabel voor Gymies API-login.
 * Token: 64 hex karakters (bin2hex(random_bytes(32))).
 * GymiesAuthMiddleware zoekt sessies hierop.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_sessions')) {
            return;
        }
        Schema::create('gymies_sessions', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('user_id');
            $table->string('token', 64)->unique();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->timestamp('last_activity')->nullable();
            $table->timestamps();
            $table->index('user_id');
            $table->index('token');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_sessions');
    }
};
