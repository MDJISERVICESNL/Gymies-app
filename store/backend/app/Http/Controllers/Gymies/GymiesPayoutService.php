<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies Payout Service — centraal punt voor trainer-saldo mutaties.
 *
 * Fees:
 * - Per boeking: €0,49 platformfee
 * - Maandelijkse uitbetaling: €0,99
 * - Wekelijkse uitbetaling: €1,49
 * - Next-day uitbetaling: €1,99
 * - Minimum uitbetaling: €10,00
 */
final class GymiesPayoutService
{
    // Platform fee per boeking (in centen)
    public const BOOKING_FEE_CENTS = 49;

    // Uitbetaalfees per frequentie (in centen)
    // Maandelijks = gratis (zit in abo), wekelijks = €0,99, volgende dag = €1,49
    public const PAYOUT_FEE_MONTHLY = 0;
    public const PAYOUT_FEE_WEEKLY = 99;
    public const PAYOUT_FEE_DAILY = 149;

    // Minimum saldo voor uitbetaling (in centen)
    public const MINIMUM_PAYOUT_CENTS = 1000;

    /**
     * Zorg dat alle payout-tabellen bestaan.
     */
    public static function ensureSchema(): void
    {
        GymiesSchemaEnsure::trainerPayoutsTable();
        GymiesSchemaEnsure::payoutTransactionsTable();
        GymiesSchemaEnsure::payoutRequestsTable();
    }

    /**
     * Haal het payout-fee bedrag op voor een gegeven frequentie.
     */
    public static function payoutFeeForFrequency(string $frequency): int
    {
        return match ($frequency) {
            'daily' => self::PAYOUT_FEE_DAILY,
            'weekly' => self::PAYOUT_FEE_WEEKLY,
            'monthly' => self::PAYOUT_FEE_MONTHLY,
            default => self::PAYOUT_FEE_MONTHLY,
        };
    }

    /**
     * Na succesvolle betaling: crediteer trainer-saldo (sessieprijs - platformfee).
     * Alleen voor trainers met payout_mode = 'gymies'.
     */
    public static function creditBooking(int $trainerId, int $amountCents, int $bookingId, ?int $clientId = null, ?string $description = null): bool
    {
        if (!self::isGymiesPayout($trainerId)) {
            return false;
        }

        self::ensureSchema();
        self::ensureTrainerRecord($trainerId);

        $netAmount = $amountCents - self::BOOKING_FEE_CENTS;
        if ($netAmount < 0) {
            $netAmount = 0;
        }

        // Zoekbare omschrijving opbouwen
        $bookingDesc = $description ?? self::buildBookingDescription($bookingId, $clientId);
        $feeDesc = "Platformfee €0,49 — sessie #{$bookingId}";

        try {
            DB::beginTransaction();

            // Credit: netto bedrag naar saldo
            DB::table('gymies_payout_transactions')->insert([
                'user_id' => $trainerId,
                'amount_cents' => $netAmount,
                'type' => 'earning',
                'booking_id' => $bookingId,
                'description' => $bookingDesc,
                'status' => 'completed',
                'created_at' => now(),
            ]);

            // Platform fee registreren
            DB::table('gymies_payout_transactions')->insert([
                'user_id' => $trainerId,
                'amount_cents' => -self::BOOKING_FEE_CENTS,
                'type' => 'platform_fee',
                'booking_id' => $bookingId,
                'description' => $feeDesc,
                'status' => 'completed',
                'created_at' => now(),
            ]);

            // Saldo bijwerken
            DB::table('gymies_trainer_payouts')
                ->where('user_id', $trainerId)
                ->increment('balance_cents', $netAmount);

            DB::table('gymies_trainer_payouts')
                ->where('user_id', $trainerId)
                ->increment('total_earned_cents', $netAmount);

            DB::table('gymies_trainer_payouts')
                ->where('user_id', $trainerId)
                ->increment('total_fees_cents', self::BOOKING_FEE_CENTS);

            DB::commit();
            return true;
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('[PayoutService] creditBooking failed', [
                'trainer_id' => $trainerId,
                'amount' => $amountCents,
                'booking_id' => $bookingId,
                'error' => $e->getMessage(),
            ]);
            if (app()->bound('sentry')) {
                app('sentry')->captureException($e);
            }
            return false;
        }
    }

