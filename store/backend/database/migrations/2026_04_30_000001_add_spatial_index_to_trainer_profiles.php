<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Voeg een reguliere index toe op trainer_lat/trainer_lng voor
 * snellere ST_Distance_Sphere queries bij het zoeken van trainers.
 *
 * MySQL 5.7+ ondersteunt ST_Distance_Sphere op gewone DOUBLE kolommen.
 * Een samengestelde index op (trainer_lat, trainer_lng) helpt de query planner
 * om rijen met NULL-waarden snel over te slaan.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        $hasLat = Schema::hasColumn('gymies_trainer_profiles', 'trainer_lat');
        $hasLng = Schema::hasColumn('gymies_trainer_profiles', 'trainer_lng');

        if (!$hasLat || !$hasLng) {
            return;
        }

        // Voeg samengestelde index toe voor geo-queries
        try {
            DB::statement('ALTER TABLE gymies_trainer_profiles ADD INDEX idx_trainer_geo (trainer_lat, trainer_lng)');
        } catch (\Illuminate\Database\QueryException $e) {
            // Index bestaat al — geen probleem
            if (!str_contains($e->getMessage(), 'Duplicate key name')) {
                throw $e;
            }
        }
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        try {
            DB::statement('ALTER TABLE gymies_trainer_profiles DROP INDEX idx_trainer_geo');
        } catch (\Illuminate\Database\QueryException $e) {
            // Index bestaat niet — geen probleem
        }
    }
};
