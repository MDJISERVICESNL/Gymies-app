<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * V2 Booking Architecture — Idempotency keys.
 *
 * Voorkomt dubbele boekingen bij netwerk-retries of dubbele klikken.
 * Client stuurt X-Idempotency-Key header (UUID). Server cacht response.
 * Bij retry: return cached response zonder opnieuw te boeken.
 * TTL: 24 uur, daarna opgeruimd via scheduled artisan command.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_idempotency_keys')) {
            return;
        }

        Schema::create('gymies_idempotency_keys', function (Blueprint $table) {
            $table->id();
            $table->string('idempotency_key', 64)->unique();
            $table->unsignedBigInteger('user_id')->index();
            $table->string('endpoint', 120);
            $table->string('method', 10)->default('POST');
            $table->unsignedSmallInteger('response_code');
            $table->json('response_body');
            $table->timestamp('created_at')->useCurrent();
            $table->timestamp('expires_at')->nullable()->index();

            $table->foreign('user_id')
                  ->references('id')
                  ->on('gymies_users')
                  ->onDelete('cascade');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_idempotency_keys');
    }
};
