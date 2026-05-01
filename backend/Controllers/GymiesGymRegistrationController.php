<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Services\GymiesPasswordValidator;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use App\Helpers\GymiesMailTemplates;
use App\Helpers\GymiesNotificationEmail;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

/**
 * Gymies API: Gym zelfservice registratie en demo-aanvragen.
 *
 * Publieke endpoints:
 *   POST gym/register       — Gym eigenaar maakt account + organisatie aan
 *   POST gym/request-demo   — Gym vraagt vrijblijvende demo aan
 *
 * Beveiligde endpoints:
 *   POST gym/onboarding     — Na registratie: locatie, logo, eerste trainer invite
 *
 * Tabellen: gymies_users, gymies_sessions, gymies_organisations,
 *           gymies_organisation_members, gymies_gym_demo_requests
 *
 * Extends GymiesGymController for access to requireGymMember() helper.
 */
final class GymiesGymRegistrationController extends GymiesGymController
{
    private const SESSION_TTL_DAYS = 14;

    // ─── Publiek: Gym registratie (GEBLOKKEERD — alleen via goedkeuring) ────

    /**
     * POST gym/register
     *
     * DEPRECATED: Directe registratie is uitgeschakeld.
     * Gyms moeten eerst een demo aanvragen, worden beoordeeld door het team,
     * en ontvangen bij goedkeuring een persoonlijke registratielink.
     *
     * Gebruik POST gym/request-demo om een aanvraag in te dienen.
     * Gebruik POST gym/register-with-token na goedkeuring.
     *
     * Feature flag: gym_direct_register_enabled in gymies_system_settings.
     * Standaard: uitgeschakeld.
     */
    public function register(Request $request): JsonResponse
    {
        // Feature flag check: alleen als expliciet ingeschakeld
        $directRegisterEnabled = false;
        if (Schema::hasTable('gymies_system_settings')) {
            $setting = DB::table('gymies_system_settings')
                ->where('setting_key', 'gym_direct_register_enabled')
                ->first();
            if ($setting && in_array(strtolower((string) $setting->setting_value), ['1', 'true', 'yes'], true)) {
                $directRegisterEnabled = true;
            }
        }

        if (!$directRegisterEnabled) {
            return response()->json([
                'message' => 'Directe registratie is niet beschikbaar. Vraag een demo aan via onze website — na goedkeuring ontvangt u een persoonlijke registratielink.',
                'action' => 'request_demo',
                'demo_url' => '/voor-gyms',
            ], 403);
        }

        // ─── Validatie ───────────────────────────────────────────────────────
        $data = $request->validate([
            'gym_name'            => 'required|string|min:2|max:255',
            'contact_name'        => 'required|string|min:2|max:255',
            'email'               => 'required|email|max:255',
            'password'            => 'required|string|min:12|max:128',
            'phone'               => 'nullable|string|max:32',
            'city'                => 'nullable|string|max:128',
            'estimated_trainers'  => 'nullable|integer|min:1|max:500',
            'website_url'         => 'nullable|url|max:512',
        ]);

        $email = mb_strtolower(trim($data['email']));

        // Wachtwoord kwaliteitscheck
        $pwResult = GymiesPasswordValidator::validate($data['password']);
        if (!$pwResult->passes()) {
            throw ValidationException::withMessages(['password' => $pwResult->errors()]);
        }

        // E-mail uniek?
        if (DB::table('gymies_users')->where('email', $email)->exists()) {
            throw ValidationException::withMessages([
                'email' => ['Er bestaat al een account met dit e-mailadres. Log in of gebruik een ander adres.'],
            ]);
        }

        // Gym naam al in gebruik? (zachte check, geen blokkade)
        $existingOrg = DB::table('gymies_organisations')
            ->whereRaw('LOWER(name) = ?', [mb_strtolower(trim($data['gym_name']))])
            ->where('status', 'active')
            ->exists();

        // ─── Transactie: user + organisatie + member + sessie ────────────────
        $result = DB::transaction(function () use ($data, $email, $existingOrg) {
            $now = now();

            // 1. Gebruiker aanmaken (role: klant — gym-owners zijn geen trainers)
            $userInsert = [
                'email'         => $email,
                'password_hash' => Hash::make($data['password']),
                'role'          => 'klant',
                'display_name'  => trim($data['contact_name']),
                'phone'         => $data['phone'] ?? null,
                'created_at'    => $now,
                'updated_at'    => $now,
            ];
            if (Schema::hasColumn('gymies_users', 'email_verified_at')) {
                $userInsert['email_verified_at'] = null;
            }
            $userId = DB::table('gymies_users')->insertGetId($userInsert);

            // 2. Organisatie aanmaken
            $orgInsert = [
                'name'             => trim($data['gym_name']),
                'type'             => 'gym',
                'status'           => 'active',
                'contact_email'    => $email,
                'payout_frequency' => 'weekly',
                'payout_minimum_cents' => 0,
                'created_at'       => $now,
                'updated_at'       => $now,
            ];
            $orgId = DB::table('gymies_organisations')->insertGetId($orgInsert);

            // 3. Owner-member koppeling
            DB::table('gymies_organisation_members')->insert([
                'organisation_id' => $orgId,
                'user_id'         => $userId,
                'role'            => 'owner',
                'status'          => 'active',
                'invited_at'      => $now,
                'joined_at'       => $now,
                'created_at'      => $now,
                'updated_at'      => $now,
            ]);

            // 4. Sessie token genereren (zelfde flow als GymiesAuthController)
            $token = bin2hex(random_bytes(32)); // 64 hex chars
            $sessionInsert = [
                'user_id'    => $userId,
                'token'      => $token,
                'expires_at' => $now->copy()->addDays(self::SESSION_TTL_DAYS),
                'created_at' => $now,
                'updated_at' => $now,
            ];
            if (Schema::hasColumn('gymies_sessions', 'user_agent')) {
                $sessionInsert['user_agent'] = mb_substr((string) request()->userAgent(), 0, 255);
            }
            if (Schema::hasColumn('gymies_sessions', 'ip_address')) {
                $sessionInsert['ip_address'] = request()->ip();
            }
            DB::table('gymies_sessions')->insert($sessionInsert);

            // 5. E-mail verificatiecode versturen (als tabel bestaat)
            $verificationCode = null;
            if (Schema::hasTable('gymies_email_verification_codes')) {
                $verificationCode = str_pad((string) random_int(100000, 999999), 6, '0', STR_PAD_LEFT);
                DB::table('gymies_email_verification_codes')->insert([
                    'user_id'    => $userId,
                    'code'       => $verificationCode,
                    'expires_at' => $now->copy()->addHours(24),
                    'created_at' => $now,
                ]);
            }

            // 6. Metadata opslaan (stad, geschat aantal trainers, website)
            if (Schema::hasTable('gymies_gym_demo_requests')) {
                // Optioneel: registratie ook loggen als converted demo request
                // voor analytics (hoeveel directe registraties vs demo-aanvragen)
            }

            return [
                'user_id'           => $userId,
                'organisation_id'   => $orgId,
                'token'             => $token,
                'verification_code' => $verificationCode,
                'existing_name'     => $existingOrg,
            ];
        });

        // Logging
        Log::channel('single')->info('GymRegistration: nieuwe gym aangemeld', [
            'user_id'         => $result['user_id'],
            'organisation_id' => $result['organisation_id'],
            'gym_name'        => $data['gym_name'],
            'city'            => $data['city'] ?? null,
        ]);

        // Welkomstmail versturen naar gym-eigenaar
        try {
            $appName = GymiesNotificationEmail::mailBrandName();
            $baseUrl = GymiesNotificationEmail::mailPublicBaseUrl();
            [$subject, $text, $html] = GymiesMailTemplates::gymWelkom(
                trim($data['contact_name']),
                trim($data['gym_name']),
                $appName,
                $baseUrl,
            );
            GymiesNotificationEmail::send($email, $subject, $text, $html);
        } catch (\Throwable $e) {
            // Mail falen mag registratie niet blokkeren
            Log::channel('single')->warning('GymRegistration: welkomstmail mislukt', [
                'email' => $email,
                'error' => $e->getMessage(),
            ]);
        }

        // E-mail verificatiemail versturen (als code is aangemaakt)
        if (!empty($result['verification_code'])) {
            try {
                $appName = $appName ?? GymiesNotificationEmail::mailBrandName();
                $baseUrl = $baseUrl ?? GymiesNotificationEmail::mailPublicBaseUrl();

                // Magic token voor 1-klik verificatie (zelfde als sessie-token)
                $magicToken = $result['token'];

                [$vSubject, $vText, $vHtml] = GymiesMailTemplates::verificatie(
                    trim($data['contact_name']),
                    $result['verification_code'],
                    $magicToken,
                    $appName,
                    $baseUrl,
                );
                GymiesNotificationEmail::send($email, $vSubject, $vText, $vHtml);
            } catch (\Throwable $e) {
                Log::channel('single')->warning('GymRegistration: verificatiemail mislukt', [
                    'email' => $email,
                    'error' => $e->getMessage(),
                ]);
            }
        }

        return response()->json([
            'message' => 'Gym succesvol geregistreerd.',
            'data' => [
                'user_id'           => (string) $result['user_id'],
                'organisation_id'   => (string) $result['organisation_id'],
                'organisation_name' => trim($data['gym_name']),
                'token'             => $result['token'],
                'email_verified'    => false,
                'onboarding_complete' => false,
                'warning' => $result['existing_name']
                    ? 'Er bestaat al een gym met deze naam. Neem contact op als dit jouw gym is.'
                    : null,
            ],
        ], 201);
    }

