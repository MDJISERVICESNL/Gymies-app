<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\PromotionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PromotionController extends Controller
{
    public function __construct(
        private PromotionService $promotionService
    ) {}

    /**
     * POST /api/promo/validate
     *
     * Valideer een promo-code voor een trainer + tier.
     * Body: { "code": "GYMIES50", "tier": "pro" }
     *
     * Response (geldig):
     * {
     *   "valid": true,
     *   "promotion": {
     *     "promotion_id": 1,
     *     "promotion_slug": "zomeractie-2026",
     *     "type": "coupon",
     *     "display_label": "50% korting eerste 3 maanden",
     *     "discount_type": "percentage",
     *     "discount_value": 50,
     *     "discount_months": 3,
     *     "original_price": "€64,99",
     *     "price": "€32,50",
     *     "ends_at": null
     *   }
     * }
     *
     * Response (ongeldig):
     * { "valid": false, "error": "Deze code is niet geldig." }
     */
    public function validate(Request $request): JsonResponse
    {
        $request->validate([
            'code' => 'required|string|max:50',
            'tier' => 'required|string|in:starter,pro,pro_plus',
        ]);

        $trainer = $request->user();
        $result = $this->promotionService->validateCode(
            $request->input('code'),
            $trainer->id,
            $request->input('tier'),
        );

        if ($result === null) {
            return response()->json([
                'valid' => false,
                'error' => 'Deze code is niet geldig of verlopen.',
            ], 200); // 200 (niet 404) zodat de app het netjes afhandelt
        }

        if (isset($result['error'])) {
            return response()->json([
                'valid' => false,
                'error' => $result['error'],
            ], 200);
        }

        return response()->json($result);
    }

    /**
     * GET /api/promo/active
     *
     * Haal de actieve promotie op voor de ingelogde trainer.
     *
     * Response (actief):
     * {
     *   "has_active_promotion": true,
     *   "promotion": {
     *     "id": 42,
     *     "promotion_slug": "zomeractie-2026",
     *     "type": "discount_months",
     *     "status": "active",
     *     "display_label": "50% korting eerste 3 maanden",
     *     "applied_tier": "pro",
     *     "original_price": "€64,99",
     *     "discounted_price": "€32,50",
     *     "expires_at": "2026-07-20T00:00:00+00:00",
     *     "days_remaining": 91,
     *     "months_remaining": 2,
     *     "months_used": 1,
     *     "is_trial": false,
     *     "is_active": true
     *   }
     * }
     *
     * Response (geen actieve promo):
     * { "has_active_promotion": false, "promotion": null }
     */
    public function active(Request $request): JsonResponse
    {
        $trainer = $request->user();
        $promo = $this->promotionService->getActivePromotion($trainer->id);

        return response()->json([
            'has_active_promotion' => $promo !== null && $promo->isActive(),
            'promotion'            => $promo?->toAppArray(),
        ]);
    }

    /**
     * POST /api/promo/activate
     *
     * Activeer een promotie (na succesvolle Mollie checkout of trial start).
     * Body: { "promotion_id": 1, "tier": "pro", "code": "GYMIES50" }
     */
    public function activate(Request $request): JsonResponse
    {
        $request->validate([
            'promotion_id' => 'required|integer|exists:promotions,id',
            'tier'         => 'required|string|in:starter,pro,pro_plus',
            'code'         => 'nullable|string|max:50',
        ]);

        $trainer = $request->user();

        try {
            $trainerPromo = $this->promotionService->activate(
                $trainer->id,
                $request->input('promotion_id'),
                $request->input('tier'),
                $request->input('code'),
            );

            return response()->json([
                'success'   => true,
                'promotion' => $trainerPromo->toAppArray(),
            ]);
        } catch (\RuntimeException $e) {
            return response()->json([
                'success' => false,
                'error'   => $e->getMessage(),
            ], 422);
        }
    }
}
