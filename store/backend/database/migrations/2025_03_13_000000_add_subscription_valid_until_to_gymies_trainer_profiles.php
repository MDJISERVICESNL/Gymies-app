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
        if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_valid_until')) {
            return;
        }
        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            $table->date('subscription_valid_until')->nullable();
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }
        if (!Schema::hasColumn('gymies_trainer_profiles', 'subscription_valid_until')) {
            return;
        }
        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            $table->dropColumn('subscription_valid_until');
        });
    }
};