    // ─── Publiek: Demo aanvragen ─────────────────────────────────────────────

    /**
     * POST gym/request-demo
     *
     * Slaat een demo-aanvraag op. Geen account nodig.
     * Rate-limited via middleware.
     */
    public function requestDemo(Request $request): JsonResponse
    {
        $data = $request->validate([
            'gym_name'            => 'required|string|min:2|max:255',
            'contact_name'        => 'required|string|min:2|max:255',
            'email'               => 'required|email|max:255',
            'phone'               => 'nullable|string|max:32',
            'city'                => 'nullable|string|max:128',
            'estimated_trainers'  => 'nullable|integer|min:1|max:500',
            'website_url'         => 'nullable|url|max:512',
            'message'             => 'nullable|string|max:2000',
        ]);

        $email = mb_strtolower(trim($data['email']));

        // Check: niet te veel aanvragen van zelfde e-mail (spam-preventie)
        if (Schema::hasTable('gymies_gym_demo_requests')) {
            $recentCount = DB::table('gymies_gym_demo_requests')
                ->where('email', $email)
                ->where('created_at', '>=', now()->subHours(24))
                ->count();

            if ($recentCount >= 3) {
                return response()->json([
                    'message' => 'Je hebt al meerdere aanvragen ingediend. We nemen zo snel mogelijk contact op.',
                ], 429);
            }

            // Genereer unieke referentiecode (GYM-XXXXXX)
            $referenceCode = 'GYM-' . strtoupper(substr(bin2hex(random_bytes(3)), 0, 6));

            $insertData = [
                'gym_name'           => trim($data['gym_name']),
                'contact_name'       => trim($data['contact_name']),
                'email'              => $email,
                'phone'              => $data['phone'] ?? null,
                'city'               => $data['city'] ?? null,
                'estimated_trainers' => $data['estimated_trainers'] ?? null,
                'website_url'        => $data['website_url'] ?? null,
                'message'            => $data['message'] ?? null,
                'status'             => 'new',
                'created_at'         => now(),
                'updated_at'         => now(),
            ];

            // Voeg referentiecode toe als kolom bestaat
            if (Schema::hasColumn('gymies_gym_demo_requests', 'reference_code')) {
                $insertData['reference_code'] = $referenceCode;
            }

            DB::table('gymies_gym_demo_requests')->insert($insertData);
        }

        Log::channel('single')->info('GymDemoRequest: nieuwe demo-aanvraag', [
            'gym_name'       => $data['gym_name'],
            'email'          => $email,
            'city'           => $data['city'] ?? null,
            'reference_code' => $referenceCode ?? null,
        ]);

        // Bevestigingsmail versturen naar de aanvrager
        try {
            $appName = GymiesNotificationEmail::mailBrandName();
            $baseUrl = GymiesNotificationEmail::mailPublicBaseUrl();
            [$subject, $text, $html] = GymiesMailTemplates::gymDemoBevestiging(
                trim($data['contact_name']),
                trim($data['gym_name']),
                $appName,
                $baseUrl,
            );
            GymiesNotificationEmail::send($email, $subject, $text, $html);
        } catch (\Throwable $e) {
            Log::channel('single')->warning('GymDemoRequest: bevestigingsmail mislukt', [
                'email' => $email,
                'error' => $e->getMessage(),
            ]);
        }

        // Interne admin notificatie — sales-team informeren over nieuwe lead
        try {
            $adminEmails = $this->getAdminNotificationEmails();
            if (!empty($adminEmails)) {
                $appName = $appName ?? GymiesNotificationEmail::mailBrandName();
                $adminUrl = rtrim(GymiesNotificationEmail::mailPublicBaseUrl(), '/') . '/admin/demo-requests';

                [$aSubject, $aText, $aHtml] = GymiesMailTemplates::adminNieuweDemoAanvraag(
                    trim($data['gym_name']),
                    trim($data['contact_name']),
                    $email,
                    $data['phone'] ?? null,
                    $data['city'] ?? null,
                    isset($data['estimated_trainers']) ? (int) $data['estimated_trainers'] : null,
                    $data['message'] ?? null,
                    $appName,
                    $adminUrl,
                );
                foreach ($adminEmails as $adminEmail) {
                    GymiesNotificationEmail::send($adminEmail, $aSubject, $aText, $aHtml);
                }
            }
        } catch (\Throwable $e) {
            Log::channel('single')->warning('GymDemoRequest: admin notificatie mislukt', [
                'error' => $e->getMessage(),
            ]);
        }

        return response()->json([
            'message' => 'Demo-aanvraag ontvangen. We nemen binnen 24 uur contact op.',
            'data' => [
                'status'         => 'received',
                'reference_code' => $referenceCode ?? null,
                'status_url'     => '/gym/aanvraag-status',
            ],
        ], 201);
    }

