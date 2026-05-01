<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_feature_flags')) return;

        Schema::create('gymies_feature_flags', function (Blueprint $table) {
            $table->id();
            $table->string('key', 100)->unique();           // bijv. 'buddy_bookings', 'group_sessions'
            $table->string('name', 200);                     // Beschrijvende naam
            $table->text('description')->nullable();
            $table->boolean('enabled')->default(false);      // Globaal aan/uit
            $table->json('allowed_roles')->nullable();       // ['trainer', 'client'] of null = alle roles
            $table->json('allowed_user_ids')->nullable();    // [1, 5, 23] voor beta testers
            $table->float('rollout_percentage', 5, 2)->default(100.00); // 0-100%, gradual rollout
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_feature_flags');
    }
};
