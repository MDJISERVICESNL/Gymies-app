<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Http\Traits\GymiesSchemaCacheTrait;
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
    use GymiesSchemaCacheTrait;

    /** Log zoekvraag (locatie) voor demand heatmap. Publiek aanroepbaar. */
    public function logSearch(Request $request): JsonResponse
    {
        $request->validate(['location_query' => 'required|string|max:255']);
        $query = trim((string) $request->input('location_query'));
        if ($query === '') {
            return response()->json(['ok' => true]);
        }
        if (!$this->tableExists('gymies_search_log')) {
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

        if (!$this->tableExists('gymies_users') || !$this->tableExists('gymies_trainer_profiles')) {
            return response()->json(['data' => []]);
        }

        $usersQuery = DB::table('gymies_users as u')
            ->join('gymies_trainer_profiles as p', 'u.id', '=', 'p.user_id')
            ->where('u.role', 'trainer')
            ->select('u.id as user_id', 'p.region');

        if ($this->columnExists('gymies_trainer_profiles', 'moderation_status')) {
            $usersQuery->where(function ($q) {
                $q->whereNull('p.moderation_status')->orWhere('p.moderation_status', 'approved');
            });
        }

        $trainers = $usersQuery->get();
        $cityByTrainer = [];

        if ($this->tableExists('gymies_trainer_locations') && $trainers->isNotEmpty()) {
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
            \Log::error('GymiesTrainerController@index FAILED', [
                'error' => $e->getMessage(),
                'file'  => $e->getFile() . ':' . $e->getLine(),
                'trace' => array_slice($e->getTrace(), 0, 5),
            ]);
            return response()->json([
                'message' => 'Server Error',
                'debug'   => config('app.debug') ? $e->getMessage() : null,
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
        $priceMin = $request->query('price_min') !== null ? (int) $request->query('price_min') : null;
        $priceMax = $request->query('price_max') !== null ? (int) $request->query('price_max') : null;
        $experienceMin = $request->query('experience_min') !== null ? (int) $request->query('experience_min') : null;
        $availableDay = $request->query('available_day') !== null ? strtolower(trim((string) $request->query('available_day'))) : null;
        $hasGymTables = $this->tableExists('gymies_organisation_trainers') && $this->tableExists('gymies_organisations');
        $hasProfiles = $this->tableExists('gymies_trainer_profiles');
        $hasReviews = $this->tableExists('gymies_reviews');

        $usersQuery = DB::table('gymies_users as u')->where('u.role', 'trainer');

        $select = ['u.id as user_id', 'u.email', 'u.display_name', 'u.email_verified_at'];
        if ($hasProfiles) {
            $usersQuery->leftJoin('gymies_trainer_profiles as p', 'u.id', '=', 'p.user_id');
            $select = array_merge($select, [
                'p.id as profile_id', 'p.bio', 'p.specialty', 'p.hourly_rate_cents', 'p.avatar_url',
                'p.region', 'p.trainer_verified_at', 'p.certifications', 'p.experience_years',
                'p.languages', 'p.min_session_minutes', 'p.trial_session_cents', 'p.is_available',
            ]);
            if ($this->columnExists('gymies_trainer_profiles', 'women_only')) {
                $select[] = 'p.women_only';
            }
            if ($this->columnExists('gymies_trainer_profiles', 'moderation_status')) {
                $usersQuery->where(function ($q) {
                    $q->whereNull('p.moderation_status')->orWhere('p.moderation_status', 'approved');
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
            $usersQuery->leftJoinSub($reviews, 'r', fn ($join) => $join->on('u.id', '=', 'r.trainer_user_id'));
            $select[] = 'r.avg_rating';
            $select[] = 'r.review_count';
        } else {
            $select[] = DB::raw('NULL as avg_rating');
            $select[] = DB::raw('0 as review_count');
        }
        $usersQuery->select($select);

        if ($hasGymTables) {
            $usersQuery
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
        if ($hasProfiles && $womenOnly && $this->columnExists('gymies_trainer_profiles', 'women_only')) {
            $usersQuery->where('p.women_only', '=', 1);
        }

        // Move text search filtering to SQL (before ->get())
        if ($q) {
            $q = strtolower(mb_substr(trim((string) $q), 0, 255));
            $qEsc = str_replace(['%', '_', '\\'], ['\\%', '\\_', '\\\\'], $q);
            $usersQuery->where(function ($query) use ($qEsc, $hasGymTables) {
                $query->whereRaw('LOWER(u.email) LIKE ?', ['%' . $qEsc . '%'])
                    ->orWhereRaw('LOWER(u.display_name) LIKE ?', ['%' . $qEsc . '%'])
                    ->orWhereRaw('LOWER(p.specialty) LIKE ?', ['%' . $qEsc . '%'])
                    ->orWhereRaw('LOWER(p.region) LIKE ?', ['%' . $qEsc . '%']);
                if ($hasGymTables) {
                    $query->orWhereRaw('LOWER(o.name) LIKE ?', ['%' . $qEsc . '%']);
                }
            });
        }

        // Prijsfilter (in centen)
        if ($hasProfiles && $priceMin !== null) {
            $usersQuery->where('p.hourly_rate_cents', '>=', $priceMin);
        }
        if ($hasProfiles && $priceMax !== null) {
            $usersQuery->where('p.hourly_rate_cents', '<=', $priceMax);
        }
        // Ervaringsfilter (minimaal X jaar)
        if ($hasProfiles && $experienceMin !== null && $this->columnExists('gymies_trainer_profiles', 'experience_years')) {
            $usersQuery->where('p.experience_years', '>=', $experienceMin);
        }

        // Specialty exact match filtering in SQL
        if ($specialty !== null && $specialty !== '') {
            $tag = strtolower($specialty);
            $usersQuery->where(function ($query) use ($tag) {
                $query->whereRaw("LOWER(p.specialty) = ?", [$tag])
                    ->orWhereRaw("LOWER(p.specialty) LIKE ?", [$tag . ',%'])
                    ->orWhereRaw("LOWER(p.specialty) LIKE ?", ['%,' . $tag])
                    ->orWhereRaw("LOWER(p.specialty) LIKE ?", ['%,' . $tag . ',%']);
            });
        }

        // Beschikbaarheidsfilter (dag van de week)
        if ($availableDay !== null && $this->tableExists('gymies_availability_slots')) {
            $validDays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
                          'maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'];
            if (in_array($availableDay, $validDays, true)) {
                // Map Dutch days to English for DB
                $dayMap = ['maandag' => 'monday', 'dinsdag' => 'tuesday', 'woensdag' => 'wednesday',
                           'donderdag' => 'thursday', 'vrijdag' => 'friday', 'zaterdag' => 'saturday', 'zondag' => 'sunday'];
                $dbDay = $dayMap[$availableDay] ?? $availableDay;
                $usersQuery->whereExists(function ($sub) use ($dbDay) {
                    $sub->select(DB::raw(1))
                        ->from('gymies_availability_slots')
                        ->whereColumn('gymies_availability_slots.trainer_user_id', 'u.id')
                        ->where('gymies_availability_slots.weekday', $dbDay);
                });
            }
        }

        if ($hasProfiles && $this->columnExists('gymies_trainer_profiles', 'quality_score')) {
            $usersQuery->orderByRaw('p.quality_score IS NULL ASC')->orderByDesc('p.quality_score')
                ->orderByRaw('p.sort_order IS NULL ASC')->orderBy('p.sort_order')->orderBy('u.display_name');
        } else {
            $usersQuery->orderBy('u.display_name');
        }
        $users = $usersQuery->get();

        // Ambassador-data koppelen aan trainers
        $hasAmbassadors = $this->tableExists('gymies_ambassadors');
        if ($hasAmbassadors) {
            $ambByUser = DB::table('gymies_ambassadors')
                ->whereIn('user_id', $users->pluck('user_id')->filter())
                ->where('is_active', 1)
                ->get(['user_id', 'tier', 'is_founding_partner', 'is_featured'])
                ->keyBy('user_id');
            $users = $users->map(function ($u) use ($ambByUser) {
                $amb = $ambByUser->get((int) $u->user_id);
                $u->is_ambassador = $amb !== null;
                $u->is_founding_partner = $amb ? (bool) $amb->is_founding_partner : false;
                $u->ambassador_tier = $amb?->tier;
                // Ambassador boost voor ranking: elite=+20, active=+10, starter=+5
                if ($amb) {
                    $boost = match ($amb->tier) {
                        'elite' => 20,
                        'active' => 10,
                        default => 5,
                    };
                    $u->quality_score = (int) ($u->quality_score ?? 0) + $boost;
                }
                return $u;
            });
        } else {
            $users = $users->map(function ($u) {
                $u->is_ambassador = false;
                $u->is_founding_partner = false;
                $u->ambassador_tier = null;
                return $u;
            });
        }

        // Afstand berekenen + stad-eerst ranking:
        //   Tier 1: zelfde stad (≤15 km) → quality_score DESC, dan afstand
        //   Tier 2: in de buurt (15–50 km) → afstand ASC, dan quality_score DESC
        //   Tier 3: ver weg (>50 km) of geen locatie → afstand ASC
        $hasLocations = $this->tableExists('gymies_trainer_locations');
        if ($userLat !== null && $userLng !== null && $hasLocations) {
            $userLatRad = deg2rad($userLat);
            $userLngRad = deg2rad($userLng);
            $locations = DB::table('gymies_trainer_locations')
                ->whereNotNull('latitude')
                ->whereNotNull('longitude')
                ->whereIn('trainer_user_id', $users->pluck('user_id'))
                ->orderBy('is_primary', 'desc')
                ->get(['trainer_user_id', 'latitude', 'longitude', 'city']);
            $locByTrainer = [];
            foreach ($locations as $loc) {
                $tid = (string) $loc->trainer_user_id;
                if (!isset($locByTrainer[$tid])) {
                    $locByTrainer[$tid] = [
                        'lat' => (float) $loc->latitude,
                        'lng' => (float) $loc->longitude,
                        'city' => $loc->city ?? null,
                    ];
                }
            }
            $users = $users->map(function ($u) use ($locByTrainer, $userLatRad, $userLngRad) {
                $u->distance_km = null;
                $u->trainer_city = null;
                $info = $locByTrainer[(string) $u->user_id] ?? null;
                if ($info) {
                    $latRad = deg2rad($info['lat']);
                    $lngRad = deg2rad($info['lng']);
                    $earthKm = 6371;
                    $u->distance_km = round($earthKm * 2 * asin(sqrt(
                        pow(sin(($userLatRad - $latRad) / 2), 2) +
                        cos($userLatRad) * cos($latRad) * pow(sin(($userLngRad - $lngRad) / 2), 2)
                    )), 2);
                    $u->trainer_city = $info['city'];
                }
                return $u;
            });

            // Sorteer: stad-eerst, kwaliteit, afstand
            $sameCityKm = 15;
            $nearbyKm = 50;
            $users = $users->sort(function ($a, $b) use ($sameCityKm, $nearbyKm) {
                $distA = $a->distance_km ?? 999999;
                $distB = $b->distance_km ?? 999999;
                // Tier bepalen: 0 = zelfde stad, 1 = nabij, 2 = ver/onbekend
                $tierA = $distA <= $sameCityKm ? 0 : ($distA <= $nearbyKm ? 1 : 2);
                $tierB = $distB <= $sameCityKm ? 0 : ($distB <= $nearbyKm ? 1 : 2);
                if ($tierA !== $tierB) {
                    return $tierA <=> $tierB;
                }
                // Zelfde stad: quality_score DESC, dan afstand ASC
                if ($tierA === 0) {
                    $qsA = (int) ($a->quality_score ?? 0);
                    $qsB = (int) ($b->quality_score ?? 0);
                    if ($qsA !== $qsB) {
                        return $qsB <=> $qsA; // hoog naar laag
                    }
                    return $distA <=> $distB;
                }
                // Nabij / ver: afstand ASC, dan quality_score DESC als tiebreaker
                if ($distA !== $distB) {
                    return $distA <=> $distB;
                }
                return (int) ($b->quality_score ?? 0) <=> (int) ($a->quality_score ?? 0);
            })->values();
        }

        $data = $users->map(fn ($u) => $this->trainerToArray($u))->all();
        return response()->json(['data' => $data]);
    }

    public function show(string $id): JsonResponse
    {
        $hasGymTables = $this->tableExists('gymies_organisation_trainers') && $this->tableExists('gymies_organisations');
        $hasProfiles = $this->tableExists('gymies_trainer_profiles');
        $hasReviews = $this->tableExists('gymies_reviews');

        $query = DB::table('gymies_users as u')->where('u.id', $id)->where('u.role', 'trainer');

        // Add moderation_status filter to match index() method
        if ($hasProfiles && $this->columnExists('gymies_trainer_profiles', 'moderation_status')) {
            $query->leftJoin('gymies_trainer_profiles as p', 'u.id', '=', 'p.user_id');
            $query->where(function ($q) {
                $q->whereNull('p.moderation_status')->orWhere('p.moderation_status', 'approved');
            });
        }

        $select = ['u.id as user_id', 'u.email', 'u.display_name', 'u.email_verified_at'];
        if ($hasProfiles) {
            $query->leftJoin('gymies_trainer_profiles as p', 'u.id', '=', 'p.user_id');
            $profileCols = [
                'p.id as profile_id', 'p.bio', 'p.specialty', 'p.hourly_rate_cents', 'p.avatar_url',
                'p.region', 'p.trainer_verified_at', 'p.certifications', 'p.experience_years',
                'p.languages', 'p.min_session_minutes', 'p.trial_session_cents', 'p.is_available',
            ];
            if ($this->columnExists('gymies_trainer_profiles', 'women_only')) {
                $profileCols[] = 'p.women_only';
            }
            if ($this->columnExists('gymies_trainer_profiles', 'duo_surcharge_cents')) {
                $profileCols[] = 'p.duo_surcharge_cents';
            }
            if ($this->columnExists('gymies_trainer_profiles', 'travel_surcharge_cents')) {
                $profileCols[] = 'p.travel_surcharge_cents';
            }
            if ($this->columnExists('gymies_trainer_profiles', 'is_gymies_pro')) {
                $profileCols[] = 'p.is_gymies_pro';
                $profileCols[] = 'p.gymies_pro_since';
                $profileCols[] = 'p.consecutive_completed';
            }
            if ($this->columnExists('gymies_trainer_profiles', 'accepts_cash')) {
                $profileCols[] = 'p.accepts_cash';
                $profileCols[] = 'p.accepts_online';
                $profileCols[] = 'p.subscription_plan';
                $profileCols[] = 'p.mollie_onboarding_status';
            }
            if ($this->columnExists('gymies_trainer_profiles', 'spoed_inval_standby_date')) {
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

        // Ambassador-data voor show
        $u->is_ambassador = false;
        $u->is_founding_partner = false;
        $u->ambassador_tier = null;
        if ($this->tableExists('gymies_ambassadors')) {
            $amb = DB::table('gymies_ambassadors')
                ->where('user_id', (int) $u->user_id)
                ->where('is_active', 1)
                ->first(['tier', 'is_founding_partner']);
            if ($amb) {
                $u->is_ambassador = true;
                $u->is_founding_partner = (bool) $amb->is_founding_partner;
                $u->ambassador_tier = $amb->tier;
            }
        }

        $data = $this->trainerToArray($u);
        // Fee Switcher: mag publiek zodat boekflow servicekosten kan tonen (default klant betaalt).
        $data['client_pays_service_fee'] = true;
        if ($this->tableExists('gymies_trainer_bank_accounts')
            && $this->columnExists('gymies_trainer_bank_accounts', 'client_pays_service_fee')) {
            $cp = DB::table('gymies_trainer_bank_accounts')
                ->where('trainer_user_id', (int) $u->user_id)
                ->value('client_pays_service_fee');
            if ($cp !== null) {
                $data['client_pays_service_fee'] = (bool) (int) $cp;
            }
        }
        if ($this->tableExists('gymies_trainer_storefront')) {
            $sf = DB::table('gymies_trainer_storefront')
                ->where('trainer_user_id', (int) $u->user_id)
                ->first();
            if ($sf) {
                $stories = [];
                if (!empty($sf->success_stories_json)) {
                    $d = json_decode((string) $sf->success_stories_json, true);
                    if (is_array($d)) {
                        $stories = $d;
                    }
                }
                $data['storefront'] = [
                    'success_stories' => $stories,
                    'video_pitch_url' => $sf->video_pitch_url,
                    'instagram_handle' => $this->columnExists('gymies_trainer_storefront', 'instagram_handle') ? ($sf->instagram_handle ?? null) : null,
                    'specializations_display' => $sf->specializations_display,
                    'seo_title' => $sf->seo_title,
                    'seo_description' => $sf->seo_description,
                    'seo_keywords' => $sf->seo_keywords,
                ];
            }
        }
        return response()->json(['data' => $data]);
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
        if (!$this->tableExists('gymies_organisation_trainers') || !$this->tableExists('gym_locations')) {
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
        $rows = DB::table('gym_locations')
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
        if ($this->columnExists('gymies_organisations', 'default_location_id')) {
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

        if (!$this->tableExists('gymies_packages')) {
            return response()->json(['data' => []]);
        }

        $hasLessonType = $this->columnExists('gymies_packages', 'lesson_type');
        $hasWeeksCount = $this->columnExists('gymies_packages', 'weeks_count');
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

    public function media(string $id): JsonResponse
    {
        $trainer = DB::table('gymies_users')
            ->where('id', $id)
            ->where('role', 'trainer')
            ->first(['id']);
        if (!$trainer) {
            return response()->json(['message' => 'Trainer not found'], 404);
        }
        if (!$this->tableExists('gymies_trainer_media')) {
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

        if ($request->has('spoed_inval_standby_today') && $this->columnExists('gymies_trainer_profiles', 'spoed_inval_standby_date')) {
            $updateProfile['spoed_inval_standby_date'] = $request->boolean('spoed_inval_standby_today')
                ? now()->format('Y-m-d')
                : null;
        }

        $existingProfile = DB::table('gymies_trainer_profiles')->where('user_id', $user->id)->first();
        if ($existingProfile) {
            if (!empty($updateProfile)) {
                $finalProfile = $updateProfile;
                if ($this->columnExists('gymies_trainer_profiles', 'moderation_status')) {
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
            if ($this->columnExists('gymies_trainer_profiles', 'moderation_status')) {
                $insert['moderation_status'] = 'pending_review';
            }
            DB::table('gymies_trainer_profiles')->insert($insert);
        }

        return $this->show((string) $user->id);
    }

    private function getCancellationPolicyLabel(int $trainerUserId): string
    {
        if (!$this->tableExists('gymies_cancellation_policies')) {
            return 'Gratis annuleren tot 24 uur van tevoren';
        }
        $topPolicy = DB::table('gymies_cancellation_policies')
            ->where('trainer_user_id', $trainerUserId)
            ->orderBy('hours_before', 'desc')
            ->first();
        if (!$topPolicy) {
            return 'Gratis annuleren tot 24 uur van tevoren';
        }
        $hours = (int) $topPolicy->hours_before;
        $pct = (int) $topPolicy->refund_percent;
        if ($pct >= 100) {
            return "Gratis annuleren tot {$hours} uur van tevoren";
        }
        if ($pct > 0) {
            return "Tot {$hours} uur van tevoren: {$pct}% restitutie";
        }
        return "Annuleren tot {$hours} uur van tevoren: geen restitutie";
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
            'cancellation_policy_label' => $this->getCancellationPolicyLabel((int) $u->user_id),
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
            'trainer_city' => $field('trainer_city'),
            'is_ambassador' => (bool) ($field('is_ambassador') ?? false),
            'is_founding_partner' => (bool) ($field('is_founding_partner') ?? false),
            'ambassador_tier' => $field('ambassador_tier'),
        ];
    }

    private function isStandbyToday(?string $date): bool
    {
        if ($date === null || $date === '') {
            return false;
        }
        return $date === now()->format('Y-m-d');
    }

    // ─── Trainer Slug ────────────────────────────────────────────

    /**
     * GET trainers/by-slug/{slug}
     * Resolve trainer by profile_slug and redirect to trainers/{id}.
     */
    public function showBySlug(Request $request, string $slug): \Illuminate\Http\RedirectResponse
    {
        $slug = trim($slug);
        if ($slug === '') {
            abort(404);
        }
        if (!$this->tableExists('gymies_trainer_profiles')
            || !$this->columnExists('gymies_trainer_profiles', 'profile_slug')) {
            abort(404);
        }
        $profile = DB::table('gymies_trainer_profiles')
            ->where('profile_slug', $slug)
            ->first();
        if (!$profile || !($profile->user_id ?? null)) {
            abort(404);
        }
        $userId = (int) $profile->user_id;
        try {
            $url = route('api.gymies.trainers.show', ['id' => $userId], true);
            return redirect($url, 302);
        } catch (\Throwable $e) {
            $base = $request->getSchemeAndHttpHost() . ($request->getBaseUrl() ?: '');
            return redirect(rtrim($base, '/') . '/api/gymies/trainers/' . $userId, 302);
        }
    }

    // ─── Trainer Reviews ─────────────────────────────────────────

    /**
     * GET trainers/{id}/reviews – publieke lijst van reviews voor een trainer.
     */
    public function reviews(Request $request, string $id): JsonResponse
    {
        $trainerId = (int) $id;
        if ($trainerId <= 0) {
            return response()->json(['data' => [], 'rating_avg' => null, 'count' => 0], 200);
        }
        $table = 'gymies_booking_reviews';
        if (!$this->tableExists($table)) {
            return response()->json(['data' => [], 'rating_avg' => null, 'count' => 0], 200);
        }
        $reviews = DB::table($table)
            ->where('trainer_user_id', $trainerId)
            ->orderByDesc('created_at')
            ->get()
            ->map(function ($row) {
                $clientName = ($row->is_anonymous ?? false) ? 'Anoniem' : null;
                if ($clientName === null) {
                    $clientName = $this->resolveReviewClientName((int) ($row->client_user_id ?? 0));
                }
                return [
                    'id' => $row->id,
                    'rating' => (int) ($row->rating ?? 0),
                    'message' => $row->message ? (string) $row->message : null,
                    'is_anonymous' => (bool) ($row->is_anonymous ?? false),
                    'client_name' => $clientName,
                    'created_at' => $row->created_at ? (\Carbon\Carbon::parse($row->created_at)->toIso8601String()) : null,
                ];
            })
            ->values()
            ->all();
        $avg = DB::table($table)->where('trainer_user_id', $trainerId)->avg('rating');
        return response()->json([
            'data' => $reviews,
            'rating_avg' => $avg !== null ? round((float) $avg, 1) : null,
            'count' => count($reviews),
        ]);
    }

    private function resolveReviewClientName(int $userId): string
    {
        if ($userId <= 0) return 'Anoniem';
        $usersTable = $this->tableExists('gymies_users') ? 'gymies_users' : 'users';
        $user = DB::table($usersTable)->where('id', $userId)->first();
        if (!$user) return 'Anoniem';
        $name = trim((string) ($user->display_name ?? $user->first_name ?? $user->name ?? ''));
        if ($name !== '') return explode(' ', $name)[0] ?? $name;
        $email = trim($user->email ?? '');
        if ($email !== '') {
            $part = explode('@', $email)[0] ?? '';
            return $part !== '' ? $part : 'Anoniem';
        }
        return 'Anoniem';
    }

    // ─── Trainer Documents ───────────────────────────────────────

    private const DOC_ALLOWED_KEYS = [
        'company_name', 'companyName', 'kvk_number', 'kvk', 'vat_number', 'vat',
        'trainer_address_line1', 'address_line1', 'address', 'trainer_postcode', 'postcode',
        'trainer_city', 'city', 'trainer_country', 'country', 'country_code',
        'vog_url', 'vog_document_url', 'diploma_urls', 'diploma_url',
    ];

    public function documentsIndex(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }
        $docs = $this->loadTrainerDocuments((int) $user->id);
        return response()->json(['data' => $docs]);
    }

    public function documentsUpdate(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }
        $body = $request->all();
        $flat = [];
        foreach (['documents', 'company', 'company_profile', 'companyProfile'] as $key) {
            if (isset($body[$key]) && is_array($body[$key])) {
                $flat = array_merge($flat, $body[$key]);
            }
        }
        $flat = array_merge($body, $flat);
        $update = [];
        $company = $flat['company_name'] ?? $flat['companyName'] ?? null;
        if (is_string($company)) $update['company_name'] = trim($company);
        $kvk = $flat['kvk_number'] ?? $flat['kvk'] ?? null;
        if (is_string($kvk)) $update['kvk_number'] = trim($kvk);
        $vat = $flat['vat_number'] ?? $flat['vat'] ?? null;
        if (is_string($vat)) $update['vat_number'] = trim($vat);
        $addr = $flat['trainer_address_line1'] ?? $flat['address_line1'] ?? $flat['address'] ?? null;
        if (is_string($addr)) $update['trainer_address_line1'] = trim($addr);
        $postcode = $flat['trainer_postcode'] ?? $flat['postcode'] ?? null;
        if (is_string($postcode)) $update['trainer_postcode'] = trim($postcode);
        $city = $flat['trainer_city'] ?? $flat['city'] ?? null;
        if (is_string($city)) $update['trainer_city'] = trim($city);
        $country = $flat['trainer_country'] ?? $flat['country'] ?? $flat['country_code'] ?? null;
        if (is_string($country)) $update['trainer_country'] = trim($country);
        $vog = $flat['vog_url'] ?? $flat['vog_document_url'] ?? null;
        if (is_string($vog)) $update['vog_url'] = trim($vog);
        $diplomas = $flat['diploma_urls'] ?? $flat['diploma_url'] ?? null;
        if (is_array($diplomas)) {
            $update['diploma_urls'] = array_values(array_map('strval', array_filter($diplomas)));
        } elseif (is_string($diplomas) && trim($diplomas) !== '') {
            $update['diploma_urls'] = array_values(array_filter(array_map('trim', explode("\n", $diplomas))));
        }
        if (empty($update)) {
            return response()->json(['data' => $this->loadTrainerDocuments((int) $user->id)]);
        }
        if (!$this->tableExists('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Trainer-documenten tabel ontbreekt.'], 500);
        }
        $existingColumns = Schema::getColumnListing('gymies_trainer_profiles');
        $allowedUpdate = [];
        foreach ($update as $col => $value) {
            if (in_array($col, $existingColumns, true)) $allowedUpdate[$col] = $value;
        }
        if (isset($allowedUpdate['diploma_urls']) && is_array($allowedUpdate['diploma_urls'])) {
            $allowedUpdate['diploma_urls'] = json_encode($allowedUpdate['diploma_urls']);
        }
        $allowedUpdate['updated_at'] = now();
        $profile = DB::table('gymies_trainer_profiles')->where('user_id', (int) $user->id)->first();
        if ($profile) {
            DB::table('gymies_trainer_profiles')->where('user_id', (int) $user->id)->update($allowedUpdate);
        } else {
            $allowedUpdate['user_id'] = (int) $user->id;
            $allowedUpdate['created_at'] = now();
            DB::table('gymies_trainer_profiles')->insert($allowedUpdate);
        }
        return response()->json(['data' => $this->loadTrainerDocuments((int) $user->id)]);
    }

    private function loadTrainerDocuments(int $userId): array
    {
        if (!$this->tableExists('gymies_trainer_profiles')) return [];
        $profile = DB::table('gymies_trainer_profiles')->where('user_id', $userId)->first();
        if (!$profile) return [];
        $row = (array) $profile;
        $docs = [];
        $map = [
            'company_name' => ['company_name', 'companyName'],
            'kvk_number' => ['kvk_number', 'kvk'],
            'vat_number' => ['vat_number', 'vat'],
            'trainer_address_line1' => ['trainer_address_line1', 'address_line1', 'address'],
            'trainer_postcode' => ['trainer_postcode', 'postcode'],
            'trainer_city' => ['trainer_city', 'city'],
            'trainer_country' => ['trainer_country', 'country', 'country_code'],
            'vog_url' => ['vog_url', 'vog_document_url'],
            'diploma_urls' => ['diploma_urls', 'diploma_url'],
        ];
        foreach ($map as $canonical => $aliases) {
            $value = null;
            foreach (array_merge([$canonical], $aliases) as $key) {
                if (isset($row[$key]) && $row[$key] !== null && $row[$key] !== '') { $value = $row[$key]; break; }
            }
            if ($value !== null) {
                if ($canonical === 'diploma_urls' && is_string($value)) {
                    $decoded = json_decode($value, true);
                    $docs['diploma_urls'] = is_array($decoded) ? $decoded : [$value];
                } else {
                    $docs[$canonical] = $value;
                    foreach ($aliases as $a) { if ($a !== $canonical) $docs[$a] = $value; }
                }
            }
        }
        if (isset($docs['diploma_urls']) && !isset($docs['diploma_url'])) {
            $d = $docs['diploma_urls'];
            $docs['diploma_url'] = is_array($d) ? ($d[0] ?? null) : $d;
        }
        return $docs;
    }

    // ─── Trainer Client Payments ─────────────────────────────────

    /**
     * GET trainer/clients/{clientUserId}/payments
     */
    public function clientPayments(Request $request, string $clientUserId): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }
        $trainerUserId = (int) $trainer->id;
        $bookingsTable = $this->resolvePaymentsBookingsTable();
        if (!$bookingsTable) return response()->json(['data' => []], 200);
        $trainerCol = $this->resolvePaymentsTrainerColumn($bookingsTable);
        $clientCol = $this->resolvePaymentsClientColumn($bookingsTable);
        $paidAtCol = $this->resolvePaymentsPaidAtColumn($bookingsTable);
        $amountCol = $this->resolvePaymentsAmountColumn($bookingsTable);
        $scheduledCol = $this->resolvePaymentsScheduledColumn($bookingsTable);
        if (!$trainerCol || !$clientCol) return response()->json(['data' => []], 200);
        $query = DB::table($bookingsTable)
            ->where($trainerCol, $trainerUserId)
            ->where($clientCol, $clientUserId);
        if ($paidAtCol && $this->columnExists($bookingsTable, $paidAtCol)) {
            $query->whereNotNull($paidAtCol);
        }
        $rows = $query->orderByDesc($scheduledCol ?? $paidAtCol ?? 'id')->limit(100)->get();
        $payments = [];
        foreach ($rows as $row) {
            $rowArr = (array) $row;
            $id = $rowArr['id'] ?? $rowArr['booking_id'] ?? null;
            $amountCents = (int) ($rowArr[$amountCol] ?? $rowArr['amount_cents'] ?? $rowArr['amountCents'] ?? 0);
            $paidAt = $rowArr[$paidAtCol] ?? $rowArr['paid_at'] ?? $rowArr['paidAt'] ?? null;
            $scheduledAt = $rowArr[$scheduledCol] ?? $rowArr['scheduled_at'] ?? $rowArr['scheduledAt'] ?? $paidAt;
            $payments[] = [
                'booking_id' => (string) $id,
                'amount_cents' => $amountCents,
                'currency' => 'EUR',
                'status' => 'paid',
                'paid_at' => $paidAt ? date('c', strtotime($paidAt)) : null,
                'session_date' => $scheduledAt ? date('Y-m-d', strtotime($scheduledAt)) : null,
                'reference_id' => $rowArr['mollie_payment_id'] ?? $rowArr['reference_id'] ?? null,
            ];
        }
        return response()->json(['data' => $payments]);
    }

    private function resolvePaymentsBookingsTable(): ?string
    {
        foreach (['gymies_bookings', 'bookings'] as $t) { if ($this->tableExists($t)) return $t; }
        return null;
    }
    private function resolvePaymentsTrainerColumn(string $table): ?string
    {
        foreach (['trainer_user_id', 'trainer_id', 'trainerUserId', 'trainerId'] as $c) { if ($this->columnExists($table, $c)) return $c; }
        return null;
    }
    private function resolvePaymentsClientColumn(string $table): ?string
    {
        foreach (['client_user_id', 'client_id', 'user_id', 'clientUserId', 'clientId'] as $c) { if ($this->columnExists($table, $c)) return $c; }
        return null;
    }
    private function resolvePaymentsPaidAtColumn(string $table): ?string
    {
        foreach (['paid_at', 'paidAt', 'payment_date'] as $c) { if ($this->columnExists($table, $c)) return $c; }
        return null;
    }
    private function resolvePaymentsAmountColumn(string $table): ?string
    {
        foreach (['amount_cents', 'amountCents', 'amount'] as $c) { if ($this->columnExists($table, $c)) return $c; }
        return null;
    }
    private function resolvePaymentsScheduledColumn(string $table): ?string
    {
        foreach (['scheduled_at', 'scheduledAt', 'session_at', 'date', 'created_at'] as $c) { if ($this->columnExists($table, $c)) return $c; }
        return null;
    }

    // ─── Trainer Locations ───────────────────────────────────────

    public function locationIndex(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || ($user->role ?? '') !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }
        if (!$this->tableExists('gymies_trainer_locations')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_trainer_locations')
            ->where('trainer_user_id', $user->id)
            ->orderByDesc('is_primary')
            ->orderBy('name')
            ->get();
        $data = $rows->map(fn ($r) => self::formatLocationRow($r))->all();
        return response()->json(['data' => $data]);
    }

    public function locationStore(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || ($user->role ?? '') !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }
        if (!$this->tableExists('gymies_trainer_locations')) {
            return response()->json(['error' => 'Table not available'], 500);
        }
        $request->validate([
            'name' => 'required|string|max:255',
            'address_line1' => 'nullable|string|max:255',
            'postcode' => 'nullable|string|max:20',
            'city' => 'nullable|string|max:255',
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'location_type' => 'nullable|in:gym,home,outdoor,online',
            'is_primary' => 'nullable|boolean',
        ]);
        $isPrimary = (bool) $request->input('is_primary', false);
        if ($isPrimary) {
            DB::table('gymies_trainer_locations')->where('trainer_user_id', $user->id)->update(['is_primary' => false]);
        }
        $id = DB::table('gymies_trainer_locations')->insertGetId([
            'trainer_user_id' => $user->id,
            'name' => $request->input('name'),
            'address_line1' => $request->input('address_line1'),
            'postcode' => $request->input('postcode'),
            'city' => $request->input('city'),
            'latitude' => $request->input('latitude'),
            'longitude' => $request->input('longitude'),
            'location_type' => $request->input('location_type', 'gym'),
            'is_primary' => $isPrimary ? 1 : 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $row = DB::table('gymies_trainer_locations')->where('id', $id)->first();
        return response()->json(['data' => self::formatLocationRow($row)], 201);
    }

    public function locationUpdate(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || ($user->role ?? '') !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }
        $row = DB::table('gymies_trainer_locations')->where('id', $id)->where('trainer_user_id', $user->id)->first();
        if (!$row) return response()->json(['error' => 'Not found'], 404);
        $request->validate([
            'name' => 'sometimes|required|string|max:255',
            'address_line1' => 'nullable|string|max:255',
            'postcode' => 'nullable|string|max:20',
            'city' => 'nullable|string|max:255',
            'latitude' => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'location_type' => 'nullable|in:gym,home,outdoor,online',
            'is_primary' => 'nullable|boolean',
        ]);
        $updates = array_filter($request->only(['name', 'address_line1', 'postcode', 'city', 'latitude', 'longitude', 'location_type']), fn ($v) => $v !== null);
        if ($request->has('is_primary') && $request->boolean('is_primary')) {
            DB::table('gymies_trainer_locations')->where('trainer_user_id', $user->id)->where('id', '!=', $id)->update(['is_primary' => false]);
            $updates['is_primary'] = true;
        } elseif ($request->has('is_primary')) {
            $updates['is_primary'] = false;
        }
        $updates['updated_at'] = now();
        DB::table('gymies_trainer_locations')->where('id', $id)->update($updates);
        $updated = DB::table('gymies_trainer_locations')->where('id', $id)->first();
        return response()->json(['data' => self::formatLocationRow($updated)]);
    }

    public function locationDestroy(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || ($user->role ?? '') !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }
        $deleted = DB::table('gymies_trainer_locations')->where('id', $id)->where('trainer_user_id', $user->id)->delete();
        if (!$deleted) return response()->json(['error' => 'Not found'], 404);
        return response()->json(['message' => 'Deleted']);
    }

    private static function formatLocationRow(object $r): array
    {
        return [
            'id' => (string) $r->id,
            'trainer_user_id' => (string) $r->trainer_user_id,
            'name' => (string) $r->name,
            'address_line1' => $r->address_line1,
            'postcode' => $r->postcode,
            'city' => $r->city,
            'latitude' => $r->latitude !== null ? (float) $r->latitude : null,
            'longitude' => $r->longitude !== null ? (float) $r->longitude : null,
            'location_type' => (string) ($r->location_type ?? 'gym'),
            'is_primary' => (bool) $r->is_primary,
            'created_at' => $r->created_at,
            'updated_at' => $r->updated_at,
        ];
    }

    public function trainerSettings(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['trainer'], true)) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }
        $settings = [];
        if ($this->tableExists('gymies_trainer_profiles')) {
            $profile = DB::table('gymies_trainer_profiles')->where('user_id', $user->id)->first();
            if ($profile) {
                $settings = array_filter((array) $profile, fn($k) => !in_array($k, ['id', 'user_id', 'created_at', 'updated_at'], true), ARRAY_FILTER_USE_KEY);
            }
        }
        return response()->json(['data' => $settings]);
    }

    public function updateTrainerSettings(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['trainer'], true)) {
            return response()->json(['message' => 'Unauthorized'], 403);
        }
        $data = $request->except(['id', 'user_id', 'created_at', 'updated_at']);
        if (empty($data)) {
            return response()->json(['message' => 'Geen wijzigingen opgegeven.'], 422);
        }
        if ($this->tableExists('gymies_trainer_profiles')) {
            $data['updated_at'] = now();
            DB::table('gymies_trainer_profiles')->where('user_id', $user->id)->update($data);
        }
        return $this->trainerSettings($request);
    }
}
