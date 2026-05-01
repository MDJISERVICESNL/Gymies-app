<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use App\Services\GymiesInvoicePdfGenerator;

final class GymiesInvoiceController extends Controller
{
    /**
     * Trainer: lijst van gegenereerde facturen (die zij naar klanten hebben gestuurd).
     */
    public function trainerInvoices(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        if (!Schema::hasTable('gymies_trainer_invoices')) {
            return response()->json(['invoices' => []]);
        }

        $invoices = DB::table('gymies_trainer_invoices as i')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'i.client_user_id')
            ->where('i.trainer_user_id', (int) $user->id)
            ->select('i.*', 'c.display_name as client_name', 'c.email as client_email')
            ->orderByDesc('i.created_at')
            ->limit(100)
            ->get();

        return response()->json(['invoices' => $invoices]);
    }

    /**
     * Klant: lijst van ontvangen facturen (van trainers).
     */
    public function clientInvoices(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_trainer_invoices')) {
            return response()->json(['invoices' => []]);
        }

        $invoices = DB::table('gymies_trainer_invoices as i')
            ->leftJoin('gymies_users as t', 't.id', '=', 'i.trainer_user_id')
            ->where('i.client_user_id', (int) $user->id)
            ->select('i.*', 't.display_name as trainer_name')
            ->orderByDesc('i.created_at')
            ->limit(100)
            ->get();

        return response()->json(['invoices' => $invoices]);
    }

    /**
     * Klant: download factuur-PDF (alleen eigen facturen).
     */
    public function clientInvoiceDownload(Request $request, int $id): \Symfony\Component\HttpFoundation\Response|JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_trainer_invoices')) {
            return response()->json(['message' => 'Geen factuurtabel'], 404);
        }

        $row = DB::table('gymies_trainer_invoices')
            ->where('id', $id)
            ->where('client_user_id', (int) $user->id)
            ->first();

        if (!$row) {
            return response()->json(['message' => 'Factuur niet gevonden'], 404);
        }

        $pdfUrl = property_exists($row, 'pdf_url') ? (string) ($row->pdf_url ?? '') : '';
        if ($pdfUrl === '' && Schema::hasColumn('gymies_trainer_invoices', 'pdf_url') && class_exists(GymiesInvoicePdfGenerator::class)) {
            $url = GymiesInvoicePdfGenerator::generateAndStore($row);
            if ($url !== null) {
                DB::table('gymies_trainer_invoices')->where('id', $id)->update(['pdf_url' => $url]);
                $pdfUrl = $url;
            }
        }

        $publicBase = function_exists('storage_path') ? storage_path('app/public') : null;
        if ($pdfUrl !== '' && $publicBase !== null && str_starts_with($pdfUrl, '/storage/')) {
            $rel = substr($pdfUrl, strlen('/storage/'));
            $abs = $publicBase . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $rel);
            if (is_file($abs) && is_readable($abs)) {
                $ext = strtolower(pathinfo($abs, PATHINFO_EXTENSION));
                $name = ($row->invoice_number ?? 'factuur') . '.' . ($ext === 'pdf' ? 'pdf' : 'html');
                return response()->download($abs, $name);
            }
        }

        return response()->json(['message' => 'PDF nog niet beschikbaar'], 404);
    }

    /**
     * Genereer factuur voor een voltooide boeking (intern aangeroepen vanuit cron).
     */
    public static function generateForBooking(object $booking): ?int
    {
        if (!Schema::hasTable('gymies_trainer_invoices')) {
            return null;
        }

        $existing = DB::table('gymies_trainer_invoices')
            ->where('booking_id', (int) $booking->id)
            ->first();
        if ($existing) {
            return (int) $existing->id;
        }

        $trainer = DB::table('gymies_users')->where('id', (int) $booking->trainer_user_id)->first();
        if (!$trainer) {
            return null;
        }
        $client = DB::table('gymies_users')->where('id', (int) $booking->client_user_id)->first();
        if (!$client) {
            return null;
        }

        $kvkNumber = property_exists($trainer, 'coc_number') ? $trainer->coc_number : null;
        $vatNumber = property_exists($trainer, 'vat_number') ? $trainer->vat_number : null;
        $businessName = property_exists($trainer, 'business_name') ? $trainer->business_name : ($trainer->display_name ?? 'Trainer');

        $amountCents = (int) ($booking->amount_cents ?? 0);
        $vatPercent = 21.00;
        $vatCents = (int) round($amountCents * ($vatPercent / (100 + $vatPercent)));
        $netCents = $amountCents - $vatCents;

        $year = date('Y');
        $lastInvoice = DB::table('gymies_trainer_invoices')
            ->where('trainer_user_id', (int) $booking->trainer_user_id)
            ->where('invoice_number', 'LIKE', "%-{$year}-%")
            ->orderByDesc('id')
            ->first(['invoice_number']);

        $seq = 1;
        if ($lastInvoice && preg_match('/-(\d+)$/', $lastInvoice->invoice_number, $m)) {
            $seq = (int) $m[1] + 1;
        }

        $prefix = strtoupper(substr(preg_replace('/[^a-zA-Z]/', '', $businessName), 0, 5));
        $trainerInvoiceNumber = "{$prefix}-{$year}-" . str_pad((string) $seq, 4, '0', STR_PAD_LEFT);

        $scheduledDate = date('d-m-Y', strtotime($booking->scheduled_at));
        $branded = GymiesPlanManager::can((int) $booking->trainer_user_id, GymiesPlanManager::FEATURE_INVOICE_BRANDED);
        // Starter: standaard Gymies-bon in omschrijving; Pro/Studio: factuur met trainergegevens (PDF later met logo/BTW)
        $description = $branded
            ? "Factuur: Personal Training sessie op {$scheduledDate}"
            : "Gymies bon – betaling bevestigd, sessie op {$scheduledDate}";

        $clientName = trim((string) (($client->display_name ?? '') !== '' ? $client->display_name : (($client->first_name ?? '') . ' ' . ($client->last_name ?? ''))));
        $trainerAddress = property_exists($trainer, 'address_line1') ? (string) ($trainer->address_line1 ?? '') : '';
        $trainerPostcode = property_exists($trainer, 'postcode') ? (string) ($trainer->postcode ?? '') : '';
        $trainerCity = property_exists($trainer, 'city') ? (string) ($trainer->city ?? '') : '';
        $trainerCountry = property_exists($trainer, 'country') ? (string) ($trainer->country ?? 'NL') : 'NL';
        $clientAddress = property_exists($client, 'address_line1') ? (string) ($client->address_line1 ?? '') : '';
        $clientPostcode = property_exists($client, 'postcode') ? (string) ($client->postcode ?? '') : '';
        $clientCity = property_exists($client, 'city') ? (string) ($client->city ?? '') : '';
        $clientCountry = property_exists($client, 'country') ? (string) ($client->country ?? 'NL') : 'NL';
        $trainerCustomerNumber = null;
        if (Schema::hasTable('gymies_trainer_client_numbers')) {
            $trainerCustomerNumber = DB::table('gymies_trainer_client_numbers')
                ->where('trainer_user_id', (int) $booking->trainer_user_id)
                ->where('client_user_id', (int) $booking->client_user_id)
                ->value('trainer_customer_number');
        }
        $invoiceDate = date('Y-m-d');
        $serviceDate = date('Y-m-d', strtotime((string) $booking->scheduled_at));
        $dueDate = date('Y-m-d', strtotime($invoiceDate . ' +14 days'));

        $insert = [
            'trainer_user_id' => (int) $booking->trainer_user_id,
            'client_user_id' => (int) $booking->client_user_id,
            'booking_id' => (int) $booking->id,
            'invoice_number' => $trainerInvoiceNumber,
            'amount_cents' => $netCents,
            'vat_percent' => $vatPercent,
            'vat_cents' => $vatCents,
            'total_cents' => $amountCents,
            'kvk_number' => $branded ? $kvkNumber : null,
            'vat_number' => $branded ? $vatNumber : null,
            'business_name' => $branded ? $businessName : 'Gymies',
            'description' => $description,
            'status' => 'generated',
            'created_at' => now(),
        ];
        if (Schema::hasColumn('gymies_trainer_invoices', 'trainer_invoice_number')) {
            $insert['trainer_invoice_number'] = $trainerInvoiceNumber;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'invoice_date')) {
            $insert['invoice_date'] = $invoiceDate;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'service_date')) {
            $insert['service_date'] = $serviceDate;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'due_date')) {
            $insert['due_date'] = $dueDate;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'currency')) {
            $insert['currency'] = 'EUR';
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'service_type')) {
            $insert['service_type'] = 'personal_training';
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'price_ex_vat_cents')) {
            $insert['price_ex_vat_cents'] = $netCents;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'price_inc_vat_cents')) {
            $insert['price_inc_vat_cents'] = $amountCents;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'company_name')) {
            $insert['company_name'] = $branded ? $businessName : 'Gymies';
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'trainer_name')) {
            $insert['trainer_name'] = (string) ($trainer->display_name ?? '');
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'trainer_address_line1')) {
            $insert['trainer_address_line1'] = $trainerAddress !== '' ? $trainerAddress : null;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'trainer_postcode')) {
            $insert['trainer_postcode'] = $trainerPostcode !== '' ? $trainerPostcode : null;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'trainer_city')) {
            $insert['trainer_city'] = $trainerCity !== '' ? $trainerCity : null;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'trainer_country')) {
            $insert['trainer_country'] = $trainerCountry !== '' ? $trainerCountry : 'NL';
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'client_name')) {
            $insert['client_name'] = $clientName !== '' ? $clientName : null;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'trainer_customer_number')) {
            $insert['trainer_customer_number'] = $trainerCustomerNumber !== null ? (string) $trainerCustomerNumber : null;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'client_address_line1')) {
            $insert['client_address_line1'] = $clientAddress !== '' ? $clientAddress : null;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'client_postcode')) {
            $insert['client_postcode'] = $clientPostcode !== '' ? $clientPostcode : null;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'client_city')) {
            $insert['client_city'] = $clientCity !== '' ? $clientCity : null;
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'client_country')) {
            $insert['client_country'] = $clientCountry !== '' ? $clientCountry : 'NL';
        }
        if (Schema::hasColumn('gymies_trainer_invoices', 'pdf_url')) {
            $insert['pdf_url'] = null;
        }
        $id = DB::table('gymies_trainer_invoices')->insertGetId($insert);

        if (Schema::hasColumn('gymies_trainer_invoices', 'gymies_invoice_number')) {
            $gymiesInvoiceNumber = 'GYM-' . date('Y') . '-' . str_pad((string) $id, 8, '0', STR_PAD_LEFT);
            DB::table('gymies_trainer_invoices')->where('id', $id)->update([
                'gymies_invoice_number' => $gymiesInvoiceNumber,
            ]);
        }

        // PDF/HTML genereren en pdf_url vullen (Dompdf optioneel)
        if (Schema::hasColumn('gymies_trainer_invoices', 'pdf_url') && class_exists(GymiesInvoicePdfGenerator::class)) {
            $row = DB::table('gymies_trainer_invoices')->where('id', $id)->first();
            if ($row) {
                $url = GymiesInvoicePdfGenerator::generateAndStore($row);
                if ($url !== null) {
                    DB::table('gymies_trainer_invoices')->where('id', $id)->update(['pdf_url' => $url]);
                }
            }
        }

        return $id;
    }

    /**
     * Trainer: download kwartaaloverzicht als ZIP (CSV per factuur tot PDF-pijplijn live is).
     */
    public function trainerInvoicesQuarterZip(Request $request): \Symfony\Component\HttpFoundation\Response|JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }
        if (!Schema::hasTable('gymies_trainer_invoices')) {
            return response()->json(['message' => 'Geen factuurtabel'], 404);
        }
        $year = min(max((int) $request->query('year', (int) date('Y')), 2020), 2100);
        $quarter = min(max((int) $request->query('quarter', (int) ceil((int) date('n') / 3)), 1), 4);
        $startMonth = ($quarter - 1) * 3 + 1;
        $endMonth = $startMonth + 2;
        $from = sprintf('%04d-%02d-01 00:00:00', $year, $startMonth);
        $to = date('Y-m-t 23:59:59', strtotime(sprintf('%04d-%02d-01', $year, $endMonth)));

        $rows = DB::table('gymies_trainer_invoices as i')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'i.client_user_id')
            ->where('i.trainer_user_id', (int) $user->id)
            ->where('i.created_at', '>=', $from)
            ->where('i.created_at', '<=', $to)
            ->orderBy('i.id')
            ->select('i.*', 'c.display_name as client_name', 'c.email as client_email')
            ->get();

        if ($rows->isEmpty()) {
            return response()->json(['message' => 'Geen facturen in dit kwartaal.'], 404);
        }

        if (!class_exists(\ZipArchive::class)) {
            return response()->json(['message' => 'ZIP niet beschikbaar op server'], 501);
        }
        $zipPath = sys_get_temp_dir() . '/gymies_invoices_' . $user->id . '_' . $year . '_Q' . $quarter . '.zip';
        $zip = new \ZipArchive();
        if ($zip->open($zipPath, \ZipArchive::CREATE | \ZipArchive::OVERWRITE) !== true) {
            return response()->json(['message' => 'ZIP aanmaken mislukt'], 500);
        }
        $index = 1;
        $publicBase = function_exists('storage_path') ? storage_path('app/public') : null;
        $pdfAdded = [];
        foreach ($rows as $r) {
            $csv = "invoice_number,total_cents,description,created_at,client_name,client_email\n";
            $csv .= sprintf(
                '"%s",%d,"%s","%s","%s","%s"' . "\n",
                str_replace('"', '""', (string) $r->invoice_number),
                (int) $r->total_cents,
                str_replace('"', '""', (string) ($r->description ?? '')),
                (string) $r->created_at,
                str_replace('"', '""', (string) ($r->client_name ?? '')),
                str_replace('"', '""', (string) ($r->client_email ?? ''))
            );
            $safeName = preg_replace('/[^a-zA-Z0-9_-]/', '_', $r->invoice_number);
            $addedPdf = false;
            $pdfUrl = property_exists($r, 'pdf_url') ? (string) ($r->pdf_url ?? '') : '';
            // On-demand PDF genereren als pdf_url leeg is (backfill voor bestaande facturen)
            if ($pdfUrl === '' && Schema::hasColumn('gymies_trainer_invoices', 'pdf_url') && class_exists(GymiesInvoicePdfGenerator::class)) {
                $fresh = DB::table('gymies_trainer_invoices')->where('id', (int) $r->id)->first();
                if ($fresh) {
                    $url = GymiesInvoicePdfGenerator::generateAndStore($fresh);
                    if ($url !== null) {
                        DB::table('gymies_trainer_invoices')->where('id', (int) $r->id)->update(['pdf_url' => $url]);
                        $pdfUrl = $url;
                    }
                }
            }
            if ($pdfUrl !== '' && $publicBase !== null && str_starts_with($pdfUrl, '/storage/')) {
                $rel = substr($pdfUrl, strlen('/storage/'));
                $abs = $publicBase . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $rel);
                if (is_file($abs) && is_readable($abs)) {
                    $ext = strtolower(pathinfo($abs, PATHINFO_EXTENSION));
                    if ($ext === 'pdf' || $ext === 'html') {
                        $zip->addFile($abs, 'factuur_' . $index . '_' . $safeName . '.' . $ext);
                        $addedPdf = true;
                    }
                }
            }
            $pdfAdded[(int) $r->id] = $addedPdf;
            if (!$addedPdf) {
                $zip->addFromString('factuur_' . $index . '_' . $safeName . '.csv', $csv);
            }
            $index++;
        }
        // Overzicht-CSV: alle facturen in kwartaal
        $overzichtCsv = "invoice_number,total_cents,client_name,created_at,pdf_aanwezig\n";
        foreach ($rows as $r) {
            $hasPdf = $pdfAdded[(int) $r->id] ?? (property_exists($r, 'pdf_url') && (string) ($r->pdf_url ?? '') !== '');
            $overzichtCsv .= sprintf(
                '"%s",%d,"%s","%s",%s' . "\n",
                str_replace('"', '""', (string) $r->invoice_number),
                (int) $r->total_cents,
                str_replace('"', '""', (string) ($r->client_name ?? '')),
                (string) $r->created_at,
                $hasPdf ? 'ja' : 'nee'
            );
        }
        $zip->addFromString('overzicht_Q' . $quarter . '_' . $year . '.csv', $overzichtCsv);
        $zip->addFromString('README.txt', "Gymies facturen {$year} Q{$quarter}\n\n" .
            "- PDF/HTML per factuur indien gegenereerd (Gymies-template)\n" .
            "- CSV per factuur als fallback bij ontbrekende PDF\n" .
            "- overzicht_Q{$quarter}_{$year}.csv = totaaloverzicht\n");
        $zip->close();

        return response()->download($zipPath, "gymies_facturen_{$year}_Q{$quarter}.zip")->deleteFileAfterSend(true);
    }
}
