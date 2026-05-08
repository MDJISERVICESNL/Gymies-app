<?php

declare(strict_types=1);

namespace App\Services;

use App\Http\Controllers\Gymies\GymiesFeatureFlags;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies Fraud Detection Service
 * ──────────────────────────────
 * Controleert onboarding aanvragen op potentiële fraude.
 *
 * Checks:
 * 1. Duplicate KvK-nummer (al in gebruik door andere trainer) → HARD BLOCK
 * 2. Duplicate IBAN (al in gebruik) → WARNING
 * 3. ID document hash vergelijking (zelfde document = zelfde persoon) → WARNING
 * 4. Verdachte patronen (meerdere registraties, snelle registratie) → WARNING
 * 5. KvK format validatie (8 cijfers, begint niet met 0) → HARD BLOCK
 * 6. IBAN checksum validatie (NL mod97) → HARD BLOCK
 *
 * Respecteert feature flag 'fraud_detection' — als uitgeschakeld, geen checks.
 */
final class FraudDetectionService
{
    /**
     * Voer alle fraud checks uit voor een trainer.
     * Returns array met warnings en hard blocks.
     */
    // Configuratie
    private const MAX_REGISTRATIONS_PER_IP_24H = 3;
    private const KVK_PATTERN = '/^[1-9]\d{7}$/'; // 8 cijfers, begint niet met 0

    public static function check(int $trainerId): array
    {
        // Respecteer feature flag
        if (!GymiesFeatureFlags::isEnabled('fraud_detection')) {
            return ['passed' => true, 'blocks' => [], 'warnings' => [], 'risk_level' => 'none', 'skipped' => true];
        }

        $profile = DB::table('gymies_trainer_profiles')->where('id', $trainerId)->first();
        if (!$profile) {
            return ['passed' => false, 'error' => 'Profiel niet gevonden.'];
        }

        $warnings = [];
        $blocks = [];

        // 1. KvK format validatie (hard block bij ongeldig formaat)
        $kvkFormatResult = self::validateKvkFormat($profile->kvk_number ?? null);
        if ($kvkFormatResult) {
            $blocks[] = $kvkFormatResult;
        }

        // 2. Duplicate KvK (hard block)
        $kvkResult = self::checkDuplicateKvk($trainerId, $profile->kvk_number ?? null);
        if ($kvkResult) {
            $blocks[] = $kvkResult;
        }

        // 3. IBAN checksum validatie (hard block bij ongeldige checksum)
        $ibanValidResult = self::validateIbanChecksum($profile);
        if ($ibanValidResult) {
            $blocks[] = $ibanValidResult;
        }

        // 4. Duplicate IBAN (warning)
        $ibanResult = self::checkDuplicateIban($trainerId, $profile);
        if ($ibanResult) {
            $warnings[] = $ibanResult;
        }

        // 5. Duplicate ID document (warning)
        $idResult = self::checkDuplicateIdDocument($trainerId);
        if ($idResult) {
            $warnings[] = $idResult;
        }

        // 6. Rate limiting: rapid registrations
        $ipResult = self::checkRapidRegistrations($trainerId);
        if ($ipResult) {
            $warnings[] = $ipResult;
        }

        $passed = empty($blocks);

        // Log bij verdachte gevallen
        if (!$passed || !empty($warnings)) {
            self::logFraudAlert($trainerId, $blocks, $warnings);
        }

        return [
            'passed'   => $passed,
            'blocks'   => $blocks,
            'warnings' => $warnings,
            'risk_level' => self::calculateRiskLevel($blocks, $warnings),
        ];
    }

