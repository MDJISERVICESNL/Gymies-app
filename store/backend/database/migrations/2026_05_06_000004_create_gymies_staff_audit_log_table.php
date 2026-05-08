<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Staff Audit Log — volledig audit trail voor alle staff acties.
 *
 * Polymorphe target: target_type + target_id verwijzen naar elk model.
 * Metadata bevat voor/na waarden en extra context.
 * Belangrijk voor compliance en fraude-detectie.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('gymies_staff_audit_log')) {
            return;
        }

        Schema::create('gymies_staff_audit_log', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('staff_id');
            $table->string('action', 100)->comment('bijv. trainer.approved, trial.extended, code.created');
            $table->string('target_type', 100)->comment('Model class: App\\Models\\TrainerProfile, etc.');
            $table->unsignedBigInteger('target_id');
            $table->json('metadata')->nullable()
                ->comment('{"before":{},"after":{},"reason":"...","ip":"..."}');
            $table->string('ip_address', 45)->nullable();
            $table->timestamps();

            $table->foreign('staff_id')->references('id')->on('gymies_users')->cascadeOnDelete();

            $table->index('staff_id', 'idx_audit_staff');
            $table->index(['target_type', 'target_id'], 'idx_audit_target');
            $table->index('action', 'idx_audit_action');
            $table->index('created_at', 'idx_audit_created');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_staff_audit_log');
    }
};
