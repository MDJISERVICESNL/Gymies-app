<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Carbon\Carbon;

class Promotion extends Model
{
    use SoftDeletes;

    protected $table = 'gymies_promotions';

    protected $fillable = [
        'name', 'slug', 'type', 'discount_type', 'value_cents',
        'discount_months', 'trial_days', 'campaign_price_cents',
        'valid_from', 'valid_until', 'is_active', 'max_uses', 'use_count',
        'max_uses_per_trainer', 'code', 'applicable_plan_ids', 'applicable_slugs',
        'new_subscriptions_only', 'display_label', 'display_badge',
        'description', 'mollie_coupon_id',
    ];

    protected $casts = [
        'is_active'              => 'boolean',
        'new_subscriptions_only' => 'boolean',
        'valid_from'             => 'date',
        'valid_until'            => 'date',
        'applicable_plan_ids'    => 'array',
        'applicable_slugs'       => 'array',
        'max_uses'               => 'integer',
        'use_count'              => 'integer',
        'max_uses_per_trainer'   => 'integer',
        'value_cents'            => 'integer',
        'discount_months'        => 'integer',
        'trial_days'             => 'integer',
        'campaign_price_cents'   => 'integer',
    ];

    // ─── Relaties ───

    public function trainerPromotions(): HasMany
    {
        return $this->hasMany(TrainerPromotion::class, 'promotion_id');
    }

    // ─── Scopes ───

    public function scopeAvailable($query)
    {
        return $query
            ->where('is_active', true)
            ->where(function ($q) {
                $q->whereNull('valid_from')->orWhere('valid_from', '<=', now()->toDateString());
            })
            ->where(function ($q) {
                $q->whereNull('valid_until')->orWhere('valid_until', '>=', now()->toDateString());
            })
            ->where(function ($q) {
                $q->whereNull('max_uses')->orWhereColumn('use_count', '<', 'max_uses');
            });
    }

    public function scopeActiveCampaigns($query)
    {
        return $query->available()->whereIn('type', ['campaign', 'trial']);
    }

    // ─── Helpers ───

    public function isValid(): bool
    {
        if (! $this->is_active) return false;
        if ($this->valid_from && Carbon::parse($this->valid_from)->isFuture()) return false;
        if ($this->valid_until && Carbon::parse($this->valid_until)->isPast()) return false;
        if ($this->max_uses !== null && $this->use_count >= $this->max_uses) return false;
        return true;
    }

    public function isValidForPlan($planIdOrSlug): bool
    {
        if (! $this->isValid()) return false;

        // Check op plan ID
        if (! empty($this->applicable_plan_ids) && is_numeric($planIdOrSlug)) {
            return in_array((int) $planIdOrSlug, $this->applicable_plan_ids);
        }

        // Check op slug
        if (! empty($this->applicable_slugs)) {
            return in_array($planIdOrSlug, $this->applicable_slugs);
        }

        // Geen beperking = alle plannen
        return true;
    }

    public function canBeUsedBy(int $trainerUserId): bool
    {
        if (! $this->isValid()) return false;

        $usageCount = $this->trainerPromotions()
            ->where('trainer_user_id', $trainerUserId)
            ->count();

        return $usageCount < $this->max_uses_per_trainer;
    }

    /**
     * Bereken korting in centen.
     */
    public function calculateDiscount(int $originalPriceCents): int
    {
        if ($this->type === 'campaign' && $this->campaign_price_cents !== null) {
            return max(0, $originalPriceCents - $this->campaign_price_cents);
        }

        if ($this->type === 'trial') {
            return $originalPriceCents; // 100% korting tijdens trial
        }

        if ($this->discount_type === 'percent') {
            return (int) round($originalPriceCents * $this->value_cents / 100);
        }

        // fixed (value_cents = bedrag in centen)
        return min($this->value_cents, $originalPriceCents);
    }

    public function calculateFinalPrice(int $originalPriceCents): int
    {
        return max(0, $originalPriceCents - $this->calculateDiscount($originalPriceCents));
    }

    public function calculateExpiresAt(): ?Carbon
    {
        if ($this->type === 'trial' && $this->trial_days) {
            return now()->addDays($this->trial_days);
        }
        if ($this->type === 'discount_months' && $this->discount_months) {
            return now()->addMonths($this->discount_months);
        }
        if ($this->type === 'campaign' && $this->valid_until) {
            return Carbon::parse($this->valid_until)->endOfDay();
        }
        return null;
    }

    /**
     * Data voor de app (plans endpoint).
     */
    public function toDisplayArray(int $originalPriceCents): array
    {
        $finalPrice = $this->calculateFinalPrice($originalPriceCents);

        return [
            'promotion_id'     => $this->id,
            'promotion_slug'   => $this->slug,
            'type'             => $this->type,
            'display_label'    => $this->display_label,
            'display_badge'    => $this->display_badge,
            'discount_type'    => $this->discount_type,
            'discount_value'   => $this->value_cents,
            'discount_months'  => $this->discount_months,
            'trial_days'       => $this->trial_days,
            'original_price'   => '€' . number_format($originalPriceCents / 100, 2, ',', '.'),
            'price'            => '€' . number_format($finalPrice / 100, 2, ',', '.'),
            'ends_at'          => $this->valid_until?->toIso8601String(),
        ];
    }
}