    // ─── Publiek: Status check voor gym-aanvragers ────────────────────────────

    /**
     * GET gym/demo-status?reference_code=GYM-XXXXXX&email=info@example.com
     *
     * Publieke statuspage: gym-aanvrager kan met referentiecode + email
     * de voortgang van zijn/haar demo-aanvraag bekijken.
     * Dubbele verificatie (code + email) voorkomt dat derden status inzien.
     */
    public function demoStatus(Request $request): JsonResponse
    {
        $data = $request->validate([
            'reference_code' => 'required|string|max:12',
            'email'          => 'required|email|max:255',
        ]);

        $code  = strtoupper(trim($data['reference_code']));
        $email = strtolower(trim($data['email']));

        // Formaat check: GYM-XXXXXX (6 hex chars)
        if (!preg_match('/^GYM-[A-F0-9]{6}$/', $code)) {
            return response()->json([
                'message' => 'Ongeldige referentiecode. Gebruik het formaat GYM-XXXXXX.',
            ], 422);
        }

        if (!Schema::hasTable('gymies_gym_demo_requests')) {
            return response()->json(['message' => 'Service tijdelijk niet beschikbaar.'], 503);
        }

        $demoRequest = DB::table('gymies_gym_demo_requests')
            ->where('reference_code', $code)
            ->first();

        if (!$demoRequest) {
            // Generiek bericht om enumeration te voorkomen
            return response()->json([
                'message' => 'Aanvraag niet gevonden. Controleer je referentiecode en e-mailadres.',
            ], 404);
        }

        // Email verificatie (case-insensitive)
        if (strtolower(trim($demoRequest->email)) !== $email) {
            // Zelfde generiek bericht — geeft niet prijs of de code bestaat
            return response()->json([
                'message' => 'Aanvraag niet gevonden. Controleer je referentiecode en e-mailadres.',
            ], 404);
        }

        // Status mapping naar gebruiksvriendelijke teksten
        $statusLabels = [
            'new'            => 'Ontvangen',
            'contacted'      => 'In behandeling',
            'demo_scheduled' => 'Demo ingepland',
            'approved'       => 'Goedgekeurd',
            'converted'      => 'Geregistreerd',
            'rejected'       => 'Afgewezen',
        ];

        $statusDescriptions = [
            'new'            => 'Je aanvraag is ontvangen en wordt zo snel mogelijk beoordeeld door ons team.',
            'contacted'      => 'We hebben contact opgenomen. Check je e-mail voor meer informatie.',
            'demo_scheduled' => 'Er is een demo ingepland. Je ontvangt binnenkort een uitnodiging.',
            'approved'       => 'Je aanvraag is goedgekeurd! Check je e-mail voor de registratielink.',
            'converted'      => 'Je gym is succesvol geregistreerd. Je kunt nu inloggen.',
            'rejected'       => 'Helaas is je aanvraag op dit moment afgewezen. Neem contact op voor meer informatie.',
        ];

        $status = $demoRequest->status ?? 'new';

        // Stap-indicator: welke stappen zijn doorlopen
        $steps = [
            ['key' => 'received',  'label' => 'Aanvraag ontvangen',  'done' => true],
            ['key' => 'review',    'label' => 'In behandeling',      'done' => in_array($status, ['contacted', 'demo_scheduled', 'approved', 'converted'])],
            ['key' => 'approved',  'label' => 'Goedgekeurd',         'done' => in_array($status, ['approved', 'converted'])],
            ['key' => 'registered','label' => 'Geregistreerd',       'done' => $status === 'converted'],
        ];

        $responseData = [
            'reference_code' => $code,
            'gym_name'       => $demoRequest->gym_name,
            'status'         => $status,
            'status_label'   => $statusLabels[$status] ?? ucfirst($status),
            'status_description' => $statusDescriptions[$status] ?? '',
            'steps'          => $steps,
            'submitted_at'   => $demoRequest->created_at,
        ];

        // Bij goedkeuring: token info toevoegen (zonder het token zelf te lekken)
        if ($status === 'approved' && Schema::hasTable('gymies_gym_invite_tokens')) {
            $invite = DB::table('gymies_gym_invite_tokens')
                ->where('demo_request_id', $demoRequest->id)
                ->where('status', 'pending')
                ->first();

            if ($invite) {
                $responseData['invite_expires_at'] = $invite->expires_at;
                $responseData['invite_sent']       = true;
            }
        }

        return response()->json(['data' => $responseData]);
    }

