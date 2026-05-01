<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        $tableName = 'gymies_booking_mollie_payments';
        if (Schema::hasTable($tableName)) {
            return;
        }
        Schema::create($tableName, function (Blueprint $table) {
            $table->id();
            $table->string('booking_id', 64)->index();
            $table->string('mollie_payment_id', 64)->unique();
            $table->unsignedBigInteger('trainer_user_id')->nullable()->index();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_booking_mollie_payments');
    }
};
