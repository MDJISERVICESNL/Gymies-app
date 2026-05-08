<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * Trainer Payout endpoints:
 * GET  payout/balance       — huidig saldo + info
 * GET  payout/transactions  — transactiegeschiedenis
 * GET  payout/requests      — uitbetaalverzoeken
 * GET  payout/fees          — fee-overzicht
 * POST payout/request       — uitbetaling aanvragen
 * PUT  payout/settings      — IBAN + frequency wijzigen
 * PUT  payout/mode          — switch naar eigen Mollie of terug naar Gymies
 *
 * AUDIT LOGGING ADDED:
 * - Payout requests
 * - IBAN/settings changes
 * - Payout mode changes
 */
class GymiesPayoutController
{
    use GymiesAuditTrait;
    /**
     * GET payout/balance — huidig saldo, IBAN, frequency, modus.
     */
    public function balance(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainerId = (int) $user->id;
        $payout = GymiesPayoutService::getTrainerPayout($trainerId);

        if (!$payout) {
            return response()->json(['message' => 'Payout profiel niet gevonden.'], 404);
        }

        return response()->json([
            'balance_cents' => (int) $payout->balance_cents,
            'balance_formatted' => '€' . number_format((int) $payout->balance_cents / 100, 2, ',', '.'),
            'iban' => $payout->iban,
            'iban_name' => $payout->iban_name,
            'payout_frequency' => $payout->payout_frequency,
            'payout_mode' => $payout->payout_mode,
            'total_earned_cents' => (int) $payout->total_earned_cents,
            'total_paid_out_cents' => (int) $payout->total_paid_out_cents,
            'total_fees_cents' => (int) $payout->total_fees_cents,
            'last_payout_at' => $payout->last_payout_at,
            'minimum_payout_cents' => GymiesPayoutService::MINIMUM_PAYOUT_CENTS,
            'can_request_payout' => (int) $payout->balance_cents >= GymiesPayoutService::MINIMUM_PAYOUT_CENTS
                && !empty($payout->iban)
                && $payout->payout_mode === 'gymies',
        ]);
    }

    /**
     * GET payout/transactions — transactiegeschiedenis.
     */
    public function transactions(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $limit = min(100, max(1, (int) ($request->query('limit') ?? 50)));
        $offset = max(0, (int) ($request->query('offset') ?? 0));

        $transactions = GymiesPayoutService::getTransactions((int) $user->id, $limit, $offset);

        return response()->json([
            'transactions' => array_map(function ($tx) {
                return [
                    'id' => $tx->id,
                    'amount_cents' => (int) $tx->amount_cents,
                    'amount_formatted' => ($tx->amount_cents >= 0 ? '+' : '') . '€' . number_format(abs((int) $tx->amount_cents) / 100, 2, ',', '.'),
                    'type' => $tx->type,
                    'description' => $tx->description,
                    'status' => $tx->status,
                    'booking_id' => $tx->booking_id,
                    'created_at' => $tx->created_at,
                ];
            }, $transactions),
            'limit' => $limit,
            'offset' => $offset,
        ]);
    }

    /**
     * GET payout/requests — uitbetaalverzoeken.
     */
    public function requests(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $requests = GymiesPayoutService::getPayoutRequests((int) $user->id);

        return response()->json([
            'requests' => array_map(function ($r) {
                return [
                    'id' => $r->id,
                    'amount_cents' => (int) $r->amount_cents,
                    'fee_cents' => (int) $r->fee_cents,
                    'net_amount_cents' => (int) $r->net_amount_cents,
                    'net_formatted' => '€' . number_format((int) $r->net_amount_cents / 100, 2, ',', '.'),
                    'iban' => $r->iban,
                    'frequency' => $r->frequency,
                    'status' => $r->status,
                    'paid_at' => $r->paid_at,
                    'created_at' => $r->created_at,
                ];
            }, $requests),
        ]);
    }

    /**
     * GET payout/fees — fee-overzicht zodat Flutter dit kan tonen.
     */
    public function fees(Request $request): JsonResponse
    {
        return response()->json([
            'booking_fee_cents' => GymiesPayoutService::BOOKING_FEE_CENTS,
            'booking_fee_formatted' => '€0,49',
            'payout_fees' => [
                'monthly' => [
                    'cents' => GymiesPayoutService::PAYOUT_FEE_MONTHLY,
                    'formatted' => 'Gratis',
                    'label' => 'Maandelijks (1e van de maand)',
                ],
                'weekly' => [
                    'cents' => GymiesPayoutService::PAYOUT_FEE_WEEKLY,
                    'formatted' => '€0,99',
                    'label' => 'Wekelijks (elke vrijdag)',
                ],
                'daily' => [
                    'cents' => GymiesPayoutService::PAYOUT_FEE_DAILY,
                    'formatted' => '€1,49',
                    'label' => 'Volgende dag (on demand)',
                ],
            ],
            'minimum_payout_cents' => GymiesPayoutService::MINIMUM_PAYOUT_CENTS,
            'minimum_payout_formatted' => '€10,00',
        ]);
    }

