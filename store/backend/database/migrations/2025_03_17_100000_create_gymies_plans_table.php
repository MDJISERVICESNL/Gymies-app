<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        $tableName = 'gymies_plans';
        if (Schema::hasTable($tableName)) {
            return;
        }
        Schema::create($tableName, function (Blueprint $table) {
            $table->id();
            $table->string('slug', 32)->unique();
            $table->string('name', 64);
            $table->unsignedInteger('amount_cents')->default(0);
            $table->string('price_label', 32)->nullable();
            $table->unsignedTinyInteger('sort_order')->default(0);
            $table->timestamps();
        });

        $now = now();
        DB::table($tableName)->insert([
            ['slug' => 'starter', 'name' => 'Starter', 'amount_cents' => 2995, 'price_label' => '€29,95/mnd', 'sort_order' => 1, 'created_at' => $now, 'updated_at' => $now],
            ['slug' => 'pro', 'name' => 'Pro', 'amount_cents' => 5995, 'price_label' => '€59,95/mnd', 'sort_order' => 2, 'created_at' => $now, 'updated_at' => $now],
            ['slug' => 'elite', 'name' => 'Elite', 'amount_cents' => 9995, 'price_label' => '€99,95/mnd', 'sort_order' => 3, 'created_at' => $now, 'updated_at' => $now],
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_plans');
    }
};
