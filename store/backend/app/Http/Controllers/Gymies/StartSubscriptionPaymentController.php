<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\Request;

/**
 * POST subscription/start-payment { "tier": "starter"|"pro"|"elite" }
 * Start Mollie checkout voor abonnement. Retourneert payment_url.
 */
class StartSubscriptionPaymentController
{
    use SubscriptionPaymentTrait;

    public function __invoke(Request $request)
    {
        return $this->startSubscriptionPayment($request);
    }
}