    // ─── Beveiligd: Onboarding na registratie ────────────────────────────────

    /**
     * POST gym/onboarding
     *
     * Stap-voor-stap onboarding. Accepteert velden die per stap worden ingevuld.
     * Idempotent: kan meerdere keren worden aangeroepen.
     */
    public function onboarding(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        $orgId = (int) $ctx['organisation_id'];
        $data = $request->validate([
            // Stap 1: Basisgegevens
            'logo_url'          => 'nullable|url|max:512',
            'opening_hours_json' => 'nullable|json',

            // Stap 2: Eerste locatie
            'location_name'     => 'nullable|string|max:255',
            'location_address'  => 'nullable|string|max:500',
            'location_city'     => 'nullable|string|max:128',
            'location_type'     => 'nullable|string|in:gym,studio,outdoor,home',
            'location_capacity' => 'nullable|integer|min:1|max:1000',

            // Stap 3: Uitnodiging e-mail (voor eerste trainer)
            'invite_trainer_email' => 'nullable|email|max:255',

            // Markering
            'onboarding_step'   => 'nullable|string|in:basics,location,invite,complete',
        ]);

        $updates = [];

        // Stap 1: Logo + openingstijden
        if (isset($data['logo_url']) && Schema::hasColumn('gymies_organisations', 'logo_url')) {
            $updates['logo_url'] = $data['logo_url'];
        }
        if (isset($data['opening_hours_json']) && Schema::hasColumn('gymies_organisations', 'opening_hours_json')) {
            $updates['opening_hours_json'] = $data['opening_hours_json'];
        }

        if (!empty($updates)) {
            $updates['updated_at'] = now();
            DB::table('gymies_organisations')->where('id', $orgId)->update($updates);
        }

        // Stap 2: Locatie toevoegen
        $locationId = null;
        if (!empty($data['location_name']) && Schema::hasTable('gymies_gym_locations')) {
            // Check of locatie al bestaat
            $existing = DB::table('gymies_gym_locations')
                ->where('organisation_id', $orgId)
                ->whereRaw('LOWER(name) = ?', [mb_strtolower(trim($data['location_name']))])
                ->first();

            if (!$existing) {
                $locationId = DB::table('gymies_gym_locations')->insertGetId([
                    'organisation_id' => $orgId,
                    'name'            => trim($data['location_name']),
                    'address'         => $data['location_address'] ?? null,
                    'city'            => $data['location_city'] ?? null,
                    'location_type'   => $data['location_type'] ?? 'gym',
                    'capacity'        => $data['location_capacity'] ?? null,
                    'sort_order'      => 0,
                    'created_at'      => now(),
                    'updated_at'      => now(),
                ]);

                // Stel in als default locatie
                if (Schema::hasColumn('gymies_organisations', 'default_location_id')) {
                    DB::table('gymies_organisations')
                        ->where('id', $orgId)
                        ->whereNull('default_location_id')
                        ->update(['default_location_id' => $locationId]);
                }
            } else {
                $locationId = $existing->id;
            }
        }

        // Stap 3: Trainer uitnodigen
        $inviteResult = null;
        if (!empty($data['invite_trainer_email']) && Schema::hasTable('gymies_gym_invites')) {
            $inviteEmail = mb_strtolower(trim($data['invite_trainer_email']));

            // Maak een invite-token
            $inviteToken = bin2hex(random_bytes(16));
            DB::table('gymies_gym_invites')->insert([
                'organisation_id' => $orgId,
                'token'           => $inviteToken,
                'email'           => $inviteEmail,
                'max_uses'        => 1,
                'used_count'      => 0,
                'expires_at'      => now()->addDays(14),
                'created_at'      => now(),
                'updated_at'      => now(),
            ]);

            $inviteResult = [
                'email' => $inviteEmail,
                'invite_link' => 'https://www.gymiesapp.nl/register?gym_invite_token=' . $inviteToken,
                'expires_in_days' => 14,
            ];

            // Invite e-mail versturen naar trainer
            try {
                $org = DB::table('gymies_organisations')->where('id', $orgId)->first();
                $gymName = $org->name ?? 'Uw gym';
                $appName = GymiesNotificationEmail::mailBrandName();
                $baseUrl = GymiesNotificationEmail::mailPublicBaseUrl();

                [$invSubject, $invText, $invHtml] = GymiesMailTemplates::gymTrainerInvite(
                    $inviteEmail,
                    $gymName,
                    $inviteToken,
                    $appName,
                    $baseUrl,
                );
                GymiesNotificationEmail::send($inviteEmail, $invSubject, $invText, $invHtml);
                $inviteResult['email_sent'] = true;
            } catch (\Throwable $e) {
                Log::channel('single')->warning('GymOnboarding: trainer invite mail mislukt', [
                    'email' => $inviteEmail,
                    'error' => $e->getMessage(),
                ]);
                $inviteResult['email_sent'] = false;
            }
        }

        // Onboarding voortgang berekenen
        $org = DB::table('gymies_organisations')->where('id', $orgId)->first();
        $hasLocation = Schema::hasTable('gymies_gym_locations')
            ? DB::table('gymies_gym_locations')->where('organisation_id', $orgId)->exists()
            : false;
        $hasTrainer = DB::table('gymies_organisation_trainers')
            ->where('organisation_id', $orgId)
            ->where('status', 'active')
            ->exists();

        $completedSteps = [];
        if ($org) {
            $completedSteps[] = 'account'; // altijd klaar als je hier bent
            if (!empty($org->logo_url) || !empty($org->opening_hours_json ?? null)) {
                $completedSteps[] = 'basics';
            }
            if ($hasLocation) {
                $completedSteps[] = 'location';
            }
            if ($hasTrainer) {
                $completedSteps[] = 'trainer';
            }
        }

        return response()->json([
            'message' => 'Onboarding bijgewerkt.',
            'data' => [
                'organisation_id'    => (string) $orgId,
                'completed_steps'    => $completedSteps,
                'total_steps'        => 4,
                'onboarding_complete' => count($completedSteps) >= 4,
                'location_id'        => $locationId ? (string) $locationId : null,
                'invite'             => $inviteResult,
            ],
        ]);
    }

