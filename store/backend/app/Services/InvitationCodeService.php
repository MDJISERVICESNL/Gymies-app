<?php

declare(strict_types=1);

namespace App\Services;

use App\Http\Controllers\Gymies\GymiesFeatureFlags;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Carbon\Carbon;

/**
 * Gymies Invitation Code Service
 * ───────────────────────────────
 * Beheert uitnodigingscodes voor de soft launch.
 *
 * Code types:
 * - staff:    Handmatig aangemaakt door medewerkers
 * - referral: Automatisch gegenereerd voor actieve trainers
 * - promo:    Marketing campagnes
 * - partner:  Samenwerkingspartners (gyms, etc.)
 *
 * Feature flag 'require_invitation_code' bepaalt of codes verplicht zijn.
 */
final class InvitationCodeService
{
    private const TABLE = 'gymies_invitation_codes';
    private const CODE_LENGTH = 8;
    private const CODE_PREFIX = 'GYM-';
    private const REFERRAL_PREFIX = 'REF-';
    private const MAX_REFERRAL_CODES_DEFAULT = 5;
    private const DEFAULT_EXPIRY_DAYS = 90;

    /**
     * Check of uitnodigingscodes verplicht zijn (feature flag).
     */
    public static function isRequired(): bool
    {
        return GymiesFeatureFlags::isEnabled('require_invitation_code');
    }

    /**
     * Genereer een nieuwe uitnodigingscode.
     */
    public static function generate(
        int $createdBy,
        string $source = 'staff',
        int $maxUses = 1,
        ?int $expiryDays = null,
        ?int $referredByTrainerId = null
    ): array {
        if (!Schema::hasTable(self::TABLE)) {
            return ['success' => false, 'error' => 'Invitation codes tabel bestaat niet.'];
        }

        $prefix = $source === 'referral' ? self::REFERRAL_PREFIX : self::CODE_PREFIX;
        $code = self::generateUniqueCode($prefix);
        $expiresAt = Carbon::now()->addDays($expiryDays ?? self::DEFAULT_EXPIRY_DAYS);

        try {
            $id = DB::table(self::TABLE)->insertGetId([
                'code'                   => $code,
                'source'                 => $source,
                'max_uses'               => $maxUses,
                'used_count'             => 0,
                'created_by'             => $createdBy,
                'referred_by_trainer_id' => $referredByTrainerId,
                'expires_at'             => $expiresAt,
                'is_active'              => true,
                'created_at'             => now(),
                'updated_at'             => now(),
            ]);

            return [
                'success'    => true,
                'code'       => $code,
                'id'         => $id,
                'expires_at' => $expiresAt->toIso8601String(),
            ];
        } catch (\Throwable $e) {
            Log::error('InvitationCodeService@generate FAILED', ['error' => $e->getMessage()]);
            return ['success' => false, 'error' => 'Code aanmaken mislukt.'];
        }
    }

    /**
     * Valideer een code (zonder te verbruiken).
     */
    public static function validate(string $code): array
    {
        if (!Schema::hasTable(self::TABLE)) {
            // Als tabel niet bestaat en codes niet verplicht, is alles ok
            return self::isRequired()
                ? ['valid' => false, 'error' => 'Systeem niet beschikbaar.']
                : ['valid' => true, 'reason' => 'codes_not_required'];
        }

        if (!self::isRequired()) {
            return ['valid' => true, 'reason' => 'codes_not_required'];
        }

        $record = DB::table(self::TABLE)
            ->where('code', strtoupper(trim($code)))
            ->first();

        if (!$record) {
            return ['valid' => false, 'error' => 'Ongeldige uitnodigingscode.'];
        }

        if (!$record->is_active) {
            return ['valid' => false, 'error' => 'Deze code is gedeactiveerd.'];
        }

        if ($record->expires_at && Carbon::parse($record->expires_at)->isPast()) {
            return ['valid' => false, 'error' => 'Deze code is verlopen.'];
        }

        if ($record->used_count >= $record->max_uses) {
            return ['valid' => false, 'error' => 'Deze code is al volledig gebruikt.'];
        }

        return [
            'valid'  => true,
            'code'   => $record->code,
            'source' => $record->source,
            'referred_by_trainer_id' => $record->referred_by_trainer_id,
        ];
    }

