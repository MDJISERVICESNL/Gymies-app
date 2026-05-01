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
        if (Schema::hasColumn('gymies_trainer_profiles', 'mollie_access_token')) {
            return;
        }
        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            $table->text('mollie_access_token')->nullable();
            $table->text('mollie_refresh_token')->nullable();
            $table->timestamp('mollie_token_expires_at')->nullable();
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }
        if (!Schema::hasColumn('gymies_trainer_profiles', 'mollie_access_token')) {
            return;
        }
        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            $table->dropColumn(['mollie_access_token', 'mollie_refresh_token', 'mollie_token_expires_at']);
        });
    }
};
