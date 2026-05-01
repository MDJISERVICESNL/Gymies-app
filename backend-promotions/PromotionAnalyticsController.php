<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Promotion;
use App\Models\TrainerPromotion;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class PromotionAnalyticsController extends Controller
{
    /**
     * GET /api/admin/promo-stats
     *
     * Overzicht van alle promoties met conversie- en omzetdata.
     *
     * Query params:
     *   ?from=2026-01-01        Vanaf datum (optioneel)
     *   ?until=2026-12-31       Tot datum (optioneel)
     *   ?type=campaign           Filter op type (optioneel)
     *   ?slug=zomeractie-2026    Specifieke promotie (optioneel)
     */
    public function stats(Request $request): JsonResponse
    {
        $query = Promotion::withTrashed();

        // Filters
        if ($request->filled('type')) {
            $query->where('type', $request->input('type'));
        }
        if ($request->filled('slug')) {
            $query->where('slug', $request->input('slug'));
        }

        $promotions = $query->orderByDesc('created_at')->get();

        $from = $request->input('from');
        $until = $request->input('until');

        $stats = $promotions->map(function (Promotion $promo) use ($from, $until) {
            $tpQuery = TrainerPromotion::where('promotion_id', $promo->id);

            if ($from) {
                $tpQuery->where('activated_at', '>=', $from);
            }
            if ($until) {
                $tpQuery->where('activated_at', '<=', $until . ' 23:59:59');
            }

            $trainerPromos = $tpQuery->get();

            $totalActivations = $trainerPromos->count();
            $activeCount = $trainerPromos->where('status', 'active')->count();
            $expiredCount = $trainerPromos->where('status', 'expired')->count();
            $cancelledCount = $trainerPromos->where('status', 'cancelled')->count();
            $convertedCount = $trainerPromos->where('status', 'converted')->count();

            // Conversieratio: trial → betaald
            $conversionRate = null;
            if ($promo->type === 'trial' && $totalActivations > 0) {
                $conversionRate = round(($convertedCount / $totalActivations) * 100, 1);
            }

            // Omzet-impact: totale korting die is gegeven
            $totalDiscountGiven = $trainerPromos->sum(function ($tp) {
                if ($tp->original_price_cents && $tp->discounted_price_cents !== null) {
                    return max(0, $tp->original_price_cents - $tp->discounted_price_cents);
                }
                return 0;
            });

            // Maanden verbruikt (voor discount_months type)
            $totalMonthsUsed = $trainerPromos->sum('months_used');

            // Totale omzet met korting (wat trainers daadwerkelijk betalen)
            $totalRevenueWithPromo = $trainerPromos->sum(function ($tp) {
                return ($tp->discounted_price_cents ?? 0) * max(1, $tp->months_used);
            });

            // Meest gebruikte codes
            $codeUsage = $trainerPromos
                ->whereNotNull('code_used')
                ->groupBy('code_used')
                ->map->count()
                ->sortDesc()
                ->take(5);

            // Performance per plan
            $perPlan = $trainerPromos
                ->groupBy('applied_slug')
                ->map(function ($group, $slug) {
                    return [
                        'slug'          => $slug,
                        'activations'   => $group->count(),
                        'active'        => $group->where('status', 'active')->count(),
                        'converted'     => $group->where('status', 'converted')->count(),
                        'cancelled'     => $group->where('status', 'cancelled')->count(),
                        'avg_discount'  => $group->avg(function ($tp) {
                            if ($tp->original_price_cents && $tp->discounted_price_cents !== null) {
                                return $tp->original_price_cents - $tp->discounted_price_cents;
                            }
                            return 0;
                        }),
                    ];
                })
                ->values();

            // Tijdlijn: activaties per week
            $timeline = $trainerPromos
                ->groupBy(function ($tp) {
                    return $tp->activated_at?->startOfWeek()->toDateString() ?? 'onbekend';
                })
                ->map(function ($group, $week) {
                    return [
                        'week'        => $week,
                        'activations' => $group->count(),
                        'conversions' => $group->where('status', 'converted')->count(),
                    ];
                })
                ->sortKeys()
                ->values();

            return [
                'promotion_id'   => $promo->id,
                'name'           => $promo->name,
                'slug'           => $promo->slug,
                'type'           => $promo->type,
                'is_active'      => $promo->is_active,
                'display_label'  => $promo->display_label,
                'code'           => $promo->code,
                'valid_from'     => $promo->valid_from?->toDateString(),
                'valid_until'    => $promo->valid_until?->toDateString(),
                'created_at'     => $promo->created_at?->toIso8601String(),

                // ── Gebruik ──
                'max_uses'          => $promo->max_uses,
                'use_count'         => $promo->use_count,
                'uses_remaining'    => $promo->max_uses !== null
                    ? max(0, $promo->max_uses - $promo->use_count)
                    : null,

                // ── Activaties & Status ──
                'total_activations' => $totalActivations,
                'status_breakdown'  => [
                    'active'    => $activeCount,
                    'expired'   => $expiredCount,
                    'cancelled' => $cancelledCount,
                    'converted' => $convertedCount,
                ],

                // ── Conversie ──
                'conversion_rate_pct' => $conversionRate,

                // ── Financieel ──
                'total_discount_given_cents'  => $totalDiscountGiven,
                'total_discount_given'        => '€' . number_format($totalDiscountGiven / 100, 2, ',', '.'),
                'total_revenue_with_promo_cents' => $totalRevenueWithPromo,
                'total_revenue_with_promo'    => '€' . number_format($totalRevenueWithPromo / 100, 2, ',', '.'),
                'total_months_used'           => $totalMonthsUsed,

                // ── Per plan ──
                'per_plan' => $perPlan,

                // ── Meest gebruikte codes ──
                'top_codes' => $codeUsage->map(function ($count, $code) {
                    return ['code' => $code, 'times_used' => $count];
                })->values(),

                // ── Tijdlijn ──
                'timeline' => $timeline,
            ];
        });

        // Totalen
        $totals = [
            'total_promotions'        => $promotions->count(),
            'active_promotions'       => $promotions->where('is_active', true)->count(),
            'total_activations'       => $stats->sum('total_activations'),
            'total_discount_given'    => '€' . number_format($stats->sum('total_discount_given_cents') / 100, 2, ',', '.'),
            'total_conversions'       => $stats->sum(fn ($s) => $s['status_breakdown']['converted']),
            'avg_conversion_rate_pct' => $stats->whereNotNull('conversion_rate_pct')->avg('conversion_rate_pct'),
        ];

        return response()->json([
            'totals' => $totals,
            'promotions' => $stats,
        ]);
    }

    /**
     * GET /api/admin/promo-stats/{slug}
     *
     * Detail van één promotie inclusief individuele trainer-activaties.
     */
    public function detail(string $slug): JsonResponse
    {
        $promo = Promotion::withTrashed()->where('slug', $slug)->firstOrFail();

        $trainerPromos = TrainerPromotion::with('promotion')
            ->where('promotion_id', $promo->id)
            ->orderByDesc('activated_at')
            ->get();

        $trainers = $trainerPromos->map(function (TrainerPromotion $tp) {
            // Haal trainer info op
            $user = DB::table('gymies_users')->where('id', $tp->trainer_user_id)->first();
            $profile = DB::table('gymies_trainer_profiles')
                ->where('user_id', $tp->trainer_user_id)
                ->first();

            return [
                'trainer_user_id'    => $tp->trainer_user_id,
                'trainer_name'       => $user?->name ?? 'Onbekend',
                'trainer_email'      => $user?->email ?? null,
                'business_name'      => $profile?->business_name ?? null,
                'status'             => $tp->status,
                'applied_plan'       => $tp->applied_slug,
                'code_used'          => $tp->code_used,
                'original_price'     => $tp->original_price_cents
                    ? '€' . number_format($tp->original_price_cents / 100, 2, ',', '.')
                    : null,
                'discounted_price'   => $tp->discounted_price_cents !== null
                    ? '€' . number_format($tp->discounted_price_cents / 100, 2, ',', '.')
                    : null,
                'discount_amount'    => ($tp->original_price_cents && $tp->discounted_price_cents !== null)
                    ? '€' . number_format(($tp->original_price_cents - $tp->discounted_price_cents) / 100, 2, ',', '.')
                    : null,
                'months_used'        => $tp->months_used,
                'months_remaining'   => $tp->months_remaining,
                'activated_at'       => $tp->activated_at?->toIso8601String(),
                'expires_at'         => $tp->expires_at?->toIso8601String(),
                'converted_at'       => $tp->converted_at?->toIso8601String(),
            ];
        });

        return response()->json([
            'promotion' => [
                'id'            => $promo->id,
                'name'          => $promo->name,
                'slug'          => $promo->slug,
                'type'          => $promo->type,
                'display_label' => $promo->display_label,
                'is_active'     => $promo->is_active,
                'created_at'    => $promo->created_at?->toIso8601String(),
            ],
            'total_trainers' => $trainers->count(),
            'trainers'       => $trainers,
        ]);
    }

    /**
     * GET /api/admin/promo-stats/compare
     *
     * Vergelijk 2+ promoties naast elkaar.
     * Query: ?slugs=zomeractie-2026,pro-zomer-2026
     */
    public function compare(Request $request): JsonResponse
    {
        $slugs = explode(',', $request->input('slugs', ''));
        $slugs = array_filter(array_map('trim', $slugs));

        if (count($slugs) < 2) {
            return response()->json([
                'error' => 'Geef minimaal 2 slugs op: ?slugs=slug1,slug2',
            ], 422);
        }

        $promotions = Promotion::withTrashed()->whereIn('slug', $slugs)->get();

        $comparison = $promotions->map(function (Promotion $promo) {
            $tps = TrainerPromotion::where('promotion_id', $promo->id)->get();
            $totalActivations = $tps->count();
            $converted = $tps->where('status', 'converted')->count();
            $cancelled = $tps->where('status', 'cancelled')->count();

            $totalDiscount = $tps->sum(function ($tp) {
                if ($tp->original_price_cents && $tp->discounted_price_cents !== null) {
                    return $tp->original_price_cents - $tp->discounted_price_cents;
                }
                return 0;
            });

            return [
                'slug'              => $promo->slug,
                'name'              => $promo->name,
                'type'              => $promo->type,
                'activations'       => $totalActivations,
                'converted'         => $converted,
                'cancelled'         => $cancelled,
                'conversion_rate'   => $totalActivations > 0
                    ? round(($converted / $totalActivations) * 100, 1) . '%'
                    : 'n/a',
                'cancel_rate'       => $totalActivations > 0
                    ? round(($cancelled / $totalActivations) * 100, 1) . '%'
                    : 'n/a',
                'total_discount'    => '€' . number_format($totalDiscount / 100, 2, ',', '.'),
                'avg_discount_per_trainer' => $totalActivations > 0
                    ? '€' . number_format(($totalDiscount / $totalActivations) / 100, 2, ',', '.')
                    : '€0,00',
            ];
        });

        // Bepaal winnaar op basis van conversie
        $winner = $comparison->sortByDesc(function ($item) {
            return (float) str_replace(['%', 'n/a'], ['', '0'], $item['conversion_rate']);
        })->first();

        return response()->json([
            'comparison' => $comparison->values(),
            'best_performer' => $winner ? $winner['slug'] : null,
        ]);
    }
}
