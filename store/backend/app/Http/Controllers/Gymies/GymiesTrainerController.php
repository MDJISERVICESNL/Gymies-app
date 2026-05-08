<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * Publieke trainer-endpoints en trainer/me.
 * GET trainers – index (zoek/filter)
 * GET trainers/{id} – trainer profiel (publiek)
 * GET trainer/me – eigen profiel (beveiligd)
 * PUT/POST trainer/me – eigen profiel bijwerken
 */
class GymiesTrainerController
{
    public function index(Request $request): JsonResponse
    {
        try {
            $trainers = $this->loadTrainers($request);
            return response()->json(['data' => $trainers]);
        } catch (\Throwable $e) {
            Log::error('GymiesTrainerController@index FAILED', [
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

    public function show(Request $request, string $id): JsonResponse
    {
        try {
            $trainerId = (int) $id;
            if ($trainerId <= 0) {
                return response()->json(['message' => 'Trainer niet gevonden.'], 404);
            }

            $trainer = $this->loadTrainerById($trainerId);
            if (!$trainer) {
                return response()->json(['message' => 'Trainer niet gevonden.'], 404);
            }

            return response()->json($trainer);
        } catch (\Throwable $e) {
            Log::error('GymiesTrainerController@show FAILED', [
                'id'    => $id,
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

    public function me(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainer = $this->loadTrainerById((int) $user->id);
        if (!$trainer) {
            $trainer = $this->buildMinimalTrainerFromUser($user);
        }

        return response()->json(['data' => $trainer]);
    }

    public function updateMe(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $body = $request->all();
        $update = [];

        if (isset($body['display_name']) && is_string($body['display_name'])) {
            $update['display_name'] = trim($body['display_name']);
        }
        if (isset($body['specialty']) && is_string($body['specialty'])) {
            $update['specialty'] = trim($body['specialty']);
        }
        if (isset($body['region']) && is_string($body['region'])) {
            $update['region'] = trim($body['region']);
        }
        if (isset($body['bio']) && is_string($body['bio'])) {
            $update['bio'] = trim($body['bio']);
        }
        if (array_key_exists('hourly_rate_cents', $body) && is_numeric($body['hourly_rate_cents'])) {
            $update['hourly_rate_cents'] = (int) $body['hourly_rate_cents'];
        }
        if (isset($body['profile_slug']) && is_string($body['profile_slug'])) {
            $update['profile_slug'] = trim($body['profile_slug']) ?: null;
        }
        if (isset($body['visible_badges']) && is_array($body['visible_badges'])) {
            // Max 6 toggleable badges (always-visible badges worden niet meegeteld)
            $badges = array_values(array_slice($body['visible_badges'], 0, 6));
            $update['visible_badges'] = json_encode($badges);
        }

        if (!empty($update) && Schema::hasTable('gymies_trainer_profiles')) {
            $existingColumns = Schema::getColumnListing('gymies_trainer_profiles');
            $allowedUpdate = [];
            foreach ($update as $col => $value) {
                if (in_array($col, $existingColumns, true)) {
                    $allowedUpdate[$col] = $value;
                }
            }
            if (!empty($allowedUpdate)) {
                $allowedUpdate['updated_at'] = now();
                $profile = DB::table('gymies_trainer_profiles')->where('user_id', (int) $user->id)->first();
                if ($profile) {
                    DB::table('gymies_trainer_profiles')
                        ->where('user_id', (int) $user->id)
                        ->update($allowedUpdate);
                } else {
                    $allowedUpdate['user_id'] = (int) $user->id;
                    $allowedUpdate['created_at'] = now();
                    DB::table('gymies_trainer_profiles')->insert($allowedUpdate);
                }
            }
        }

        $trainer = $this->loadTrainerById((int) $user->id);
        if (!$trainer) {
            $trainer = $this->buildMinimalTrainerFromUser($user);
        }

        return response()->json(['data' => $trainer]);
    }

    public function logSearch(Request $request): JsonResponse
    {
        return response()->json(['ok' => true]);
    }

    public function packages(Request $request, string $id): JsonResponse
    {
        $trainerId = (int) $id;
        if ($trainerId <= 0) {
            return response()->json(['data' => []]);
        }

        $packages = $this->loadPackages($trainerId);
        return response()->json(['data' => $packages]);
    }

    public function media(Request $request, string $id): JsonResponse
    {
        $trainerId = (int) $id;
        if ($trainerId <= 0) {
            return response()->json(['data' => [], 'media' => []]);
        }

        $media = $this->loadMedia($trainerId);
        return response()->json(['data' => $media, 'media' => $media]);
    }

    /**
     * GET trainers/{id}/stories — Publiek: actieve stories (niet verlopen).
     */
    public function stories(Request $request, string $id): JsonResponse
    {
        $trainerId = (int) $id;
        if ($trainerId <= 0) {
            return response()->json(['stories' => [], 'data' => []]);
        }

        GymiesSchemaEnsure::trainerMediaStoryColumns();

        if (!Schema::hasTable('gymies_trainer_media')) {
            return response()->json(['stories' => [], 'data' => []]);
        }

        $userIdCol = Schema::hasColumn('gymies_trainer_media', 'trainer_user_id')
            ? 'trainer_user_id'
            : 'user_id';

        $query = DB::table('gymies_trainer_media')
            ->where($userIdCol, $trainerId)
            ->where('usage', 'story')
            ->where(function ($q) {
                $q->whereNull('expires_at')
                  ->orWhere('expires_at', '>', now());
            })
            ->orderByDesc('created_at')
            ->limit(200);

        $rows = $query->get();

        $stories = $rows->map(function ($row) {
            $filePath = (string) ($row->file_path ?? '');
            $externalUrl = (string) ($row->external_url ?? '');
            $url = $externalUrl !== '' ? $externalUrl : $filePath;
            if ($filePath !== '' && !str_starts_with($filePath, 'http')) {
                $url = url($filePath);
            }
            return [
                'id' => (string) $row->id,
                'media_type' => (string) ($row->media_type ?? 'image'),
                'type' => (string) ($row->media_type ?? 'image'),
                'url' => $url,
                'thumbnail_url' => $row->thumbnail_url ?? null,
                'caption' => $row->caption ?? null,
                'usage' => 'story',
                'created_at' => $row->created_at ?? null,
                'expires_at' => $row->expires_at ?? null,
            ];
        })->all();

        return response()->json(['stories' => $stories, 'data' => $stories]);
    }

    /**
     * GET trainers/{id}/has-stories — Publiek: heeft trainer actieve stories?
     */
    public function hasStories(Request $request, string $id): JsonResponse
    {
        $trainerId = (int) $id;
        if ($trainerId <= 0) {
            return response()->json(['has_stories' => false]);
        }

        GymiesSchemaEnsure::trainerMediaStoryColumns();

        if (!Schema::hasTable('gymies_trainer_media') || !Schema::hasColumn('gymies_trainer_media', 'usage')) {
            return response()->json(['has_stories' => false]);
        }

        $userIdCol = Schema::hasColumn('gymies_trainer_media', 'trainer_user_id')
            ? 'trainer_user_id'
            : 'user_id';

        $exists = DB::table('gymies_trainer_media')
            ->where($userIdCol, $trainerId)
            ->where('usage', 'story')
            ->where(function ($q) {
                $q->whereNull('expires_at')
                  ->orWhere('expires_at', '>', now());
            })
            ->exists();

        return response()->json(['has_stories' => $exists]);
    }

    private function usersTable(): ?string
    {
        foreach (['gymies_users', 'users'] as $t) {
            if (Schema::hasTable($t)) {
                return $t;
            }
        }
        return null;
    }

    private function loadTrainers(Request $request): array
    {
        $usersTable = $this->usersTable();
        if (!$usersTable || !Schema::hasTable('gymies_trainer_profiles')) {
            return [];
        }

        $userCols = Schema::getColumnListing($usersTable);
        $profileCols = Schema::getColumnListing('gymies_trainer_profiles');

        $nameCol = 'id';
        foreach (['display_name', 'name', 'full_name', 'first_name'] as $try) {
            if (in_array($try, $userCols)) { $nameCol = $try; break; }
        }

        $query = DB::table('gymies_trainer_profiles')
            ->join($usersTable, "{$usersTable}.id", '=', 'gymies_trainer_profiles.user_id');

        $searchQuery = $request->input('query');
        if (is_string($searchQuery) && trim($searchQuery) !== '') {
            $term = '%' . trim($searchQuery) . '%';
            $query->where(function ($q) use ($usersTable, $profileCols, $nameCol, $term) {
                $q->where("{$usersTable}.{$nameCol}", 'like', $term)
                    ->orWhere("{$usersTable}.email", 'like', $term);
                if (in_array('specialty', $profileCols)) $q->orWhere('gymies_trainer_profiles.specialty', 'like', $term);
                if (in_array('city', $profileCols))      $q->orWhere('gymies_trainer_profiles.city', 'like', $term);
                if (in_array('region', $profileCols))    $q->orWhere('gymies_trainer_profiles.region', 'like', $term);
                if (in_array('bio', $profileCols))       $q->orWhere('gymies_trainer_profiles.bio', 'like', $term);
            });
        }

        // Add pagination parameters
        $limit = min(100, max(1, (int) ($request->query('limit') ?? 50)));
        $offset = max(0, (int) ($request->query('offset') ?? 0));

        $lat = $request->has('lat') ? $this->parseFloat($request->input('lat')) : null;
        $lng = $request->has('lng') ? $this->parseFloat($request->input('lng')) : null;
        $hasCoords = $lat !== null && $lng !== null;
        $maxDistanceKm = $this->parseFloat($request->input('radius_km')) ?? 50.0;

        // ── Optimalisatie: gebruik MySQL ST_Distance_Sphere wanneer mogelijk ──
        $hasLatCol = in_array('trainer_lat', $profileCols) || in_array('lat', $profileCols);
        $hasLngCol = in_array('trainer_lng', $profileCols) || in_array('lng', $profileCols);
        $latCol = in_array('trainer_lat', $profileCols) ? 'gymies_trainer_profiles.trainer_lat' : 'gymies_trainer_profiles.lat';
        $lngCol = in_array('trainer_lng', $profileCols) ? 'gymies_trainer_profiles.trainer_lng' : 'gymies_trainer_profiles.lng';

        if ($hasCoords && $hasLatCol && $hasLngCol) {
            // DB-niveau afstandsberekening: filter + sorteer op afstand
            $distanceExpr = "ST_Distance_Sphere(POINT({$lngCol}, {$latCol}), POINT(?, ?))";
            $maxDistanceMeters = $maxDistanceKm * 1000;

            $query->selectRaw("{$usersTable}.*, gymies_trainer_profiles.*, {$distanceExpr} AS distance_meters", [$lng, $lat]);

            // Filter: alleen trainers MET coördinaten en binnen radius
            $queryWithCoords = (clone $query)
                ->whereNotNull($latCol)
                ->whereNotNull($lngCol)
                ->where($latCol, '!=', 0)
                ->where($lngCol, '!=', 0)
                ->whereRaw("{$distanceExpr} <= ?", [$lng, $lat, $maxDistanceMeters])
                ->orderByRaw("{$distanceExpr} ASC", [$lng, $lat]);

            $profilesWithCoords = $queryWithCoords->limit($limit)->offset($offset)->get();

            // Trainers zonder coördinaten: vallen terug op city lookup
            $queryWithoutCoords = (clone $query)
                ->where(function ($q) use ($latCol, $lngCol) {
                    $q->whereNull($latCol)
                      ->orWhereNull($lngCol)
                      ->orWhere($latCol, 0)
                      ->orWhere($lngCol, 0);
                });
            // Reset selectRaw voor de without-coords query
            $queryWithoutCoords = DB::table('gymies_trainer_profiles')
                ->join($usersTable, "{$usersTable}.id", '=', 'gymies_trainer_profiles.user_id')
                ->select("{$usersTable}.*", 'gymies_trainer_profiles.*')
                ->where(function ($q) use ($latCol, $lngCol) {
                    $q->whereNull($latCol)
                      ->orWhereNull($lngCol)
                      ->orWhere($latCol, 0)
                      ->orWhere($lngCol, 0);
                });

            // Pas dezelfde search filter toe
            $searchQuery = $request->input('query');
            if (is_string($searchQuery) && trim($searchQuery) !== '') {
                $term = '%' . trim($searchQuery) . '%';
                $queryWithoutCoords->where(function ($q) use ($usersTable, $profileCols, $nameCol, $term) {
                    $q->where("{$usersTable}.{$nameCol}", 'like', $term)
                        ->orWhere("{$usersTable}.email", 'like', $term);
                    if (in_array('specialty', $profileCols)) $q->orWhere('gymies_trainer_profiles.specialty', 'like', $term);
                    if (in_array('city', $profileCols))      $q->orWhere('gymies_trainer_profiles.city', 'like', $term);
                    if (in_array('region', $profileCols))    $q->orWhere('gymies_trainer_profiles.region', 'like', $term);
                    if (in_array('bio', $profileCols))       $q->orWhere('gymies_trainer_profiles.bio', 'like', $term);
                });
            }

            $profilesWithoutCoords = $queryWithoutCoords->get();

            $trainers = [];

            // Verwerk trainers met DB-berekende afstand
            foreach ($profilesWithCoords as $row) {
                $trainer = $this->rowToTrainer($row);
                $trainer['distance_km'] = round(($row->distance_meters ?? 0) / 1000, 2);
                $trainers[] = $trainer;
            }

            // Verwerk trainers zonder coördinaten: PHP city fallback
            foreach ($profilesWithoutCoords as $row) {
                $trainer = $this->rowToTrainer($row);
                $city = $row->city ?? $row->region ?? null;
                if (is_string($city) && trim($city) !== '') {
                    $coords = $this->cityCoords(trim($city));
                    if ($coords !== null) {
                        $trainer['distance_km'] = $this->haversineKm($lat, $lng, $coords[0], $coords[1]);
                    }
                }
                $trainers[] = $trainer;
            }

            return $trainers;
        }

        // ── Fallback: geen coördinaten of geen lat/lng kolommen → originele PHP-logica ──
        $profiles = $query->select("{$usersTable}.*", 'gymies_trainer_profiles.*')->limit($limit)->offset($offset)->get();

        $trainers = [];
        foreach ($profiles as $row) {
            $trainer = $this->rowToTrainer($row);
            if ($hasCoords) {
                $trainerLat = null;
                $trainerLng = null;
                if ($this->hasTrainerCoords($row)) {
                    $trainerLat = (float) ($row->trainer_lat ?? $row->lat ?? 0);
                    $trainerLng = (float) ($row->trainer_lng ?? $row->lng ?? 0);
                } else {
                    $city = $row->city ?? $row->region ?? null;
                    if (is_string($city) && trim($city) !== '') {
                        $coords = $this->cityCoords(trim($city));
                        if ($coords !== null) {
                            $trainerLat = $coords[0];
                            $trainerLng = $coords[1];
                        }
                    }
                }
                if ($trainerLat !== null && $trainerLng !== null) {
                    $trainer['distance_km'] = $this->haversineKm($lat, $lng, $trainerLat, $trainerLng);
                }
            }
            $trainers[] = $trainer;
        }

        return $trainers;
    }

    private const CITY_COORDS = [
        'rotterdam' => [51.9225, 4.4792],
        'amsterdam' => [52.3676, 4.9041],
        'den haag' => [52.0705, 4.3007],
        'denhaag' => [52.0705, 4.3007],
        'utrecht' => [52.0907, 5.1214],
        'leiden' => [52.1601, 4.4970],
        'haarlem' => [52.3874, 4.6462],
        'eindhoven' => [51.4416, 5.4697],
        'groningen' => [53.2194, 6.5665],
        'tilburg' => [51.5555, 5.0913],
        'almere' => [52.3508, 5.2647],
        'breda' => [51.5866, 4.7760],
        'nijmegen' => [51.8427, 5.8532],
        'enschede' => [52.2215, 6.8937],
    ];

    private function cityCoords(string $city): ?array
    {
        $key = strtolower(trim($city));
        if (isset(self::CITY_COORDS[$key])) {
            return self::CITY_COORDS[$key];
        }
        $keyNoSpaces = str_replace(' ', '', $key);
        foreach (self::CITY_COORDS as $k => $v) {
            if (str_replace(' ', '', $k) === $keyNoSpaces) {
                return $v;
            }
        }
        return null;
    }

    private function parseFloat($value): ?float
    {
        if ($value === null) {
            return null;
        }
        if (is_numeric($value)) {
            return (float) $value;
        }
        return null;
    }

    private function hasTrainerCoords(object $row): bool
    {
        $r = (array) $row;
        $lat = $r['trainer_lat'] ?? $r['lat'] ?? null;
        $lng = $r['trainer_lng'] ?? $r['lng'] ?? null;
        return $lat !== null && $lng !== null && is_numeric($lat) && is_numeric($lng);
    }

    private function haversineKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $earthRadius = 6371.0;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) * sin($dLat / 2)
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2))
            * sin($dLng / 2) * sin($dLng / 2);
        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));
        return round($earthRadius * $c, 2);
    }

    private function loadTrainerById(int $userId): ?array
    {
        $usersTable = $this->usersTable();
        if (!$usersTable || !Schema::hasTable('gymies_trainer_profiles')) {
            return null;
        }

        $userCols = Schema::getColumnListing($usersTable);
        $profileCols = Schema::getColumnListing('gymies_trainer_profiles');

        // Dynamisch user-naam kolom bepalen
        $nameCol = 'id';
        foreach (['display_name', 'name', 'full_name', 'first_name'] as $try) {
            if (in_array($try, $userCols)) { $nameCol = $try; break; }
        }

        $select = [
            "{$usersTable}.id as user_id",
            "{$usersTable}.{$nameCol} as name",
        ];
        if (in_array('email', $userCols))  $select[] = "{$usersTable}.email";

        // created_at voor founding partner badge berekening
        if (in_array('created_at', $profileCols)) {
            $select[] = "gymies_trainer_profiles.created_at as profile_created_at";
        } elseif (in_array('created_at', $userCols)) {
            $select[] = "{$usersTable}.created_at";
        }

        // Alle trainer_profiles kolommen: alleen selecteren als ze bestaan
        $profileFields = [
            'display_name'       => 'profile_display_name',
            'specialty'          => 'specialty',
            'region'             => 'region',
            'city'               => 'city',
            'bio'                => 'bio',
            'hourly_rate_cents'  => 'hourly_rate_cents',
            'avatar_url'         => 'avatar_url',
            'profile_slug'       => 'profile_slug',
            'booking_advance_days' => 'booking_advance_days',
            'payment_method'     => 'payment_method',
            'boosted_until'      => 'boosted_until',
            // Badge-gerelateerde profiel velden
            'offers_online_sessions' => 'offers_online_sessions',
            'has_flexible_hours'     => 'has_flexible_hours',
            'same_day_booking'       => 'same_day_booking',
            'has_free_cancellation'  => 'has_free_cancellation',
            'has_free_trial'         => 'has_free_trial',
        ];
        foreach ($profileFields as $col => $alias) {
            if (in_array($col, $profileCols)) {
                $as = ($col !== $alias) ? " as {$alias}" : '';
                $select[] = "gymies_trainer_profiles.{$col}{$as}";
            }
        }

        $row = DB::table('gymies_trainer_profiles')
            ->join($usersTable, "{$usersTable}.id", '=', 'gymies_trainer_profiles.user_id')
            ->where('gymies_trainer_profiles.user_id', $userId)
            ->select($select)
            ->first();

        if (!$row) {
            return null;
        }

        return $this->rowToTrainer($row);
    }

    private function rowToTrainer(object $row): array
    {
        $r = (array) $row;
        $profile = [
            'user_id' => (string) ($r['user_id'] ?? $r['id'] ?? ''),
            'display_name' => $r['profile_display_name'] ?? $r['display_name'] ?? $r['name'] ?? $r['email'] ?? 'Trainer',
            'email' => $r['email'] ?? '',
            'specialty' => $r['specialty'] ?? null,
            'region' => $r['region'] ?? null,
            'city' => $r['city'] ?? null,
            'bio' => $r['bio'] ?? null,
            'hourly_rate_cents' => isset($r['hourly_rate_cents']) ? (int) $r['hourly_rate_cents'] : null,
            'avatar_url' => $r['avatar_url'] ?? $r['avatar'] ?? null,
            'profile_slug' => $r['profile_slug'] ?? null,
            'booking_advance_days' => isset($r['booking_advance_days']) ? (int) $r['booking_advance_days'] : 28,
            'payment_method' => $r['payment_method'] ?? 'transfer_and_cash',
        ];
        if (array_key_exists('boosted_until', $r) && $r['boosted_until'] !== null) {
            $profile['boosted_until'] = $r['boosted_until'];
        }
        if (array_key_exists('distance_km', $r) && $r['distance_km'] !== null) {
            $profile['distance_km'] = (float) $r['distance_km'];
        }

        // Founding Partner badge — computed via feature flags
        $profile['is_founding_partner'] = $this->isFoundingPartner($r);

        // Computed badge velden — trainer profile columns die direct doorgestuurd worden
        $badgeFields = [
            'offers_online_sessions', 'has_flexible_hours', 'same_day_booking',
            'has_free_cancellation', 'has_free_trial', 'return_client_percentage',
            'is_top_booked',
        ];
        foreach ($badgeFields as $field) {
            if (array_key_exists($field, $r)) {
                $profile[$field] = $r[$field];
            }
        }

        // Computed: return_client_percentage (indien niet in profiel, berekenen uit bookings)
        if (!isset($profile['return_client_percentage'])) {
            $profile['return_client_percentage'] = $this->computeReturnClientPercentage($r);
        }

        // Computed: is_top_booked (top 10% van regio)
        if (!isset($profile['is_top_booked'])) {
            $profile['is_top_booked'] = $this->computeIsTopBooked($r);
        }

        return $profile;
    }

    private function buildMinimalTrainerFromUser(object $user): array
    {
        $r = (array) $user;
        $minimal = [
            'user_id' => (string) ($r['id'] ?? ''),
            'display_name' => $r['display_name'] ?? $r['name'] ?? $r['email'] ?? 'Trainer',
            'email' => $r['email'] ?? '',
            'specialty' => null,
            'region' => null,
            'city' => null,
            'bio' => null,
            'hourly_rate_cents' => null,
            'avatar_url' => null,
            'profile_slug' => null,
            'booking_advance_days' => 28,
            'payment_method' => 'transfer_and_cash',
        ];
        $minimal['is_founding_partner'] = $this->isFoundingPartner($r);
        return $minimal;
    }

    /**
     * Check of een trainer als Founding Partner kwalificeert.
     * Gebaseerd op feature flags: founding_partner_badge_enabled + founding_partner_cutoff_date.
     */
    private function isFoundingPartner(array $row): bool
    {
        if (!GymiesFeatureFlags::isEnabled('founding_partner_badge_enabled')) {
            return false;
        }

        $cutoff = GymiesFeatureFlags::getValue('founding_partner_cutoff_date');
        if (!$cutoff) {
            return false;
        }

        // Trainer's registratie-datum: probeer created_at uit profile of user tabel
        $createdAt = $row['profile_created_at'] ?? $row['created_at'] ?? null;
        if (!$createdAt) {
            return false;
        }

        try {
            $createdDate = new \DateTime((string) $createdAt);
            $cutoffDate  = new \DateTime($cutoff);
            return $createdDate < $cutoffDate;
        } catch (\Throwable $e) {
            return false;
        }
    }

    /**
     * Bereken het percentage klanten dat terugkomt (≥2 bookings met deze trainer).
     */
    private function computeReturnClientPercentage(array $row): ?float
    {
        $userId = (int) ($row['user_id'] ?? $row['id'] ?? 0);
        if ($userId <= 0 || !Schema::hasTable('gymies_bookings')) {
            return null;
        }

        $trainerCol = Schema::hasColumn('gymies_bookings', 'trainer_user_id')
            ? 'trainer_user_id' : 'trainer_id';
        $clientCol = Schema::hasColumn('gymies_bookings', 'client_user_id')
            ? 'client_user_id' : 'client_id';

        $totalClients = DB::table('gymies_bookings')
            ->where($trainerCol, $userId)
            ->distinct($clientCol)
            ->count($clientCol);

        if ($totalClients < 3) return null; // Te weinig data

        $returningClients = DB::table('gymies_bookings')
            ->select($clientCol)
            ->where($trainerCol, $userId)
            ->groupBy($clientCol)
            ->havingRaw('COUNT(*) >= 2')
            ->get()
            ->count();

        return round(($returningClients / $totalClients) * 100, 1);
    }

    /**
     * Check of trainer in de top 10% meest geboekt is in zijn regio.
     */
    private function computeIsTopBooked(array $row): bool
    {
        $userId = (int) ($row['user_id'] ?? $row['id'] ?? 0);
        $city = $row['city'] ?? $row['region'] ?? null;
        if ($userId <= 0 || !$city || !Schema::hasTable('gymies_bookings')) {
            return false;
        }

        $trainerCol = Schema::hasColumn('gymies_bookings', 'trainer_user_id')
            ? 'trainer_user_id' : 'trainer_id';

        // Bookings in de afgelopen 30 dagen voor deze trainer
        $myBookings = DB::table('gymies_bookings')
            ->where($trainerCol, $userId)
            ->where('created_at', '>=', now()->subDays(30))
            ->count();

        if ($myBookings < 5) return false; // Minimum drempel

        // Alle trainers in dezelfde stad: bookings afgelopen 30 dagen
        $cityTrainerIds = DB::table('gymies_trainer_profiles')
            ->where('city', $city)
            ->pluck('user_id')
            ->toArray();

        if (count($cityTrainerIds) < 5) return false; // Te weinig trainers voor vergelijking

        $bookingCounts = DB::table('gymies_bookings')
            ->whereIn($trainerCol, $cityTrainerIds)
            ->where('created_at', '>=', now()->subDays(30))
            ->select($trainerCol)
            ->selectRaw('COUNT(*) as cnt')
            ->groupBy($trainerCol)
            ->orderByDesc('cnt')
            ->pluck('cnt', $trainerCol)
            ->toArray();

        $topCutoff = (int) ceil(count($cityTrainerIds) * 0.10);
        $topTrainerIds = array_slice(array_keys($bookingCounts), 0, max(1, $topCutoff));

        return in_array($userId, $topTrainerIds, true);
    }

    private function loadPackages(int $trainerId): array
    {
        if (!Schema::hasTable('gymies_packages')) {
            return [];
        }

        $userIdCol = Schema::hasColumn('gymies_packages', 'trainer_user_id')
            ? 'trainer_user_id'
            : 'user_id';
        $rows = DB::table('gymies_packages')
            ->where($userIdCol, $trainerId)
            ->get();

        $packages = [];
        // Alleen veilige velden — voorkom interne metadata leaks.
        $allowed = ['id', 'name', 'description', 'price_cents', 'session_count', 'duration_weeks', 'is_active', 'sort_order', 'created_at'];
        foreach ($rows as $row) {
            $packages[] = collect((array) $row)->only($allowed)->toArray();
        }
        return $packages;
    }

    private function loadMedia(int $trainerId): array
    {
        if (!Schema::hasTable('gymies_trainer_media')) {
            return [];
        }

        GymiesSchemaEnsure::trainerMediaStoryColumns();

        $userIdCol = Schema::hasColumn('gymies_trainer_media', 'trainer_user_id')
            ? 'trainer_user_id'
            : 'user_id';

        $hasUsage = Schema::hasColumn('gymies_trainer_media', 'usage');
        $hasExpires = Schema::hasColumn('gymies_trainer_media', 'expires_at');

        $query = DB::table('gymies_trainer_media')
            ->where($userIdCol, $trainerId);

        // Filter verlopen stories uit
        if ($hasUsage && $hasExpires) {
            $query->where(function ($q) {
                $q->where('usage', '!=', 'story')
                  ->orWhere(function ($q2) {
                      $q2->where('usage', 'story')
                         ->where(function ($q3) {
                             $q3->whereNull('expires_at')
                                ->orWhere('expires_at', '>', now());
                         });
                  });
            });
        }

        $rows = $query->get();

        $media = [];
        foreach ($rows as $row) {
            $filePath = (string) ($row->file_path ?? '');
            $externalUrl = (string) ($row->external_url ?? '');
            $url = $externalUrl !== '' ? $externalUrl : $filePath;
            if ($filePath !== '' && !str_starts_with($filePath, 'http')) {
                $url = url($filePath);
            }
            $item = [
                'id' => (string) $row->id,
                'type' => (string) ($row->media_type ?? 'image'),
                'media_type' => (string) ($row->media_type ?? 'image'),
                'url' => $url,
                'thumbnail_url' => $row->thumbnail_url ?? null,
                'caption' => $row->caption ?? null,
                'sort_order' => (int) ($row->sort_order ?? 0),
                'created_at' => $row->created_at ?? null,
                'usage' => $hasUsage ? ((string) ($row->usage ?? 'gallery')) : 'gallery',
            ];
            $media[] = $item;
        }
        return $media;
    }
}
