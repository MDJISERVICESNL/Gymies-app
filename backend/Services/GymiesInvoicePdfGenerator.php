<?php

declare(strict_types=1);

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Factuur-PDF/HTML voor Smart-Invoice hub.
 * Als dompdf/dompdf geïnstalleerd is: echte PDF; anders HTML in storage (print-to-PDF).
 * Kopieer naar app/Services na composer require dompdf/dompdf.
 */
final class GymiesInvoicePdfGenerator
{
    /**
     * @param object $invoiceRow rij uit gymies_trainer_invoices
     * @return string|null relatieve URL (bv. /storage/invoices/...) of null
     */
    public static function generateAndStore(object $invoiceRow): ?string
    {
        $id = (int) ($invoiceRow->id ?? 0);
        $trainerId = (int) ($invoiceRow->trainer_user_id ?? 0);
        if ($id <= 0 || $trainerId <= 0) {
            return null;
        }

        $html = self::renderHtml($invoiceRow);
        $dir = self::storageDir();
        if ($dir === null) {
            return null;
        }
        $sub = $dir . DIRECTORY_SEPARATOR . $trainerId;
        if (!is_dir($sub) && !@mkdir($sub, 0755, true)) {
            return null;
        }

        $baseName = 'invoice_' . $id;
        // PDF als Dompdf beschikbaar
        if (class_exists(\Dompdf\Dompdf::class)) {
            $options = new \Dompdf\Options();
            $options->set('isRemoteEnabled', true);
            $dompdf = new \Dompdf\Dompdf($options);
            $dompdf->loadHtml($html);
            $dompdf->setPaper('A4', 'portrait');
            $dompdf->render();
            $pdfPath = $sub . DIRECTORY_SEPARATOR . $baseName . '.pdf';
            file_put_contents($pdfPath, $dompdf->output());
            return '/storage/invoices/' . $trainerId . '/' . $baseName . '.pdf';
        }

        // Fallback: HTML (gebruiker kan printen naar PDF)
        $htmlPath = $sub . DIRECTORY_SEPARATOR . $baseName . '.html';
        file_put_contents($htmlPath, $html);
        return '/storage/invoices/' . $trainerId . '/' . $baseName . '.html';
    }

    private static function storageDir(): ?string
    {
        if (function_exists('storage_path')) {
            $p = storage_path('app/public/invoices');
            if (!is_dir($p) && !@mkdir($p, 0755, true)) {
                return null;
            }
            return $p;
        }
        $base = dirname(__DIR__, 2) . '/storage/app/public/invoices';
        if (!is_dir($base) && !@mkdir($base, 0755, true)) {
            return null;
        }
        return $base;
    }

