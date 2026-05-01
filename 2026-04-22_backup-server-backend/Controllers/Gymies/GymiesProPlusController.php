<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Models\TrainerProPlusSettings;
use App\Models\TrainerNewsletter;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;

final class GymiesProPlusController extends Controller
{
    /**
     * Self-healing: maak de gymies_trainer_pro_plus_settings tabel aan als deze niet bestaat.
     * Voorkomt 500-fouten wanneer de migratie nog niet is gedraaid op de server.
     */
    private static function ensureTable(): void
    {
        if (Schema::hasTable('gymies_trainer_pro_plus_settings')) {
            return;
        }

        Schema::create('gymies_trainer_pro_plus_settings', function (\Illuminate\Database\Schema\Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('trainer_user_id')->unique();
            $table->string('brand_color', 7)->nullable();
            $table->string('brand_logo_url', 500)->nullable();
            $table->string('brand_banner_url', 500)->nullable();
            $table->string('intro_video_url', 500)->nullable();
            $table->string('custom_slug', 100)->nullable()->unique();
            $table->boolean('newsletter_enabled')->default(false);
            $table->boolean('booking_widget_enabled')->default(false);
            $table->boolean('is_verified')->default(false);
            $table->string('qr_code_url', 500)->nullable();
            $table->timestamps();

            $table->index('trainer_user_id');
        });

        if (function_exists('logger')) {
            logger()->info('[GymiesProPlus] Self-healed: created gymies_trainer_pro_plus_settings table');
        }
    }

    /**
     * Self-healing: maak de gymies_trainer_newsletters tabel aan als deze niet bestaat.
     */
    private static function ensureNewsletterTable(): void
    {
        if (Schema::hasTable('gymies_trainer_newsletters')) {
            return;
        }

        Schema::create('gymies_trainer_newsletters', function (\Illuminate\Database\Schema\Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('trainer_user_id');
            $table->string('subject', 200);
            $table->text('body');
            $table->unsignedInteger('sent_to_count')->default(0);
            $table->timestamps();

            $table->index('trainer_user_id');
        });

        if (function_exists('logger')) {
            logger()->info('[GymiesProPlus] Self-healed: created gymies_trainer_newsletters table');
        }
    }

    /**
     * Map Eloquent model velden naar Flutter-verwachte sleutels.
     * DB: booking_widget_enabled → Flutter: widget_enabled
     * DB: is_verified → Flutter: verified_badge
     */
    private static function settingsToFlutter(TrainerProPlusSettings $settings): array
    {
        return [
            'brand_color'        => $settings->brand_color,
            'brand_logo_url'     => $settings->brand_logo_url,
            'brand_banner_url'   => $settings->brand_banner_url,
            'intro_video_url'    => $settings->intro_video_url,
            'custom_slug'        => $settings->custom_slug,
            'newsletter_enabled' => (bool) $settings->newsletter_enabled,
            'widget_enabled'     => (bool) $settings->booking_widget_enabled,
            'verified_badge'     => (bool) $settings->is_verified,
            'qr_code_url'        => $settings->qr_code_url,
        ];
    }

    /**
     * Map Flutter-veldnamen naar DB-kolomnamen voor update.
     */
    private static function mapFlutterToDb(array $data): array
    {
        $mapped = [];
        $fieldMap = [
            'widget_enabled'     => 'booking_widget_enabled',
            'verified_badge'     => 'is_verified',
        ];
        foreach ($data as $key => $value) {
            $dbKey = $fieldMap[$key] ?? $key;
            $mapped[$dbKey] = $value;
        }
        return $mapped;
    }

    /**
     * Get Pro+ settings for authenticated trainer
     */
    public function getSettings(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        // Check if Pro+
        $assertion = GymiesPlanManager::assertProPlus((int) $user->id);
        if (!$assertion['allowed']) {
            return response()->json([
                'message' => $assertion['message'],
                'upgrade_hint' => $assertion['upgrade_hint'],
                'error' => 'upgrade_required',
            ], 403);
        }

        self::ensureTable();

        $settings = TrainerProPlusSettings::where('trainer_user_id', (int) $user->id)->first();
        if (!$settings) {
            // Create default settings if doesn't exist
            $settings = TrainerProPlusSettings::create([
                'trainer_user_id' => (int) $user->id,
            ]);
        }

        return response()->json([
            'settings' => self::settingsToFlutter($settings),
        ]);
    }