    /**
     * Check duplicate KvK nummer.
     */
    private static function checkDuplicateKvk(int $trainerId, ?string $kvkNumber): ?array
    {
        if (empty($kvkNumber)) return null;

        $duplicate = DB::table('gymies_trainer_profiles')
            ->where('kvk_number', $kvkNumber)
            ->where('id', '!=', $trainerId)
            ->first();

        if ($duplicate) {
            return [
                'type'    => 'duplicate_kvk',
                'message' => 'KvK-nummer is al in gebruik door een andere trainer.',
                'details' => [
                    'kvk_number'       => $kvkNumber,
                    'existing_trainer' => $duplicate->id,
                ],
            ];
        }

        return null;
    }

    /**
     * Valideer KvK-nummer format.
     * Nederlands KvK-nummer: precies 8 cijfers, begint niet met 0.
     */
    private static function validateKvkFormat(?string $kvkNumber): ?array
    {
        if (empty($kvkNumber)) return null; // Nog niet ingevuld, geen block

        // Strip spaties en streepjes
        $clean = preg_replace('/[\s\-]/', '', $kvkNumber);

        if (!preg_match(self::KVK_PATTERN, $clean)) {
            return [
                'type'    => 'invalid_kvk_format',
                'message' => 'KvK-nummer heeft een ongeldig formaat. Verwacht: 8 cijfers, beginnend met 1-9.',
                'details' => [
                    'provided'     => $kvkNumber,
                    'cleaned'      => $clean,
                    'expected_format' => '8 cijfers (bijv. 12345678)',
                ],
            ];
        }

        return null;
    }

    /**
     * Valideer IBAN checksum (ISO 13616 / mod97).
     * Ondersteunt alle IBAN-landen, geoptimaliseerd voor NL (NLxx BANK 0123456789).
     */
    private static function validateIbanChecksum(object $profile): ?array
    {
        // Probeer IBAN uit verschillende velden te halen
        $iban = $profile->iban ?? null;

        // Als er geen directe IBAN is, check payout tabel
        if (empty($iban) && Schema::hasTable('gymies_trainer_payouts')) {
            $userId = $profile->user_id ?? 0;
            $payout = DB::table('gymies_trainer_payouts')
                ->where('trainer_user_id', $userId)
                ->first();
            $iban = $payout->iban ?? null;
        }

        if (empty($iban)) return null; // Nog niet ingevuld

        // Normaliseer: strip spaties, hoofdletters
        $clean = strtoupper(preg_replace('/\s+/', '', $iban));

        // Basischeck: minimaal 15, maximaal 34 karakters, begint met 2 letters + 2 cijfers
        if (!preg_match('/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/', $clean)) {
            return [
                'type'    => 'invalid_iban_format',
                'message' => 'IBAN heeft een ongeldig formaat.',
                'details' => [
                    'provided' => $iban,
                    'expected' => 'bijv. NL91 ABNA 0417 1643 00',
                ],
            ];
        }

        // NL-specifieke lengte check (18 karakters)
        if (str_starts_with($clean, 'NL') && strlen($clean) !== 18) {
            return [
                'type'    => 'invalid_iban_format',
                'message' => 'Nederlands IBAN moet 18 karakters bevatten.',
                'details' => [
                    'provided' => $iban,
                    'length'   => strlen($clean),
                    'expected' => 18,
                ],
            ];
        }

        // Mod97 checksum validatie (ISO 13616)
        if (!self::ibanMod97Check($clean)) {
            return [
                'type'    => 'invalid_iban_checksum',
                'message' => 'IBAN checksum is ongeldig. Controleer of het nummer correct is ingevoerd.',
                'details' => [
                    'provided' => $iban,
                ],
            ];
        }

        return null;
    }

