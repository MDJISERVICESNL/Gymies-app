<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trainer documenten voor facturering en compliance.
 * GET  trainer/documents – documenten ophalen
 * PUT  trainer/documents – documenten opslaan
 */
class GymiesTrainerDocumentsController
{
    private const ALLOWED_KEYS = [
        'company_name',
        'companyName',
        'kvk_number',
        'kvk',
        'vat_number',
        'vat',
        'trainer_address_line1',
        'address_line1',
        'address',
        'trainer_postcode',
        'postcode',
        'trainer_city',
        'city',
        'trainer_country',
        'country',
        'country_code',
        'vog_url',
        'vog_document_url',
        'diploma_urls',
        'diploma_url',
    ];

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $docs = $this->loadDocuments((int) $user->id);
        return response()->json(['data' => $docs]);
    }

    public function update(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $body = $request->all();

        // Accepteer geneste structuren (documents, company, etc.)
        $flat = [];
        foreach (['documents', 'company', 'company_profile', 'companyProfile'] as $key) {
            if (isset($body[$key]) && is_array($body[$key])) {
                $flat = array_merge($flat, $body[$key]);
            }
        }
        $flat = array_merge($body, $flat);

        $update = [];

        // company_name
        $company = $flat['company_name'] ?? $flat['companyName'] ?? null;
        if (is_string($company)) {
            $update['company_name'] = trim($company);
        }

        // kvk
        $kvk = $flat['kvk_number'] ?? $flat['kvk'] ?? null;
        if (is_string($kvk)) {
            $update['kvk_number'] = trim($kvk);
        }

        // vat
        $vat = $flat['vat_number'] ?? $flat['vat'] ?? null;
        if (is_string($vat)) {
            $update['vat_number'] = trim($vat);
        }

        // address
        $addr = $flat['trainer_address_line1'] ?? $flat['address_line1'] ?? $flat['address'] ?? null;
        if (is_string($addr)) {
            $update['trainer_address_line1'] = trim($addr);
        }

        // postcode
        $postcode = $flat['trainer_postcode'] ?? $flat['postcode'] ?? null;
        if (is_string($postcode)) {
            $update['trainer_postcode'] = trim($postcode);
        }

        // city
        $city = $flat['trainer_city'] ?? $flat['city'] ?? null;
        if (is_string($city)) {
            $update['trainer_city'] = trim($city);
        }

        // country
        $country = $flat['trainer_country'] ?? $flat['country'] ?? $flat['country_code'] ?? null;
        if (is_string($country)) {
            $update['trainer_country'] = trim($country);
        }

        // vog_url
        $vog = $flat['vog_url'] ?? $flat['vog_document_url'] ?? null;
        if (is_string($vog)) {
            $update['vog_url'] = trim($vog);
        }

        // diploma_urls
        $diplomas = $flat['diploma_urls'] ?? $flat['diploma_url'] ?? null;
        if (is_array($diplomas)) {
            $update['diploma_urls'] = array_values(array_map('strval', array_filter($diplomas)));
        } elseif (is_string($diplomas) && trim($diplomas) !== '') {
            $update['diploma_urls'] = array_values(array_filter(array_map('trim', explode("\n", $diplomas))));
        }

        if (empty($update)) {
            $docs = $this->loadDocuments((int) $user->id);
            return response()->json(['data' => $docs]);
        }

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return response()->json(['message' => 'Trainer-documenten tabel ontbreekt.'], 500);
        }

        // Alleen kolommen die bestaan
        $existingColumns = Schema::getColumnListing('gymies_trainer_profiles');
        $allowedUpdate = [];
        foreach ($update as $col => $value) {
            if (in_array($col, $existingColumns, true)) {
                $allowedUpdate[$col] = $value;
            }
        }

        if (isset($allowedUpdate['diploma_urls']) && is_array($allowedUpdate['diploma_urls'])) {
            $allowedUpdate['diploma_urls'] = json_encode($allowedUpdate['diploma_urls']);
        }

        $allowedUpdate['updated_at'] = now();

        $profile = DB::table('gymies_trainer_profiles')->where('user_id', (int) $user->id)->first();

        if ($profile) {
            DB::table('gymies_trainer_profiles')
                ->where('user_id', (int) $user->id)
                ->update($allowedUpdate);
        } else {
            $allowedUpdate['user_id'] = (int) $user->id;
            $allowedUpdate['created_at'] = now();
            DB::table('gymies_trainer_profiles')->insert($allowedUpdate);
        }

        $docs = $this->loadDocuments((int) $user->id);
        return response()->json(['data' => $docs]);
    }

    private function loadDocuments(int $userId): array
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return [];
        }

        $profile = DB::table('gymies_trainer_profiles')->where('user_id', $userId)->first();
        if (!$profile) {
            return [];
        }

        $row = (array) $profile;
        $docs = [];

        $map = [
            'company_name' => ['company_name', 'companyName'],
            'kvk_number' => ['kvk_number', 'kvk'],
            'vat_number' => ['vat_number', 'vat'],
            'trainer_address_line1' => ['trainer_address_line1', 'address_line1', 'address'],
            'trainer_postcode' => ['trainer_postcode', 'postcode'],
            'trainer_city' => ['trainer_city', 'city'],
            'trainer_country' => ['trainer_country', 'country', 'country_code'],
            'vog_url' => ['vog_url', 'vog_document_url'],
            'diploma_urls' => ['diploma_urls', 'diploma_url'],
        ];

        foreach ($map as $canonical => $aliases) {
            $value = null;
            foreach (array_merge([$canonical], $aliases) as $key) {
                if (isset($row[$key])) {
                    $v = $row[$key];
                    if ($v !== null && $v !== '') {
                        $value = $v;
                        break;
                    }
                }
            }
            if ($value !== null) {
                if ($canonical === 'diploma_urls' && is_string($value)) {
                    $decoded = json_decode($value, true);
                    $docs['diploma_urls'] = is_array($decoded) ? $decoded : [$value];
                } else {
                    $docs[$canonical] = $value;
                    foreach ($aliases as $a) {
                        if ($a !== $canonical) {
                            $docs[$a] = $value;
                        }
                    }
                }
            }
        }

        if (isset($docs['diploma_urls']) && !isset($docs['diploma_url'])) {
            $d = $docs['diploma_urls'];
            $docs['diploma_url'] = is_array($d) ? ($d[0] ?? null) : $d;
        }

        return $docs;
    }
}