    /**
     * POST payout/request — uitbetaling aanvragen.
     *
     * BUG FIX: Verify balance at time of processing, not just at request time.
     * Prevents edge case where balance changes between UI check and actual request.
     */
    public function requestPayout(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainerId = (int) $user->id;
        $frequency = $request->input('frequency'); // optioneel override (bijv. 'daily' voor next-day)

        // BUG FIX: Verify balance again at request time with lock
        GymiesPayoutService::ensureSchema();
        $payout = DB::table('gymies_trainer_payouts')
            ->where('user_id', $trainerId)
            ->lockForUpdate()
            ->first(['balance_cents']);

        if (!$payout || (int) ($payout->balance_cents ?? 0) < GymiesPayoutService::MINIMUM_PAYOUT_CENTS) {
            return response()->json([
                'success' => false,
                'message' => 'Onvoldoende saldo voor uitbetaling (minimum €10,00).',
            ], 422);
        }

        // BUG-003: Add try-catch for Mollie API and transaction errors
        try {
            $result = GymiesPayoutService::requestPayout($trainerId, $frequency);
            $status = $result['success'] ? 200 : 422;

            // Log payout request
            if ($result['success']) {
                $payoutAmount = (int) ($payout->balance_cents ?? 0);
                $this->auditLog($trainerId, 'payout.request.created', 'Payout', (int) ($result['payout_id'] ?? 0), [
                    'amount_cents' => $payoutAmount,
                    'frequency' => $frequency,
                ], (string) ($request->ip() ?? 'unknown'));
                Log::info('Payout request created', ['user_id' => $trainerId, 'amount_cents' => $payoutAmount]);
            } else {
                Log::warning('Payout request failed', ['user_id' => $trainerId, 'error' => $result['message'] ?? 'unknown']);
            }

            return response()->json($result, $status);
        } catch (\Throwable $e) {
            Log::error('Payout request failed', [
                'user_id' => $trainerId,
                'error' => $e->getMessage(),
            ]);
            $this->auditLog($trainerId, 'payout.request.error', 'Payout', 0, ['error' => $e->getMessage()], (string) ($request->ip() ?? 'unknown'));
            return response()->json([
                'success' => false,
                'message' => 'Er is een fout opgetreden bij het aanvragen van uitbetaling. Probeer later opnieuw.',
            ], 500);
        }
    }

    /**
     * PUT payout/settings — IBAN + frequency wijzigen.
     */
    public function updateSettings(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainerId = (int) $user->id;
        GymiesPayoutService::ensureSchema();

        // Ensure record exists
        GymiesPayoutService::getTrainerPayout($trainerId);

        $updates = [];

        // IBAN
        $iban = $request->input('iban');
        if ($iban !== null) {
            $iban = strtoupper(str_replace(' ', '', trim($iban)));
            if ($iban !== '' && !GymiesPayoutService::validateIban($iban)) {
                return response()->json(['message' => 'Ongeldig IBAN-nummer. Controleer je invoer.'], 422);
            }
            $updates['iban'] = $iban ?: null;
        }

        // IBAN naam
        $ibanName = $request->input('iban_name');
        if ($ibanName !== null) {
            $updates['iban_name'] = trim($ibanName) ?: null;
        }

        // Frequency
        $frequency = $request->input('payout_frequency');
        if ($frequency !== null && in_array($frequency, ['monthly', 'weekly', 'daily'], true)) {
            $updates['payout_frequency'] = $frequency;
        }

        if (empty($updates)) {
            return response()->json(['message' => 'Geen wijzigingen.'], 422);
        }

        $updates['updated_at'] = now();

        // Store old values for audit log
        $oldPayout = DB::table('gymies_trainer_payouts')->where('user_id', $trainerId)->first();
        $oldValues = [];
        foreach ($updates as $key => $val) {
            if ($key !== 'updated_at' && isset($oldPayout->$key)) {
                $oldValues[$key] = $oldPayout->$key;
            }
        }

        DB::table('gymies_trainer_payouts')
            ->where('user_id', $trainerId)
            ->update($updates);

        // Log settings update
        $this->auditLog($trainerId, 'payout.settings.updated', 'Payout', $trainerId, $oldValues, $updates, (string) ($request->ip() ?? 'unknown'));
        Log::info('Payout settings updated', ['user_id' => $trainerId, 'fields' => array_keys($updates)]);

        return response()->json(['message' => 'Instellingen opgeslagen.', 'updated' => array_keys($updates)]);
    }

