<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Throwable;

/**
 * GymiesHealthController
 *
 * Biedt health check endpoints voor monitoring, uptime robots en dashboards.
 *
 * Routes om toe te voegen aan routes_gymies_full.php:
 *
 *   // Public health check (voor uptime monitoring)
 *   Route::get('health',        [GymiesHealthController::class, 'ping']);
 *
 *   // Uitgebreide status (alleen voor cyber/admin)
 *   Route::get('health/status', [GymiesHealthController::class, 'status'])
 *       ->middleware(['gymies.auth', 'gymies.cyber:cyber.access']);
 */
final class GymiesHealthController extends Controller
{
    /**
     * GET /api/gymies/health
     *
     * Snelle ping — alleen database basis check.
     * Geschikt voor uptime monitoring (geen auth vereist).
     */
    public function ping(): JsonResponse
    {
        $dbOk    = $this->checkDatabase();
        $healthy = $dbOk['ok'];

        // T-057 FIXED: environment en versie verborgen in productie
        $response = [
            'status'    => $healthy ? 'ok' : 'degraded',
            'timestamp' => now()->toIso8601String(),
            'database'  => $dbOk['ok'] ? 'connected' : 'error',
        ];
        // Alleen in locale/test omgeving extra info tonen
        if (app()->environment('local', 'testing')) {
            $response['version'] = config('gymies.api_version', '1.0');
        }

        return response()->json($response, $healthy ? 200 : 503, [
            'Cache-Control' => 'no-store, no-cache',
            'X-API-Version' => config('gymies.api_version', '1.0'),
        ]);
    }

    /**
     * GET /api/gymies/health/status
     *
     * Uitgebreide status check (vereist cyber-toegang).
     * Controleert: database, cache, externe services, schijfruimte, wachtrijen.
     */
    public function status(Request $request): JsonResponse
    {
        $startTime = hrtime(true);

        $checks = [
            'database'       => $this->checkDatabase(),
            'cache'          => $this->checkCache(),
            'queue'          => $this->checkQueue(),
            'storage'        => $this->checkStorage(),
            'mollie'         => $this->checkMollie(),
            'reverb'         => $this->checkReverb(),
            'mail'           => $this->checkMail(),
            'sentry'         => $this->checkSentry(),
            'backup'         => $this->checkBackup(),
        ];

        // Circuit breaker status toevoegen aan Mollie check
        try {
            $cb = new \App\Http\Controllers\Gymies\MollieCircuitBreaker();
            $cbStatus = $cb->getStatus();
            $checks['mollie']['circuit_breaker'] = $cbStatus;
            if ($cbStatus['state'] === 'open') {
                $checks['mollie']['ok'] = false;
                $checks['mollie']['note'] = 'Circuit breaker OPEN — Mollie herhaaldelijk onbereikbaar';
            }
        } catch (\Throwable $e) {
            // Geen circuit breaker info beschikbaar — negeer
        }

        $allOk    = collect($checks)->every(fn ($c) => $c['ok']);
        $anyDown  = collect($checks)->contains(fn ($c) => !$c['ok'] && ($c['critical'] ?? false));
        $duration = (int) round((hrtime(true) - $startTime) / 1_000_000);

        $overallStatus = match (true) {
            $anyDown => 'down',
            !$allOk  => 'degraded',
            default  => 'ok',
        };

        // T-057 FIXED: environment en versie verborgen in productie
        $response = [
            'status'        => $overallStatus,
            'timestamp'     => now()->toIso8601String(),
            'checks'        => $checks,
            'check_time_ms' => $duration,
        ];
        // Alleen in locale/test omgeving extra info tonen
        if (app()->environment('local', 'testing')) {
            $response['environment'] = app()->environment();
            $response['version'] = config('gymies.api_version', '1.0');
        }

        return response()->json($response, $anyDown ? 503 : ($allOk ? 200 : 207), [
            'Cache-Control' => 'no-store, no-cache',
            'X-API-Version' => config('gymies.api_version', '1.0'),
        ]);
    }

