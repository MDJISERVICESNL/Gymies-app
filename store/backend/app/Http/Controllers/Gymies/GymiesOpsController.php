<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

final class GymiesOpsController extends Controller
{
    private const ENABLE_MANUAL_BACKUP_ENDPOINT = true;
    private const ENABLE_MANUAL_WEB_SYNC_ENDPOINT = true;

    public function health(Request $request): JsonResponse
    {
        $dbOk = false;
        try {
            DB::select('SELECT 1');
            $dbOk = true;
        } catch (\Throwable $e) {
            $dbOk = false;
        }

        return response()->json([
            'status' => $dbOk ? 'ok' : 'degraded',
            'checks' => [
                'database' => $dbOk ? 'ok' : 'error',
            ],
            'timestamp' => now()->toIso8601String(),
        ], $dbOk ? 200 : 503);
    }

    public function metrics(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        // Trainers zien eigen metrics; admins zien platform-brede metrics
        if ($user->role !== 'trainer' && ((int) ($user->is_admin ?? 0)) !== 1) {
            return response()->json(['message' => 'Geen toegang tot metrics.'], 403);
        }
        $trainerId = (int) $user->id;

        $bookings = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->selectRaw("SUM(CASE WHEN status='confirmed' THEN 1 ELSE 0 END) as confirmed_count")
            ->selectRaw("SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END) as cancelled_count")
            ->selectRaw("SUM(CASE WHEN status='pending' THEN 1 ELSE 0 END) as pending_count")
            ->first();

        $errorCount = DB::getSchemaBuilder()->hasTable('gymies_api_error_logs')
            ? (int) DB::table('gymies_api_error_logs')
                ->where('user_id', $trainerId)
                ->where('created_at', '>=', now()->subHours(24))
                ->count()
            : 0;

        return response()->json([
            'data' => [
                'pending_count' => (int) ($bookings->pending_count ?? 0),
                'confirmed_count' => (int) ($bookings->confirmed_count ?? 0),
                'cancelled_count' => (int) ($bookings->cancelled_count ?? 0),
                'api_errors_24h' => $errorCount,
                'generated_at' => now()->toIso8601String(),
            ],
        ]);
    }

    public function featureFlags(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $defaults = [
            'trainer_dashboard_suggestions' => true,
            'trainer_dashboard_customization' => true,
            'trainer_realtime_badges' => true,
            'trainer_email_notifications' => true,
        ];

        if (!DB::getSchemaBuilder()->hasTable('gymies_system_settings')) {
            return response()->json(['data' => $defaults]);
        }

        $rows = DB::table('gymies_system_settings')
            ->whereIn('setting_key', array_keys($defaults))
            ->get(['setting_key', 'setting_value']);

        $flags = $defaults;
        foreach ($rows as $row) {
            $flags[(string) $row->setting_key] = in_array((string) $row->setting_value, ['1', 'true', 'on'], true);
        }
        return response()->json(['data' => $flags]);
    }

    /**
     * Filterdefinities ophalen voor een context (tickets, bookings, users, payouts, trainers, group_sessions).
     * Publiek voor trainers; admin-contexts vereisen admin-rechten.
     */
    public function filterDefinitions(Request $request): JsonResponse
    {
        $context = trim((string) ($request->query('context') ?? ''));
        $allowedPublic = ['trainers'];
        $allowedAdmin = ['tickets', 'bookings', 'users', 'payouts', 'group_sessions'];
        $allowed = array_merge($allowedPublic, $allowedAdmin);

        if ($context === '' || !in_array($context, $allowed, true)) {
            return response()->json([
                'message' => 'Ongeldige of ontbrekende context. Gebruik: ?context=tickets|bookings|users|payouts|trainers|group_sessions',
            ], 422);
        }

        if (in_array($context, $allowedAdmin, true)) {
            $user = $request->attributes->get('gymies_user');
            if (!$user || $user->role !== 'admin') {
                return response()->json(['message' => 'Alleen admins kunnen filterdefinities voor deze context ophalen.'], 403);
            }
        }

        if (!Schema::hasTable('gymies_filter_definitions')) {
            return response()->json(['data' => []]);
        }

        $rows = DB::table('gymies_filter_definitions')
            ->where('context', $context)
            ->where('is_active', 1)
            ->orderBy('sort_order')
            ->orderBy('filter_key')
            ->get(['filter_key', 'label', 'filter_type', 'options_json', 'default_value', 'placeholder', 'sort_order']);

        $data = $rows->map(static function ($r) {
            $options = $r->options_json;
            if (is_string($options)) {
                $options = json_decode($options, true);
            }
            return [
                'filter_key' => $r->filter_key,
                'label' => $r->label,
                'filter_type' => $r->filter_type,
                'options' => is_array($options) ? $options : [],
                'default_value' => $r->default_value,
                'placeholder' => $r->placeholder,
                'sort_order' => (int) $r->sort_order,
            ];
        })->all();

        return response()->json(['data' => $data]);
    }