    /**
     * Bij refund: trek bedrag af van trainer-saldo.
     */
    public static function debitRefund(int $trainerId, int $amountCents, int $bookingId, ?string $description = null): bool
    {
        if (!self::isGymiesPayout($trainerId)) {
            return false;
        }

        self::ensureSchema();

        try {
            return DB::transaction(function() use ($trainerId, $amountCents, $bookingId, $description) {
                // Netto refund (we geven ook de platformfee terug intern)
                $refundAmount = $amountCents - self::BOOKING_FEE_CENTS;
                if ($refundAmount < 0) {
                    $refundAmount = 0;
                }

                DB::table('gymies_payout_transactions')->insert([
                    'user_id' => $trainerId,
                    'amount_cents' => -$refundAmount,
                    'type' => 'refund',
                    'booking_id' => $bookingId,
                    'description' => $description ?? "Refund sessie #{$bookingId}",
                    'status' => 'completed',
                    'created_at' => now(),
                ]);

                // Saldo verlagen (minimum 0)
                $current = DB::table('gymies_trainer_payouts')
                    ->where('user_id', $trainerId)
                    ->value('balance_cents') ?? 0;

                $newBalance = max(0, $current - $refundAmount);

                DB::table('gymies_trainer_payouts')
                    ->where('user_id', $trainerId)
                    ->update(['balance_cents' => $newBalance, 'updated_at' => now()]);

                return true;
            });
        } catch (\Throwable $e) {
            Log::error('[PayoutService] debitRefund failed', [
                'trainer_id' => $trainerId,
                'amount' => $amountCents,
                'booking_id' => $bookingId,
                'error' => $e->getMessage(),
            ]);
            if (app()->bound('sentry')) {
                app('sentry')->captureException($e);
            }
            return false;
        }
    }

    /**
     * Penalty bij no-show of overtreding.
     */
    public static function debitPenalty(int $trainerId, int $amountCents, ?int $bookingId = null, ?string $description = null): bool
    {
        if (!self::isGymiesPayout($trainerId)) {
            return false;
        }

        self::ensureSchema();

        try {
            DB::table('gymies_payout_transactions')->insert([
                'user_id' => $trainerId,
                'amount_cents' => -$amountCents,
                'type' => 'penalty',
                'booking_id' => $bookingId,
                'description' => $description ?? 'Boete',
                'status' => 'completed',
                'created_at' => now(),
            ]);

            $current = DB::table('gymies_trainer_payouts')
                ->where('user_id', $trainerId)
                ->value('balance_cents') ?? 0;

            $newBalance = max(0, $current - $amountCents);

            DB::table('gymies_trainer_payouts')
                ->where('user_id', $trainerId)
                ->update(['balance_cents' => $newBalance, 'updated_at' => now()]);

            return true;
        } catch (\Throwable $e) {
            Log::error('[PayoutService] debitPenalty failed', [
                'trainer_id' => $trainerId,
                'error' => $e->getMessage(),
            ]);
            if (app()->bound('sentry')) {
                app('sentry')->captureException($e);
            }
            return false;
        }
    }

