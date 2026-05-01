<?php

namespace App\Services;

use App\Models\Promotion;
use App\Models\TrainerPromotion;
use App\Models\Plan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class PromotionService
{
    /**
     * Haal prijs uit gymies_plans tabel.
     */
    private function getPlanPrice(string $slug): int
    {
        $plan = Plan::where('slug', $slug)->first();
        return $plan?->price_cents_per_month ?? 0;
    }

    // ─────────────────────────────────────────────────
    //  VALIDATIE
    // ─────────────────────────────────────────────────

    public function validateCode(string $code, int $trainerUserId, string $slug): ?array
    {
        $promotion = Promotion::where('code', strtoupper(trim($code)))
            ->available()
            ->first();

        if (! $promotion) {
            return null;
        }

        if (! $promotion->isValidForPlan($slug)) {
            return ['error' => 'Deze code is niet geldig voor dit plan.'];
        }

        if (! $promotion->canBeUsedBy($trainerUserId)) {
            return ['error' => 'Je hebt deze code al gebruikt.'];
        }

        $originalPrice = $this->getPlanPrice($slug);

        return [
            'valid'    => true,
            'promotion' => $promotion->toDisplayArray($originalPrice),
        ];
    }

    // ─────────────────────────────────────────────────
    //  ACTIVATIE
    // ─────────────────────────────────────────────────

    public function activate(int $trainerUserId, int $promotionId, string $slug, ?string $codeUsed = null): TrainerPromotion
    {
        $promotion = Promotion::findOrFail($promotionId);

        if (! $promotion->isValid()) {
            throw new \RuntimeException('Promotie is niet meer geldig.');
        }

        if (! $promotion->canBeUsedBy($trainerUserId)) {
            throw new \RuntimeException('Je hebt deze promotie al gebruikt.');
        }

        $plan = Plan::where('slug', $slug)->first();
        $originalPrice = $plan?->price_cents_per_month ?? 0;
        $discountedPrice = $promotion->calculateFinalPrice($originalPrice);
        $expiresAt = $promotion->calculateExpiresAt();

        return DB::transaction(function () use (
            $trainerUserId, $promotion, $plan, $slug, $codeUsed,
            $originalPrice, $discountedPrice, $expiresAt
        ) {
            $promotion->increment('use_count');

            return TrainerPromotion::create([
                'trainer_user_id'       => $trainerUserId,
                'promotion_id'          => $promotion->id,
                'plan_id'               => $plan?->id,
                'status'                => 'active',
                'activated_at'          => now(),
                'expires_at'            => $expiresAt,
                'applied_slug'          => $slug,
                'original_price_cents'  => $originalPrice,
                'discounted_price_cents' => $discountedPrice,
                'months_remaining'      => $promotion->discount_months,
                'months_used'           => 0,
                'code_used'             => $codeUsed ? strtoupper(trim($codeUsed)) : null,
            ]);
        });
    }

    // ─────────────────────────────────────────────────
    //  ACTIEVE PROMO OPHALEN
    // ─────────────────────────────────────────────────

    public function getActivePromotion(int $trainerUserId): ?TrainerPromotion
    {
        return TrainerPromotion::with('promotion')
            ->where('trainer_user_id', $trainerUserId)
            ->where('status', 'active')
            ->where(function ($q) {
                $q->whereNull('expires_at')
                  ->orWhere('expires_at', '>', now());
            })
            ->latest('activated_at')
            ->first();
    }

    // ─────────────────────────────────────────────────
    //  PLANS ENRICHEN MET PROMO-DATA
    // ─────────────────────────────────────────────────

    /**
     * Voeg actieve campagnes toe aan de plan-data voor de app.
     * Wordt aangeroepen vanuit je PlansController (GET /api/plans).
     */
    public function enrichPlansWithPromotions(array $plans, ?int $trainerUserId = null): array
    {
        $campaigns = Promotion::activeCampaigns()->get();
        $trainerPromo = $trainerUserId ? $this->getActivePromotion($trainerUserId) : null;

        foreach ($plans as &$plan) {
            $slug = $plan['slug'] ?? '';
            $originalPrice = $plan['price_cents_per_month'] ?? 0;

            // Trainer heeft al actieve promo voor dit plan
            if ($trainerPromo && $trainerPromo->applied_slug === $slug) {
                $plan['price_label']    = $trainerPromo->discounted_price_cents !== null
                    ? '€' . number_format($trainerPromo->discounted_price_cents / 100, 2, ',', '.')
                    : null;
                $plan['original_price'] = '€' . number_format($originalPrice / 100, 2, ',', '.');
                $plan['promo_label']    = $trainerPromo->promotion?->display_label;
                $plan['badge_label']    = $trainerPromo->promotion?->display_badge ?? $plan['badge_label'] ?? null;
                $plan['active_promotion'] = $trainerPromo->toAppArray();
                continue;
            }

            // Zoek beste campagne voor dit plan
            $bestCampaign = $campaigns
                ->filter(fn ($c) => $c->isValidForPlan($slug))
                ->sortByDesc('value_cents')
                ->first();

            if ($bestCampaign) {
                $promoData = $bestCampaign->toDisplayArray($originalPrice);
                $plan['price_label']    = $promoData['price'];
                $plan['original_price'] = $promoData['original_price'];
                $plan['promo_label']    = $promoData['display_label'];
                $plan['badge_label']    = $promoData['display_badge'] ?? $plan['badge_label'] ?? null;
                $plan['available_promotion'] = $promoData;
            }
        }

        return $plans;
    }

    // ─────────────────────────────────────────────────
    //  MOLLIE WEBHOOK
    // ─────────────────────────────────────────────────

    public function handleMolliePayment(int $trainerUserId): void
    {
        $trainerPromo = $this->getActivePromotion($trainerUserId);
        if (! $trainerPromo) return;

        $promotion = $trainerPromo->promotion;
        if (! $promotion) return;

        if ($promotion->type === 'discount_months') {
            $trainerPromo->recordMonthUsed();

            Log::info('Promo maand verbruikt', [
                'trainer_user_id' => $trainerUserId,
                'promotion_slug'  => $promotion->slug,
                'months_used'     => $trainerPromo->fresh()->months_used,
                'months_remaining' => $trainerPromo->fresh()->months_remaining,
            ]);
        }
    }

    public function handleTrialConversion(int $trainerUserId): void
    {
        $trainerPromo = $this->getActivePromotion($trainerUserId);
        if (! $trainerPromo) return;

        if ($trainerPromo->promotion?->type === 'trial') {
            $trainerPromo->markConverted();

            Log::info('Trial geconverteerd', [
                'trainer_user_id' => $trainerUserId,
                'promotion_slug'  => $trainerPromo->promotion->slug,
            ]);
        }
    }

    // ─────────────────────────────────────────────────
    //  EXPIRATIE (php artisan promotions:expire)
    // ─────────────────────────────────────────────────

    public function expireOldPromotions(): int
    {
        $count = TrainerPromotion::where('status', 'active')
            ->whereNotNull('expires_at')
            ->where('expires_at', '<=', now())
            ->update(['status' => 'expired']);

        if ($count > 0) {
            Log::info("$count trainer-promoties verlopen gemarkeerd.");
        }

        return $count;
    }
}