    public function runBackup(Request $request): JsonResponse
    {
        if (!self::ENABLE_MANUAL_BACKUP_ENDPOINT) {
            return response()->json(['message' => 'Backup endpoint is uitgeschakeld.'], 404);
        }

        $user = $request->attributes->get('gymies_user');
        if (!$user || ((int) ($user->is_admin ?? 0)) !== 1) {
            return response()->json(['message' => 'Alleen admins kunnen een backup starten.'], 403);
        }

        $backupDir = env('TRAINMAAT_BACKUP_DIR', '/root/backups');
        $laravelPath = base_path();
        $timestamp = now()->format('Ymd_His');
        $archiveName = "gymies_app_{$timestamp}.tar.gz";
        $archivePath = rtrim($backupDir, '/') . '/' . $archiveName;

        // S-048: Command Injection Risk — valideer padden voordat ze in shell-commando's worden gebruikt
        if (!preg_match('/^[a-zA-Z0-9\/._-]+$/', $laravelPath)) {
            logger()->warning('Gymies Ops runBackup: laravelPath validation failed', [
                'path' => $laravelPath,
            ]);
            return response()->json(['message' => 'Ongeldig Laravel-pad.'], 422);
        }
        if (!preg_match('/^[a-zA-Z0-9\/._-]+$/', $backupDir)) {
            logger()->warning('Gymies Ops runBackup: backupDir validation failed', [
                'path' => $backupDir,
            ]);
            return response()->json(['message' => 'Ongeldig backup-directory.'], 422);
        }

        $sudoCheck = 1;
        @exec('sudo -n true', $sudoOutput, $sudoCheck);
        if ($sudoCheck !== 0) {
            return response()->json([
                'message' => 'Backup vereist sudo-rechten voor de webuser op /root/backups.',
            ], 500);
        }

        // Draait als achtergrondproces zodat UI direct kan doorgaan.
        $command = sprintf(
            "nohup bash -lc %s > /dev/null 2>&1 &",
            escapeshellarg(sprintf(
                "sudo -n mkdir -p %s && sudo -n tar -czf %s %s",
                escapeshellarg($backupDir),
                escapeshellarg($archivePath),
                escapeshellarg($laravelPath)
            ))
        );

        @exec($command, $output, $exitCode);
        if ($exitCode !== 0) {
            // T-010 FIXED: interne paden verborgen in error responses
            if (!app()->environment('local', 'testing')) {
                return response()->json(['message' => 'Operatie mislukt. Contacteer de beheerder.'], 500);
            }
            // Alleen in local/testing het gedetailleerde pad tonen
            return response()->json(['message' => 'Fout: Backup kon niet gestart worden. Exit code: ' . $exitCode], 500);
        }

        return response()->json([
            'data' => [
                'status' => 'started',
                'backup_path' => $archivePath,
                'started_at' => now()->toIso8601String(),
            ],
        ], 202);
    }