    // ─── Publiek: Invite token valideren ────────────────────────────────────

    /**
     * GET gym/validate-invite-token?token=xxx
     *
     * Valideert een invite token en retourneert de pre-filled gegevens.
     * Publiek endpoint — geen auth nodig.
     * Wordt aangeroepen door de registratiepagina om te controleren of
     * het token geldig is en de formuliervelden in te vullen.
     */
    public function validateInviteToken(Request $request): JsonResponse
    {
        $token = trim((string) $request->input('token', ''));

        // Token format validatie (64 hex chars)
        if (!preg_match('/^[a-fA-F0-9]{64}$/', $token)) {
            return response()->json([
                'valid'   => false,
                'message' => 'Ongeldige registratielink.',
            ], 422);
        }

        if (!Schema::hasTable('gymies_gym_invite_tokens')) {
            return response()->json([
                'valid'   => false,
                'message' => 'Registratie via uitnodiging is momenteel niet beschikbaar.',
            ], 500);
        }

        $inviteToken = DB::table('gymies_gym_invite_tokens')
            ->where('token', $token)
            ->first();

        if (!$inviteToken) {
            return response()->json([
                'valid'   => false,
                'message' => 'Registratielink niet gevonden. Controleer de link of neem contact op.',
            ], 404);
        }

        // Status checks
        if ($inviteToken->status === 'used') {
            return response()->json([
                'valid'   => false,
                'message' => 'Deze registratielink is al gebruikt. Log in als u al een account heeft.',
            ], 410);
        }

        if ($inviteToken->status === 'revoked') {
            return response()->json([
                'valid'   => false,
                'message' => 'Deze registratielink is ingetrokken. Neem contact op voor een nieuwe link.',
            ], 410);
        }

        if ($inviteToken->status === 'expired' || now()->greaterThan($inviteToken->expires_at)) {
            // Markeer als expired als dat nog niet is
            if ($inviteToken->status !== 'expired') {
                DB::table('gymies_gym_invite_tokens')
                    ->where('id', $inviteToken->id)
                    ->update(['status' => 'expired', 'updated_at' => now()]);
            }
            return response()->json([
                'valid'   => false,
                'message' => 'Deze registratielink is verlopen. Neem contact op voor een nieuwe link.',
            ], 410);
        }

        // Token is geldig — retourneer pre-filled data
        return response()->json([
            'valid' => true,
            'data'  => [
                'gym_name'           => $inviteToken->gym_name,
                'contact_name'       => $inviteToken->contact_name,
                'email'              => $inviteToken->email,
                'phone'              => $inviteToken->phone,
                'city'               => $inviteToken->city,
                'estimated_trainers' => $inviteToken->estimated_trainers,
                'website_url'        => $inviteToken->website_url,
                'expires_at'         => $inviteToken->expires_at,
            ],
        ]);
    }