    /**
     * Update Pro+ settings
     */
    public function updateSettings(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        // Check if Pro+
        $assertion = GymiesPlanManager::assertProPlus((int) $user->id);
        if (!$assertion['allowed']) {
            return response()->json([
                'message' => $assertion['message'],
                'upgrade_hint' => $assertion['upgrade_hint'],
                'error' => 'upgrade_required',
            ], 403);
        }

        // Gereserveerde slugs die trainers niet mogen gebruiken
        $reservedSlugs = [
            'admin', 'api', 'login', 'register', 'dashboard', 'trainer', 'trainers',
            'gym', 'gymies', 'support', 'help', 'about', 'contact', 'blog', 'pricing',
            'terms', 'privacy', 'sitemap', 'robots', 'feed', 'www', 'mail', 'email',
            'app', 'web', 'static', 'assets', 'images', 'css', 'js', 'fonts',
            'null', 'undefined', 'true', 'false', 'new', 'create', 'edit', 'delete',
            'update', 'store', 'index', 'home', 'search', 'filter', 'sort', 'page',
            'voor-trainers', 'voor-gyms', 'ambassador', 'faq', 'over-ons', 'steden',
        ];

        // Saniteer de slug eerst voordat validatie plaatsvindt
        if ($request->has('custom_slug') && $request->input('custom_slug') !== null) {
            $rawSlug = strtolower(trim($request->input('custom_slug')));
            $rawSlug = preg_replace('/[^a-z0-9\-]/', '', $rawSlug);
            $rawSlug = preg_replace('/-+/', '-', $rawSlug);
            $rawSlug = trim($rawSlug, '-');
            $request->merge(['custom_slug' => $rawSlug]);
        }

        $validated = $request->validate([
            'brand_color'        => ['nullable', 'string', 'regex:/^#[A-Fa-f0-9]{6}$/'],
            'custom_slug'        => [
                'nullable', 'string', 'min:3', 'max:50',
                'regex:/^[a-z0-9][a-z0-9\-]*[a-z0-9]$/',
                \Illuminate\Validation\Rule::notIn($reservedSlugs),
                \Illuminate\Validation\Rule::unique('gymies_trainer_pro_plus_settings', 'custom_slug')
                    ->ignore($user->id, 'trainer_user_id')  // unique slug check excludes current trainer,
            ],
            'intro_video_url'    => ['nullable', 'string', 'max:500', 'url'],
            'newsletter_enabled' => ['nullable', 'boolean'],
            'widget_enabled'     => ['nullable', 'boolean'],
            'verified_badge'     => ['nullable', 'boolean'], // admin-only in productie
        ]);

        self::ensureTable();

        $settings = TrainerProPlusSettings::firstOrCreate(['trainer_user_id' => (int) $user->id]);
        // Map Flutter-veldnamen naar DB-kolomnamen (widget_enabled → booking_widget_enabled, etc.)
        $dbData = self::mapFlutterToDb(array_filter($validated, fn($v) => $v !== null));
        $settings->update($dbData);

        return response()->json([
            'ok' => true,
            'settings' => self::settingsToFlutter($settings),
            'message' => 'Pro+ settings updated successfully.',
        ]);
    }

