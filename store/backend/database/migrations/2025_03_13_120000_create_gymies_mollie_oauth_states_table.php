<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_mollie_oauth_states')) {
            return;
        }
        Schema::create('gymies_mollie_oauth_states', function (Blueprint $table) {
            $table->id();
            $table->string('state', 64)->unique();
            $table->unsignedBigInteger('user_id');
            $table->timestamp('expires_at')->index();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_mollie_oauth_states');
    }
};