    /**
     * IBAN mod97 controle (ISO 13616).
     * Verplaats landcode + checkdigits naar einde, converteer letters naar cijfers, check mod 97 = 1.
     */
    private static function ibanMod97Check(string $iban): bool
    {
        // Stap 1: verplaats eerste 4 karakters naar einde
        $rearranged = substr($iban, 4) . substr($iban, 0, 4);

        // Stap 2: converteer letters naar cijfers (A=10, B=11, ..., Z=35)
        $numeric = '';
        for ($i = 0, $len = strlen($rearranged); $i < $len; $i++) {
            $char = $rearranged[$i];
            if (ctype_alpha($char)) {
                $numeric .= (string)(ord($char) - ord('A') + 10);
            } else {
                $numeric .= $char;
            }
        }

        // Stap 3: mod 97 via stukjes (te groot voor PHP int)
        $remainder = 0;
        for ($i = 0, $len = strlen($numeric); $i < $len; $i++) {
            $remainder = (int)(($remainder * 10 + (int)$numeric[$i]) % 97);
        }

        return $remainder === 1;
    }

    /**
     * Check duplicate IBAN.
     */
    private static function checkDuplicateIban(int $trainerId, object $profile): ?array
    {
        // Check in payout table als die bestaat
        if (!Schema::hasTable('gymies_trainer_payouts')) return null;

        $userId = $profile->user_id ?? 0;
        $payout = DB::table('gymies_trainer_payouts')
            ->where('trainer_user_id', $userId)
            ->first();

        if (!$payout || empty($payout->iban_last4 ?? null)) return null;

        // Zoek andere trainers met zelfde IBAN last4
        $duplicates = DB::table('gymies_trainer_payouts')
            ->where('iban_last4', $payout->iban_last4)
            ->where('trainer_user_id', '!=', $userId)
            ->count();

        if ($duplicates > 0) {
            return [
                'type'    => 'duplicate_iban',
                'message' => 'IBAN (laatste 4 cijfers) komt overeen met een ander account.',
                'details' => [
                    'iban_last4'      => $payout->iban_last4,
                    'duplicate_count' => $duplicates,
                ],
            ];
        }

        return null;
    }

    /**
     * Check duplicate ID documenten (hash vergelijking).
     */
    private static function checkDuplicateIdDocument(int $trainerId): ?array
    {
        if (!Schema::hasTable('gymies_document_uploads')) return null;

        // Haal trainer's ID document op
        $profile = DB::table('gymies_trainer_profiles')->where('id', $trainerId)->first();
        $userId = $profile->user_id ?? 0;

        $idDoc = DB::table('gymies_document_uploads')
            ->where('user_id', $userId)
            ->where('document_category', 'id_document')
            ->whereNotNull('file_hash')
            ->first();

        if (!$idDoc || empty($idDoc->file_hash)) return null;

        // Zoek duplicates
        $duplicates = DB::table('gymies_document_uploads')
            ->where('file_hash', $idDoc->file_hash)
            ->where('user_id', '!=', $userId)
            ->where('document_category', 'id_document')
            ->count();

        if ($duplicates > 0) {
            return [
                'type'    => 'duplicate_id_document',
                'message' => 'ID document komt overeen met een eerder geüpload document.',
                'details' => [
                    'hash_match_count' => $duplicates,
                ],
            ];
        }

        return null;
    }