    /**
     * GET /api/gymies/app-version
     *
     * Publiek endpoint voor force-update check.
     * Flutter app stuurt huidige versie, backend retourneert of update nodig is.
     *
     * Response:
     * Gedetailleerde queue metrics (admin only).
     * Toont pending/failed jobs, throughput, en worker status.
     */
    public function queueMetrics(): JsonResponse
    {
        $data = [
            'driver'     => config('queue.default'),
            'connection' => config('queue.connections.' . config('queue.default') . '.driver', 'unknown'),
        ];

        if (DB::getSchemaBuilder()->hasTable('jobs')) {
            // Pending per queue
            $data['pending'] = DB::table('jobs')
                ->selectRaw('queue, COUNT(*) as count')
                ->groupBy('queue')
                ->pluck('count', 'queue')
                ->toArray();
            $data['pending_total'] = array_sum($data['pending']);

            // Oudste wachtende job
            $oldest = DB::table('jobs')->orderBy('created_at', 'asc')->first(['created_at', 'queue', 'payload']);
            if ($oldest) {
                $data['oldest_job'] = [
                    'queue'      => $oldest->queue,
                    'waiting_s'  => (int) now()->diffInSeconds($oldest->created_at),
                    'created_at' => $oldest->created_at,
                    'class'      => $this->extractJobClass($oldest->payload),
                ];
            }

            // Throughput: jobs verwerkt in laatste uur (geschat via ID gap)
            $data['jobs_last_hour'] = DB::table('jobs')
                ->where('created_at', '>=', now()->subHour())
                ->count();
        }

        if (DB::getSchemaBuilder()->hasTable('failed_jobs')) {
            // Failed jobs breakdown
            $data['failed'] = [
                'last_hour' => DB::table('failed_jobs')
                    ->where('failed_at', '>=', now()->subHour())->count(),
                'last_24h'  => DB::table('failed_jobs')
                    ->where('failed_at', '>=', now()->subDay())->count(),
                'total'     => DB::table('failed_jobs')->count(),
            ];

            // Laatste 5 failed jobs
            $recentFailed = DB::table('failed_jobs')
                ->orderBy('failed_at', 'desc')
                ->limit(5)
                ->get(['id', 'queue', 'failed_at', 'exception']);

            $data['recent_failures'] = $recentFailed->map(fn ($f) => [
                'id'        => $f->id,
                'queue'     => $f->queue,
                'failed_at' => $f->failed_at,
                'error'     => \Illuminate\Support\Str::limit($f->exception ?? '', 200),
            ])->toArray();
        }

        return response()->json($data);
    }

    /**
     * Haal de job class naam uit een queue payload.
     */
    private function extractJobClass(?string $payload): ?string
    {
        if (!$payload) return null;
        $decoded = json_decode($payload, true);
        return $decoded['displayName'] ?? $decoded['job'] ?? null;
    }

    /**
     *  - min_version: laagste versie die nog werkt
     *  - latest_version: nieuwste versie
     *  - force_update: true als huidige versie te oud is
     *  - update_url_ios / update_url_android: store links
     */
    public function appVersion(Request $request): JsonResponse
    {
        // Minimale versies — pas aan wanneer je een breaking API change deployt
        $minVersion     = config('gymies.min_app_version', '1.0.0');
        $latestVersion  = config('gymies.latest_app_version', '1.2.1');

        $clientVersion = $request->input('version', '0.0.0');
        $platform      = $request->input('platform', 'unknown'); // ios / android

        $forceUpdate = version_compare($clientVersion, $minVersion, '<');

        return response()->json([
            'min_version'    => $minVersion,
            'latest_version' => $latestVersion,
            'force_update'   => $forceUpdate,
            'update_url_ios'     => 'https://apps.apple.com/app/gymies/id6760937860',
            'update_url_android' => 'https://play.google.com/store/apps/details?id=com.gymies.app',
            'message'        => $forceUpdate
                ? 'Er is een belangrijke update beschikbaar. Werk de app bij om door te gaan.'
                : null,
        ], 200, ['Cache-Control' => 'no-store, max-age=0']);
    }

    // ── Private checks ────────────────────────────────────────────────────────

    /** @return array{ok: bool, critical: bool, latency_ms?: int, error?: string} */
    private function checkDatabase(): array
    {
        try {
            $start = hrtime(true);
            DB::select('SELECT 1');
            $latency = (int) round((hrtime(true) - $start) / 1_000_000);

            // Controleer ook de gymies kerntabellen
            $tables = ['gymies_users', 'gymies_bookings', 'gymies_trainers'];
            foreach ($tables as $table) {
                if (!DB::getSchemaBuilder()->hasTable($table)) {
                    return [
                        'ok'       => false,
                        'critical' => true,
                        'error'    => "Kerntabel `{$table}` ontbreekt.",
                    ];
                }
            }

            return [
                'ok'         => true,
                'critical'   => true, // database is altijd kritiek
                'latency_ms' => $latency,
                'note'       => $latency > 200 ? 'Hoge latentie gedetecteerd.' : null,
            ];
        } catch (Throwable $e) {
            return [
                'ok'       => false,
                'critical' => true,
                'error'    => 'Database niet bereikbaar: ' . $e->getMessage(),
            ];
        }
    }