    /**
     * PUT payout/mode — switch payout modus (gymies ↔ mollie_connect).
     */
    public function updateMode(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $mode = $request->input('payout_mode');
        if (!in_array($mode, ['gymies', 'mollie_connect'], true)) {
            return response()->json(['message' => 'Ongeldige modus. Kies "gymies" of "mollie_connect".'], 422);
        }

        $trainerId = (int) $user->id;
        GymiesPayoutService::ensureSchema();
        GymiesPayoutService::getTrainerPayout($trainerId);

        // Check of er openstaand saldo is bij switch naar mollie
        if ($mode === 'mollie_connect') {
            $balance = DB::table('gymies_trainer_payouts')
                ->where('user_id', $trainerId)
                ->value('balance_cents') ?? 0;

            if ((int) $balance > 0) {
                return response()->json([
                    'message' => 'Je hebt nog een openstaand saldo van €' . number_format((int) $balance / 100, 2, ',', '.') . '. Vraag eerst een uitbetaling aan voordat je overschakelt.',
                ], 422);
            }
        }

        $oldMode = DB::table('gymies_trainer_payouts')->where('user_id', $trainerId)->value('payout_mode');

        DB::table('gymies_trainer_payouts')
            ->where('user_id', $trainerId)
            ->update(['payout_mode' => $mode, 'updated_at' => now()]);

        // Log mode change
        $this->auditLog($trainerId, 'payout.mode.changed', 'Payout', $trainerId, ['old_mode' => $oldMode], ['new_mode' => $mode], (string) ($request->ip() ?? 'unknown'));
        Log::warning('Payout mode changed', ['user_id' => $trainerId, 'from' => $oldMode, 'to' => $mode]);

        return response()->json([
            'message' => $mode === 'mollie_connect'
                ? 'Overgeschakeld naar eigen Mollie. Je ontvangt betalingen direct.'
                : 'Overgeschakeld naar Gymies uitbetaling.',
            'payout_mode' => $mode,
        ]);
    }

    /**
     * GET payout/business — bedrijfsgegevens voor self-billing facturen.
     */
    public function getBusinessInfo(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainerId = (int) $user->id;
        $payout = GymiesPayoutService::getTrainerPayout($trainerId);
        if (!$payout) {
            return response()->json(['message' => 'Profiel niet gevonden.'], 404);
        }

        // Fallback: als payout geen bedrijfsgegevens heeft, probeer uit trainer_profiles
        $kvk = $payout->kvk_number ?? null;
        $btw = $payout->btw_number ?? null;
        $company = $payout->company_name ?? null;
        $street = $payout->street ?? null;
        $postal = $payout->postal_code ?? null;
        $city = $payout->city ?? null;

        if (empty($kvk) || empty($company)) {
            $profile = Schema::hasTable('gymies_trainer_profiles')
                ? DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->first()
                : null;

            if ($profile) {
                $kvk = $kvk ?: ($profile->kvk_number ?? null);
                $btw = $btw ?: ($profile->vat_number ?? null);
                $company = $company ?: ($profile->company_name ?? null);
                $street = $street ?: ($profile->trainer_address_line1 ?? null);
                $postal = $postal ?: ($profile->trainer_postcode ?? null);
                $city = $city ?: ($profile->trainer_city ?? null);

                // Auto-sync naar payout tabel als we data ophaalden
                $sync = array_filter([
                    'kvk_number' => $kvk,
                    'btw_number' => $btw,
                    'company_name' => $company,
                    'street' => $street,
                    'postal_code' => $postal,
                    'city' => $city,
                ]);
                if (!empty($sync)) {
                    $sync['updated_at'] = now();
                    DB::table('gymies_trainer_payouts')->where('user_id', $trainerId)->update($sync);
                }
            }
        }

        return response()->json([
            'kvk_number' => $kvk,
            'btw_number' => $btw,
            'company_name' => $company,
            'street' => $street,
            'postal_code' => $postal,
            'city' => $city,
            'self_billing_agreed' => !empty($payout->self_billing_agreed_at),
            'self_billing_agreed_at' => $payout->self_billing_agreed_at ?? null,
            'is_complete' => !empty($kvk)
                && !empty($company)
                && !empty($street)
                && !empty($postal)
                && !empty($city)
                && !empty($payout->iban)
                && !empty($payout->self_billing_agreed_at),
        ]);
    }

