<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class TrainerPromotion extends Model
{
    protected $table = 'gymies_trainer_promotions';

    protected $fillable = [
        'trainer_user_id', 'promotion_id', 'plan_id', 'status',
        'activated_at', 'expires_at', 'converted_at', 'applied_slug',
        'original_price_cents', 'discounted_price_cents',
        'months_remaining', 'months_used', 'code_used',
        'mollie_subscription_id', 'mollie_mandate_id',
    ];

    protected $casts = [
        'activated_at'          => 'datetime',
        'expires_at'            => 'datetime',
        'converted_at'          => 'datetime',
        'original_price_cents'  => 'integer',
        'discounted_price_cents' => 'integer',
        'months_remaining'      => 'integer',
        'months_used'           => 'integer',
    ];

    // ─── Relaties ───

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class, 'trainer_user_id');
    }

    public function promotion(): BelongsTo
    {
        return $this->belongsTo(Promotion::class);
    }

    public function plan(): BelongsTo
    {
        return $this->belongsTo(Plan::class);
    }

    // ─── Scopes ───

    public function scopeActive($query)
    {
        return $query->where('status', 'active');
    }

    // ─── Helpers ───

    public function isActive(): bool
    {
        if ($this->status !== 'active') return false;
        if ($this->expires_at && $this->expires_at->isPast()) return false;
        return true;
    }

    public function daysRemaining(): ?int
    {
        if (! $this->expires_at) return null;
        return max(0, (int) now()->diffInDays($this->expires_at, false));
    }

    public function isTrialEndingSoon(int $withinDays = 3): bool
    {
        if (! $this->promotion) return false;
        if ($this->promotion->type !== 'trial') return false;
        if (! $this->expires_at) return false;

        $remaining = $this->daysRemaining();
        return $remaining !== null && $remaining <= $withinDays && $remaining >= 0;
    }

    public function markExpired(): void
    {
        $this->update(['status' => 'expired']);
    }

    public function markConverted(): void
    {
        $this->update([
            'status'       => 'converted',
            'converted_at' => now(),
        ]);
    }

    public function recordMonthUsed(): void
    {
        $this->increment('months_used');
        if ($this->months_remaining !== null) {
            $this->decrement('months_remaining');
        }

        if ($this->months_remaining !== null && $this->months_remaining <= 0) {
            $this->markExpired();
        }
    }

    /**
     * Data voor de app.
     */
    public function toAppArray(): array
    {
        $promo = $this->promotion;

        return [
            'id'                    => $this->id,
            'promotion_id'          => $this->promotion_id,
            'promotion_slug'        => $promo?->slug,
            'type'                  => $promo?->type,
            'status'                => $this->status,
            'display_label'         => $promo?->display_label,
            'applied_tier'          => $this->applied_slug,
            'original_price_cents'  => $this->original_price_cents,
            'discounted_price_cents' => $this->discounted_price_cents,
            'original_price'        => $this->original_price_cents
                ? '€' . number_format($this->original_price_cents / 100, 2, ',', '.')
                : null,
            'discounted_price'      => $this->discounted_price_cents !== null
                ? '€' . number_format($this->discounted_price_cents / 100, 2, ',', '.')
                : null,
            'activated_at'          => $this->activated_at?->toIso8601String(),
            'expires_at'            => $this->expires_at?->toIso8601String(),
            'days_remaining'        => $this->daysRemaining(),
            'months_remaining'      => $this->months_remaining,
            'months_used'           => $this->months_used,
            'is_trial'              => $promo?->type === 'trial',
            'is_active'             => $this->isActive(),
        ];
    }
}
