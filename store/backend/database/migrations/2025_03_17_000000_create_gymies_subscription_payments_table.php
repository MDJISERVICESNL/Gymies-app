<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        $tableName = 'gymies_subscription_payments';
        if (Schema::hasTable($tableName)) {
            return;
        }
        Schema::create($tableName, function (Blueprint $table) {
            $table->id();
            $table->string('mollie_payment_id', 64)->unique();
            $table->unsignedBigInteger('user_id');
            $table->string('tier', 16);
            $table->unsignedInteger('amount_cents');
            $table->string('status', 32)->default('open');
            $table->timestamps();
            $table->index(['user_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_subscription_payments');
    }
};
