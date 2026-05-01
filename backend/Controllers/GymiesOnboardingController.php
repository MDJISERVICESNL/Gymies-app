<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;

final class GymiesOnboardingController extends Controller
{
    private const MOLLIE_API = 'https://api.mollie.com/v2';

    /** State → trainer_user_id in cache; callback is publiek dus geen Bearer — alleen state koppelt trainer. */
    private const MOLLIE_OAUTH_STATE_CACHE_PREFIX = 'gymies_mollie_oauth_state:';

    /** Genoeg marge voor Mollie-pagina + trage redirect; te kort = "state verlopen" terwijl user nog bezig was. */
    private const MOLLIE_OAUTH_STATE_TTL_MINUTES = 30;

    private const REQUIRED_DOCUMENTS = ['kvk_extract', 'id_document', 'certification'];

    /** Optioneel; blokkeert onboarding-stap niet. */
    private const OPTIONAL_DOCUMENTS = ['vog'];

    /**
     * Mollie Client ID — config/gymies.php + .env. Bij config:cache moet config bestaan;
     * anders valt terug op $_ENV (Dotenv laadt .env vóór cache).
     */
    private function mollieClientId(): string
    {
        $id = config('gymies.mollie_client_id');
        if (is_string($id) && trim($id) !== '') {
            return trim($id);
        }
        $id = $_ENV['MOLLIE_CLIENT_ID'] ?? null;
        if (is_string($id) && trim($id) !== '') {
            return trim($id);
        }

        return trim((string) env('MOLLIE_CLIENT_ID', ''));
    }

    private function mollieClientSecret(): string
    {
        $s = config('gymies.mollie_client_secret');
        if (is_string($s) && $s !== '') {
            return $s;
        }
        $s = $_ENV['MOLLIE_CLIENT_SECRET'] ?? null;
        if (is_string($s) && $s !== '') {
            return $s;
        }

        return (string) env('MOLLIE_CLIENT_SECRET', '');
    }

    /**
     * Geeft huidige onboardingstap terug voor de trainer.
     */
    public function onboardingStatus(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers doorlopen onboarding.'], 403);
        }

        $documents = [];
        if (Schema::hasTable('gymies_document_uploads') && Schema::hasColumn('gymies_document_uploads', 'document_category')) {
            $docs = DB::table('gymies_document_uploads')
                ->where('user_id', (int) $user->id)
                ->whereIn('document_category', self::REQUIRED_DOCUMENTS)
                ->get(['document_category', 'verified_at', 'rejected_at', 'rejection_reason', 'created_at']);
            foreach ($docs as $d) {
                $documents[$d->document_category] = [
                    'uploaded' => true,
                    'verified' => $d->verified_at !== null,
                    'rejected' => $d->rejected_at !== null,
                    'rejection_reason' => $d->rejection_reason,
                ];
            }
            // Optionele documenten (VOG): zelfde vorm, niet verplicht voor current_step
            $optionalDocs = DB::table('gymies_document_uploads')
                ->where('user_id', (int) $user->id)
                ->whereIn('document_category', self::OPTIONAL_DOCUMENTS)
                ->get(['document_category', 'verified_at', 'rejected_at', 'rejection_reason', 'created_at']);
            foreach ($optionalDocs as $d) {
                if (isset($documents[$d->document_category])) {
                    continue;
                }
                $documents[$d->document_category] = [
                    'uploaded' => true,
                    'verified' => $d->verified_at !== null,
                    'rejected' => $d->rejected_at !== null,
                    'rejection_reason' => $d->rejection_reason,
                ];
            }
        }

        $mollieStatus = 'not_started';
        $subscriptionPlan = null;
        if (Schema::hasTable('gymies_trainer_profiles')) {
            $profile = DB::table('gymies_trainer_profiles')
                ->where('user_id', (int) $user->id)
                ->first(['mollie_onboarding_status', 'mollie_profile_id', 'subscription_plan']);
            if ($profile) {
                $mollieStatus = $profile->mollie_onboarding_status ?? 'not_started';
                $subscriptionPlan = $profile->subscription_plan;
            }
        }

        $hasSubscription = false;
        if (Schema::hasTable('gymies_subscriptions')) {
            $hasSubscription = DB::table('gymies_subscriptions')
                ->where('trainer_user_id', (int) $user->id)
                ->whereIn('status', ['active', 'trialing', 'past_due'])
                ->exists();
        }