    /** @return array{ok: bool, critical: bool, driver?: string, error?: string} */
    private function checkCache(): array
    {
        try {
            $key   = 'gymies_health_check_' . time();
            $value = 'pong_' . random_int(1000, 9999);
            Cache::put($key, $value, 10);
            $retrieved = Cache::get($key);
            Cache::forget($key);

            if ($retrieved !== $value) {
                return ['ok' => false, 'critical' => false, 'error' => 'Cache read/write mismatch.'];
            }

            return [
                'ok'       => true,
                'critical' => false,
                'driver'   => config('cache.default', 'file'),
            ];
        } catch (Throwable $e) {
            return ['ok' => false, 'critical' => false, 'error' => $e->getMessage()];
        }
    }

    /** @return array{ok: bool, critical: bool, pending?: int, failed?: int, error?: string} */
    private function checkQueue(): array
    {
        try {
            if (!DB::getSchemaBuilder()->hasTable('jobs')) {
                return ['ok' => true, 'critical' => false, 'note' => 'Geen queue tabel.'];
            }

            $pending = DB::table('jobs')->count();
            $failed  = DB::getSchemaBuilder()->hasTable('failed_jobs')
                ? DB::table('failed_jobs')
                    ->where('failed_at', '>=', now()->subHour())
                    ->count()
                : 0;
            $failedTotal = DB::getSchemaBuilder()->hasTable('failed_jobs')
                ? DB::table('failed_jobs')->count()
                : 0;

            // Oudste job — detecteert vast zittende queue worker
            $oldestJob = DB::table('jobs')->orderBy('created_at', 'asc')->value('created_at');
            $oldestAge = null;
            $stale     = false;
            if ($oldestJob) {
                $oldestAge = (int) now()->diffInSeconds($oldestJob);
                $stale     = $oldestAge > 600; // >10 minuten = worker draait niet
            }

            // Jobs per queue naam
            $queues = DB::table('jobs')
                ->selectRaw('queue, COUNT(*) as count')
                ->groupBy('queue')
                ->pluck('count', 'queue')
                ->toArray();

            $ok = $failed < 10 && !$stale;

            $notes = [];
            if ($failed > 0) $notes[] = "{$failed} mislukte jobs in het laatste uur";
            if ($stale)       $notes[] = "Oudste job wacht al {$oldestAge}s — worker mogelijk gestopt";

            return [
                'ok'           => $ok,
                'critical'     => $stale, // Queue worker down = kritiek
                'pending'      => $pending,
                'failed_1h'    => $failed,
                'failed_total' => $failedTotal,
                'oldest_age_s' => $oldestAge,
                'queues'       => $queues ?: null,
                'worker_ok'    => !$stale,
                'note'         => !empty($notes) ? implode('; ', $notes) : null,
            ];
        } catch (Throwable $e) {
            return ['ok' => false, 'critical' => false, 'error' => $e->getMessage()];
        }
    }

    /** @return array{ok: bool, critical: bool, free_mb?: int, error?: string} */
    private function checkStorage(): array
    {
        try {
            $storagePath = storage_path();
            $freeBytes   = disk_free_space($storagePath);
            $totalBytes  = disk_total_space($storagePath);

            if ($freeBytes === false || $totalBytes === false) {
                return ['ok' => false, 'critical' => false, 'error' => 'Kan schijfruimte niet bepalen.'];
            }

            $freeMb      = (int) round($freeBytes / 1_048_576);
            $freePercent = $totalBytes > 0 ? round($freeBytes / $totalBytes * 100, 1) : 0;
            $ok          = $freeMb > 200; // minimaal 200 MB vrij

            return [
                'ok'           => $ok,
                'critical'     => false,
                'free_mb'      => $freeMb,
                'free_percent' => $freePercent,
                'note'         => !$ok ? 'Weinig schijfruimte beschikbaar.' : null,
            ];
        } catch (Throwable $e) {
            return ['ok' => false, 'critical' => false, 'error' => $e->getMessage()];
        }
    }

    /** @return array{ok: bool, critical: bool, reachable?: bool, error?: string} */
    private function checkMollie(): array
    {
        try {
            $mollieKey = config('services.mollie.key') ?? env('MOLLIE_KEY');
            if (!$mollieKey) {
                return ['ok' => true, 'critical' => false, 'note' => 'Mollie niet geconfigureerd.'];
            }

            $response = Http::timeout(5)
                ->withToken($mollieKey)
                ->get('https://api.mollie.com/v2/methods');

            $result = [
                'ok'        => $response->successful(),
                'critical'  => false,
                'reachable' => $response->successful(),
                'status'    => $response->status(),
            ];

            // Webhook monitoring: check stale betalingen
            if (DB::getSchemaBuilder()->hasTable('gymies_payment_transactions')) {
                $stalePayments = DB::table('gymies_payment_transactions')
                    ->where('status', 'open')
                    ->where('created_at', '<', now()->subMinutes(30))
                    ->count();

                $result['stale_payments'] = $stalePayments;
                if ($stalePayments > 5) {
                    $result['ok'] = false;
                    $result['note'] = "{$stalePayments} betalingen wachten >30min — webhook probleem?";
                }
            }

            if (!$response->successful()) {
                $result['note'] = 'Mollie API antwoordt met status ' . $response->status();
            }

            return $result;
        } catch (Throwable $e) {
            return ['ok' => false, 'critical' => false, 'error' => 'Mollie niet bereikbaar: ' . $e->getMessage()];
        }
    }