    /**
     * Rate limiting: check snelle registraties.
     * 1. Per IP: max registraties per IP in 24u
     * 2. Globaal: ongewoon hoog volume trainer registraties
     * 3. Zelfde e-mail domein: meerdere accounts met zelfde domein
     */
    private static function checkRapidRegistrations(int $trainerId): ?array
    {
        $profile = DB::table('gymies_trainer_profiles')->where('id', $trainerId)->first();
        if (!$profile) return null;

        $userId = $profile->user_id ?? 0;
        $user = DB::table('gymies_users')->where('id', $userId)->first();
        if (!$user) return null;

        $warnings = [];

        // 1. IP-based rate limiting
        $ip = $user->last_login_ip ?? $user->registration_ip ?? request()?->ip();
        if (!empty($ip)) {
            $ipRegistrations = DB::table('gymies_users')
                ->where('role', 'trainer')
                ->where('id', '!=', $userId)
                ->where('created_at', '>=', now()->subHours(24))
                ->where(function ($q) use ($ip) {
                    $q->where('last_login_ip', $ip)
                      ->orWhere('registration_ip', $ip);
                })
                ->count();

            if ($ipRegistrations >= self::MAX_REGISTRATIONS_PER_IP_24H) {
                return [
                    'type'    => 'rate_limit_ip',
                    'message' => "Meer dan " . self::MAX_REGISTRATIONS_PER_IP_24H . " trainer registraties vanaf hetzelfde IP in 24 uur.",
                    'details' => [
                        'ip'         => self::maskIp($ip),
                        'count_24h'  => $ipRegistrations,
                        'threshold'  => self::MAX_REGISTRATIONS_PER_IP_24H,
                    ],
                ];
            }
        }

        // 2. Globaal volume check
        $totalRecent = DB::table('gymies_users')
            ->where('role', 'trainer')
            ->where('id', '!=', $userId)
            ->where('created_at', '>=', now()->subHours(24))
            ->count();

        if ($totalRecent > 10) {
            return [
                'type'    => 'rapid_registrations',
                'message' => 'Ongewoon veel trainer registraties in de afgelopen 24 uur (' . $totalRecent . ').',
                'details' => [
                    'count_24h' => $totalRecent,
                    'threshold' => 10,
                ],
            ];
        }

        // 3. Zelfde e-mail domein check (meerdere accounts met wegwerp-domein)
        $email = $user->email ?? '';
        $domain = substr(strrchr($email, '@'), 1);
        if (!empty($domain) && !in_array($domain, ['gmail.com', 'hotmail.com', 'outlook.com', 'live.nl', 'ziggo.nl', 'kpnmail.nl', 'yahoo.com', 'icloud.com'], true)) {
            $sameDomainCount = DB::table('gymies_users')
                ->where('role', 'trainer')
                ->where('id', '!=', $userId)
                ->where('email', 'like', '%@' . $domain)
                ->where('created_at', '>=', now()->subDays(7))
                ->count();

            if ($sameDomainCount >= 3) {
                return [
                    'type'    => 'suspicious_email_domain',
                    'message' => "Meerdere trainer accounts met hetzelfde e-maildomein ($domain) in de afgelopen 7 dagen.",
                    'details' => [
                        'domain'  => $domain,
                        'count'   => $sameDomainCount,
                    ],
                ];
            }
        }

        return null;
    }

    /**
     * Maskeer IP-adres voor privacy (toon alleen eerste 2 octetten).
     */
    private static function maskIp(string $ip): string
    {
        $parts = explode('.', $ip);
        if (count($parts) === 4) {
            return $parts[0] . '.' . $parts[1] . '.xxx.xxx';
        }
        return 'xxx.xxx.xxx.xxx';
    }

    private static function calculateRiskLevel(array $blocks, array $warnings): string
    {
        if (!empty($blocks)) return 'high';
        if (count($warnings) >= 2) return 'medium';
        if (!empty($warnings)) return 'low';
        return 'none';
    }

    private static function logFraudAlert(int $trainerId, array $blocks, array $warnings): void
    {
        if (Schema::hasTable('gymies_staff_audit_log')) {
            try {
                DB::table('gymies_staff_audit_log')->insert([
                    'staff_id'    => 0, // System
                    'action'      => 'fraud.alert',
                    'target_type' => 'TrainerProfile',
                    'target_id'   => $trainerId,
                    'metadata'    => json_encode([
                        'blocks'     => $blocks,
                        'warnings'   => $warnings,
                        'risk_level' => self::calculateRiskLevel($blocks, $warnings),
                    ]),
                    'ip_address'  => request()?->ip(),
                    'created_at'  => now(),
                    'updated_at'  => now(),
                ]);
            } catch (\Throwable $e) {
                Log::warning('Fraud alert logging mislukt: ' . $e->getMessage());
            }
        }

        Log::warning('Fraud alert voor trainer #' . $trainerId, [
            'blocks'   => $blocks,
            'warnings' => $warnings,
        ]);
    }
}
