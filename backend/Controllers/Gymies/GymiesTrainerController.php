<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies API: lijst trainers, één trainer.
 * Tabellen: gymies_users, gymies_trainer_profiles.
 */
final class GymiesTrainerController extends Controller
{
    /** Log zoekvraag (locatie) voor demand heatmap. Publiek aanroepbaar. */
    public function logSearch(Request $request): JsonResponse
    {
        $request->validate(['location_query' => 'required|string|max:255']);
        $query = trim((string) $request->input('location_query'));
        if ($query === '') {
            return response()->json(['ok' => true]);
        }
        if (!Schema::hasTable('gymies_search_log')) {
            return response()->json(['ok' => true]);
        }
        $userId = null;
        $user = $request->attributes->get('gymies_user');
        if ($user && isset($user->id)) {
            $userId = (int) $user->id;
        }
        $cityNormalized = mb_strtolower($query);
        if (mb_strlen($cityNormalized) > 100) {
            $cityNormalized = mb_substr($cityNormalized, 0, 100);
        }
        DB::table('gymies_search_log')->insert([
            'user_id' => $userId,
            'location_query' => $query,
            'city_normalized' => $cityNormalized,
            'created_at' => now(),
        ]);
        return response()->json(['ok' => true]);
    }

    /**
     * Publiek: tot 12 steden waar trainers staan (primaire/niet-online locatie-stad, anders profiel-regio).
     * Alleen steden met minstens één trainer; gesorteerd op aantal trainers.
     */
    public function landingCities(Request $request): JsonResponse
    {
        $limit = (int) $request->query('limit', 12);
        $limit = max(1, min(12, $limit));

        if (!Schema::hasTable('gymies_users') || !Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['data' => []]);
        }

        // S-050: Exclude deleted/inactive trainers
        $usersQuery = DB::table('gymies_users as u')
            ->join('gymies_trainer_profiles as p', 'u.id', '=', 'p.user_id')
            ->where('u.role', 'trainer');
        if (Schema::hasColumn('gymies_users', 'deleted_at')) {
            $usersQuery->whereNull('u.deleted_at');
        }
        if (Schema::hasColumn('gymies_users', 'is_active')) {
            $usersQuery->where('u.is_active', 1);
        }
        $usersQuery->select('u.id as user_id', 'p.region');

        if (Schema::hasColumn('gymies_trainer_profiles', 'moderation_status')) {
            $usersQuery->where(function ($q) {
                $q->whereNull('p.moderation_status')->orWhere('p.moderation_status', 'approved');
            });
        }

        $trainers = $usersQuery->get();
        $cityByTrainer = [];

        if (Schema::hasTable('gymies_trainer_locations') && $trainers->isNotEmpty()) {
            $ids = $trainers->pluck('user_id')->map(static fn ($id) => (int) $id)->all();
            $locs = DB::table('gymies_trainer_locations')
                ->whereIn('trainer_user_id', $ids)
                ->orderByDesc('is_primary')
                ->orderBy('id')
                ->get(['trainer_user_id', 'city', 'location_type']);

            foreach ($locs as $loc) {
                $tid = (int) $loc->trainer_user_id;
                if (isset($cityByTrainer[$tid])) {
                    continue;
                }
                $lt = (string) ($loc->location_type ?? '');
                if ($lt === 'online') {
                    continue;
                }
                $city = trim((string) ($loc->city ?? ''));
                if ($city === '') {
                    continue;
                }
                $cityByTrainer[$tid] = $city;
            }
        }

        foreach ($trainers as $t) {
            $tid = (int) $t->user_id;
            if (isset($cityByTrainer[$tid])) {
                continue;
            }
            $region = trim((string) ($t->region ?? ''));
            if ($region === '') {
                continue;
            }
            $parts = preg_split('/\s*,\s*/', $region, 2);
            $city = trim((string) ($parts[0] ?? ''));
            if ($city === '') {
                continue;
            }
            $cityByTrainer[$tid] = $city;
        }

        $buckets = [];
        foreach ($cityByTrainer as $city) {
            $key = mb_strtolower($city, 'UTF-8');
            if ($key === '') {
                continue;
            }
            if (!isset($buckets[$key])) {
                $buckets[$key] = ['city' => $city, 'trainer_count' => 0];
            }
            $buckets[$key]['trainer_count']++;
        }

        uasort($buckets, static function ($a, $b) {
            if ($a['trainer_count'] !== $b['trainer_count']) {
                return $b['trainer_count'] <=> $a['trainer_count'];
            }
            return strcasecmp($a['city'], $b['city']);
        });

        $rows = array_slice(array_values($buckets), 0, $limit);