    public function runWebSync(Request $request): JsonResponse
    {
        if (!self::ENABLE_MANUAL_WEB_SYNC_ENDPOINT) {
            return response()->json(['message' => 'Web sync endpoint is uitgeschakeld.'], 404);
        }

        $user = $request->attributes->get('gymies_user');
        if (!$user || ((int) ($user->is_admin ?? 0)) !== 1) {
            return response()->json(['message' => 'Alleen admins kunnen een web sync starten.'], 403);
        }

        $scriptPath = env(
            'GYMIES_WEB_SYNC_SCRIPT',
            '/var/www/gymies.nl/laravel/gymies_deploy/sync_gymies_web.sh'
        );

        // S-082: Unsafe Shell Script — valideer scriptpad voordat uitvoering + check symlinks
        if (!is_file($scriptPath)) {
            return response()->json([
                'message' => 'Sync script niet gevonden op server.',
                'script_path' => $scriptPath,
            ], 500);
        }

        if (!is_readable($scriptPath)) {
            return response()->json([
                'message' => 'Sync script is niet leesbaar. Controleer permissies.',
                'script_path' => $scriptPath,
            ], 500);
        }

        // Voorkomen van symlink-aanvallen: realpath resolveert symlinks
        $realPath = realpath($scriptPath);
        if ($realPath === false) {
            return response()->json([
                'message' => 'Kan scriptpad niet resolven.',
                'script_path' => $scriptPath,
            ], 500);
        }

        // Valideer dat het pad binnen verwachte directory valt
        $expectedBase = '/var/www/gymies.nl/laravel/gymies_deploy';
        if (strpos($realPath, $expectedBase) !== 0) {
            logger()->warning('Gymies Ops runWebSync: path outside expected directory', [
                'resolved_path' => $realPath,
                'expected_base' => $expectedBase,
            ]);
            return response()->json([
                'message' => 'Scriptpad is niet in verwachte directory.',
                'script_path' => $scriptPath,
            ], 422);
        }

        if (!is_executable($realPath)) {
            return response()->json([
                'message' => 'Sync script is niet uitvoerbaar. Geef execute permissie (chmod +x).',
                'script_path' => $scriptPath,
            ], 500);
        }

        $logPath = storage_path('logs/gymies_web_sync.log');
        // T-014 FIXED: achtergrondprocess PID bijgehouden voor timeout beheer
        $pidFile = sys_get_temp_dir() . '/gymies_sync_' . time() . '.pid';
        $command = sprintf(
            "nohup bash -lc %s >> %s 2>&1 & echo $!",
            escapeshellarg(escapeshellcmd($realPath)),
            escapeshellarg($logPath)
        );

        $output = [];
        @exec($command, $output, $exitCode);
        if ($exitCode !== 0) {
            // T-010 FIXED: interne paden verborgen in error responses
            if (!app()->environment('local', 'testing')) {
                return response()->json(['message' => 'Operatie mislukt. Contacteer de beheerder.'], 500);
            }
            return response()->json(['message' => 'Fout: Web sync kon niet gestart worden.'], 500);
        }

        // T-014: Sla PID op van started process
        $pid = (int) ($output[0] ?? 0);
        if ($pid > 0) {
            file_put_contents($pidFile, (string) $pid);
        }

        return response()->json([
            'data' => [
                'status' => 'started',
                'script_path' => $scriptPath,
                'log_path' => $logPath,
                'process_id' => $pid > 0 ? $pid : null,
                'started_at' => now()->toIso8601String(),
            ],
        ], 202);
    }

    /** Actieve banner en onderhoudsmodus voor de app (binnen auth). */
    public function broadcastsActive(Request $request): JsonResponse
    {
        if (!Schema::hasTable('gymies_broadcasts')) {
            return response()->json(['data' => ['banner' => null, 'maintenance' => false, 'maintenance_message' => null]]);
        }
        $now = now()->toDateTimeString();
        $banner = DB::table('gymies_broadcasts')
            ->where('type', 'banner')
            ->where(function ($q) use ($now): void {
                $q->whereNull('active_until')->orWhere('active_until', '>', $now);
            })
            ->orderByDesc('id')
            ->first(['id', 'title', 'message', 'severity']);
        $maintenance = DB::table('gymies_broadcasts')
            ->where('type', 'maintenance')
            ->where(function ($q) use ($now): void {
                $q->whereNull('active_until')->orWhere('active_until', '>', $now);
            })
            ->orderByDesc('id')
            ->first(['id', 'message', 'title']);
        return response()->json([
            'data' => [
                'banner' => $banner ? [
                    'id' => (string) $banner->id,
                    'title' => $banner->title ?? null,
                    'message' => (string) $banner->message,
                    'severity' => (string) ($banner->severity ?? 'info'),
                ] : null,
                'maintenance' => $maintenance !== null,
                'maintenance_message' => $maintenance ? (trim((string) ($maintenance->title ?? '')) !== '' ? $maintenance->title : $maintenance->message) : null,
            ],
        ]);
    }

