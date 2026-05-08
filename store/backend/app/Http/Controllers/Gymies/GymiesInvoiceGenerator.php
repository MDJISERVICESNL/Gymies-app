<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

/**
 * Self-billing factuur PDF generator.
 *
 * Genereert een wettelijk conforme factuur namens de trainer (leverancier)
 * gericht aan Gymies (afnemer). Dit is een self-billing constructie
 * conform Nederlandse wet- en regelgeving.
 *
 * Vereisten self-billing factuur:
 * - Factuurnummer (opvolgend)
 * - Factuurdatum
 * - Gegevens leverancier (trainer): naam, adres, KvK, BTW
 * - Gegevens afnemer (Gymies): naam, adres, KvK, BTW
 * - Omschrijving diensten
 * - Bedragen excl/incl BTW
 * - Vermelding "Factuur opgesteld door afnemer (self-billing)"
 */
final class GymiesInvoiceGenerator
{
    // Gymies bedrijfsgegevens (afnemer)
    private const GYMIES_COMPANY = 'Gymies B.V.';
    private const GYMIES_STREET = 'Keizersgracht 100';
    private const GYMIES_POSTAL = '1015 AA';
    private const GYMIES_CITY = 'Amsterdam';
    private const GYMIES_KVK = '90123456';
    private const GYMIES_BTW = 'NL864523719B01';

    /**
     * Genereer een factuur-PDF voor een betaalde payout request.
     *
     * @return string|null Pad naar opgeslagen PDF, of null bij fout.
     */
    public static function generate(int $payoutRequestId): ?string
    {
        try {
            $request = DB::table('gymies_payout_requests')->where('id', $payoutRequestId)->first();
            if (!$request || empty($request->invoice_number)) {
                Log::warning('[InvoiceGenerator] Request niet gevonden of geen factuurnummer', ['id' => $payoutRequestId]);
                return null;
            }

            $trainer = DB::table('gymies_trainer_payouts')->where('user_id', $request->user_id)->first();
            if (!$trainer) {
                Log::warning('[InvoiceGenerator] Trainer payout record niet gevonden', ['user_id' => $request->user_id]);
                return null;
            }

            $user = DB::table('users')->where('id', $request->user_id)->first(['name', 'first_name', 'last_name', 'email']);

            // Bouw factuurdata op
            $invoiceData = self::buildInvoiceData($request, $trainer, $user);

            // Genereer HTML → PDF
            $html = self::renderHtml($invoiceData);
            $pdf = self::htmlToPdf($html);

            if (!$pdf) {
                return null;
            }

            // Opslaan
            $filename = "invoices/{$request->invoice_number}.pdf";
            Storage::disk('local')->put($filename, $pdf);

            return $filename;
        } catch (\Throwable $e) {
            Log::error('[InvoiceGenerator] Generatie gefaald', [
                'request_id' => $payoutRequestId,
                'error' => $e->getMessage(),
            ]);
            if (app()->bound('sentry')) {
                app('sentry')->captureException($e);
            }
            return null;
        }
    }

