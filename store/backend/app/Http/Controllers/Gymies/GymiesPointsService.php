<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * GymiesPointsService
 *
 * Gymies Points systeem: toekenen van punten voor acties (referrals, sessies),
 * inzien van saldo/history, en besteding van punten voor beloningen.
 *
 * Database-tabellen:
 * - gymies_points_rules: regels (event_type, points_awarded, conditions_json, is_active)
 * - gymies_points_ledger: transactie-log (user_id, delta, event_type, ref_id, ref_table, description)
 * - gymies_points_redemptions: beloningen (user_id, reward_type, reward_cents, status, created_at)
 * - gymies_users: kolom 'gymies_points' (huidig saldo)
 */
final class GymiesPointsService
{
    /**
     * Ken punten toe aan een gebruiker voor een event.
     * Idempotent: als (user_id, event_type, ref_id, ref_table) al bestaat → return false (geen dubbele toekenning).
     *
     * @param int $userId
     * @param string $eventType (bijv. 'referral_signup', 'referral_first_session', 'referral_milestone_5x5')
     * @param int|null $refId (bijv. booking_id, user_id)
     * @param string|null $refTable (bijv. 'gymies_bookings', 'gymies_users')
     * @param string|null $description (optioneel; voor audit trail)
     * @return bool true als punten zijn toegekend, false als al eerder toegekend of rule niet actief
     */
    public static function award(
        int $userId,
        string $eventType,
        ?int $refId = null,
        ?string $refTable = null,
        ?string $description = null
    ): bool {
        if (!Schema::hasTable('gymies_points_rules') || !Schema::hasTable('gymies_points_ledger')) {
            return false;
        }

        // Haal de rule op
        $rule = self::getRule($eventType);
        if (!$rule || !(bool) ($rule->is_active ?? false) || ((int) ($rule->points_awarded ?? 0)) === 0) {
            return false;
        }

        // B27: TOCTOU-fix — idempotentie-check + write in één atomische transactie met lock.
        // Zonder lock konden twee gelijktijdige requests beide de check passeren en dubbel punten toekennen.
        $delta = (int) $rule->points_awarded;
        $success = DB::transaction(function () use ($userId, $eventType, $refId, $refTable, $description, $delta) {
            // Vergrendel de gebruikersrij zodat geen enkel ander process punten kan bijschrijven
            // voordat wij klaar zijn met de idempotentie-check én de ledger-insert.
            DB::table('gymies_users')->where('id', $userId)->lockForUpdate()->value('id');

            // Controleer opnieuw ná de lock of de entry al bestaat.
            $existing = DB::table('gymies_points_ledger')
                ->where('user_id', $userId)
                ->where('event_type', $eventType)
                ->when($refId !== null, fn ($q) => $q->where('ref_id', $refId))
                ->when($refId === null, fn ($q) => $q->whereNull('ref_id'))
                ->when($refTable !== null, fn ($q) => $q->where('ref_table', $refTable))
                ->when($refTable === null, fn ($q) => $q->whereNull('ref_table'))
                ->exists();

            if ($existing) {
                return false; // Al eerder toegekend — ook concurrente poging geblokkeerd
            }

            return self::writeLedgerLocked(
                $userId,
                $delta,
                $eventType,
                $refId,
                $refTable,
                $description ?? "Punten toegekend voor {$eventType}"
            );
        });

        if ($success && in_array($eventType, ['referral_signup', 'referral_first_session', 'referral_session_milestone'])) {
            // Controleer milestone voor referral events
            self::checkMilestone5x5($userId);
        }

        return $success;
    }

    /**
     * Geef het huidige punten-saldo van een gebruiker.
     *
     * @param int $userId
     * @return int saldo (nooit onder 0)
     */
    public static function getBalance(int $userId): int
    {
        if (!Schema::hasTable('gymies_users') || !Schema::hasColumn('gymies_users', 'gymies_points')) {
            return 0;
        }

        $balance = DB::table('gymies_users')
            ->where('id', $userId)
            ->value('gymies_points');

        return max(0, (int) ($balance ?? 0));
    }

