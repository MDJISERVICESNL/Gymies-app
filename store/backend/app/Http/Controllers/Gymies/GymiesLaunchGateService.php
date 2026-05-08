<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Gymies Launch Gate Service — Controlled launch & exclusivity management.
 *
 * Features:
 * - Regional launch phases: closed → waitlist → invite_only → open
 * - Invite code system with fraud detection (max 5 uses per IP per 24 hours)
 * - Waitlist management with position tracking
 * - Regional readiness evaluation (trainer/client counts, ratios, booking metrics)
 *
 * Tables:
 * - gymies_launch_regions: Regional launch status & counters
 * - gymies_invite_codes: Master invite code records with usage limits
 * - gymies_invite_code_uses: Individual code usage tracking (for fraud detection)
 * - gymies_waitlist: Waitlist entries with position & status
 */
final class GymiesLaunchGateService
{
    /**
     * Ensure all launch gate tables exist.
     */
    public static function ensureSchema(): void
    {
        try {
            if (!Schema::hasTable('gymies_launch_regions')) {
                DB::statement("
                    CREATE TABLE IF NOT EXISTS gymies_launch_regions (
                        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                        city VARCHAR(128) NOT NULL,
                        slug VARCHAR(64) NOT NULL UNIQUE,
                        province VARCHAR(128) DEFAULT NULL,
                        status ENUM('closed','waitlist','invite_only','open') NOT NULL DEFAULT 'closed',
                        min_trainers_to_open INT UNSIGNED NOT NULL DEFAULT 5,
                        max_client_trainer_ratio INT UNSIGNED NOT NULL DEFAULT 15,
                        trainers_count INT UNSIGNED NOT NULL DEFAULT 0,
                        clients_count INT UNSIGNED NOT NULL DEFAULT 0,
                        waitlist_count INT UNSIGNED NOT NULL DEFAULT 0,
                        bookings_this_week INT UNSIGNED NOT NULL DEFAULT 0,
                        latitude DECIMAL(10,7) DEFAULT NULL,
                        longitude DECIMAL(10,7) DEFAULT NULL,
                        opened_at TIMESTAMP NULL DEFAULT NULL,
                        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                        INDEX idx_slug (slug),
                        INDEX idx_status (status)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            }

            if (!Schema::hasTable('gymies_invite_codes')) {
                DB::statement("
                    CREATE TABLE IF NOT EXISTS gymies_invite_codes (
                        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                        code VARCHAR(20) NOT NULL UNIQUE,
                        owner_user_id BIGINT UNSIGNED NOT NULL,
                        owner_type ENUM('trainer','gym','staff','ambassador') NOT NULL DEFAULT 'trainer',
                        region_slug VARCHAR(64) DEFAULT NULL,
                        max_uses INT UNSIGNED NOT NULL DEFAULT 20,
                        uses_count INT UNSIGNED NOT NULL DEFAULT 0,
                        valid_until TIMESTAMP NULL DEFAULT NULL,
                        referred_role ENUM('client','trainer') NOT NULL DEFAULT 'client',
                        status ENUM('active','exhausted','expired','revoked') NOT NULL DEFAULT 'active',
                        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                        INDEX idx_owner (owner_user_id),
                        INDEX idx_code_status (code, status),
                        INDEX idx_region (region_slug),
                        INDEX idx_valid_until (valid_until)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            }

            if (!Schema::hasTable('gymies_invite_code_uses')) {
                DB::statement("
                    CREATE TABLE IF NOT EXISTS gymies_invite_code_uses (
                        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                        invite_code_id BIGINT UNSIGNED NOT NULL,
                        used_by_user_id BIGINT UNSIGNED NOT NULL,
                        ip_address VARCHAR(45) DEFAULT NULL,
                        confirmed_at TIMESTAMP NULL DEFAULT NULL,
                        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                        INDEX idx_code (invite_code_id),
                        INDEX idx_user (used_by_user_id),
                        INDEX idx_ip_time (ip_address, created_at),
                        FOREIGN KEY (invite_code_id) REFERENCES gymies_invite_codes(id) ON DELETE CASCADE
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            }

            if (!Schema::hasTable('gymies_waitlist')) {
                DB::statement("
                    CREATE TABLE IF NOT EXISTS gymies_waitlist (
                        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                        user_id BIGINT UNSIGNED NOT NULL,
                        region_slug VARCHAR(64) NOT NULL,
                        role ENUM('client','trainer') NOT NULL DEFAULT 'client',
                        position INT UNSIGNED NOT NULL DEFAULT 0,
                        status ENUM('waiting','activated','expired') NOT NULL DEFAULT 'waiting',
                        activated_at TIMESTAMP NULL DEFAULT NULL,
                        notified_at TIMESTAMP NULL DEFAULT NULL,
                        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                        UNIQUE KEY uk_user_region (user_id, region_slug),
                        INDEX idx_region_status (region_slug, status),
                        INDEX idx_position (region_slug, position)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            }
            // ── gymies_trainer_regions: multi-stad koppeltabel ──
            if (!Schema::hasTable('gymies_trainer_regions')) {
                DB::statement("
                    CREATE TABLE IF NOT EXISTS gymies_trainer_regions (
                        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                        trainer_user_id BIGINT UNSIGNED NOT NULL,
                        region_slug VARCHAR(64) NOT NULL,
                        source ENUM('self_reported','kvk_verified','staff_assigned') NOT NULL DEFAULT 'self_reported',
                        verified TINYINT(1) NOT NULL DEFAULT 0,
                        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                        UNIQUE KEY uk_trainer_region (trainer_user_id, region_slug),
                        INDEX idx_region (region_slug),
                        INDEX idx_trainer (trainer_user_id),
                        INDEX idx_verified (region_slug, verified)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            }

            // Migration: add min_clients_waitlist column if missing
            if (Schema::hasTable('gymies_launch_regions') && !Schema::hasColumn('gymies_launch_regions', 'min_clients_waitlist')) {
                try {
                    DB::statement("ALTER TABLE gymies_launch_regions ADD COLUMN min_clients_waitlist INT UNSIGNED NOT NULL DEFAULT 10 AFTER max_client_trainer_ratio");
                } catch (\Throwable $migErr) {
                    Log::info('[LaunchGateService] min_clients_waitlist migration skipped', ['msg' => $migErr->getMessage()]);
                }
            }

            // Migration: add source column to waitlist for tracking how users joined
            if (Schema::hasTable('gymies_waitlist') && !Schema::hasColumn('gymies_waitlist', 'source')) {
                try {
                    DB::statement("ALTER TABLE gymies_waitlist ADD COLUMN source ENUM('registration','booking_gate','staff','manual') NOT NULL DEFAULT 'registration' AFTER status");
                } catch (\Throwable $migErr) {
                    Log::info('[LaunchGateService] waitlist source migration skipped', ['msg' => $migErr->getMessage()]);
                }
            }

            // Migration: add lat/lng columns if missing
            if (Schema::hasTable('gymies_launch_regions') && !Schema::hasColumn('gymies_launch_regions', 'latitude')) {
                try {
                    DB::statement("ALTER TABLE gymies_launch_regions ADD COLUMN latitude DECIMAL(10,7) DEFAULT NULL AFTER bookings_this_week");
                    DB::statement("ALTER TABLE gymies_launch_regions ADD COLUMN longitude DECIMAL(10,7) DEFAULT NULL AFTER latitude");
                } catch (\Throwable $migErr) {
                    // Column may already exist (race condition) — safe to ignore
                    Log::info('[LaunchGateService] lat/lng migration skipped', ['msg' => $migErr->getMessage()]);
                }
                // Back-fill coordinates for existing rows
                self::backfillCoordinates();
            }
        } catch (\Throwable $e) {
            Log::error('[LaunchGateService] ensureSchema failed', ['error' => $e->getMessage()]);
            if (app()->bound('sentry')) {
                app('sentry')->captureException($e);
            }
        }
    }

    /**
     * Dutch city → coordinates lookup table.
     * Covers all major cities; falls back to province capitals.
     */
    public static function getCityCoordinates(string $city): ?array
    {
        $lookup = [
            // Randstad
            'amsterdam'     => [52.3676, 4.9041],
            'rotterdam'     => [51.9225, 4.4792],
            'den haag'      => [52.0705, 4.3007],
            'utrecht'       => [52.0907, 5.1214],
            'almere'        => [52.3508, 5.2647],
            'haarlem'       => [52.3874, 4.6462],
            'leiden'        => [52.1601, 4.4970],
            'delft'         => [52.0116, 4.3571],
            'dordrecht'     => [51.8133, 4.6901],
            'zoetermeer'    => [52.0575, 4.4931],
            // Noord-Brabant
            'eindhoven'     => [51.4416, 5.4697],
            'tilburg'       => [51.5555, 5.0913],
            'breda'         => [51.5719, 4.7683],
            'den bosch'     => [51.6998, 5.3049],
            "'s-hertogenbosch" => [51.6998, 5.3049],
            'helmond'       => [51.4792, 5.6614],
            // Gelderland
            'arnhem'        => [51.9851, 5.8987],
            'nijmegen'      => [51.8126, 5.8372],
            'apeldoorn'     => [52.2112, 5.9699],
            'ede'           => [52.0484, 5.6615],
            // Overijssel
            'enschede'      => [52.2215, 6.8937],
            'zwolle'        => [52.5168, 6.0830],
            'deventer'      => [52.2660, 6.1552],
            'hengelo'       => [52.2649, 6.7934],
            // Noord-Holland
            'zaandam'       => [52.4389, 4.8262],
            'hilversum'     => [52.2292, 5.1669],
            'alkmaar'       => [52.6324, 4.7534],
            'hoorn'         => [52.6424, 5.0602],
            // Zuid-Holland
            'gouda'         => [52.0115, 4.7104],
            'schiedam'      => [51.9244, 4.3989],
            'vlaardingen'   => [51.9120, 4.3421],
            // Limburg
            'maastricht'    => [50.8514, 5.6910],
            'venlo'         => [51.3704, 6.1724],
            'heerlen'       => [50.8882, 5.9811],
            'sittard'       => [51.0006, 5.8686],
            'roermond'      => [51.1943, 5.9877],
            // Friesland
            'leeuwarden'    => [53.2012, 5.7999],
            // Groningen
            'groningen'     => [53.2194, 6.5665],
            // Drenthe
            'assen'         => [52.9929, 6.5642],
            'emmen'         => [52.7792, 6.8975],
            // Flevoland
            'lelystad'      => [52.5185, 5.4714],
            // Zeeland
            'middelburg'    => [51.4988, 3.6109],
            'vlissingen'    => [51.4427, 3.5710],
            'goes'          => [51.5040, 3.8927],
        ];

        $key = strtolower(trim($city));

        // Direct match
        if (isset($lookup[$key])) {
            return ['lat' => $lookup[$key][0], 'lng' => $lookup[$key][1]];
        }

        // Partial match (e.g. "Amsterdam-Zuid" → "amsterdam")
        foreach ($lookup as $name => $coords) {
            if (str_contains($key, $name) || str_contains($name, $key)) {
                return ['lat' => $coords[0], 'lng' => $coords[1]];
            }
        }

        return null;
    }

    /**
     * Back-fill latitude/longitude for all regions missing coordinates.
     */
    public static function backfillCoordinates(): void
    {
        try {
            $regions = DB::table('gymies_launch_regions')
                ->whereNull('latitude')
                ->get(['id', 'city']);

            foreach ($regions as $region) {
                $coords = self::getCityCoordinates((string) $region->city);
                if ($coords) {
                    DB::table('gymies_launch_regions')
                        ->where('id', $region->id)
                        ->update([
                            'latitude' => $coords['lat'],
                            'longitude' => $coords['lng'],
                        ]);
                }
            }
        } catch (\Throwable $e) {
            Log::warning('[LaunchGateService] backfillCoordinates failed', ['error' => $e->getMessage()]);
        }
    }

    /**
     * Look up user's city from gymies_users or gymies_trainer_profiles.
     * Try multiple locations to find city info.
     */
    public static function getUserCity(int $userId, string $role = 'client'): ?string
    {
        try {
            $city = null;

            if ($role === 'trainer' || $role === 'trainer_profile') {
                // Try trainer_profiles first
                if (Schema::hasTable('gymies_trainer_profiles')) {
                    $city = DB::table('gymies_trainer_profiles')
                        ->where('user_id', $userId)
                        ->value('city');
                }
            }

            // Fallback to gymies_users
            if ($city === null && Schema::hasTable('gymies_users')) {
                $city = DB::table('gymies_users')
                    ->where('id', $userId)
                    ->value('city');
            }

            return $city ? trim((string) $city) : null;
        } catch (\Throwable $e) {
            Log::warning('[LaunchGateService] getUserCity failed', [
                'user_id' => $userId,
                'role' => $role,
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Resolve region by city (case-insensitive LIKE match).
     */
    public static function resolveRegionForCity(?string $city): ?object
    {
        if (!$city) {
            return null;
        }

        self::ensureSchema();

        try {
            $city = trim((string) $city);
            if ($city === '') {
                return null;
            }

            return DB::table('gymies_launch_regions')
                ->whereRaw('LOWER(city) LIKE ?', [strtolower($city) . '%'])
                ->first();
        } catch (\Throwable $e) {
            Log::warning('[LaunchGateService] resolveRegionForCity failed', [
                'city' => $city,
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Check if user can access the platform.
     *
     * @return array{allowed: bool, reason: string, region: ?object, waitlist_position: ?int}
     */
    public static function canAccessPlatform(int $userId, string $role, ?string $inviteCode = null): array
    {
        self::ensureSchema();

        try {
            // If launch gate not yet active, allow everyone
            if (!Schema::hasTable('gymies_launch_regions')) {
                return [
                    'allowed' => true,
                    'reason' => 'Launch gate niet actief',
                    'region' => null,
                    'waitlist_position' => null,
                ];
            }

            // Look up user's city
            $city = self::getUserCity($userId, $role);
            if (!$city) {
                return [
                    'allowed' => false,
                    'reason' => 'Stad niet ingesteld in profiel',
                    'region' => null,
                    'waitlist_position' => null,
                ];
            }

            // Find region
            $region = self::resolveRegionForCity($city);
            if (!$region) {
                return [
                    'allowed' => false,
                    'reason' => 'Regio niet beschikbaar',
                    'region' => null,
                    'waitlist_position' => null,
                ];
            }

            // Check region status
            $status = (string) $region->status;

            if ($status === 'open') {
                return [
                    'allowed' => true,
                    'reason' => 'Regio geopend',
                    'region' => $region,
                    'waitlist_position' => null,
                ];
            }

            // Check if invite code is valid
            $codeValid = false;
            if ($inviteCode) {
                $codeResult = self::validateInviteCode($inviteCode);
                $codeValid = $codeResult['valid'];
            }

            if (($status === 'invite_only' || $status === 'waitlist') && $codeValid) {
                return [
                    'allowed' => true,
                    'reason' => 'Toegang met invitatiecode',
                    'region' => $region,
                    'waitlist_position' => null,
                ];
            }

            if ($status === 'closed') {
                return [
                    'allowed' => false,
                    'reason' => 'Regio gesloten. Meld je aan voor de wachtlijst.',
                    'region' => $region,
                    'waitlist_position' => self::getWaitlistPosition($userId, $region->slug),
                ];
            }

            // Default: offer waitlist
            return [
                'allowed' => false,
                'reason' => 'Regio in beperkte modus. Meld je aan voor de wachtlijst.',
                'region' => $region,
                'waitlist_position' => self::getWaitlistPosition($userId, $region->slug),
            ];
        } catch (\Throwable $e) {
            Log::error('[LaunchGateService] canAccessPlatform failed', [
                'user_id' => $userId,
                'role' => $role,
                'error' => $e->getMessage(),
            ]);
            return [
                'allowed' => false,
                'reason' => 'Fout bij het controleren van toegang',
                'region' => null,
                'waitlist_position' => null,
            ];
        }
    }

    /**
     * Validate invite code.
     *
     * @return array{valid: bool, message: string, code_row: ?object}
     */
    public static function validateInviteCode(string $code): array
    {
        self::ensureSchema();

        try {
            $code = trim(strtoupper((string) $code));
            if ($code === '') {
                return ['valid' => false, 'message' => 'Invitatiecode is verplicht'];
            }

            $codeRow = DB::table('gymies_invite_codes')
                ->where('code', $code)
                ->first();

            if (!$codeRow) {
                return ['valid' => false, 'message' => 'Ongeldige invitatiecode'];
            }

            // Check status
            if ((string) $codeRow->status !== 'active') {
                return [
                    'valid' => false,
                    'message' => 'Deze code is niet meer geldig (' . $codeRow->status . ')',
                    'code_row' => $codeRow,
                ];
            }

            // Check usage limit
            $uses = (int) $codeRow->uses_count;
            $maxUses = (int) $codeRow->max_uses;
            if ($uses >= $maxUses) {
                return [
                    'valid' => false,
                    'message' => 'Deze code is opgebruikt',
                    'code_row' => $codeRow,
                ];
            }

            // Check expiry
            if ($codeRow->valid_until !== null) {
                $expiresAt = \Carbon\Carbon::parse($codeRow->valid_until);
                if (now()->isAfter($expiresAt)) {
                    return [
                        'valid' => false,
                        'message' => 'Deze code is verlopen',
                        'code_row' => $codeRow,
                    ];
                }
            }

            // Check fraud: max 5 uses per IP per 24 hours
            // TODO: require IP address in consume method
            $fraudCheck = self::checkInviteCodeFraud($codeRow->id);
            if (!$fraudCheck['allowed']) {
                return [
                    'valid' => false,
                    'message' => $fraudCheck['message'],
                    'code_row' => $codeRow,
                ];
            }

            return [
                'valid' => true,
                'message' => 'Code geldig',
                'code_row' => $codeRow,
            ];
        } catch (\Throwable $e) {
            Log::error('[LaunchGateService] validateInviteCode failed', [
                'code' => $code,
                'error' => $e->getMessage(),
            ]);
            return [
                'valid' => false,
                'message' => 'Fout bij valideren code',
            ];
        }
    }

    /**
     * Check for fraud on invite code usage.
     * Max 5 uses per IP address per 24 hours.
     *
     * @return array{allowed: bool, message: string}
     */
    private static function checkInviteCodeFraud(int $codeId, ?string $ipAddress = null): array
    {
        try {
            // If no IP available, allow (can't check)
            if (!$ipAddress) {
                return ['allowed' => true, 'message' => ''];
            }

            $count = DB::table('gymies_invite_code_uses')
                ->where('invite_code_id', $codeId)
                ->where('ip_address', $ipAddress)
                ->where('created_at', '>=', now()->subHours(24))
                ->count();

            if ($count >= 5) {
                return [
                    'allowed' => false,
                    'message' => 'Te veel pogingen van dit apparaat. Probeer later opnieuw.',
                ];
            }

            return ['allowed' => true, 'message' => ''];
        } catch (\Throwable $e) {
            // Fail-open on error
            Log::warning('[LaunchGateService] checkInviteCodeFraud failed', [
                'code_id' => $codeId,
                'error' => $e->getMessage(),
            ]);
            return ['allowed' => true, 'message' => ''];
        }
    }

    /**
     * Consume invite code after successful validation.
     */
    public static function consumeInviteCode(string $code, int $userId, ?string $ipAddress = null): bool
    {
        self::ensureSchema();

        try {
            $code = trim(strtoupper((string) $code));

            DB::beginTransaction();

            // Get code and lock for update
            $codeRow = DB::table('gymies_invite_codes')
                ->where('code', $code)
                ->lockForUpdate()
                ->first();

            if (!$codeRow) {
                DB::rollBack();
                return false;
            }

            $codeId = (int) $codeRow->id;

            // Record usage
            DB::table('gymies_invite_code_uses')->insert([
                'invite_code_id' => $codeId,
                'used_by_user_id' => $userId,
                'ip_address' => $ipAddress,
                'confirmed_at' => now(),
                'created_at' => now(),
            ]);

            // Increment uses_count
            DB::table('gymies_invite_codes')
                ->where('id', $codeId)
                ->increment('uses_count');

            // Check if exhausted
            $newUses = (int) DB::table('gymies_invite_codes')
                ->where('id', $codeId)
                ->value('uses_count');

            $maxUses = (int) $codeRow->max_uses;
            if ($newUses >= $maxUses) {
                DB::table('gymies_invite_codes')
                    ->where('id', $codeId)
                    ->update(['status' => 'exhausted']);
            }

            // Update region counters
            $regionSlug = $codeRow->region_slug;
            if ($regionSlug) {
                $referredRole = (string) $codeRow->referred_role;
                if ($referredRole === 'trainer') {
                    DB::table('gymies_launch_regions')
                        ->where('slug', $regionSlug)
                        ->increment('trainers_count');
                } else {
                    DB::table('gymies_launch_regions')
                        ->where('slug', $regionSlug)
                        ->increment('clients_count');
                }
            }

            DB::commit();
            return true;
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('[LaunchGateService] consumeInviteCode failed', [
                'code' => $code,
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Generate invite codes.
     *
     * @return array Array of code strings
     */
    public static function generateInviteCodes(
        int $ownerUserId,
        string $ownerType,
        int $count = 1,
        ?string $regionSlug = null,
        string $referredRole = 'client',
        int $maxUsesPerCode = 20
    ): array {
        self::ensureSchema();

        $codes = [];

        try {
            DB::beginTransaction();

            for ($i = 0; $i < $count; $i++) {
                $code = 'GYM-' . Str::upper(Str::random(6));

                // Ensure uniqueness (very low chance of collision, but check)
                while (DB::table('gymies_invite_codes')->where('code', $code)->exists()) {
                    $code = 'GYM-' . Str::upper(Str::random(6));
                }

                DB::table('gymies_invite_codes')->insert([
                    'code' => $code,
                    'owner_user_id' => $ownerUserId,
                    'owner_type' => $ownerType,
                    'region_slug' => $regionSlug,
                    'max_uses' => $maxUsesPerCode,
                    'uses_count' => 0,
                    'referred_role' => $referredRole,
                    'status' => 'active',
                    'created_at' => now(),
                ]);

                $codes[] = $code;
            }

            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('[LaunchGateService] generateInviteCodes failed', [
                'owner_id' => $ownerUserId,
                'count' => $count,
                'error' => $e->getMessage(),
            ]);
        }

        return $codes;
    }

    /**
     * Add user to waitlist for a region.
     *
     * @return array{success: bool, position: int, message: string}
     */
    public static function addToWaitlist(int $userId, string $regionSlug, string $role = 'client'): array
    {
        self::ensureSchema();

        try {
            $regionSlug = trim((string) $regionSlug);

            // Check not already on waitlist
            $existing = DB::table('gymies_waitlist')
                ->where('user_id', $userId)
                ->where('region_slug', $regionSlug)
                ->first();

            if ($existing) {
                return [
                    'success' => false,
                    'position' => (int) $existing->position,
                    'message' => 'Je staat al op de wachtlijst',
                ];
            }

            DB::beginTransaction();

            // Get current waitlist count (will be position)
            $region = DB::table('gymies_launch_regions')
                ->where('slug', $regionSlug)
                ->lockForUpdate()
                ->first();

            if (!$region) {
                DB::rollBack();
                return [
                    'success' => false,
                    'position' => 0,
                    'message' => 'Regio niet gevonden',
                ];
            }

            $position = (int) $region->waitlist_count + 1;

            // Insert waitlist entry
            DB::table('gymies_waitlist')->insert([
                'user_id' => $userId,
                'region_slug' => $regionSlug,
                'role' => $role,
                'position' => $position,
                'status' => 'waiting',
                'created_at' => now(),
            ]);

            // Increment waitlist_count
            DB::table('gymies_launch_regions')
                ->where('slug', $regionSlug)
                ->increment('waitlist_count');

            DB::commit();

            return [
                'success' => true,
                'position' => $position,
                'message' => 'Je bent toegevoegd aan de wachtlijst (positie ' . $position . ')',
            ];
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('[LaunchGateService] addToWaitlist failed', [
                'user_id' => $userId,
                'region' => $regionSlug,
                'error' => $e->getMessage(),
            ]);
            return [
                'success' => false,
                'position' => 0,
                'message' => 'Fout bij toevoegen aan wachtlijst',
            ];
        }
    }

    /**
     * Get waitlist position for user in region.
     */
    public static function getWaitlistPosition(int $userId, ?string $regionSlug = null): ?int
    {
        try {
            $query = DB::table('gymies_waitlist')
                ->where('user_id', $userId)
                ->where('status', 'waiting');

            if ($regionSlug) {
                $query->where('region_slug', trim((string) $regionSlug));
            }

            $entry = $query->first();

            return $entry ? (int) $entry->position : null;
        } catch (\Throwable $e) {
            Log::warning('[LaunchGateService] getWaitlistPosition failed', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Activate user from waitlist (when invited).
     */
    public static function activateFromWaitlist(int $userId, ?string $regionSlug = null): bool
    {
        try {
            $query = DB::table('gymies_waitlist')
                ->where('user_id', $userId);

            if ($regionSlug) {
                $query->where('region_slug', trim((string) $regionSlug));
            }

            $updated = $query->update([
                'status' => 'activated',
                'activated_at' => now(),
                'updated_at' => now(),
            ]);

            return $updated > 0;
        } catch (\Throwable $e) {
            Log::error('[LaunchGateService] activateFromWaitlist failed', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Activate users from waitlist for a region (up to limit).
     * Called when region opens.
     *
     * @return int Count of activated users
     */
    public static function activateWaitlistForRegion(string $regionSlug, int $limit = 50): int
    {
        try {
            $regionSlug = trim((string) $regionSlug);

            $users = DB::table('gymies_waitlist')
                ->where('region_slug', $regionSlug)
                ->where('status', 'waiting')
                ->orderBy('position', 'asc')
                ->limit($limit)
                ->pluck('id');

            if ($users->isEmpty()) {
                return 0;
            }

            $updated = DB::table('gymies_waitlist')
                ->whereIn('id', $users)
                ->update([
                    'status' => 'activated',
                    'activated_at' => now(),
                    'updated_at' => now(),
                ]);

            return (int) $updated;
        } catch (\Throwable $e) {
            Log::error('[LaunchGateService] activateWaitlistForRegion failed', [
                'region' => $regionSlug,
                'error' => $e->getMessage(),
            ]);
            return 0;
        }
    }

    /**
     * Count "launch-ready" trainers in a region.
     *
     * A trainer is launch-ready when ALL of the following are true:
     *  1. Onboarding status = 'approved'
     *  2. At least 1 service/dienst created
     *  3. Availability set (at least 1 slot)
     *  4. KvK + IBAN verified (documents reviewed)
     *  5. Payment profile active (Mollie connected OR Gymies Connect)
     *  6. Linked to region via gymies_trainer_regions
     *
     * Falls back to basic count if tables don't exist.
     */
    public static function countLaunchReadyTrainers(string $regionSlug): int
    {
        try {
            // If trainer_regions table exists, use it for accurate counting
            if (Schema::hasTable('gymies_trainer_regions')) {
                $trainerIds = DB::table('gymies_trainer_regions')
                    ->where('region_slug', $regionSlug)
                    ->pluck('trainer_user_id')
                    ->toArray();

                if (empty($trainerIds)) {
                    return 0;
                }

                $readyCount = 0;
                foreach ($trainerIds as $trainerId) {
                    if (self::isTrainerLaunchReady((int) $trainerId)) {
                        $readyCount++;
                    }
                }

                return $readyCount;
            }

            // Fallback: count from region counters (legacy)
            $region = DB::table('gymies_launch_regions')
                ->where('slug', $regionSlug)
                ->first();

            return $region ? (int) $region->trainers_count : 0;
        } catch (\Throwable $e) {
            Log::warning('[LaunchGateService] countLaunchReadyTrainers failed', [
                'region' => $regionSlug,
                'error' => $e->getMessage(),
            ]);
            return 0;
        }
    }

    /**
     * Check if a single trainer meets all launch-readiness criteria.
     */
    public static function isTrainerLaunchReady(int $userId): bool
    {
        try {
            // 1. Check onboarding status = approved
            $onboardingOk = false;
            if (Schema::hasTable('gymies_onboarding_submissions')) {
                $onboardingOk = DB::table('gymies_onboarding_submissions')
                    ->where('user_id', $userId)
                    ->where('status', 'approved')
                    ->exists();
            } else {
                // No onboarding table → check if trainer profile exists as proxy
                $onboardingOk = Schema::hasTable('gymies_trainer_profiles')
                    && DB::table('gymies_trainer_profiles')->where('user_id', $userId)->exists();
            }
            if (!$onboardingOk) return false;

            // 2. At least 1 service created
            $hasServices = false;
            if (Schema::hasTable('gymies_services')) {
                $hasServices = DB::table('gymies_services')
                    ->where('trainer_user_id', $userId)
                    ->where('status', 'active')
                    ->exists();
            }
            if (!$hasServices) return false;

            // 3. Availability set (at least 1 slot)
            $hasAvailability = false;
            if (Schema::hasTable('gymies_availability')) {
                $hasAvailability = DB::table('gymies_availability')
                    ->where('trainer_user_id', $userId)
                    ->exists();
            }
            if (!$hasAvailability) return false;

            // 4. KvK + IBAN present (basic check — verified by staff during onboarding review)
            if (Schema::hasTable('gymies_trainer_profiles')) {
                $profile = DB::table('gymies_trainer_profiles')
                    ->where('user_id', $userId)
                    ->first(['kvk_number', 'iban']);

                if (!$profile) return false;
                $kvkOk = !empty($profile->kvk_number) && strlen(trim((string) $profile->kvk_number)) >= 8;
                $ibanOk = !empty($profile->iban) && strlen(trim((string) $profile->iban)) >= 10;
                if (!$kvkOk || !$ibanOk) return false;
            }

            // 5. Payment profile (Mollie connected OR gymies_connect_payments flag)
            $paymentOk = false;
            if (Schema::hasTable('gymies_trainer_profiles')) {
                $mollieToken = DB::table('gymies_trainer_profiles')
                    ->where('user_id', $userId)
                    ->value('mollie_access_token');
                $paymentOk = !empty($mollieToken);
            }
            // If no personal Mollie, check if Gymies Connect is enabled (platform handles payments)
            if (!$paymentOk && class_exists(GymiesFeatureFlags::class)) {
                $paymentOk = GymiesFeatureFlags::isEnabled('gymies_connect_payments', $userId);
            }
            // Fallback: if no payment tables found, assume ok (early stage)
            if (!$paymentOk && !Schema::hasTable('gymies_trainer_profiles')) {
                $paymentOk = true;
            }
            if (!$paymentOk) return false;

            return true;
        } catch (\Throwable $e) {
            Log::warning('[LaunchGateService] isTrainerLaunchReady failed', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Add trainer to a region (multi-stad support).
     *
     * @param string $source 'self_reported' | 'kvk_verified' | 'staff_assigned'
     */
    public static function addTrainerToRegion(int $userId, string $regionSlug, string $source = 'self_reported', bool $verified = false): bool
    {
        self::ensureSchema();

        try {
            $regionSlug = trim((string) $regionSlug);
            if ($regionSlug === '') return false;

            // Max 3 regions per trainer (prevent abuse)
            $currentCount = DB::table('gymies_trainer_regions')
                ->where('trainer_user_id', $userId)
                ->count();

            if ($currentCount >= 3) {
                Log::info('[LaunchGateService] Trainer at max regions limit', [
                    'user_id' => $userId,
                    'current_count' => $currentCount,
                ]);
                return false;
            }

            DB::table('gymies_trainer_regions')->updateOrInsert(
                ['trainer_user_id' => $userId, 'region_slug' => $regionSlug],
                [
                    'source' => $source,
                    'verified' => $verified ? 1 : 0,
                    'updated_at' => now(),
                ]
            );

            return true;
        } catch (\Throwable $e) {
            Log::error('[LaunchGateService] addTrainerToRegion failed', [
                'user_id' => $userId,
                'region' => $regionSlug,
                'error' => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Sync trainer regions from KvK vestigingsplaats.
     * Called after staff approves onboarding + KvK verification.
     *
     * Marks the KvK city region as verified and sets self-reported regions as unverified.
     */
    public static function syncTrainerRegionsFromKvK(int $userId): void
    {
        self::ensureSchema();

        try {
            // Get KvK city from trainer profile
            $kvkCity = null;
            if (Schema::hasTable('gymies_trainer_profiles')) {
                $kvkCity = DB::table('gymies_trainer_profiles')
                    ->where('user_id', $userId)
                    ->value('city');
            }

            if (!$kvkCity || trim((string) $kvkCity) === '') {
                Log::info('[LaunchGateService] No KvK city found for trainer', ['user_id' => $userId]);
                return;
            }

            $kvkCity = trim((string) $kvkCity);
            $region = self::resolveRegionForCity($kvkCity);

            if (!$region) {
                Log::info('[LaunchGateService] KvK city has no matching region', [
                    'user_id' => $userId,
                    'kvk_city' => $kvkCity,
                ]);
                return;
            }

            // Add/update KvK-verified region
            self::addTrainerToRegion($userId, $region->slug, 'kvk_verified', true);

            // Mark all OTHER self-reported regions as unverified (don't remove them)
            DB::table('gymies_trainer_regions')
                ->where('trainer_user_id', $userId)
                ->where('region_slug', '!=', $region->slug)
                ->where('source', 'self_reported')
                ->update(['verified' => 0, 'updated_at' => now()]);

            Log::info('[LaunchGateService] Synced trainer regions from KvK', [
                'user_id' => $userId,
                'kvk_city' => $kvkCity,
                'region_slug' => $region->slug,
            ]);
        } catch (\Throwable $e) {
            Log::error('[LaunchGateService] syncTrainerRegionsFromKvK failed', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Get region progress for public display (vague indicators, no exact numbers).
     *
     * Returns progress_level: 'early' (<25%), 'growing' (25-50%), 'almost' (50-75%), 'nearly_ready' (>75%)
     * And a human-readable message.
     */
    public static function getRegionProgress(string $regionSlug): array
    {
        self::ensureSchema();

        try {
            $region = DB::table('gymies_launch_regions')
                ->where('slug', $regionSlug)
                ->first();

            if (!$region) {
                return [
                    'progress_level' => 'early',
                    'progress_pct' => 0,
                    'message' => 'Regio nog niet actief',
                    'status' => 'closed',
                ];
            }

            $status = (string) $region->status;
            if ($status === 'open') {
                return [
                    'progress_level' => 'open',
                    'progress_pct' => 100,
                    'message' => 'Regio is live!',
                    'status' => 'open',
                ];
            }

            $minTrainers = (int) $region->min_trainers_to_open;
            $minClients = (int) ($region->min_clients_waitlist ?? 10);
            $readyTrainers = self::countLaunchReadyTrainers($regionSlug);

            // Count waitlisted clients for this region
            $waitlistedClients = DB::table('gymies_waitlist')
                ->where('region_slug', $regionSlug)
                ->where('role', 'client')
                ->where('status', 'waiting')
                ->count();

            // Calculate combined progress (50% trainers, 50% clients)
            $trainerProgress = $minTrainers > 0 ? min(1.0, $readyTrainers / $minTrainers) : 1.0;
            $clientProgress = $minClients > 0 ? min(1.0, $waitlistedClients / $minClients) : 1.0;
            $combinedPct = (int) round(($trainerProgress * 50) + ($clientProgress * 50));

            $level = 'early';
            $message = 'Word een van de eerste in jouw stad!';

            if ($combinedPct >= 75) {
                $level = 'nearly_ready';
                $message = 'Bijna klaar voor launch!';
            } elseif ($combinedPct >= 50) {
                $level = 'almost';
                $message = 'We groeien snel in jouw stad!';
            } elseif ($combinedPct >= 25) {
                $level = 'growing';
                $message = 'Jouw stad is in opbouw!';
            }

            return [
                'progress_level' => $level,
                'progress_pct' => $combinedPct,
                'message' => $message,
                'status' => $status,
            ];
        } catch (\Throwable $e) {
            Log::warning('[LaunchGateService] getRegionProgress failed', [
                'region' => $regionSlug,
                'error' => $e->getMessage(),
            ]);
            return [
                'progress_level' => 'early',
                'progress_pct' => 0,
                'message' => 'Status onbekend',
                'status' => 'closed',
            ];
        }
    }

    /**
     * Evaluate if a region is ready to open.
     *
     * Uses launch-ready trainer count (not just registered) and checks min_clients_waitlist.
     *
     * @return array{ready: bool, trainers: int, ready_trainers: int, clients: int, clients_waitlist: int, ratio: float, bookings_week: int, recommendation: string}
     */
    public static function evaluateRegionReadiness(string $regionSlug): array
    {
        self::ensureSchema();

        try {
            $regionSlug = trim((string) $regionSlug);

            $region = DB::table('gymies_launch_regions')
                ->where('slug', $regionSlug)
                ->first();

            if (!$region) {
                return [
                    'ready' => false,
                    'trainers' => 0,
                    'ready_trainers' => 0,
                    'clients' => 0,
                    'clients_waitlist' => 0,
                    'ratio' => 0,
                    'bookings_week' => 0,
                    'recommendation' => 'Regio niet gevonden',
                ];
            }

            $totalTrainers = (int) $region->trainers_count;
            $readyTrainers = self::countLaunchReadyTrainers($regionSlug);
            $clientsCount = (int) $region->clients_count;
            $minTrainers = (int) $region->min_trainers_to_open;
            $maxRatio = (int) $region->max_client_trainer_ratio;
            $minClients = (int) ($region->min_clients_waitlist ?? 10);
            $bookingsThisWeek = (int) $region->bookings_this_week;

            // Count clients on waitlist
            $clientsWaitlist = DB::table('gymies_waitlist')
                ->where('region_slug', $regionSlug)
                ->where('role', 'client')
                ->where('status', 'waiting')
                ->count();

            $ratio = $readyTrainers > 0 ? $clientsCount / $readyTrainers : 0;

            // All conditions must be met:
            // 1. Enough launch-ready trainers
            // 2. Enough clients interested (waitlist)
            // 3. Ratio not too high
            $trainersOk = $readyTrainers >= $minTrainers;
            $clientsOk = $clientsWaitlist >= $minClients;
            $ratioOk = $ratio <= $maxRatio;

            $ready = $trainersOk && $clientsOk && $ratioOk;

            $recommendations = [];
            if (!$trainersOk) {
                $needed = $minTrainers - $readyTrainers;
                $recommendations[] = "Nog {$needed} launch-ready trainer(s) nodig (geregistreerd: {$totalTrainers}, klaar: {$readyTrainers})";
            }
            if (!$clientsOk) {
                $needed = $minClients - $clientsWaitlist;
                $recommendations[] = "Nog {$needed} klant(en) op wachtlijst nodig ({$clientsWaitlist}/{$minClients})";
            }
            if (!$ratioOk) {
                $recommendations[] = 'Trainer/client ratio te hoog (' . number_format($ratio, 1) . ')';
            }
            $recommendation = $ready
                ? 'Regio klaar voor opening'
                : implode('. ', $recommendations);

            return [
                'ready' => $ready,
                'trainers' => $totalTrainers,
                'ready_trainers' => $readyTrainers,
                'clients' => $clientsCount,
                'clients_waitlist' => $clientsWaitlist,
                'ratio' => round($ratio, 2),
                'bookings_week' => $bookingsThisWeek,
                'recommendation' => $recommendation,
            ];
        } catch (\Throwable $e) {
            Log::error('[LaunchGateService] evaluateRegionReadiness failed', [
                'region' => $regionSlug,
                'error' => $e->getMessage(),
            ]);
            return [
                'ready' => false,
                'trainers' => 0,
                'ready_trainers' => 0,
                'clients' => 0,
                'clients_waitlist' => 0,
                'ratio' => 0,
                'bookings_week' => 0,
                'recommendation' => 'Fout bij evaluatie',
            ];
        }
    }

    /**
     * Update region counters from actual data.
     *
     * Trainers: counted via gymies_trainer_regions (multi-stad aware).
     * Clients: counted from gymies_users + city match OR from gymies_waitlist.
     */
    public static function updateRegionCounters(string $regionSlug): void
    {
        self::ensureSchema();

        try {
            $regionSlug = trim((string) $regionSlug);

            // Get region city for client matching
            $region = DB::table('gymies_launch_regions')
                ->where('slug', $regionSlug)
                ->first();

            if (!$region) return;

            // ── Trainers: from trainer_regions table (accurate multi-stad) ──
            $trainersCount = 0;
            if (Schema::hasTable('gymies_trainer_regions')) {
                $trainersCount = (int) DB::table('gymies_trainer_regions')
                    ->where('region_slug', $regionSlug)
                    ->count();
            } elseif (Schema::hasTable('gymies_trainer_profiles')) {
                // Fallback: city LIKE match
                $trainersCount = (int) DB::table('gymies_trainer_profiles')
                    ->whereRaw('LOWER(city) LIKE ?', [strtolower($region->city) . '%'])
                    ->count();
            }

            // ── Clients: users with matching city ──
            $clientsCount = 0;
            if (Schema::hasTable('gymies_users')) {
                $clientsCount = (int) DB::table('gymies_users')
                    ->whereRaw('LOWER(city) LIKE ?', [strtolower($region->city) . '%'])
                    ->whereIn('role', ['klant', 'client'])
                    ->count();
            }

            // ── Waitlist count ──
            $waitlistCount = (int) DB::table('gymies_waitlist')
                ->where('region_slug', $regionSlug)
                ->where('status', 'waiting')
                ->count();

            // ── Bookings this week (region-scoped via trainer_regions) ──
            $bookingsThisWeek = 0;
            if (Schema::hasTable('gymies_bookings') && Schema::hasTable('gymies_trainer_regions')) {
                $trainerIds = DB::table('gymies_trainer_regions')
                    ->where('region_slug', $regionSlug)
                    ->pluck('trainer_user_id')
                    ->toArray();

                if (!empty($trainerIds)) {
                    $placeholders = implode(',', array_fill(0, count($trainerIds), '?'));
                    $bookingsThisWeek = (int) DB::table('gymies_bookings')
                        ->whereRaw("trainer_user_id IN ($placeholders)", $trainerIds)
                        ->where('scheduled_at', '>=', now()->startOfWeek())
                        ->where('scheduled_at', '<=', now()->endOfWeek())
                        ->count();
                }
            }

            // Update region
            DB::table('gymies_launch_regions')
                ->where('slug', $regionSlug)
                ->update([
                    'trainers_count' => $trainersCount,
                    'clients_count' => $clientsCount,
                    'waitlist_count' => $waitlistCount,
                    'bookings_this_week' => $bookingsThisWeek,
                    'updated_at' => now(),
                ]);

            Log::info('[LaunchGateService] updateRegionCounters completed', [
                'region' => $regionSlug,
                'trainers_total' => $trainersCount,
                'trainers_ready' => self::countLaunchReadyTrainers($regionSlug),
                'clients' => $clientsCount,
                'waitlist' => $waitlistCount,
                'bookings' => $bookingsThisWeek,
            ]);
        } catch (\Throwable $e) {
            Log::error('[LaunchGateService] updateRegionCounters failed', [
                'region' => $regionSlug,
                'error' => $e->getMessage(),
            ]);
        }
    }
}
