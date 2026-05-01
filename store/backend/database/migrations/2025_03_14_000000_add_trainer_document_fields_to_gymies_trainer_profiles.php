<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) {
            $columns = [
                'company_name',
                'kvk_number',
                'vat_number',
                'trainer_address_line1',
                'trainer_postcode',
                'trainer_city',
                'trainer_country',
                'vog_url',
                'diploma_urls',
            ];

            foreach ($columns as $col) {
                if (!Schema::hasColumn('gymies_trainer_profiles', $col)) {
                    if ($col === 'diploma_urls') {
                        $table->json('diploma_urls')->nullable();
                    } else {
                        $table->string($col)->nullable();
                    }
                }
            }
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        $columns = [
            'company_name',
            'kvk_number',
            'vat_number',
            'trainer_address_line1',
            'trainer_postcode',
            'trainer_city',
            'trainer_country',
            'vog_url',
            'diploma_urls',
        ];

        Schema::table('gymies_trainer_profiles', function (Blueprint $table) use ($columns) {
            foreach ($columns as $col) {
                if (Schema::hasColumn('gymies_trainer_profiles', $col)) {
                    $table->dropColumn($col);
                }
            }
        });
    }
};
