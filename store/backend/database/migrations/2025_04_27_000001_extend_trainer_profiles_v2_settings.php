<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * V2 Booking Architecture — Trainer profile instellingen uitbreiden.
 *
 * Nieuwe kolommen:
 * - timezone                → voor UTC-opslag + lokale weergave (DST-proof)
 * - session_duration_min    → standaard sessieduur in minuten
 * - buffer_minutes          → pauze/uitloop buffer tussen slots
 * - max_sessions_per_day    → burnout preventie per dag
 * - max_sessions_per_week   → burnout preventie per week
 * - min_break_minutes       → minimale pauze tussen sessies (alias voor buffer)
 */
return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            if (!Schema::hasColumn('gymies_trainer_profiles', 'timezone')) {
                $table->string('timezone', 50)->default('Europe/Amsterdam')->after('payment_method');
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'session_duration_min')) {
                $table->unsignedSmallInteger('session_duration_min')->default(60)->after('timezone');
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'buffer_minutes')) {
                $table->unsignedSmallInteger('buffer_minutes')->default(15)->after('session_duration_min');
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'max_sessions_per_day')) {
                $table->unsignedSmallInteger('max_sessions_per_day')->nullable()->after('buffer_minutes');
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'max_sessions_per_week')) {
                $table->unsignedSmallInteger('max_sessions_per_week')->nullable()->after('max_sessions_per_day');
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'min_break_minutes')) {
                $table->unsignedSmallInteger('min_break_minutes')->default(15)->after('max_sessions_per_week');
            }
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        $columns = ['timezone', 'session_duration_min', 'buffer_minutes', 'max_sessions_per_day', 'max_sessions_per_week', 'min_break_minutes'];

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) use ($columns) {
            foreach ($columns as $col) {
                if (Schema::hasColumn('gymies_trainer_profiles', $col)) {
                    $table->dropColumn($col);
                }
            }
        });
    }
};
