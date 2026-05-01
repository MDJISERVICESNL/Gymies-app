<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * V2 Booking Architecture — Wachtlijst.
 *
 * Slot vol → klant op wachtlijst. Bij annulering → eerste op lijst
 * krijgt push + 15 min claim window. Daarna → volgende in rij.
 * Als claim verloopt → slot terug naar publiek beschikbaar.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_waitlist')) {
            return;
        }

        Schema::create('gymies_waitlist', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('client_user_id')->index();
            $table->unsignedBigInteger('trainer_user_id')->index();
            // Gewenst moment
            $table->date('desired_date');
            $table->string('desired_time', 5);  // '09:00'
            $table->unsignedSmallInteger('desired_duration_minutes')->default(60);
            // Positie in de wachtrij (1 = eerste)
            $table->unsignedSmallInteger('position')->default(1);
            // Status: waiting, offered, claimed, expired, cancelled
            $table->string('status', 20)->default('waiting')->index();
            // Wanneer het aanbod is gedaan (status → offered)
            $table->timestamp('offered_at')->nullable();
            // Claim deadline (15 min na offered_at)
            $table->timestamp('expires_at')->nullable()->index();
            // De booking die het slot vrijmaakte (voor audit trail)
            $table->unsignedBigInteger('released_booking_id')->nullable();
            // De booking die is aangemaakt na claim
            $table->unsignedBigInteger('claimed_booking_id')->nullable();
            $table->timestamps();

            $table->foreign('client_user_id')
                  ->references('id')
                  ->on('gymies_users')
                  ->onDelete('cascade');

            $table->foreign('trainer_user_id')
                  ->references('id')
                  ->on('gymies_users')
                  ->onDelete('cascade');

            // Voorkom dubbele wachtlijst-entries voor hetzelfde slot
            $table->unique(
                ['client_user_id', 'trainer_user_id', 'desired_date', 'desired_time'],
                'waitlist_unique_slot'
            );
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_waitlist');
    }
};