    // ─── Publiek: Registratie met invite token ──────────────────────────────

    /**
     * POST gym/register-with-token
     *
     * Registratie via goedgekeurde invite token.
     * Vergelijkbaar met register() maar:
     * - Vereist geldig token
     * - Pre-fills komen uit het token (gym_name, email, etc.)
     * - Markeert token als 'used' na succesvolle registratie
     * - Koppelt registratie terug aan de demo-aanvraag
     * - Markeert demo-aanvraag als 'converted'
     */
    public function registerWithToken(Request $request): JsonResponse
    {
        // ─── Validatie ──────────────────────────────────────────────────
        $data = $request->validate([
            'token'               => 'required|string|size:64',
            'password'            => 'required|string|min:12|max:128',
            // Optioneel: gebruiker mag gegevens aanpassen
            'gym_name'            => 'nullable|string|min:2|max:255',
            'contact_name'        => 'nullable|string|min:2|max:255',
            'phone'               => 'nullable|string|max:32',
            'city'                => 'nullable|string|max:128',
            'estimated_trainers'  => 'nullable|integer|min:1|max:500',
            'website_url'         => 'nullable|url|max:512',
        ]);

        $token = trim($data['token']);

        // Token format validatie
        if (!preg_match('/^[a-fA-F0-9]{64}$/', $token)) {
            return response()->json(['message' => 'Ongeldige registratielink.'], 422);
        }

        if (!Schema::hasTable('gymies_gym_invite_tokens')) {
            return response()->json(['message' => 'Registratie via uitnodiging is momenteel niet beschikbaar.'], 500);
        }

        // Token ophalen en valideren
        $inviteToken = DB::table('gymies_gym_invite_tokens')
            ->where('token', $token)
            ->first();

        if (!$inviteToken) {
            return response()->json(['message' => 'Registratielink niet gevonden.'], 404);
        }

        if ($inviteToken->status !== 'pending') {
            $statusMessages = [
                'used'    => 'Deze registratielink is al gebruikt.',
                'expired' => 'Deze registratielink is verlopen.',
                'revoked' => 'Deze registratielink is ingetrokken.',
            ];
            return response()->json([
                'message' => $statusMessages[$inviteToken->status] ?? 'Token is niet meer geldig.',
            ], 410);
        }

        if (now()->greaterThan($inviteToken->expires_at)) {
            DB::table('gymies_gym_invite_tokens')
                ->where('id', $inviteToken->id)
                ->update(['status' => 'expired', 'updated_at' => now()]);
            return response()->json(['message' => 'Deze registratielink is verlopen.'], 410);
        }

        // Gebruik token data als basis, maar laat gebruiker overschrijven
        $gymName     = trim($data['gym_name'] ?? $inviteToken->gym_name);
        $contactName = trim($data['contact_name'] ?? $inviteToken->contact_name);
        $email       = mb_strtolower(trim($inviteToken->email)); // E-mail komt ALTIJD uit token (security)
        $phone       = $data['phone'] ?? $inviteToken->phone;
        $city        = $data['city'] ?? $inviteToken->city;

        // Wachtwoord kwaliteitscheck
        $pwResult = GymiesPasswordValidator::validate($data['password']);
        if (!$pwResult->passes()) {
            throw ValidationException::withMessages(['password' => $pwResult->errors()]);
        }

        // E-mail uniek check
        if (DB::table('gymies_users')->where('email', $email)->exists()) {
            throw ValidationException::withMessages([
                'email' => ['Er bestaat al een account met dit e-mailadres. Log in of neem contact op.'],
            ]);
        }

        // ─── Transactie: user + organisatie + member + sessie + token update ──
        $result = DB::transaction(function () use (
            $gymName, $contactName, $email, $phone, $city, $data, $inviteToken
        ) {
            $now = now();

            // 1. Gebruiker aanmaken
            $userInsert = [
                'email'         => $email,
                'password_hash' => Hash::make($data['password']),
                'role'          => 'klant',
                'display_name'  => $contactName,
                'phone'         => $phone,
                'created_at'    => $now,
                'updated_at'    => $now,
            ];
            if (Schema::hasColumn('gymies_users', 'email_verified_at')) {
                // E-mail is al geverifieerd door het admin-goedkeuringsproces
                $userInsert['email_verified_at'] = $now;
            }
            $userId = DB::table('gymies_users')->insertGetId($userInsert);

            // 2. Organisatie aanmaken
            $orgInsert = [
                'name'             => $gymName,
                'type'             => 'gym',
                'status'           => 'active',
                'contact_email'    => $email,
                'payout_frequency' => 'weekly',
                'payout_minimum_cents' => 0,
                'created_at'       => $now,
                'updated_at'       => $now,
            ];
            if (!empty($city) && Schema::hasColumn('gymies_organisations', 'city')) {
                $orgInsert['city'] = $city;
            }
            if (!empty($data['website_url'] ?? $inviteToken->website_url) && Schema::hasColumn('gymies_organisations', 'website_url')) {
                $orgInsert['website_url'] = $data['website_url'] ?? $inviteToken->website_url;
            }
            $orgId = DB::table('gymies_organisations')->insertGetId($orgInsert);

            // 3. Owner-member koppeling
            DB::table('gymies_organisation_members')->insert([
                'organisation_id' => $orgId,
                'user_id'         => $userId,
                'role'            => 'owner',
                'status'          => 'active',
                'invited_at'      => $now,
                'joined_at'       => $now,
                'created_at'      => $now,
                'updated_at'      => $now,
            ]);

            // 4. Sessie token genereren
            $sessionToken = bin2hex(random_bytes(32));
            $sessionInsert = [
                'user_id'    => $userId,
                'token'      => $sessionToken,
                'expires_at' => $now->copy()->addDays(self::SESSION_TTL_DAYS),
                'created_at' => $now,
                'updated_at' => $now,
            ];
            if (Schema::hasColumn('gymies_sessions', 'user_agent')) {
                $sessionInsert['user_agent'] = mb_substr((string) request()->userAgent(), 0, 255);
            }
            if (Schema::hasColumn('gymies_sessions', 'ip_address')) {
                $sessionInsert['ip_address'] = request()->ip();
            }
            DB::table('gymies_sessions')->insert($sessionInsert);

            // 5. Invite token markeren als used
            DB::table('gymies_gym_invite_tokens')
                ->where('id', $inviteToken->id)
                ->update([
                    'status'                    => 'used',
                    'used_at'                   => $now,
                    'registered_user_id'        => $userId,
                    'registered_organisation_id' => $orgId,
                    'updated_at'                => $now,
                ]);

            // 6. Demo-aanvraag markeren als converted (als gekoppeld)
            if ($inviteToken->demo_request_id && Schema::hasTable('gymies_gym_demo_requests')) {
                DB::table('gymies_gym_demo_requests')
                    ->where('id', $inviteToken->demo_request_id)
                    ->update([
                        'status'     => 'converted',
                        'updated_at' => $now,
                    ]);
            }

            return [
                'user_id'         => $userId,
                'organisation_id' => $orgId,
                'token'           => $sessionToken,
            ];
        });

        // Logging
        Log::channel('single')->info('GymRegistration: gym geregistreerd via invite token', [
            'user_id'           => $result['user_id'],
            'organisation_id'   => $result['organisation_id'],
            'gym_name'          => $gymName,
            'invite_token_id'   => $inviteToken->id,
            'demo_request_id'   => $inviteToken->demo_request_id,
        ]);

        // Automatische trial starten — gym heeft direct toegang tot alle features
        $trialInfo = null;
        try {
            $trialInfo = $this->startAutoTrial((int) $result['organisation_id']);
        } catch (\Throwable $e) {
            Log::channel('single')->warning('GymRegistration (token): auto-trial mislukt', [
                'organisation_id' => $result['organisation_id'],
                'error' => $e->getMessage(),
            ]);
        }

        // Welkomstmail versturen
        try {
            $appName = GymiesNotificationEmail::mailBrandName();
            $baseUrl = GymiesNotificationEmail::mailPublicBaseUrl();
            [$subject, $text, $html] = GymiesMailTemplates::gymWelkom(
                $contactName,
                $gymName,
                $appName,
                $baseUrl,
            );
            GymiesNotificationEmail::send($email, $subject, $text, $html);
        } catch (\Throwable $e) {
            Log::channel('single')->warning('GymRegistration (token): welkomstmail mislukt', [
                'email' => $email,
                'error' => $e->getMessage(),
            ]);
        }

        return response()->json([
            'message' => 'Gym succesvol geregistreerd.',
            'data' => [
                'user_id'             => (string) $result['user_id'],
                'organisation_id'     => (string) $result['organisation_id'],
                'organisation_name'   => $gymName,
                'token'               => $result['token'],
                'email_verified'      => true,
                'onboarding_complete' => false,
                'trial'               => $trialInfo,
            ],
        ], 201);
    }