    private static function renderHtml(object $r): string
    {
        $num = htmlspecialchars((string) ($r->trainer_invoice_number ?? $r->invoice_number ?? ''), ENT_QUOTES, 'UTF-8');
        $gymiesNum = htmlspecialchars((string) ($r->gymies_invoice_number ?? ''), ENT_QUOTES, 'UTF-8');
        $business = htmlspecialchars((string) ($r->company_name ?? $r->business_name ?? 'Gymies'), ENT_QUOTES, 'UTF-8');
        $logoUrl = self::resolveLogoUrl($r);
        $desc = htmlspecialchars((string) ($r->description ?? ''), ENT_QUOTES, 'UTF-8');
        $total = number_format(((int) ($r->total_cents ?? 0)) / 100, 2, ',', '.');
        $vat = number_format(((int) ($r->vat_cents ?? 0)) / 100, 2, ',', '.');
        $net = number_format(((int) ($r->price_ex_vat_cents ?? $r->amount_cents ?? 0)) / 100, 2, ',', '.');
        $kvk = htmlspecialchars((string) ($r->kvk_number ?? ''), ENT_QUOTES, 'UTF-8');
        $vatNr = htmlspecialchars((string) ($r->vat_number ?? ''), ENT_QUOTES, 'UTF-8');
        $invoiceDate = htmlspecialchars((string) ($r->invoice_date ?? substr((string) ($r->created_at ?? ''), 0, 10)), ENT_QUOTES, 'UTF-8');
        $serviceDate = htmlspecialchars((string) ($r->service_date ?? ''), ENT_QUOTES, 'UTF-8');
        $trainerAddress = trim((string) (($r->trainer_address_line1 ?? '') . ' ' . ($r->trainer_postcode ?? '') . ' ' . ($r->trainer_city ?? '')));
        $clientName = htmlspecialchars((string) ($r->client_name ?? ''), ENT_QUOTES, 'UTF-8');
        $clientAddress = trim((string) (($r->client_address_line1 ?? '') . ' ' . ($r->client_postcode ?? '') . ' ' . ($r->client_city ?? '')));
        $trainerAddressHtml = htmlspecialchars($trainerAddress, ENT_QUOTES, 'UTF-8');
        $clientAddressHtml = htmlspecialchars($clientAddress, ENT_QUOTES, 'UTF-8');
        $serviceType = htmlspecialchars((string) ($r->service_type ?? 'dienst'), ENT_QUOTES, 'UTF-8');
        $trainerCustomerNumber = htmlspecialchars((string) ($r->trainer_customer_number ?? ''), ENT_QUOTES, 'UTF-8');

        $kvkHtml = $kvk !== '' ? 'KvK: ' . $kvk . '<br>' : '';
        $vatHtml = $vatNr !== '' ? 'BTW: ' . $vatNr . '<br>' : '';
        $gymiesHtml = $gymiesNum !== '' ? '<br><small style="color:#666">Gymies ref: ' . $gymiesNum . '</small>' : '';
        $clientExtra = $trainerCustomerNumber !== '' ? '<br><small>Klantnummer: ' . $trainerCustomerNumber . '</small>' : '';
        $logoHtml = $logoUrl !== '' ? '<img src="' . htmlspecialchars($logoUrl, ENT_QUOTES, 'UTF-8') . '" alt="Logo" style="max-height: 48px; max-width: 180px; margin-bottom: 8px;" />' : '';

        return <<<HTML
<!DOCTYPE html>
<html lang="nl">
<head>
  <meta charset="UTF-8">
  <title>Factuur {$num}</title>
  <style>
    body { font-family: DejaVu Sans, sans-serif; font-size: 11px; color: #1a1a2e; margin: 24px; }
    .header { border-bottom: 3px solid #E53935; padding-bottom: 12px; margin-bottom: 20px; }
    .header h1 { font-size: 20px; margin: 0; color: #1a1a2e; }
    .header .brand { font-size: 10px; color: #E53935; letter-spacing: 0.5px; margin-top: 2px; }
    h2 { font-size: 14px; font-weight: 600; margin: 16px 0 8px; color: #1a1a2e; }
    .invoice-num { font-size: 18px; font-weight: 700; color: #E53935; letter-spacing: 0.5px; }
    .two-col { display: table; width: 100%; margin: 12px 0; }
    .two-col > div { display: table-cell; width: 50%; vertical-align: top; padding-right: 24px; }
    table { width: 100%; border-collapse: collapse; margin-top: 16px; }
    th, td { border: 1px solid #ddd; padding: 10px; text-align: left; }
    th { background: #f8f8f8; font-weight: 600; color: #333; }
    .total-row { background: #fff5f5; font-weight: 700; font-size: 13px; }
    .total-row td { border-top: 2px solid #E53935; }
    .meta { margin-top: 24px; font-size: 10px; color: #666; padding-top: 12px; border-top: 1px solid #eee; }
  </style>
</head>
<body>
  <div class="header">
    {$logoHtml}
    <h1>{$business}</h1>
    <div class="brand">FACTUUR VIA GYMIES</div>
  </div>
  <p><span class="invoice-num">Factuur {$num}</span>{$gymiesHtml}</p>
  <p><strong>Factuurdatum:</strong> {$invoiceDate} &nbsp;|&nbsp; <strong>Dienstdatum:</strong> {$serviceDate} &nbsp;|&nbsp; <strong>Dienst:</strong> {$serviceType}</p>
  <div class="two-col">
    <div>
      <h2>Leverancier</h2>
      <strong>{$business}</strong><br>{$trainerAddressHtml}
    </div>
    <div>
      <h2>Factuur aan</h2>
      <strong>{$clientName}</strong><br>{$clientAddressHtml}{$clientExtra}
    </div>
  </div>
  <h2>Omschrijving</h2>
  <p>{$desc}</p>
  <table>
    <tr><th>Omschrijving</th><th style="text-align:right;width:80px">Bedrag</th></tr>
    <tr><td>{$desc}</td><td style="text-align:right">€ {$total}</td></tr>
  </table>
  <table>
    <tr><td>Subtotaal excl. BTW</td><td style="text-align:right">€ {$net}</td></tr>
    <tr><td>BTW</td><td style="text-align:right">€ {$vat}</td></tr>
    <tr class="total-row"><td>Totaal incl. BTW</td><td style="text-align:right">€ {$total}</td></tr>
  </table>
  <div class="meta">
    {$kvkHtml}{$vatHtml}
    Factuurdatum: {$invoiceDate} &nbsp;|&nbsp; Gymies – Personal Trainer Platform
  </div>
</body>
</html>
HTML;
    }

    /** Logo-URL: organisatie logo of trainer avatar. */
    private static function resolveLogoUrl(object $r): string
    {
        $trainerId = (int) ($r->trainer_user_id ?? 0);
        if ($trainerId <= 0) {
            return '';
        }
        if (Schema::hasTable('gymies_organisation_trainers') && Schema::hasTable('gymies_organisations')) {
            $org = DB::table('gymies_organisation_trainers as ot')
                ->join('gymies_organisations as o', 'o.id', '=', 'ot.organisation_id')
                ->where('ot.trainer_user_id', $trainerId)
                ->where('ot.status', 'active')
                ->whereNotNull('o.logo_url')
                ->where('o.logo_url', '!=', '')
                ->value('o.logo_url');
            if ($org !== null && trim((string) $org) !== '') {
                return trim((string) $org);
            }
        }
        if (Schema::hasTable('gymies_trainer_profiles') && Schema::hasColumn('gymies_trainer_profiles', 'avatar_url')) {
            $avatar = DB::table('gymies_trainer_profiles')
                ->where('user_id', $trainerId)
                ->value('avatar_url');
            if ($avatar !== null && trim((string) $avatar) !== '') {
                return trim((string) $avatar);
            }
        }
        return '';
    }
}
