<?php

namespace App\Console\Commands;

use App\Services\PromotionService;
use Illuminate\Console\Command;

/**
 * Dagelijks draaien: php artisan promotions:expire
 *
 * Voeg toe aan app/Console/Kernel.php:
 *   $schedule->command('promotions:expire')->dailyAt('02:00');
 */
class ExpirePromotionsCommand extends Command
{
    protected $signature = 'promotions:expire';
    protected $description = 'Markeer verlopen promoties als expired';

    public function handle(PromotionService $service): int
    {
        $count = $service->expireOldPromotions();
        $this->info("$count promotie(s) gemarkeerd als verlopen.");
        return Command::SUCCESS;
    }
}