    /**
     * Send newsletter to all active clients
     */
    public function sendNewsletter(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        // Check if Pro+ and newsletter enabled
        $assertion = GymiesPlanManager::assertProPlus((int) $user->id);
        if (!$assertion['allowed']) {
            return response()->json([
                'message' => $assertion['message'],
                'error' => 'upgrade_required',
            ], 403);
        }

        self::ensureTable();

        $settings = TrainerProPlusSettings::where('trainer_user_id', (int) $user->id)->first();
        if (!$settings || !$settings->newsletter_enabled) {
            return response()->json([
                'message' => 'Newsletter feature is not enabled in Pro+ settings.',
                'error' => 'newsletter_disabled',
            ], 403);
        }

        self::ensureNewsletterTable();

        // Rate limit: max 2 nieuwsbrieven per 7 dagen
        $recentCount = TrainerNewsletter::where('trainer_user_id', (int) $user->id)
            ->where('created_at', '>=', now()->subDays(7))
            ->count();

        if ($recentCount >= 2) {
            $oldestRecent = TrainerNewsletter::where('trainer_user_id', (int) $user->id)
                ->where('created_at', '>=', now()->subDays(7))
                ->orderBy('created_at')
                ->first();

            $nextAllowedAt = $oldestRecent?->created_at->addDays(7);

            return response()->json([
                'error'           => 'rate_limit_exceeded',
                'message'         => 'Je hebt het maximum van 2 nieuwsbrieven per week bereikt.',
                'next_allowed_at' => $nextAllowedAt?->toIso8601String(),
                'next_allowed_human' => $nextAllowedAt?->diffForHumans(),
            ], 429);
        }

        $validated = $request->validate([
            'subject' => ['required', 'string', 'max:200', 'regex:/^[^<>{}]*$/'],
            'body'    => ['required', 'string', 'min:10', 'max:1000'],
        ]);

        // Sanitize: strip alle HTML/script tags, daarna veilig escapen
        $validated['subject'] = strip_tags(trim($validated['subject']));
        $validated['body']    = strip_tags(trim($validated['body']));

        // Get all active clients who booked sessions in last 60 days
        $clients = DB::table('gymies_users as u')
            ->leftJoin('gymies_bookings as b', 'b.client_user_id', '=', 'u.id')
            ->where('u.role', 'client')
            ->where('b.trainer_user_id', (int) $user->id)
            ->where('b.created_at', '>=', now()->subDays(60))
            ->select('u.id', 'u.email', 'u.display_name')
            ->distinct()
            ->get();

        if ($clients->isEmpty()) {
            return response()->json([
                'message' => 'No active clients found.',
                'sent_to' => 0,
            ]);
        }

        // Queue emails for sending
        $sentCount = 0;
        foreach ($clients as $client) {
            if ($client->email) {
                try {
                    // Queue newsletter job (async)
                    Mail::queue(function ($message) use ($client, $validated, $user) {
                        $message
                            ->to($client->email)
                            ->subject($validated['subject'])
                            ->html($this->renderNewsletterHtml($validated['body'], $client->display_name));
                    });
                    $sentCount++;
                } catch (\Throwable $e) {
                    if (function_exists('logger')) {
                        logger()->error('Newsletter send failed', [
                            'trainer_user_id' => $user->id,
                            'client_id' => $client->id,
                            'error' => $e->getMessage(),
                        ]);
                    }
                }
            }
        }

        // Log newsletter
        TrainerNewsletter::create([
            'trainer_user_id' => (int) $user->id,
            'subject' => $validated['subject'],
            'body' => $validated['body'],
            'sent_to_count' => $sentCount,
        ]);

        return response()->json([
            'ok' => true,
            'message' => "Newsletter queued for {$sentCount} clients.",
            'sent_to' => $sentCount,
        ]);
    }

    /**
     * Get embed widget code for trainer's Pro+ page
     */
    public function getWidgetCode(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        // Check if Pro+
        $assertion = GymiesPlanManager::assertProPlus((int) $user->id);
        if (!$assertion['allowed']) {
            return response()->json([
                'message' => $assertion['message'],
                'error' => 'upgrade_required',
            ], 403);
        }

        self::ensureTable();

        $settings = TrainerProPlusSettings::where('trainer_user_id', (int) $user->id)->first();
        if (!$settings) {
            return response()->json(['message' => 'Pro+ settings not found.'], 404);
        }

        $slug = $settings->custom_slug ?? 'trainer-' . $user->id;
        $color = $settings->brand_color ?? '#0B1F3A';

        // Generate widget embed code — gebruik API domein voor widget.js
        $apiDomain = rtrim(config('app.url', 'https://www.gymies.nl'), '/');
        $widgetCode = <<<HTML
<script async src="{$apiDomain}/widget.js" data-trainer="{$slug}" data-brand-color="{$color}"></script>
<div id="gymies-widget-{$slug}"></div>
HTML;

        return response()->json([
            'widget_code' => $widgetCode,
            'slug' => $slug,
            'brand_color' => $color,
        ]);
    }