    /**
     * Bouw gestructureerde factuurdata.
     */
    private static function buildInvoiceData(object $request, object $trainer, ?object $user): array
    {
        $trainerName = self::resolveTrainerName($trainer, $user);
        $paidAt = $request->paid_at ? \Carbon\Carbon::parse($request->paid_at) : now();
        $createdAt = \Carbon\Carbon::parse($request->created_at);

        // BTW berekening: meeste PT-ZZP'ers zitten in KOR (geen BTW)
        $hasVat = !empty($trainer->btw_number);
        $netAmount = (int) $request->net_amount_cents;
        $vatRate = $hasVat ? 21 : 0;
        $vatAmount = $hasVat ? (int) round($netAmount * ($vatRate / 100)) : 0;
        $totalInclVat = $netAmount + $vatAmount;

        // Periode bepaling
        $periodStart = $createdAt->copy()->startOfWeek();
        $periodEnd = $createdAt->copy();

        // Haal per-boeking platform fees op voor deze periode
        $platformFeesTotal = 0;
        $bookingCount = 0;
        if (\Illuminate\Support\Facades\Schema::hasTable('gymies_payout_transactions')) {
            $feeData = DB::table('gymies_payout_transactions')
                ->where('user_id', $request->user_id)
                ->where('type', 'platform_fee')
                ->where('status', 'completed')
                ->where('created_at', '<=', $createdAt)
                ->selectRaw('COUNT(*) as cnt, COALESCE(SUM(ABS(amount_cents)), 0) as total_fees')
                ->first();
            $platformFeesTotal = (int) ($feeData->total_fees ?? 0);
            $bookingCount = (int) ($feeData->cnt ?? 0);
        }

        $months = [
            1 => 'januari', 2 => 'februari', 3 => 'maart', 4 => 'april',
            5 => 'mei', 6 => 'juni', 7 => 'juli', 8 => 'augustus',
            9 => 'september', 10 => 'oktober', 11 => 'november', 12 => 'december',
        ];

        return [
            // Factuurnummer & datum
            'invoice_number' => $request->invoice_number,
            'invoice_date' => $paidAt->format('d') . ' ' . $months[(int)$paidAt->format('m')] . ' ' . $paidAt->format('Y'),
            'invoice_date_short' => $paidAt->format('d-m-Y'),

            // Leverancier (trainer)
            'supplier_name' => $trainer->company_name ?? $trainerName,
            'supplier_street' => $trainer->street ?? '',
            'supplier_postal' => $trainer->postal_code ?? '',
            'supplier_city' => $trainer->city ?? '',
            'supplier_kvk' => $trainer->kvk_number ?? '',
            'supplier_btw' => $trainer->btw_number ?? 'Vrijgesteld (KOR)',
            'supplier_iban' => $request->iban ?? '',
            'supplier_iban_name' => $request->iban_name ?? $trainerName,

            // Afnemer (Gymies)
            'buyer_name' => self::GYMIES_COMPANY,
            'buyer_street' => self::GYMIES_STREET,
            'buyer_postal' => self::GYMIES_POSTAL,
            'buyer_city' => self::GYMIES_CITY,
            'buyer_kvk' => self::GYMIES_KVK,
            'buyer_btw' => self::GYMIES_BTW,

            // Bedragen
            'gross_amount_cents' => (int) $request->amount_cents,
            'fee_cents' => (int) $request->fee_cents,
            'net_amount_cents' => $netAmount,
            'vat_rate' => $vatRate,
            'vat_amount_cents' => $vatAmount,
            'total_incl_vat_cents' => $totalInclVat,

            // Geformateerd
            'gross_formatted' => self::formatCents((int) $request->amount_cents),
            'fee_formatted' => self::formatCents((int) $request->fee_cents),
            'net_formatted' => self::formatCents($netAmount),
            'vat_formatted' => self::formatCents($vatAmount),
            'total_formatted' => self::formatCents($totalInclVat),

            // Omschrijving
            'frequency' => $request->frequency,
            'frequency_label' => match ($request->frequency) {
                'weekly' => 'wekelijks',
                'monthly' => 'maandelijks',
                'daily' => 'volgende dag',
                default => $request->frequency,
            },
            'period_description' => self::buildPeriodDescription($request->frequency, $createdAt),

            // Per-boeking transactiekosten (platformfees)
            'platform_fees_total_cents' => $platformFeesTotal,
            'platform_fees_formatted' => self::formatCents($platformFeesTotal),
            'booking_count' => $bookingCount,
            'booking_fee_per_session' => self::formatCents(GymiesPayoutService::BOOKING_FEE_CENTS),

            // Meta
            'has_vat' => $hasVat,
            'self_billing_note' => 'Deze factuur is opgesteld door de afnemer (self-billing) conform artikel 3.5 Uitvoeringsbesluit OB 1968.',
        ];
    }

