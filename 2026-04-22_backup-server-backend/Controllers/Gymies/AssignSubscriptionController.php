<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;

/**
 * Admin: abonnement toewijzen met optionele proefperiode.
 * POST vault-console/users/{userId}/assign-subscription
 */
class AssignSubscriptionController
{
    use AssignSubscriptionTrait;

    public function assign(Request $request, string $userId): JsonResponse
    {
        return $this->performAssignSubscription($request, $userId);
    }
}
