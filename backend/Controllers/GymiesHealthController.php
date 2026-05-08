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
 *   Route::get('health',        [GymiesHealthController::class, 'ping'])
 *       ->middleware('gymies.rate.limit:health');
 *
 *   // Uitgebreide status (alleen voor cyber/admin)
 *   Route::get('health/status', [GymiesHealthController::class, 'status'])
 *       ->middleware(['gymies.auth', 'gymies.cyber:cyber.access']);
 *
 *   // Master cron runner (voert alle cron jobs uit)
 *   Route::post('cron/run-all', [GymiesHealthController::class, 'runAllCrons'])
 *       ->middleware('gymies.rate.limit:cron');
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
            'mail'           => $this->checkMail(),
        ];

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

            $ok = $failed < 10; // tolerantie: <10 mislukte jobs per uur

            return [
                'ok'       => $ok,
                'critical' => false,
                'pending'  => $pending,
                'failed'   => $failed,
                'note'     => $failed > 0 ? "{$failed} mislukte jobs in het laatste uur." : null,
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

            return [
                'ok'        => $response->successful(),
                'critical'  => false,
                'reachable' => $response->successful(),
                'status'    => $response->status(),
                'note'      => !$response->successful()
                    ? 'Mollie API antwoordt met status ' . $response->status()
                    : null,
            ];
        } catch (Throwable $e) {
            return ['ok' => false, 'critical' => false, 'error' => 'Mollie niet bereikbaar: ' . $e->getMessage()];
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

    /**
     * POST /api/gymies/cron/run-all
     *
     * Master cron endpoint: voert alle critical cron jobs uit in sequentie.
     * Geschikt voor external cron runners (curl, webhook, uptime monitor).
     * Vereist GYMIES_CRON_KEY.
     */
    public function runAllCrons(Request $request): JsonResponse
    {
        $cronController = new \App\Http\Controllers\Gymies\GymiesCronController();
        $results = [];

        $jobs = [
            'expirePendingBookings' => fn() => $cronController->expirePendingBookings($request),
            'expireReservedBookings' => fn() => $cronController->expireReservedBookings($request),
            'bookingReminders' => fn() => $cronController->bookingReminders($request),
            'autoCompletePastSessions' => fn() => $cronController->autoCompletePastSessions($request),
            'refreshProClientHealth' => fn() => $cronController->refreshProClientHealth($request),
            'subscriptionReminders' => fn() => $cronController->subscriptionReminders($request),
        ];

        $startTime = hrtime(true);
        foreach ($jobs as $jobName => $jobFn) {
            try {
                $response = $jobFn();
                $results[$jobName] = json_decode($response->getContent(), true) ?? ['error' => 'Could not decode response'];
            } catch (Throwable $e) {
                $results[$jobName] = ['error' => $e->getMessage()];
                \Log::error("Cron job {$jobName} failed: " . $e->getMessage());
            }
        }
        $duration = (int) round((hrtime(true) - $startTime) / 1_000_000);

        return response()->json([
            'status' => 'completed',
            'jobs' => $results,
            'total_time_ms' => $duration,
            'timestamp' => now()->toIso8601String(),
        ]);
    }
}
