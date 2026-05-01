<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        $tableName = 'gymies_booking_reviews';
        if (Schema::hasTable($tableName)) {
            if (!Schema::hasColumn($tableName, 'is_anonymous')) {
                Schema::table($tableName, function (Blueprint $table) {
                    $table->boolean('is_anonymous')->default(false)->after('message');
                });
            }
            return;
        }
        Schema::create($tableName, function (Blueprint $table) {
            $table->id();
            $table->string('booking_id', 64)->index();
            $table->unsignedBigInteger('client_user_id')->index();
            $table->unsignedBigInteger('trainer_user_id')->index();
            $table->unsignedTinyInteger('rating'); // 1-5
            $table->text('message')->nullable();
            $table->boolean('is_anonymous')->default(false);
            $table->timestamps();
            $table->unique(['booking_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_booking_reviews');
    }
};