        $allDocsUploaded = true;
        foreach (self::REQUIRED_DOCUMENTS as $cat) {
            if (!isset($documents[$cat]) || !$documents[$cat]['uploaded']) {
                $allDocsUploaded = false;
                break;
            }
        }

        $currentStep = 'documents';
        if ($allDocsUploaded && $mollieStatus === 'not_started') {
            $currentStep = 'mollie_connect';
        } elseif ($mollieStatus === 'completed' && !$hasSubscription) {
            $currentStep = 'select_plan';
        } elseif ($hasSubscription) {
            $currentStep = 'completed';
        }

        return response()->json([
            'current_step' => $currentStep,
            'documents' => $documents,
            'optional_document_categories' => self::OPTIONAL_DOCUMENTS,
            'mollie_onboarding_status' => $mollieStatus,
            'subscription_plan' => $subscriptionPlan,
            'has_active_subscription' => $hasSubscription,
        ]);
    }

    /**
     * Document uploaden (KvK-uittreksel, ID, certificering).
     */
    public function uploadDocument(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $request->validate([
            'document_category' => 'required|string|in:kvk_extract,id_document,certification,insurance,vog',
            'file' => 'required|file|max:10240|mimes:pdf,jpg,jpeg,png',
        ]);

        if (!GymiesSchemaEnsure::documentUploadsTableAndColumns()) {
            return response()->json(['message' => 'Document-systeem niet beschikbaar. Draai migratie alter_gymies_saas_model.sql of create_gymies_tables_if_not_exists.sql.'], 503);
        }

        $category = $request->input('document_category');
        $file = $request->file('file');
        $path = $file->store('gymies/documents/' . $user->id, 'public');

        $existing = DB::table('gymies_document_uploads')
            ->where('user_id', (int) $user->id)
            ->where('document_category', $category)
            ->first();

        $data = [
            'user_id' => (int) $user->id,
            'type' => $this->mapCategoryToType($category),
            'document_category' => $category,
            'file_url' => $path,
            'original_filename' => $file->getClientOriginalName(),
            'mime_type' => $file->getMimeType(),
            'file_size_bytes' => $file->getSize(),
            'verified_at' => null,
            'rejected_at' => null,
            'rejection_reason' => null,
            'created_at' => now(),
        ];

        if ($existing) {
            DB::table('gymies_document_uploads')->where('id', $existing->id)->update($data);
        } else {
            DB::table('gymies_document_uploads')->insert($data);
        }

        return response()->json(['ok' => true, 'message' => ucfirst(str_replace('_', ' ', $category)) . ' geüpload.']);
    }

    /**
     * Na verificatie van ID: bestand verwijderen (AVG — geen kopie bewaren).
     * Roept admin aan na goedkeuring; row blijft met verified_at, file_url wordt leeggemaakt.
     */
    public function purgeIdDocumentAfterVerification(int $trainerUserId): bool
    {
        if (!Schema::hasTable('gymies_document_uploads')) {
            return false;
        }
        $row = DB::table('gymies_document_uploads')
            ->where('user_id', $trainerUserId)
            ->where('document_category', 'id_document')
            ->whereNotNull('verified_at')
            ->first();
        if (!$row || empty($row->file_url)) {
            return false;
        }
        $path = $row->file_url;
        if (Storage::disk('public')->exists($path)) {
            Storage::disk('public')->delete($path);
        }
        $update = [
            'file_url' => '',
        ];
        if (Schema::hasColumn('gymies_document_uploads', 'original_filename')) {
            $update['original_filename'] = null;
        }
        if (Schema::hasColumn('gymies_document_uploads', 'mime_type')) {
            $update['mime_type'] = null;
        }
        if (Schema::hasColumn('gymies_document_uploads', 'file_size_bytes')) {
            $update['file_size_bytes'] = null;
        }
        DB::table('gymies_document_uploads')->where('id', $row->id)->update($update);

        return true;
    }

    /**
     * Start Mollie Connect OAuth flow: geeft redirect URL terug.
     */
    public function startMollieConnect(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen Mollie Connect starten. Log opnieuw in als trainer.'], 403);
        }

        $clientId = $this->mollieClientId();
        if ($clientId === '') {
            // Altijd 422 + JSON — nooit 503/500 zodat de app geen generieke "Serverfout" toont.
            return response()->json([
                'message' => 'Mollie Connect is nog niet geconfigureerd op de server. Vraag de beheerder MOLLIE_CLIENT_ID (en secret) in .env te zetten en php artisan config:clear uit te voeren.',
                'redirect_url' => null,
            ], 422);
        }

        try {
            return $this->startMollieConnectBuildResponse($request, $user, $clientId);
        } catch (\Throwable $e) {
            logger()->error('Gymies Mollie start: onverwachte fout', [
                'trainer_user_id' => $user->id ?? null,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString(),
            ]);

            $response = [
                'message' => 'Mollie Connect starten lukt tijdelijk niet. Probeer het over een paar minuten opnieuw. Blijft het misgaan, controleer de serverlogs.',
                'redirect_url' => null,
            ];
            // In debug modus: toon fout zodat we kunnen diagnosticeren
            if (config('app.debug')) {
                $response['error_detail'] = $e->getMessage();
            }
            return response()->json($response, 422);
        }
    }

    /**
     * Bouwt authorize-URL en persist state; losgehaald zodat startMollieConnect alles in try-catch kan vangen.
     */
    private function startMollieConnectBuildResponse(Request $request, object $user, string $clientId): JsonResponse
    {
        $redirectUri = rtrim((string) config('app.url'), '/') . '/api/gymies/onboarding/mollie-connect/callback';
        $state = bin2hex(random_bytes(16));

        // Callback heeft geen auth: state moet server-side aan trainer hangen (eenmalig, TTL).
        $trainerId = (int) $user->id;
        $expiresAt = now()->addMinutes(self::MOLLIE_OAUTH_STATE_TTL_MINUTES);
        Cache::put(
            self::MOLLIE_OAUTH_STATE_CACHE_PREFIX . $state,
            $trainerId,
            $expiresAt
        );
        // DB is bron voor callback (cache deelt niet tussen php-fpm requests).
        GymiesSchemaEnsure::mollieOauthStatesTable();
        if (Schema::hasTable('gymies_mollie_oauth_states')) {
            try {
                $expiresStr = $expiresAt->format('Y-m-d H:i:s');
                $createdStr = now()->format('Y-m-d H:i:s');
                DB::table('gymies_mollie_oauth_states')->updateOrInsert(
                    ['state' => $state],
                    [
                        'trainer_user_id' => $trainerId,
                        'expires_at' => $expiresStr,
                        'created_at' => $createdStr,
                    ]
                );
                $verify = DB::table('gymies_mollie_oauth_states')->where('state', $state)->first();
                if (!$verify) {
                    logger()->error('Gymies Mollie start: state direct na insert niet terugleesbaar', [
                        'trainer_user_id' => $trainerId,
                        'state_prefix' => substr($state, 0, 8),
                    ]);
                } else {
                    logger()->info('Gymies Mollie start: state opgeslagen', [
                        'trainer_user_id' => $trainerId,
                        'state_prefix' => substr($state, 0, 8),
                        'expires_at' => $verify->expires_at,
                    ]);
                }
            } catch (\Throwable $e) {
                logger()->error('Gymies Mollie start: gymies_mollie_oauth_states insert mislukt', [
                    'trainer_user_id' => $trainerId,
                    'error' => $e->getMessage(),
                ]);
            }
        } else {
            logger()->warning('Gymies Mollie start: tabel gymies_mollie_oauth_states ontbreekt — callback kan state niet terugvinden.');
        }

        DB::table('gymies_users')->where('id', (int) $user->id)->update([
            'updated_at' => now(),
        ]);

        // Sessie timestamp bijwerken (optioneel; gymies_sessions heeft soms geen updated_at)
        if (Schema::hasTable('gymies_sessions') && Schema::hasColumn('gymies_sessions', 'updated_at')) {
            $token = $request->attributes->get('gymies_token');
            if ($token) {
                DB::table('gymies_sessions')
                    ->where('token', $token)
                    ->update(['updated_at' => now()]);
            }
        }

        $authorizeUrl = 'https://my.mollie.com/oauth2/authorize?' . http_build_query([
            'client_id' => $clientId,
            'redirect_uri' => $redirectUri,
            'state' => $state,
            'scope' => 'payments.read payments.write profiles.read profiles.write organizations.read onboarding.read',
            'response_type' => 'code',
            'approval_prompt' => 'force',
        ]);

        // Zorg dat nieuwe trainers een profiel hebben; update anders alleen mollie_onboarding_status
        if (Schema::hasTable('gymies_trainer_profiles') && Schema::hasColumn('gymies_trainer_profiles', 'mollie_onboarding_status')) {
            $exists = DB::table('gymies_trainer_profiles')->where('user_id', (int) $user->id)->exists();
            if (!$exists) {
                $now = now()->format('Y-m-d H:i:s');
                DB::table('gymies_trainer_profiles')->insert([
                    'user_id' => (int) $user->id,
                    'mollie_onboarding_status' => 'pending',
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            } else {
                DB::table('gymies_trainer_profiles')
                    ->where('user_id', (int) $user->id)
                    ->update(['mollie_onboarding_status' => 'pending']);
            }
        }

        return response()->json([
            'redirect_url' => $authorizeUrl,
            'state' => $state,
        ]);
    }

    /**
     * Mollie Connect OAuth callback: wisselt code in voor access token en slaat profiel-ID op.
     */
    public function mollieConnectCallback(Request $request): Response|JsonResponse
    {
        // Mollie stuurt bij afbreken error + error_description (geen code).
        if ($request->filled('error')) {
            $desc = (string) $request->input('error_description', $request->input('error'));

            return response()->json([
                'ok' => false,
                'message' => 'Mollie Connect geannuleerd of geweigerd.',
                'error' => $request->input('error'),
                'error_description' => $desc,
            ], 422);
        }

        $code = $request->input('code');
        $state = $request->input('state');
        if (!$code || !is_string($code)) {
            return response()->json(['message' => 'Geen authorisatiecode ontvangen.'], 422);
        }
        if (!$state || !is_string($state)) {
            return response()->json(['message' => 'Ontbrekende of ongeldige state. Start de koppeling opnieuw vanuit de app.'], 422);
        }
        // Bewaar origineel voor fallback-match (sommige clients encoderen anders).
        $stateRaw = trim((string) $request->input('state'));
        // Mollie geeft state terug zoals verstuurd; trim + één keer decoden tegen dubbel-encoding.
        $state = trim(rawurldecode($stateRaw));
        if (strlen($state) < 16) {
            return response()->json(['message' => 'Ontbrekende of ongeldige state. Start de koppeling opnieuw vanuit de app.'], 422);
        }

        // Trainer koppelen: eerst DB (betrouwbaar over requests), dan cache. State pas WISSEN na
        // geslaagde token exchange — anders bij Mollie 503 is state weg en retry onmogelijk.
        $trainerId = null;
        GymiesSchemaEnsure::mollieOauthStatesTable();
        if (Schema::hasTable('gymies_mollie_oauth_states')) {
            // Expiry in PHP (Carbon) i.p.v. SQL NOW() — voorkomt TZ/session mismatch met expires_at-kolom.
            $row = DB::table('gymies_mollie_oauth_states')
                ->where('state', $state)
                ->first();
            if (!$row && $stateRaw !== $state) {
                $row = DB::table('gymies_mollie_oauth_states')->where('state', $stateRaw)->first();
            }
            if ($row && (int) $row->trainer_user_id > 0) {
                try {
                    $exp = \Carbon\Carbon::parse((string) $row->expires_at);
                    if ($exp->greaterThan(now())) {
                        $trainerId = (int) $row->trainer_user_id;
                    } else {
                        logger()->warning('Gymies Mollie callback: state wel gevonden maar verlopen', [
                            'state_prefix' => substr($state, 0, 8),
                            'expires_at' => $row->expires_at,
                            'now' => now()->toDateTimeString(),
                        ]);
                    }
                } catch (\Throwable $e) {
                    logger()->warning('Gymies Mollie callback: expires_at parse failed', [
                        'expires_at' => $row->expires_at ?? null,
                        'error' => $e->getMessage(),
                    ]);
                }
            }
            if (!$trainerId && Schema::hasTable('gymies_mollie_oauth_states')) {
                $cnt = DB::table('gymies_mollie_oauth_states')->count();
                logger()->warning('Gymies Mollie callback: state niet gekoppeld na DB-check', [
                    'state_prefix' => substr($state, 0, 8),
                    'state_len' => strlen($state),
                    'rows_in_table' => $cnt,
                ]);
            }
        }
        if (!$trainerId || $trainerId <= 0) {
            $fromCache = Cache::get(self::MOLLIE_OAUTH_STATE_CACHE_PREFIX . $state);
            if ($fromCache && (int) $fromCache > 0) {
                $trainerId = (int) $fromCache;
            }
        }
        if (!$trainerId || $trainerId <= 0) {
            logger()->warning('Gymies Mollie callback: state niet gevonden', [
                'state_prefix' => substr($state, 0, 8),
                'has_code' => $code !== null,
                'query_keys' => array_keys($request->query()),
            ]);

            return response()->json([
                'message' => 'State verlopen of ongeldig. Start Mollie Connect opnieuw vanuit de app (binnen ' . self::MOLLIE_OAUTH_STATE_TTL_MINUTES . ' minuten na start). Zorg dat de migratie gymies_mollie_oauth_states is gedraaid als dit blijft gebeuren.',
            ], 422);
        }
        $trainerId = (int) $trainerId;

        $clientId = $this->mollieClientId();
        $clientSecret = $this->mollieClientSecret();

        $tokenResponse = Http::asForm()->timeout(15)->post('https://api.mollie.com/oauth2/tokens', [
            'grant_type' => 'authorization_code',
            'code' => $code,
            'redirect_uri' => rtrim(config('app.url', ''), '/') . '/api/gymies/onboarding/mollie-connect/callback',
            'client_id' => $clientId,
            'client_secret' => $clientSecret,
        ]);

        if (!$tokenResponse->successful()) {
            logger()->warning('Gymies Mollie OAuth token exchange failed', [
                'trainer_user_id' => $trainerId,
                'status' => $tokenResponse->status(),
                'body' => $tokenResponse->body(),
            ]);

            // State niet wissen: bij 503 kan retry metzelfde URL nog slagen zodra Mollie weer up is.
            return response()->json(['message' => 'Mollie OAuth token exchange mislukt.'], 502);
        }

        $tokenData = $tokenResponse->json();
        $accessToken = $tokenData['access_token'] ?? null;

        if (!$accessToken) {
            // Geen token in body: state laten staan voor eventuele retry (zeldzaam).
            return response()->json(['message' => 'Geen access token ontvangen.'], 502);
        }

        // Eenmalig consumeren zodra we een token hebben — voorkomt hergebruik state/code.
        Cache::forget(self::MOLLIE_OAUTH_STATE_CACHE_PREFIX . $state);
        if (Schema::hasTable('gymies_mollie_oauth_states')) {
            DB::table('gymies_mollie_oauth_states')->where('state', $state)->delete();
        }

        // Haal Mollie profiel-ID op
        $profileResponse = Http::withToken($accessToken)->timeout(15)
            ->get(self::MOLLIE_API . '/profiles/me');

        $profileId = $profileResponse->json('id');
        if (!$profileId) {
            $profilesResponse = Http::withToken($accessToken)->timeout(15)
                ->get(self::MOLLIE_API . '/profiles');
            $profileId = $profilesResponse->json('_embedded.profiles.0.id');
        }

        // Trainer komt uit state-cache (callback is publiek, geen Bearer).
        $saved = false;
        if ($profileId && Schema::hasColumn('gymies_trainer_profiles', 'mollie_profile_id')) {
            $updated = DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->update([
                'mollie_profile_id' => $profileId,
                'mollie_onboarding_status' => 'completed',
            ]);
            $saved = $updated > 0;
            if (!$saved) {
                logger()->warning('Gymies Mollie callback: geen profielrij bijgewerkt; trainer moet profiel aanmaken of onboarding doorlopen.', [
                    'trainer_user_id' => $trainerId,
                    'mollie_profile_id' => $profileId,
                ]);
            }
        }

        // 200 ook als profiel niet geüpdatet (token al verbruikt); client toont message + profile_saved.
        $payload = [
            'ok' => (bool) $profileId && $saved,
            'mollie_profile_id' => $profileId,
            'trainer_user_id' => $trainerId,
            'profile_saved' => $saved,
            'message' => $saved && $profileId
                ? 'Mollie account succesvol gekoppeld!'
                : ($profileId
                    ? 'Mollie gekoppeld maar profielrij ontbreekt — maak eerst je trainerprofiel aan via onboarding, daarna opnieuw koppelen.'
                    : 'Geen Mollie profiel-ID ontvangen.'),
        ];

        // Browser-request (Mollie redirect): HTML met redirect terug naar app.
        // Bij popup: navigeer de opener (heeft sessie/token) en sluit popup — voorkomt uitloggen.
        $accept = $request->header('Accept', '');
        if (str_contains($accept, 'text/html')) {
            $appUrl = rtrim((string) config('app.url'), '/');
            $redirectTo = $appUrl . '/trainer/onboarding?mollie_done=1';
            $message = htmlspecialchars($payload['message'] ?? 'Koppeling voltooid.');

            $html = '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Gymies – Mollie</title></head><body style="font-family:sans-serif;max-width:480px;margin:4em auto;padding:1.5em;text-align:center;"><p>' . $message . '</p><p id="msg">U wordt teruggestuurd naar Gymies…</p><p><a href="' . htmlspecialchars($redirectTo) . '">Klik hier als u niet wordt doorgestuurd</a></p><script>
(function(){
  var r="' . addslashes($redirectTo) . '";
  if (window.opener && !window.opener.closed) {
    try { window.opener.location.href=r; } catch(e) {}
    window.close();
    setTimeout(function(){ window.location.href=r; }, 300);
  } else {
    window.location.href=r;
  }
})();
</script></body></html>';

            return response($html, 200, ['Content-Type' => 'text/html; charset=utf-8']);
        }

        return response()->json($payload);
    }

    /**
     * Selecteer abonnement en start SEPA-mandaat flow.
     */
    public function selectPlan(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Unauthorized'], 403);
        }

        $request->validate(['plan_slug' => 'required|string|in:starter,pro,studio']);

        $plan = DB::table('gymies_plans')
            ->where('slug', $request->input('plan_slug'))
            ->where('is_active', 1)
            ->first();

        if (!$plan) {
            return response()->json(['message' => 'Plan niet gevonden.'], 404);
        }

        $existingSub = DB::table('gymies_subscriptions')
            ->where('trainer_user_id', (int) $user->id)
            ->whereIn('status', ['active', 'trialing'])
            ->first();

        if ($existingSub) {
            return response()->json(['message' => 'Je hebt al een actief abonnement.'], 422);
        }

        $subscriptionController = app(GymiesSubscriptionController::class);
        try {
            $result = $subscriptionController->createSubscriptionForTrainer((int) $user->id, (int) $plan->id);
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('selectPlan createSubscriptionForTrainer', ['error' => $e->getMessage()]);
            }
            $result = ['ok' => false, 'error' => 'Serverfout bij abonnement.'];
        }

        if (!$result['ok']) {
            // Plankeuze vastleggen als profiel al bestaat (geen insert zonder verplichte kolommen)
            if (Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                $exists = DB::table('gymies_trainer_profiles')->where('user_id', (int) $user->id)->exists();
                if ($exists) {
                    DB::table('gymies_trainer_profiles')
                        ->where('user_id', (int) $user->id)
                        ->update(['subscription_plan' => $plan->slug, 'updated_at' => now()]);
                }
            }
            return response()->json([
                'ok' => false,
                'message' => $result['error'] ?? 'Abonnement starten lukt nog niet.',
                'plan_slug' => $plan->slug,
                'checkout_url' => $result['checkout_url'] ?? null,
                'wizard_can_continue' => true,
            ], 200);
        }

        return response()->json([
            'ok' => true,
            'subscription_id' => $result['subscription_id'],
            'checkout_url' => $result['checkout_url'] ?? null,
            'trial_or_referral' => $result['trial_or_referral'] ?? false,
            'trial_ends_at' => $result['trial_ends_at'] ?? null,
            'message' => ($result['trial_or_referral'] ?? false)
                ? 'Pro trial of referral actief. Betaal later via Inkomsten.'
                : 'Abonnement ' . $plan->name . ' gestart. Voltooi de betaling.',
        ]);
    }

    private function mapCategoryToType(string $category): string
    {
        return match ($category) {
            'kvk_extract' => 'certificate',
            'id_document' => 'id',
            'certification' => 'certificate',
            'insurance' => 'insurance',
            'vog' => 'certificate',
            default => 'other',
        };
    }
}
