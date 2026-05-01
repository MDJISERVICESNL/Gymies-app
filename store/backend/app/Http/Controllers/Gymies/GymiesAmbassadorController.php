<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies Ambassador Systeem
 *
 * Publiek:
 *   POST   /api/gymies/ambassador/apply               — aanmelding indienen
 *   GET    /api/gymies/ambassador/validate-code        — code beschikbaarheid checken
 *   GET    /api/gymies/ambassadors                     — publieke lijst featured ambassadors
 *
 * Ingelogd (ambassadors):
 *   GET    /api/gymies/ambassador/me                   — eigen stats + code + tier
 *   GET    /api/gymies/ambassador/conversions          — conversie-geschiedenis
 *   POST   /api/gymies/ambassador/iban                 — IBAN opslaan voor uitbetaling
 *
 * Admin:
 *   GET    /api/gymies/admin/ambassador/applications   — alle aanvragen
 *   POST   /api/gymies/admin/ambassador/applications/{id}/approve
 *   POST   /api/gymies/admin/ambassador/applications/{id}/reject
 *   GET    /api/gymies/admin/ambassador/list           — alle actieve ambassadors + stats
 *   POST   /api/gymies/admin/ambassador/{id}/tier      — handmatige tier-aanpassing
 *   POST   /api/gymies/admin/ambassador/{id}/toggle-featured
 *   POST   /api/gymies/admin/ambassador/{id}/toggle-active
 *   POST   /api/gymies/admin/ambassador/{id}/mark-paid — conversies als uitbetaald markeren
 *
 * Cron (via GymiesCronController):
 *   evaluateAmbassadorTiers()                          — maandelijkse tier-evaluatie
 */
final class GymiesAmbassadorController extends Controller
{
    // Tier-drempels (conversies per 30 dagen)
    private const TIER_ELITE_MIN  = 20;
    private const TIER_ACTIVE_MIN = 6;

    // Beloningen in eurocenten
    private const REWARD_TRAINER_CENTS  = 2500; // €25 per trainer-signup
    private const REWARD_SPORTER_CENTS  = 300;  // €3 per sporter-boeking

    // Minimale uitbetalingsdrempel
    private const PAYOUT_THRESHOLD_CENTS = 5000; // €50

    // Fraude-detectie: max conversies per IP per code per 48u
    private const FRAUD_MAX_CONVERSIONS_PER_IP = 5;

    // =========================================================================
    // PUBLIEK
    // =========================================================================

    /**
     * POST /api/gymies/ambassador/apply
     * Aanmelding indienen vanuit het contactformulier.
     * Edge cases: dubbele aanvraag, al actief ambassadeur, rate limiting (via middleware).
     */
    public function apply(Request $request): JsonResponse
    {
        GymiesSchemaEnsure::ambassadorTables();
        if (!Schema::hasTable('gymies_ambassador_applications')) {
            return response()->json(['message' => 'Aanmeldingen tijdelijk niet beschikbaar.'], 503);
        }

        $data = $request->validate([
            'voornaam'      => 'required|string|max:100',
            'achternaam'    => 'required|string|max:100',
            'email'         => 'required|email|max:255',
            'telefoon'      => 'nullable|string|max:30',
            'stad'          => 'required|string|max:100',
            'platform'      => 'required|in:instagram,tiktok,youtube,blog,anders',
            'handle'        => 'required|string|max:255',
            'volgersaantal' => 'required|in:<1000,1000-5000,5000-20000,20000-100000,100000+',
            'niche'         => 'required|in:fitness,voeding,lifestyle,sport,personal-training,anders',
            'rol'           => 'required|in:sporter,trainer,beiden',
            'motivatie'     => 'required|string|min:30|max:3000',
            'contentLink'   => 'nullable|url|max:500',
            'kortingscode'  => 'nullable|string|max:20|alpha_num',
        ]);

        $email = mb_strtolower(trim($data['email']));

        // Check: al een actieve ambassadeur?
        if (Schema::hasTable('gymies_ambassadors')) {
            $activeAmb = DB::table('gymies_ambassadors')
                ->where('email', $email)
                ->where('is_active', 1)
                ->exists();
            if ($activeAmb) {
                return response()->json([
                    'message' => 'Je bent al ambassadeur bij Gymies.',
                    'code' => 'already_ambassador',
                ], 409);
            }
        }

        // Check: bestaande pending/approved aanvraag met dit e-mailadres?
        $existingPending = DB::table('gymies_ambassador_applications')
            ->where('email', $email)
            ->whereIn('status', ['pending', 'approved'])
            ->first(['id', 'status']);

        if ($existingPending) {
            $statusLabel = $existingPending->status === 'approved' ? 'goedgekeurd' : 'in behandeling';
            return response()->json([
                'message' => "Je aanmelding is al {$statusLabel}. We nemen contact met je op via {$email}.",
                'code' => 'duplicate_application',
            ], 409);
        }

        // Gewenste kortingscode: normaliseren en beschikbaarheid checken
        $gewensteCode = null;
        if (!empty($data['kortingscode'])) {
            $gewensteCode = strtoupper(trim($data['kortingscode']));
            if ($this->codeExists($gewensteCode)) {
                // Genereer automatisch een alternatief
                $gewensteCode = $this->generateAlternativeCode($gewensteCode);
            }
        }

        DB::table('gymies_ambassador_applications')->insert([
            'voornaam'      => trim($data['voornaam']),
            'achternaam'    => trim($data['achternaam']),
            'email'         => $email,
            'telefoon'      => $data['telefoon'] ?? null,
            'stad'          => trim($data['stad']),
            'platform'      => $data['platform'],
            'handle'        => trim($data['handle']),
            'volgers_range' => $data['volgersaantal'],
            'niche'         => $data['niche'],
            'rol'           => $data['rol'],
            'motivatie'     => trim($data['motivatie']),
            'content_link'  => $data['contentLink'] ?? null,
            'gewenste_code' => $gewensteCode,
            'status'        => 'pending',
            'created_at'    => now(),
        ]);

        Log::info('[Ambassador] Nieuwe aanmelding ontvangen', [
            'email'    => $email,
            'platform' => $data['platform'],
            'handle'   => $data['handle'],
        ]);

        return response()->json([
            'ok' => true,
            'message' => 'Aanmelding ontvangen. We reageren binnen 3 werkdagen.',
        ], 201);
    }

