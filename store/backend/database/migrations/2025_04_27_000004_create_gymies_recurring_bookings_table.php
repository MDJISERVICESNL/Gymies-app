<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * V2 Booking Architecture — Recurring bookings.
 *
 * Klant boekt "elke dinsdag 09:00". Scheduled job genereert
 * concrete bookings 2 weken vooruit. Bij conflict (trainer exception)
 * → klant krijgt notificatie om te verplaatsen.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_recurring_bookings')) {
            return;
        }

        Schema::create('gymies_recurring_bookings', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('client_user_id')->index();
            $table->unsignedBigInteger('trainer_user_id')->index();
            // ISO weekdag: 1=maandag .. 7=zondag
            $table->unsignedTinyInteger('day_of_week');
            // Starttijd: '09:00'
            $table->string('start_time', 5);
            // Duur in minuten
            $table->unsignedSmallInteger('duration_minutes')->default(60);
            // Herhaal tot datum (null = onbeperkt)
            $table->date('repeat_until')->nullable();
            // Elke X weken (1 = wekelijks, 2 = om de week)
            $table->unsignedSmallInteger('repeat_every_weeks')->default(1);
            // Optioneel gekoppeld pakket
            $table->unsignedBigInteger('package_id')->nullable();
            // Status: active, paused, cancelled
            $table->string('status', 20)->default('active')->index();
            // Tot welke datum er al concrete bookings zijn gegenereerd
            $table->date('generated_until')->nullable();
            // Prijs per sessie in centen (0 als via pakket)
            $table->unsignedInteger('amount_cents')->default(0);
            $table->timestamps();

            $table->foreign('client_user_id')
                  ->references('id')
                  ->on('gymies_users')
                  ->onDelete('cascade');

            $table->foreign('trainer_user_id')
                  ->references('id')
                  ->on('gymies_users')
                  ->onDelete('cascade');

            // Unieke constraint: 1 klant, 1 trainer, 1 dag+tijd tegelijk
            $table->unique(['client_user_id', 'trainer_user_id', 'day_of_week', 'start_time'], 'recurring_unique_slot');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_recurring_bookings');
    }
};