    /**
     * Publieke site-media (hero/secties) — admin beheert via Control Tower (gymies_system_settings).
     * Lege strings = geen asset; app toont gradient/placeholder.
     * site_subscriptions_json wordt ALTIJD dynamisch uit gymies_plans gegenereerd (nooit opslaan/bewerken).
     */
    public function siteMediaPublic(): JsonResponse
    {
        $keys = [
            'site_hero_image_url',
            'site_hero_video_url',
            'site_section_training_url',
            'site_section_trainer_url',
            'site_section_fitness_url',
            'site_og_image_url',
            'site_gallery_urls',
            'site_subscriptions_json',
            'yearly_discount_percent',
            'plan_starter_features',
            'plan_pro_features',
            'plan_studio_features',
        ];
        $defaults = array_fill_keys($keys, '');
        if (!Schema::hasTable('gymies_system_settings')) {
            $defaults['site_subscriptions_json'] = $this->buildSiteSubscriptionsJsonFromPlans(15);
            $defaults['yearly_discount_percent'] = '15';
            return response()->json(['data' => $defaults]);
        }
        $rows = DB::table('gymies_system_settings')->whereIn('setting_key', $keys)->get(['setting_key', 'setting_value']);
        $out = $defaults;
        foreach ($rows as $row) {
            $k = (string) $row->setting_key;
            if (isset($out[$k]) && $k !== 'site_subscriptions_json') {
                $out[$k] = trim((string) ($row->setting_value ?? ''));
            }
        }
        // Lege plan-features = JSON array
        foreach (['plan_starter_features', 'plan_pro_features', 'plan_studio_features'] as $fk) {
            if (!isset($out[$fk]) || $out[$fk] === '') {
                $out[$fk] = '[]';
            }
        }
        if (!isset($out['site_gallery_urls']) || $out['site_gallery_urls'] === '') {
            $out['site_gallery_urls'] = '[]';
        }
        $discount = $this->getYearlyDiscountPercent();
        if (!isset($out['yearly_discount_percent']) || trim((string) $out['yearly_discount_percent']) === '') {
            $out['yearly_discount_percent'] = (string) $discount;
        }
        $out['site_subscriptions_json'] = $this->buildSiteSubscriptionsJsonFromPlans($discount);
        return response()->json(['data' => $out]);
    }

    /**
     * Jaarlijkse korting in procenten (0–100). Uit gymies_system_settings.yearly_discount_percent.
     */
    private function getYearlyDiscountPercent(): int
    {
        if (!Schema::hasTable('gymies_system_settings')) {
            return 15;
        }
        $row = DB::table('gymies_system_settings')->where('setting_key', 'yearly_discount_percent')->first();
        $val = $row ? trim((string) ($row->setting_value ?? '')) : '';
        $pct = (int) $val;
        return ($pct >= 0 && $pct <= 100) ? $pct : 15;
    }