        return response()->json(['data' => $rows]);
    }

    public function index(Request $request): JsonResponse
    {
        try {
            return $this->doIndex($request);
        } catch (\Throwable $e) {
            // Log zodat we de exacte fout kunnen zien
            \Log::error('GymiesTrainerController@index FAILED', [
                'error' => $e->getMessage(),
                'file' => $e->getFile() . ':' . $e->getLine(),
                'trace' => $e->getTraceAsString(),
            ]);
            return response()->json([
                'message' => 'Server error bij trainers ophalen.',
                'debug_error' => app()->hasDebugModeEnabled() ? $e->getMessage() : null,
            ], 500);
        }
    }

    private function doIndex(Request $request): JsonResponse
    {
        $q = $request->query('q');
        $specialty = $request->query('specialty') ? trim((string) $request->query('specialty')) : null;
        $womenOnly = filter_var($request->query('women_only', false), FILTER_VALIDATE_BOOL);
        $userLat = $request->query('latitude') !== null ? (float) $request->query('latitude') : null;
        $userLng = $request->query('longitude') !== null ? (float) $request->query('longitude') : null;

        // T-008 FIXED: NaN/Inf GPS coordinaten geblokkeerd
        if ($userLat !== null && !is_finite($userLat)) {
            $userLat = null;
        }
        if ($userLng !== null && !is_finite($userLng)) {
            $userLng = null;
        }

        // Tabel-checks
        if (!Schema::hasTable('gymies_users')) {
            return response()->json(['data' => [], '_note' => 'gymies_users table missing']);
        }

        $hasGymTables = Schema::hasTable('gymies_organisation_trainers') && Schema::hasTable('gymies_organisations');
        $hasProfiles = Schema::hasTable('gymies_trainer_profiles');
        $hasReviews = Schema::hasTable('gymies_reviews');

        // S-050: Exclude deleted/inactive trainers
        $usersQuery = DB::table('gymies_users as u')
            ->where('u.role', 'trainer');

        // Veilige deleted_at check — kolom bestaat mogelijk niet
        if (Schema::hasColumn('gymies_users', 'deleted_at')) {
            $usersQuery->whereNull('u.deleted_at');
        }
        if (Schema::hasColumn('gymies_users', 'is_active')) {
            $usersQuery->where('u.is_active', 1);
        }

        $select = ['u.id as user_id', 'u.email'];
        // display_name veilig toevoegen
        if (Schema::hasColumn('gymies_users', 'display_name')) {
            $select[] = 'u.display_name';
        }
        if (Schema::hasColumn('gymies_users', 'email_verified_at')) {
            $select[] = 'u.email_verified_at';
        }

        if ($hasProfiles) {
            $usersQuery->leftJoin('gymies_trainer_profiles as p', 'u.id', '=', 'p.user_id');

            // Kern-kolommen van trainer_profiles — elk veilig checken
            $profileCols = ['id as profile_id', 'bio', 'specialty', 'hourly_rate_cents', 'avatar_url',
                'region', 'trainer_verified_at', 'certifications', 'experience_years',
                'languages', 'min_session_minutes', 'trial_session_cents', 'is_available',
            ];
            foreach ($profileCols as $col) {
                $realCol = str_contains($col, ' as ') ? explode(' as ', $col)[0] : $col;
                if (Schema::hasColumn('gymies_trainer_profiles', $realCol)) {
                    $select[] = 'p.' . $col;
                }
            }
            if (Schema::hasColumn('gymies_trainer_profiles', 'women_only')) {
                $select[] = 'p.women_only';
            }
            if (Schema::hasColumn('gymies_trainer_profiles', 'moderation_status')) {
                $usersQuery->where(function ($subQ) {
                    $subQ->whereNull('p.moderation_status')->orWhere('p.moderation_status', 'approved');
                });
                if (Schema::hasColumn('gymies_trainer_profiles', 'quality_score')) {
                    $select[] = 'p.quality_score';
                }
            }
        } else {
            $select[] = DB::raw('u.id as profile_id');
        }
        if ($hasReviews) {
            $reviews = DB::table('gymies_reviews')
                ->select('trainer_user_id', DB::raw('AVG(rating) as avg_rating'), DB::raw('COUNT(*) as review_count'))
                ->where('status', 'approved')
                ->groupBy('trainer_user_id');
            $usersQuery->leftJoinSub($reviews, 'r', fn ($join) => $join->on('u.id', '=', 'r.trainer_user_id'));
            $select[] = 'r.avg_rating';
            $select[] = 'r.review_count';
        } else {
            $select[] = DB::raw('NULL as avg_rating');
            $select[] = DB::raw('0 as review_count');
        }
        $usersQuery->select($select);

        if ($hasGymTables) {
            // Gym-tabellen veilig joinen — check dat kolommen bestaan
            $hasOtStatus = Schema::hasColumn('gymies_organisation_trainers', 'status');
            $hasOtPrimary = Schema::hasColumn('gymies_organisation_trainers', 'is_primary');
            $hasOrgStatus = Schema::hasColumn('gymies_organisations', 'status');

            $usersQuery
                ->leftJoin('gymies_organisation_trainers as ot', function ($join) use ($hasOtStatus, $hasOtPrimary) {
                    $join->on('ot.trainer_user_id', '=', 'u.id');
                    if ($hasOtStatus) {
                        $join->where('ot.status', '=', 'active');
                    }
                    if ($hasOtPrimary) {
                        $join->where('ot.is_primary', '=', 1);
                    }
                })
                ->leftJoin('gymies_organisations as o', function ($join) use ($hasOrgStatus) {
                    $join->on('o.id', '=', 'ot.organisation_id');
                    if ($hasOrgStatus) {
                        $join->where('o.status', '=', 'active');
                    }
                });

            // addSelect veilig
            $gymSelect = [];
            $gymSelect[] = 'o.id as organisation_id';
            if (Schema::hasColumn('gymies_organisations', 'name')) {
                $gymSelect[] = 'o.name as organisation_name';
            }
            if (Schema::hasColumn('gymies_organisation_trainers', 'payout_route')) {
                $gymSelect[] = 'ot.payout_route as organisation_payout_route';
            }
            if (!empty($gymSelect)) {
                $usersQuery->addSelect($gymSelect);
            }
        }
        if ($hasProfiles && $womenOnly && Schema::hasColumn('gymies_trainer_profiles', 'women_only')) {
            $usersQuery->where('p.women_only', '=', 1);
        }

        // ORDER BY — alles veilig met Schema checks
        if ($hasProfiles && Schema::hasColumn('gymies_trainer_profiles', 'quality_score')) {
            if (Schema::hasColumn('gymies_trainer_profiles', 'ambassador_boost')) {
                $usersQuery->orderByRaw('COALESCE(p.ambassador_boost, 0) DESC');
            }
            if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                $usersQuery->orderByRaw("CASE WHEN p.subscription_plan IN ('pro','pro_plus','studio','elite') THEN 0 ELSE 1 END ASC");
            }
            $usersQuery->orderByRaw('p.quality_score IS NULL ASC')->orderByDesc('p.quality_score');
            if (Schema::hasColumn('gymies_trainer_profiles', 'sort_order')) {
                $usersQuery->orderByRaw('p.sort_order IS NULL ASC')->orderBy('p.sort_order');
            }
            $usersQuery->orderBy('u.display_name');
        } else {
            if ($hasProfiles && Schema::hasColumn('gymies_trainer_profiles', 'ambassador_boost')) {
                $usersQuery->orderByRaw('COALESCE(p.ambassador_boost, 0) DESC');
            }
            if ($hasProfiles && Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                $usersQuery->orderByRaw("CASE WHEN p.subscription_plan IN ('pro','pro_plus','studio','elite') THEN 0 ELSE 1 END ASC");
            }
            $usersQuery->orderBy('u.display_name');
        }
        $users = $usersQuery->get();

        if ($q) {
            $q = strtolower($q);
            $users = $users->filter(function ($u) use ($q) {
                return str_contains(strtolower($u->email ?? ''), $q)
                    || str_contains(strtolower($u->display_name ?? ''), $q)
                    || str_contains(strtolower($u->specialty ?? ''), $q)
                    || str_contains(strtolower($u->region ?? ''), $q)
                    || str_contains(strtolower($u->organisation_name ?? ''), $q);
            })->values();
        }
        if ($specialty !== null && $specialty !== '') {
            $tag = strtolower($specialty);
            $users = $users->filter(function ($u) use ($tag) {
                $s = strtolower($u->specialty ?? '');
                if ($s === '') return false;
                return $s === $tag
                    || str_starts_with($s, $tag . ',')
                    || str_ends_with($s, ',' . $tag)
                    || str_contains($s, ',' . $tag . ',');
            })->values();
        }

        // Afstand berekenen en sorteren als lat/lng gegeven
        $hasLocations = Schema::hasTable('gymies_trainer_locations');
        if ($userLat !== null && $userLng !== null && $hasLocations) {
            $userLatRad = deg2rad($userLat);
            $userLngRad = deg2rad($userLng);
            $locations = DB::table('gymies_trainer_locations')
                ->whereNotNull('latitude')
                ->whereNotNull('longitude')
                ->whereIn('trainer_user_id', $users->pluck('user_id'))
                ->orderBy('is_primary', 'desc')
                ->get(['trainer_user_id', 'latitude', 'longitude']);
            $locByTrainer = [];
            foreach ($locations as $loc) {
                $tid = (string) $loc->trainer_user_id;
                if (!isset($locByTrainer[$tid])) {
                    $locByTrainer[$tid] = [(float) $loc->latitude, (float) $loc->longitude];
                }
            }
            $users = $users->map(function ($u) use ($locByTrainer, $userLatRad, $userLngRad) {
                $u->distance_km = null;
                $coords = $locByTrainer[(string) $u->user_id] ?? null;
                if ($coords) {
                    $latRad = deg2rad($coords[0]);
                    $lngRad = deg2rad($coords[1]);
                    $earthKm = 6371;
                    $u->distance_km = $earthKm * 2 * asin(sqrt(
                        pow(sin(($userLatRad - $latRad) / 2), 2) +
                        cos($userLatRad) * cos($latRad) * pow(sin(($userLngRad - $lngRad) / 2), 2)
                    ));
                }
                return $u;
            });
            $users = $users->sortBy(function ($u) {
                $d = $u->distance_km ?? 999999;
                return $d;
            })->values();
        }

        $data = $users->map(fn ($u) => $this->trainerToArray($u))->all();
        return response()->json(['data' => $data]);
    }

    public function show(string $id): JsonResponse
    {
        try {
        $hasGymTables = Schema::hasTable('gymies_organisation_trainers') && Schema::hasTable('gymies_organisations');
        $hasProfiles = Schema::hasTable('gymies_trainer_profiles');
        $hasReviews = Schema::hasTable('gymies_reviews');

        $query = DB::table('gymies_users as u')->where('u.id', $id)->where('u.role', 'trainer');

        $select = ['u.id as user_id', 'u.email'];
        if (Schema::hasColumn('gymies_users', 'display_name')) {
            $select[] = 'u.display_name';
        }
        if (Schema::hasColumn('gymies_users', 'email_verified_at')) {
            $select[] = 'u.email_verified_at';
        }
        if ($hasProfiles) {
            $query->leftJoin('gymies_trainer_profiles as p', 'u.id', '=', 'p.user_id');
            // Veilig: alleen kolommen selecteren die daadwerkelijk bestaan
            $profileCols = ['p.id as profile_id'];
            $allProfileCols = [
                'bio', 'specialty', 'hourly_rate_cents', 'avatar_url',
                'region', 'trainer_verified_at', 'certifications', 'experience_years',
                'languages', 'min_session_minutes', 'trial_session_cents', 'is_available',
                'women_only', 'duo_surcharge_cents', 'travel_surcharge_cents',
                'lead_time_minutes', 'booking_max_days_ahead',
            ];
            foreach ($allProfileCols as $col) {
                if (Schema::hasColumn('gymies_trainer_profiles', $col)) {
                    $profileCols[] = 'p.' . $col;
                }
            }
            // Gymies Pro kolommen (groep)
            if (Schema::hasColumn('gymies_trainer_profiles', 'is_gymies_pro')) {
                $profileCols[] = 'p.is_gymies_pro';
                if (Schema::hasColumn('gymies_trainer_profiles', 'gymies_pro_since')) {
                    $profileCols[] = 'p.gymies_pro_since';
                }
                if (Schema::hasColumn('gymies_trainer_profiles', 'consecutive_completed')) {
                    $profileCols[] = 'p.consecutive_completed';
                }
            }
            // Betaalmethode kolommen (groep)
            if (Schema::hasColumn('gymies_trainer_profiles', 'accepts_cash')) {
                $profileCols[] = 'p.accepts_cash';
                if (Schema::hasColumn('gymies_trainer_profiles', 'accepts_online')) {
                    $profileCols[] = 'p.accepts_online';
                }
                if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                    $profileCols[] = 'p.subscription_plan';
                }
                if (Schema::hasColumn('gymies_trainer_profiles', 'mollie_onboarding_status')) {
                    $profileCols[] = 'p.mollie_onboarding_status';
                }
            }
            if (Schema::hasColumn('gymies_trainer_profiles', 'spoed_inval_standby_date')) {
                $profileCols[] = 'p.spoed_inval_standby_date';
            }
            $select = array_merge($select, $profileCols);
        } else {
            $select[] = DB::raw('u.id as profile_id');
        }
        if ($hasReviews) {
            $reviews = DB::table('gymies_reviews')
                ->select('trainer_user_id', DB::raw('AVG(rating) as avg_rating'), DB::raw('COUNT(*) as review_count'))
                ->where('status', 'approved')
                ->groupBy('trainer_user_id');
            $query->leftJoinSub($reviews, 'r', fn ($join) => $join->on('u.id', '=', 'r.trainer_user_id'));
            $select[] = 'r.avg_rating';
            $select[] = 'r.review_count';
        } else {
            $select[] = DB::raw('NULL as avg_rating');
            $select[] = DB::raw('0 as review_count');
        }
        $query->select($select);

        if ($hasGymTables) {
            $query
                ->leftJoin('gymies_organisation_trainers as ot', function ($join) {
                    $join->on('ot.trainer_user_id', '=', 'u.id')
                        ->where('ot.status', '=', 'active')
                        ->where('ot.is_primary', '=', 1);
                })
                ->leftJoin('gymies_organisations as o', function ($join) {
                    $join->on('o.id', '=', 'ot.organisation_id')
                        ->where('o.status', '=', 'active');
                })
                ->addSelect(
                    'o.id as organisation_id',
                    'o.name as organisation_name',
                    'ot.payout_route as organisation_payout_route'
                );
        }

        $u = $query->first();

        if (!$u) {
            return response()->json(['message' => 'Trainer not found'], 404);
        }
        $data = $this->trainerToArray($u);
        // Fee Switcher: mag publiek zodat boekflow servicekosten kan tonen (default klant betaalt).
        $data['client_pays_service_fee'] = true;
        if (Schema::hasTable('gymies_trainer_bank_accounts')
            && Schema::hasColumn('gymies_trainer_bank_accounts', 'client_pays_service_fee')) {
            $cp = DB::table('gymies_trainer_bank_accounts')
                ->where('trainer_user_id', (int) $u->user_id)
                ->value('client_pays_service_fee');
            if ($cp !== null) {
                $data['client_pays_service_fee'] = (bool) (int) $cp;
            }
        }
        if (Schema::hasTable('gymies_trainer_storefront')) {
            $sf = DB::table('gymies_trainer_storefront')
                ->where('trainer_user_id', (int) $u->user_id)
                ->first();
            if ($sf) {
                $stories = [];
                if (!empty($sf->success_stories_json)) {
                    // S-083: Try-catch for JSON decoding
                    try {
                        $d = json_decode((string) $sf->success_stories_json, true);
                        if (is_array($d)) {
                            $stories = $d;
                        }
                    } catch (\Throwable) {
                        // S-083: JSON decode error — use empty stories
                        $stories = [];
                    }
                }
                $data['storefront'] = [
                    'success_stories' => $stories,
                    'video_pitch_url' => $sf->video_pitch_url,
                    'instagram_handle' => Schema::hasColumn('gymies_trainer_storefront', 'instagram_handle') ? ($sf->instagram_handle ?? null) : null,
                    'specializations_display' => $sf->specializations_display,
                    'seo_title' => $sf->seo_title,
                    'seo_description' => $sf->seo_description,
                    'seo_keywords' => $sf->seo_keywords,
                ];
            }
        }
        return response()->json(['data' => $data]);
        } catch (\Throwable $e) {
            \Log::error('[GymiesTrainerController::show] SQL/runtime error for trainer ' . $id . ': ' . $e->getMessage());
            // Fallback: retourneer minimale profieldata vanuit gymies_users
            try {
                $fallbackUser = DB::table('gymies_users')->where('id', $id)->where('role', 'trainer')->first();
                if ($fallbackUser) {
                    $displayName = property_exists($fallbackUser, 'display_name') ? ($fallbackUser->display_name ?? '') : '';
                    return response()->json(['data' => [
                        'id' => (string) $fallbackUser->id,
                        'user_id' => (string) $fallbackUser->id,
                        'email' => $fallbackUser->email ?? '',
                        'display_name' => $displayName ?: ($fallbackUser->email ?? ''),
                        'bio' => null,
                        'specialty' => null,
                        'hourly_rate_cents' => null,
                        'avatar_url' => null,
                        'region' => null,
                        'rating' => null,
                        'review_count' => 0,
                        'is_available' => true,
                        '_fallback' => true,
                    ]]);
                }
            } catch (\Throwable) {
                // Dubbele fout — geef originele melding terug
            }
            return response()->json(['message' => 'Kon trainerprofiel niet laden: ' . $e->getMessage()], 500);
        }
    }

    /**
     * Publiek: gym-locaties van de trainer (via primary organisation).
     * Voor boekflow: klant kan optioneel zaal/locatie kiezen.
     */
    public function gymLocations(string $id): JsonResponse
    {
        $trainer = DB::table('gymies_users')
            ->where('id', $id)
            ->where('role', 'trainer')
            ->first(['id']);
        if (!$trainer) {
            return response()->json(['message' => 'Trainer not found'], 404);
        }
        if (!Schema::hasTable('gymies_organisation_trainers') || !Schema::hasTable('gymies_gym_locations')) {
            return response()->json(['data' => []]);
        }
        $orgLink = DB::table('gymies_organisation_trainers')
            ->where('trainer_user_id', $id)
            ->where('status', 'active')
            ->where('is_primary', 1)
            ->first(['organisation_id']);
        if (!$orgLink || empty($orgLink->organisation_id)) {
            return response()->json(['data' => []]);
        }
        $orgId = (int) $orgLink->organisation_id;
        $rows = DB::table('gymies_gym_locations')
            ->where('organisation_id', $orgId)
            ->orderBy('sort_order')
            ->orderBy('name')
            ->get();
        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'name' => (string) $r->name,
            'location_type' => (string) ($r->location_type ?? 'zaal'),
            'capacity' => $r->capacity !== null ? (int) $r->capacity : null,
        ])->all();
        $defaultLocationId = null;
        if (Schema::hasColumn('gymies_organisations', 'default_location_id')) {
            $org = DB::table('gymies_organisations')->where('id', $orgId)->first(['default_location_id']);
            if ($org && $org->default_location_id) {
                $defaultLocationId = (string) $org->default_location_id;
            }
        }
        return response()->json([
            'data' => $data,
            'default_location_id' => $defaultLocationId,
        ]);
    }

    public function packages(string $id): JsonResponse
    {
        $trainer = DB::table('gymies_users')
            ->where('id', $id)
            ->where('role', 'trainer')
            ->first(['id']);
        if (!$trainer) {
            return response()->json(['message' => 'Trainer not found'], 404);
        }

        if (!Schema::hasTable('gymies_packages')) {
            return response()->json(['data' => []]);
        }

        $hasLessonType = Schema::hasColumn('gymies_packages', 'lesson_type');
        $hasWeeksCount = Schema::hasColumn('gymies_packages', 'weeks_count');
        $select = ['id', 'name', 'sessions_count', 'total_cents', 'valid_days'];
        if ($hasLessonType) {
            $select[] = 'lesson_type';
        }
        if ($hasWeeksCount) {
            $select[] = 'weeks_count';
        }

        $rows = DB::table('gymies_packages')
            ->where('trainer_user_id', $id)
            ->orderBy('total_cents')
            ->get($select);

        $data = $rows->map(function ($r) use ($hasLessonType, $hasWeeksCount) {
            $weeks = $hasWeeksCount
                ? (int) ($r->weeks_count ?? 1)
                : max((int) ceil(((int) ($r->valid_days ?? 7)) / 7), 1);

            return [
                'id' => (string) $r->id,
                'name' => (string) ($r->name ?? ''),
                'lesson_type' => $hasLessonType ? (string) ($r->lesson_type ?? 'solo') : 'solo',
                'sessions_count' => (int) ($r->sessions_count ?? 1),
                'weeks_count' => $weeks,
                'price_cents' => (int) ($r->total_cents ?? 0),
            ];
        })->all();

        return response()->json(['data' => $data]);
    }

    /**
     * Publiek: laatste goedgekeurde review van een trainer.
     * Retourneert 1 review of null — voor het openbare profiel.
     */
    public function latestReview(string $id): JsonResponse
    {
        if (!Schema::hasTable('gymies_reviews')) {
            return response()->json(['data' => null]);
        }

        $review = DB::table('gymies_reviews as rv')
            ->leftJoin('gymies_users as cu', 'cu.id', '=', 'rv.client_user_id')
            ->where('rv.trainer_user_id', (int) $id)
            ->where('rv.status', 'approved')
            ->orderByDesc('rv.created_at')
            ->first([
                'rv.id',
                'rv.rating',
                'rv.review_text as comment',
                'cu.display_name as client_display_name',
                'cu.avatar_url as client_avatar_url',
                'rv.created_at',
            ]);

        if (!$review) {
            return response()->json(['data' => null]);
        }

        // Privacy: alleen voornaam tonen van klant
        $clientName = $review->client_display_name ?? 'Klant';
        $parts = explode(' ', $clientName, 2);
        $firstName = $parts[0];
        $lastInitial = isset($parts[1]) ? mb_substr($parts[1], 0, 1) . '.' : '';

        return response()->json(['data' => [
            'id' => (string) $review->id,
            'rating' => (int) $review->rating,
            'comment' => $review->comment,
            'client_display_name' => trim("{$firstName} {$lastInitial}"),
            'client_avatar_url' => $review->client_avatar_url,
            'created_at' => $review->created_at,
        ]]);
    }

    public function media(string $id): JsonResponse
    {
        $trainer = DB::table('gymies_users')
            ->where('id', $id)
            ->where('role', 'trainer')
            ->first(['id']);
        if (!$trainer) {
            return response()->json(['message' => 'Trainer not found'], 404);
        }
        if (!Schema::hasTable('gymies_trainer_media')) {
            return response()->json(['data' => []]);
        }

        $rows = DB::table('gymies_trainer_media')
            ->where('trainer_user_id', $id)
            ->where('is_public', 1)
            ->orderBy('sort_order')
            ->orderByDesc('id')
            ->get();

        $data = $rows->map(function ($r) {
            $filePath = (string) ($r->file_path ?? '');
            $externalUrl = (string) ($r->external_url ?? '');
            $url = $externalUrl !== ''
                ? $externalUrl
                : ($filePath !== '' && !str_starts_with($filePath, 'http')
                    ? url($filePath)
                    : $filePath);

            return [
                'id' => (string) $r->id,
                'media_type' => (string) ($r->media_type ?? 'image'),
                'source_type' => (string) ($r->source_type ?? 'external'),
                'url' => $url,
                'thumbnail_url' => $r->thumbnail_url,
                'caption' => $r->caption,
                'is_public' => (bool) ($r->is_public ?? false),
                'sort_order' => (int) ($r->sort_order ?? 0),
            ];
        })->all();

        return response()->json(['data' => $data]);
    }

    public function me(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers hebben toegang.'], 403);
        }

        return $this->show((string) $user->id);
    }

    public function updateMe(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen hun openbare profiel wijzigen.'], 403);
        }

        $request->validate([
            'display_name' => 'nullable|string|max:255',
            'bio' => 'nullable|string|max:5000',
            'specialty' => 'nullable|string|max:255',
            'hourly_rate_cents' => 'nullable|integer|min:0|max:1000000',
            'avatar_url' => 'nullable|url|max:512',
            'region' => 'nullable|string|max:255',
            'certifications' => 'nullable|string|max:5000',
            'experience_years' => 'nullable|integer|min:0|max:80',
            'languages' => 'nullable|string|max:255',
            'min_session_minutes' => 'nullable|integer|min:15|max:240',
            'lead_time_minutes' => 'nullable|integer|min:30|max:10080',
            'booking_max_days_ahead' => 'nullable|integer|min:1|max:365',
            'trial_session_cents' => 'nullable|integer|min:0|max:1000000',
            'is_available' => 'nullable|boolean',
            'women_only' => 'nullable|boolean',
            'accepts_cash' => 'nullable|boolean',
            'accepts_online' => 'nullable|boolean',
            'spoed_inval_standby_today' => 'nullable|boolean',
        ]);

        // T-013 FIXED: expliciete whitelist via $request->only() voorkomt schema-driven mass assignment
        // Schema::getColumnListing() dient alleen als extra DB-validatie — de initiële whitelist is leidend
        $userPayload = $request->only(['display_name']);
        $userColumns = array_flip(Schema::getColumnListing('gymies_users'));
        $updateUser = [];
        foreach ($userPayload as $key => $value) {
            if (!isset($userColumns[$key])) {
                continue;
            }
            if (is_string($value)) {
                $value = trim($value);
                $value = $value === '' ? null : $value;
            }
            $updateUser[$key] = $value;
        }
        if (!empty($updateUser)) {
            DB::table('gymies_users')->where('id', $user->id)->update($updateUser);
        }

        // woman_to_woman alias voor women_only (Flutter etalage badge)
        if ($request->has('woman_to_woman') && !$request->has('women_only')) {
            $request->merge(['women_only' => $request->boolean('woman_to_woman')]);
        }

        $profilePayload = $request->only([
            'bio',
            'specialty',
            'hourly_rate_cents',
            'avatar_url',
            'region',
            'certifications',
            'experience_years',
            'languages',
            'min_session_minutes',
            'trial_session_cents',
            'is_available',
            'women_only',
            'accepts_cash',
            'accepts_online',
            'duo_surcharge_cents',
            'travel_surcharge_cents',
            'lead_time_minutes',
            'booking_max_days_ahead',
        ]);
        $profileColumns = array_flip(Schema::getColumnListing('gymies_trainer_profiles'));
        $updateProfile = [];
        foreach ($profilePayload as $key => $value) {
            if (!isset($profileColumns[$key])) {
                continue;
            }
            if (is_string($value)) {
                $value = trim($value);
                $value = $value === '' ? null : $value;
            }
            if ($key === 'is_available' && $value !== null) {
                $value = $request->boolean('is_available') ? 1 : 0;
            }
            if ($key === 'women_only' && $value !== null) {
                $value = $request->boolean('women_only') ? 1 : 0;
            }
            if ($key === 'accepts_cash' && $value !== null) {
                $value = $request->boolean('accepts_cash') ? 1 : 0;
            }
            if ($key === 'accepts_online' && $value !== null) {
                $value = $request->boolean('accepts_online') ? 1 : 0;
            }
            if ($key === 'lead_time_minutes' && $value !== null) {
                $value = (int) $value;
            }
            if ($key === 'booking_max_days_ahead') {
                // null of leeg = platformdefault (kolom NULL)
                if ($value === null || $value === '') {
                    $updateProfile[$key] = null;
                    continue;
                }
                $value = (int) $value;
                if ($value < 1) {
                    $value = 1;
                }
                if ($value > 365) {
                    $value = 365;
                }
            }
            $updateProfile[$key] = $value;
        }

        if ($request->has('spoed_inval_standby_today') && Schema::hasColumn('gymies_trainer_profiles', 'spoed_inval_standby_date')) {
            $updateProfile['spoed_inval_standby_date'] = $request->boolean('spoed_inval_standby_today')
                ? now()->format('Y-m-d')
                : null;
        }

        $existingProfile = DB::table('gymies_trainer_profiles')->where('user_id', $user->id)->first();
        if ($existingProfile) {
            if (!empty($updateProfile)) {
                $finalProfile = $updateProfile;
                if (Schema::hasColumn('gymies_trainer_profiles', 'moderation_status')) {
                    $finalProfile['moderation_status'] = 'pending_review';
                }
                DB::table('gymies_trainer_profiles')->where('user_id', $user->id)->update($finalProfile);
            }
        } else {
            $insert = array_merge([
                'user_id' => $user->id,
                'created_at' => now(),
                'updated_at' => now(),
            ], $updateProfile);
            if (Schema::hasColumn('gymies_trainer_profiles', 'moderation_status')) {
                $insert['moderation_status'] = 'pending_review';
            }
            DB::table('gymies_trainer_profiles')->insert($insert);
        }

        return $this->show((string) $user->id);
    }

    /**
     * Publiek: tot 6 trainers op basis van het IP-adres van de bezoeker (stads-niveau).
     * Geen GPS-toestemming nodig – IP-geolocation via ipapi.co (gratis, 30k/mnd).
     * Geeft city + data terug; data leeg als geen trainers gevonden of geolocation faalt.
     */
    public function landingNearby(Request $request): JsonResponse
    {
        $limit  = 6;
        $radius = 35; // km

        $ip = $request->ip();

        // Privé/lokale IP's overslaan – geen geolocation mogelijk.
        if (!filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) {
            return response()->json(['data' => [], 'city' => null]);
        }

        // S-049: IP → stad/coördinaten via ipapi.co (HTTPS, no MITM attack possible).
        try {
            $geo = \Illuminate\Support\Facades\Http::timeout(3)
                ->get("https://ipapi.co/{$ip}/json/")
                ->json();
        } catch (\Throwable $e) {
            return response()->json(['data' => [], 'city' => null]);
        }

        // S-049: Validate numeric ranges for lat/lng to prevent injection
        $lat  = isset($geo['latitude'])  ? (float) $geo['latitude']  : null;
        $lng  = isset($geo['longitude']) ? (float) $geo['longitude'] : null;

        // S-049: Valid range: -90 to 90 for latitude, -180 to 180 for longitude
        if (
            $lat === null || $lng === null ||
            $lat < -90 || $lat > 90 ||
            $lng < -180 || $lng > 180
        ) {
            return response()->json(['data' => [], 'city' => null]);
        }

        $city = isset($geo['city'])      ? trim((string) $geo['city']) : null;

        if ($lat === null || $lng === null) {
            return response()->json(['data' => [], 'city' => null]);
        }

        // Bouw dezelfde query als index() maar minimaal: alleen velden voor de landing-kaart.
        $hasProfiles = Schema::hasTable('gymies_trainer_profiles');
        $hasReviews  = Schema::hasTable('gymies_reviews');
        $hasLocations = Schema::hasTable('gymies_trainer_locations');

        // S-050: Exclude deleted/inactive trainers
        $q = DB::table('gymies_users as u')
            ->where('u.role', 'trainer');
        if (Schema::hasColumn('gymies_users', 'deleted_at')) {
            $q->whereNull('u.deleted_at');
        }
        if (Schema::hasColumn('gymies_users', 'is_active')) {
            $q->where('u.is_active', 1);
        }
        $select = ['u.id as user_id', 'u.email', 'u.display_name', 'u.email_verified_at'];

        if ($hasProfiles) {
            $q->leftJoin('gymies_trainer_profiles as p', 'u.id', '=', 'p.user_id');
            $select = array_merge($select, [
                'p.id as profile_id', 'p.bio', 'p.specialty', 'p.hourly_rate_cents',
                'p.avatar_url', 'p.region', 'p.trainer_verified_at', 'p.certifications',
                'p.experience_years', 'p.languages', 'p.min_session_minutes',
                'p.trial_session_cents', 'p.is_available',
            ]);
            if (Schema::hasColumn('gymies_trainer_profiles', 'women_only')) {
                $select[] = 'p.women_only';
            }
            if (Schema::hasColumn('gymies_trainer_profiles', 'moderation_status')) {
                $q->where(function ($sq) {
                    $sq->whereNull('p.moderation_status')->orWhere('p.moderation_status', 'approved');
                });
                $select[] = 'p.quality_score';
            }
        } else {
            $select[] = DB::raw('u.id as profile_id');
        }

        if ($hasReviews) {
            $reviews = DB::table('gymies_reviews')
                ->select('trainer_user_id', DB::raw('AVG(rating) as avg_rating'), DB::raw('COUNT(*) as review_count'))
                ->where('status', 'approved')
                ->groupBy('trainer_user_id');
            $q->leftJoinSub($reviews, 'r', fn ($j) => $j->on('u.id', '=', 'r.trainer_user_id'));
            $select[] = 'r.avg_rating';
            $select[] = 'r.review_count';
        } else {
            $select[] = DB::raw('NULL as avg_rating');
            $select[] = DB::raw('0 as review_count');
        }

        $q->select($select);

        if ($hasProfiles && Schema::hasColumn('gymies_trainer_profiles', 'quality_score')) {
            $q->orderByRaw('p.quality_score IS NULL ASC')->orderByDesc('p.quality_score')->orderBy('u.display_name');
        } else {
            $q->orderBy('u.display_name');
        }

        $trainers = $q->get();

        // Haversine afstandsberekening en filter op radius.
        if ($hasLocations && $trainers->isNotEmpty()) {
            $userLatRad = deg2rad($lat);
            $userLngRad = deg2rad($lng);
            $ids = $trainers->pluck('user_id')->map(static fn ($id) => (int) $id)->all();

            $locs = DB::table('gymies_trainer_locations')
                ->whereNotNull('latitude')
                ->whereNotNull('longitude')
                ->whereIn('trainer_user_id', $ids)
                ->orderByDesc('is_primary')
                ->get(['trainer_user_id', 'latitude', 'longitude']);

            $locByTrainer = [];
            foreach ($locs as $loc) {
                $tid = (string) $loc->trainer_user_id;
                if (!isset($locByTrainer[$tid])) {
                    $locByTrainer[$tid] = [(float) $loc->latitude, (float) $loc->longitude];
                }
            }

            $trainers = $trainers->map(function ($u) use ($locByTrainer, $userLatRad, $userLngRad) {
                $u->distance_km = null;
                $coords = $locByTrainer[(string) $u->user_id] ?? null;
                if ($coords) {
                    $latRad = deg2rad($coords[0]);
                    $lngRad = deg2rad($coords[1]);
                    $u->distance_km = 6371 * 2 * asin(sqrt(
                        pow(sin(($userLatRad - $latRad) / 2), 2) +
                        cos($userLatRad) * cos($latRad) * pow(sin(($userLngRad - $lngRad) / 2), 2)
                    ));
                }
                return $u;
            })->filter(fn ($u) => $u->distance_km !== null && $u->distance_km <= $radius)
              ->sortBy(fn ($u) => $u->distance_km)
              ->values();
        }

        if ($trainers->isEmpty()) {
            return response()->json(['data' => [], 'city' => $city]);
        }

        $data = $trainers->take($limit)->map(fn ($u) => $this->trainerToArray($u))->values()->all();

        return response()->json(['data' => $data, 'city' => $city]);
    }

    private function trainerToArray(object $u): array
    {
        $field = fn (string $name) => property_exists($u, $name) ? $u->{$name} : null;
        $emailVerified = !empty($field('email_verified_at'));
        $trainerVerified = !empty($field('trainer_verified_at'));
        $rating = $field('avg_rating') !== null ? round((float) $field('avg_rating'), 1) : null;
        $reviewCount = (int) ($field('review_count') ?? 0);
        $organisationName = $field('organisation_name');
        return [
            'id' => (string) ($field('profile_id') ?? $u->user_id),
            'user_id' => (string) $u->user_id,
            'email' => $u->email ?? '',
            'display_name' => $field('display_name') ?? $u->email ?? '',
            'bio' => $field('bio'),
            'specialty' => $field('specialty'),
            'hourly_rate_cents' => $field('hourly_rate_cents') !== null ? (int) $field('hourly_rate_cents') : null,
            'avatar_url' => $field('avatar_url'),
            'region' => $field('region'),
            'certifications' => $field('certifications'),
            'experience_years' => $field('experience_years') !== null ? (int) $field('experience_years') : null,
            'languages' => $field('languages'),
            'min_session_minutes' => $field('min_session_minutes') !== null ? (int) $field('min_session_minutes') : null,
            'trial_session_cents' => $field('trial_session_cents') !== null ? (int) $field('trial_session_cents') : null,
            'is_available' => $field('is_available') !== null ? (bool) $field('is_available') : null,
            'email_verified' => $emailVerified,
            'trainer_verified' => $trainerVerified,
            'rating' => $rating,
            'review_count' => $reviewCount,
            'response_time_label' => 'Binnen 2 uur',
            'cancellation_policy_label' => 'Gratis annuleren tot 24 uur van tevoren',
            'organisation_id' => $field('organisation_id') ? (string) $field('organisation_id') : null,
            'organisation_name' => $organisationName,
            'organisation_badge_text' => $organisationName ? ('Trainer bij ' . (string) $organisationName) : null,
            'organisation_payout_route' => $field('organisation_payout_route'),
            'is_gym_trainer' => !empty($organisationName),
            'women_only' => (bool) ($field('women_only') ?? false),
            'woman_to_woman' => (bool) ($field('women_only') ?? false),
            'duo_surcharge_cents' => $field('duo_surcharge_cents') !== null ? (int) $field('duo_surcharge_cents') : null,
            'travel_surcharge_cents' => $field('travel_surcharge_cents') !== null ? (int) $field('travel_surcharge_cents') : null,
            'is_gymies_pro' => (bool) ($field('is_gymies_pro') ?? false),
            'gymies_pro_since' => $field('gymies_pro_since'),
            'consecutive_completed' => (int) ($field('consecutive_completed') ?? 0),
            'accepts_cash' => (bool) ($field('accepts_cash') ?? false),
            'accepts_online' => (bool) ($field('accepts_online') ?? true),
            'lead_time_minutes' => $field('lead_time_minutes') !== null ? (int) $field('lead_time_minutes') : null,
            'booking_max_days_ahead' => $field('booking_max_days_ahead') !== null && $field('booking_max_days_ahead') !== ''
                ? (int) $field('booking_max_days_ahead')
                : null,
            'subscription_plan' => $field('subscription_plan'),
            'mollie_onboarding_status' => $field('mollie_onboarding_status'),
            'spoed_inval_standby_today' => $this->isStandbyToday($field('spoed_inval_standby_date')),
            'distance_km' => $field('distance_km') !== null ? round((float) $field('distance_km'), 1) : null,
        ];
    }

    private function isStandbyToday(?string $date): bool
    {
        if ($date === null || $date === '') {
            return false;
        }
        return $date === now()->format('Y-m-d');
    }
}