    /**
     * Generate QR code for trainer's Pro+ page
     */
    public function getQRCode(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        // Check if Pro+
        $assertion = GymiesPlanManager::assertProPlus((int) $user->id);
        if (!$assertion['allowed']) {
            return response()->json([
                'message' => $assertion['message'],
                'error' => 'upgrade_required',
            ], 403);
        }

        self::ensureTable();

        $settings = TrainerProPlusSettings::where('trainer_user_id', (int) $user->id)->first();
        if (!$settings) {
            return response()->json(['message' => 'Pro+ settings not found.'], 404);
        }

        $slug = $settings->custom_slug ?? 'trainer-' . $user->id;
        $targetUrl = 'https://gymies.nl/trainer/' . urlencode($slug);

        // Return URL — frontend can generate QR using any QR library
        return response()->json([
            'qr_url' => $targetUrl,
            'slug' => $slug,
            'message' => 'Use any QR code generator with this URL to create a scannable code.',
        ]);
    }

    /**
     * Get client analytics for Pro+
     */
    public function getClientAnalytics(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        // Check if Pro+
        $assertion = GymiesPlanManager::assertProPlus((int) $user->id);
        if (!$assertion['allowed']) {
            return response()->json([
                'message' => $assertion['message'],
                'error' => 'upgrade_required',
            ], 403);
        }

        $clients = DB::table('gymies_users as u')
            ->leftJoin('gymies_bookings as b', 'b.client_user_id', '=', 'u.id')
            ->where('u.role', 'client')
            ->where('b.trainer_user_id', (int) $user->id)
            ->select(
                'u.id as client_id',
                'u.display_name',
                DB::raw('COUNT(b.id) as total_sessions'),
                DB::raw('SUM(COALESCE(b.amount_cents, 0)) as total_spent_cents'),
                DB::raw('MAX(b.created_at) as last_session_at')
            )
            ->groupBy('u.id', 'u.display_name')
            ->orderByDesc('last_session_at')
            ->get()
            ->map(function ($row) {
                // Determine status based on last session
                $lastSession = $row->last_session_at ? \Carbon\Carbon::parse($row->last_session_at) : null;
                $daysAgo = $lastSession ? $lastSession->diffInDays(now()) : 999;

                // Flutter verwacht: 'active', 'risk', 'inactive' — niet 'at_risk'/'churned'
                $status = match (true) {
                    $daysAgo <= 30 => 'active',
                    $daysAgo <= 60 => 'risk',
                    default => 'inactive',
                };

                // Privacy: retourneer alleen voornaam + eerste letter achternaam
                $nameParts    = explode(' ', trim($row->display_name ?? ''), 2);
                $displayName  = $nameParts[0] . (isset($nameParts[1]) ? ' ' . strtoupper(substr($nameParts[1], 0, 1)) . '.' : '');

                // Flutter verwacht: 'id' (niet 'client_id'), 'name' (niet 'display_name'),
                // 'last_session_date' (niet 'last_session_at')
                return [
                    'id'                => $row->client_id,
                    'name'              => $displayName,
                    'total_sessions'    => (int) $row->total_sessions,
                    'total_spent_cents' => (int) ($row->total_spent_cents ?? 0),
                    'last_session_date' => $row->last_session_at,
                    'status'            => $status,
                    // NOOIT: email, phone, address, date_of_birth
                ];
            });

        return response()->json([
            'clients' => $clients,
            'summary' => [
                'total_clients'  => $clients->count(),
                'active_count'   => $clients->where('status', 'active')->count(),
                'risk_count'     => $clients->where('status', 'risk')->count(),
                'inactive_count' => $clients->where('status', 'inactive')->count(),
            ],
        ]);
    }

