<?php

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Carbon\Carbon;

/**
 * GymiesCyberController
 *
 * Alle endpoints voor het Cyber Security Dashboard.
 * Alle routes vereisen is_cyber == 1 of admin.super.
 *
 * Route prefix: api/gymies/cyber/
 */
class GymiesCyberController extends Controller
{
    // ─── Cyber Auth (merged from GymiesCyberAuthController) ─────
    private const CYBER_TOKEN_TTL_MINUTES = 30;
    private const CYBER_MAX_PIN_ATTEMPTS = 5;
    private const CYBER_LOCKOUT_MINUTES = 15;
    private const CYBER_PIN_LENGTH = 6;

    // ════════════════════════════════════════════════════════════════════
    // 1. SYSTEEM HEALTH OVERZICHT
    // GET api/gymies/cyber/health
    // ════════════════════════════════════════════════════════════════════
    public function health(): JsonResponse
    {
        $checks = [];

        // Database
        try {
            DB::select('SELECT 1');
            $checks['database'] = ['status' => 'ok', 'label' => 'Database'];
        } catch (\Throwable $e) {
            $checks['database'] = ['status' => 'error', 'label' => 'Database', 'detail' => $e->getMessage()];
        }

        // T-048 FIXED: API key gemaskeerd in health checks — nooit in logs
        $mollieKey = config('services.mollie.key', env('MOLLIE_API_KEY', ''));
        if (empty($mollieKey)) {
            $checks['mollie'] = ['status' => 'unconfigured'];
        } else {
            // Gebruik key maar log nooit de waarde
            try {
                $result = $this->pingApi(
                    'https://api.mollie.com/v2/methods',
                    ['Authorization' => 'Bearer ' . $mollieKey],
                    'Mollie API'
                );
                $checks['mollie'] = $result;
            } catch (\Throwable $e) {
                // T-048: log NOOIT de key of authorization header
                $checks['mollie'] = ['status' => 'error', 'message' => 'Mollie niet bereikbaar'];
            }
        }

        // Brevo / SMTP: controleer of de config aanwezig is
        $brevoKey = env('BREVO_API_KEY', '');
        $checks['brevo'] = empty($brevoKey)
            ? ['status' => 'warning', 'label' => 'Brevo', 'detail' => 'API key niet geconfigureerd']
            : ['status' => 'ok',      'label' => 'Brevo'];

        // Nginx (via /tmp/nginx_status of proc)
        $checks['nginx'] = $this->checkNginxRunning();

        // Queue: kijk of er stuck jobs zijn (> 30 min)
        try {
            $stuckJobs = DB::table('jobs')
                ->where('available_at', '<', now()->subMinutes(30)->timestamp)
                ->count();
            $checks['queue'] = $stuckJobs === 0
                ? ['status' => 'ok',      'label' => 'Queue', 'detail' => 'Geen stuck jobs']
                : ['status' => 'warning', 'label' => 'Queue', 'detail' => $stuckJobs . ' stuck job(s)'];
        } catch (\Throwable) {
            $checks['queue'] = ['status' => 'unknown', 'label' => 'Queue', 'detail' => 'Tabel niet gevonden'];
        }

        // Failed jobs laatste 24h
        try {
            $failedJobs = DB::table('failed_jobs')
                ->where('failed_at', '>=', now()->subHours(24)->toDateTimeString())
                ->count();
            $checks['failed_jobs'] = [
                'status' => $failedJobs === 0 ? 'ok' : 'warning',
                'label'  => 'Failed Jobs (24h)',
                'detail' => $failedJobs . ' mislukt',
            ];
        } catch (\Throwable) {
            $checks['failed_jobs'] = ['status' => 'unknown', 'label' => 'Failed Jobs'];
        }

        $overall = collect($checks)->pluck('status')->contains('error') ? 'degraded'
            : (collect($checks)->pluck('status')->contains('warning') ? 'warning' : 'ok');

        return response()->json([
            'overall'   => $overall,
            'checks'    => $checks,
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 2. NGINX STATUS
    // GET api/gymies/cyber/nginx
    // ════════════════════════════════════════════════════════════════════
    public function nginx(Request $request): JsonResponse
    {
        $status     = $this->checkNginxRunning();
        $statusPage = $this->fetchNginxStatusPage();

        return response()->json([
            'running'             => $status['status'] === 'ok',
            'status'              => $status,
            'active_connections'  => $statusPage['active_connections'] ?? null,
            'accepts'             => $statusPage['accepts'] ?? null,
            'handled'             => $statusPage['handled'] ?? null,
            'requests'            => $statusPage['requests'] ?? null,
            'reading'             => $statusPage['reading'] ?? null,
            'writing'             => $statusPage['writing'] ?? null,
            'waiting'             => $statusPage['waiting'] ?? null,
            'config_test'         => $this->nginxConfigTest($request), // S-080: Pass request for rate limiting
            'timestamp'           => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 3. API HEALTH (Mollie + Brevo live check)
    // GET api/gymies/cyber/api-health
    // ════════════════════════════════════════════════════════════════════
    public function apiHealth(): JsonResponse
    {
        $mollieKey = config('services.mollie.key', env('MOLLIE_API_KEY', ''));
        $brevoKey  = env('BREVO_API_KEY', '');

        $mollie = $this->pingApi(
            'https://api.mollie.com/v2/methods',
            ['Authorization' => 'Bearer ' . $mollieKey],
            'Mollie'
        );

        $brevo = !empty($brevoKey)
            ? $this->pingApi(
                'https://api.brevo.com/v3/account',
                ['api-key' => $brevoKey],
                'Brevo'
            )
            : ['status' => 'warning', 'label' => 'Brevo', 'detail' => 'API key niet geconfigureerd', 'response_ms' => 0];

        // Laatste succesvolle Mollie webhook
        $lastWebhook = DB::table('gymies_payment_transactions')
            ->whereNotNull('paid_at')
            ->orderByDesc('paid_at')
            ->value('paid_at');

        // Recent mislukte betalingen (24h)
        $failedPayments = DB::table('gymies_payment_transactions')
            ->where('status', 'failed')
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->count();

        return response()->json([
            'apis' => [
                'mollie' => $mollie,
                'brevo'  => $brevo,
            ],
            'mollie_last_webhook'    => $lastWebhook,
            'failed_payments_24h'    => $failedPayments,
            'timestamp'              => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 4. NETWERK TRAFFIC
    // GET api/gymies/cyber/network-traffic
    // ════════════════════════════════════════════════════════════════════
    public function networkTraffic(Request $request): JsonResponse
    {
        $hours = min((int) $request->query('hours', 1), 24);

        $since = Carbon::now()->subHours($hours);

        // Recente requests
        $recentRequests = DB::table('gymies_request_log')
            ->where('created_at', '>=', $since)
            ->selectRaw('
                COUNT(*) as total,
                SUM(CASE WHEN status_code >= 500 THEN 1 ELSE 0 END) as errors_5xx,
                SUM(CASE WHEN status_code >= 400 AND status_code < 500 THEN 1 ELSE 0 END) as errors_4xx,
                SUM(CASE WHEN status_code >= 200 AND status_code < 300 THEN 1 ELSE 0 END) as success_2xx,
                ROUND(AVG(response_ms), 0) as avg_response_ms,
                MAX(response_ms) as max_response_ms
            ')
            ->first();

        // Top 10 endpoints
        $topEndpoints = DB::table('gymies_request_log')
            ->where('created_at', '>=', $since)
            ->selectRaw('path, method, COUNT(*) as hits, ROUND(AVG(response_ms),0) as avg_ms')
            ->groupBy('path', 'method')
            ->orderByDesc('hits')
            ->limit(10)
            ->get();

        // Requests per minuut (laatste 60 minuten, per 5 min bucket)
        $timeline = DB::table('gymies_request_log')
            ->where('created_at', '>=', Carbon::now()->subHour())
            ->selectRaw("
                DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') as minute_bucket,
                COUNT(*) as requests,
                SUM(CASE WHEN status_code >= 500 THEN 1 ELSE 0 END) as errors
            ")
            ->groupByRaw("DATE_FORMAT(created_at, '%Y-%m-%d %H:%i')")
            ->orderBy('minute_bucket')
            ->get();

        // Top IPs
        $topIps = DB::table('gymies_request_log')
            ->where('created_at', '>=', $since)
            ->selectRaw('ip_address, COUNT(*) as hits')
            ->groupBy('ip_address')
            ->orderByDesc('hits')
            ->limit(10)
            ->get();

        // Error log (laatste 20 errors)
        $recentErrors = DB::table('gymies_request_log')
            ->where('created_at', '>=', $since)
            ->where('status_code', '>=', 400)
            ->select('method', 'path', 'status_code', 'ip_address', 'response_ms', 'created_at')
            ->orderByDesc('created_at')
            ->limit(20)
            ->get();

        return response()->json([
            'period_hours'    => $hours,
            'summary'         => $recentRequests,
            'top_endpoints'   => $topEndpoints,
            'timeline'        => $timeline,
            'top_ips'         => $topIps,
            'recent_errors'   => $recentErrors,
            'timestamp'       => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 5. BERICHTEN MONITOR
    // GET api/gymies/cyber/messages
    // ════════════════════════════════════════════════════════════════════
    public function messages(): JsonResponse
    {
        // Verzonden berichten per dag (laatste 7 dagen)
        $dailyVolume = DB::table('gymies_client_messages')
            ->where('created_at', '>=', Carbon::now()->subDays(7))
            ->selectRaw("DATE(created_at) as dag, COUNT(*) as berichten")
            ->groupByRaw('DATE(created_at)')
            ->orderBy('dag')
            ->get();

        // Totaal vandaag
        $todayTotal = DB::table('gymies_client_messages')
            ->whereDate('created_at', today())
            ->count();

        // Ongelezen berichten per trainer
        $unreadByTrainer = DB::table('gymies_client_messages as m')
            ->join('gymies_users as u', 'u.id', '=', 'm.trainer_user_id')
            ->where('m.is_read', 0)
            ->selectRaw('m.trainer_user_id, u.display_name, COUNT(*) as ongelezen')
            ->groupBy('m.trainer_user_id', 'u.display_name')
            ->orderByDesc('ongelezen')
            ->limit(10)
            ->get();

        // Push notificatie queue status
        $pendingPush = DB::table('gymies_notification_queue')
            ->where('status', 'pending')
            ->count();

        $failedPush = DB::table('gymies_notification_queue')
            ->where('status', 'failed')
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->count();

        $sentPush24h = DB::table('gymies_notification_queue')
            ->where('status', 'sent')
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->count();

        return response()->json([
            'daily_volume'       => $dailyVolume,
            'today_total'        => $todayTotal,
            'unread_by_trainer'  => $unreadByTrainer,
            'push_pending'       => $pendingPush,
            'push_failed_24h'    => $failedPush,
            'push_sent_24h'      => $sentPush24h,
            'timestamp'          => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 6. SECURITY EVENTS
    // GET api/gymies/cyber/security-events
    // ════════════════════════════════════════════════════════════════════
    public function securityEvents(): JsonResponse
    {
        // Rate limit hits uit request log (429 responses)
        $rateLimitHits = DB::table('gymies_request_log')
            ->where('status_code', 429)
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->selectRaw('ip_address, COUNT(*) as hits')
            ->groupBy('ip_address')
            ->orderByDesc('hits')
            ->limit(20)
            ->get();

        // Webhook failures (non-200 op webhook endpoint)
        $webhookFailures = DB::table('gymies_request_log')
            ->where('path', 'like', '%webhook%')
            ->where('status_code', '>=', 400)
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->select('method', 'path', 'status_code', 'ip_address', 'created_at')
            ->orderByDesc('created_at')
            ->limit(20)
            ->get();

        // Cyber alerts (open + acknowledged)
        $cyberAlerts = DB::table('gymies_cyber_alerts')
            ->whereIn('status', ['open', 'acknowledged'])
            ->orderByDesc('created_at')
            ->limit(50)
            ->get();

        // Admin alerts (hergebruik bestaande tabel)
        $adminAlerts = DB::table('gymies_admin_alerts')
            ->whereIn('status', ['open', 'new'])
            ->orderByDesc('created_at')
            ->limit(20)
            ->get();

        // IP allowlist (om te vergelijken met blocked attempts)
        $allowedIps = DB::table('gymies_admin_ip_allowlist')
            ->where('status', 'active')
            ->pluck('ip_pattern')
            ->toArray();

        return response()->json([
            'rate_limit_hits_24h' => $rateLimitHits,
            'webhook_failures_24h'=> $webhookFailures,
            'cyber_alerts'        => $cyberAlerts,
            'admin_alerts'        => $adminAlerts,
            'allowed_ips_count'   => count($allowedIps),
            'timestamp'           => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 7. ACTIEVE SESSIES
    // GET api/gymies/cyber/sessions
    // ════════════════════════════════════════════════════════════════════
    public function activeSessions(): JsonResponse
    {
        // Actieve sessies (niet expired/revoked, laatste 24h actief)
        $sessions = DB::table('gymies_sessions as s')
            ->join('gymies_users as u', 'u.id', '=', 's.user_id')
            ->whereNull('s.revoked_at')
            ->where('s.last_used_at', '>=', Carbon::now()->subHours(24))
            ->select(
                's.id', 's.user_id', 'u.display_name', 'u.email',
                'u.is_admin', 'u.is_cyber',
                's.ip_address', 's.user_agent',
                's.created_at', 's.last_used_at'
            )
            ->orderByDesc('s.last_used_at')
            ->limit(100)
            ->get();

        // Verdachte sessies: zelfde user_id, meerdere IPs tegelijk
        $suspiciousSessions = DB::table('gymies_sessions')
            ->whereNull('revoked_at')
            ->where('last_used_at', '>=', Carbon::now()->subHours(1))
            ->selectRaw('user_id, COUNT(DISTINCT ip_address) as ip_count')
            ->groupBy('user_id')
            ->having('ip_count', '>', 2)
            ->orderByDesc('ip_count')
            ->get();

        // Totale actieve sessies
        $totalActive = DB::table('gymies_sessions')
            ->whereNull('revoked_at')
            ->where('last_used_at', '>=', Carbon::now()->subHours(24))
            ->count();

        // Admin/cyber sessies
        $privilegedSessions = DB::table('gymies_sessions as s')
            ->join('gymies_users as u', 'u.id', '=', 's.user_id')
            ->whereNull('s.revoked_at')
            ->where(function ($q) {
                $q->where('u.is_admin', 1)->orWhere('u.is_cyber', 1);
            })
            ->where('s.last_used_at', '>=', Carbon::now()->subHours(24))
            ->select('s.user_id', 'u.display_name', 'u.email', 'u.is_admin', 'u.is_cyber', 's.ip_address', 's.last_used_at')
            ->orderByDesc('s.last_used_at')
            ->get();

        return response()->json([
            'total_active'        => $totalActive,
            'sessions'            => $sessions,
            'suspicious'          => $suspiciousSessions,
            'privileged_sessions' => $privilegedSessions,
            'timestamp'           => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 8. AUTH LOG
    // GET api/gymies/cyber/auth-log
    // ════════════════════════════════════════════════════════════════════
    public function authLog(Request $request): JsonResponse
    {
        $hours = min((int) $request->query('hours', 24), 72);
        $since = Carbon::now()->subHours($hours);

        // Auth events uit request log (login endpoints)
        $loginAttempts = DB::table('gymies_request_log')
            ->where('path', 'like', '%/auth/login%')
            ->where('created_at', '>=', $since)
            ->selectRaw('
                ip_address,
                COUNT(*) as attempts,
                SUM(CASE WHEN status_code = 200 THEN 1 ELSE 0 END) as successes,
                SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) as failures,
                MAX(created_at) as last_attempt
            ')
            ->groupBy('ip_address')
            ->orderByDesc('failures')
            ->limit(30)
            ->get();

        // Password reset pogingen
        $passwordResets = DB::table('gymies_request_log')
            ->where('path', 'like', '%/auth/reset%')
            ->where('created_at', '>=', $since)
            ->count();

        // Email verificatie pogingen
        $emailVerifications = DB::table('gymies_request_log')
            ->where('path', 'like', '%/auth/verify%')
            ->where('created_at', '>=', $since)
            ->count();

        // Brute force kandidaten (>10 failures per IP)
        $bruteForce = $loginAttempts->filter(fn($r) => (int) $r->failures > 10);

        // Recente succesvolle logins van nieuwe IPs (niet eerder gezien)
        $recentLogins = DB::table('gymies_request_log')
            ->where('path', 'like', '%/auth/login%')
            ->where('status_code', 200)
            ->where('created_at', '>=', $since)
            ->select('ip_address', 'user_id', 'created_at')
            ->orderByDesc('created_at')
            ->limit(20)
            ->get();

        return response()->json([
            'period_hours'       => $hours,
            'login_attempts'     => $loginAttempts,
            'password_resets'    => $passwordResets,
            'email_verifications'=> $emailVerifications,
            'brute_force_ips'    => $bruteForce->values(),
            'recent_logins'      => $recentLogins,
            'timestamp'          => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 9. RATE LIMIT MONITOR
    // GET api/gymies/cyber/rate-limits
    // ════════════════════════════════════════════════════════════════════
    public function rateLimits(): JsonResponse
    {
        // 429 responses per IP (24h)
        $blockedIps = DB::table('gymies_request_log')
            ->where('status_code', 429)
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->selectRaw('ip_address, COUNT(*) as blocks, MAX(created_at) as last_block')
            ->groupBy('ip_address')
            ->orderByDesc('blocks')
            ->limit(30)
            ->get();

        // 429 per endpoint
        $blockedEndpoints = DB::table('gymies_request_log')
            ->where('status_code', 429)
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->selectRaw('path, method, COUNT(*) as blocks')
            ->groupBy('path', 'method')
            ->orderByDesc('blocks')
            ->limit(10)
            ->get();

        // Timeline van blocks (per uur, laatste 24h)
        $timeline = DB::table('gymies_request_log')
            ->where('status_code', 429)
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->selectRaw("DATE_FORMAT(created_at, '%Y-%m-%d %H:00') as hour_bucket, COUNT(*) as blocks")
            ->groupByRaw("DATE_FORMAT(created_at, '%Y-%m-%d %H:00')")
            ->orderBy('hour_bucket')
            ->get();

        // Totaal per dag
        $total24h = DB::table('gymies_request_log')
            ->where('status_code', 429)
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->count();

        return response()->json([
            'total_blocks_24h'   => $total24h,
            'blocked_ips'        => $blockedIps,
            'blocked_endpoints'  => $blockedEndpoints,
            'timeline'           => $timeline,
            'timestamp'          => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 10. GEO & IP REPUTATIE
    // GET api/gymies/cyber/geo
    // ════════════════════════════════════════════════════════════════════
    public function geo(): JsonResponse
    {
        // Top IPs van de laatste 24h
        $topIps = DB::table('gymies_request_log')
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->selectRaw('ip_address, COUNT(*) as requests, MAX(created_at) as last_seen')
            ->groupBy('ip_address')
            ->orderByDesc('requests')
            ->limit(50)
            ->get();

        // IPs die 403/401 krijgen (ongeautoriseerde pogingen)
        $unauthorizedIps = DB::table('gymies_request_log')
            ->whereIn('status_code', [401, 403])
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->selectRaw('ip_address, COUNT(*) as attempts, MAX(created_at) as last_attempt')
            ->groupBy('ip_address')
            ->orderByDesc('attempts')
            ->limit(20)
            ->get();

        // IP allowlist (admin toegestane IPs)
        $allowlist = DB::table('gymies_admin_ip_allowlist')
            ->where('status', 'active')
            ->select('ip_pattern', 'created_at')
            ->get();

        // Unieke IPs vandaag
        $uniqueIpsToday = DB::table('gymies_request_log')
            ->whereDate('created_at', today())
            ->distinct('ip_address')
            ->count('ip_address');

        return response()->json([
            'unique_ips_today'   => $uniqueIpsToday,
            'top_ips_24h'        => $topIps,
            'unauthorized_ips'   => $unauthorizedIps,
            'admin_allowlist'    => $allowlist,
            'note'               => 'Geo-lookup vereist een externe IP-database (MaxMind GeoLite2) op de server.',
            'timestamp'          => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 11. WEBHOOK INTEGRITEIT
    // GET api/gymies/cyber/webhooks
    // ════════════════════════════════════════════════════════════════════
    public function webhooks(): JsonResponse
    {
        // Mollie webhook calls (vanuit request log)
        $webhookRequests = DB::table('gymies_request_log')
            ->where('path', 'like', '%webhook%')
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->selectRaw('
                COUNT(*) as total,
                SUM(CASE WHEN status_code = 200 THEN 1 ELSE 0 END) as success,
                SUM(CASE WHEN status_code >= 400 THEN 1 ELSE 0 END) as failed,
                AVG(response_ms) as avg_ms
            ')
            ->first();

        // Recente webhook calls
        $recentWebhooks = DB::table('gymies_request_log')
            ->where('path', 'like', '%webhook%')
            ->where('created_at', '>=', Carbon::now()->subHours(24))
            ->select('method', 'path', 'status_code', 'ip_address', 'response_ms', 'created_at')
            ->orderByDesc('created_at')
            ->limit(20)
            ->get();

        // Laatste succesvolle betaling (Mollie → webhook → betaling verwerkt)
        $lastPaidTransaction = DB::table('gymies_payment_transactions')
            ->whereNotNull('paid_at')
            ->orderByDesc('paid_at')
            ->select('id', 'mollie_payment_id', 'amount_cents', 'paid_at', 'status')
            ->first();

        // Betalingen zonder webhook (aangemaakt maar nooit bijgewerkt)
        $pendingTransactions = DB::table('gymies_payment_transactions')
            ->where('status', 'open')
            ->where('created_at', '<', Carbon::now()->subMinutes(30))
            ->count();

        return response()->json([
            'webhook_summary_24h'    => $webhookRequests,
            'recent_webhooks'        => $recentWebhooks,
            'last_paid_transaction'  => $lastPaidTransaction,
            'pending_stale_payments' => $pendingTransactions,
            'timestamp'              => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 12. API ERROR LOG
    // GET api/gymies/cyber/error-log
    // ════════════════════════════════════════════════════════════════════
    public function errorLog(Request $request): JsonResponse
    {
        $hours = min((int) $request->query('hours', 24), 72);
        $since = Carbon::now()->subHours($hours);

        // 5xx errors
        $serverErrors = DB::table('gymies_request_log')
            ->where('status_code', '>=', 500)
            ->where('created_at', '>=', $since)
            ->select('method', 'path', 'status_code', 'ip_address', 'response_ms', 'created_at')
            ->orderByDesc('created_at')
            ->limit(50)
            ->get();

        // 4xx errors (exclusief 429, die is in rate-limits)
        $clientErrors = DB::table('gymies_request_log')
            ->where('status_code', '>=', 400)
            ->where('status_code', '<', 500)
            ->where('status_code', '!=', 429)
            ->where('created_at', '>=', $since)
            ->selectRaw('path, method, status_code, COUNT(*) as hits')
            ->groupBy('path', 'method', 'status_code')
            ->orderByDesc('hits')
            ->limit(20)
            ->get();

        // Error rate per uur
        $errorRate = DB::table('gymies_request_log')
            ->where('status_code', '>=', 400)
            ->where('created_at', '>=', $since)
            ->selectRaw("DATE_FORMAT(created_at, '%Y-%m-%d %H:00') as hour_bucket, COUNT(*) as errors")
            ->groupByRaw("DATE_FORMAT(created_at, '%Y-%m-%d %H:00')")
            ->orderBy('hour_bucket')
            ->get();

        // Laravel log: laatste errors (lees logbestand)
        $laravelErrors = $this->readLatestLaravelErrors(20);

        return response()->json([
            'period_hours'  => $hours,
            'server_errors' => $serverErrors,
            'client_errors' => $clientErrors,
            'error_rate'    => $errorRate,
            'laravel_errors'=> $laravelErrors,
            'timestamp'     => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 13. SERVER RESOURCES
    // GET api/gymies/cyber/server
    // ════════════════════════════════════════════════════════════════════
    public function server(): JsonResponse
    {
        $data = [];

        // CPU load
        if (function_exists('sys_getloadavg')) {
            [$load1, $load5, $load15] = sys_getloadavg();
            $data['cpu'] = [
                'load_1min'  => round($load1,  2),
                'load_5min'  => round($load5,  2),
                'load_15min' => round($load15, 2),
                'status'     => $load1 > 2.0 ? 'warning' : 'ok',
            ];
        }

        // Memory
        $memInfo = $this->readMemInfo();
        if ($memInfo) {
            $data['memory'] = $memInfo;
        }

        // Disk
        $diskFree  = disk_free_space('/');
        $diskTotal = disk_total_space('/');
        if ($diskFree !== false && $diskTotal !== false) {
            $usedPct = round((($diskTotal - $diskFree) / $diskTotal) * 100, 1);
            $data['disk'] = [
                'total_gb'  => round($diskTotal / (1024 ** 3), 1),
                'free_gb'   => round($diskFree  / (1024 ** 3), 1),
                'used_pct'  => $usedPct,
                'status'    => $usedPct > 85 ? 'warning' : 'ok',
            ];
        }

        // PHP
        $data['php'] = [
            'version'    => PHP_VERSION,
            'memory_limit'=> ini_get('memory_limit'),
            'max_exec'   => ini_get('max_execution_time'),
        ];

        // Uptime
        if (file_exists('/proc/uptime')) {
            $uptime = (float) explode(' ', file_get_contents('/proc/uptime'))[0];
            $days   = floor($uptime / 86400);
            $hours  = floor(($uptime % 86400) / 3600);
            $data['uptime'] = [
                'seconds'    => (int) $uptime,
                'human'      => "{$days}d {$hours}h",
            ];
        }

        return response()->json(array_merge($data, [
            'timestamp' => now()->toIso8601String(),
        ]));
    }

    // ════════════════════════════════════════════════════════════════════
    // 14. CRON JOB STATUS
    // GET api/gymies/cyber/crons
    // ════════════════════════════════════════════════════════════════════
    public function crons(): JsonResponse
    {
        // Bekende cron endpoints in de app
        $knownCrons = [
            ['name' => 'Autopilot Retention',  'key' => 'auto_pilot_retention'],
            ['name' => 'Booking Reminders',    'key' => 'booking_reminders'],
            ['name' => 'Platform Fee Deducts', 'key' => 'platform_fee'],
            ['name' => 'Slot Cleanup',         'key' => 'slot_cleanup'],
        ];

        // Controleer laatste uitvoering via request log
        foreach ($knownCrons as &$cron) {
            $last = DB::table('gymies_request_log')
                ->where('path', 'like', '%cron%' . $cron['key'] . '%')
                ->where('status_code', 200)
                ->orderByDesc('created_at')
                ->value('created_at');

            $cron['last_run']      = $last;
            $cron['last_run_human']= $last ? Carbon::parse($last)->diffForHumans() : 'Nooit';
            $cron['status']        = !$last ? 'unknown'
                : (Carbon::parse($last)->diffInHours(now()) > 25 ? 'warning' : 'ok');
        }
        unset($cron);

        // Laravel queue jobs (pending / processing / failed)
        $queueStats = [];
        try {
            $queueStats = [
                'pending'  => DB::table('jobs')->count(),
                'failed'   => DB::table('failed_jobs')->count(),
                'failed_24h'=> DB::table('failed_jobs')
                    ->where('failed_at', '>=', Carbon::now()->subHours(24)->toDateTimeString())
                    ->count(),
            ];
        } catch (\Throwable) {
            $queueStats = ['note' => 'Queue tabellen niet gevonden'];
        }

        return response()->json([
            'cron_jobs'   => $knownCrons,
            'queue_stats' => $queueStats,
            'timestamp'   => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 15. LOG VIEWER
    // GET api/gymies/cyber/logs
    // ════════════════════════════════════════════════════════════════════
    public function logs(Request $request): JsonResponse
    {
        $lines = min((int) $request->query('lines', 100), 500);
        $level = $request->query('level', 'all'); // all|error|warning|info

        $logFile = storage_path('logs/laravel.log');

        if (!file_exists($logFile)) {
            return response()->json(['lines' => [], 'note' => 'Log bestand niet gevonden.', 'timestamp' => now()->toIso8601String()]);
        }

        // Lees laatste N regels
        $allLines = $this->tailFile($logFile, $lines * 3); // oversample voor filtering

        $parsed = [];
        $pattern = '/^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (\w+)\.(\w+): (.+)/';
        $buffer  = '';

        foreach ($allLines as $line) {
            if (preg_match($pattern, $line, $m)) {
                if ($buffer !== '' && !empty($parsed)) {
                    $parsed[count($parsed) - 1]['context'] .= "\n" . trim($buffer);
                    $buffer = '';
                }
                $entry = [
                    'timestamp' => $m[1],
                    'env'       => $m[2],
                    'level'     => strtolower($m[3]),
                    'message'   => substr($m[4], 0, 500),
                    'context'   => '',
                ];
                if ($level === 'all' || $entry['level'] === $level) {
                    $parsed[] = $entry;
                }
            } else {
                $buffer .= $line;
            }
        }

        $result = array_slice(array_reverse($parsed), 0, $lines);

        return response()->json([
            'lines'     => $result,
            'total'     => count($result),
            'log_file'  => basename($logFile),
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 16. SSL/TLS DETAILS
    // GET api/gymies/cyber/ssl
    // ════════════════════════════════════════════════════════════════════
    public function ssl(): JsonResponse
    {
        $appUrl  = config('app.url', env('APP_URL', ''));
        $host    = parse_url($appUrl, PHP_URL_HOST) ?? '';
        $port    = 443;
        $result  = [];

        if (!empty($host)) {
            $context = stream_context_create(['ssl' => [
                'capture_peer_cert' => true,
                'verify_peer'       => false,
                'verify_peer_name'  => false,
            ]]);

            $conn = @stream_socket_client(
                "ssl://{$host}:{$port}",
                $errno, $errstr, 5,
                STREAM_CLIENT_CONNECT, $context
            );

            if ($conn) {
                $params = stream_context_get_params($conn);
                $cert   = openssl_x509_parse($params['options']['ssl']['peer_certificate']);
                fclose($conn);

                $validTo  = Carbon::createFromTimestamp($cert['validTo_time_t']);
                $daysLeft = (int) now()->diffInDays($validTo, false);

                $result = [
                    'host'        => $host,
                    'subject'     => $cert['subject']['CN'] ?? 'Onbekend',
                    'issuer'      => $cert['issuer']['O'] ?? 'Onbekend',
                    'valid_from'  => Carbon::createFromTimestamp($cert['validFrom_time_t'])->toDateString(),
                    'valid_to'    => $validTo->toDateString(),
                    'days_left'   => $daysLeft,
                    'status'      => $daysLeft < 14 ? 'critical' : ($daysLeft < 30 ? 'warning' : 'ok'),
                    'san'         => isset($cert['extensions']['subjectAltName'])
                        ? explode(', ', $cert['extensions']['subjectAltName'])
                        : [],
                ];
            } else {
                $result = ['host' => $host, 'status' => 'error', 'detail' => "Kan niet verbinden: {$errstr}"];
            }
        } else {
            $result = ['status' => 'unknown', 'detail' => 'APP_URL niet geconfigureerd'];
        }

        return response()->json(array_merge($result, [
            'timestamp' => now()->toIso8601String(),
        ]));
    }

    // ════════════════════════════════════════════════════════════════════
    // 17. FILE INTEGRITY
    // GET api/gymies/cyber/integrity
    // ════════════════════════════════════════════════════════════════════
    public function integrity(): JsonResponse
    {
        $criticalFiles = [
            base_path('routes_gymies_full.php'),
            base_path('backend/Middleware/GymiesSecurityHeadersMiddleware.php'),
            base_path('backend/Middleware/GymiesAdminIpAllowlistMiddleware.php'),
            base_path('backend/Middleware/GymiesCyberCapabilityMiddleware.php'),
            public_path('.htaccess'),
            public_path('gymies-media/.htaccess'),
            public_path('storage/.htaccess'),
        ];

        $checksums = DB::table('gymies_system_settings')
            ->where('key', 'like', 'file_checksum_%')
            ->pluck('value', 'key')
            ->toArray();

        $results = [];
        foreach ($criticalFiles as $filePath) {
            $key      = 'file_checksum_' . md5($filePath);
            $exists   = file_exists($filePath);
            $current  = $exists ? md5_file($filePath) : null;
            $stored   = $checksums[$key] ?? null;
            $changed  = $stored !== null && $current !== null && $current !== $stored;
            $newFile  = $stored === null && $current !== null;

            $results[] = [
                'file'    => str_replace(base_path(), '', $filePath),
                'exists'  => $exists,
                'status'  => !$exists ? 'missing' : ($changed ? 'modified' : ($newFile ? 'new' : 'ok')),
                'hash'    => $current,
            ];
        }

        $issues = array_filter($results, fn($r) => $r['status'] !== 'ok' && $r['status'] !== 'new');

        return response()->json([
            'files'          => $results,
            'issues_count'   => count($issues),
            'note'           => 'Sla checksums op via POST /cyber/integrity/snapshot om baseline te bewaren.',
            'timestamp'      => now()->toIso8601String(),
        ]);
    }

    // POST api/gymies/cyber/integrity/snapshot — sla huidige checksums op als baseline
    public function integritySnapshot(): JsonResponse
    {
        $criticalFiles = [
            base_path('routes_gymies_full.php'),
            base_path('backend/Middleware/GymiesSecurityHeadersMiddleware.php'),
            base_path('backend/Middleware/GymiesAdminIpAllowlistMiddleware.php'),
            base_path('backend/Middleware/GymiesCyberCapabilityMiddleware.php'),
            public_path('.htaccess'),
            public_path('gymies-media/.htaccess'),
            public_path('storage/.htaccess'),
        ];

        foreach ($criticalFiles as $filePath) {
            if (!file_exists($filePath)) continue;
            $key = 'file_checksum_' . md5($filePath);
            DB::table('gymies_system_settings')->updateOrInsert(
                ['key' => $key],
                ['value' => md5_file($filePath), 'updated_at' => now()]
            );
        }

        Log::info('[Cyber] File integrity snapshot opgeslagen.');

        return response()->json(['message' => 'Checksums opgeslagen.', 'timestamp' => now()->toIso8601String()]);
    }

    // ════════════════════════════════════════════════════════════════════
    // 18. BACKUP STATUS
    // GET api/gymies/cyber/backup
    // ════════════════════════════════════════════════════════════════════
    public function backup(): JsonResponse
    {
        // Controleer backup directory (aanpasbaar via env)
        $backupDir = env('GYMIES_BACKUP_DIR', storage_path('backups'));
        $exists    = is_dir($backupDir);

        $backups = [];
        if ($exists) {
            $files = glob($backupDir . '/*.{sql,sql.gz,zip,tar.gz}', GLOB_BRACE);
            usort($files, fn($a, $b) => filemtime($b) - filemtime($a));

            foreach (array_slice($files, 0, 10) as $file) {
                $backups[] = [
                    'name'       => basename($file),
                    'size_mb'    => round(filesize($file) / (1024 * 1024), 2),
                    'created_at' => Carbon::createFromTimestamp(filemtime($file))->toDateTimeString(),
                    'age_hours'  => round((time() - filemtime($file)) / 3600, 1),
                ];
            }
        }

        $latestBackup    = $backups[0] ?? null;
        $latestAgeHours  = $latestBackup ? (float) $latestBackup['age_hours'] : null;
        $backupStatus    = !$latestBackup ? 'unknown'
            : ($latestAgeHours > 48 ? 'critical'
            : ($latestAgeHours > 26 ? 'warning' : 'ok'));

        return response()->json([
            'backup_dir'        => $backupDir,
            'dir_exists'        => $exists,
            'status'            => $backupStatus,
            'latest_backup'     => $latestBackup,
            'recent_backups'    => $backups,
            'note'              => 'Stel GYMIES_BACKUP_DIR in .env in op de backup map van je server.',
            'timestamp'         => now()->toIso8601String(),
        ]);
    }

    // ════════════════════════════════════════════════════════════════════
    // CYBER ALERT MANAGEMENT
    // ════════════════════════════════════════════════════════════════════

    // POST api/gymies/cyber/alerts/{id}/acknowledge
    public function acknowledgeAlert(Request $request, int $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        $updated = DB::table('gymies_cyber_alerts')
            ->where('id', $id)
            ->where('status', 'open')
            ->update([
                'status'            => 'acknowledged',
                'acknowledged_by'   => (int) $user->id,
                'updated_at'        => now(),
            ]);

        return $updated
            ? response()->json(['message' => 'Alert bevestigd.'])
            : response()->json(['message' => 'Alert niet gevonden of al verwerkt.'], 404);
    }

    // POST api/gymies/cyber/alerts/{id}/resolve
    public function resolveAlert(Request $request, int $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        $updated = DB::table('gymies_cyber_alerts')
            ->where('id', $id)
            ->update([
                'status'          => 'resolved',
                'acknowledged_by' => (int) $user->id,
                'updated_at'      => now(),
            ]);

        return $updated
            ? response()->json(['message' => 'Alert opgelost.'])
            : response()->json(['message' => 'Alert niet gevonden.'], 404);
    }

    // ════════════════════════════════════════════════════════════════════
    // PRIVATE HELPERS
    // ════════════════════════════════════════════════════════════════════

    private function pingApi(string $url, array $headers, string $label): array
    {
        $start = microtime(true);
        try {
            $context = stream_context_create([
                'http' => [
                    'method'  => 'GET',
                    'header'  => implode("\r\n", array_map(
                        fn($k, $v) => "{$k}: {$v}", array_keys($headers), $headers
                    )),
                    'timeout' => 5,
                ],
                'ssl' => ['verify_peer' => true],
            ]);
            $response   = @file_get_contents($url, false, $context);
            $responseMs = (int) ((microtime(true) - $start) * 1000);
            $httpStatus = 0;
            if (isset($http_response_header)) {
                preg_match('/HTTP\/\d\.\d (\d{3})/', $http_response_header[0] ?? '', $m);
                $httpStatus = (int) ($m[1] ?? 0);
            }
            $ok = $response !== false && $httpStatus >= 200 && $httpStatus < 300;
            return [
                'label'       => $label,
                'status'      => $ok ? 'ok' : 'error',
                'http_status' => $httpStatus,
                'response_ms' => $responseMs,
            ];
        } catch (\Throwable $e) {
            return [
                'label'       => $label,
                'status'      => 'error',
                'response_ms' => (int) ((microtime(true) - $start) * 1000),
                'detail'      => $e->getMessage(),
            ];
        }
    }

    private function checkNginxRunning(): array
    {
        // Probeer /proc te lezen voor nginx process
        $running = false;
        if (is_dir('/proc')) {
            foreach (glob('/proc/*/cmdline') as $cmdlineFile) {
                $cmd = @file_get_contents($cmdlineFile);
                if ($cmd && str_contains($cmd, 'nginx')) {
                    $running = true;
                    break;
                }
            }
        }

        return [
            'label'  => 'Nginx',
            'status' => $running ? 'ok' : 'warning',
            'detail' => $running ? 'Nginx draait' : 'Nginx niet gevonden in /proc (mogelijk in container)',
        ];
    }

    private function fetchNginxStatusPage(): array
    {
        // Standaard nginx status endpoint (vereist nginx stub_status module)
        $statusUrl = env('NGINX_STATUS_URL', 'http://127.0.0.1/nginx_status');
        $content   = @file_get_contents($statusUrl);
        if (!$content) return [];

        $data = [];
        if (preg_match('/Active connections:\s+(\d+)/', $content, $m)) {
            $data['active_connections'] = (int) $m[1];
        }
        if (preg_match('/(\d+)\s+(\d+)\s+(\d+)/', $content, $m)) {
            $data['accepts']  = (int) $m[1];
            $data['handled']  = (int) $m[2];
            $data['requests'] = (int) $m[3];
        }
        if (preg_match('/Reading:\s+(\d+)\s+Writing:\s+(\d+)\s+Waiting:\s+(\d+)/', $content, $m)) {
            $data['reading'] = (int) $m[1];
            $data['writing'] = (int) $m[2];
            $data['waiting'] = (int) $m[3];
        }
        return $data;
    }

    private function nginxConfigTest(Request $request = null): array
    {
        // S-080: Rate limiting to prevent DoS on nginx -t command (max 1 test per minute per user)
        if ($request !== null) {
            $user = $request->attributes->get('gymies_user');
            if ($user) {
                $key = 'nginx_test:' . (int) $user->id;
                $limiter = \Illuminate\Support\Facades\RateLimiter::attempt(
                    $key,
                    1, // max 1 attempt
                    fn () => true,
                    60 // per 60 seconds
                );
                if (!$limiter) {
                    return [
                        'exit_code' => 429,
                        'output'    => 'Rate limit exceeded: max 1 nginx test per minute',
                        'status'    => 'rate_limited',
                    ];
                }
            }
        }

        // T-049 FIXED: command execution beveiligd
        if (!function_exists('exec') || !is_executable('/usr/sbin/nginx')) {
            return ['status' => 'unavailable', 'message' => 'nginx niet beschikbaar'];
        }
        $cmd = escapeshellcmd('nginx -t');
        @exec($cmd . ' 2>&1', $output, $code);
        return [
            'exit_code' => $code,
            'output'    => implode("\n", $output),
            'status'    => $code === 0 ? 'ok' : 'error',
        ];
    }

    private function readMemInfo(): ?array
    {
        if (!file_exists('/proc/meminfo')) return null;
        $lines = file('/proc/meminfo', FILE_IGNORE_NEW_LINES);
        $mem   = [];
        foreach ($lines as $line) {
            [$key, $val] = array_pad(explode(':', $line, 2), 2, '');
            $mem[trim($key)] = (int) trim(str_replace(' kB', '', $val));
        }
        $total     = ($mem['MemTotal']     ?? 0) / 1024;
        $available = ($mem['MemAvailable'] ?? 0) / 1024;
        $used      = $total - $available;
        $usedPct   = $total > 0 ? round(($used / $total) * 100, 1) : 0;

        return [
            'total_mb'    => round($total, 0),
            'used_mb'     => round($used, 0),
            'available_mb'=> round($available, 0),
            'used_pct'    => $usedPct,
            'status'      => $usedPct > 90 ? 'critical' : ($usedPct > 75 ? 'warning' : 'ok'),
        ];
    }

    private function tailFile(string $filePath, int $lines): array
    {
        $file   = new \SplFileObject($filePath, 'r');
        $file->seek(PHP_INT_MAX);
        $total  = $file->key();
        $start  = max(0, $total - $lines);
        $file->seek($start);
        $result = [];
        while (!$file->eof()) {
            $result[] = $file->fgets();
        }
        return $result;
    }

    private function readLatestLaravelErrors(int $limit): array
    {
        $logFile = storage_path('logs/laravel.log');
        if (!file_exists($logFile)) return [];

        $lines   = $this->tailFile($logFile, $limit * 5);
        $errors  = [];
        $pattern = '/^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \w+\.(ERROR|CRITICAL|ALERT|EMERGENCY): (.+)/';

        foreach ($lines as $line) {
            if (preg_match($pattern, $line, $m)) {
                $errors[] = [
                    'timestamp' => $m[1],
                    'level'     => strtolower($m[2]),
                    'message'   => substr($m[3], 0, 300),
                ];
                if (count($errors) >= $limit) break;
            }
        }
        return array_reverse($errors);
    }

    // ════════════════════════════════════════════════════════════════════
    // USER MANAGEMENT & POINTS ENDPOINTS
    // ════════════════════════════════════════════════════════════════════

    // 1. GET api/gymies/cyber/users — Gebruikerslijst met filtering
    public function userList(Request $request): JsonResponse
    {
        $search   = $request->query('search', '');
        $role     = $request->query('role', 'all');
        $hasSub   = $request->query('has_sub', null);
        $isPartner= $request->query('is_partner', null);
        $limit    = min((int) $request->query('limit', 50), 500);

        $query = DB::table('gymies_users as u')
            ->leftJoin('gymies_subscriptions as sub', function ($join) {
                $join->on('u.id', '=', 'sub.trainer_user_id')
                     ->whereNull('sub.deleted_at');
            })
            ->leftJoin('gymies_plans as plan', 'plan.id', '=', 'sub.plan_id')
            ->leftJoin('gymies_trainer_profiles as tp', 'tp.user_id', '=', 'u.id');

        // Filter op zoekterm
        if (!empty($search)) {
            $query->where(function ($q) use ($search) {
                $q->where('u.display_name', 'like', "%{$search}%")
                  ->orWhere('u.email', 'like', "%{$search}%");
            });
        }

        // Filter op rol
        if ($role !== 'all') {
            $query->where('u.role', $role);
        }

        // Filter op subscription
        if ($hasSub !== null) {
            $hasSub = (bool) $hasSub;
            if ($hasSub) {
                $query->whereNotNull('sub.id');
            } else {
                $query->whereNull('sub.id');
            }
        }

        // Filter op partner status
        if ($isPartner !== null) {
            $query->where('u.is_partner', (bool) $isPartner);
        }

        $total = $query->count('u.id');

        // S-047: is_admin exposed aan cyber-rol — Verwijder is_admin uit selectie
        // In plaats daarvan gebruiken we een CASE statement om elevated role status bloot te stellen
        // T-047 FIXED: elevated role status verwijderd uit user listing
        $users = $query->select(
            'u.id', 'u.display_name', 'u.email', 'u.role', 'u.is_partner', 'u.gymies_points', 'u.trainer_approved_at',
            'sub.status as sub_status', 'sub.trial_source', 'sub.trial_ends_at', 'sub.plan_id',
            'plan.name as plan_name'
        )->limit($limit)->get();

        Log::info('Gymies cyber: userList query', ['search' => $search, 'role' => $role, 'limit' => $limit, 'total' => $total]);

        return response()->json([
            'users' => $users,
            'total' => $total,
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    // 2. GET api/gymies/cyber/users/{id} — Volledig gebruikersprofiel
    public function userDetail(Request $request, int $id): JsonResponse
    {
        $id = (int) $id;

        // Gebruiker details
        $user = DB::table('gymies_users')->find($id);
        if (!$user) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }

        // Subscription history
        $subscriptions = DB::table('gymies_subscriptions as sub')
            ->leftJoin('gymies_plans as plan', 'plan.id', '=', 'sub.plan_id')
            ->where('sub.trainer_user_id', $id)
            ->select('sub.*', 'plan.name as plan_name')
            ->orderByDesc('sub.created_at')
            ->get();

        // Referral info
        $referralAsReferrer = DB::table('gymies_referrals')
            ->where('referrer_user_id', $id)
            ->count();

        $referralAsReferred = DB::table('gymies_referrals')
            ->where('referred_user_id', $id)
            ->select('referrer_user_id', 'referral_code', 'created_at')
            ->first();

        // Points ledger (laatste 10)
        $pointsLedger = DB::table('gymies_points_ledger')
            ->where('user_id', $id)
            ->select('event_type', 'points_delta', 'reference_id', 'created_at')
            ->orderByDesc('created_at')
            ->limit(10)
            ->get();

        // Trainer profile
        $trainerProfile = DB::table('gymies_trainer_profiles')->where('user_id', $id)->first();

        // S-095: Unnecessary PII in userDetail — Maskeer/verwijder gevoelige scores
        // trainer_approved_at blijft (relevant voor monitoring), maar quality_score en interne scores verwijderd
        if ($trainerProfile) {
            $trainerProfile->quality_score = null;
            $trainerProfile->moderation_score = null;
            $trainerProfile->approval_score = null;
            // Houd alleen operationeel relevante velden
        }

        Log::info('Gymies cyber: userDetail query', ['user_id' => $id]);

        return response()->json([
            'user' => $user,
            'subscriptions' => $subscriptions,
            'referrals' => [
                'codes_created' => $referralAsReferrer,
                'referred_by' => $referralAsReferred,
            ],
            'points' => [
                'current_balance' => $user->gymies_points,
                'ledger_recent' => $pointsLedger,
            ],
            'trainer_profile' => $trainerProfile,
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    // 3. POST api/gymies/cyber/users/{id}/promote — Promoveer naar trainer
    public function promoteToTrainer(Request $request, int $id): JsonResponse
    {
        $id = (int) $id;
        $cyber = $request->attributes->get('gymies_user');

        $validated = $request->validate([
            'plan_slug' => 'required|string',
            'trial_days' => 'required|integer|min:1|max:365',
            'is_partner' => 'required|boolean',
            'note' => 'nullable|string',
        ]);

        $user = DB::table('gymies_users')->find($id);
        if (!$user) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }

        if ($user->role !== 'klant') {
            return response()->json(['message' => 'Gebruiker is niet klant.'], 422);
        }

        // S-045: promoteToTrainer zonder bevestiging — Gebruikers-consent verplicht
        // Controleer of trainer_upgrade_consent kolom bestaat en of gebruiker toestemming heeft gegeven
        if (Schema::hasColumn('gymies_users', 'trainer_upgrade_consent')) {
            if (!$user->trainer_upgrade_consent) {
                // Sla pending_trainer_upgrade flag op in plaats van direct promoten
                DB::table('gymies_users')
                    ->where('id', $id)
                    ->update(['pending_trainer_upgrade' => 1, 'updated_at' => now()]);

                Log::info('Gymies cyber: promoteToTrainer pending consent', ['user_id' => $id, 'by_user_id' => (int) $cyber->id]);

                return response()->json([
                    'message' => 'Wachtende upgrade — gebruiker moet toestemming geven.',
                    'status' => 'pending_consent',
                    'user_id' => $id,
                ], 202);
            }
        }

        // Check of al subscription bestaat
        $existingSub = DB::table('gymies_subscriptions')
            ->where('trainer_user_id', $id)
            ->first();

        if ($existingSub) {
            return response()->json(['message' => 'Gebruiker heeft al een subscription.'], 422);
        }

        return DB::transaction(function () use ($id, $user, $cyber, $validated) {
            // Update user
            DB::table('gymies_users')
                ->where('id', $id)
                ->update([
                    'role' => 'trainer',
                    'is_partner' => $validated['is_partner'],
                    'trainer_approved_at' => $user->trainer_approved_at ?? now(),
                    'updated_at' => now(),
                ]);

            // Create trainer profile if not exists
            DB::table('gymies_trainer_profiles')->updateOrInsert(
                ['user_id' => $id],
                [
                    'moderation_status' => 'approved',
                    'created_at' => now(),
                    'updated_at' => now(),
                ]
            );

            // Get plan
            $plan = DB::table('gymies_plans')->where('slug', $validated['plan_slug'])->first();
            if (!$plan) {
                throw new \Exception('Plan niet gevonden.');
            }

            // Create subscription
            $subId = DB::table('gymies_subscriptions')->insertGetId([
                'trainer_user_id' => $id,
                'plan_id' => $plan->id,
                'status' => 'trialing',
                'trial_source' => 'manual',
                'trial_ends_at' => now()->addDays($validated['trial_days']),
                'manually_assigned' => 1,
                'assigned_by_user_id' => (int) $cyber->id,
                'assigned_note' => $validated['note'] ?? '',
                'current_period_start' => now(),
                'current_period_end' => now()->addDays($validated['trial_days']),
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            Log::info('Gymies cyber: promoteToTrainer', [
                'user_id' => $id,
                'plan' => $validated['plan_slug'],
                'trial_days' => $validated['trial_days'],
                'sub_id' => $subId,
                'by_user_id' => (int) $cyber->id,
            ]);

            return response()->json([
                'ok' => true,
                'message' => 'Gebruiker gepromoveerd naar trainer.',
                'subscription_id' => $subId,
            ]);
        });
    }

    // 4. POST api/gymies/cyber/users/{id}/assign-sub — Toewijzen/updaten subscription
    public function assignSubscription(Request $request, int $id): JsonResponse
    {
        $id = (int) $id;
        $cyber = $request->attributes->get('gymies_user');

        $validated = $request->validate([
            'plan_slug' => 'required|string',
            'trial_days' => 'required|integer|min:1|max:365',
            'note' => 'nullable|string',
        ]);

        $user = DB::table('gymies_users')->find($id);
        if (!$user) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }

        if ($user->role !== 'trainer') {
            return response()->json(['message' => 'Gebruiker is geen trainer.'], 422);
        }

        return DB::transaction(function () use ($id, $cyber, $validated) {
            // Check existing active subscription
            $existing = DB::table('gymies_subscriptions')
                ->where('trainer_user_id', $id)
                ->whereIn('status', ['trialing', 'active'])
                ->first();

            $plan = DB::table('gymies_plans')->where('slug', $validated['plan_slug'])->first();
            if (!$plan) {
                throw new \Exception('Plan niet gevonden.');
            }

            $wasOverride = false;
            $subId = null;

            if ($existing) {
                // Update existing
                DB::table('gymies_subscriptions')
                    ->where('id', $existing->id)
                    ->update([
                        'trial_ends_at' => now()->addDays($validated['trial_days']),
                        'assigned_note' => $validated['note'] ?? '',
                        'updated_at' => now(),
                    ]);
                $subId = $existing->id;
                $wasOverride = true;
            } else {
                // Create new
                $subId = DB::table('gymies_subscriptions')->insertGetId([
                    'trainer_user_id' => $id,
                    'plan_id' => $plan->id,
                    'status' => 'trialing',
                    'trial_source' => 'manual',
                    'trial_ends_at' => now()->addDays($validated['trial_days']),
                    'manually_assigned' => 1,
                    'assigned_by_user_id' => (int) $cyber->id,
                    'assigned_note' => $validated['note'] ?? '',
                    'current_period_start' => now(),
                    'current_period_end' => now()->addDays($validated['trial_days']),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            Log::info('Gymies cyber: assignSubscription', [
                'user_id' => $id,
                'plan' => $validated['plan_slug'],
                'trial_days' => $validated['trial_days'],
                'sub_id' => $subId,
                'was_override' => $wasOverride,
                'by_user_id' => (int) $cyber->id,
            ]);

            return response()->json([
                'ok' => true,
                'message' => 'Subscription ' . ($wasOverride ? 'bijgewerkt' : 'toegewezen') . '.',
                'subscription_id' => $subId,
                'was_override' => $wasOverride,
            ]);
        });
    }

    // 5. POST api/gymies/cyber/users/{id}/partner — Toggle partner status
    public function togglePartner(Request $request, int $id): JsonResponse
    {
        $id = (int) $id;

        $validated = $request->validate([
            'is_partner' => 'required|boolean',
            'trial_days' => 'nullable|integer|min:1|max:365',
        ]);

        $user = DB::table('gymies_users')->find($id);
        if (!$user) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }

        $update = [
            'is_partner' => $validated['is_partner'],
            'updated_at' => now(),
        ];

        if ($validated['trial_days'] ?? false) {
            $update['partner_trial_days'] = $validated['trial_days'];
        }

        if ($validated['is_partner'] && !$user->partner_since) {
            $update['partner_since'] = now();
        }

        DB::table('gymies_users')
            ->where('id', $id)
            ->update($update);

        Log::info('Gymies cyber: togglePartner', [
            'user_id' => $id,
            'is_partner' => $validated['is_partner'],
        ]);

        return response()->json([
            'ok' => true,
            'is_partner' => $validated['is_partner'],
        ]);
    }

    // 6. POST api/gymies/cyber/users/{id}/pause — Pauzeer/hervatten trainer account
    public function pauseAccount(Request $request, int $id): JsonResponse
    {
        $id = (int) $id;

        $validated = $request->validate([
            'pause' => 'required|boolean',
        ]);

        $trainerProfile = DB::table('gymies_trainer_profiles')
            ->where('user_id', $id)
            ->first();

        if (!$trainerProfile) {
            return response()->json(['message' => 'Trainer profiel niet gevonden.'], 404);
        }

        $newStatus = $validated['pause'] ? 'paused' : 'approved';

        DB::table('gymies_trainer_profiles')
            ->where('user_id', $id)
            ->update([
                'moderation_status' => $newStatus,
                'updated_at' => now(),
            ]);

        Log::info('Gymies cyber: pauseAccount', [
            'user_id' => $id,
            'new_status' => $newStatus,
        ]);

        return response()->json([
            'ok' => true,
            'status' => $newStatus,
        ]);
    }

    // 7. GET api/gymies/cyber/points/leaderboard — Punten-ranglijst
    public function pointsLeaderboard(Request $request): JsonResponse
    {
        // T-060 FIXED: pagination toegevoegd aan leaderboard
        $page   = max(1, (int)($request->query('page', 1)));
        $limit  = 50;
        $offset = ($page - 1) * $limit;

        $leaderboard = DB::table('gymies_users as u')
            ->leftJoin('gymies_referrals as ref', 'ref.referrer_user_id', '=', 'u.id')
            ->where('u.gymies_points', '>', 0)
            ->selectRaw('u.id, u.display_name, u.email, u.gymies_points, COUNT(DISTINCT ref.id) as referrals_count')
            ->groupBy('u.id', 'u.display_name', 'u.email', 'u.gymies_points')
            ->orderByDesc('u.gymies_points')
            ->limit($limit)
            ->offset($offset)
            ->get();

        Log::info('Gymies cyber: pointsLeaderboard', ['page' => $page]);

        return response()->json([
            'leaderboard' => $leaderboard,
            'page' => $page,
            'limit' => $limit,
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    // 8. POST api/gymies/cyber/points/adjust/{userId} — Handmatig punten aanpassen
    public function adjustPoints(Request $request, int $userId): JsonResponse
    {
        $userId = (int) $userId;
        $cyber = $request->attributes->get('gymies_user');

        // S-046: Ongelimiteerde punten aanpassing — Voeg range validatie toe
        $validated = $request->validate([
            'delta' => 'required|integer|between:-100000,100000',
            'reason' => 'required|string|min:5|max:500',
        ]);

        $user = DB::table('gymies_users')->find($userId);
        if (!$user) {
            return response()->json(['message' => 'Gebruiker niet gevonden.'], 404);
        }

        return DB::transaction(function () use ($userId, $user, $cyber, $validated) {
            // Update user points balance
            $newBalance = (int) $user->gymies_points + $validated['delta'];
            $newBalance = max(0, $newBalance); // Nooit negatief

            DB::table('gymies_users')
                ->where('id', $userId)
                ->update([
                    'gymies_points' => $newBalance,
                    'updated_at' => now(),
                ]);

            // Insert ledger entry — S-046: Opnamen reason in ledger
            DB::table('gymies_points_ledger')->insert([
                'user_id' => $userId,
                'event_type' => 'manual_adjustment',
                'points_delta' => $validated['delta'],
                'reference_id' => null,
                'reason' => $validated['reason'] ?? null,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            Log::info('Gymies cyber: adjustPoints', [
                'user_id' => $userId,
                'delta' => $validated['delta'],
                'reason' => $validated['reason'],
                'by_user_id' => (int) $cyber->id,
                'new_balance' => $newBalance,
            ]);

            return response()->json([
                'ok' => true,
                'new_balance' => $newBalance,
            ]);
        });
    }

    // 9. GET api/gymies/cyber/points/rules — Alle punten regels
    public function pointsRules(Request $request): JsonResponse
    {
        $rules = DB::table('gymies_points_rules')
            ->select('id', 'event_type', 'points_awarded', 'conditions_json', 'is_active', 'label', 'created_at', 'updated_at')
            ->get();

        Log::info('Gymies cyber: pointsRules');

        return response()->json([
            'rules' => $rules,
            'timestamp' => now()->toIso8601String(),
        ]);
    }

    // 10. PUT api/gymies/cyber/points/rules/{id} — Update punten regel
    public function updatePointsRule(Request $request, int $id): JsonResponse
    {
        $id = (int) $id;

        $validated = $request->validate([
            'points_awarded' => 'required|integer|min:0',
            'conditions_json' => 'nullable|json',
            'is_active' => 'required|boolean',
            'label' => 'nullable|string|max:255',
        ]);

        $rule = DB::table('gymies_points_rules')->find($id);
        if (!$rule) {
            return response()->json(['message' => 'Regel niet gevonden.'], 404);
        }

        $update = [
            'points_awarded' => $validated['points_awarded'],
            'is_active' => $validated['is_active'],
            'updated_at' => now(),
        ];

        if (isset($validated['conditions_json'])) {
            $update['conditions_json'] = $validated['conditions_json'];
        }

        if (isset($validated['label'])) {
            $update['label'] = $validated['label'];
        }

        DB::table('gymies_points_rules')
            ->where('id', $id)
            ->update($update);

        $updated = DB::table('gymies_points_rules')->find($id);

        Log::info('Gymies cyber: updatePointsRule', [
            'rule_id' => $id,
            'points_awarded' => $validated['points_awarded'],
        ]);

        return response()->json([
            'ok' => true,
            'rule' => $updated,
        ]);
    }

    // ─── Cyber Auth ──────────────────────────────────────────────

    public function cyberLogin(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user) return response()->json(['message' => 'Niet ingelogd.'], 401);
        $isCyber = ((int)($user->is_cyber ?? 0)) === 1;
        $isAdmin = ((int)($user->is_admin ?? 0)) === 1;
        if (!$isCyber && !$isAdmin) return response()->json(['message' => 'Geen cyber toegang.'], 403);
        $ip = $request->ip() ?? '0.0.0.0';
        $lockout = DB::table('gymies_cyber_pin_lockouts')->where('user_id', $user->id)->where('ip_address', $ip)->first();
        if ($lockout && $lockout->locked_until && now()->lt($lockout->locked_until)) {
            $remaining = now()->diffInMinutes($lockout->locked_until) + 1;
            $this->cyberAuditLog($user->id, null, 'cyber.login.blocked', '/cyber/auth', 'POST', $ip, 429);
            return response()->json(['message' => "Te veel pogingen. Probeer over {$remaining} minuten opnieuw.", 'locked_until' => $lockout->locked_until, 'remaining_minutes' => $remaining], 429);
        }
        $globalKey = 'cyber_pin_global:' . (int)$user->id;
        $globalWindowStart = now()->subMinutes(15);
        $globalAttempts = DB::table('gymies_rate_limits')->where('key', $globalKey)->where('window_start', '>=', $globalWindowStart)->count();
        if ($globalAttempts >= 10) {
            return response()->json(['message' => 'Te veel PIN pogingen. Account tijdelijk geblokkeerd.', 'retry_after' => 15 * 60], 429);
        }
        DB::table('gymies_rate_limits')->insert(['key' => $globalKey, 'window_start' => now(), 'created_at' => now()]);
        $pin = (string)($request->input('pin') ?? '');
        if (strlen($pin) !== self::CYBER_PIN_LENGTH || !ctype_digit($pin)) {
            return response()->json(['message' => 'PIN moet precies ' . self::CYBER_PIN_LENGTH . ' cijfers zijn.'], 422);
        }
        $pinHash = DB::table('gymies_users')->where('id', $user->id)->value('cyber_pin_hash');
        if (!$pinHash || !Hash::check($pin, $pinHash)) {
            $attempts = ($lockout->attempts ?? 0) + 1;
            $lockedUntil = $attempts >= self::CYBER_MAX_PIN_ATTEMPTS ? now()->addMinutes(self::CYBER_LOCKOUT_MINUTES)->toDateTimeString() : null;
            DB::table('gymies_cyber_pin_lockouts')->updateOrInsert(['user_id' => $user->id, 'ip_address' => $ip], ['attempts' => $attempts, 'locked_until' => $lockedUntil, 'last_attempt' => now()]);
            $this->cyberAuditLog($user->id, null, 'cyber.login.failed', '/cyber/auth', 'POST', $ip, 401);
            $remaining = max(0, self::CYBER_MAX_PIN_ATTEMPTS - $attempts);
            return response()->json(['message' => !$pinHash ? 'Geen PIN ingesteld. Stel eerst een PIN in.' : "Onjuiste PIN. Nog {$remaining} poging" . ($remaining !== 1 ? 'en' : '') . " over.", 'attempts_remaining' => $remaining, 'pin_not_set' => !$pinHash], 401);
        }
        DB::table('gymies_cyber_pin_lockouts')->where('user_id', $user->id)->where('ip_address', $ip)->delete();
        $rawToken = bin2hex(random_bytes(32));
        $tokenHash = hash('sha256', $rawToken);
        $expiresAt = now()->addMinutes(self::CYBER_TOKEN_TTL_MINUTES);
        DB::table('gymies_cyber_sessions')->where('user_id', $user->id)->where('ip_address', $ip)->update(['revoked' => 1]);
        $sessionId = DB::table('gymies_cyber_sessions')->insertGetId([
            'user_id' => $user->id, 'token_hash' => $tokenHash, 'ip_address' => $ip,
            'user_agent' => substr($request->userAgent() ?? '', 0, 500), 'last_active' => now(),
            'expires_at' => $expiresAt, 'revoked' => 0, 'created_at' => now(),
        ]);
        $this->cyberAuditLog($user->id, $sessionId, 'cyber.login.success', '/cyber/auth', 'POST', $ip, 200);
        return response()->json(['cyber_token' => $rawToken, 'expires_at' => $expiresAt->toIso8601String(), 'expires_in' => self::CYBER_TOKEN_TTL_MINUTES * 60, 'session_id' => $sessionId])
            ->withHeaders(['Cache-Control' => 'no-store, no-cache, must-revalidate', 'Pragma' => 'no-cache']);
    }

    public function cyberSetupPin(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user) return response()->json(['message' => 'Niet ingelogd.'], 401);
        $isCyber = ((int)($user->is_cyber ?? 0)) === 1;
        $isAdmin = ((int)($user->is_admin ?? 0)) === 1;
        if (!$isCyber && !$isAdmin) return response()->json(['message' => 'Geen cyber toegang.'], 403);
        $setupKey = 'cyber_pin_setup:' . (int)$user->id;
        $windowStart = now()->subMinutes(15);
        $attempts = DB::table('gymies_rate_limits')->where('key', $setupKey)->where('window_start', '>=', $windowStart)->count();
        if ($attempts >= 5) return response()->json(['message' => 'Te veel PIN setup pogingen.'], 429);
        DB::table('gymies_rate_limits')->insert(['key' => $setupKey, 'window_start' => now(), 'created_at' => now()]);
        $pin = (string)($request->input('pin') ?? '');
        $confirm = (string)($request->input('pin_confirmation') ?? '');
        if (strlen($pin) !== self::CYBER_PIN_LENGTH || !ctype_digit($pin)) return response()->json(['message' => 'PIN moet precies ' . self::CYBER_PIN_LENGTH . ' cijfers zijn.'], 422);
        if ($pin !== $confirm) return response()->json(['message' => 'PIN en bevestiging komen niet overeen.'], 422);
        DB::table('gymies_users')->where('id', $user->id)->update(['cyber_pin_hash' => Hash::make($pin), 'cyber_pin_set_at' => now()]);
        $this->cyberAuditLog($user->id, null, 'cyber.pin.setup', '/cyber/auth/setup-pin', 'POST', $request->ip() ?? '0.0.0.0', 200);
        return response()->json(['message' => 'PIN succesvol ingesteld.']);
    }

    public function cyberLogout(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user) return response()->json(['message' => 'Niet ingelogd.'], 401);
        $cyberToken = $request->header('X-Cyber-Token');
        $ip = $request->ip() ?? '0.0.0.0';
        if ($cyberToken) {
            $tokenHash = hash('sha256', $cyberToken);
            DB::table('gymies_cyber_sessions')->where('token_hash', $tokenHash)->where('user_id', $user->id)->update(['revoked' => 1]);
        } else {
            DB::table('gymies_cyber_sessions')->where('user_id', $user->id)->where('revoked', 0)->update(['revoked' => 1]);
        }
        $this->cyberAuditLog($user->id, null, 'cyber.logout', '/cyber/auth', 'DELETE', $ip, 200);
        return response()->json(['message' => 'Cyber sessie beëindigd.']);
    }

    public function cyberStatus(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user) return response()->json(['active' => false, 'reason' => 'not_authenticated'], 401);
        $cyberToken = $request->header('X-Cyber-Token');
        if (!$cyberToken) {
            return response()->json(['active' => false, 'reason' => 'no_cyber_token', 'pin_set' => !empty(DB::table('gymies_users')->where('id', $user->id)->value('cyber_pin_hash'))]);
        }
        $tokenHash = hash('sha256', $cyberToken);
        $session = DB::table('gymies_cyber_sessions')->where('user_id', $user->id)->where('revoked', 0)->where('expires_at', '>', now())->first();
        if (!$session || !hash_equals((string)$session->token_hash, (string)$tokenHash)) {
            return response()->json(['active' => false, 'reason' => 'session_invalid_or_expired']);
        }
        return response()->json(['active' => true, 'expires_at' => $session->expires_at, 'session_id' => $session->id]);
    }

    private function cyberAuditLog(int $userId, ?int $sessionId, string $action, string $endpoint, string $method, string $ip, int $statusCode, ?array $details = null): void
    {
        try {
            DB::table('gymies_cyber_audit_log')->insert([
                'user_id' => $userId, 'session_id' => $sessionId, 'action' => $action,
                'endpoint' => $endpoint, 'method' => $method, 'ip_address' => $ip,
                'status_code' => $statusCode, 'details' => $details ? json_encode($details) : null, 'created_at' => now(),
            ]);
        } catch (\Throwable $e) {
            Log::warning('[Cyber] Audit log mislukt: ' . $e->getMessage());
        }
    }
}
