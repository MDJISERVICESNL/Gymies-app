<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('gymies_subscription_features', function (Blueprint $table) {
            $table->id();
            $table->string('key', 64)->unique();
            $table->string('label');
            $table->string('enabled_from', 16)->default('starter');
            $table->string('type', 16)->default('boolean');
            $table->integer('limit_starter')->nullable();
            $table->integer('limit_pro')->nullable();
            $table->integer('limit_elite')->nullable();
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();
        });

        $this->seedDefaults();
    }

    public function down(): void
    {
        Schema::dropIfExists('gymies_subscription_features');
    }

    private function seedDefaults(): void
    {
        $rows = [
            ['key' => 'sessions', 'label' => 'Sessiebeheer', 'enabled_from' => 'starter', 'type' => 'boolean', 'sort_order' => 1],
            ['key' => 'messages', 'label' => 'Berichten (1-op-1 chat)', 'enabled_from' => 'starter', 'type' => 'boolean', 'sort_order' => 2],
            ['key' => 'agenda', 'label' => 'Agenda', 'enabled_from' => 'starter', 'type' => 'boolean', 'sort_order' => 3],
            ['key' => 'invoice', 'label' => 'Factuur opstellen', 'enabled_from' => 'starter', 'type' => 'boolean', 'sort_order' => 4],
            ['key' => 'documents', 'label' => 'Documenten', 'enabled_from' => 'starter', 'type' => 'boolean', 'sort_order' => 5],
            ['key' => 'income', 'label' => 'Inkomstenoverzicht', 'enabled_from' => 'starter', 'type' => 'boolean', 'sort_order' => 6],
            ['key' => 'checkin', 'label' => 'Check-in scanner', 'enabled_from' => 'starter', 'type' => 'boolean', 'sort_order' => 7],
            ['key' => 'waitlist', 'label' => 'Wachtlijst / standby', 'enabled_from' => 'starter', 'type' => 'boolean', 'sort_order' => 8],
            ['key' => 'dossier', 'label' => 'Dossier opstellen per klant', 'enabled_from' => 'pro', 'type' => 'boolean', 'sort_order' => 9],
            ['key' => 'goals', 'label' => 'Doelen instellen per klant', 'enabled_from' => 'pro', 'type' => 'boolean', 'sort_order' => 10],
            ['key' => 'health_score', 'label' => 'Client health score', 'enabled_from' => 'pro', 'type' => 'boolean', 'sort_order' => 11],
            ['key' => 'upsell', 'label' => 'Upsell suggesties', 'enabled_from' => 'pro', 'type' => 'boolean', 'sort_order' => 12],
            ['key' => 'rebook', 'label' => 'Herboek suggesties', 'enabled_from' => 'pro', 'type' => 'boolean', 'sort_order' => 13],
            ['key' => 'priority_support', 'label' => 'Priority support lane', 'enabled_from' => 'pro', 'type' => 'boolean', 'sort_order' => 14],
            ['key' => 'bulk_message', 'label' => 'Bulk bericht naar klanten', 'enabled_from' => 'pro', 'type' => 'boolean', 'sort_order' => 15],
            ['key' => 'client_tags', 'label' => 'Klanttags/labels', 'enabled_from' => 'pro', 'type' => 'boolean', 'sort_order' => 16],
            ['key' => 'advanced_reporting', 'label' => 'Geavanceerde rapportage', 'enabled_from' => 'elite', 'type' => 'boolean', 'sort_order' => 17],
            ['key' => 'suite_tools', 'label' => 'Organisatie Elite mode', 'enabled_from' => 'elite', 'type' => 'boolean', 'sort_order' => 18],
            ['key' => 'promoted_profile', 'label' => 'Promoted profiel', 'enabled_from' => 'elite', 'type' => 'boolean', 'sort_order' => 19],
            ['key' => 'profile_videos', 'label' => 'Videos op profiel', 'enabled_from' => 'pro', 'type' => 'limit', 'limit_pro' => 1, 'limit_elite' => -1, 'sort_order' => 20],
            ['key' => 'profile_stories', 'label' => 'Story-achtig op profiel', 'enabled_from' => 'pro', 'type' => 'limit', 'limit_pro' => 1, 'limit_elite' => -1, 'sort_order' => 21],
            ['key' => 'max_clients', 'label' => 'Aantal actieve klanten', 'enabled_from' => 'starter', 'type' => 'limit', 'limit_starter' => -1, 'limit_pro' => -1, 'limit_elite' => -1, 'sort_order' => 22],
        ];

        foreach ($rows as $r) {
            \Illuminate\Support\Facades\DB::table('gymies_subscription_features')->insert(array_merge($r, [
                'created_at' => now(),
                'updated_at' => now(),
            ]));
        }
    }
};
