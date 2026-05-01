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

        if (Schema::hasColumn('gymies_trainer_profiles', 'profile_slug')) {
            return;
        }

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            $table->string('profile_slug', 64)->nullable()->unique()->after('user_id');
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        if (!Schema::hasColumn('gymies_trainer_profiles', 'profile_slug')) {
            return;
        }

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            $table->dropColumn('profile_slug');
        });
    }
};