    /**
     * Upload brand logo
     */
    public function uploadLogo(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $assertion = GymiesPlanManager::assertProPlus((int) $user->id);
        if (!$assertion['allowed']) {
            return response()->json([
                'message' => $assertion['message'],
                'error' => 'upgrade_required',
            ], 403);
        }

        $validated = $request->validate([
            'logo' => 'required|image|max:2048|mimes:jpeg,png,webp',
        ]);

        $path = Storage::disk('public')->putFile(
            "trainer-logos/{$user->id}",
            $validated['logo']
        );

        self::ensureTable();
        $settings = TrainerProPlusSettings::firstOrCreate(['trainer_user_id' => (int) $user->id]);
        $settings->update(['brand_logo_url' => Storage::url($path)]);

        return response()->json([
            'ok' => true,
            'url' => $settings->brand_logo_url,
            'logo_url' => $settings->brand_logo_url,
            'message' => 'Logo uploaded successfully.',
        ]);
    }

    /**
     * Upload brand banner
     */
    public function uploadBanner(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $assertion = GymiesPlanManager::assertProPlus((int) $user->id);
        if (!$assertion['allowed']) {
            return response()->json([
                'message' => $assertion['message'],
                'error' => 'upgrade_required',
            ], 403);
        }

        $validated = $request->validate([
            'banner' => 'required|image|max:4096|mimes:jpeg,png,webp',
        ]);

        $path = Storage::disk('public')->putFile(
            "trainer-banners/{$user->id}",
            $validated['banner']
        );

        self::ensureTable();
        $settings = TrainerProPlusSettings::firstOrCreate(['trainer_user_id' => (int) $user->id]);
        $settings->update(['brand_banner_url' => Storage::url($path)]);

        return response()->json([
            'ok' => true,
            'url' => $settings->brand_banner_url,
            'banner_url' => $settings->brand_banner_url,
            'message' => 'Banner uploaded successfully.',
        ]);
    }

    /**
     * Upload intro video
     */
    public function uploadVideo(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $assertion = GymiesPlanManager::assertProPlus((int) $user->id);
        if (!$assertion['allowed']) {
            return response()->json([
                'message' => $assertion['message'],
                'error' => 'upgrade_required',
            ], 403);
        }

        $validated = $request->validate([
            'video' => 'required|mimes:mp4,webm,ogg|max:102400', // 100MB max
        ]);

        $path = Storage::disk('public')->putFile(
            "trainer-videos/{$user->id}",
            $validated['video']
        );

        self::ensureTable();
        $settings = TrainerProPlusSettings::firstOrCreate(['trainer_user_id' => (int) $user->id]);
        $settings->update(['intro_video_url' => Storage::url($path)]);

        return response()->json([
            'ok' => true,
            'url' => $settings->intro_video_url,
            'video_url' => $settings->intro_video_url,
            'message' => 'Video uploaded successfully.',
        ]);
    }