    // ─── Helper: Automatische trial starten ─────────────────────────────────

    /**
     * Haal e-mailadressen op van admins die notificaties moeten ontvangen.
     * Configureerbaar via gymies_system_settings (key: gym_admin_notification_emails).
     * Fallback: alle actieve admins met capability 'admin.organisations.manage'.
     */
    private function getAdminNotificationEmails(): array
    {
        // Eerst: check system setting (komma-gescheiden lijst)
        if (Schema::hasTable('gymies_system_settings')) {
            $setting = DB::table('gymies_system_settings')
                ->where('setting_key', 'gym_admin_notification_emails')
                ->first();
            if ($setting && !empty(trim((string) $setting->setting_value))) {
                return array_filter(
                    array_map('trim', explode(',', (string) $setting->setting_value)),
                    fn($e) => filter_var($e, FILTER_VALIDATE_EMAIL) !== false
                );
            }
        }

        // Fallback: actieve admins met organisatie-beheer rechten
        if (Schema::hasTable('gymies_admin_users')) {
            $admins = DB::table('gymies_admin_users')
                ->where('is_active', 1)
                ->pluck('email')
                ->filter(fn($e) => filter_var($e, FILTER_VALIDATE_EMAIL) !== false)
                ->take(5) // Max 5 om spam te voorkomen
                ->toArray();
            if (!empty($admins)) {
                return $admins;
            }
        }

        return [];
    }

