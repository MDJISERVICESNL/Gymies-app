<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('gymies_sessions')) {
            return;
        }
        if (Schema::hasColumn('gymies_sessions', 'last_activity')) {
            return;
        }
        Schema::table('gymies_sessions', function (Blueprint $table) {
            $table->timestamp('last_activity')->nullable()->after('token');
        });
    }

    public function down(): void
    {
        if (Schema::hasTable('gymies_sessions') && Schema::hasColumn('gymies_sessions', 'last_activity')) {
            Schema::table('gymies_sessions', function (Blueprint $table) {
                $table->dropColumn('last_activity');
            });
        }
    }
};