    /**
     * PUT payout/business — bedrijfsgegevens opslaan (KvK, BTW, adres).
     */
    public function updateBusinessInfo(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainerId = (int) $user->id;
        GymiesPayoutService::ensureSchema();
        GymiesPayoutService::getTrainerPayout($trainerId);

        $updates = [];

        // KvK-nummer (8 cijfers)
        $kvk = $request->input('kvk_number');
        if ($kvk !== null) {
            $kvk = trim(str_replace(' ', '', $kvk));
            if ($kvk !== '' && !preg_match('/^\d{8}$/', $kvk)) {
                return response()->json(['message' => 'KvK-nummer moet exact 8 cijfers zijn.'], 422);
            }
            $updates['kvk_number'] = $kvk ?: null;
        }

        // BTW-nummer (NL + 9 chars + B + 2 chars, bijv. NL123456789B01)
        $btw = $request->input('btw_number');
        if ($btw !== null) {
            $btw = strtoupper(trim(str_replace(' ', '', $btw)));
            if ($btw !== '' && !preg_match('/^NL\d{9}B\d{2}$/', $btw)) {
                // Sta ook lege string toe (trainer zit in KOR en heeft geen BTW-nr)
                if ($btw !== 'KOR' && $btw !== '') {
                    return response()->json(['message' => 'BTW-nummer ongeldig. Formaat: NL123456789B01 of laat leeg bij KOR.'], 422);
                }
            }
            $updates['btw_number'] = ($btw === '' || $btw === 'KOR') ? null : $btw;
        }

        // Bedrijfsnaam
        $companyName = $request->input('company_name');
        if ($companyName !== null) {
            $updates['company_name'] = trim($companyName) ?: null;
        }

        // Adres
        $street = $request->input('street');
        if ($street !== null) {
            $updates['street'] = trim($street) ?: null;
        }

        $postalCode = $request->input('postal_code');
        if ($postalCode !== null) {
            $pc = strtoupper(trim(str_replace(' ', '', $postalCode)));
            if ($pc !== '' && !preg_match('/^\d{4}[A-Z]{2}$/', $pc)) {
                return response()->json(['message' => 'Postcode ongeldig. Formaat: 1234AB.'], 422);
            }
            $updates['postal_code'] = $pc ?: null;
        }

        $city = $request->input('city');
        if ($city !== null) {
            $updates['city'] = trim($city) ?: null;
        }

        if (empty($updates)) {
            return response()->json(['message' => 'Geen wijzigingen.'], 422);
        }

        $updates['updated_at'] = now();

        DB::table('gymies_trainer_payouts')
            ->where('user_id', $trainerId)
            ->update($updates);

        // Sync naar gymies_trainer_profiles (Documenten-scherm)
        self::syncToProfilesTable($trainerId, $updates);

        return response()->json(['message' => 'Bedrijfsgegevens opgeslagen.', 'updated' => array_keys($updates)]);
    }

