<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trait: Beschikbare plannen ophalen uit gymies_plans.
 * Gebruik in GymiesSubscriptionController::availablePlans:
 *   return $this->availablePlansResponse();
 *
 * Tabel gymies_plans: id, slug, name, amount_cents, price_label, sort_order
 */
trait AvailablePlansTrait
{
    public function availablePlansResponse(): JsonResponse
    {
        if (!Schema::hasTable('gymies_plans')) {
            return response()->json([
                'data' => $this->defaultPlansFallback(),
            ]);
        }

        $rows = DB::table('gymies_plans')
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get();

        if ($rows->isEmpty()) {
            return response()->json([
                'data' => $this->defaultPlansFallback(),
            ]);
        }

        $plans = $rows->map(function ($row) {
            $amountCents = (int) ($row->amount_cents ?? 0);
            $priceLabel = $row->price_label ?? ('€' . number_format($amountCents / 100, 2, ',', '') . '/mnd');
            return [
                'id' => $row->id,
                'plan_id' => $row->id,
                'slug' => $row->slug,
                'plan_slug' => $row->slug,
                'name' => $row->name,
                'plan_name' => $row->name,
                'amount_cents' => $amountCents,
                'amount' => $amountCents,
                'price' => $amountCents / 100,
                'price_label' => $priceLabel,
            ];
        })->values()->all();

        return response()->json(['data' => $plans]);
    }

    private function defaultPlansFallback(): array
    {
        return [
            ['id' => 1, 'slug' => 'starter', 'name' => 'Starter', 'amount_cents' => 2995, 'price_label' => '€29,95/mnd'],
            ['id' => 2, 'slug' => 'pro', 'name' => 'Pro', 'amount_cents' => 5995, 'price_label' => '€59,95/mnd'],
            ['id' => 3, 'slug' => 'elite', 'name' => 'Elite', 'amount_cents' => 9995, 'price_label' => '€99,95/mnd'],
        ];
    }
}
