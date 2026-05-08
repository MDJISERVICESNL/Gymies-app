<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpFoundation\Response;

final class GymiesComplianceController extends Controller
{
    public function export(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $userId = (int) $user->id;
        // T-001 FIXED: export beperkt tot eigen data, GDPR audit trail toegevoegd
        Log::info('GYMIES_GDPR_EXPORT', [
            'exporter_id' => $user->id,
            'exporter_role' => $user->role,
            'exported_at' => now()->toIso8601String(),
            'ip' => $request->server('REMOTE_ADDR'),
        ]);

        // S-078: IDOR GDPR Export — ensure user can only export their own data
        $bookings = DB::table('gymies_bookings')
            ->where(function ($q) use ($userId) {
                $q->where('client_user_id', $userId)
                  ->orWhere('trainer_user_id', $userId);
            })
            ->orderByDesc('id')
            ->get();
        $consents = DB::getSchemaBuilder()->hasTable('gymies_user_consents')
            ? DB::table('gymies_user_consents')->where('user_id', $userId)->get()
            : collect();
        $cookies = DB::getSchemaBuilder()->hasTable('gymies_cookie_preferences')
            ? DB::table('gymies_cookie_preferences')->where('user_id', $userId)->first()
            : null;

        // T-001 FIXED: trainers mogen geen client-persoonsdata exporteren
        if ($user->role === 'trainer') {
            $bookings = $bookings->map(function ($row) {
                unset($row->client_email, $row->client_phone, $row->client_bsn);
                return $row;
            });
        }

        return response()->json([
            'data' => [
                'user' => DB::table('gymies_users')->where('id', $userId)->first(),
                'bookings' => $bookings,
                'consents' => $consents,
                'cookie_preferences' => $cookies,
                'generated_at' => now()->toIso8601String(),
            ],
        ]);
    }

    /**
     * Zelfde export als JSON, maar als PDF (of HTML print-to-PDF als Dompdf ontbreekt).
     */
    public function exportPdf(Request $request): Response
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $userId = (int) $user->id;
        // S-078: IDOR GDPR Export — ensure user can only export their own data
        $userRow = DB::table('gymies_users')->where('id', $userId)->first();
        $bookings = DB::table('gymies_bookings')
            ->where(function ($q) use ($userId) {
                $q->where('client_user_id', $userId)
                  ->orWhere('trainer_user_id', $userId);
            })
            ->orderByDesc('id')
            ->get();
        $consents = DB::getSchemaBuilder()->hasTable('gymies_user_consents')
            ? DB::table('gymies_user_consents')->where('user_id', $userId)->get()
            : collect();
        $cookies = DB::getSchemaBuilder()->hasTable('gymies_cookie_preferences')
            ? DB::table('gymies_cookie_preferences')->where('user_id', $userId)->first()
            : null;

        $generatedAt = now()->toIso8601String();
        $redacted = ['password', 'password_hash', 'remember_token', 'two_factor_secret', 'mollie_access_token', 'mollie_refresh_token'];
        $userArr = $userRow ? (array) $userRow : [];
        foreach ($redacted as $k) {
            unset($userArr[$k]);
        }

        $html = $this->renderGdprExportHtml($userArr, $bookings, $consents, $cookies, $generatedAt);

        $fileName = 'gymies-data-export-' . $userId . '-' . date('Y-m-d') . '.pdf';

        if (\class_exists(\Dompdf\Dompdf::class)) {
            $options = new \Dompdf\Options();
            $options->set('isRemoteEnabled', false);
            $options->set('defaultFont', 'DejaVu Sans');
            $dompdf = new \Dompdf\Dompdf($options);
            $dompdf->loadHtml($html);
            $dompdf->setPaper('A4', 'portrait');
            $dompdf->render();

            return response($dompdf->output(), 200, [
                'Content-Type' => 'application/pdf',
                'Content-Disposition' => 'attachment; filename="' . $fileName . '"',
            ]);
        }

        // Fallback: HTML — gebruiker kan afdrukken → PDF
        $htmlName = 'gymies-data-export-' . $userId . '-' . date('Y-m-d') . '.html';