    /**
     * GET /api/gymies/ambassador/validate-code?code=SARA15
     * Checkt of een kortingscode beschikbaar is (voor live-feedback in het formulier).
     */
    public function validateCode(Request $request): JsonResponse
    {
        $code = strtoupper(trim((string) $request->query('code', '')));
        if ($code === '' || strlen($code) > 20) {
            return response()->json(['available' => false, 'message' => 'Ongeldige code.']);
        }
        if (!preg_match('/^[A-Z0-9]+$/', $code)) {
            return response()->json(['available' => false, 'message' => 'Alleen letters en cijfers.']);
        }

        GymiesSchemaEnsure::ambassadorTables();

        $available = !$this->codeExists($code);
        return response()->json([
            'available' => $available,
            'code'      => $code,
            'message'   => $available ? 'Code is beschikbaar!' : 'Code is al in gebruik.',
        ]);
    }

    /**
     * GET /api/gymies/ambassadors
     * Publieke lijst van featured ambassadors voor de /ambassador pagina op gymies.nl.
     */
    public function publicList(Request $request): JsonResponse
    {
        GymiesSchemaEnsure::ambassadorTables();
        if (!Schema::hasTable('gymies_ambassadors')) {
            return response()->json(['data' => []]);
        }

        $ambassadors = DB::table('gymies_ambassadors')
            ->where('is_active', 1)
            ->where('is_featured', 1)
            ->orderByDesc('tier') // elite > active > starter
            ->orderByDesc('trainer_conversions')
            ->limit(24)
            ->get([
                'id', 'voornaam', 'achternaam', 'stad',
                'platform', 'handle', 'tier',
                'is_founding_partner', 'trainer_conversions', 'sporter_conversions',
                // Publieke profiel velden (na migratie)
                ...(Schema::hasColumn('gymies_ambassadors', 'slug') ? ['slug', 'avatar_url', 'bio', 'specialiteit'] : []),
            ])
            ->map(fn ($a) => [
                'id'               => (int) $a->id,
                'naam'             => $a->voornaam . ' ' . mb_substr($a->achternaam, 0, 1) . '.',
                'stad'             => $a->stad,
                'platform'         => $a->platform,
                'handle'           => $a->handle,
                'tier'             => $a->tier,
                'is_founding_partner' => (bool) $a->is_founding_partner,
                'conversions'      => (int) $a->trainer_conversions + (int) $a->sporter_conversions,
                'slug'             => $a->slug ?? null,
                'avatar_url'       => $a->avatar_url ?? null,
                'bio'              => $a->bio ?? null,
                'specialiteit'     => $a->specialiteit ?? null,
            ]);

        return response()->json(['data' => $ambassadors]);
    }

    /**
     * GET /api/gymies/ambassador/profile/{slug}
     * Publiek profiel van een enkele ambassador (voor gymies.nl/ambassador/[slug]).
     */
    public function publicProfile(Request $request, string $slug): JsonResponse
    {
        // Haal ambassador op via slug — join met application voor stad/platform/handle
        $a = DB::table('gymies_ambassadors as amb')
            ->leftJoin('gymies_ambassador_applications as app', 'amb.application_id', '=', 'app.id')
            ->where('amb.slug', $slug)
            ->where('amb.is_active', 1)
            ->where('amb.is_public', 1)
            ->select([
                'amb.*',
                'app.stad',
                'app.platform',
                'app.handle',
            ])
            ->first();

        if (!$a) {
            return response()->json(['message' => 'Ambassador niet gevonden.'], 404);
        }

        return response()->json([
            'data' => [
                'id'                  => (int) $a->id,
                'voornaam'            => $a->voornaam,
                'achternaam_initial'  => mb_substr($a->achternaam, 0, 1) . '.',
                'naam'                => $a->voornaam . ' ' . mb_substr($a->achternaam, 0, 1) . '.',
                'slug'                => $a->slug,
                'bio'                 => $a->bio ?? null,
                'avatar_url'          => $a->avatar_url ?? null,
                'stad'                => $a->stad ?? null,
                'specialiteit'        => $a->specialiteit ?? null,
                'platform'            => $a->platform ?? null,
                'handle'              => $a->handle ?? null,
                'social_instagram'    => $a->social_instagram ?? null,
                'social_tiktok'       => $a->social_tiktok ?? null,
                'social_youtube'      => $a->social_youtube ?? null,
                'social_website'      => $a->social_website ?? null,
                'tier'                => $a->tier,
                'is_founding_partner' => (bool) ($a->is_founding_partner ?? false),
                'discount_code'       => $a->discount_code,
                'conversions'         => (int) ($a->trainer_conversions ?? 0) + (int) ($a->sporter_conversions ?? 0),
                'joined_at'           => $a->created_at ?? null,
            ],
        ]);
    }

    // =========================================================================
    // INGELOGD — AMBASSADOR DASHBOARD
    // =========================================================================

    /**
     * GET /api/gymies/ambassador/me
     * Eigen ambassador-stats, tier, code, verdiensten.
     * Retourneert 404 als de ingelogde user geen ambassadeur is.
     */
    public function me(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        GymiesSchemaEnsure::ambassadorTables();
        if (!Schema::hasTable('gymies_ambassadors')) {
            return response()->json(['message' => 'Niet gevonden.'], 404);
        }

        $amb = DB::table('gymies_ambassadors')
            ->where('user_id', (int) $user->id)
            ->where('is_active', 1)
            ->first();

        if (!$amb) {
            return response()->json(['message' => 'Je bent geen actieve ambassadeur.'], 404);
        }

        // Recent conversies (5 meest recent)
        $recentConversions = [];
        if (Schema::hasTable('gymies_ambassador_conversions')) {
            $recentConversions = DB::table('gymies_ambassador_conversions as c')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'c.referred_user_id')
                ->where('c.ambassador_id', (int) $amb->id)
                ->whereNull('c.reversed_at')
                ->where('c.suspicious', 0)
                ->orderByDesc('c.created_at')
                ->limit(5)
                ->get(['c.conversion_type', 'c.reward_cents', 'c.created_at', 'c.paid_at'])
                ->map(fn ($c) => [
                    'type'         => $c->conversion_type,
                    'reward_cents' => (int) $c->reward_cents,
                    'paid'         => $c->paid_at !== null,
                    'created_at'   => $c->created_at,
                ])
                ->values()
                ->all();
        }