    /**
     * PUBLIEK endpoint — retourneert trainer widget data voor embed op externe websites.
     * Geen auth vereist. Slug of trainer-ID als route parameter.
     * CORS headers zodat het script van externe domeinen mag laden.
     */
    public function widgetData(Request $request, string $slug): JsonResponse
    {
        self::ensureTable();

        // Zoek trainer op slug of op ID (trainer-{id} formaat)
        $settings = null;
        $trainerId = null;

        if (preg_match('/^trainer-(\d+)$/', $slug, $m)) {
            $trainerId = (int) $m[1];
            $settings = TrainerProPlusSettings::where('trainer_user_id', $trainerId)->first();
        } else {
            $settings = TrainerProPlusSettings::where('custom_slug', $slug)->first();
            $trainerId = $settings?->trainer_user_id;
        }

        if (!$trainerId) {
            return response()->json(['error' => 'Trainer niet gevonden.'], 404)
                ->header('Access-Control-Allow-Origin', '*');
        }

        // Haal publieke trainer data op
        $trainer = DB::table('gymies_users')
            ->where('id', $trainerId)
            ->where('role', 'trainer')
            ->select('id', 'display_name')
            ->first();

        if (!$trainer) {
            return response()->json(['error' => 'Trainer niet gevonden.'], 404)
                ->header('Access-Control-Allow-Origin', '*');
        }

        $profile = DB::table('gymies_trainer_profiles')
            ->where('user_id', $trainerId)
            ->select('specialty', 'bio', 'avatar_url', 'hourly_rate_cents', 'city')
            ->first();

        // Beschikbare pakketten (veilig: tabel kan nog niet bestaan)
        $packages = collect();
        try {
            if (Schema::hasTable('gymies_trainer_packages')) {
                $packages = DB::table('gymies_trainer_packages')
                    ->where('trainer_user_id', $trainerId)
                    ->where('is_active', true)
                    ->select('id', 'name', 'sessions_count', 'price_cents', 'description')
                    ->orderBy('price_cents')
                    ->get();
            }
        } catch (\Throwable $e) { /* graceful degradation */ }

        // Beschikbare slots (veilig)
        $availability = collect();
        try {
            if (Schema::hasTable('gymies_availability')) {
                $availability = DB::table('gymies_availability')
                    ->where('trainer_user_id', $trainerId)
                    ->where('is_active', true)
                    ->select('day_of_week', 'start_time', 'end_time')
                    ->orderBy('day_of_week')
                    ->get();
            }
        } catch (\Throwable $e) { /* graceful degradation */ }

        $appUrl = rtrim(config('gymies.flutter_web_url', env('GYMIES_APP_URL', 'https://gymiesapp.nl')), '/');
        $bookingUrl = $appUrl . '/trainer/' . $trainerId . '/book';

        $data = [
            'trainer' => [
                'name'       => $trainer->display_name,
                'specialty'  => $profile->specialty ?? null,
                'bio'        => $profile->bio ? mb_substr($profile->bio, 0, 200) : null,
                'avatar_url' => $profile->avatar_url ?? null,
                'city'       => $profile->city ?? null,
                'hourly_rate_cents' => $profile->hourly_rate_cents ?? null,
            ],
            'branding' => [
                'brand_color' => $settings?->brand_color ?? '#0B1F3A',
                'logo_url'    => $settings?->brand_logo_url,
                'banner_url'  => $settings?->brand_banner_url,
            ],
            'packages'     => $packages,
            'availability' => $availability,
            'booking_url'  => $bookingUrl,
        ];

        return response()->json($data)
            ->header('Access-Control-Allow-Origin', '*')
            ->header('Access-Control-Allow-Methods', 'GET')
            ->header('Cache-Control', 'public, max-age=300');
    }

    /**
     * Render newsletter HTML template
     */
    private function renderNewsletterHtml(string $body, string $clientName): string
    {
        // XSS-safe: escape alle user-gegenereerde content voordat het in HTML komt
        $safeClientName = htmlspecialchars($clientName, ENT_QUOTES | ENT_HTML5, 'UTF-8');
        $safeBody       = nl2br(htmlspecialchars($body, ENT_QUOTES | ENT_HTML5, 'UTF-8'));

        return <<<HTML
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; line-height: 1.6; color: #333; }
        .container { max-width: 600px; margin: 0 auto; padding: 20px; }
        .header { border-bottom: 2px solid #f0f0f0; padding-bottom: 20px; margin-bottom: 20px; }
        .content { white-space: pre-wrap; word-break: break-word; }
        .footer { margin-top: 30px; padding-top: 20px; border-top: 1px solid #f0f0f0; font-size: 12px; color: #999; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h2>Hallo {$safeClientName}!</h2>
        </div>
        <div class="content">
            {$safeBody}
        </div>
        <div class="footer">
            <p>Dit bericht is van je trainer via Gymies.</p>
            <p><a href="https://gymies.nl">Bezoek Gymies</a></p>
        </div>
    </div>
</body>
</html>
HTML;
    }
}
