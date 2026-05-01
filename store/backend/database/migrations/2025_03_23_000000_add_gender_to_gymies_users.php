<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('gymies_users')) {
            return;
        }

        if (Schema::hasColumn('gymies_users', 'gender')) {
            return;
        }

        Schema::table('gymies_users', function (Blueprint $table) {
            $table->string('gender', 16)->nullable();
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_users')) {
            return;
        }

        if (!Schema::hasColumn('gymies_users', 'gender')) {
            return;
        }

        Schema::table('gymies_users', function (Blueprint $table) {
            $table->dropColumn('gender');
        });
    }
};
