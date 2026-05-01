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
            if (!Schema::hasColumn('gymies_trainer_profiles', 'subscription_pending_downgrade')) {
                $table->boolean('subscription_pending_downgrade')->default(false);
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'subscription_downgrades_at')) {
                $table->date('subscription_downgrades_at')->nullable();
            }
            if (!Schema::hasColumn('gymies_trainer_profiles', 'subscription_downgrade_to')) {
                $table->string('subscription_downgrade_to', 16)->nullable();
            }
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }
        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            $columns = ['subscription_pending_downgrade', 'subscription_downgrades_at', 'subscription_downgrade_to'];
            foreach ($columns as $col) {
                if (Schema::hasColumn('gymies_trainer_profiles', $col)) {
                    $table->dropColumn($col);
                }
            }
        });
    }
};
