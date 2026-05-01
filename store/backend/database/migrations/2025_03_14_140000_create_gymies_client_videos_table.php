<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('gymies_client_videos')) {
            Schema::create('gymies_client_videos', function (Blueprint $table) {
                $table->id();
                $table->unsignedBigInteger('trainer_user_id');
                $table->unsignedBigInteger('client_user_id');
                $table->string('url', 1024);
                $table->string('title', 255)->nullable();
                $table->string('storage_path', 512)->nullable();
                $table->timestamps();
                $table->index(['trainer_user_id', 'client_user_id']);
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_client_videos');
    }
};