    /**
     * Bouw een leesbare periode-omschrijving.
     */
    private static function buildPeriodDescription(string $frequency, \Carbon\Carbon $date): string
    {
        $months = [
            1 => 'januari', 2 => 'februari', 3 => 'maart', 4 => 'april',
            5 => 'mei', 6 => 'juni', 7 => 'juli', 8 => 'augustus',
            9 => 'september', 10 => 'oktober', 11 => 'november', 12 => 'december',
        ];

        return match ($frequency) {
            'weekly' => "Week {$date->format('W')}, {$date->format('Y')}",
            'monthly' => ucfirst($months[(int)$date->format('m')]) . " {$date->format('Y')}",
            'daily' => (int)$date->format('d') . " {$months[(int)$date->format('m')]} {$date->format('Y')}",
            default => $date->format('d-m-Y'),
        };
    }

    /**
     * Render factuur-HTML template.
     */
    private static function renderHtml(array $data): string
    {
        $vatRow = $data['has_vat']
            ? "<tr><td>BTW ({$data['vat_rate']}%)</td><td class=\"right\">{$data['vat_formatted']}</td></tr>"
            : "<tr><td>BTW</td><td class=\"right\">Vrijgesteld (KOR)</td></tr>";

        $html = <<<HTML
<!DOCTYPE html>
<html lang="nl">
<head>
<meta charset="UTF-8">
<title>Factuur {$data['invoice_number']}</title>
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Helvetica Neue', Arial, sans-serif; font-size: 10pt; color: #1a1a1a; padding: 40px 50px; line-height: 1.5; }
    .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 40px; border-bottom: 3px solid #1a1a1a; padding-bottom: 20px; }
    .header h1 { font-size: 24pt; font-weight: 700; letter-spacing: -0.5px; }
    .header .meta { text-align: right; font-size: 9pt; color: #555; }
    .parties { display: flex; justify-content: space-between; margin-bottom: 35px; }
    .party { width: 45%; }
    .party-label { font-size: 8pt; text-transform: uppercase; letter-spacing: 1px; color: #888; margin-bottom: 5px; font-weight: 600; }
    .party-name { font-weight: 700; font-size: 11pt; margin-bottom: 3px; }
    .party-detail { font-size: 9pt; color: #444; }
    .invoice-info { margin-bottom: 30px; background: #f7f7f7; padding: 15px 20px; border-radius: 4px; }
    .invoice-info table { width: 100%; }
    .invoice-info td { padding: 3px 0; font-size: 9pt; }
    .invoice-info td:first-child { font-weight: 600; width: 160px; }
    .lines { width: 100%; border-collapse: collapse; margin-bottom: 25px; }
    .lines th { background: #1a1a1a; color: #fff; padding: 10px 15px; text-align: left; font-size: 9pt; text-transform: uppercase; letter-spacing: 0.5px; }
    .lines th.right, .lines td.right { text-align: right; }
    .lines td { padding: 12px 15px; border-bottom: 1px solid #eee; font-size: 9.5pt; }
    .lines tr:last-child td { border-bottom: none; }
    .totals { width: 320px; margin-left: auto; border-collapse: collapse; margin-bottom: 30px; }
    .totals td { padding: 6px 15px; font-size: 9.5pt; }
    .totals td.right { text-align: right; }
    .totals tr.total { border-top: 2px solid #1a1a1a; font-weight: 700; font-size: 11pt; }
    .totals tr.total td { padding-top: 10px; }
    .payment { margin-bottom: 25px; padding: 15px 20px; background: #f0f7f0; border-radius: 4px; border-left: 4px solid #2d8a4e; }
    .payment h3 { font-size: 9pt; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 5px; color: #2d8a4e; }
    .payment p { font-size: 9pt; }
    .footer { margin-top: 40px; padding-top: 15px; border-top: 1px solid #ddd; font-size: 8pt; color: #888; }
    .self-billing { margin-top: 15px; padding: 10px 15px; background: #fff8e6; border: 1px solid #f0d060; border-radius: 4px; font-size: 8.5pt; color: #6b5900; }
</style>
</head>
<body>

<div class="header">
    <div>
        <h1>FACTUUR</h1>
        <p style="font-size:9pt; color:#555; margin-top:3px;">Self-billing</p>
    </div>
    <div class="meta">
        <strong>{$data['invoice_number']}</strong><br>
        {$data['invoice_date']}
    </div>
</div>

<div class="parties">
    <div class="party">
        <div class="party-label">Leverancier (trainer)</div>
        <div class="party-name">{$data['supplier_name']}</div>
        <div class="party-detail">
            {$data['supplier_street']}<br>
            {$data['supplier_postal']} {$data['supplier_city']}<br><br>
            KvK: {$data['supplier_kvk']}<br>
            BTW: {$data['supplier_btw']}
        </div>
    </div>
    <div class="party">
        <div class="party-label">Afnemer</div>
        <div class="party-name">{$data['buyer_name']}</div>
        <div class="party-detail">
            {$data['buyer_street']}<br>
            {$data['buyer_postal']} {$data['buyer_city']}<br><br>
            KvK: {$data['buyer_kvk']}<br>
            BTW: {$data['buyer_btw']}
        </div>
    </div>
</div>

<div class="invoice-info">
    <table>
        <tr><td>Factuurnummer</td><td>{$data['invoice_number']}</td></tr>
        <tr><td>Factuurdatum</td><td>{$data['invoice_date']}</td></tr>
        <tr><td>Periode</td><td>{$data['period_description']}</td></tr>
        <tr><td>Uitbetaalfrequentie</td><td>{$data['frequency_label']}</td></tr>
    </table>
</div>

<table class="lines">
    <thead>
        <tr>
            <th>Omschrijving</th>
            <th class="right">Bedrag</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td>Personal training diensten — {$data['period_description']}<br><span style="font-size:8.5pt;color:#666;">Uitbetaling {$data['frequency_label']}</span></td>
            <td class="right">{$data['gross_formatted']}</td>
        </tr>
HTML;

        // Platformfees (per-boeking transactiekosten) — altijd tonen als er boekingen zijn
        if ($data['booking_count'] > 0) {
            $html .= <<<HTML
        <tr>
            <td>Transactiekosten ({$data['booking_count']} sessies × {$data['booking_fee_per_session']})<br><span style="font-size:8.5pt;color:#666;">Platformfee per boeking</span></td>
            <td class="right">-{$data['platform_fees_formatted']}</td>
        </tr>
HTML;
        }

        // Uitbetaalfee alleen tonen als deze > 0 is (niet bij maandelijks)
        if ($data['fee_cents'] > 0) {
            $html .= <<<HTML
        <tr>
            <td>Uitbetaalfee ({$data['frequency_label']})</td>
            <td class="right">-{$data['fee_formatted']}</td>
        </tr>
HTML;
        }

        $html .= <<<HTML
    </tbody>
</table>

<table class="totals">
    <tr><td>Subtotaal excl. BTW</td><td class="right">{$data['net_formatted']}</td></tr>
    {$vatRow}
    <tr class="total"><td>Totaal te betalen</td><td class="right">{$data['total_formatted']}</td></tr>
</table>

<div class="payment">
    <h3>Betaalgegevens</h3>
    <p>
        IBAN: <strong>{$data['supplier_iban']}</strong><br>
        T.n.v.: {$data['supplier_iban_name']}
    </p>
</div>

<div class="self-billing">
    {$data['self_billing_note']}
</div>

<div class="footer">
    <p>Gegenereerd door Gymies — {$data['invoice_date_short']}</p>
</div>

</body>
</html>
HTML;

        return $html;
    }

    /**
     * Converteer HTML naar PDF bytes.
     * Gebruikt wkhtmltopdf als die beschikbaar is, anders dompdf, anders opslaan als HTML.
     */
    private static function htmlToPdf(string $html): ?string
    {
        // Optie 1: dompdf (meest gangbare Laravel PDF library)
        if (class_exists(\Dompdf\Dompdf::class)) {
            try {
                $dompdf = new \Dompdf\Dompdf(['isHtml5ParserEnabled' => true, 'isRemoteEnabled' => false]);
                $dompdf->loadHtml($html);
                $dompdf->setPaper('A4', 'portrait');
                $dompdf->render();
                return $dompdf->output();
            } catch (\Throwable $e) {
                Log::warning('[InvoiceGenerator] dompdf failed, falling back', ['error' => $e->getMessage()]);
            }
        }

        // Optie 2: wkhtmltopdf via shell
        $wkhtmltopdf = self::findWkhtmltopdf();
        if ($wkhtmltopdf) {
            try {
                $tmpHtml = tempnam(sys_get_temp_dir(), 'inv_') . '.html';
                $tmpPdf = tempnam(sys_get_temp_dir(), 'inv_') . '.pdf';
                file_put_contents($tmpHtml, $html);
                exec("{$wkhtmltopdf} --quiet --page-size A4 --margin-top 10 --margin-bottom 10 \"{$tmpHtml}\" \"{$tmpPdf}\" 2>&1", $output, $code);
                if ($code === 0 && file_exists($tmpPdf)) {
                    $pdf = file_get_contents($tmpPdf);
                    @unlink($tmpHtml);
                    @unlink($tmpPdf);
                    return $pdf;
                }
                @unlink($tmpHtml);
                @unlink($tmpPdf);
            } catch (\Throwable $e) {
                Log::warning('[InvoiceGenerator] wkhtmltopdf failed', ['error' => $e->getMessage()]);
            }
        }

        // Optie 3: sla als HTML op (fallback — kan later door cron naar PDF worden geconverteerd)
        Log::info('[InvoiceGenerator] Geen PDF renderer beschikbaar, sla HTML op als fallback.');
        return $html;
    }

    /**
     * Zoek wkhtmltopdf binary.
     */
    private static function findWkhtmltopdf(): ?string
    {
        $paths = ['/usr/local/bin/wkhtmltopdf', '/usr/bin/wkhtmltopdf'];
        foreach ($paths as $path) {
            if (file_exists($path) && is_executable($path)) {
                return $path;
            }
        }
        return null;
    }

    /**
     * Haal de factuur-PDF op als binary content.
     */
    public static function getInvoicePdf(int $payoutRequestId): ?string
    {
        $request = DB::table('gymies_payout_requests')->where('id', $payoutRequestId)->first();
        if (!$request || empty($request->invoice_path)) {
            return null;
        }

        if (Storage::disk('local')->exists($request->invoice_path)) {
            return Storage::disk('local')->get($request->invoice_path);
        }

        return null;
    }

    /**
     * Check of een factuur-PDF bestaat.
     */
    public static function invoiceExists(int $payoutRequestId): bool
    {
        $request = DB::table('gymies_payout_requests')->where('id', $payoutRequestId)->first();
        if (!$request || empty($request->invoice_path)) {
            return false;
        }

        return Storage::disk('local')->exists($request->invoice_path);
    }

    /**
     * Resolve trainer naam.
     */
    private static function resolveTrainerName(object $trainer, ?object $user): string
    {
        if (!empty($trainer->company_name)) {
            return $trainer->company_name;
        }
        if ($user && !empty($user->first_name)) {
            return trim($user->first_name . ' ' . ($user->last_name ?? ''));
        }
        if ($user && !empty($user->name)) {
            return $user->name;
        }
        return 'Onbekend';
    }

    /**
     * Format cents naar Euro string.
     */
    private static function formatCents(int $cents): string
    {
        return '€' . number_format($cents / 100, 2, ',', '.');
    }

    /**
     * Bouw gestructureerde data voor gym settlement factuur.
     * Platform (Gymies) stelt de factuur op namens de gym.
     */
    public static function buildGymSettlementInvoiceData(int $settlementId): array
    {
        $settlement = DB::table('gymies_organisation_settlements')->where('id', $settlementId)->first();
        if (!$settlement) {
            throw new \Exception("Settlement {$settlementId} niet gevonden");
        }

        $org = DB::table('gymies_organisations')->where('id', (int) $settlement->organisation_id)->first();
        if (!$org) {
            throw new \Exception("Organisatie {$settlement->organisation_id} niet gevonden");
        }

        // Haal payment transactions op voor deze settlement periode
        $transactions = DB::table('gymies_payment_transactions')
            ->where('organisation_id', (int) $settlement->organisation_id)
            ->where('mollie_account_source', 'organisation')
            ->whereBetween('created_at', [$settlement->period_start, $settlement->period_end])
            ->orderBy('created_at')
            ->get(['id', 'amount_cents', 'fee_cents', 'net_cents', 'booking_id', 'created_at']);

        $months = [
            1 => 'januari', 2 => 'februari', 3 => 'maart', 4 => 'april',
            5 => 'mei', 6 => 'juni', 7 => 'juli', 8 => 'augustus',
            9 => 'september', 10 => 'oktober', 11 => 'november', 12 => 'december',
        ];

        $periodStart = \Carbon\Carbon::parse($settlement->period_start);
        $periodEnd = \Carbon\Carbon::parse($settlement->period_end);
        $periodStr = $periodStart->format('d') . ' ' . $months[(int)$periodStart->format('m')] . ' '
                     . $periodStart->format('Y') . ' — ' . $periodEnd->format('d') . ' '
                     . $months[(int)$periodEnd->format('m')] . ' ' . $periodEnd->format('Y');

        return [
            // Settlement info
            'invoice_number' => (string) ($settlement->invoice_number ?? 'SETTLE-' . $settlement->id),
            'settlement_id' => (int) $settlement->id,
            'settlement_date' => $periodEnd->format('d') . ' ' . $months[(int)$periodEnd->format('m')] . ' ' . $periodEnd->format('Y'),
            'settlement_date_short' => $periodEnd->format('d-m-Y'),
            'period_start' => $periodStart->format('d-m-Y'),
            'period_end' => $periodEnd->format('d-m-Y'),
            'period_description' => $periodStr,

            // Gym (supplier/afnemer in self-billing)
            'gym_name' => (string) $org->name,
            'gym_street' => (string) ($org->address ?? ''),
            'gym_postal' => (string) ($org->postal_code ?? ''),
            'gym_city' => (string) ($org->city ?? ''),
            'gym_kvk' => (string) ($org->kvk_number ?? ''),
            'gym_iban' => (string) ($org->payout_iban ?? ''),
            'gym_iban_name' => (string) ($org->payout_iban_name ?? $org->name),

            // Gymies (buyer/leverancier in self-billing — platform bills gym)
            'buyer_name' => self::GYMIES_COMPANY,
            'buyer_street' => self::GYMIES_STREET,
            'buyer_postal' => self::GYMIES_POSTAL,
            'buyer_city' => self::GYMIES_CITY,
            'buyer_kvk' => self::GYMIES_KVK,
            'buyer_btw' => self::GYMIES_BTW,

            // Bedragen
            'gross_amount_cents' => (int) $settlement->gross_cents,
            'fee_cents' => (int) $settlement->fee_cents,
            'adjustments_cents' => (int) $settlement->adjustments_cents,
            'net_amount_cents' => (int) $settlement->net_cents,

            // Geformateerd
            'gross_formatted' => self::formatCents((int) $settlement->gross_cents),
            'fee_formatted' => self::formatCents((int) $settlement->fee_cents),
            'adjustments_formatted' => self::formatCents((int) $settlement->adjustments_cents),
            'net_formatted' => self::formatCents((int) $settlement->net_cents),

            // Transactions/line items
            'transactions' => $transactions->map(fn ($t) => [
                'id' => (int) $t->id,
                'amount_cents' => (int) $t->amount_cents,
                'fee_cents' => (int) $t->fee_cents,
                'net_cents' => (int) $t->net_cents,
                'amount_formatted' => self::formatCents((int) $t->amount_cents),
                'fee_formatted' => self::formatCents((int) $t->fee_cents),
                'net_formatted' => self::formatCents((int) $t->net_cents),
                'created_at' => \Carbon\Carbon::parse($t->created_at)->format('d-m-Y'),
            ])->all(),
            'transaction_count' => $transactions->count(),

            // Meta
            'self_billing_note' => 'Deze factuur is opgesteld door de afnemer (self-billing) conform artikel 3.5 Uitvoeringsbesluit OB 1968.',
        ];
    }

    /**
     * Genereer HTML voor gym settlement afrekening.
     */
    public static function renderGymSettlementHtml(array $data): string
    {
        $html = <<<HTML
<!DOCTYPE html>
<html lang="nl">
<head>
<meta charset="UTF-8">
<title>Afrekening {$data['invoice_number']}</title>
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: 'Helvetica Neue', Arial, sans-serif; font-size: 10pt; color: #1a1a1a; padding: 40px 50px; line-height: 1.5; }
    .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 40px; border-bottom: 3px solid #1a1a1a; padding-bottom: 20px; }
    .header h1 { font-size: 24pt; font-weight: 700; letter-spacing: -0.5px; }
    .header .meta { text-align: right; font-size: 9pt; color: #555; }
    .parties { display: flex; justify-content: space-between; margin-bottom: 35px; }
    .party { width: 45%; }
    .party-label { font-size: 8pt; text-transform: uppercase; letter-spacing: 1px; color: #888; margin-bottom: 5px; font-weight: 600; }
    .party-name { font-weight: 700; font-size: 11pt; margin-bottom: 3px; }
    .party-detail { font-size: 9pt; color: #444; }
    .invoice-info { margin-bottom: 30px; background: #f7f7f7; padding: 15px 20px; border-radius: 4px; }
    .invoice-info table { width: 100%; }
    .invoice-info td { padding: 3px 0; font-size: 9pt; }
    .invoice-info td:first-child { font-weight: 600; width: 160px; }
    .lines { width: 100%; border-collapse: collapse; margin-bottom: 25px; }
    .lines th { background: #1a1a1a; color: #fff; padding: 10px 15px; text-align: left; font-size: 9pt; text-transform: uppercase; letter-spacing: 0.5px; }
    .lines th.right, .lines td.right { text-align: right; }
    .lines td { padding: 12px 15px; border-bottom: 1px solid #eee; font-size: 9.5pt; }
    .lines tr:last-child td { border-bottom: none; }
    .totals { width: 320px; margin-left: auto; border-collapse: collapse; margin-bottom: 30px; }
    .totals td { padding: 6px 15px; font-size: 9.5pt; }
    .totals td.right { text-align: right; }
    .totals tr.total { border-top: 2px solid #1a1a1a; font-weight: 700; font-size: 11pt; }
    .totals tr.total td { padding-top: 10px; }
    .payment { margin-bottom: 25px; padding: 15px 20px; background: #f0f7f0; border-radius: 4px; border-left: 4px solid #2d8a4e; }
    .payment h3 { font-size: 9pt; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 5px; color: #2d8a4e; }
    .payment p { font-size: 9pt; }
    .footer { margin-top: 40px; padding-top: 15px; border-top: 1px solid #ddd; font-size: 8pt; color: #888; }
    .self-billing { margin-top: 15px; padding: 10px 15px; background: #fff8e6; border: 1px solid #f0d060; border-radius: 4px; font-size: 8.5pt; color: #6b5900; }
</style>
</head>
<body>

<div class="header">
    <div>
        <h1>AFREKENING</h1>
        <p style="font-size:9pt; color:#555; margin-top:3px;">Self-billing</p>
    </div>
    <div class="meta">
        <strong>{$data['invoice_number']}</strong><br>
        {$data['settlement_date']}
    </div>
</div>

<div class="parties">
    <div class="party">
        <div class="party-label">Afrekeningsdeelnemer (leverancier)</div>
        <div class="party-name">{$data['gym_name']}</div>
        <div class="party-detail">
            {$data['gym_street']}<br>
            {$data['gym_postal']} {$data['gym_city']}<br><br>
            KvK: {$data['gym_kvk']}
        </div>
    </div>
    <div class="party">
        <div class="party-label">Afrekeningshouder (afnemer)</div>
        <div class="party-name">{$data['buyer_name']}</div>
        <div class="party-detail">
            {$data['buyer_street']}<br>
            {$data['buyer_postal']} {$data['buyer_city']}<br><br>
            KvK: {$data['buyer_kvk']}<br>
            BTW: {$data['buyer_btw']}
        </div>
    </div>
</div>

<div class="invoice-info">
    <table>
        <tr><td>Factuurnummer</td><td>{$data['invoice_number']}</td></tr>
        <tr><td>Afrekendatum</td><td>{$data['settlement_date']}</td></tr>
        <tr><td>Afrekeningsperiode</td><td>{$data['period_start']} tot {$data['period_end']}</td></tr>
    </table>
</div>

<table class="lines">
    <thead>
        <tr>
            <th>Omschrijving</th>
            <th class="right">Bruto</th>
            <th class="right">Fee</th>
            <th class="right">Netto</th>
        </tr>
    </thead>
    <tbody>
        <tr>
            <td>Afrekeningsopbrengsten — {$data['period_description']}<br><span style="font-size:8.5pt;color:#666;">Verwerkte boekingen en transacties</span></td>
            <td class="right">{$data['gross_formatted']}</td>
            <td class="right">-{$data['fee_formatted']}</td>
            <td class="right">{$data['net_formatted']}</td>
        </tr>
HTML;

        // Adjustments alleen tonen als deze > 0 zijn
        if ((int) $data['adjustments_cents'] !== 0) {
            $sign = (int) $data['adjustments_cents'] > 0 ? '+' : '';
            $html .= <<<HTML
        <tr>
            <td>Correcties<br><span style="font-size:8.5pt;color:#666;">Retourdebietten, vorderingen</span></td>
            <td class="right">—</td>
            <td class="right">—</td>
            <td class="right">{$sign}{$data['adjustments_formatted']}</td>
        </tr>
HTML;
        }

        $html .= <<<HTML
    </tbody>
</table>

<table class="totals">
    <tr><td>Totaal bruto opbrengsten</td><td class="right">{$data['gross_formatted']}</td></tr>
    <tr><td>Platform fee ({$data['transaction_count']} transacties)</td><td class="right">-{$data['fee_formatted']}</td></tr>
    <tr class="total"><td>Totaal netto uitbetaling</td><td class="right">{$data['net_formatted']}</td></tr>
</table>

<div class="payment">
    <h3>Uitbetaalgegevens</h3>
    <p>
        IBAN: <strong>{$data['gym_iban']}</strong><br>
        T.n.v.: {$data['gym_iban_name']}
    </p>
</div>

<div class="self-billing">
    {$data['self_billing_note']}
</div>

<div class="footer">
    <p>Gegenereerd door Gymies — {$data['settlement_date_short']}</p>
</div>

</body>
</html>
HTML;

        return $html;
    }

    /**
     * Genereer settlement invoice PDF en sla op.
     */
    public static function getGymSettlementInvoicePdf(int $settlementId): ?string
    {
        try {
            $settlement = DB::table('gymies_organisation_settlements')->where('id', $settlementId)->first();
            if (!$settlement || empty($settlement->invoice_number)) {
                Log::warning('[InvoiceGenerator] Settlement niet gevonden of geen factuurnummer', ['id' => $settlementId]);
                return null;
            }

            // Bouw factuurdata op
            $invoiceData = self::buildGymSettlementInvoiceData($settlementId);

            // Genereer HTML → PDF
            $html = self::renderGymSettlementHtml($invoiceData);
            $pdf = self::htmlToPdf($html);

            if (!$pdf) {
                return null;
            }

            // Opslaan onder gymies/gym-settlement-invoices/
            $filename = "gymies/gym-settlement-invoices/{$settlement->invoice_number}.pdf";
            Storage::disk('local')->put($filename, $pdf);

            // Update settlement record met invoice_path
            DB::table('gymies_organisation_settlements')
                ->where('id', $settlementId)
                ->update(['invoice_path' => $filename]);

            return $pdf;
        } catch (\Throwable $e) {
            Log::error('[InvoiceGenerator] Settlement factuur generatie gefaald', [
                'settlement_id' => $settlementId,
                'error' => $e->getMessage(),
            ]);
            if (app()->bound('sentry')) {
                app('sentry')->captureException($e);
            }
            return null;
        }
    }
}