    /**
     * Gebruik een code (verhoog used_count).
     * Moet worden aangeroepen bij succesvolle registratie.
     */
    public static function redeem(string $code, int $trainerId): array
    {
        if (!Schema::hasTable(self::TABLE)) {
            return self::isRequired()
                ? ['success' => false, 'error' => 'Systeem niet beschikbaar.']
                : ['success' => true, 'reason' => 'codes_not_required'];
        }

        if (!self::isRequired()) {
            return ['success' => true, 'reason' => 'codes_not_required'];
        }

        $validation = self::validate($code);
        if (!($validation['valid'] ?? false)) {
            return ['success' => false, 'error' => $validation['error'] ?? 'Ongeldige code.'];
        }

        $upperCode = strtoupper(trim($code));

        DB::beginTransaction();
        try {
            // Atomic increment
            $affected = DB::table(self::TABLE)
                ->where('code', $upperCode)
                ->where('is_active', true)
                ->whereRaw('used_count < max_uses')
                ->increment('used_count');

            if ($affected === 0) {
                DB::rollBack();
                return ['success' => false, 'error' => 'Code kon niet worden ingewisseld (race condition of al gebruikt).'];
            }

            // Sla op welke code de trainer heeft gebruikt
            if (Schema::hasColumn('gymies_trainer_profiles', 'invitation_code_used')) {
                DB::table('gymies_trainer_profiles')
                    ->where('id', $trainerId)
                    ->update([
                        'invitation_code_used' => $upperCode,
                        'updated_at' => now(),
                    ]);
            }

            DB::commit();
            return ['success' => true, 'code' => $upperCode];
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('InvitationCodeService@redeem FAILED', ['error' => $e->getMessage()]);
            return ['success' => false, 'error' => 'Code inwisselen mislukt.'];
        }
    }

    /**
     * Genereer referral code voor een actieve trainer.
     */
    public static function generateReferralCode(int $trainerId): array
    {
        if (!Schema::hasTable(self::TABLE)) {
            return ['success' => false, 'error' => 'Tabel niet beschikbaar.'];
        }

        // Check limiet
        $existing = DB::table(self::TABLE)
            ->where('referred_by_trainer_id', $trainerId)
            ->where('is_active', true)
            ->count();

        $maxCodes = GymiesFeatureFlags::getInt('max_referral_codes_per_trainer', self::MAX_REFERRAL_CODES_DEFAULT);
        if ($existing >= $maxCodes) {
            return ['success' => false, 'error' => 'Maximum aantal referral codes bereikt (' . $maxCodes . ').'];
        }

        // Haal user_id op voor created_by
        $profile = DB::table('gymies_trainer_profiles')->where('id', $trainerId)->first();
        $userId = $profile->user_id ?? $trainerId;

        return self::generate(
            createdBy: (int) $userId,
            source: 'referral',
            maxUses: 1,
            expiryDays: 60,
            referredByTrainerId: $trainerId
        );
    }

    /**
     * Deactiveer een code.
     */
    public static function deactivate(int $codeId, int $staffId): array
    {
        if (!Schema::hasTable(self::TABLE)) {
            return ['success' => false, 'error' => 'Tabel niet beschikbaar.'];
        }

        $affected = DB::table(self::TABLE)
            ->where('id', $codeId)
            ->update(['is_active' => false, 'updated_at' => now()]);

        if ($affected > 0) {
            // Audit
            if (Schema::hasTable('gymies_staff_audit_log')) {
                DB::table('gymies_staff_audit_log')->insert([
                    'staff_id'    => $staffId,
                    'action'      => 'code.deactivated',
                    'target_type' => 'InvitationCode',
                    'target_id'   => $codeId,
                    'ip_address'  => request()?->ip(),
                    'created_at'  => now(),
                    'updated_at'  => now(),
                ]);
            }
        }

        return ['success' => $affected > 0];
    }

    /**
     * Lijst alle codes (voor staff dashboard).
     */
    public static function list(int $page = 1, int $perPage = 25, ?string $source = null): array
    {
        if (!Schema::hasTable(self::TABLE)) {
            return ['data' => [], 'total' => 0];
        }

        $query = DB::table(self::TABLE)->orderByDesc('created_at');

        if ($source) {
            $query->where('source', $source);
        }

        $total = $query->count();
        $data = $query->offset(($page - 1) * $perPage)->limit($perPage)->get();

        return ['data' => $data, 'total' => $total, 'page' => $page, 'per_page' => $perPage];
    }

    // ─── Private Helpers ─────────────────────────────────────────

    private static function generateUniqueCode(string $prefix): string
    {
        $maxAttempts = 10;
        for ($i = 0; $i < $maxAttempts; $i++) {
            $code = $prefix . strtoupper(Str::random(self::CODE_LENGTH));
            $exists = DB::table(self::TABLE)->where('code', $code)->exists();
            if (!$exists) {
                return $code;
            }
        }
        // Fallback met timestamp
        return $prefix . strtoupper(Str::random(self::CODE_LENGTH)) . '-' . time();
    }
}
