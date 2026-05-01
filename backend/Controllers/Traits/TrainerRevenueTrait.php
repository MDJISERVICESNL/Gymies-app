<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies\Traits;

use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trainer revenue and payout management trait.
 * Extracts revenue tracking, forecast, and payout processing functionality.
 */
trait TrainerRevenueTrait
{
    private const PAYOUT_FEE_PERCENT = [
        'weekly' => 1.5,
        'biweekly' => 1.0,
        'monthly' => 0.0,
    ];

    public function revenue(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $trainerId = (int) $user->id;
        $statusFilter = strtolower(trim((string) $request->query('status', '')));
        $allowedFilters = ['paid', 'cash', 'open', 'cancelled'];
        if ($statusFilter !== '' && !in_array($statusFilter, $allowedFilters, true)) {
            return response()->json(['message' => 'Ongeldige statusfilter. Gebruik paid, cash, open of cancelled.'], 422);
        }

        $bookingSelect = ['id', 'scheduled_at', 'status', 'amount_cents', 'paid_at'];
        if (Schema::hasColumn('gymies_bookings', 'payment_method')) {
            $bookingSelect[] = 'payment_method';
        }

        $rows = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereNotNull('amount_cents')
            ->orderByDesc('scheduled_at')
            ->limit(250)
            ->get($bookingSelect);

        $bookingIds = $rows->pluck('id')->map(fn ($id) => (int) $id)->all();
        $latestTxByBooking = [];
        if (!empty($bookingIds) && Schema::hasTable('gymies_payment_transactions')) {
            $latestIds = DB::table('gymies_payment_transactions')
                ->whereIn('booking_id', $bookingIds)
                ->selectRaw('MAX(id) as id')
                ->groupBy('booking_id')
                ->pluck('id')
                ->map(fn ($id) => (int) $id)
                ->all();
            if (!empty($latestIds)) {
                $latestTxByBooking = DB::table('gymies_payment_transactions')
                    ->whereIn('id', $latestIds)
                    ->get(['booking_id', 'status', 'payment_method', 'provider', 'provider_transaction_id', 'paid_at', 'amount_cents'])
                    ->keyBy(fn ($r) => (int) $r->booking_id)
                    ->all();
            }
        }

        $items = [];
        $totalRevenue = 0;
        $paidRevenue = 0;
        $pendingPayout = 0;
        $monthly = [];

        foreach ($rows as $r) {
            $bookingId = (int) $r->id;
            $tx = $latestTxByBooking[$bookingId] ?? null;
            $storedPaymentMethod = $tx ? (string) ($tx->payment_method ?? '') : (string) ($r->payment_method ?? '');
            $provider = $tx ? (string) ($tx->provider ?? '') : '';
            $paymentMethod = $this->toCanonicalPaymentMethod($storedPaymentMethod, $provider);
            $rawStatus = $tx ? (string) ($tx->status ?? '') : (!empty($r->paid_at) ? 'paid' : 'pending');
            $paymentStatus = $this->toCanonicalPaymentStatus($rawStatus, $paymentMethod, (string) ($r->status ?? ''));
            if ($statusFilter !== '' && $paymentStatus !== $statusFilter) {
                continue;
            }

            $amountCents = (int) ($tx->amount_cents ?? $r->amount_cents ?? 0);
            $paidAt = $tx && !empty($tx->paid_at) ? $tx->paid_at : ($r->paid_at ?? null);
            $paymentReference = $tx ? (string) ($tx->provider_transaction_id ?? '') : null;

            if ($paymentStatus !== 'cancelled') {
                $totalRevenue += $amountCents;
            }
            if (in_array($paymentStatus, ['paid', 'cash'], true)) {
                $paidRevenue += $amountCents;
            }
            if ($paymentStatus === 'open') {
                $pendingPayout += $amountCents;
            }
            if (!empty($r->scheduled_at) && $paymentStatus !== 'cancelled') {
                $monthKey = substr((string) $r->scheduled_at, 0, 7);
                $monthly[$monthKey] = ($monthly[$monthKey] ?? 0) + $amountCents;
            }

            $items[] = [
                'id' => (string) $bookingId,
                'booking_id' => (string) $bookingId,
                'scheduled_at' => $r->scheduled_at,
                'amount_cents' => $amountCents,
                'status' => (string) ($r->status ?? ''),
                'payment_status' => $paymentStatus,
                'payment_method' => $paymentMethod,
                'payment_reference' => $paymentReference !== '' ? $paymentReference : null,
                'paid_at' => $paidAt,
            ];
        }

        return response()->json([
            'data' => [
                'total_revenue_cents' => $totalRevenue,
                'paid_revenue_cents' => $paidRevenue,
                'pending_payout_cents' => $pendingPayout,
                'monthly_revenue_cents' => $monthly,
                'items' => $items,
            ],
        ]);
    }

