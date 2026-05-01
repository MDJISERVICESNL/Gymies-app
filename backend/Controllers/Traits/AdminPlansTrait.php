<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies\Traits;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

trait AdminPlansTrait
{
    public function plansIndex(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_plans')) {
            return response()->json(['plans' => []]);
        }

        $this->ensurePlansHaveSlugs();

        // Alleen actieve plannen (zelfde filtering als onboarding/website – dynamische prijzen).
        $plans = DB::table('gymies_plans')
            ->when(
                Schema::hasColumn('gymies_plans', 'is_active'),
                fn ($q) => $q->where('is_active', 1)
            )
            ->orderBy('price_cents_per_month')
            ->orderBy('id')
            ->get();

        // Eén plan per slug (duplicates filteren); plannen zonder slug nu ook tonen (id als fallback).
        $seen = [];
        $plans = $plans->filter(function ($p) use (&$seen) {
            $slug = (string) ($p->slug ?? '');
            $key = $slug !== '' ? $slug : ('id_' . ($p->id ?? ''));
            if (isset($seen[$key])) {
                return false;
            }
            $seen[$key] = true;
            return true;
        })->values();

        return response()->json(['plans' => $plans]);
    }

    /**
     * Zorg dat elk actief plan een slug heeft (starter/pro/studio). Backfill uit name indien leeg.
     */
    private function ensurePlansHaveSlugs(): void
    {
        if (!Schema::hasTable('gymies_plans') || !Schema::hasColumn('gymies_plans', 'slug')) {
            return;
        }
        $nameToSlug = [
            'starter' => 'starter',
            'pro' => 'pro',
            'studio' => 'studio',
            'elite' => 'studio',
        ];
        $rows = DB::table('gymies_plans')
            ->when(Schema::hasColumn('gymies_plans', 'is_active'), fn ($q) => $q->where('is_active', 1))
            ->get(['id', 'slug', 'name']);
        foreach ($rows as $row) {
            $slug = trim((string) ($row->slug ?? ''));
            if ($slug !== '') {
                continue;
            }
            $name = strtolower(trim((string) ($row->name ?? '')));
            $newSlug = null;
            foreach ($nameToSlug as $kw => $s) {
                if (str_contains($name, $kw)) {
                    $newSlug = $s;
                    break;
                }
            }
            if ($newSlug === null) {
                $newSlug = 'starter'; // fallback voor onbekende namen
            }
            $update = ['slug' => $newSlug];
            if (Schema::hasColumn('gymies_plans', 'updated_at')) {
                $update['updated_at'] = now();
            }
            DB::table('gymies_plans')->where('id', (int) $row->id)->update($update);
        }
    }

    /**
     * Admin: plan bijwerken (o.a. prijs per maand in centen).
     * Accepteren id (numeriek) of slug (starter, pro, studio) in de URL.
     * Bestaande abonnementen blijven op oude Mollie-bedragen tot periodewissel;
     * nieuwe select-plan gebruikt direct de nieuwe prijs.
     */
    public function plansUpdate(Request $request, string $planId): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        if (!Schema::hasTable('gymies_plans')) {
            return response()->json(['message' => 'Plan niet gevonden.'], 404);
        }

        $request->validate([
            'price_cents_per_month' => 'nullable|integer|min:0|max:10000000',
            'price_euros_per_month' => 'nullable|numeric|min:0|max:100000',
            'name' => 'nullable|string|max:255',
            'description' => 'nullable|string|max:500',
            'is_active' => 'nullable|boolean',
        ]);

        $plan = null;
        if ($this->isPositiveId($planId)) {
            $plan = DB::table('gymies_plans')->where('id', (int) $planId)->first();
        }
        if (!$plan && in_array(strtolower(trim($planId)), ['starter', 'pro', 'studio'], true)) {
            $plan = DB::table('gymies_plans')->where('slug', strtolower(trim($planId)))->first();
        }
        if (!$plan) {
            return response()->json(['message' => 'Plan niet gevonden.'], 404);
        }

        $actualPlanId = (int) $plan->id;

        $update = [];
        if ($request->has('price_cents_per_month')) {
            $update['price_cents_per_month'] = (int) $request->input('price_cents_per_month');
        } elseif ($request->has('price_euros_per_month')) {
            $update['price_cents_per_month'] = (int) round((float) $request->input('price_euros_per_month') * 100);
        }
        if ($request->has('name')) {
            $name = trim((string) $request->input('name'));
            if ($name !== '') {
                $update['name'] = $name;
            }
        }
        if ($request->has('description')) {
            $update['description'] = $request->input('description') === null
                ? null
                : trim((string) $request->input('description'));
        }
        if ($request->has('is_active')) {
            $update['is_active'] = $request->boolean('is_active') ? 1 : 0;
        }

        if (empty($update)) {
            return response()->json(['message' => 'Geen velden om bij te werken.'], 422);
        }

        if (Schema::hasColumn('gymies_plans', 'updated_at')) {
            $update['updated_at'] = now();
        }

        DB::table('gymies_plans')->where('id', $actualPlanId)->update($update);
        $fresh = DB::table('gymies_plans')->where('id', $actualPlanId)->first();

        return response()->json(['plan' => $fresh, 'message' => 'Plan bijgewerkt.']);
    }

    /**
     * Sync prijzen uit gymies_plans naar site_subscriptions_json (alleen prijsveld, rest blijft).
     */
    public function plansSyncToSite(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.payments.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $count = $this->syncPlansToSiteSubscriptionsJson();
        if ($count === 0) {
            return response()->json([
                'message' => 'Geen plannen gevonden om te synchroniseren. Controleer dat gymies_plans de slugs starter, pro en studio heeft (draai alter_gymies_fix_plans_and_site_subscriptions.sql indien nodig).',
            ], 422);
        }
        return response()->json(['message' => "Prijzen gesynchroniseerd naar landingspagina ($count plan(nen)).", 'synced_count' => $count]);
    }

    /**
     * Sync gymies_plans → site_subscriptions_json zodat landingspagina actuele prijzen toont.
     * Wijzigt ALLEEN de prijs per plan; rest (title, description, features, layout) blijft intact.
     * Retourneert aantal gesynchroniseerde plannen (0 als niets gedaan).
     */
    private function syncPlansToSiteSubscriptionsJson(): int
    {
        if (!Schema::hasTable('gymies_plans') || !Schema::hasTable('gymies_system_settings')) {
            return 0;
        }

        $this->ensurePlansHaveSlugs();

        // Map slug → prijsstring
        $plans = DB::table('gymies_plans')
            ->when(
                Schema::hasColumn('gymies_plans', 'is_active'),
                fn ($q) => $q->where('is_active', 1)
            )
            ->orderBy('price_cents_per_month')
            ->orderBy('id')
            ->get(['slug', 'price_cents_per_month']);

        $slugToPrice = [];
        $orderedPrices = [];
        $orderedSlugs = [];
        foreach ($plans as $p) {
            $slug = (string) ($p->slug ?? '');
            if ($slug === '') {
                continue;
            }
            $cents = (int) ($p->price_cents_per_month ?? 0);
            $euro = $cents / 100;
            $priceStr = $cents === 0
                ? '€0'
                : ($euro == floor($euro) ? '€' . (int) $euro : '€' . number_format($euro, 2, ',', ''));
            $slugToPrice[$slug] = $priceStr;
            $orderedPrices[] = $priceStr;
            $orderedSlugs[] = $slug;
        }

        if ($slugToPrice === []) {
            return 0;
        }

        // Bestaande site_subscriptions_json laden
        $row = DB::table('gymies_system_settings')->where('setting_key', 'site_subscriptions_json')->first();
        $existing = $row ? trim((string) ($row->setting_value ?? '')) : '';

        if ($existing !== '') {
            $decoded = json_decode($existing, true);
            if (is_array($decoded) && count($decoded) > 0) {
                // Alleen prijzen bijwerken; rest onaangeroerd
                $slugMatch = [
                    'starter' => ['starter'],
                    'pro' => ['pro'],
                    'studio' => ['studio', 'elite'],
                ];
                foreach ($decoded as $i => $item) {
                    if (!is_array($item)) {
                        continue;
                    }
                    $title = strtolower(trim((string) ($item['title'] ?? '')));
                    $slugFromItem = $item['slug'] ?? null;
                    if ($slugFromItem !== null && isset($slugToPrice[$slugFromItem])) {
                        $decoded[$i]['price'] = $slugToPrice[$slugFromItem];
                        $decoded[$i]['slug'] = $slugFromItem;
                        continue;
                    }
                    foreach ($slugMatch as $slug => $keywords) {
                        foreach ($keywords as $kw) {
                            if (str_contains($title, $kw)) {
                                $decoded[$i]['price'] = $slugToPrice[$slug] ?? $item['price'] ?? '€0';
                                $decoded[$i]['slug'] = $slug;
                                break 2;
                            }
                        }
                    }
                    // Position-based fallback: eerste kaart = eerste plan, etc.
                    if (isset($orderedPrices[$i], $orderedSlugs[$i])) {
                        $decoded[$i]['price'] = $orderedPrices[$i];
                        $decoded[$i]['slug'] = $orderedSlugs[$i];
                    }
                }
                $json = json_encode($decoded, JSON_UNESCAPED_UNICODE);
                if ($json !== false) {
                    $updateData = ['setting_value' => $json];
                    if (Schema::hasColumn('gymies_system_settings', 'updated_at')) {
                        $updateData['updated_at'] = now();
                    }
                    DB::table('gymies_system_settings')->updateOrInsert(
                        ['setting_key' => 'site_subscriptions_json'],
                        $updateData
                    );
                }
                return count($slugToPrice);
            }
        }

        // Geen bestaande JSON of ongeldig → opnieuw opbouwen
        $defaults = [
            'starter' => ['description' => 'Voor de beginnende trainer', 'features' => ['1 Actief profiel', 'Directe boekingen', 'Support via community'], 'buttonText' => 'Begin gratis', 'isFeatured' => false],
            'pro' => ['description' => 'Meest gekozen door experts', 'features' => ['Story functionaliteit', '0% Commissie op sessies', 'Priority in zoekresultaten', 'Uitgebreide analytics'], 'buttonText' => 'Start met Pro', 'isFeatured' => true],
            'studio' => ['description' => 'Voor studio\'s en gyms', 'features' => ['Onbeperkt trainers', 'Eigen branding opties', 'API koppelingen', 'Dedicated manager'], 'buttonText' => 'Contact sales', 'isFeatured' => false],
        ];
        $plansFull = DB::table('gymies_plans')
            ->when(Schema::hasColumn('gymies_plans', 'is_active'), fn ($q) => $q->where('is_active', 1))
            ->orderBy('price_cents_per_month')
            ->orderBy('id')
            ->get(['slug', 'name', 'description', 'price_cents_per_month']);

        $arr = [];
        foreach ($plansFull as $p) {
            $slug = (string) ($p->slug ?? '');
            if ($slug === '' || !isset($slugToPrice[$slug])) {
                continue;
            }
            $def = $defaults[$slug] ?? ['description' => (string) ($p->description ?? ''), 'features' => [], 'buttonText' => 'Kies plan', 'isFeatured' => false];
            $arr[] = [
                'slug' => $slug,
                'title' => (string) ($p->name ?? ucfirst($slug)),
                'price' => $slugToPrice[$slug],
                'description' => trim((string) ($p->description ?? '')) !== '' ? (string) $p->description : $def['description'],
                'features' => $def['features'],
                'buttonText' => $def['buttonText'],
                'isFeatured' => $def['isFeatured'],
            ];
        }
        if ($arr !== []) {
            $json = json_encode($arr, JSON_UNESCAPED_UNICODE);
            if ($json !== false) {
                $updateData = ['setting_value' => $json];
                if (Schema::hasColumn('gymies_system_settings', 'updated_at')) {
                    $updateData['updated_at'] = now();
                }
                DB::table('gymies_system_settings')->updateOrInsert(
                    ['setting_key' => 'site_subscriptions_json'],
                    $updateData
                );
            }
        }
        return count($slugToPrice);
    }

    /**
     * Admin: abonnement toewijzen aan gebruiker/trainer met 1 klik.
     * Werkt voor trainers en klanten (klant wordt automatisch trainer).
     * Geen Mollie-flow — direct actief in de database.
     */
    public function assignSubscription(Request $request, string $userId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.users.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($userId)) {
            return response()->json(['message' => 'Ongeldige user id.'], 422);
        }
        $request->validate(['plan_slug' => 'required|string|in:starter,pro,studio']);
        $planSlug = $request->input('plan_slug');

        if (!Schema::hasTable('gymies_plans') || !Schema::hasTable('gymies_subscriptions')) {
            return response()->json(['message' => 'SaaS-tabellen ontbreken. Draai migraties.'], 503);
        }

        $plan = DB::table('gymies_plans')->where('slug', $planSlug)->where('is_active', 1)->first();
        if (!$plan) {
            return response()->json(['message' => 'Plan niet gevonden of niet actief.'], 404);
        }

        $user = DB::table('gymies_users')->where('id', (int) $userId)->first();
        if (!$user) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }

        $trainerId = (int) $userId;
        $now = now();

        if ((string) $user->role !== 'trainer') {
            DB::table('gymies_users')->where('id', $trainerId)->update([
                'role' => 'trainer',
                'updated_at' => $now,
            ]);
        }

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Trainerprofielen-tabel ontbreekt.'], 503);
        }

        $profile = DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->first();
        if (!$profile) {
            DB::table('gymies_trainer_profiles')->insert([
                'user_id' => $trainerId,
                'bio' => null,
                'specialty' => null,
                'hourly_rate_cents' => null,
                'region' => null,
                'is_available' => 0,
                'subscription_plan' => $planSlug,
                'mollie_onboarding_status' => 'not_started',
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        } else {
            DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->update([
                'subscription_plan' => $planSlug,
                'updated_at' => $now,
            ]);
        }

        $cancelPayload = [
            'status' => 'cancelled',
            'cancelled_at' => $now,
            'updated_at' => $now,
        ];
        if (Schema::hasColumn('gymies_subscriptions', 'cancel_reason')) {
            $cancelPayload['cancel_reason'] = 'Admin: nieuw plan toegewezen';
        }
        DB::table('gymies_subscriptions')
            ->where('trainer_user_id', $trainerId)
            ->whereIn('status', ['active', 'trialing'])
            ->update($cancelPayload);

        $periodStart = $now->toDateString();
        $periodEnd = $now->copy()->addMonth()->toDateString();

        DB::table('gymies_subscriptions')->insert([
            'trainer_user_id' => $trainerId,
            'plan_id' => (int) $plan->id,
            'status' => 'active',
            'current_period_start' => $periodStart,
            'current_period_end' => $periodEnd,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $this->audit((int) $admin->id, 'admin_assign_subscription', 'user', $trainerId, [
            'plan_slug' => $planSlug,
            'plan_id' => (int) $plan->id,
        ]);

        return response()->json([
            'ok' => true,
            'message' => ucfirst($planSlug) . ' toegewezen aan ' . ($user->display_name ?? $user->email),
            'subscription_plan' => $planSlug,
        ]);
    }

    /**
     * Admin: trainer onboarding pipeline (wie zit waar in het onboarding-proces).
     */
    public function onboardingPipeline(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }

        $trainers = DB::table('gymies_users as u')
            ->leftJoin('gymies_trainer_profiles as tp', 'tp.user_id', '=', 'u.id')
            ->where('u.role', 'trainer')
            ->select(
                'u.id', 'u.display_name', 'u.email', 'u.created_at',
                'tp.mollie_onboarding_status', 'tp.subscription_plan', 'tp.mollie_profile_id'
            )
            ->orderByDesc('u.created_at')
            ->get();

        $result = [];
        foreach ($trainers as $t) {
            $docs = [];
            if (Schema::hasTable('gymies_document_uploads') && Schema::hasColumn('gymies_document_uploads', 'document_category')) {
                $docs = DB::table('gymies_document_uploads')
                    ->where('user_id', (int) $t->id)
                    ->whereIn('document_category', ['kvk_extract', 'id_document', 'certification', 'vog'])
                    ->get(['document_category', 'verified_at', 'rejected_at'])
                    ->keyBy('document_category')
                    ->toArray();
            }
            $hasSub = Schema::hasTable('gymies_subscriptions')
                ? DB::table('gymies_subscriptions')
                    ->where('trainer_user_id', (int) $t->id)
                    ->whereIn('status', ['active', 'trialing'])
                    ->exists()
                : false;

            $result[] = [
                'trainer_id' => (string) $t->id,
                'name' => $t->display_name,
                'email' => $t->email,
                'registered_at' => $t->created_at,
                'documents' => $docs,
                'mollie_status' => $t->mollie_onboarding_status ?? 'not_started',
                'has_mollie_profile' => $t->mollie_profile_id !== null,
                'subscription_plan' => $t->subscription_plan,
                'has_active_subscription' => $hasSub,
            ];
        }

        return response()->json(['trainers' => $result]);
    }

    /**
     * Admin: ghost-rating dashboard (overzicht per trainer).
     */
    public function ghostRatingDashboard(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request);
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_ghost_ratings')) {
            return response()->json(['trainers' => []]);
        }

        $trainers = DB::table('gymies_ghost_ratings as gr')
            ->join('gymies_users as u', 'u.id', '=', 'gr.trainer_user_id')
            ->select(
                'gr.trainer_user_id',
                'u.display_name as trainer_name',
                DB::raw('ROUND(AVG(gr.punctuality), 2) as avg_punctuality'),
                DB::raw('ROUND(AVG(gr.energy), 2) as avg_energy'),
                DB::raw('ROUND(AVG(gr.would_rebook), 2) as avg_would_rebook'),
                DB::raw('COUNT(*) as total_ratings'),
            )
            ->groupBy('gr.trainer_user_id', 'u.display_name')
            ->orderByRaw('AVG(gr.energy) ASC')
            ->get();

        return response()->json(['trainers' => $trainers]);
    }
}