    /**
     * Genereer site_subscriptions_json uit gymies_plans.
     * Waterdicht: exact 3 plannen (starter, pro, studio), één per slug. Geen duplicaten.
     * Prijzen dynamisch uit DB. Jaarprijs = monthly × 12 × (1 - discount/100) of price_cents_per_year.
     */
    private function buildSiteSubscriptionsJsonFromPlans(int $yearlyDiscountPercent): string
    {
        $defaults = [
            'starter' => ['description' => 'Voor de beginnende trainer', 'features' => ['1 Actief profiel', 'Directe boekingen', 'Support via community'], 'buttonText' => 'Begin gratis', 'isFeatured' => false],
            'pro' => ['description' => 'Meest gekozen door experts', 'features' => ['Story functionaliteit', '0% Commissie op sessies', 'Priority in zoekresultaten', 'Uitgebreide analytics'], 'buttonText' => 'Start met Pro', 'isFeatured' => true],
            'studio' => ['description' => "Voor studio's en gyms", 'features' => ['Onbeperkt trainers', 'Eigen branding opties', 'API koppelingen', 'Dedicated manager'], 'buttonText' => 'Contact sales', 'isFeatured' => false],
        ];
        $storedFeatures = $this->loadPlanFeaturesFromSettings();
        $order = ['starter', 'pro', 'studio'];
        $fallbackPrices = ['starter' => 0, 'pro' => 2995, 'studio' => 9995];

        $bySlug = [];
        if (Schema::hasTable('gymies_plans')) {
            $select = ['slug', 'name', 'description', 'price_cents_per_month'];
            if (Schema::hasColumn('gymies_plans', 'price_cents_per_year')) {
                $select[] = 'price_cents_per_year';
            }
            $plans = DB::table('gymies_plans')
                ->whereIn('slug', $order)
                ->when(Schema::hasColumn('gymies_plans', 'is_active'), fn ($q) => $q->where('is_active', 1))
                ->orderByRaw("FIELD(slug, 'starter', 'pro', 'studio')")
                ->orderBy('id')
                ->get($select);

            foreach ($plans as $p) {
                $slug = (string) ($p->slug ?? '');
                if ($slug === '' || !in_array($slug, $order, true) || isset($bySlug[$slug])) {
                    continue;
                }
                $centsMonthly = (int) ($p->price_cents_per_month ?? 0);
                $centsYearly = null;
                if (Schema::hasColumn('gymies_plans', 'price_cents_per_year') && isset($p->price_cents_per_year) && $p->price_cents_per_year !== null) {
                    $centsYearly = (int) $p->price_cents_per_year;
                }
                if ($centsYearly === null && $centsMonthly > 0 && $yearlyDiscountPercent >= 0 && $yearlyDiscountPercent <= 100) {
                    $centsYearly = (int) round($centsMonthly * 12 * (1 - $yearlyDiscountPercent / 100));
                }
                $priceStr = $this->formatPriceCents($centsMonthly);
                $priceYearlyStr = $centsYearly !== null ? $this->formatPriceCents($centsYearly) : $priceStr;
                $def = $defaults[$slug] ?? ['description' => (string) ($p->description ?? ''), 'features' => [], 'buttonText' => 'Kies plan', 'isFeatured' => false];
                $features = !empty($storedFeatures[$slug]) ? $storedFeatures[$slug] : $def['features'];
                $bySlug[$slug] = [
                    'slug' => $slug,
                    'title' => (string) ($p->name ?? ucfirst($slug)),
                    'price' => $priceStr,
                    'price_yearly' => $priceYearlyStr,
                    'description' => trim((string) ($p->description ?? '')) !== '' ? (string) $p->description : $def['description'],
                    'features' => $features,
                    'buttonText' => $def['buttonText'],
                    'isFeatured' => $def['isFeatured'],
                ];
            }
        }

        $arr = [];
        foreach ($order as $slug) {
            if (isset($bySlug[$slug])) {
                $arr[] = $bySlug[$slug];
            } else {
                $def = $defaults[$slug];
                $features = !empty($storedFeatures[$slug]) ? $storedFeatures[$slug] : $def['features'];
                $fallback = $fallbackPrices[$slug] ?? 0;
                $priceStr = $this->formatPriceCents($fallback);
                $yearlyCents = $fallback > 0 ? (int) round($fallback * 12 * (1 - $yearlyDiscountPercent / 100)) : 0;
                $arr[] = [
                    'slug' => $slug,
                    'title' => ucfirst($slug),
                    'price' => $priceStr,
                    'price_yearly' => $this->formatPriceCents($yearlyCents),
                    'description' => $def['description'],
                    'features' => $features,
                    'buttonText' => $def['buttonText'],
                    'isFeatured' => $def['isFeatured'],
                ];
            }
        }
        $json = json_encode($arr, JSON_UNESCAPED_UNICODE);
        return $json !== false ? $json : '[]';
    }

    private function formatPriceCents(int $cents): string
    {
        if ($cents <= 0) {
            return '€0';
        }
        $euro = $cents / 100;
        return $euro == floor($euro) ? '€' . (int) $euro : '€' . number_format($euro, 2, ',', '');
    }

    /**
     * T-018 FIXED: options_json structuur validatie voor filters
     * Valideer dat options_json alleen veilige value+label pairs bevat
     */
    private function validateFilterOptionsJson(?array $options): array
    {
        if (!is_array($options)) {
            return [];
        }
        // Sanitiseer: alleen value + label
        $safeOptions = array_map(function ($opt) {
            return [
                'value' => htmlspecialchars((string)($opt['value'] ?? ''), ENT_QUOTES, 'UTF-8'),
                'label' => htmlspecialchars((string)($opt['label'] ?? ''), ENT_QUOTES, 'UTF-8'),
            ];
        }, array_slice($options, 0, 100)); // Begrens tot 100 entries
        return $safeOptions;
    }

    /**
     * Lees opgeslagen features per plan uit gymies_system_settings.
     * Keys: plan_starter_features, plan_pro_features, plan_studio_features (JSON array).
     */
    private function loadPlanFeaturesFromSettings(): array
    {
        $out = [];
        $order = ['starter', 'pro', 'studio'];
        if (!Schema::hasTable('gymies_system_settings')) {
            return $out;
        }
        foreach ($order as $slug) {
            $key = 'plan_' . $slug . '_features';
            $row = DB::table('gymies_system_settings')->where('setting_key', $key)->first();
            $raw = $row ? trim((string) ($row->setting_value ?? '')) : '';
            if ($raw === '') {
                continue;
            }
            $decoded = json_decode($raw, true);
            if (is_array($decoded)) {
                $list = array_values(array_filter(array_map('strval', $decoded), fn ($s) => trim($s) !== ''));
                if (!empty($list)) {
                    $out[$slug] = $list;
                }
            }
        }
        return $out;
    }
}