        return response($html, 200, [
            'Content-Type' => 'text/html; charset=UTF-8',
            'Content-Disposition' => 'attachment; filename="' . $htmlName . '"',
        ]);
    }

    /**
     * @param array<string, mixed> $userArr
     * @param \Illuminate\Support\Collection<int, object> $bookings
     * @param \Illuminate\Support\Collection<int, object> $consents
     */
    private function renderGdprExportHtml(
        array $userArr,
        $bookings,
        $consents,
        ?object $cookies,
        string $generatedAt
    ): string {
        $e = static function ($v): string {
            if ($v === null) {
                return '';
            }
            if (\is_bool($v)) {
                return $v ? 'ja' : 'nee';
            }
            if (\is_scalar($v)) {
                return \htmlspecialchars((string) $v, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
            }

            return \htmlspecialchars(\json_encode($v, JSON_UNESCAPED_UNICODE), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        };

        $rowsUser = '';
        foreach ($userArr as $k => $v) {
            $rowsUser .= '<tr><td style="padding:4px 8px;border:1px solid #ccc;">' . $e((string) $k) . '</td>'
                . '<td style="padding:4px 8px;border:1px solid #ccc;">' . $e($v) . '</td></tr>';
        }

        $rowsBookings = '';
        foreach ($bookings as $b) {
            $b = (array) $b;
            $rowsBookings .= '<tr>';
            foreach (['id', 'status', 'starts_at', 'ends_at', 'client_user_id', 'trainer_user_id', 'created_at'] as $col) {
                $rowsBookings .= '<td style="padding:4px 6px;border:1px solid #ccc;font-size:10px;">'
                    . $e($b[$col] ?? '') . '</td>';
            }
            $rowsBookings .= '</tr>';
        }
        if ($rowsBookings === '') {
            $rowsBookings = '<tr><td colspan="7" style="padding:8px;border:1px solid #ccc;">Geen boekingen.</td></tr>';
        }

        $consentsHtml = $consents->isEmpty()
            ? '<p>Geen consent-registraties.</p>'
            : '<pre style="font-size:10px;">' . $e(\json_encode($consents->all(), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)) . '</pre>';
        $cookiesHtml = $cookies === null
            ? '<p>Geen cookievoorkeuren opgeslagen.</p>'
            : '<pre style="font-size:10px;">' . $e(\json_encode((array) $cookies, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)) . '</pre>';

        return '<!DOCTYPE html><html lang="nl"><head><meta charset="UTF-8"><title>Data-export AVG Gymies</title>'
            . '<style>body{font-family:DejaVu Sans,sans-serif;font-size:11px;margin:24px;} h1{font-size:18px;} h2{font-size:14px;margin-top:16px;} table{border-collapse:collapse;width:100%;}</style></head><body>'
            . '<h1>Data-export (AVG)</h1>'
            . '<p><strong>Gegenereerd:</strong> ' . $e($generatedAt) . '</p>'
            . '<p>Dit overzicht bevat de bij Gymies opgeslagen gegevens die aan jouw account zijn gekoppeld. '
            . 'Gevoelige velden (wachtwoord, tokens) zijn niet opgenomen.</p>'
            . '<h2>Accountgegevens</h2><table>' . $rowsUser . '</table>'
            . '<h2>Boekingen</h2><table><thead><tr>'
            . '<th style="border:1px solid #ccc;padding:4px;">id</th><th style="border:1px solid #ccc;padding:4px;">status</th>'
            . '<th style="border:1px solid #ccc;padding:4px;">starts_at</th><th style="border:1px solid #ccc;padding:4px;">ends_at</th>'
            . '<th style="border:1px solid #ccc;padding:4px;">client_user_id</th><th style="border:1px solid #ccc;padding:4px;">trainer_user_id</th>'
            . '<th style="border:1px solid #ccc;padding:4px;">created_at</th></tr></thead><tbody>' . $rowsBookings . '</tbody></table>'
            . '<h2>Toestemmingen</h2>' . $consentsHtml
            . '<h2>Cookievoorkeuren</h2>' . $cookiesHtml
            . '<p style="margin-top:24px;color:#666;font-size:10px;">Gymies — AVG data-export</p>'
            . '</body></html>';
    }

    public function deleteRequest(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        // T-002 FIXED: fail-secure rate limiting — bij DB fout altijd blokkeren
        try {
            $userId = (int) $user->id;
            $rlKey = 'gdpr_delete_req:' . $userId;
            $windowStart = now()->subHours(24);
            $maxAttempts = 1; // max 1 per 24 uur
            $attemptCount = DB::table('gymies_rate_limits')
                ->where('key', $rlKey)
                ->where('window_start', '>=', $windowStart)
                ->count();
            if ($attemptCount >= $maxAttempts) {
                return response()->json(['message' => 'Te veel verwijderverzoeken. Probeer het later opnieuw.'], 429);
            }
            DB::table('gymies_rate_limits')->insert([
                'key' => $rlKey,
                'window_start' => $windowStart,
                'created_at' => now(),
            ]);
        } catch (\Throwable $e) {
            // T-002: bij DB fout → altijd blokkeren (fail-secure)
            return response()->json(['message' => 'Beveiliging tijdelijk niet beschikbaar.'], 503);
        }

        if (DB::getSchemaBuilder()->hasTable('gymies_audit_log')) {
            DB::table('gymies_audit_log')->insert([
                'user_id' => $user->id,
                'action' => 'gdpr_delete_requested',
                'entity_type' => 'user',
                'entity_id' => $user->id,
                'new_values' => json_encode(['requested_at' => now()->toIso8601String()], JSON_UNESCAPED_UNICODE),
                'ip_address' => $request->ip(),
                'created_at' => now(),
            ]);
        }

        return response()->json([
            'data' => [
                'status' => 'requested',
                'message' => 'Verwijderverzoek ontvangen. Support verwerkt dit verzoek handmatig.',
            ],
        ], 202);
    }

    /**
     * Definitief account verwijderen (trainer of klant): user-rij wissen — FK CASCADE ruimt gerelateerde data op.
     * Vereist bevestigingstekst om per ongeluk tikken te voorkomen.
     */
    public function deleteAccount(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!empty($user->is_admin)) {
            return response()->json(['message' => 'Admin-accounts kunnen niet via dit endpoint worden verwijderd.'], 403);
        }

        // S-079: Account Deletion Weak Confirmation — add 24-hour rate limiting cooldown
        if (Schema::hasTable('gymies_rate_limits')) {
            $deleteKey = 'delete_account:' . (int) $user->id;
            $lastDelete = DB::table('gymies_rate_limits')
                ->where('key', $deleteKey)
                ->orderByDesc('created_at')
                ->first();
            if ($lastDelete) {
                $lastDeleteTime = \Carbon\Carbon::parse($lastDelete->created_at);
                if (now()->diffInHours($lastDeleteTime) < 24) {
                    return response()->json(['message' => 'Je kunt je account maar eens per 24 uur verwijderen. Probeer het later opnieuw.'], 429);
                }
            }
        }

        $request->validate([
            'confirm' => 'required|string',
        ]);
        $confirm = trim((string) $request->input('confirm'));
        if ($confirm !== 'VERWIJDER MIJN ACCOUNT') {
            return response()->json([
                'message' => 'Typ exact: VERWIJDER MIJN ACCOUNT om te bevestigen.',
            ], 422);
        }

        $userId = (int) $user->id;
        $role = strtolower((string) ($user->role ?? ''));
        if (!\in_array($role, ['trainer', 'klant'], true)) {
            return response()->json([
                'message' => 'Dit accounttype kan hier niet definitief worden verwijderd. Gebruik het verwijderverzoek (handmatige verwerking).',
            ], 422);
        }

        if (DB::getSchemaBuilder()->hasTable('gymies_audit_log')) {
            DB::table('gymies_audit_log')->insert([
                'user_id' => $userId,
                'action' => 'account_deleted_self',
                'entity_type' => 'user',
                'entity_id' => $userId,
                'new_values' => json_encode(['deleted_at' => now()->toIso8601String()], JSON_UNESCAPED_UNICODE),
                'ip_address' => $request->ip(),
                'created_at' => now(),
            ]);
        }

        try {
            DB::transaction(function () use ($userId) {
                // Sessies expliciet wissen (token ongeldig vóór user delete)
                if (DB::getSchemaBuilder()->hasTable('gymies_sessions')) {
                    DB::table('gymies_sessions')->where('user_id', $userId)->delete();
                }
                $deleted = DB::table('gymies_users')->where('id', $userId)->delete();
                if ($deleted === 0) {
                    throw new \RuntimeException('Gebruiker niet gevonden of al verwijderd.');
                }
            });

            // S-079: Account Deletion Weak Confirmation — register deletion attempt for rate limiting
            if (Schema::hasTable('gymies_rate_limits')) {
                DB::table('gymies_rate_limits')->insert([
                    'key'          => 'delete_account:' . $userId,
                    'window_start' => now(),
                    'created_at'   => now(),
                ]);
            }
        } catch (\Throwable $e) {
            logger()->error('Gymies deleteAccount failed', [
                'user_id' => $userId,
                'error' => $e->getMessage(),
            ]);

            return response()->json([
                'message' => 'Verwijderen mislukt door databasebeperking. Neem contact op met support.',
            ], 422);
        }

        return response()->json([
            'data' => [
                'status' => 'deleted',
                'message' => 'Je account en bijbehorende gegevens zijn verwijderd.',
            ],
        ], 200);
    }

    public function consent(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $userId = (int) $user->id;
        $consents = DB::getSchemaBuilder()->hasTable('gymies_user_consents')
            ? DB::table('gymies_user_consents')
                ->where('user_id', $userId)
                ->get(['consent_type', 'accepted_at'])
            : collect();
        $cookies = DB::getSchemaBuilder()->hasTable('gymies_cookie_preferences')
            ? DB::table('gymies_cookie_preferences')->where('user_id', $userId)->first()
            : null;

        return response()->json([
            'data' => [
                'consents' => $consents,
                'cookie_preferences' => $cookies,
            ],
        ]);
    }

    public function updateConsent(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $request->validate([
            'marketing_enabled' => 'nullable|boolean',
            'analytics_enabled' => 'nullable|boolean',
            'important_only_email' => 'nullable|boolean',
        ]);

        $userId = (int) $user->id;

        if (DB::getSchemaBuilder()->hasTable('gymies_cookie_preferences')) {
            $existing = DB::table('gymies_cookie_preferences')->where('user_id', $userId)->first();
            $payload = [
                'analytics_enabled' => $request->boolean('analytics_enabled', false) ? 1 : 0,
                'marketing_enabled' => $request->boolean('marketing_enabled', false) ? 1 : 0,
                'functional_enabled' => 1,
                'updated_at' => now(),
            ];
            if ($existing) {
                DB::table('gymies_cookie_preferences')->where('user_id', $userId)->update($payload);
            } else {
                $payload['user_id'] = $userId;
                DB::table('gymies_cookie_preferences')->insert($payload);
            }
        }

        if (DB::getSchemaBuilder()->hasTable('gymies_user_consents')) {
            $this->upsertConsent($userId, 'marketing', $request->boolean('marketing_enabled', false));
            $this->upsertConsent($userId, 'analytics', $request->boolean('analytics_enabled', false));
            $this->upsertConsent($userId, 'important_only_email', $request->boolean('important_only_email', false));
        }

        return $this->consent($request);
    }

    private function upsertConsent(int $userId, string $type, bool $enabled): void
    {
        $existing = DB::table('gymies_user_consents')
            ->where('user_id', $userId)
            ->where('consent_type', $type)
            ->first();

        if (!$enabled) {
            // In dit schema betekent afwezig record: geen toestemming.
            if ($existing) {
                DB::table('gymies_user_consents')->where('id', $existing->id)->delete();
            }
            return;
        }

        $payload = [
            'accepted_at' => now(),
            'ip_address' => request()->ip(),
        ];
        if ($existing) {
            DB::table('gymies_user_consents')->where('id', $existing->id)->update($payload);
            return;
        }

        DB::table('gymies_user_consents')->insert([
            'user_id' => $userId,
            'consent_type' => $type,
            'accepted_at' => now(),
            'ip_address' => request()->ip(),
            'created_at' => now(),
        ]);
    }
}
