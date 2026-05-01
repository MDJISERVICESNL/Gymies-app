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

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            if (!Schema::hasColumn('gymies_trainer_profiles', 'booking_advance_days')) {
                $table->unsignedInteger('booking_advance_days')->nullable()->default(28);
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'payment_method')) {
                $table->string('payment_method', 32)->nullable()->default('transfer_and_cash');
            }
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            if (Schema::hasColumn('gymies_trainer_profiles', 'booking_advance_days')) {
                $table->dropColumn('booking_advance_days');
            }
            if (Schema::hasColumn('gymies_trainer_profiles', 'payment_method')) {
                $table->dropColumn('payment_method');
            }
        });
    }
};
