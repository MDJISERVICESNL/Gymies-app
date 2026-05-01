<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        if (Schema::hasColumn('gymies_trainer_profiles', 'boosted_until')) {
            return;
        }

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            $table->dateTime('boosted_until')->nullable()->after('profile_slug');
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        if (!Schema::hasColumn('gymies_trainer_profiles', 'boosted_until')) {
            return;
        }

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            $table->dropColumn('boosted_until');
        });
    }
};