    /**
     * Omzet-voorspeller (Pro/Studio): geplande sessies deze maand + churn-proxy uit sleeping wallets.
     * Starter krijgt 403 of lege payload met upgrade hint.
     */
    public function revenueForecast(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        if (!$this->trainerCanEditPackages($trainerId)) {
            return response()->json([
                'data' => [
                    'available' => false,
                    'message' => 'Omzet-voorspeller is beschikbaar vanaf Pro. Upgrade om vooruit te kijken.',
                ],
            ]);
        }
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => ['available' => true, 'forecast_cents' => 0, 'message' => 'Geen boekingen.']]);
        }

        $now = CarbonImmutable::now();
        $monthStart = $now->startOfMonth();
        $monthEnd = $now->endOfMonth();
        $prevStart = $monthStart->subMonth();
        $prevEnd = $monthStart->subSecond();

        $statuses = ['confirmed', 'pending', 'completed', 'reserved', 'no_show'];
        $splitDeduct = [];
        $sumMonth = function (CarbonImmutable $from, CarbonImmutable $to, bool $onlyCompleted = false) use ($trainerId, $statuses, &$splitDeduct): int {
            $q = DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerId)
                ->whereNotNull('amount_cents')
                ->where('scheduled_at', '>=', $from->toDateTimeString())
                ->where('scheduled_at', '<=', $to->toDateTimeString());
            if ($onlyCompleted) {
                $q->whereIn('status', ['confirmed', 'completed', 'no_show']);
            } else {
                $q->whereIn('status', $statuses);
            }
            $rows = $q->get(['id', 'amount_cents', 'status']);
            if ($rows->isEmpty()) {
                return 0;
            }
            $ids = $rows->pluck('id')->all();
            if (!empty($ids) && Schema::hasTable('gymies_admin_refunds')) {
                $splitDeduct = DB::table('gymies_admin_refunds')
                    ->where('type', 'split')
                    ->whereIn('booking_id', $ids)
                    ->pluck('amount_cents', 'booking_id')
                    ->map(fn ($c) => (int) $c)
                    ->all();
            } else {
                $splitDeduct = [];
            }
            $sum = 0;
            foreach ($rows as $r) {
                if ($onlyCompleted && !in_array((string) $r->status, ['confirmed', 'completed', 'no_show'], true)) {
                    continue;
                }
                $sum += (int) ($r->amount_cents ?? 0) - ($splitDeduct[(int) $r->id] ?? 0);
            }
            return max($sum, 0);
        };

        $forecastCents = $sumMonth($monthStart, $monthEnd, false);
        $realizedPrevCents = $sumMonth($prevStart, $prevEnd, true);

        // Churn-proxy: klanten met resterende strippen-sessies maar 14d niet geboekt × gem. sessiewaarde
        $sleepingCount = 0;
        if (Schema::hasTable('gymies_packages') && Schema::hasColumn('gymies_bookings', 'package_id')) {
            $cutoff = $now->subDays(14)->toDateTimeString();
            $packages = DB::table('gymies_packages')->where('trainer_user_id', $trainerId)->get(['id', 'sessions_count']);
            if (!$packages->isEmpty()) {
                $clientIds = DB::table('gymies_bookings')
                    ->where('trainer_user_id', $trainerId)
                    ->distinct()
                    ->pluck('client_user_id')
                    ->filter()
                    ->unique()
                    ->values()
                    ->all();
                $bookingCountPrev = DB::table('gymies_bookings')
                    ->where('trainer_user_id', $trainerId)
                    ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                    ->where('scheduled_at', '>=', $prevStart->toDateTimeString())
                    ->where('scheduled_at', '<=', $prevEnd->toDateTimeString())
                    ->count();
                $avgPrev = $bookingCountPrev > 0 ? (int) round($realizedPrevCents / $bookingCountPrev) : 0;
                foreach ($clientIds as $cid) {
                    $remainingTotal = 0;
                    foreach ($packages as $pkg) {
                        $sessionsCount = (int) ($pkg->sessions_count ?? 0);
                        if ($sessionsCount <= 0) {
                            continue;
                        }
                        $used = (int) DB::table('gymies_bookings')
                            ->where('client_user_id', $cid)
                            ->where('package_id', (int) $pkg->id)
                            ->whereNotIn('status', ['cancelled'])
                            ->count();
                        $remainingTotal += max(0, $sessionsCount - $used);
                    }
                    if ($remainingTotal < 1) {
                        continue;
                    }
                    $lastBooking = DB::table('gymies_bookings')
                        ->where('client_user_id', $cid)
                        ->where('trainer_user_id', $trainerId)
                        ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                        ->orderByDesc('scheduled_at')
                        ->value('scheduled_at');
                    if ($lastBooking !== null && (string) $lastBooking >= $cutoff) {
                        continue;
                    }
                    $sleepingCount++;
                }
                if ($sleepingCount > 0 && $avgPrev > 0) {
                    $churnRisk = (int) round($sleepingCount * $avgPrev * 0.3);
                    $forecastCents = max($forecastCents - $churnRisk, 0);
                }
            }
        }

        $growthPercent = null;
        if ($realizedPrevCents > 0) {
            $growthPercent = (int) round(($forecastCents - $realizedPrevCents) / $realizedPrevCents * 100);
        }

        $monthNamesNl = [
            1 => 'januari', 2 => 'februari', 3 => 'maart', 4 => 'april',
            5 => 'mei', 6 => 'juni', 7 => 'juli', 8 => 'augustus',
            9 => 'september', 10 => 'oktober', 11 => 'november', 12 => 'december',
        ];
        $monthName = $monthNamesNl[(int) $now->format('n')] ?? $now->format('F');
        $euro = number_format($forecastCents / 100, 0, ',', '.');
        $growthText = $growthPercent === null
            ? 'Nog geen vergelijking mogelijk (vorige maand leeg).'
            : ($growthPercent >= 0
                ? "Op schema voor +{$growthPercent}% groei t.o.v. vorige maand."
                : "{$growthPercent}% t.o.v. vorige maand; focus op retentie.");

        $message = "Verwachte omzet {$monthName}: €{$euro},- ({$growthText})";

        return response()->json([
            'data' => [
                'available' => true,
                'forecast_cents' => $forecastCents,
                'realized_previous_month_cents' => $realizedPrevCents,
                'growth_percent_vs_previous' => $growthPercent,
                'sleeping_clients_count' => $sleepingCount,
                'month_label' => $monthName,
                'message' => $message,
            ],
        ]);
    }

    /**
     * Fee Switcher alleen (geen volledige bankpayload nodig).
     */
    public function updateFeePreference(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        if (!Schema::hasTable('gymies_trainer_bank_accounts')
            || !Schema::hasColumn('gymies_trainer_bank_accounts', 'client_pays_service_fee')) {
            return response()->json(['message' => 'Niet beschikbaar op deze omgeving. Voer de SQL-migratie uit.'], 422);
        }
        $request->validate(['client_pays_service_fee' => 'required|boolean']);
        $trainerId = (int) $user->id;
        $exists = DB::table('gymies_trainer_bank_accounts')->where('trainer_user_id', $trainerId)->exists();
        if (!$exists) {
            return response()->json([
                'message' => 'Stel eerst je uitbetalingsgegevens in (IBAN e.d.); daarna kun je de fee-optie wisselen.',
            ], 422);
        }
        DB::table('gymies_trainer_bank_accounts')
            ->where('trainer_user_id', $trainerId)
            ->update([
                'client_pays_service_fee' => $request->boolean('client_pays_service_fee') ? 1 : 0,
                'updated_at' => now(),
            ]);

        return response()->json(['data' => $this->readPayoutSettings($trainerId)]);
    }

    public function payoutSettings(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        return response()->json([
            'data' => $this->readPayoutSettings((int) $user->id),
        ]);
    }

    public function updatePayoutSettings(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $request->validate([
            'account_holder_first_name' => 'required|string|max:120',
            'account_holder_last_name' => 'required|string|max:120',
            'iban' => 'nullable|string|min:8|max:34',
            'payout_frequency' => 'required|in:weekly,biweekly,monthly',
            'minimum_payout_cents' => 'nullable|integer|min:0|max:100000000',
            'notify_payout_paid' => 'nullable|boolean',
            'notify_payout_failed' => 'nullable|boolean',
            // Fee Switcher: true = klant betaalt toeslag bovenop tarief; false = trainer neemt in marge.
            'client_pays_service_fee' => 'nullable|boolean',
        ]);

        if (!DB::getSchemaBuilder()->hasTable('gymies_trainer_bank_accounts')) {
            return response()->json(['message' => 'Bankrekening tabel ontbreekt op deze omgeving.'], 422);
        }

        $trainerId = (int) $user->id;
        $existing = DB::table('gymies_trainer_bank_accounts')
            ->where('trainer_user_id', $trainerId)
            ->first();

        $firstName = trim((string) $request->input('account_holder_first_name'));
        $lastName = trim((string) $request->input('account_holder_last_name'));
        $holderName = trim($firstName . ' ' . $lastName);
        $ibanRawInput = trim((string) $request->input('iban', ''));
        $ibanRaw = strtoupper(preg_replace('/\s+/', '', $ibanRawInput));
        if ($ibanRaw !== '' && !$this->looksLikeIban($ibanRaw)) {
            return response()->json(['message' => 'Ongeldig IBAN-formaat.'], 422);
        }
        if ($ibanRaw === '' && !$existing) {
            return response()->json(['message' => 'IBAN is verplicht.'], 422);
        }
        $frequency = (string) $request->input('payout_frequency');
        $minimum = (int) $request->input('minimum_payout_cents', 0);
        $now = now();

        $payload = [
            'trainer_user_id' => $trainerId,
            'account_holder_name' => $holderName,
            'account_holder_first_name' => $firstName,
            'account_holder_last_name' => $lastName,
            'iban_masked' => $ibanRaw !== '' ? $this->maskIban($ibanRaw) : ($existing->iban_masked ?? ''),
            'iban_last4' => $ibanRaw !== '' ? substr($ibanRaw, -4) : ($existing->iban_last4 ?? null),
            'payout_frequency' => $frequency,
            'minimum_payout_cents' => $minimum,
            'notify_payout_paid' => $request->boolean('notify_payout_paid', true),
            'notify_payout_failed' => $request->boolean('notify_payout_failed', true),
            'status' => 'pending',
            'updated_at' => $now,
        ];
        if (Schema::hasColumn('gymies_trainer_bank_accounts', 'client_pays_service_fee')) {
            $payload['client_pays_service_fee'] = $request->boolean('client_pays_service_fee', true) ? 1 : 0;
        }

        if ($existing) {
            DB::table('gymies_trainer_bank_accounts')
                ->where('trainer_user_id', $trainerId)
                ->update($payload);
        } else {
            $payload['created_at'] = $now;
            DB::table('gymies_trainer_bank_accounts')->insert($payload);
        }

        return response()->json([
            'data' => $this->readPayoutSettings($trainerId),
        ]);
    }

    public function payoutPreview(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $trainerId = (int) $user->id;
        $settings = $this->readPayoutSettings($trainerId);
        $totals = $this->trainerRevenueTotals($trainerId);
        $preview = $this->buildPayoutPreview($totals['pending_payout_cents'], $settings);

        return response()->json([
            'data' => $preview,
        ]);
    }

    public function payoutCalendar(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $trainerId = (int) $user->id;
        $settings = $this->readPayoutSettings($trainerId);
        $totals = $this->trainerRevenueTotals($trainerId);
        $preview = $this->buildPayoutPreview($totals['pending_payout_cents'], $settings);
        $dates = $this->nextPayoutDates((string) ($settings['payout_frequency'] ?? 'monthly'), 3);

        $data = array_map(fn (string $date) => [
            'date' => $date,
            'is_eligible' => (bool) $preview['is_eligible'],
            'remaining_to_minimum_cents' => (int) $preview['remaining_to_minimum_cents'],
        ], $dates);

        return response()->json(['data' => $data]);
    }

    public function payoutHistory(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        if (!DB::getSchemaBuilder()->hasTable('gymies_payouts')) {
            return response()->json(['data' => []]);
        }

        $rows = DB::table('gymies_payouts')
            ->where('trainer_user_id', $user->id)
            ->orderByDesc('id')
            ->limit(100)
            ->get([
                'id',
                'amount_cents',
                'gross_cents',
                'fee_cents',
                'payout_frequency',
                'status',
                'reference',
                'requested_at',
                'paid_at',
                'created_at',
            ]);

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'amount_cents' => (int) ($r->amount_cents ?? 0),
            'gross_cents' => (int) ($r->gross_cents ?? $r->amount_cents ?? 0),
            'fee_cents' => (int) ($r->fee_cents ?? 0),
            'payout_frequency' => $r->payout_frequency ?: 'monthly',
            'status' => $r->status ?? 'pending',
            'reference' => $r->reference,
            'requested_at' => $r->requested_at ?? $r->created_at,
            'paid_at' => $r->paid_at,
        ])->all();

        return response()->json(['data' => $data]);
    }

    /**
     * @deprecated Payouts verlopen nu volledig via Mollie Connect (application fees + automatic splits).
     * Dit endpoint is behouden zodat oudere app-versies niet crashen (410 Gone).
     */
    public function requestPayoutNow(Request $request): JsonResponse
    {
        return response()->json([
            'message' => 'Handmatige uitbetalingen zijn niet meer beschikbaar. Alle betalingen worden automatisch via Mollie Connect verwerkt.',
        ], 410);
    }

    public function revenueExport(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $trainerId = (int) $user->id;
        $bookingRows = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereNotNull('amount_cents')
            ->orderByDesc('scheduled_at')
            ->limit(1000)
            ->get(['id', 'scheduled_at', 'status', 'amount_cents', 'paid_at']);

        $payoutRows = DB::getSchemaBuilder()->hasTable('gymies_payouts')
            ? DB::table('gymies_payouts')
                ->where('trainer_user_id', $trainerId)
                ->orderByDesc('id')
                ->limit(1000)
                ->get([
                    'id',
                    'amount_cents',
                    'gross_cents',
                    'fee_cents',
                    'payout_frequency',
                    'status',
                    'reference',
                    'requested_at',
                    'paid_at',
                ])
            : collect();

        $lines = [];
        $lines[] = 'section,id,scheduled_at,status,amount_cents,paid_at,reference,gross_cents,fee_cents,payout_frequency,requested_at';
        foreach ($bookingRows as $b) {
            $lines[] = implode(',', [
                'income',
                $this->csvCell((string) $b->id),
                $this->csvCell((string) ($b->scheduled_at ?? '')),
                $this->csvCell((string) ($b->status ?? '')),
                (string) ((int) ($b->amount_cents ?? 0)),
                $this->csvCell((string) ($b->paid_at ?? '')),
                '',
                '',
                '',
                '',
                '',
            ]);
        }
        foreach ($payoutRows as $p) {
            $lines[] = implode(',', [
                'payout',
                $this->csvCell((string) $p->id),
                '',
                $this->csvCell((string) ($p->status ?? '')),
                (string) ((int) ($p->amount_cents ?? 0)),
                $this->csvCell((string) ($p->paid_at ?? '')),
                $this->csvCell((string) ($p->reference ?? '')),
                (string) ((int) ($p->gross_cents ?? 0)),
                (string) ((int) ($p->fee_cents ?? 0)),
                $this->csvCell((string) ($p->payout_frequency ?? '')),
                $this->csvCell((string) ($p->requested_at ?? '')),
            ]);
        }

        return response()->json([
            'data' => [
                'generated_at' => now()->toIso8601String(),
                'csv' => implode("\n", $lines),
                'income_count' => $bookingRows->count(),
                'payout_count' => $payoutRows->count(),
            ],
        ]);
    }

    private function toCanonicalPaymentMethod(string $storedMethod, string $provider): string
    {
        $m = strtolower(trim($storedMethod));
        $p = strtolower(trim($provider));
        if ($m === 'cash' || $p === 'cash') {
            return 'cash';
        }
        return 'mollie';
    }

    private function toCanonicalPaymentStatus(string $rawStatus, string $paymentMethod, string $bookingStatus): string
    {
        $raw = strtolower(trim($rawStatus));
        $booking = strtolower(trim($bookingStatus));
        if ($paymentMethod === 'cash' && in_array($raw, ['paid', 'cash', 'paid_cash'], true)) {
            return 'cash';
        }
        if (in_array($raw, ['paid', 'mollie_paid', 'paid_mollie'], true)) {
            return 'paid';
        }
        if (in_array($raw, ['failed', 'expired', 'cancelled', 'canceled'], true) || $booking === 'cancelled') {
            return 'cancelled';
        }
        if (in_array($raw, ['pending', 'open', 'awaiting_cash', 'unpaid', ''], true)) {
            return 'open';
        }
        return 'open';
    }

    /**
     * @return array<string,mixed>
     */
    private function readPayoutSettings(int $trainerId): array
    {
        if (!DB::getSchemaBuilder()->hasTable('gymies_trainer_bank_accounts')) {
            return $this->defaultPayoutSettings();
        }

        $row = DB::table('gymies_trainer_bank_accounts')
            ->where('trainer_user_id', $trainerId)
            ->first();
        if (!$row) {
            return $this->defaultPayoutSettings();
        }

        $frequency = in_array($row->payout_frequency ?? null, ['weekly', 'biweekly', 'monthly'], true)
            ? (string) $row->payout_frequency
            : 'monthly';

        $out = [
            'account_holder_first_name' => (string) ($row->account_holder_first_name ?? ''),
            'account_holder_last_name' => (string) ($row->account_holder_last_name ?? ''),
            'account_holder_name' => (string) ($row->account_holder_name ?? ''),
            'iban_masked' => (string) ($row->iban_masked ?? ''),
            'iban_last4' => (string) ($row->iban_last4 ?? ''),
            'bank_verification_status' => (string) ($row->status ?? 'pending'),
            'payout_frequency' => $frequency,
            'payout_fee_percent' => $this->payoutFeePercent($frequency),
            'minimum_payout_cents' => (int) ($row->minimum_payout_cents ?? 0),
            'notify_payout_paid' => (bool) ($row->notify_payout_paid ?? true),
            'notify_payout_failed' => (bool) ($row->notify_payout_failed ?? true),
            'next_payout_date' => $this->nextPayoutDate($frequency),
            'updated_at' => $row->updated_at ?? null,
        ];
        if (Schema::hasColumn('gymies_trainer_bank_accounts', 'client_pays_service_fee')) {
            $out['client_pays_service_fee'] = (bool) (int) ($row->client_pays_service_fee ?? 1);
        } else {
            $out['client_pays_service_fee'] = true;
        }
        return $out;
    }

    /**
     * @return array<string,mixed>
     */
    private function defaultPayoutSettings(): array
    {
        $frequency = 'monthly';

        return [
            'account_holder_first_name' => '',
            'account_holder_last_name' => '',
            'account_holder_name' => '',
            'iban_masked' => '',
            'iban_last4' => '',
            'bank_verification_status' => 'pending',
            'payout_frequency' => $frequency,
            'payout_fee_percent' => $this->payoutFeePercent($frequency),
            'minimum_payout_cents' => 0,
            'notify_payout_paid' => true,
            'notify_payout_failed' => true,
            'next_payout_date' => $this->nextPayoutDate($frequency),
            'updated_at' => null,
            'client_pays_service_fee' => true,
        ];
    }

    /**
     * @return array<string,int>
     */
    private function trainerRevenueTotals(int $trainerId): array
    {
        $rows = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereNotNull('amount_cents')
            ->get(['id', 'status', 'amount_cents', 'paid_at']);

        $revenueBookingIds = $rows->whereIn('status', ['confirmed', 'completed', 'no_show'])->pluck('id')->all();
        $splitDeduct = [];
        if (!empty($revenueBookingIds) && Schema::hasTable('gymies_admin_refunds')) {
            $splitDeduct = DB::table('gymies_admin_refunds')
                ->where('type', 'split')
                ->whereIn('booking_id', $revenueBookingIds)
                ->pluck('amount_cents', 'booking_id')
                ->map(fn ($c) => (int) $c)
                ->all();
        }

        $total = 0;
        foreach ($rows as $r) {
            if (!in_array((string) $r->status, ['confirmed', 'completed', 'no_show'], true)) {
                continue;
            }
            $amt = (int) ($r->amount_cents ?? 0);
            $total += $amt - ($splitDeduct[(int) $r->id] ?? 0);
        }
        $paid = (int) $rows->whereNotNull('paid_at')->sum('amount_cents');
        $pending = max($total - $paid, 0);
        if (Schema::hasColumn('gymies_users', 'trainer_balance_cents')) {
            $balance = (int) (DB::table('gymies_users')->where('id', $trainerId)->value('trainer_balance_cents') ?? 0);
            if ($balance < 0) {
                $pending = max(0, $pending + $balance);
            }
        }

        return [
            'total_revenue_cents' => $total,
            'paid_revenue_cents' => $paid,
            'pending_payout_cents' => $pending,
        ];
    }

    /**
     * @param array<string,mixed> $settings
     * @return array<string,mixed>
     */
    private function buildPayoutPreview(int $pendingPayoutCents, array $settings): array
    {
        $frequency = (string) ($settings['payout_frequency'] ?? 'monthly');
        $minimum = (int) ($settings['minimum_payout_cents'] ?? 0);
        $feePercent = $this->payoutFeePercent($frequency);
        $feeCents = (int) round($pendingPayoutCents * ($feePercent / 100));
        $netCents = max($pendingPayoutCents - $feeCents, 0);
        $isEligible = $pendingPayoutCents >= $minimum;

        return [
            'gross_cents' => $pendingPayoutCents,
            'fee_cents' => $feeCents,
            'net_cents' => $netCents,
            'fee_percent' => $feePercent,
            'is_eligible' => $isEligible,
            'minimum_payout_cents' => $minimum,
            'remaining_to_minimum_cents' => $isEligible ? 0 : ($minimum - $pendingPayoutCents),
            'next_payout_date' => $this->nextPayoutDate($frequency),
        ];
    }

    private function payoutFeePercent(string $frequency): float
    {
        return self::PAYOUT_FEE_PERCENT[$frequency] ?? 0.0;
    }

    private function looksLikeIban(string $iban): bool
    {
        return (bool) preg_match('/^[A-Z]{2}[0-9A-Z]{6,32}$/', $iban);
    }

    private function maskIban(string $iban): string
    {
        $len = strlen($iban);
        if ($len <= 4) {
            return $iban;
        }
        $start = substr($iban, 0, 4);
        $end = substr($iban, -4);
        $mask = str_repeat('*', max($len - 8, 4));

        return $start . $mask . $end;
    }

    private function nextPayoutDate(string $frequency): string
    {
        $today = CarbonImmutable::now()->startOfDay();

        if ($frequency === 'weekly') {
            return $today->next('monday')->toDateString();
        }

        if ($frequency === 'biweekly') {
            $anchor = CarbonImmutable::create(2025, 1, 6, 0, 0, 0); // maandag
            $candidate = $today->next('monday');
            $weeksFromAnchor = (int) floor($anchor->diffInDays($candidate, false) / 7);
            if ($weeksFromAnchor % 2 !== 0) {
                $candidate = $candidate->addWeek();
            }
            return $candidate->toDateString();
        }

        return $today->addMonthNoOverflow()->startOfMonth()->toDateString();
    }

    /**
     * @return list<string>
     */
    private function nextPayoutDates(string $frequency, int $count): array
    {
        $dates = [];
        $cursor = CarbonImmutable::now()->startOfDay();
        for ($i = 0; $i < $count; $i++) {
            if ($frequency === 'weekly') {
                $cursor = $cursor->next('monday');
            } elseif ($frequency === 'biweekly') {
                $anchor = CarbonImmutable::create(2025, 1, 6, 0, 0, 0);
                $candidate = $cursor->next('monday');
                $weeksFromAnchor = (int) floor($anchor->diffInDays($candidate, false) / 7);
                if ($weeksFromAnchor % 2 !== 0) {
                    $candidate = $candidate->addWeek();
                }
                $cursor = $candidate;
            } else {
                $cursor = $cursor->addMonthNoOverflow()->startOfMonth();
            }
            $dates[] = $cursor->toDateString();
        }

        return $dates;
    }

    private function csvCell(string $value): string
    {
        $escaped = str_replace('"', '""', $value);
        return '"' . $escaped . '"';
    }
}