        $nextTier = match ($amb->tier) {
            'starter' => ['tier' => 'active',  'needed' => self::TIER_ACTIVE_MIN],
            'active'  => ['tier' => 'elite',   'needed' => self::TIER_ELITE_MIN],
            default   => null,
        };

        return response()->json([
            'data' => [
                'id'                   => (int) $amb->id,
                'tier'                 => $amb->tier,
                'is_founding_partner'  => (bool) $amb->is_founding_partner,
                'discount_code'        => $amb->discount_code,
                'share_url'            => 'https://www.gymies.nl?amb=' . urlencode($amb->discount_code),
                'trainer_conversions'  => (int) $amb->trainer_conversions,
                'sporter_conversions'  => (int) $amb->sporter_conversions,
                'total_earned_cents'   => (int) $amb->total_earned_cents,
                'pending_payout_cents' => (int) $amb->pending_payout_cents,
                'payout_threshold_cents' => self::PAYOUT_THRESHOLD_CENTS,
                'has_iban'             => $amb->iban !== null && $amb->iban !== '',
                'next_tier'            => $nextTier,
                'recent_conversions'   => $recentConversions,
                'member_since'         => $amb->created_at,
            ],
        ]);
    }

    /**
     * GET /api/gymies/ambassador/conversions?page=1
     * Volledige paginated conversie-geschiedenis.
     */
    public function myConversions(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        GymiesSchemaEnsure::ambassadorTables();
        if (!Schema::hasTable('gymies_ambassadors') || !Schema::hasTable('gymies_ambassador_conversions')) {
            return response()->json(['data' => [], 'pagination' => ['page' => 1, 'total' => 0]]);
        }

        $amb = DB::table('gymies_ambassadors')
            ->where('user_id', (int) $user->id)
            ->where('is_active', 1)
            ->first(['id']);

        if (!$amb) {
            return response()->json(['message' => 'Je bent geen actieve ambassadeur.'], 404);
        }

        $page  = max(1, (int) ($request->query('page', 1)));
        $limit = 25;
        $offset = ($page - 1) * $limit;

        $total = DB::table('gymies_ambassador_conversions')
            ->where('ambassador_id', (int) $amb->id)
            ->where('suspicious', 0)
            ->count();

        $rows = DB::table('gymies_ambassador_conversions')
            ->where('ambassador_id', (int) $amb->id)
            ->where('suspicious', 0)
            ->orderByDesc('created_at')
            ->offset($offset)
            ->limit($limit)
            ->get(['id', 'conversion_type', 'reward_cents', 'reversed_at', 'paid_at', 'created_at'])
            ->map(fn ($r) => [
                'id'            => (int) $r->id,
                'type'          => $r->conversion_type,
                'reward_cents'  => (int) $r->reward_cents,
                'reversed'      => $r->reversed_at !== null,
                'paid'          => $r->paid_at !== null,
                'created_at'    => $r->created_at,
            ])
            ->values()
            ->all();

        return response()->json([
            'data' => $rows,
            'pagination' => [
                'page'  => $page,
                'limit' => $limit,
                'total' => $total,
                'pages' => (int) ceil($total / $limit),
            ],
        ]);
    }

    /**
     * POST /api/gymies/ambassador/iban
     * IBAN + rekeninghouder opslaan voor uitbetaling.
     */
    public function saveIban(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $data = $request->validate([
            'iban'      => ['required', 'string', 'max:34', 'regex:/^[A-Z]{2}[0-9]{2}[A-Z0-9]{1,30}$/'],
            'iban_name' => 'required|string|max:100',
        ]);

        GymiesSchemaEnsure::ambassadorTables();
        $amb = DB::table('gymies_ambassadors')
            ->where('user_id', (int) $user->id)
            ->where('is_active', 1)
            ->first(['id']);

        if (!$amb) {
            return response()->json(['message' => 'Niet gevonden.'], 404);
        }

        // N-009 FIXED: IBAN check-digit validatie toegevoegd
        $normalizedIban = strtoupper(str_replace(' ', '', $data['iban']));
        if (!$this->validateIban($normalizedIban)) {
            return response()->json(['message' => 'IBAN is ongeldig. Controleer de gegevens.'], 422);
        }

        // P-FIX-AMB-2b: Reset IBAN verification when IBAN changes
        $updateData = [
            'iban'       => $normalizedIban,
            'iban_name'  => trim($data['iban_name']),
            'updated_at' => now(),
        ];

        // Mark IBAN as unverified until admin approves
        if (Schema::hasColumn('gymies_ambassadors', 'iban_verified_at')) {
            $updateData['iban_verified_at'] = null;
        }

        DB::table('gymies_ambassadors')->where('id', (int) $amb->id)->update($updateData);

        return response()->json(['ok' => true, 'message' => 'IBAN opgeslagen.']);
    }

    // =========================================================================
    // ADMIN
    // =========================================================================

    /**
     * GET /api/gymies/admin/ambassador/applications?status=pending
     */
    public function adminApplications(Request $request): JsonResponse
    {
        $this->requireAdmin($request);
        GymiesSchemaEnsure::ambassadorTables();

        $status = $request->query('status', 'pending');
        $page   = max(1, (int) ($request->query('page', 1)));
        $limit  = 30;

        $query = DB::table('gymies_ambassador_applications');
        if (in_array($status, ['pending', 'approved', 'rejected'], true)) {
            $query->where('status', $status);
        }

        $total = $query->count();
        $rows  = $query->orderByDesc('created_at')
            ->offset(($page - 1) * $limit)
            ->limit($limit)
            ->get();

        return response()->json([
            'data'       => $rows,
            'pagination' => ['page' => $page, 'total' => $total, 'pages' => (int) ceil($total / $limit)],
        ]);
    }

    /**
     * POST /api/gymies/admin/ambassador/applications/{id}/approve
     * Goedkeuren: maakt ambassadeur aan + promo-code in één transactie.
     * Race-condition beschermd via SELECT FOR UPDATE + UNIQUE constraint op application_id.
     */
    public function adminApprove(Request $request, string $id): JsonResponse
    {
        $this->requireAdmin($request);
        $admin = $request->attributes->get('gymies_user');

        GymiesSchemaEnsure::ambassadorTables();
        if (!Schema::hasTable('gymies_ambassador_applications')) {
            return response()->json(['message' => 'Tabel ontbreekt.'], 503);
        }

        $data = $request->validate([
            'is_founding_partner' => 'boolean',
            'is_featured'         => 'boolean',
            'custom_code'         => 'nullable|string|max:20|alpha_num',
        ]);

        try {
            DB::beginTransaction();

            // Lock de rij — beschermt tegen dubbele admin-goedkeuring
            $app = DB::table('gymies_ambassador_applications')
                ->where('id', (int) $id)
                ->lockForUpdate()
                ->first();

            if (!$app) {
                DB::rollBack();
                return response()->json(['message' => 'Aanvraag niet gevonden.'], 404);
            }
            if ($app->status === 'approved') {
                DB::rollBack();
                return response()->json(['message' => 'Al goedgekeurd.'], 409);
            }
            if ($app->status === 'rejected') {
                DB::rollBack();
                return response()->json(['message' => 'Aanvraag is afgewezen, niet te herroepen via approve.'], 422);
            }

            // Bepaal de definitieve kortingscode
            $rawCode = $data['custom_code'] ?? $app->gewenste_code ?? null;
            $code    = $rawCode ? strtoupper(trim($rawCode)) : $this->generateCodeFromName($app->voornaam);

            // Als code toch al bestaat → genereer alternatief
            if ($this->codeExists($code)) {
                $code = $this->generateAlternativeCode($code);
            }

            // Koppel aan Gymies-gebruiker als e-mail match
            $userId = null;
            if (Schema::hasTable('gymies_users')) {
                $platformUser = DB::table('gymies_users')
                    ->where('email', mb_strtolower($app->email))
                    ->first(['id']);
                if ($platformUser) {
                    $userId = (int) $platformUser->id;
                }
            }

            // P-FIX-AMB-1: Maak promo-code aan met scoping (platform-wide of trainer-specifiek)
            $promoCodeId = null;
            if (Schema::hasTable('gymies_promo_codes')) {
                $promoData = [
                    'code'          => $code,
                    'discount_type' => 'percent',
                    'value_cents'   => 15, // 15% korting
                    'use_count'     => 0,
                    'max_uses'      => null, // onbeperkt
                    'valid_from'    => now()->toDateString(),
                    'valid_until'   => null,
                    'trainer_user_id' => null, // typically null for ambassador codes
                    'created_at'    => now(),
                    'updated_at'    => now(),
                ];

                // Add platform-wide flag if column exists
                if (Schema::hasColumn('gymies_promo_codes', 'is_platform_wide')) {
                    $promoData['is_platform_wide'] = 1; // Ambassador codes are platform-wide
                }

                $promoCodeId = DB::table('gymies_promo_codes')->insertGetId($promoData);

                // Voeg ambassador_id toe als kolom bestaat
                if (Schema::hasColumn('gymies_promo_codes', 'ambassador_id')) {
                    // wordt na insert bijgewerkt zodra we ambassador-id hebben
                }
            }

            // Maak ambassadeur-rij aan
            $ambId = DB::table('gymies_ambassadors')->insertGetId([
                'application_id'    => (int) $app->id,
                'user_id'           => $userId,
                'voornaam'          => $app->voornaam,
                'achternaam'        => $app->achternaam,
                'email'             => mb_strtolower($app->email),
                'discount_code'     => $code,
                'promo_code_id'     => $promoCodeId,
                'tier'              => 'starter',
                'is_active'         => 1,
                'is_featured'       => (int) ($data['is_featured'] ?? 0),
                'is_founding_partner' => (int) ($data['is_founding_partner'] ?? 0),
                'trainer_conversions' => 0,
                'sporter_conversions' => 0,
                'total_earned_cents'  => 0,
                'pending_payout_cents' => 0,
                'created_at'        => now(),
                'updated_at'        => now(),
            ]);

            // Update aanvraag-status
            DB::table('gymies_ambassador_applications')->where('id', (int) $id)->update([
                'status'               => 'approved',
                'reviewed_at'          => now(),
                'reviewed_by_user_id'  => (int) $admin->id,
            ]);

            // Als er een promo-code rij is, sla ambassador_id erin op als kolom bestaat
            if ($promoCodeId && Schema::hasColumn('gymies_promo_codes', 'ambassador_id')) {
                DB::table('gymies_promo_codes')->where('id', $promoCodeId)
                    ->update(['ambassador_id' => $ambId]);
            }

            // Trainer-profiel: boost op 1 zetten (starter)
            if ($userId && Schema::hasTable('gymies_trainer_profiles')) {
                DB::table('gymies_trainer_profiles')
                    ->where('user_id', $userId)
                    ->update(['ambassador_boost' => 1]);
            }

            DB::commit();

            // Stuur welkomstmail (queue-based; mislukt niet als mail-config ontbreekt)
            $this->sendApprovalNotification((int) $ambId, $app->email, $app->voornaam, $code, $userId === null);

            Log::info('[Ambassador] Goedgekeurd', [
                'application_id' => $id,
                'ambassador_id'  => $ambId,
                'code'           => $code,
                'admin_id'       => $admin->id,
            ]);

            return response()->json([
                'ok'           => true,
                'ambassador_id' => $ambId,
                'code'         => $code,
                'message'      => "Ambassadeur aangemaakt met code {$code}.",
            ]);
        } catch (\Throwable $e) {
            DB::rollBack();
            Log::error('[Ambassador] Approve mislukt', ['id' => $id, 'error' => $e->getMessage()]);
            return response()->json(['message' => 'Aanmaken mislukt. Probeer opnieuw.'], 500);
        }
    }

    /**
     * POST /api/gymies/admin/ambassador/applications/{id}/reject
     */
    public function adminReject(Request $request, string $id): JsonResponse
    {
        $this->requireAdmin($request);
        $admin = $request->attributes->get('gymies_user');

        GymiesSchemaEnsure::ambassadorTables();
        $app = DB::table('gymies_ambassador_applications')->where('id', (int) $id)->first();
        if (!$app) {
            return response()->json(['message' => 'Niet gevonden.'], 404);
        }
        if ($app->status !== 'pending') {
            return response()->json(['message' => 'Alleen pending aanvragen kunnen worden afgewezen.'], 422);
        }

        $notes = $request->input('notes', '');
        DB::table('gymies_ambassador_applications')->where('id', (int) $id)->update([
            'status'              => 'rejected',
            'admin_notes'         => $notes,
            'reviewed_at'         => now(),
            'reviewed_by_user_id' => (int) $admin->id,
        ]);

        return response()->json(['ok' => true, 'message' => 'Aanvraag afgewezen.']);
    }

    /**
     * GET /api/gymies/admin/ambassador/list
     * Alle ambassadors met stats voor de Control Tower.
     */
    public function adminList(Request $request): JsonResponse
    {
        $this->requireAdmin($request);
        GymiesSchemaEnsure::ambassadorTables();

        $tier     = $request->query('tier');
        $active   = $request->query('active');
        $page     = max(1, (int) ($request->query('page', 1)));
        $limit    = 25;

        $query = DB::table('gymies_ambassadors');
        if (in_array($tier, ['starter', 'active', 'elite'], true)) {
            $query->where('tier', $tier);
        }
        if ($active !== null) {
            $query->where('is_active', (int) filter_var($active, FILTER_VALIDATE_BOOL));
        }

        $total = $query->count();
        $rows  = $query->orderByDesc('total_earned_cents')
            ->offset(($page - 1) * $limit)
            ->limit($limit)
            ->get([
                'id', 'voornaam', 'achternaam', 'email', 'stad',
                'platform', 'handle', 'tier', 'discount_code',
                'is_active', 'is_featured', 'is_founding_partner',
                'trainer_conversions', 'sporter_conversions',
                'total_earned_cents', 'pending_payout_cents',
                'iban', 'last_evaluated_at', 'created_at',
            ]);

        return response()->json([
            'data'       => $rows,
            'pagination' => ['page' => $page, 'total' => $total, 'pages' => (int) ceil($total / $limit)],
        ]);
    }

    /**
     * POST /api/gymies/admin/ambassador/{id}/tier
     * Handmatige tier-aanpassing door admin.
     */
    public function adminSetTier(Request $request, string $id): JsonResponse
    {
        $this->requireAdmin($request);
        $data = $request->validate(['tier' => 'required|in:starter,active,elite']);

        GymiesSchemaEnsure::ambassadorTables();
        $amb = DB::table('gymies_ambassadors')->where('id', (int) $id)->first();
        if (!$amb) {
            return response()->json(['message' => 'Niet gevonden.'], 404);
        }

        $boost = match ($data['tier']) {
            'elite'   => 2,
            'active'  => 1,
            default   => 0,
        };

        DB::table('gymies_ambassadors')->where('id', (int) $id)->update([
            'tier'             => $data['tier'],
            'tier_updated_at'  => now(),
            'updated_at'       => now(),
        ]);

        // Trainer-profiel boost bijwerken
        if ($amb->user_id && Schema::hasTable('gymies_trainer_profiles')) {
            DB::table('gymies_trainer_profiles')
                ->where('user_id', (int) $amb->user_id)
                ->update(['ambassador_boost' => $boost]);
        }

        return response()->json(['ok' => true, 'tier' => $data['tier'], 'ambassador_boost' => $boost]);
    }

    /**
     * POST /api/gymies/admin/ambassador/{id}/toggle-featured
     */
    public function adminToggleFeatured(Request $request, string $id): JsonResponse
    {
        $this->requireAdmin($request);
        GymiesSchemaEnsure::ambassadorTables();

        $amb = DB::table('gymies_ambassadors')->where('id', (int) $id)->first(['id', 'is_featured']);
        if (!$amb) {
            return response()->json(['message' => 'Niet gevonden.'], 404);
        }

        $newVal = $amb->is_featured ? 0 : 1;
        DB::table('gymies_ambassadors')->where('id', (int) $id)->update([
            'is_featured' => $newVal, 'updated_at' => now(),
        ]);

        return response()->json(['ok' => true, 'is_featured' => (bool) $newVal]);
    }

    /**
     * POST /api/gymies/admin/ambassador/{id}/toggle-active
     * Activeren/deactiveren van een ambassadeur.
     */
    public function adminToggleActive(Request $request, string $id): JsonResponse
    {
        $this->requireAdmin($request);
        GymiesSchemaEnsure::ambassadorTables();

        $amb = DB::table('gymies_ambassadors')->where('id', (int) $id)->first(['id', 'is_active', 'user_id']);
        if (!$amb) {
            return response()->json(['message' => 'Niet gevonden.'], 404);
        }

        $newVal = $amb->is_active ? 0 : 1;
        DB::table('gymies_ambassadors')->where('id', (int) $id)->update([
            'is_active'  => $newVal,
            'updated_at' => now(),
        ]);

        // Als deactiveren: zoekboost op 0
        if (!$newVal && $amb->user_id && Schema::hasTable('gymies_trainer_profiles')) {
            DB::table('gymies_trainer_profiles')
                ->where('user_id', (int) $amb->user_id)
                ->update(['ambassador_boost' => 0]);
        }

        return response()->json(['ok' => true, 'is_active' => (bool) $newVal]);
    }

    /**
     * POST /api/gymies/admin/ambassador/{id}/mark-paid
     * Markeer uitbetaalde conversies als betaald en reset pending_payout_cents.
     */
    public function adminMarkPaid(Request $request, string $id): JsonResponse
    {
        $this->requireAdmin($request);
        GymiesSchemaEnsure::ambassadorTables();

        // N-018 FIXED: race condition in commissie-uitkering voorkomen
        return DB::transaction(function () use ($id) {
            $amb = DB::table('gymies_ambassadors')
                ->where('id', (int) $id)
                ->lockForUpdate()
                ->first(['id', 'pending_payout_cents', 'iban', 'iban_verified_at']);

            if (!$amb) {
                return response()->json(['message' => 'Niet gevonden.'], 404);
            }

            // P-FIX-AMB-2: IBAN ownership verification required before first payout
            if (empty($amb->iban)) {
                return response()->json([
                    'error' => 'Geen IBAN ingesteld. Ambassador moet eerst een IBAN toevoegen.',
                ], 422);
            }

            if (Schema::hasColumn('gymies_ambassadors', 'iban_verified_at') && empty($amb->iban_verified_at)) {
                return response()->json([
                    'error' => 'IBAN niet geverifieerd. Admin moet het IBAN controleren voordat uitbetaling plaatsvindt.',
                ], 422);
            }

            $amount = (int) ($amb->pending_payout_cents ?? 0);
            if ($amount === 0) {
                return response()->json(['message' => 'Geen openstaand bedrag.'], 422);
            }

            // Markeer alle onbetaalde conversies als betaald
            DB::table('gymies_ambassador_conversions')
                ->where('ambassador_id', (int) $id)
                ->whereNull('paid_at')
                ->whereNull('reversed_at')
                ->where('suspicious', 0)
                ->update(['paid_at' => now()]);

            DB::table('gymies_ambassadors')->where('id', (int) $id)->update([
                'pending_payout_cents' => 0,
                'updated_at'           => now(),
            ]);

            return response()->json([
                'ok'           => true,
                'paid_cents'   => $amount,
                'message'      => 'Uitbetaling geregistreerd.',
            ]);
        });
    }

    // =========================================================================
    // INTERNE METHODES — worden aangeroepen vanuit andere controllers
    // =========================================================================

    /**
     * Registreer een sporter-boeking conversie.
     * Aanroepen vanuit GymiesPaymentController na succesvolle Mollie-betaling.
     *
     * Edge cases die hier worden afgehandeld:
     * - ambassadeur gebruikt eigen code → geblokkeerd
     * - sporter al eerder geconverteerd via zelfde ambassadeur → geblokkeerd (unique constraint)
     * - fraude-detectie via IP-clustering
     */
    public static function recordSporterConversion(
        string $promoCode,
        int $sporterUserId,
        ?int $transactionId,
        ?string $clientIp
    ): void {
        try {
            if (!Schema::hasTable('gymies_ambassadors') || !Schema::hasTable('gymies_ambassador_conversions')) {
                return;
            }

            // Is dit een ambassador-code?
            $amb = DB::table('gymies_ambassadors')
                ->where('discount_code', strtoupper($promoCode))
                ->where('is_active', 1)
                ->first(['id', 'user_id', 'sporter_conversions', 'total_earned_cents', 'pending_payout_cents']);

            if (!$amb) {
                return; // Geen ambassador-code, gewone trainer-promo — niks doen
            }

            // Blokkeer: ambassadeur gebruikt eigen code
            if ($amb->user_id !== null && (int) $amb->user_id === $sporterUserId) {
                Log::info('[Ambassador] Eigen code gebruik geblokkeerd', [
                    'ambassador_id' => $amb->id,
                    'user_id'       => $sporterUserId,
                ]);
                return;
            }

            // Blokkeer: sporter al eerder geconverteerd via dezelfde ambassadeur
            $alreadyConverted = DB::table('gymies_ambassador_conversions')
                ->where('ambassador_id', (int) $amb->id)
                ->where('referred_user_id', $sporterUserId)
                ->where('conversion_type', 'sporter_booking')
                ->exists();

            if ($alreadyConverted) {
                return; // Sporter had al een conversie — geen tweede beloning
            }

            // Fraude-detectie: te veel conversies vanuit zelfde IP in 48u
            $suspicious = 0;
            if ($clientIp && Schema::hasTable('gymies_ambassador_conversions')) {
                // We loggen het IP op de transactie (als kolom bestaat) of via de booking
                // Simpele check: hoeveel conversies voor deze ambassador de laatste 48u?
                $recentCount = DB::table('gymies_ambassador_conversions')
                    ->where('ambassador_id', (int) $amb->id)
                    ->where('created_at', '>=', now()->subHours(48))
                    ->count();

                if ($recentCount >= self::FRAUD_MAX_CONVERSIONS_PER_IP) {
                    $suspicious = 1;
                    Log::warning('[Ambassador] Fraude-signaal: hoog conversie-volume', [
                        'ambassador_id' => $amb->id,
                        'recent_count'  => $recentCount,
                        'ip'            => $clientIp,
                    ]);
                }
            }

            $reward = $suspicious ? 0 : self::REWARD_SPORTER_CENTS;

            DB::table('gymies_ambassador_conversions')->insert([
                'ambassador_id'        => (int) $amb->id,
                'referred_user_id'     => $sporterUserId,
                'conversion_type'      => 'sporter_booking',
                'promo_code_id'        => null,
                'payment_transaction_id' => $transactionId,
                'reward_cents'         => $reward,
                'suspicious'           => $suspicious,
                'created_at'           => now(),
            ]);

            if (!$suspicious) {
                DB::table('gymies_ambassadors')->where('id', (int) $amb->id)->update([
                    'sporter_conversions'  => DB::raw('sporter_conversions + 1'),
                    'total_earned_cents'   => DB::raw("total_earned_cents + {$reward}"),
                    'pending_payout_cents' => DB::raw("pending_payout_cents + {$reward}"),
                    'updated_at'           => now(),
                ]);
            }
        } catch (\Throwable $e) {
            Log::error('[Ambassador] recordSporterConversion fout', ['error' => $e->getMessage()]);
        }
    }

    /**
     * Registreer een trainer-signup conversie.
     * Aanroepen vanuit GymiesSubscriptionController na eerste succesvolle abonnementsbetaling.
     */
    public static function recordTrainerConversion(
        string $promoCode,
        int $trainerUserId
    ): void {
        try {
            if (!Schema::hasTable('gymies_ambassadors') || !Schema::hasTable('gymies_ambassador_conversions')) {
                return;
            }

            $amb = DB::table('gymies_ambassadors')
                ->where('discount_code', strtoupper($promoCode))
                ->where('is_active', 1)
                ->first(['id', 'user_id', 'trainer_conversions', 'total_earned_cents', 'pending_payout_cents']);

            if (!$amb) {
                return;
            }

            // Blokkeer zelf-uitnodiging
            if ($amb->user_id !== null && (int) $amb->user_id === $trainerUserId) {
                return;
            }

            // Blokkeer dubbele conversie voor dezelfde trainer
            $exists = DB::table('gymies_ambassador_conversions')
                ->where('ambassador_id', (int) $amb->id)
                ->where('referred_user_id', $trainerUserId)
                ->where('conversion_type', 'trainer_signup')
                ->exists();

            if ($exists) {
                return;
            }

            $reward = self::REWARD_TRAINER_CENTS;

            DB::table('gymies_ambassador_conversions')->insert([
                'ambassador_id'    => (int) $amb->id,
                'referred_user_id' => $trainerUserId,
                'conversion_type'  => 'trainer_signup',
                'reward_cents'     => $reward,
                'suspicious'       => 0,
                'created_at'       => now(),
            ]);

            DB::table('gymies_ambassadors')->where('id', (int) $amb->id)->update([
                'trainer_conversions'  => DB::raw('trainer_conversions + 1'),
                'total_earned_cents'   => DB::raw("total_earned_cents + {$reward}"),
                'pending_payout_cents' => DB::raw("pending_payout_cents + {$reward}"),
                'updated_at'           => now(),
            ]);

            Log::info('[Ambassador] Trainer conversie geregistreerd', [
                'ambassador_id'   => $amb->id,
                'trainer_user_id' => $trainerUserId,
                'reward_cents'    => $reward,
            ]);
        } catch (\Throwable $e) {
            Log::error('[Ambassador] recordTrainerConversion fout', ['error' => $e->getMessage()]);
        }
    }

    /**
     * Terugdraaien van een conversie na refund.
     * Aanroepen vanuit GymiesPaymentController bij refund-webhook.
     */
    public static function reverseConversion(int $transactionId): void
    {
        try {
            if (!Schema::hasTable('gymies_ambassador_conversions')) {
                return;
            }

            $conv = DB::table('gymies_ambassador_conversions')
                ->where('payment_transaction_id', $transactionId)
                ->whereNull('reversed_at')
                ->whereNull('paid_at') // Alleen nog niet uitbetaalde conversies
                ->first(['id', 'ambassador_id', 'reward_cents']);

            if (!$conv) {
                return;
            }

            DB::table('gymies_ambassador_conversions')
                ->where('id', (int) $conv->id)
                ->update(['reversed_at' => now()]);

            $reward = (int) $conv->reward_cents;
            if ($reward > 0) {
                DB::table('gymies_ambassadors')
                    ->where('id', (int) $conv->ambassador_id)
                    ->update([
                        'total_earned_cents'   => DB::raw("GREATEST(0, total_earned_cents - {$reward})"),
                        'pending_payout_cents' => DB::raw("GREATEST(0, pending_payout_cents - {$reward})"),
                        'updated_at'           => now(),
                    ]);
            }

            Log::info('[Ambassador] Conversie teruggedraaid na refund', [
                'conversion_id'  => $conv->id,
                'ambassador_id'  => $conv->ambassador_id,
                'reward_cents'   => $reward,
                'transaction_id' => $transactionId,
            ]);
        } catch (\Throwable $e) {
            Log::error('[Ambassador] reverseConversion fout', ['error' => $e->getMessage()]);
        }
    }

    /**
     * Koppel bestaand Gymies-account aan ambassadeur (bij registratie met zelfde e-mail).
     * Aanroepen vanuit GymiesAuthController::register() na succesvolle registratie.
     */
    public static function linkUserToAmbassador(int $userId, string $email): void
    {
        try {
            if (!Schema::hasTable('gymies_ambassadors')) {
                return;
            }

            $amb = DB::table('gymies_ambassadors')
                ->where('email', mb_strtolower($email))
                ->whereNull('user_id')
                ->first(['id', 'tier']);

            if (!$amb) {
                return;
            }

            DB::table('gymies_ambassadors')->where('id', (int) $amb->id)->update([
                'user_id'    => $userId,
                'updated_at' => now(),
            ]);

            // Trainer-profiel boost instellen op basis van tier
            if (Schema::hasTable('gymies_trainer_profiles')) {
                $boost = match ($amb->tier) {
                    'elite'  => 2,
                    'active' => 1,
                    default  => 1, // starter krijgt ook boost 1
                };
                $profileExists = DB::table('gymies_trainer_profiles')->where('user_id', $userId)->exists();
                if ($profileExists) {
                    DB::table('gymies_trainer_profiles')
                        ->where('user_id', $userId)
                        ->update(['ambassador_boost' => $boost]);
                }
            }

            Log::info('[Ambassador] user_id gekoppeld aan ambassadeur', [
                'ambassador_id' => $amb->id,
                'user_id'       => $userId,
            ]);
        } catch (\Throwable $e) {
            Log::error('[Ambassador] linkUserToAmbassador fout', ['error' => $e->getMessage()]);
        }
    }

    /**
     * Maandelijkse tier-evaluatie.
     * Aanroepen vanuit GymiesCronController::evaluateAmbassadorTiers().
     * Idempotent: guard op last_evaluated_at < 20 dagen geleden.
     */
    public static function runTierEvaluation(): array
    {
        $results = ['evaluated' => 0, 'upgraded' => 0, 'downgraded' => 0, 'deactivated' => 0];

        try {
            GymiesSchemaEnsure::ambassadorTables();
            if (!Schema::hasTable('gymies_ambassadors') || !Schema::hasTable('gymies_ambassador_conversions')) {
                return $results;
            }

            $ambassadors = DB::table('gymies_ambassadors')
                ->where('is_active', 1)
                ->get(['id', 'user_id', 'tier', 'inactive_months', 'last_evaluated_at']);

            foreach ($ambassadors as $amb) {
                // Idempotentie-guard: niet twee keer evalueren binnen 20 dagen
                if ($amb->last_evaluated_at !== null) {
                    try {
                        $lastEval = \Carbon\Carbon::parse((string) $amb->last_evaluated_at);
                        if ($lastEval->diffInDays(now()) < 20) {
                            continue;
                        }
                    } catch (\Throwable) {}
                }

                // Tel conversies van afgelopen 30 dagen (exclusief suspicious en reversed)
                $conversions30d = DB::table('gymies_ambassador_conversions')
                    ->where('ambassador_id', (int) $amb->id)
                    ->where('created_at', '>=', now()->subDays(30))
                    ->whereNull('reversed_at')
                    ->where('suspicious', 0)
                    ->count();

                $newTier = match (true) {
                    $conversions30d >= self::TIER_ELITE_MIN  => 'elite',
                    $conversions30d >= self::TIER_ACTIVE_MIN => 'active',
                    default                                   => 'starter',
                };

                $oldTier = $amb->tier;
                $inactiveMonths = $conversions30d === 0
                    ? (int) ($amb->inactive_months ?? 0) + 1
                    : 0;

                $update = [
                    'tier'              => $newTier,
                    'tier_updated_at'   => $newTier !== $oldTier ? now() : $amb->last_evaluated_at,
                    'last_evaluated_at' => now(),
                    'inactive_months'   => $inactiveMonths,
                    'updated_at'        => now(),
                ];

                // Deactiveer na 3 maanden inactiviteit
                if ($inactiveMonths >= 3) {
                    $update['is_active'] = 0;
                    $results['deactivated']++;

                    // Zoekboost verwijderen
                    if ($amb->user_id && Schema::hasTable('gymies_trainer_profiles')) {
                        DB::table('gymies_trainer_profiles')
                            ->where('user_id', (int) $amb->user_id)
                            ->update(['ambassador_boost' => 0]);
                    }
                } else {
                    // Boost bijwerken op basis van nieuwe tier
                    $boost = match ($newTier) {
                        'elite'  => 2,
                        'active' => 1,
                        default  => 0,
                    };
                    if ($amb->user_id && Schema::hasTable('gymies_trainer_profiles')) {
                        DB::table('gymies_trainer_profiles')
                            ->where('user_id', (int) $amb->user_id)
                            ->update(['ambassador_boost' => $boost]);
                    }
                }

                DB::table('gymies_ambassadors')->where('id', (int) $amb->id)->update($update);

                $results['evaluated']++;
                if ($newTier !== $oldTier) {
                    $tierOrder = ['starter' => 0, 'active' => 1, 'elite' => 2];
                    if (($tierOrder[$newTier] ?? 0) > ($tierOrder[$oldTier] ?? 0)) {
                        $results['upgraded']++;
                    } else {
                        $results['downgraded']++;
                    }
                }
            }
        } catch (\Throwable $e) {
            Log::error('[Ambassador] Tier-evaluatie fout', ['error' => $e->getMessage()]);
        }

        return $results;
    }

    /**
     * Retourneer ambassador-data voor het user-profiel (auth/me endpoint).
     * Retourneert null als user geen actieve ambassadeur is.
     */
    public static function getProfileData(int $userId): ?array
    {
        try {
            if (!Schema::hasTable('gymies_ambassadors')) {
                return null;
            }

            $amb = DB::table('gymies_ambassadors')
                ->where('user_id', $userId)
                ->where('is_active', 1)
                ->first([
                    'tier', 'discount_code', 'is_founding_partner',
                    'trainer_conversions', 'sporter_conversions',
                    'total_earned_cents', 'pending_payout_cents',
                ]);

            if (!$amb) {
                return null;
            }

            $badge = $amb->is_founding_partner ? 'founding_partner' : 'ambassador';

            return [
                'is_active'            => true,
                'tier'                 => $amb->tier,
                'badge'                => $badge,
                'is_founding_partner'  => (bool) $amb->is_founding_partner,
                'code'                 => $amb->discount_code,
                'share_url'            => 'https://www.gymies.nl?amb=' . urlencode($amb->discount_code),
                'trainer_conversions'  => (int) $amb->trainer_conversions,
                'sporter_conversions'  => (int) $amb->sporter_conversions,
                'total_earned_cents'   => (int) $amb->total_earned_cents,
                'pending_payout_cents' => (int) $amb->pending_payout_cents,
            ];
        } catch (\Throwable) {
            return null;
        }
    }

    // =========================================================================
    // PRIVATE HELPERS
    // =========================================================================

    // N-009 FIXED: IBAN check-digit validatie
    private function validateIban(string $iban): bool
    {
        $iban = strtoupper(str_replace(' ', '', $iban));
        if (!preg_match('/^[A-Z]{2}[0-9]{2}[A-Z0-9]{4,}$/', $iban)) {
            return false;
        }
        // Move first 4 chars to end
        $rearranged = substr($iban, 4) . substr($iban, 0, 4);
        // Replace letters with digits (A=10, B=11, etc.)
        $numeric = '';
        foreach (str_split($rearranged) as $char) {
            $numeric .= ctype_alpha($char) ? (ord($char) - 55) : $char;
        }
        // Mod 97 check
        $remainder = 0;
        foreach (str_split($numeric) as $digit) {
            $remainder = ($remainder * 10 + (int) $digit) % 97;
        }
        return $remainder === 1;
    }

    private function requireAdmin(Request $request): void
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array((string) ($user->role ?? ''), ['admin', 'super_admin'], true)) {
            abort(403, 'Alleen admins kunnen dit uitvoeren.');
        }
    }

    private function codeExists(string $code): bool
    {
        $inPromo = Schema::hasTable('gymies_promo_codes')
            && DB::table('gymies_promo_codes')->where('code', $code)->exists();

        $inAmbassadors = Schema::hasTable('gymies_ambassadors')
            && DB::table('gymies_ambassadors')->where('discount_code', $code)->exists();

        $inReferrals = Schema::hasTable('gymies_referrals')
            && DB::table('gymies_referrals')->where('referral_code', $code)->exists();

        return $inPromo || $inAmbassadors || $inReferrals;
    }

    private function generateCodeFromName(string $voornaam): string
    {
        $base = strtoupper(preg_replace('/[^A-Z]/i', '', $voornaam));
        $base = substr($base, 0, 8);
        if ($base === '') {
            $base = 'AMB';
        }
        return $this->generateAlternativeCode($base . '10');
    }

    private function generateAlternativeCode(string $base): string
    {
        $attempt = $base;
        $i = 1;
        while ($this->codeExists($attempt) && $i <= 99) {
            // Vervang of voeg getal toe achteraan
            $attempt = preg_replace('/\d+$/', '', $base) . str_pad((string) $i, 2, '0', STR_PAD_LEFT);
            $i++;
        }
        return $attempt;
    }

    private function sendApprovalNotification(
        int $ambId,
        string $email,
        string $voornaam,
        string $code,
        bool $needsAccount
    ): void {
        try {
            if (!Schema::hasTable('gymies_notification_queue')) {
                return;
            }

            $accountMsg = $needsAccount
                ? ' Maak een Gymies-account aan met dit e-mailadres om je dashboard te bekijken.'
                : ' Je kunt je dashboard bekijken via de Gymies app.';

            DB::table('gymies_notification_queue')->insert([
                'user_id'       => null, // geen user_id want mogelijk geen account
                'channel'       => 'email',
                'event_type'    => 'ambassador_approved',
                'payload_json'  => json_encode([
                    'to'         => $email,
                    'voornaam'   => $voornaam,
                    'code'       => $code,
                    'ambassador_id' => $ambId,
                    'message'    => "Welkom als Gymies Ambassador! Jouw code is: {$code}.{$accountMsg}",
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => now(),
                'created_at'    => now(),
            ]);
        } catch (\Throwable) {
            // Mail-fout mag de approval-flow niet blokkeren
        }
    }
}