    /**
     * Maak een uitbetaalverzoek aan (door trainer of door cron).
     * Checkt minimum saldo en berekent fee.
     *
     * @return array{success: bool, message: string, request_id?: int}
     */
    public static function requestPayout(int $trainerId, ?string $frequencyOverride = null): array
    {
        self::ensureSchema();

        $payout = DB::table('gymies_trainer_payouts')->where('user_id', $trainerId)->first();
        if (!$payout) {
            return ['success' => false, 'message' => 'Geen payout-profiel gevonden.'];
        }

        if ($payout->payout_mode !== 'gymies') {
            return ['success' => false, 'message' => 'Trainer gebruikt eigen Mollie.'];
        }

        if (empty($payout->iban)) {
            return ['success' => false, 'message' => 'Geen IBAN ingesteld. Vul je IBAN in bij Instellingen.'];
        }

        $balance = (int) $payout->balance_cents;
        if ($balance < self::MINIMUM_PAYOUT_CENTS) {
            $min = number_format(self::MINIMUM_PAYOUT_CENTS / 100, 2, ',', '.');
            return ['success' => false, 'message' => "Minimum saldo voor uitbetaling is €{$min}."];
        }

        // Check of er al een pending request is
        $hasPending = DB::table('gymies_payout_requests')
            ->where('user_id', $trainerId)
            ->where('status', 'pending')
            ->exists();

        if ($hasPending) {
            return ['success' => false, 'message' => 'Er staat al een uitbetaling open.'];
        }

        $frequency = $frequencyOverride ?? $payout->payout_frequency;
        $feeCents = self::payoutFeeForFrequency($frequency);
        $netAmount = $balance - $feeCents;

        if ($netAmount <= 0) {
            return ['success' => false, 'message' => 'Saldo te laag na aftrek uitbetaalfee.'];
        }

        // Zoekbare omschrijving opbouwen
        $trainerName = self::resolveUserName($trainerId) ?? "Trainer #{$trainerId}";
        $now = now();
        $payoutDescription = self::buildPayoutDescription($frequency, $now, $trainerName, $netAmount);
        $feeDescription = self::buildFeeDescription($frequency, $now, $feeCents);
        $requestDescription = self::buildRequestReference($frequency, $now, $trainerId);

        try {
            DB::beginTransaction();

            // Payout request aanmaken
            $requestId = DB::table('gymies_payout_requests')->insertGetId([
                'user_id' => $trainerId,
                'amount_cents' => $balance,
                'fee_cents' => $feeCents,
                'net_amount_cents' => $netAmount,
                'iban' => $payout->iban,
                'iban_name' => $payout->iban_name,
                'frequency' => $frequency,
                'status' => 'pending',
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            // Fee transactie
            DB::table('gymies_payout_transactions')->insert([
                'user_id' => $trainerId,
                'amount_cents' => -$feeCents,
                'type' => 'payout_fee',
                'payout_request_id' => $requestId,
                'description' => $feeDescription,
                'status' => 'completed',
                'created_at' => $now,
            ]);

            // Payout transactie
            DB::table('gymies_payout_transactions')->insert([
                'user_id' => $trainerId,
                'amount_cents' => -$netAmount,
                'type' => 'payout',
                'payout_request_id' => $requestId,
                'description' => $payoutDescription,
                'status' => 'pending',
                'created_at' => $now,
            ]);

            // Saldo op 0 zetten
            DB::table('gymies_trainer_payouts')->where('user_id', $trainerId)->update([
                'balance_cents' => 0,
                'total_paid_out_cents' => DB::raw("total_paid_out_cents + {$netAmount}"),
                'total_fees_cents' => DB::raw("total_fees_cents + {$feeCents}"),
                'updated_at' => $now,
            ]);

            DB::commit();

            return [
                'success' => true,
                'message' => 'Uitbetaling aangevraagd.',
                'request_id' => $requestId,
                'reference' => $requestDescription,
                'net_amount' => $netAmount,
            ];
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('[PayoutService] requestPayout failed', [
                'trainer_id' => $trainerId,
                'error' => $e->getMessage(),
            ]);
            if (app()->bound('sentry')) {
                app('sentry')->captureException($e);
            }
            return ['success' => false, 'message' => 'Fout bij aanmaken uitbetaling.'];
        }
    }

    /**
     * Admin markeert een payout als betaald.
     * Genereert een sequentieel factuurnummer (GYM-2026-0001).
     *
     * @return array{success: bool, invoice_number?: string}
     */
    public static function markPaid(int $requestId, ?string $adminNote = null): array
    {
        try {
            $request = DB::table('gymies_payout_requests')->where('id', $requestId)->first();
            if (!$request || $request->status !== 'pending') {
                return ['success' => false];
            }

            $invoiceNumber = self::generateInvoiceNumber();

            DB::table('gymies_payout_requests')->where('id', $requestId)->update([
                'status' => 'paid',
                'paid_at' => now(),
                'admin_note' => $adminNote,
                'invoice_number' => $invoiceNumber,
                'updated_at' => now(),
            ]);

            // Update payout transaction status + beschrijving met factuurnummer
            DB::table('gymies_payout_transactions')
                ->where('payout_request_id', $requestId)
                ->where('type', 'payout')
                ->update([
                    'status' => 'completed',
                    'description' => DB::raw("CONCAT(description, ' [', '{$invoiceNumber}', ']')"),
                ]);

            // Update last_payout_at
            DB::table('gymies_trainer_payouts')
                ->where('user_id', $request->user_id)
                ->update(['last_payout_at' => now(), 'updated_at' => now()]);

            // Genereer self-billing factuur PDF (async-safe, faalt niet als PDF renderer ontbreekt)
            try {
                $invoicePath = GymiesInvoiceGenerator::generate($requestId);
                if ($invoicePath) {
                    DB::table('gymies_payout_requests')->where('id', $requestId)->update([
                        'invoice_path' => $invoicePath,
                    ]);
                }
            } catch (\Throwable $pdfEx) {
                Log::warning('[PayoutService] Invoice PDF generatie gefaald (niet-kritiek)', [
                    'request_id' => $requestId,
                    'error' => $pdfEx->getMessage(),
                ]);
            }

            // Push notificatie naar trainer
            try {
                if (class_exists(FcmPushHelper::class)) {
                    FcmPushHelper::sendToUser((int) $request->user_id, [
                        'title' => 'Uitbetaling ontvangen',
                        'body' => "Factuur {$invoiceNumber} — je uitbetaling is verwerkt.",
                        'data' => ['type' => 'payout_paid', 'invoice_number' => $invoiceNumber],
                    ]);
                }
            } catch (\Throwable $pushEx) {
                // Non-critical
            }

            return ['success' => true, 'invoice_number' => $invoiceNumber];
        } catch (\Throwable $e) {
            Log::error('[PayoutService] markPaid failed', [
                'request_id' => $requestId,
                'error' => $e->getMessage(),
            ]);
            if (app()->bound('sentry')) {
                app('sentry')->captureException($e);
            }
            return ['success' => false];
        }
    }

    /**
     * Genereer het volgende sequentiële factuurnummer.
     * Formaat: GYM-{jaar}-{volgnummer 4 cijfers}
     * Bijv: GYM-2026-0001, GYM-2026-0002, ...
     *
     * Gebruikt DB lock om race conditions te voorkomen.
     */
    private static function generateInvoiceNumber(): string
    {
        $year = now()->format('Y');
        $prefix = "GYM-{$year}-";

        // Zoek het hoogste bestaande nummer dit jaar (met lock)
        $lastInvoice = DB::table('gymies_payout_requests')
            ->where('invoice_number', 'like', "{$prefix}%")
            ->lockForUpdate()
            ->orderByDesc('invoice_number')
            ->value('invoice_number');

        if ($lastInvoice) {
            // Extract het nummer deel: "GYM-2026-0042" → 42
            $lastNumber = (int) substr($lastInvoice, strlen($prefix));
            $nextNumber = $lastNumber + 1;
        } else {
            $nextNumber = 1;
        }

        return $prefix . str_pad((string) $nextNumber, 4, '0', STR_PAD_LEFT);
    }

    /**
     * Trainer-saldo en info ophalen.
     */
    public static function getTrainerPayout(int $trainerId): ?object
    {
        self::ensureSchema();
        self::ensureTrainerRecord($trainerId);

        return DB::table('gymies_trainer_payouts')->where('user_id', $trainerId)->first();
    }

    /**
     * Check of trainer via Gymies uitbetaald wordt (niet eigen Mollie).
     */
    public static function isGymiesPayout(int $trainerId): bool
    {
        if (!Schema::hasTable('gymies_trainer_payouts')) {
            return true; // Default: gymies payout voor nieuwe trainers
        }

        $record = DB::table('gymies_trainer_payouts')->where('user_id', $trainerId)->first();
        if (!$record) {
            return true; // Nog geen record = default gymies
        }

        return $record->payout_mode === 'gymies';
    }

    /**
     * Zorg dat trainer een payout-record heeft.
     */
    private static function ensureTrainerRecord(int $trainerId): void
    {
        $exists = DB::table('gymies_trainer_payouts')->where('user_id', $trainerId)->exists();
        if (!$exists) {
            try {
                DB::table('gymies_trainer_payouts')->insert([
                    'user_id' => $trainerId,
                    'payout_frequency' => 'monthly',
                    'balance_cents' => 0,
                    'payout_mode' => 'gymies',
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            } catch (\Throwable $e) {
                // Duplicate key = al aangemaakt door concurrent request
            }
        }
    }

    /**
     * Transactiegeschiedenis voor trainer (paginated).
     */
    public static function getTransactions(int $trainerId, int $limit = 50, int $offset = 0): array
    {
        self::ensureSchema();

        $rows = DB::table('gymies_payout_transactions')
            ->where('user_id', $trainerId)
            ->orderByDesc('created_at')
            ->offset($offset)
            ->limit($limit)
            ->get();

        return $rows->toArray();
    }

    /**
     * Alle payout requests voor trainer.
     */
    public static function getPayoutRequests(int $trainerId, int $limit = 20): array
    {
        $rows = DB::table('gymies_payout_requests')
            ->where('user_id', $trainerId)
            ->orderByDesc('created_at')
            ->limit($limit)
            ->get();

        return $rows->toArray();
    }

    /**
     * IBAN validatie (NL/BE formaat).
     */
    public static function validateIban(string $iban): bool
    {
        $iban = strtoupper(str_replace(' ', '', trim($iban)));

        // Basis lengte check
        if (strlen($iban) < 15 || strlen($iban) > 34) {
            return false;
        }

        // NL: 18 chars, BE: 16 chars
        if (str_starts_with($iban, 'NL') && strlen($iban) !== 18) {
            return false;
        }
        if (str_starts_with($iban, 'BE') && strlen($iban) !== 16) {
            return false;
        }

        // Mod-97 check (ISO 13616)
        $moved = substr($iban, 4) . substr($iban, 0, 4);
        $numeric = '';
        for ($i = 0; $i < strlen($moved); $i++) {
            $char = $moved[$i];
            if (ctype_alpha($char)) {
                $numeric .= (string) (ord($char) - 55);
            } else {
                $numeric .= $char;
            }
        }

        return bcmod($numeric, '97') === '1';
    }

    // ─── DESCRIPTION HELPERS ─────────────────────────────────────────────

    /**
     * Bouw een zoekbare uitbetaling-omschrijving.
     * Formaat: "Uitbetaling wekelijks, week 22 — €47,50 naar NL91ABNA0417164300"
     */
    private static function buildPayoutDescription(string $frequency, $date, string $trainerName, int $netAmountCents): string
    {
        $freqLabel = self::frequencyLabel($frequency);
        $periodLabel = self::periodLabel($frequency, $date);
        $amount = number_format($netAmountCents / 100, 2, ',', '.');

        return "Uitbetaling {$freqLabel}, {$periodLabel} — €{$amount} aan {$trainerName}";
    }

    /**
     * Bouw een zoekbare fee-omschrijving.
     * Formaat: "Uitbetaalfee wekelijks, week 22 — €1,49"
     */
    private static function buildFeeDescription(string $frequency, $date, int $feeCents): string
    {
        $freqLabel = self::frequencyLabel($frequency);
        $periodLabel = self::periodLabel($frequency, $date);
        $amount = number_format($feeCents / 100, 2, ',', '.');

        return "Uitbetaalfee {$freqLabel}, {$periodLabel} — €{$amount}";
    }

    /**
     * Bouw een unieke referentie voor het payout request.
     * Formaat: "PAY-W22-2026-T{trainerId}" of "PAY-M05-2026-T{trainerId}"
     */
    private static function buildRequestReference(string $frequency, $date, int $trainerId): string
    {
        $year = $date->format('Y');

        return match ($frequency) {
            'weekly' => "PAY-W{$date->format('W')}-{$year}-T{$trainerId}",
            'monthly' => "PAY-M{$date->format('m')}-{$year}-T{$trainerId}",
            'daily' => "PAY-D{$date->format('md')}-{$year}-T{$trainerId}",
            default => "PAY-{$date->format('Ymd')}-T{$trainerId}",
        };
    }

    /**
     * Vertaal frequentie naar leesbaar Nederlands label.
     */
    private static function frequencyLabel(string $frequency): string
    {
        return match ($frequency) {
            'daily' => 'volgende dag',
            'weekly' => 'wekelijks',
            'monthly' => 'maandelijks',
            default => $frequency,
        };
    }

    /**
     * Bouw een periodeaanduiding op basis van frequentie.
     * weekly → "week 22", monthly → "mei 2026", daily → "6 mei 2026"
     */
    private static function periodLabel(string $frequency, $date): string
    {
        $months = [
            1 => 'januari', 2 => 'februari', 3 => 'maart', 4 => 'april',
            5 => 'mei', 6 => 'juni', 7 => 'juli', 8 => 'augustus',
            9 => 'september', 10 => 'oktober', 11 => 'november', 12 => 'december',
        ];

        return match ($frequency) {
            'weekly' => "week {$date->format('W')}",
            'monthly' => $months[(int)$date->format('m')] . ' ' . $date->format('Y'),
            'daily' => (int)$date->format('d') . ' ' . $months[(int)$date->format('m')] . ' ' . $date->format('Y'),
            default => $date->format('d-m-Y'),
        };
    }

    /**
     * Bouw een zoekbare boeking-omschrijving (voor creditBooking).
     * Formaat: "Sessie #123 — PT met Jan Jansen, 6 mei 2026 14:00"
     */
    public static function buildBookingDescription(int $bookingId, ?int $clientId = null): string
    {
        $base = "Sessie #{$bookingId}";

        // Probeer extra info op te halen
        try {
            $booking = DB::table('gymies_bookings')->where('id', $bookingId)->first();
            if (!$booking) {
                return $base;
            }

            $clientName = null;
            if ($clientId) {
                $clientName = self::resolveUserName($clientId);
            } elseif (!empty($booking->user_id)) {
                $clientName = self::resolveUserName((int)$booking->user_id);
            }

            $months = [
                1 => 'jan', 2 => 'feb', 3 => 'mrt', 4 => 'apr',
                5 => 'mei', 6 => 'jun', 7 => 'jul', 8 => 'aug',
                9 => 'sep', 10 => 'okt', 11 => 'nov', 12 => 'dec',
            ];

            $dateStr = '';
            if (!empty($booking->start_time)) {
                $dt = \Carbon\Carbon::parse($booking->start_time);
                $day = (int)$dt->format('d');
                $month = $months[(int)$dt->format('m')];
                $year = $dt->format('Y');
                $time = $dt->format('H:i');
                $dateStr = ", {$day} {$month} {$year} {$time}";
            }

            $clientPart = $clientName ? " met {$clientName}" : '';

            return "{$base} — PT{$clientPart}{$dateStr}";
        } catch (\Throwable $e) {
            return $base;
        }
    }

    /**
     * Resolve een gebruikersnaam vanuit users tabel.
     */
    private static function resolveUserName(int $userId): ?string
    {
        try {
            $user = DB::table('users')->where('id', $userId)->first(['name', 'first_name', 'last_name']);
            if (!$user) {
                return null;
            }

            if (!empty($user->first_name)) {
                $name = trim($user->first_name . ' ' . ($user->last_name ?? ''));
                return $name ?: null;
            }

            return $user->name ?: null;
        } catch (\Throwable $e) {
            return null;
        }
    }
}
