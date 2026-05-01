<?php

/**
 * Voeg deze routes toe aan je routes/api.php
 * binnen de auth:sanctum middleware group.
 */

use App\Http\Controllers\Api\PromotionController;

// ── Promotie routes (trainer authenticated) ──
Route::prefix('promo')->middleware('auth:sanctum')->group(function () {
    Route::post('/validate', [PromotionController::class, 'validate']);  // Valideer een code
    Route::get('/active', [PromotionController::class, 'active']);       // Haal actieve promo op
    Route::post('/activate', [PromotionController::class, 'activate']); // Activeer een promo
});

/**
 * BESTAANDE ROUTES AANPASSEN:
 *
 * In je PlansController (GET /api/plans):
 *   Voeg na het ophalen van de plannen toe:
 *
 *   $promotionService = app(PromotionService::class);
 *   $plans = $promotionService->enrichPlansWithPromotions($plans, auth()->id());
 *
 * In je SubscriptionController (POST /api/subscription/start-payment):
 *   Accepteer optioneel promotion_id en code in de request body.
 *   Na succesvolle Mollie checkout:
 *
 *   if ($request->input('promotion_id')) {
 *       $promotionService->activate(
 *           $trainer->id,
 *           $request->input('promotion_id'),
 *           $request->input('tier'),
 *           $request->input('code'),
 *       );
 *   }
 *
 * In je MollieWebhookController:
 *   Bij elke succesvolle recurring betaling:
 *
 *   $promotionService->handleMolliePayment($trainerId);
 *
 *   Bij eerste betaling na trial:
 *
 *   $promotionService->handleTrialConversion($trainerId);
 */