    /**
     * Sync payout bedrijfsgegevens terug naar gymies_trainer_profiles.
     */
    private static function syncToProfilesTable(int $userId, array $updates): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }

        $profile = DB::table('gymies_trainer_profiles')->where('user_id', $userId)->first();
        if (!$profile) {
            return;
        }

        $sync = [];
        if (isset($updates['company_name'])) $sync['company_name'] = $updates['company_name'];
        if (isset($updates['kvk_number'])) $sync['kvk_number'] = $updates['kvk_number'];
        if (isset($updates['btw_number'])) $sync['vat_number'] = $updates['btw_number'];
        if (isset($updates['street'])) $sync['trainer_address_line1'] = $updates['street'];
        if (isset($updates['postal_code'])) $sync['trainer_postcode'] = $updates['postal_code'];
        if (isset($updates['city'])) $sync['trainer_city'] = $updates['city'];

        if (!empty($sync)) {
            $existingColumns = Schema::getColumnListing('gymies_trainer_profiles');
            $sync = array_intersect_key($sync, array_flip($existingColumns));
            if (!empty($sync)) {
                $sync['updated_at'] = now();
                DB::table('gymies_trainer_profiles')->where('user_id', $userId)->update($sync);
            }
        }
    }

    /**
     * POST payout/self-billing-agree — trainer akkoord met self-billing.
     */
    public function agreeSelfBilling(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainerId = (int) $user->id;
        GymiesPayoutService::ensureSchema();
        GymiesPayoutService::getTrainerPayout($trainerId);

        // Check of bedrijfsgegevens compleet zijn
        $payout = DB::table('gymies_trainer_payouts')->where('user_id', $trainerId)->first();
        if (empty($payout->kvk_number) || empty($payout->company_name) || empty($payout->street) || empty($payout->postal_code) || empty($payout->city)) {
            return response()->json([
                'message' => 'Vul eerst je bedrijfsgegevens volledig in (KvK, bedrijfsnaam, adres) voordat je akkoord kunt gaan.',
            ], 422);
        }

        if (empty($payout->iban)) {
            return response()->json(['message' => 'Vul eerst je IBAN in.'], 422);
        }

        DB::table('gymies_trainer_payouts')
            ->where('user_id', $trainerId)
            ->update(['self_billing_agreed_at' => now(), 'updated_at' => now()]);

        return response()->json([
            'message' => 'Self-billing akkoord geregistreerd. Gymies maakt voortaan facturen namens jou aan.',
            'self_billing_agreed_at' => now()->toIso8601String(),
        ]);
    }

    /**
     * GET payout/invoices — trainer ziet eigen facturen.
     */
    public function trainerInvoices(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        GymiesPayoutService::ensureSchema();

        $invoices = DB::table('gymies_payout_requests')
            ->where('user_id', (int) $user->id)
            ->whereNotNull('invoice_number')
            ->where('status', 'paid')
            ->orderByDesc('paid_at')
            ->select(['id', 'invoice_number', 'net_amount_cents', 'fee_cents', 'amount_cents', 'frequency', 'paid_at', 'invoice_path'])
            ->limit(100)
            ->get();

        return response()->json([
            'invoices' => $invoices->map(fn ($r) => [
                'id' => $r->id,
                'invoice_number' => $r->invoice_number,
                'net_amount_formatted' => '€' . number_format((int) $r->net_amount_cents / 100, 2, ',', '.'),
                'fee_formatted' => '€' . number_format((int) $r->fee_cents / 100, 2, ',', '.'),
                'total_formatted' => '€' . number_format((int) $r->amount_cents / 100, 2, ',', '.'),
                'frequency' => $r->frequency,
                'paid_at' => $r->paid_at,
                'has_pdf' => !empty($r->invoice_path),
            ])->values(),
        ]);
    }

    /**
     * GET payout/invoices/{id}/download — download factuur-PDF.
     * Trainer kan alleen eigen facturen downloaden.
     */
    public function downloadInvoice(Request $request, string $id): \Illuminate\Http\Response|JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $payoutRequest = DB::table('gymies_payout_requests')
            ->where('id', (int) $id)
            ->where('user_id', (int) $user->id) // Alleen eigen facturen
            ->first();

        if (!$payoutRequest) {
            return response()->json(['message' => 'Factuur niet gevonden.'], 404);
        }

        // BUG-004: Add try-catch for file generation/read errors
        try {
            if (empty($payoutRequest->invoice_path)) {
                // Probeer alsnog te genereren
                $path = GymiesInvoiceGenerator::generate((int) $id);
                if (!$path) {
                    return response()->json(['message' => 'Factuur-PDF nog niet beschikbaar.'], 404);
                }
                DB::table('gymies_payout_requests')->where('id', (int) $id)->update(['invoice_path' => $path]);
            }

            $content = GymiesInvoiceGenerator::getInvoicePdf((int) $id);
            if (!$content) {
                return response()->json(['message' => 'PDF niet gevonden op schijf.'], 404);
            }

            $filename = ($payoutRequest->invoice_number ?? 'factuur') . '.pdf';

            // Detect of het HTML is (fallback) of echte PDF
            $contentType = str_starts_with(trim($content), '<!DOCTYPE') || str_starts_with(trim($content), '<html')
                ? 'text/html'
                : 'application/pdf';

            if ($contentType === 'text/html') {
                $filename = str_replace('.pdf', '.html', $filename);
            }

            return response($content, 200)
                ->header('Content-Type', $contentType)
                ->header('Content-Disposition', "attachment; filename=\"{$filename}\"");
        } catch (\Throwable $e) {
            Log::error('Invoice download failed', [
                'user_id' => (int) $user->id,
                'payout_request_id' => (int) $id,
                'error' => $e->getMessage(),
            ]);
            return response()->json(['message' => 'Fout bij het downloaden van de factuur.'], 500);
        }
    }
}