    /** @return array{ok: bool, critical: bool, reachable?: bool, error?: string} */
    private function checkReverb(): array
    {
        try {
            $host = env('REVERB_HOST', '127.0.0.1');
            $port = (int) env('REVERB_PORT', 8080);

            // Controleer of Reverb luistert op de geconfigureerde poort
            $connection = @fsockopen($host, $port, $errno, $errstr, 3);
            if ($connection) {
                fclose($connection);
                return [
                    'ok'       => true,
                    'critical' => false,
                    'host'     => "{$host}:{$port}",
                ];
            }

            return [
                'ok'       => false,
                'critical' => false,
                'error'    => "Reverb niet bereikbaar op {$host}:{$port}: {$errstr}",
            ];
        } catch (Throwable $e) {
            return ['ok' => false, 'critical' => false, 'error' => $e->getMessage()];
        }
    }

    /** @return array{ok: bool, critical: bool, configured?: bool} */
    private function checkSentry(): array
    {
        $dsn = config('gymies.sentry_dsn', '');
        if (empty($dsn)) {
            return ['ok' => true, 'critical' => false, 'configured' => false, 'note' => 'Sentry DSN niet geconfigureerd.'];
        }

        return [
            'ok'         => true,
            'critical'   => false,
            'configured' => true,
        ];
    }

    /** @return array{ok: bool, critical: bool, last_backup?: string, verified?: bool, size_mb?: float} */
    private function checkBackup(): array
    {
        try {
            $statusFile = storage_path('app/backup_status.json');
            if (!file_exists($statusFile)) {
                return [
                    'ok'       => true,
                    'critical' => false,
                    'note'     => 'Geen backup status gevonden. Draai scripts/backup_met_verificatie.sh',
                ];
            }

            $data = json_decode(file_get_contents($statusFile), true);
            if (!is_array($data)) {
                return ['ok' => false, 'critical' => false, 'error' => 'Backup status bestand onleesbaar.'];
            }

            $status   = $data['status'] ?? 'unknown';
            $ts       = $data['timestamp'] ?? null;
            $verified = (bool) ($data['verified'] ?? false);
            $sizeMb   = (float) ($data['size_mb'] ?? 0);

            // Controleer of backup niet te oud is (>26 uur = gemist)
            $stale = false;
            if ($ts) {
                try {
                    $backupTime = new \DateTimeImmutable($ts);
                    $now        = new \DateTimeImmutable();
                    $ageHours   = ($now->getTimestamp() - $backupTime->getTimestamp()) / 3600;
                    $stale      = $ageHours > 26;
                } catch (\Throwable $e) {
                    $stale = true;
                }
            }

            $ok = $status === 'ok' && $verified && !$stale;

            $result = [
                'ok'          => $ok,
                'critical'    => false,
                'last_backup' => $ts,
                'verified'    => $verified,
                'size_mb'     => $sizeMb,
                'rows_source' => (int) ($data['rows_source'] ?? 0),
                'rows_restored' => (int) ($data['rows_restored'] ?? 0),
            ];

            if ($stale) {
                $result['note'] = 'Laatste backup is ouder dan 26 uur — backup cron mogelijk gestopt.';
            } elseif ($status !== 'ok') {
                $result['note'] = 'Laatste backup mislukt: ' . ($data['message'] ?? 'onbekende fout');
            }

            return $result;
        } catch (Throwable $e) {
            return ['ok' => false, 'critical' => false, 'error' => $e->getMessage()];
        }
    }

    /** @return array{ok: bool, critical: bool, driver?: string} */
    private function checkMail(): array
    {
        try {
            $driver = config('mail.default', 'smtp');
            // We versturen geen echte mail — controleer alleen de configuratie
            $host = config('mail.mailers.smtp.host');
            $ok   = !empty($host) || $driver !== 'smtp';

            return [
                'ok'       => $ok,
                'critical' => false,
                'driver'   => $driver,
                'note'     => !$ok ? 'SMTP host niet geconfigureerd.' : null,
            ];
        } catch (Throwable $e) {
            return ['ok' => false, 'critical' => false, 'error' => $e->getMessage()];
        }
    }
}
