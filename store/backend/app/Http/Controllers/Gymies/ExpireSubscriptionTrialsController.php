<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;

/**
 * Cron-endpoint: verlopen proefabonnementen terugzetten naar Starter.
 * POST api/gymies/cron/expire-subscription-trials
 */
class ExpireSubscriptionTrialsController
{
    use ExpireSubscriptionTrialsTrait;

    public function __invoke(): JsonResponse
    {
        return $this->expireSubscriptionTrials();
    }
}
