<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;

/**
 * Trainer self-service: abonnement wijzigen.
 * POST subscription/change { "tier": "starter"|"pro"|"elite" }
 */
class ChangeSubscriptionController
{
    use ChangeSubscriptionTrait;

    public function __invoke(Request $request): JsonResponse
    {
        return $this->changeSubscription($request);
    }
}