    /**
     * Geef de laatste N transacties van een gebruiker.
     *
     * @param int $userId
     * @param int $limit
     * @return array[] transacties [id, user_id, delta, balance_after, event_type, description, ref_id, ref_table, created_at]
     */
    public static function getLedger(int $userId, int $limit = 20): array
    {
        if (!Schema::hasTable('gymies_points_ledger')) {
            return [];
        }

        return DB::table('gymies_points_ledger')
            ->where('user_id', $userId)
            ->orderByDesc('created_at')
            ->limit($limit)
            ->get(['id', 'user_id', 'delta', 'balance_after', 'event_type', 'description', 'ref_id', 'ref_table', 'created_at'])
            ->map(fn ($row) => [
                'id' => (int) $row->id,
                'user_id' => (int) $row->user_id,
                'delta' => (int) $row->delta,
                'balance_after' => (int) $row->balance_after,
                'event_type' => (string) $row->event_type,
                'description' => $row->description ? (string) $row->description : null,
                'ref_id' => $row->ref_id ? (int) $row->ref_id : null,
                'ref_table' => $row->ref_table ? (string) $row->ref_table : null,
                'created_at' => $row->created_at,
            ])
            ->all();
    }

    /**
     * Check of een referrer de grote 5x5 milestone heeft bereikt.
     * Zo ja → ken de milestone bonus toe (eenmalig).
     * Geeft true terug als milestone NET is bereikt en beloond.
     *
     * @param int $referrerUserId
     * @return bool true als milestone net bereikt; false als al bereikt of niet bereikt
     */
    public static function checkMilestone5x5(int $referrerUserId): bool
    {
        if (!Schema::hasTable('gymies_points_rules') || !Schema::hasTable('gymies_points_ledger') || !Schema::hasTable('gymies_referrals')) {
            return false;
        }

        // Haal rule op
        $rule = self::getRule('referral_milestone_5x5');
        if (!$rule || !(bool) ($rule->is_active ?? false)) {
            return false;
        }

        // Haal conditions op: required_referrals, sessions_per_referral
        $conditions = is_string($rule->conditions_json)
            ? json_decode($rule->conditions_json, true) ?? []
            : (array) $rule->conditions_json;

        $requiredReferrals = (int) ($conditions['required_referrals'] ?? 5);
        $sessionsPerReferral = (int) ($conditions['sessions_per_referral'] ?? 5);

        // Check: al eerder beloond?
        $alreadyAwarded = DB::table('gymies_points_ledger')
            ->where('user_id', $referrerUserId)
            ->where('event_type', 'referral_milestone_5x5')
            ->exists();

        if ($alreadyAwarded) {
            return false;
        }

        // Tel referrals die de threshold hebben bereikt
        $qualifiedReferrals = DB::table('gymies_referrals as r')
            ->where('r.referrer_user_id', $referrerUserId)
            ->where('r.status', 'completed')
            ->leftJoin('gymies_bookings as b', 'b.client_user_id', '=', 'r.referred_user_id')
            ->where('b.status', 'completed')
            ->groupBy('r.id')
            ->havingRaw('COUNT(b.id) >= ?', [$sessionsPerReferral])
            ->selectRaw('r.id')
            ->count();

        if ($qualifiedReferrals < $requiredReferrals) {
            return false; // Milestone nog niet bereikt
        }

        // Milestone bereikt! Ken punten toe + maak redemption aan
        $bonusPoints = (int) ($rule->points_awarded ?? 0);
        $bonusCents = (int) ($conditions['bonus_cents'] ?? 0);

        DB::beginTransaction();
        try {
            // Award punten
            self::writeLedger(
                $referrerUserId,
                $bonusPoints,
                'referral_milestone_5x5',
                null,
                null,
                "5x5 Referral Milestone beloond: {$requiredReferrals} verwezen gebruikers met {$sessionsPerReferral} sessies elk"
            );

            // Maak redemption aan (session credit pending)
            if ($bonusCents > 0 && Schema::hasTable('gymies_points_redemptions')) {
                DB::table('gymies_points_redemptions')->insert([
                    'user_id' => $referrerUserId,
                    'reward_type' => 'session_credit',
                    'reward_cents' => $bonusCents,
                    'status' => 'pending',
                    'description' => '5x5 Referral Milestone bonus',
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            DB::commit();
            return true;
        } catch (\Throwable $e) {
            DB::rollBack();
            if (function_exists('logger')) {
                logger()->error('GymiesPointsService::checkMilestone5x5 failed', [
                    'referrer_user_id' => $referrerUserId,
                    'error' => $e->getMessage(),
                ]);
            }
            return false;
        }
    }

    /**
     * Besteed punten voor een beloning.
     * Controleert: heeft de user genoeg punten? Is het reward type geldig?
     *
     * @param int $userId
     * @param string $rewardType ('session_credit', 'free_session', enz.)
     * @param int $pointsToSpend
     * @return array ['ok' => bool, 'redemption_id' => int|null, 'message' => string]
     */
    public static function redeem(
        int $userId,
        string $rewardType,
        int $pointsToSpend
    ): array {
        if ($pointsToSpend <= 0) {
            return [
                'ok' => false,
                'redemption_id' => null,
                'message' => 'Punten moeten groter zijn dan 0.',
            ];
        }

        if (!Schema::hasTable('gymies_points_redemptions')) {
            return [
                'ok' => false,
                'redemption_id' => null,
                'message' => 'Beloningen zijn op dit moment niet beschikbaar.',
            ];
        }

        // Haal configuratie op (points_session_credit_cents)
        $pointsSessionCreditCents = (int) (DB::table('gymies_settings')
            ->where('key', 'points_session_credit_cents')
            ->value('value') ?? 500); // Standaard: 100 punten = €5

        // P-FIX-PTS-2: Sanity-check conversion rate before applying
        $maxReasonableRate = 10000; // Max: 100 points = €100 (1 euro per point)
        $minReasonableRate = 1;     // Min: 1 point = €0.01
        if ($pointsSessionCreditCents < $minReasonableRate || $pointsSessionCreditCents > $maxReasonableRate) {
            if (function_exists('logger')) {
                logger()->critical('Points conversion rate outside safe bounds', [
                    'rate' => $pointsSessionCreditCents,
                    'changed_by' => auth()->id(),
                ]);
            }
            return [
                'ok' => false,
                'redemption_id' => null,
                'message' => 'Punten-conversie tarief is ongeldig. Neem contact op met support.',
            ];
        }

        // P-FIX-PTS-1: Integer arithmetic to avoid float precision loss
        $rewardCents = intdiv($pointsToSpend * $pointsSessionCreditCents, 100);

        // Valideer reward type vooraf (geen DB nodig)
        $validTypes = ['session_credit', 'free_session'];
        if (!in_array($rewardType, $validTypes, true)) {
            return [
                'ok' => false,
                'redemption_id' => null,
                'message' => "Beloningstype '{$rewardType}' is ongeldig.",
            ];
        }

        DB::beginTransaction();
        try {
            // B33: TOCTOU-fix — controleer saldo BINNEN transactie met lockForUpdate.
            // Zonder lock konden twee gelijktijdige verzoeken beiden de check doorstaan en
            // het saldo negatief maken.
            $balance = (int) (DB::table('gymies_users')
                ->where('id', $userId)
                ->lockForUpdate()
                ->value('gymies_points') ?? 0);

            if ($balance < $pointsToSpend) {
                DB::rollBack();
                return [
                    'ok' => false,
                    'redemption_id' => null,
                    'message' => "Je hebt niet genoeg punten. Huidig saldo: {$balance}.",
                ];
            }

            // Maak redemption aan
            $redemptionId = DB::table('gymies_points_redemptions')->insertGetId([
                'user_id' => $userId,
                'reward_type' => $rewardType,
                'reward_cents' => $rewardCents,
                'status' => 'pending',
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // Schrijf naar ledger (negatief delta)
            self::writeLedger(
                $userId,
                -$pointsToSpend,
                'redemption_' . $rewardType,
                (int) $redemptionId,
                'gymies_points_redemptions',
                "Punten besteed voor {$rewardType}"
            );

            DB::commit();

            return [
                'ok' => true,
                'redemption_id' => (int) $redemptionId,
                'message' => "Succesvolle besteding van {$pointsToSpend} punten. Je ontvangt {$rewardCents} cents korting.",
            ];
        } catch (\Throwable $e) {
            DB::rollBack();
            if (function_exists('logger')) {
                logger()->error('GymiesPointsService::redeem failed', [
                    'user_id' => $userId,
                    'reward_type' => $rewardType,
                    'error' => $e->getMessage(),
                ]);
            }
            return [
                'ok' => false,
                'redemption_id' => null,
                'message' => 'Er is een fout opgetreden bij het verwerken van je aanvraag.',
            ];
        }
    }

    /**
     * Haal de configuratie van een punten-regel op uit gymies_points_rules.
     *
     * @param string $eventType
     * @return object|null regel met velden: id, event_type, points_awarded, conditions_json, is_active, created_at
     */
    public static function getRule(string $eventType): ?object
    {
        if (!Schema::hasTable('gymies_points_rules')) {
            return null;
        }

        return DB::table('gymies_points_rules')
            ->where('event_type', $eventType)
            ->first();
    }

    /**
     * Variant van writeLedger die al binnen een actieve transactie met lock draait.
     * Geen eigen DB::transaction wrapper — de caller is verantwoordelijk voor de transactie.
     */
    private static function writeLedgerLocked(
        int $userId,
        int $delta,
        string $eventType,
        ?int $refId,
        ?string $refTable,
        string $description
    ): bool {
        if (!Schema::hasTable('gymies_points_ledger') || !Schema::hasTable('gymies_users')) {
            return false;
        }

        try {
            // Huidig saldo is al gelocked door de caller — we lezen het opnieuw.
            $currentBalance = (int) (DB::table('gymies_users')
                ->where('id', $userId)
                ->value('gymies_points') ?? 0);

            $balanceAfter = max(0, $currentBalance + $delta);

            DB::table('gymies_points_ledger')->insert([
                'user_id' => $userId,
                'delta' => $delta,
                'balance_after' => $balanceAfter,
                'event_type' => $eventType,
                'ref_id' => $refId,
                'ref_table' => $refTable,
                'description' => $description,
                'created_at' => now(),
            ]);

            DB::table('gymies_users')
                ->where('id', $userId)
                ->update([
                    'gymies_points' => $balanceAfter,
                    'updated_at' => now(),
                ]);

            return true;
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('GymiesPointsService::writeLedgerLocked failed', [
                    'user_id' => $userId,
                    'delta' => $delta,
                    'error' => $e->getMessage(),
                ]);
            }
            return false;
        }
    }

    /**
     * Interne helper: schrijf naar ledger + update gymies_users.gymies_points.
     * Gebruikt DB::transaction voor atomiciteit.
     *
     * @param int $userId
     * @param int $delta (positief of negatief)
     * @param string $eventType
     * @param int|null $refId
     * @param string|null $refTable
     * @param string $description
     * @return bool true bij succes
     */
    private static function writeLedger(
        int $userId,
        int $delta,
        string $eventType,
        ?int $refId,
        ?string $refTable,
        string $description
    ): bool {
        if (!Schema::hasTable('gymies_points_ledger') || !Schema::hasTable('gymies_users')) {
            return false;
        }

        try {
            return DB::transaction(function () use ($userId, $delta, $eventType, $refId, $refTable, $description) {
                // Haal huidig saldo op (met lock voor race condition prevention)
                $currentBalance = (int) (DB::table('gymies_users')
                    ->where('id', $userId)
                    ->lockForUpdate()
                    ->value('gymies_points') ?? 0);

                // Bereken nieuwe saldo (nooit onder 0)
                $balanceAfter = max(0, $currentBalance + $delta);

                // INSERT into ledger
                DB::table('gymies_points_ledger')->insert([
                    'user_id' => $userId,
                    'delta' => $delta,
                    'balance_after' => $balanceAfter,
                    'event_type' => $eventType,
                    'ref_id' => $refId,
                    'ref_table' => $refTable,
                    'description' => $description,
                    'created_at' => now(),
                ]);

                // UPDATE user saldo
                DB::table('gymies_users')
                    ->where('id', $userId)
                    ->update([
                        'gymies_points' => $balanceAfter,
                        'updated_at' => now(),
                    ]);

                return true;
            });
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('GymiesPointsService::writeLedger failed', [
                    'user_id' => $userId,
                    'delta' => $delta,
                    'error' => $e->getMessage(),
                ]);
            }
            return false;
        }
    }
}
