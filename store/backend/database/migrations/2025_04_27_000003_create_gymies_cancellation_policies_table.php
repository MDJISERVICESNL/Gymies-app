<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * V2 Booking Architecture — Per-trainer annuleringsbeleid.
 *
 * Overschrijft het platform-standaard beleid (48u/24u) met trainer-specifieke regels.
 * Als geen policy record bestaat → platform defaults gelden.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_cancellation_policies')) {
            return;
        }

        Schema::create('gymies_cancellation_policies', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('trainer_user_id')->unique();
            // Gratis annuleren tot X uur voor de sessie
            $table->unsignedSmallInteger('free_cancel_hours')->default(24);
            // Late cancel fee als percentage (0-100) van sessiebedrag
            $table->unsignedSmallInteger('late_cancel_fee_pct')->default(50);
            // No-show fee als percentage (0-100) van sessiebedrag
            $table->unsignedSmallInteger('no_show_fee_pct')->default(100);
            // Of verplaatsen is toegestaan i.p.v. annuleren
            $table->boolean('allow_reschedule')->default(true);
            // Verplaatsen mag tot X uur voor de sessie
            $table->unsignedSmallInteger('reschedule_limit_hours')->default(4);
            // Maximum gratis annuleringen per maand (null = onbeperkt)
            $table->unsignedSmallInteger('max_free_cancels_per_month')->nullable();
            // Custom bericht voor klanten
            $table->string('custom_message', 500)->nullable();
            $table->timestamps();

            $table->foreign('trainer_user_id')
                  ->references('id')
                  ->on('gymies_users')
                  ->onDelete('cascade');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_cancellation_policies');
    }
};
