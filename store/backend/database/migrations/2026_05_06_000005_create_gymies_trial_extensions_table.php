<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Trial Extensions — smart trial verlengingen door staff.
 *
 * Staff kan de trial van een trainer verlengen met 7, 14 of 30 dagen.
 * Elke verlenging wordt gelogd met reden en activiteitsscore.
 * Dit is apart van de audit log voor snelle queries en rapportage.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_trial_extensions')) {
            return;
        }

        Schema::create('gymies_trial_extensions', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('trainer_id');
            $table->unsignedBigInteger('extended_by_id');
            $table->unsignedSmallInteger('days')->comment('7, 14, of 30');
            $table->text('reason')->nullable();
            $table->json('activity_snapshot')->nullable()
                ->comment('{"etalage_score":80,"bookings":5,"messages":12,"app_opens":45}');
            $table->timestamp('previous_trial_end')->nullable();
            $table->timestamp('new_trial_end')->nullable();
            $table->timestamps();

            $table->foreign('trainer_id')->references('id')->on('gymies_trainer_profiles')->cascadeOnDelete();
            $table->foreign('extended_by_id')->references('id')->on('gymies_users')->cascadeOnDelete();

            $table->index('trainer_id', 'idx_extension_trainer');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_trial_extensions');
    }
};