    /**
     * Start automatisch een 14-dagen trial voor een nieuwe gym-organisatie.
     * Zoekt het actieve Studio plan (plan_type='gym') en maakt een subscription aan.
     */
    private function startAutoTrial(int $orgId): ?array
    {
        if (!Schema::hasTable('gymies_gym_subscriptions') || !Schema::hasTable('gymies_plans')) {
            return null;
        }

        // Check of er al een subscription is (idempotent)
        $existing = DB::table('gymies_gym_subscriptions')
            ->where('organisation_id', $orgId)
            ->first();
        if ($existing) {
            return [
                'status' => $existing->status,
                'already_exists' => true,
            ];
        }

        // Zoek het actieve gym plan (Studio)
        $plan = DB::table('gymies_plans')
            ->where('is_active', 1)
            ->where('plan_type', 'gym')
            ->orderBy('price_cents_per_month')
            ->first();

        if (!$plan) {
            return null;
        }

        // Trial dagen ophalen uit system settings (default 14)
        $trialDays = 14;
        if (Schema::hasTable('gymies_system_settings')) {
            $setting = DB::table('gymies_system_settings')
                ->where('setting_key', 'gym_trial_days')
                ->first();
            if ($setting) {
                $trialDays = max(1, (int) $setting->setting_value);
            }
        }

        $trialEndsAt = now()->addDays($trialDays);

        $subId = DB::table('gymies_gym_subscriptions')->insertGetId([
            'organisation_id'      => $orgId,
            'plan_id'              => (int) $plan->id,
            'status'               => 'trialing',
            'billing_cycle'        => 'monthly',
            'trial_ends_at'        => $trialEndsAt,
            'current_period_start' => now(),
            'current_period_end'   => $trialEndsAt,
            'created_at'           => now(),
            'updated_at'           => now(),
        ]);

        Log::channel('single')->info('GymRegistration: auto-trial gestart', [
            'subscription_id'  => $subId,
            'organisation_id'  => $orgId,
            'plan_id'          => $plan->id,
            'plan_name'        => $plan->name,
            'trial_days'       => $trialDays,
            'trial_ends_at'    => $trialEndsAt->toIso8601String(),
        ]);

        return [
            'subscription_id' => (int) $subId,
            'plan_name'       => $plan->name,
            'status'          => 'trialing',
            'trial_days'      => $trialDays,
            'trial_ends_at'   => $trialEndsAt->toIso8601String(),
        ];
    }
}
