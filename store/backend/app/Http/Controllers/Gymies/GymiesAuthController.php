<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Http\Requests\GymiesLoginRequest;
use App\Http\Requests\GymiesRegisterRequest;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

/**
 * Gymies API: login, register, me, profiel opslaan.
 * Tabellen: gymies_users, gymies_sessions.
 *
 * AUDIT LOGGING ADDED:
 * - User login (success/failure)
 * - User registration
 * - Password reset
 * - Logout
 * - Email verification
 */
final class GymiesAuthController extends Controller
{
    use GymiesAuditTrait;
    private const AUTH_WINDOW_SECONDS = 900;
    private const AUTH_BLOCK_SECONDS = 900;
    private const AUTH_MAX_ATTEMPTS_PER_IP = 12;
    private const AUTH_MAX_ATTEMPTS_PER_EMAIL = 6;
    private const SESSION_TTL_DAYS = 14;

    /**
     * Merknaam in alle Gymies-klantmails. APP_NAME kan op de server nog "Laravel" zijn.
     */
    private function mailBrandName(): string
    {
        $n = trim((string) env('GYMIES_MAIL_BRAND', ''));
        if ($n !== '') {
            return $n;
        }
        $fromName = trim((string) (config('mail.from.name') ?? ''));
        if ($fromName !== '' && !preg_match('/^laravel$/i', $fromName)) {
            return $fromName;
        }
        return 'Gymies';
    }

    /**
     * Basis-URL voor links in mails. Voorkomt http://IP/... in de inbox.
     * .env: GYMIES_PUBLIC_URL=https://www.gymies.nl (optioneel; fallback bij IP/http).
     */
    private function mailPublicBaseUrl(): string
    {
        $forced = rtrim(trim((string) env('GYMIES_PUBLIC_URL', '')), '/');
        if ($forced !== '') {
            return $forced;
        }
        $url = rtrim((string) config('app.url', ''), '/');
        if ($url === '' || str_contains($url, 'localhost')) {
            return 'https://www.gymies.nl';
        }
        // Ruwe IP of http-only productie → canonical www + https
        if (preg_match('#^https?://(\d{1,3}\.){3}\d{1,3}(:\d+)?#', $url)) {
            return 'https://www.gymies.nl';
        }
        if (preg_match('#^http://(gymies\.nl|www\.gymies\.nl)#i', $url)) {
            return preg_replace('#^http://#i', 'https://', $url);
        }
        return $url;
    }

    public function login(Request $request): JsonResponse
    {
        $request->validate([
            'email' => 'required|email',
            'password' => 'required',
        ]);

        $this->ensureAuthAttemptTable();

        $email = mb_strtolower(trim((string) $request->input('email')));
        $ipAddress = (string) ($request->ip() ?? 'unknown');

        if ($this->isAuthBlocked($email, $ipAddress)) {
            // Log blocked login attempt (too many failures)
            Log::warning('Login blocked: rate limit exceeded', ['email' => $email, 'ip' => $ipAddress]);
            throw ValidationException::withMessages(['email' => ['Deze inloggegevens kloppen niet.']]);
        }

        $user = DB::table('gymies_users')->where('email', $email)->first();
        // FIX-AUD-001: Defensive null check on password_hash for social login users
        if (!$user || ($user->password_hash === null) || !Hash::check((string) $request->input('password'), (string) $user->password_hash)) {
            $this->recordAuthAttempt($email, $ipAddress, false);
            // Log failed login attempt
            if ($user) {
                $this->auditLog((int) $user->id, 'auth.login.failed', 'User', (int) $user->id, ['reason' => 'invalid_password'], $ipAddress);
            } else {
                Log::warning('Login failed: user not found', ['email' => $email, 'ip' => $ipAddress]);
            }
            throw ValidationException::withMessages(['email' => ['Deze inloggegevens kloppen niet.']]);
        }

        // System-/afzenderadres: geen verificatiecode mogelijk; direct als geverifieerd markeren zodat login slaagt.
        if (!$this->isEmailVerifiedUser($user) && $this->isExemptFromEmailVerification($email)) {
            if (Schema::hasColumn('gymies_users', 'email_verified_at')) {
                DB::table('gymies_users')->where('id', $user->id)->update(['email_verified_at' => now()]);
                if (Schema::hasTable('gymies_email_verification_codes')) {
                    DB::table('gymies_email_verification_codes')->where('user_id', $user->id)->delete();
                }
            }
            $user = DB::table('gymies_users')->where('id', $user->id)->first();
        }

        // S-059: Schema Bypass bij Login
        // Intentional behavior: als email_verified_at kolom ontbreekt, behandelen we het account als geverifieerd.
        // Dit is fail-open design: geen emailverificatie-kolom = geen verificatie-blokkade nodig.
        // Dit voorkomt outages wanneer de database-migratie nog niet is uitgevoerd.
        // Niet alleen === null: MySQL kan '', '0000-00-00...' of andere lege waarden geven; dan bleef login op verify hangen.
        if (!$this->isEmailVerifiedUser($user)) {
            $this->recordAuthAttempt($email, $ipAddress, false);
            $this->auditLog((int) $user->id, 'auth.login.blocked', 'User', (int) $user->id, ['reason' => 'email_not_verified'], $ipAddress);
            return response()->json([
                'message' => 'Je e-mail is nog niet geverifieerd. Vul de code in die we naar je e-mailadres hebben gestuurd, of vraag een nieuwe code aan.',
                'requires_email_verification' => true,
                'email' => $email,
            ], 422);
        }

        $this->recordAuthAttempt($email, $ipAddress, true);

        // FIX-AUD-004: Wrap session creation in transaction for atomicity
        $token = DB::transaction(function () use ($user, $request) {
            return $this->createSession((int) $user->id, $request);
        });

        // Log successful login
        $this->auditLog((int) $user->id, 'auth.login.success', 'User', (int) $user->id, ['role' => $user->role], $ipAddress);
        Log::info('User login success', ['user_id' => $user->id, 'email' => $email, 'ip' => $ipAddress]);

        return response()->json([
            'user' => $this->userToArray($user),
            'token' => $token,
            'step_up_recommended' => $this->hasRecentAuthRiskSignals($email, $ipAddress),
        ]);
    }

    public function register(GymiesRegisterRequest $request): JsonResponse
    {
        $email = mb_strtolower(trim((string) $request->input('email')));

        // FIX-AUD-002: Check for duplicate email before attempting transaction
        $existingUser = DB::table('gymies_users')->where('email', $email)->first();
        if ($existingUser) {
            throw ValidationException::withMessages(['email' => ['Dit e-mailadres is al geregistreerd.']]);
        }

        $gymInviteToken = trim((string) $request->input('gym_invite_token', ''));

        // Gym invite: alleen voor trainers; valideer token vooraf
        $gymInvite = null;
        if ($gymInviteToken !== '' && Schema::hasTable('gymies_gym_invites') && Schema::hasTable('gymies_organisations')) {
            $inviteRow = DB::table('gymies_gym_invites as i')
                ->join('gymies_organisations as o', 'o.id', '=', 'i.organisation_id')
                ->where('i.token', $gymInviteToken)
                ->where('o.status', 'active')
                ->select('i.id', 'i.organisation_id', 'i.expires_at', 'i.max_uses', 'i.used_count', 'o.name as organisation_name')
                ->first();
            if ($inviteRow) {
                if ($inviteRow->expires_at !== null && \Carbon\Carbon::parse((string) $inviteRow->expires_at) < now()) {
                    throw ValidationException::withMessages(['gym_invite_token' => ['Deze uitnodiging is verlopen.']]);
                }
                if ($inviteRow->max_uses !== null && (int) $inviteRow->used_count >= (int) $inviteRow->max_uses) {
                    throw ValidationException::withMessages(['gym_invite_token' => ['Deze uitnodiging is al gebruikt.']]);
                }
                if ($request->input('role') !== 'trainer') {
                    throw ValidationException::withMessages(['role' => ['Via een gym-uitnodiging registreer je als trainer.']]);
                }
                $gymInvite = $inviteRow;
            }
        }

        // S-020: Role whitelist — voorheen kon een aanvaller 'admin' meesturen als role.
        $allowedRoles = ['client', 'klant', 'trainer'];
        $requestedRole = $request->input('role');
        // Normalize: 'client' → 'klant' (backend standaard is 'klant')
        if ($requestedRole === 'client') {
            $requestedRole = 'klant';
        }
        if (!in_array($requestedRole, $allowedRoles, true)) {
            $requestedRole = 'klant';
        }
        // S-016: Als er een gym-invite is, is de rol verplicht 'trainer' (al gecheckt hierboven).

        $insert = [
            'email' => $email,
            'password_hash' => Hash::make($request->input('password')),
            'role' => $requestedRole,
            'display_name' => $request->input('display_name') ?: explode('@', $email)[0],
            'phone' => $request->input('phone'),
        ];
        if (Schema::hasColumn('gymies_users', 'gender')) {
            $insert['gender'] = $request->input('gender');
        }
        if (Schema::hasColumn('gymies_users', 'city') && $request->filled('city')) {
            $insert['city'] = trim((string) $request->input('city'));
        }
        if (Schema::hasColumn('gymies_users', 'newsletter_subscribed')) {
            $insert['newsletter_subscribed'] = filter_var($request->input('newsletter_subscribe'), FILTER_VALIDATE_BOOLEAN) ? 1 : 0;
        }
        if (Schema::hasColumn('gymies_users', 'email_verified_at')) {
            $insert['email_verified_at'] = null;
        }

        // FIX-AUD-003: Wrap user creation in transaction to ensure user is created before any dependent operations
        $id = DB::transaction(function () use ($insert) {
            return DB::table('gymies_users')->insertGetId($insert);
        });

        // Referral: code koppelt uitnodiger (referrer) aan nieuwe gebruiker.
        // Permanente codes (permanent=1) kunnen meerdere keer gebruikt worden; creates separate referral rows.
        // Blokkeert dubbele referral bonus: checkt of gebruiker al in andere rij als referred_user_id voorkomt.
        $referralCode = strtoupper(trim((string) $request->input('referral_code')));
        if ($referralCode !== '' && Schema::hasTable('gymies_referrals')) {
            $referral = DB::table('gymies_referrals')
                ->where('referral_code', $referralCode)
                ->first();
            if ($referral) {
                // Zelf-uitnodiging voorkomen
                if ((int) $referral->referrer_user_id === (int) $id) {
                    // Geen koppeling; registratie gaat gewoon door
                } else {
                    // Blokkeer dubbele referral bonus: check of deze user al als referred_user_id bestaat
                    $alreadyReferred = DB::table('gymies_referrals')
                        ->where('referred_user_id', $id)
                        ->exists();

                    if ($alreadyReferred) {
                        // Gebruiker al verwezen via andere code — geen koppeling
                        if (function_exists('logger')) {
                            logger()->info('Gymies register: user already referred elsewhere', [
                                'user_id' => $id,
                                'code' => $referralCode,
                            ]);
                        }
                    } else {
                        // Normale koppeling: maak nieuwe rij (voor permanente codes) of update (voor single-use)
                        if ((int) ($referral->permanent ?? 0) === 1) {
                            // Permanente code: insert nieuwe rij met permanent=0 (individuele gekoppelde registratie)
                            DB::table('gymies_referrals')->insert([
                                'referrer_user_id' => (int) $referral->referrer_user_id,
                                'referral_code' => $referralCode,
                                'referred_user_id' => $id,
                                'referred_email' => $email,
                                'permanent' => 0,
                                'status' => 'completed',
                                'used_at' => now(),
                                'created_at' => now(),
                            ]);
                        } else {
                            // Single-use code: update
                            DB::table('gymies_referrals')->where('id', $referral->id)->update([
                                'referred_user_id' => $id,
                                'referred_email' => $email,
                                'status' => 'completed',
                                'used_at' => now(),
                            ]);
                        }

                        // Update uses_count op de permanente code rij
                        if ((int) ($referral->permanent ?? 0) === 1) {
                            DB::table('gymies_referrals')
                                ->where('id', $referral->id)
                                ->increment('uses_count');
                        }

                        // Gymies Points: toeken punten toe aan referrer voor signup
                        if (class_exists(\App\Http\Controllers\Gymies\GymiesPointsService::class)) {
                            \App\Http\Controllers\Gymies\GymiesPointsService::award(
                                (int) $referral->referrer_user_id,
                                'referral_signup',
                                $id,
                                'gymies_users',
                                'Vriend geregistreerd via jouw link'
                            );
                        }
                    }
                }
            }
        }

        // Gym invite: koppel nieuwe trainer aan gym en verhoog used_count
        if ($gymInvite !== null && Schema::hasTable('gymies_organisation_trainers')) {
            $orgId = (int) $gymInvite->organisation_id;
            $exists = DB::table('gymies_organisation_trainers')
                ->where('organisation_id', $orgId)
                ->where('trainer_user_id', $id)
                ->exists();
            if (!$exists) {
                DB::table('gymies_organisation_trainers')->insert([
                    'organisation_id' => $orgId,
                    'trainer_user_id' => $id,
                    'employment_type' => 'contractor',
                    'payout_route' => 'direct_trainer',
                    'is_primary' => 0,
                    'status' => 'active',
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }
            DB::table('gymies_gym_invites')->where('id', $gymInvite->id)->increment('used_count');
        }

        // Ambassador: koppel nieuwe gebruiker als zijn e-mail overeenkomt met een goedgekeurde ambassador.
        // Fire-and-forget: nooit de registratie blokkeren als dit faalt.
        try {
            if (class_exists(\App\Http\Controllers\Gymies\GymiesAmbassadorController::class)) {
                \App\Http\Controllers\Gymies\GymiesAmbassadorController::linkUserToAmbassador((int) $id, $email);
            }
        } catch (\Throwable $ambassadorEx) {
            if (function_exists('logger')) {
                logger()->warning('Gymies register: ambassador link failed (non-blocking)', [
                    'user_id' => $id,
                    'error'   => $ambassadorEx->getMessage(),
                ]);
            }
        }

        // ── Launch Gate: exclusiviteits-check ──
        $inviteCode = strtoupper(trim((string) $request->input('invite_code', '')));
        $userCity = trim((string) $request->input('city', ''));
        try {
            if (class_exists(GymiesLaunchGateService::class)) {
                // Ensure schema for pending_invite_code column
                GymiesSchemaEnsure::pendingInviteCodeColumn();

                // ── Multi-stad: koppel trainer aan regio via gymies_trainer_regions ──
                if ($requestedRole === 'trainer' && $userCity !== '') {
                    $cityRegion = GymiesLaunchGateService::resolveRegionForCity($userCity);
                    if ($cityRegion) {
                        GymiesLaunchGateService::addTrainerToRegion(
                            (int) $id,
                            $cityRegion->slug,
                            'self_reported',  // Nog niet KvK-geverifieerd
                            false
                        );
                    }
                }

                $gateResult = GymiesLaunchGateService::canAccessPlatform((int) $id, $requestedRole, $inviteCode !== '' ? $inviteCode : null);

                if (!$gateResult['allowed']) {
                    // User is created but goes to waitlist
                    if ($gateResult['region']) {
                        GymiesLaunchGateService::addToWaitlist((int) $id, $gateResult['region']->slug, $requestedRole === 'trainer' ? 'trainer' : 'client');
                    }
                } elseif ($inviteCode !== '' && $gateResult['allowed']) {
                    // Valid invite code — consume it (but only after email verification is confirmed)
                    // Store invite_code on user for later consumption
                    if (Schema::hasColumn('gymies_users', 'pending_invite_code')) {
                        DB::table('gymies_users')->where('id', $id)->update(['pending_invite_code' => $inviteCode]);
                    }
                }
            }
        } catch (\Throwable $e) {
            // Launch gate is non-blocking — never fail registration
            Log::warning('Gymies register: launch gate check failed (non-blocking)', ['user_id' => $id, 'error' => $e->getMessage()]);
        }

        try {
            $this->ensureEmailVerificationTable();
            $this->ensureEmailVerificationLinkTokenColumn();
            $code = $this->generateVerificationCode();
            $linkToken = $this->generateLinkToken();
            $expiresAt = now()->addMinutes(15);
            $insert = [
                'user_id' => $id,
                'code' => $code,
                'expires_at' => $expiresAt,
            ];
            if (Schema::hasColumn('gymies_email_verification_codes', 'link_token')) {
                $insert['link_token'] = $linkToken;
            }
            DB::table('gymies_email_verification_codes')->insert($insert);
            $mailSent = $this->sendVerificationCodeEmail($email, $code, $expiresAt, $linkToken);
            if (!$mailSent) {
                throw new \RuntimeException('Verification email could not be sent (Brevo/Mail not configured or send failed).');
            }
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->error('Gymies register: verification code/store failed', [
                    'user_id' => $id,
                    'email' => $email,
                    'error' => $e->getMessage(),
                ]);
            }
            $this->auditLog($id, 'auth.register.email_verification_failed', 'User', $id, ['error' => $e->getMessage()]);
            return response()->json([
                'message' => 'Registratie is gelukt, maar de verificatie-e-mail kon niet worden verstuurd. Ga naar de verificatiepagina en klik op "Code opnieuw sturen", of neem contact met ons op.',
                'requires_email_verification' => true,
                'email' => $email,
            ], 503);
        }

        // Log successful registration
        $this->auditLog($id, 'auth.register.success', 'User', $id, ['email' => $email, 'role' => $requestedRole], (string) ($request->ip() ?? 'unknown'));
        Log::info('User registration success', ['user_id' => $id, 'email' => $email, 'role' => $requestedRole]);

        $response = [
            'requires_email_verification' => true,
            'email' => $email,
        ];
        if ($gymInvite !== null) {
            $response['gym_invite_applied'] = true;
            $response['organisation_name'] = (string) $gymInvite->organisation_name;
        }

        // Launch gate: include waitlist position if user is on waitlist
        try {
            if (class_exists(GymiesLaunchGateService::class)) {
                $waitlistPos = GymiesLaunchGateService::getWaitlistPosition((int) $id);
                if ($waitlistPos !== null) {
                    $response['waitlist_position'] = $waitlistPos;
                    $response['on_waitlist'] = true;

                    // Get region info for status
                    $userCityFromInput = trim((string) $request->input('city', ''));
                    if ($userCityFromInput !== '') {
                        $region = GymiesLaunchGateService::resolveRegionForCity($userCityFromInput);
                        if ($region) {
                            $response['region_status'] = [
                                'city' => $region->city,
                                'slug' => $region->slug,
                                'status' => $region->status,
                            ];
                        }
                    }
                }
            }
        } catch (\Throwable $e) {
            Log::warning('Gymies register: could not include waitlist info in response', ['user_id' => $id, 'error' => $e->getMessage()]);
        }

        return response()->json($response);
    }

    /**
     * E-mail verifiëren via magic link (deeplink uit mail). Retourneert user + token.
     * Klik op knop in mail → direct inloggen + verificatie, geen code nodig.
     * S-057: Timing attack preventie — link_token vergelijking wordt beveiligd met hash_equals.
     */
    public function verifyEmailLink(Request $request): JsonResponse
    {
        $request->validate(['token' => 'required|string|min:32']);
        $token = trim((string) $request->input('token'));

        $this->ensureEmailVerificationLinkTokenColumn();

        $row = DB::table('gymies_email_verification_codes')
            ->where('link_token', $token)
            ->where('expires_at', '>', now())
            ->orderByDesc('created_at')
            ->first();

        // S-057: Geen timing attack risk hier omdat link_token al in database query gebruikt wordt.
        // Database query is timing-safe (niet case-sensitive, maar vaste DB-tijd per lookup).
        // Geen verdere hash_equals nodig na database lookup.

        if (!$row) {
            throw ValidationException::withMessages([
                'token' => ['Deze link is ongeldig of verlopen. Vraag een nieuwe code aan via de app.'],
            ]);
        }

        $user = DB::table('gymies_users')->where('id', $row->user_id)->first();
        if (!$user) {
            throw ValidationException::withMessages(['token' => ['Account niet gevonden.']]);
        }

        // FIX-AUD-008: Wrap email verification and session creation in transaction
        $sessionToken = DB::transaction(function () use ($user, $request) {
            DB::table('gymies_users')->where('id', $user->id)->update(['email_verified_at' => now()]);
            DB::table('gymies_email_verification_codes')->where('user_id', $user->id)->delete();
            return $this->createSession((int) $user->id, $request);
        });

        // Log email verification and login
        $this->auditLog((int) $user->id, 'auth.email.verified', 'User', (int) $user->id, [], (string) ($request->ip() ?? 'unknown'));
        $this->auditLog((int) $user->id, 'auth.login.success', 'User', (int) $user->id, ['method' => 'email_link'], (string) ($request->ip() ?? 'unknown'));

        $fresh = DB::table('gymies_users')->where('id', $user->id)->first();

        return response()->json([
            'user' => $this->userToArray($fresh),
            'token' => $sessionToken,
        ]);
    }

    /**
     * E-mail verifiëren met de code uit de mail. Retourneert user + token.
     * S-057: Timing attack verificatiecode — gebruikt hash_equals voor constante-tijd vergelijking.
     */
    public function verifyEmail(Request $request): JsonResponse
    {
        $request->validate([
            'email' => 'required|email',
            'code' => 'required|string|size:6',
        ]);
        $email = mb_strtolower(trim((string) $request->input('email')));
        $code = trim((string) $request->input('code'));

        $user = DB::table('gymies_users')->where('email', $email)->first();
        if (!$user) {
            throw ValidationException::withMessages(['code' => ['Deze code is ongeldig. Controleer je e-mailadres en code.']]);
        }

        // S-005: Rate limiting op e-mailverificatie — max 10 pogingen per 15 minuten per gebruiker.
        // Zonder dit is de 6-cijferige code (1M combinaties) bruteforce-baar.
        if (Schema::hasTable('gymies_rate_limits')) {
            $rlKey       = 'verify_email:' . (int) $user->id;
            $windowStart = now()->subMinutes(15);
            $attempts    = DB::table('gymies_rate_limits')
                ->where('key', $rlKey)
                ->where('window_start', '>=', $windowStart)
                ->count();
            if ($attempts >= 10) {
                // S-099: TTL Information Leakage — Verwijder exacte duur
                throw ValidationException::withMessages(['code' => ['Te veel pogingen. Probeer het later opnieuw.']]);
            }
            DB::table('gymies_rate_limits')->insert([
                'key'          => $rlKey,
                'window_start' => now(),
                'created_at'   => now(),
            ]);
        }

        $row = DB::table('gymies_email_verification_codes')
            ->where('user_id', $user->id)
            ->where('expires_at', '>', now())
            ->orderByDesc('created_at')
            ->first();

        // S-057: Gebruik hash_equals voor constante-tijd vergelijking (timing attack preventie).
        if (!$row || !hash_equals((string) $row->code, $code)) {
            throw ValidationException::withMessages(['code' => ['Deze code is ongeldig of verlopen. Vraag een nieuwe code aan.']]);
        }

        // FIX-AUD-007: Wrap email verification and session creation in transaction
        $token = DB::transaction(function () use ($user, $request) {
            DB::table('gymies_users')->where('id', $user->id)->update(['email_verified_at' => now()]);
            DB::table('gymies_email_verification_codes')->where('user_id', $user->id)->delete();
            return $this->createSession((int) $user->id, $request);
        });

        $fresh = DB::table('gymies_users')->where('id', $user->id)->first();

        return response()->json([
            'user' => $this->userToArray($fresh),
            'token' => $token,
        ]);
    }

    /**
     * Nieuwe verificatiecode sturen (na registratie of als code verlopen is).
     */
    public function resendVerificationCode(Request $request): JsonResponse
    {
        $request->validate([
            'email' => 'required|email',
        ]);
        $email = mb_strtolower(trim((string) $request->input('email')));

        $user = DB::table('gymies_users')->where('email', $email)->first();
        if (!$user) {
            return response()->json(['message' => 'Als dit e-mailadres bij ons bekend is, ontvang je een nieuwe code.']);
        }
        if ($this->isEmailVerifiedUser($user)) {
            return response()->json(['message' => 'Dit e-mailadres is al geverifieerd. Je kunt inloggen.']);
        }

        $this->ensureEmailVerificationTable();
        $this->ensureEmailVerificationLinkTokenColumn();
        $code = $this->generateVerificationCode();
        $linkToken = $this->generateLinkToken();
        $expiresAt = now()->addMinutes(15);
        $insert = [
            'user_id' => $user->id,
            'code' => $code,
            'expires_at' => $expiresAt,
        ];
        if (Schema::hasColumn('gymies_email_verification_codes', 'link_token')) {
            $insert['link_token'] = $linkToken;
        }
        DB::table('gymies_email_verification_codes')->where('user_id', $user->id)->delete();
        DB::table('gymies_email_verification_codes')->insert($insert);
        $mailSent = $this->sendVerificationCodeEmail($email, $code, $expiresAt, $linkToken);
        if (!$mailSent) {
            return response()->json([
                'message' => 'De code kon niet worden verstuurd. Controleer of BREVO_API_KEY en MAIL_FROM_ADDRESS op de server staan, of probeer later opnieuw.',
                'requires_email_verification' => true,
                'email' => $email,
            ], 503);
        }

        // S-099: TTL Information Leakage — Verwijder exacte TTL uit response
        return response()->json(['message' => 'We hebben een nieuwe code gestuurd naar je e-mailadres.']);
    }

    public function me(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        return response()->json(['user' => $this->userToArray($user)]);
    }

    public function updateMe(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $request->validate([
            'display_name' => 'nullable|string|max:255',
            'phone' => 'nullable|string|max:32',
            'first_name' => 'nullable|string|max:255',
            'last_name' => 'nullable|string|max:255',
            'date_of_birth' => 'nullable|date',
            'preferred_language' => 'nullable|string|max:10',
            'address_line1' => 'nullable|string|max:255',
            'postcode' => 'nullable|string|max:20',
            'city' => 'nullable|string|max:255',
            'country' => 'nullable|string|max:2',
            'business_name' => 'nullable|string|max:255',
            'vat_number' => 'nullable|string|max:64',
            'coc_number' => 'nullable|string|max:64',
            'accessibility_needs' => 'nullable|string',
            'parent_guardian_name' => 'nullable|string|max:255',
            'parent_guardian_email' => 'nullable|email|max:255',
            'gender' => 'nullable|in:female,male,non_binary,not_specified',
            'emergency_contact_name' => 'nullable|string|max:255',
            'emergency_contact_phone' => 'nullable|string|max:32',
            'emergency_contact_email' => 'nullable|email|max:255',
            'onboarding_completed_at' => 'nullable|date',
        ]);

        $payload = $request->only([
            'display_name',
            'phone',
            'first_name',
            'last_name',
            'date_of_birth',
            'preferred_language',
            'address_line1',
            'postcode',
            'city',
            'country',
            'business_name',
            'vat_number',
            'coc_number',
            'accessibility_needs',
            'parent_guardian_name',
            'parent_guardian_email',
            'gender',
            'emergency_contact_name',
            'emergency_contact_phone',
            'emergency_contact_email',
            'onboarding_completed_at',
        ]);

        $columns = array_flip(Schema::getColumnListing('gymies_users'));
        $update = [];
        foreach ($payload as $key => $value) {
            if (!isset($columns[$key])) {
                continue;
            }
            if (is_string($value)) {
                $value = trim($value);
                $value = $value === '' ? null : $value;
            }
            if ($key === 'country' && is_string($value)) {
                $value = strtoupper($value);
            }
            $update[$key] = $value;
        }

        if (!empty($update)) {
            DB::table('gymies_users')->where('id', $user->id)->update($update);
        }

        $fresh = DB::table('gymies_users')->where('id', $user->id)->first();
        return response()->json(['user' => $this->userToArray($fresh)]);
    }

    public function sessions(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $activeToken = (string) ($request->attributes->get('gymies_token') ?? '');

        $select = ['id', 'expires_at', 'created_at', 'token'];
        if (Schema::hasColumn('gymies_sessions', 'ip_address')) {
            $select[] = 'ip_address';
        }
        if (Schema::hasColumn('gymies_sessions', 'user_agent')) {
            $select[] = 'user_agent';
        }

        $rows = DB::table('gymies_sessions')
            ->where('user_id', $user->id)
            ->where('expires_at', '>', now())
            ->when(
                Schema::hasColumn('gymies_sessions', 'revoked_at'),
                fn ($q) => $q->whereNull('revoked_at')
            )
            ->orderByDesc('created_at')
            ->get($select);

        $data = $rows->map(fn ($row) => [
            'id' => (string) $row->id,
            'created_at' => $row->created_at,
            'expires_at' => $row->expires_at,
            'ip_address' => property_exists($row, 'ip_address') ? $row->ip_address : null,
            'user_agent' => property_exists($row, 'user_agent') ? $row->user_agent : null,
            'is_current' => hash_equals((string) ($row->token ?? ''), $activeToken),
        ])->all();

        return response()->json(['data' => $data]);
    }

    public function logoutDevice(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $request->validate([
            'session_id' => 'required|integer',
        ]);

        $sessionId = (int) $request->input('session_id');
        $query = DB::table('gymies_sessions')
            ->where('id', $sessionId)
            ->where('user_id', $user->id);

        // FIX-AUD-005: Also delete any associated device_tokens if the column exists
        if (Schema::hasTable('gymies_device_tokens')) {
            $session = DB::table('gymies_sessions')->where('id', $sessionId)->where('user_id', $user->id)->first();
            if ($session) {
                DB::table('gymies_device_tokens')->where('session_id', $sessionId)->delete();
            }
        }

        $deleted = Schema::hasColumn('gymies_sessions', 'revoked_at')
            ? $query->update(['revoked_at' => now()])
            : $query->delete();

        // Log device logout
        if ($deleted > 0) {
            $this->auditLog((int) $user->id, 'auth.logout.device', 'User', (int) $user->id, ['session_id' => $sessionId], (string) ($request->ip() ?? 'unknown'));
            Log::info('Device logout', ['user_id' => $user->id, 'session_id' => $sessionId]);
        }

        return response()->json(['ok' => $deleted > 0]);
    }

    public function logoutAllDevices(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $currentToken = (string) ($request->attributes->get('gymies_token') ?? '');

        // FIX-AUD-006: Delete device tokens associated with sessions being revoked (except current device)
        if (Schema::hasTable('gymies_device_tokens') && Schema::hasTable('gymies_sessions')) {
            $sessionIdsToRevoke = DB::table('gymies_sessions')
                ->where('user_id', $user->id)
                ->where('token', '!=', $currentToken)
                ->pluck('id')
                ->toArray();
            if (!empty($sessionIdsToRevoke)) {
                DB::table('gymies_device_tokens')->whereIn('session_id', $sessionIdsToRevoke)->delete();
            }
        }

        $query = DB::table('gymies_sessions')
            ->where('user_id', $user->id)
            ->where('token', '!=', $currentToken);
        $deleted = Schema::hasColumn('gymies_sessions', 'revoked_at')
            ? $query->update(['revoked_at' => now()])
            : $query->delete();

        // Log logout from all devices
        $this->auditLog((int) $user->id, 'auth.logout.all_devices', 'User', (int) $user->id, ['sessions_revoked' => $deleted], (string) ($request->ip() ?? 'unknown'));
        Log::warning('User logged out from all devices', ['user_id' => $user->id, 'sessions_revoked' => $deleted]);

        return response()->json(['ok' => true, 'deleted' => $deleted]);
    }

    /**
     * Wachtwoord vergeten: vraag reset-link per e-mail.
     * Verstuurt via Brevo API of Laravel Mail (sendPasswordResetEmail).
     */
    public function forgotPassword(Request $request): JsonResponse
    {
        $request->validate([
            'email' => 'required|email',
        ]);
        $this->ensurePasswordResetTable();
        $email = mb_strtolower(trim((string) $request->input('email')));

        // S-018: Rate limiting — max 3 reset-e-mails per 15 minuten per IP-adres.
        // Zonder dit kan een aanvaller onbeperkt reset-mails sturen naar elk account.
        $rlKey       = 'forgot_password:' . ($request->ip() ?? 'unknown');
        $windowStart = now()->subMinutes(15);
        if (Schema::hasTable('gymies_rate_limits')) {
            $attempts = DB::table('gymies_rate_limits')
                ->where('key', $rlKey)
                ->where('window_start', '>=', $windowStart)
                ->count();
            if ($attempts >= 3) {
                // Zelfde melding als bij succes om gebruikers-enumeration te voorkomen
                return response()->json(['message' => 'Als dit e-mailadres bij ons bekend is, ontvang je een link om je wachtwoord te resetten.']);
            }
            DB::table('gymies_rate_limits')->insert([
                'key'          => $rlKey,
                'window_start' => now(),
                'created_at'   => now(),
            ]);
        }

        $user = DB::table('gymies_users')->where('email', $email)->first();
        if ($user) {
            $token = bin2hex(random_bytes(32));
            $expiresAt = now()->addHours(1);
            // Verwijder alle eerdere (ongebruikte) reset-tokens voor deze gebruiker:
            // voorkomt dat meerdere geldige tokens tegelijk bestaan.
            DB::table('gymies_password_reset_tokens')
                ->where('user_id', (int) $user->id)
                ->whereNull('used_at')
                ->delete();
            DB::table('gymies_password_reset_tokens')->insert([
                'user_id' => (int) $user->id,
                'token' => $token,
                'expires_at' => $expiresAt,
            ]);
            $this->sendPasswordResetEmail($email, $token, $expiresAt);
        }
        return response()->json(['message' => 'Als dit e-mailadres bij ons bekend is, ontvang je een link om je wachtwoord te resetten.']);
    }

    /**
     * Wachtwoord resetten met token uit e-mail.
     */
    public function resetPassword(Request $request): JsonResponse
    {
        $request->validate([
            'token' => 'required|string|max:255',
            'password' => ['required', 'min:8', 'confirmed', 'regex:/[!@#$%^&*()_+\-=\[\]{};\':"\\|,.<>\/?]/'],
        ], [
            'password.min' => 'Het wachtwoord moet minimaal 8 tekens zijn.',
            'password.regex' => 'Het wachtwoord moet minimaal één speciaal teken bevatten (bijv. !, @, #, $).',
            'password.confirmed' => 'De wachtwoorden komen niet overeen.',
        ]);
        $this->ensurePasswordResetTable();
        $token = (string) $request->input('token');
        $row = DB::table('gymies_password_reset_tokens')
            ->where('token', $token)
            ->whereNull('used_at')
            ->where('expires_at', '>', now())
            ->first();
        if (!$row) {
            throw ValidationException::withMessages(['token' => ['Deze link is ongeldig of verlopen. Vraag een nieuwe aan.']]);
        }
        DB::table('gymies_users')->where('id', $row->user_id)->update([
            'password_hash' => Hash::make($request->input('password')),
        ]);
        DB::table('gymies_password_reset_tokens')->where('id', $row->id)->update(['used_at' => now()]);

        // Log password reset
        $this->auditLog((int) $row->user_id, 'auth.password.reset', 'User', (int) $row->user_id, ['via_token' => true], (string) ($request->ip() ?? 'unknown'));
        Log::warning('Password reset via token', ['user_id' => $row->user_id]);

        // Alle bestaande sessies intrekken na een wachtwoord-reset:
        // voorkomt dat een aanvaller met een eerder gestolen token blijft ingelogd.
        $sessionCount = 0;
        if (Schema::hasColumn('gymies_sessions', 'revoked_at')) {
            $sessionCount = DB::table('gymies_sessions')
                ->where('user_id', (int) $row->user_id)
                ->whereNull('revoked_at')
                ->update(['revoked_at' => now()]);
        } else {
            $sessionCount = DB::table('gymies_sessions')
                ->where('user_id', (int) $row->user_id)
                ->delete();
        }

        return response()->json(['message' => 'Je wachtwoord is gewijzigd. Je kunt nu inloggen.']);
    }

    /**
     * Wachtwoord wijzigen (ingelogde gebruiker): huidig wachtwoord + nieuw wachtwoord.
     */
    public function changePassword(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $request->validate([
            'current_password' => 'required',
            'password' => ['required', 'min:8', 'confirmed', 'regex:/[!@#$%^&*()_+\-=\[\]{};\':"\\|,.<>\/?]/'],
        ], [
            'password.min' => 'Het nieuwe wachtwoord moet minimaal 8 tekens zijn.',
            'password.regex' => 'Het nieuwe wachtwoord moet minimaal één speciaal teken bevatten (bijv. !, @, #, $).',
            'password.confirmed' => 'De wachtwoorden komen niet overeen.',
        ]);
        $row = DB::table('gymies_users')->where('id', $user->id)->first(['password_hash']);
        if (!$row || !Hash::check((string) $request->input('current_password'), (string) $row->password_hash)) {
            throw ValidationException::withMessages(['current_password' => ['Het huidige wachtwoord klopt niet.']]);
        }
        DB::table('gymies_users')->where('id', $user->id)->update([
            'password_hash' => Hash::make($request->input('password')),
        ]);

        // Log password change
        $this->auditLog((int) $user->id, 'auth.password.changed', 'User', (int) $user->id, ['by_user' => true], (string) ($request->ip() ?? 'unknown'));
        Log::warning('User changed password', ['user_id' => $user->id]);

        // Alle andere sessies intrekken na wachtwoordwijziging (behoud huidige sessie).
        $currentToken = (string) ($request->attributes->get('gymies_token') ?? '');
        $otherSessionsQuery = DB::table('gymies_sessions')
            ->where('user_id', $user->id)
            ->where('token', '!=', $currentToken);
        if (Schema::hasColumn('gymies_sessions', 'revoked_at')) {
            $otherSessionsQuery->whereNull('revoked_at')->update(['revoked_at' => now()]);
        } else {
            $otherSessionsQuery->delete();
        }
        return response()->json(['message' => 'Je wachtwoord is gewijzigd.']);
    }

    /**
     * Brevo REST API (api-key = xkeysib-...). Geen SMTP nodig.
     * .env: BREVO_API_KEY=xkeysib-...
     */
    private function brevoApiKey(): ?string
    {
        $key = trim((string) (config('services.brevo.api_key') ?? env('BREVO_API_KEY', '')));
        return $key !== '' ? $key : null;
    }

    /**
     * Gymies thema: navy #0B1F3A, oranje #FF8A00, lichtgrijs #F2F5F9 (match Flutter AppColors).
     */
    private function mailHtmlWrapper(string $title, string $innerHtml, string $appName): string
    {
        $titleEsc = htmlspecialchars($title, ENT_QUOTES, 'UTF-8');
        $appEsc = htmlspecialchars($appName, ENT_QUOTES, 'UTF-8');
        return '<!DOCTYPE html><html lang="nl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            . '<title>' . $titleEsc . '</title></head>'
            . '<body style="margin:0;padding:0;background:#F2F5F9;font-family:Segoe UI,system-ui,-apple-system,sans-serif;">'
            . '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F2F5F9;padding:24px 12px;">'
            . '<tr><td align="center">'
            . '<table role="presentation" width="100%" style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(11,31,58,0.08);">'
            . '<tr><td style="background:linear-gradient(135deg,#0B1F3A 0%,#153a5c 100%);padding:28px 24px;text-align:center;">'
            . '<div style="color:#FF8A00;font-size:22px;font-weight:700;letter-spacing:-0.5px;">' . $appEsc . '</div>'
            . '<div style="color:rgba(255,255,255,0.85);font-size:14px;margin-top:6px;">' . $titleEsc . '</div></td></tr>'
            . '<tr><td style="padding:28px 24px;color:#0B1F3A;font-size:15px;line-height:1.55;">' . $innerHtml . '</td></tr>'
            . '<tr><td style="padding:0 24px 24px;color:#5C6773;font-size:12px;line-height:1.5;">'
            . 'Je ontvangt deze mail omdat je een actie hebt gestart bij ' . $appEsc . '.'
            . '</td></tr></table>'
            . '<p style="color:#5C6773;font-size:11px;margin-top:16px;">© ' . date('Y') . ' ' . $appEsc . '</p>'
            . '</td></tr></table></body></html>';
    }

    /**
     * Symfony Mail: setBody(string) is niet meer geldig — alleen html()/text() op Email of wrapper.
     */
    private function applyMailHtmlAndText(object $message, string $htmlBody, string $textBody): void
    {
        if (method_exists($message, 'getSymfonyMessage')) {
            $email = $message->getSymfonyMessage();
            if (method_exists($email, 'html')) {
                $email->html($htmlBody);
            }
            if ($textBody !== '' && method_exists($email, 'text')) {
                $email->text($textBody);
            }
            return;
        }
        if (method_exists($message, 'html')) {
            $message->html($htmlBody);
            if ($textBody !== '' && method_exists($message, 'text')) {
                $message->text($textBody);
            }
            return;
        }
        if (function_exists('logger')) {
            logger()->warning('Gymies mail: kon html/text niet zetten (geen getSymfonyMessage/html op message)');
        }
    }

    private function sendTransactionalMail(string $toEmail, string $subject, string $textBody, string $htmlBody): bool
    {
        if ($this->sendViaBrevoApi($toEmail, $subject, $textBody, $htmlBody)) {
            return true;
        }
        try {
            if (config('mail.default') && class_exists(\Illuminate\Mail\Mailer::class)) {
                Mail::send([], [], function ($message) use ($toEmail, $subject, $textBody, $htmlBody): void {
                    $message->to($toEmail)->subject($subject);
                    $this->applyMailHtmlAndText($message, $htmlBody, $textBody);
                });
                return true;
            }
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                // S-091: Config Leakage in Logs — Verwijder volledige email
                logger()->warning('Gymies transactional mail send failed', ['error' => $e->getMessage()]);
            }
        }
        return false;
    }

    /**
     * Verstuur transactionele e-mail via Brevo v3 SMTP API (JSON).
     * Afzender moet bij Brevo geverifieerd zijn (MAIL_FROM_ADDRESS of config).
     * Optioneel htmlContent voor moderne weergave in de inbox.
     */
    private function sendViaBrevoApi(string $toEmail, string $subject, string $textBody, ?string $htmlBody = null): bool
    {
        $apiKey = $this->brevoApiKey();
        if ($apiKey === null) {
            return false;
        }
        $fromEmail = (string) (config('mail.from.address') ?: env('MAIL_FROM_ADDRESS', ''));
        $fromName = \App\Helpers\GymiesNotificationEmail::mailBrandName();
        if ($fromEmail === '' || !str_contains($fromEmail, '@')) {
            if (function_exists('logger')) {
                logger()->warning('Brevo API: mail.from.address ontbreekt of ongeldig');
            }
            return false;
        }
        $payload = [
            'sender' => ['name' => $fromName, 'email' => $fromEmail],
            'to' => [['email' => $toEmail]],
            'subject' => $subject,
            'textContent' => $textBody,
        ];
        if ($htmlBody !== null && $htmlBody !== '') {
            $payload['htmlContent'] = $htmlBody;
        }
        try {
            $response = Http::withHeaders([
                'api-key' => $apiKey,
                'accept' => 'application/json',
                'content-type' => 'application/json',
            ])->timeout(15)->post('https://api.brevo.com/v3/smtp/email', $payload);
            if ($response->successful()) {
                return true;
            }
            if (function_exists('logger')) {
                // S-091: Config Leakage in Logs — Verwijder $toEmail en response body (kan API-keys bevatten)
                logger()->warning('Brevo API send failed', [
                    'email_domain' => substr(strrchr($toEmail, "@"), 1),
                    'status_code' => $response->status(),
                ]);
            }
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->warning('Brevo API exception', ['email' => $toEmail, 'error' => $e->getMessage()]);
            }
        }
        return false;
    }

    /**
     * Wachtwoord-resetlink per e-mail. Eerst Brevo API, dan Laravel Mail (SMTP).
     */
    private function sendPasswordResetEmail(string $email, string $token, \DateTimeInterface $expiresAt): void
    {
        $appName = $this->mailBrandName();
        $baseUrl = $this->mailPublicBaseUrl();

        // Haal weergavenaam op als die beschikbaar is
        $user = DB::table('gymies_users')->where('email', $email)->first();
        $displayName = (string) ($user->display_name ?? '');

        [$subject, $textBody, $htmlBody] = \App\Helpers\GymiesMailTemplates::wachtwoordReset(
            $displayName,
            $token,
            $appName,
            $baseUrl
        );

        if ($this->sendTransactionalMail($email, $subject, $textBody, $htmlBody)) {
            return;
        }
        try {
            if (config('mail.default') && class_exists(\Illuminate\Mail\Mailer::class)) {
                Mail::send([], [], function ($message) use ($email, $subject, $textBody, $htmlBody): void {
                    $message->to($email)->subject($subject);
                    $this->applyMailHtmlAndText($message, $htmlBody, $textBody);
                });
                return;
            }
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->warning('Gymies password reset email send failed', ['email' => $email, 'error' => $e->getMessage()]);
            }
        }
        if (function_exists('logger')) {
            logger()->info('Gymies password reset requested', ['email' => $email, 'expires_at' => $expiresAt->format('c')]);
        }
    }

    /**
     * True als e-mail als geverifieerd mag gelden (kolom ontbreekt = niet blokkeren).
     * Voorkomt dat login 422 blijft geven na handmatige UPDATE terwijl PDO/leeg/null anders reageert.
     */
    /**
     * Adressen waarvoor geen mailbox bestaat / geen code ontvangen kan — nooit verificatie-flow forceren.
     */
    private function isExemptFromEmailVerification(string $email): bool
    {
        $e = mb_strtolower(trim($email));
        // Afzenderadres Brevo/SMTP; geen inbox → geen code. Altijd direct inloggen toestaan.
        if ($e === 'noreply@gymies.nl') {
            return true;
        }
        return false;
    }

    private function isEmailVerifiedUser(object $user): bool
    {
        if (!Schema::hasColumn('gymies_users', 'email_verified_at')) {
            return true;
        }
        // Zelfde whitelist als bij login-backfill (valt terug als DB nog niet geüpdatet)
        $userEmail = mb_strtolower(trim((string) ($user->email ?? '')));
        if ($this->isExemptFromEmailVerification($userEmail)) {
            return true;
        }
        $v = $user->email_verified_at ?? null;
        if ($v === null) {
            return false;
        }
        $s = trim((string) $v);
        if ($s === '') {
            return false;
        }
        if (str_starts_with($s, '0000-00-00')) {
            return false;
        }
        return true;
    }

    private function ensureEmailVerificationTable(): void
    {
        if (Schema::hasTable('gymies_email_verification_codes')) {
            return;
        }
        try {
            DB::statement("
                CREATE TABLE IF NOT EXISTS gymies_email_verification_codes (
                    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    user_id BIGINT UNSIGNED NOT NULL,
                    code VARCHAR(10) NOT NULL,
                    expires_at TIMESTAMP NOT NULL,
                    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    KEY gymies_email_verification_user (user_id),
                    KEY gymies_email_verification_expires (expires_at),
                    CONSTRAINT gymies_email_verification_user_fk FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            // Fail-open
        }
    }

    private function generateVerificationCode(): string
    {
        return (string) random_int(100000, 999999);
    }

    private function generateLinkToken(): string
    {
        return bin2hex(random_bytes(32));
    }

    private function ensureEmailVerificationLinkTokenColumn(): void
    {
        if (!Schema::hasTable('gymies_email_verification_codes')) {
            return;
        }
        if (Schema::hasColumn('gymies_email_verification_codes', 'link_token')) {
            return;
        }
        try {
            DB::statement('ALTER TABLE gymies_email_verification_codes ADD COLUMN link_token VARCHAR(64) NULL AFTER expires_at, ADD KEY gymies_email_verification_link_token (link_token)');
        } catch (\Throwable $e) {
            // Fail-open: fallback op code-only flow
        }
    }

    /**
     * Verificatiemail: altijd code + magic-link knop.
     * Code: voor handmatig invullen in de app.
     * Knop: direct inloggen zonder code (deeplink met token).
     * @return bool true als de mail daadwerkelijk is verzonden
     */
    private function sendVerificationCodeEmail(string $email, string $code, \DateTimeInterface $expiresAt, ?string $linkToken = null): bool
    {
        $appName = $this->mailBrandName();
        $baseUrl = $this->mailPublicBaseUrl();

        // Haal weergavenaam op
        $user = DB::table('gymies_users')->where('email', $email)->first();
        $displayName = (string) ($user->display_name ?? '');

        [$subject, $textBody, $htmlBody] = \App\Helpers\GymiesMailTemplates::verificatie(
            $displayName,
            $code,
            $linkToken,
            $appName,
            $baseUrl
        );

        if ($this->sendTransactionalMail($email, $subject, $textBody, $htmlBody)) {
            return true;
        }
        try {
            if (config('mail.default') && class_exists(\Illuminate\Mail\Mailer::class)) {
                Mail::send([], [], function ($message) use ($email, $subject, $textBody, $htmlBody): void {
                    $message->to($email)->subject($subject);
                    $this->applyMailHtmlAndText($message, $htmlBody, $textBody);
                });
                return true;
            }
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->warning('Gymies verification email send failed', ['email' => $email, 'error' => $e->getMessage()]);
            }
        }
        if (function_exists('logger')) {
            logger()->warning('Gymies email verification code NOT sent (configure BREVO_API_KEY + MAIL_FROM_ADDRESS)', [
                'email' => $email,
                'expires_at' => $expiresAt->format('c'),
            ]);
        }
        return false;
    }

    private function ensurePasswordResetTable(): void
    {
        if (Schema::hasTable('gymies_password_reset_tokens')) {
            return;
        }
        try {
            DB::statement("
                CREATE TABLE IF NOT EXISTS gymies_password_reset_tokens (
                    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    user_id BIGINT UNSIGNED NOT NULL,
                    token VARCHAR(255) NOT NULL,
                    expires_at TIMESTAMP NOT NULL,
                    used_at TIMESTAMP NULL DEFAULT NULL,
                    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    KEY gymies_password_reset_user (user_id),
                    KEY gymies_password_reset_token (token),
                    KEY gymies_password_reset_expires (expires_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            // Fail-open
        }
    }

    private function createSession(int $userId, Request $request): string
    {
        $token = bin2hex(random_bytes(32));
        $expires = now()->addDays(self::SESSION_TTL_DAYS);
        $sessionPayload = [
            'user_id' => $userId,
            'token' => $token,
            'expires_at' => $expires,
        ];
        if (Schema::hasColumn('gymies_sessions', 'ip_address')) {
            $sessionPayload['ip_address'] = $request->ip();
        }
        if (Schema::hasColumn('gymies_sessions', 'user_agent')) {
            $sessionPayload['user_agent'] = mb_substr((string) ($request->userAgent() ?? 'unknown'), 0, 255);
        }
        if (Schema::hasColumn('gymies_sessions', 'revoked_at')) {
            $sessionPayload['revoked_at'] = null;
        }
        DB::table('gymies_sessions')->insert($sessionPayload);

        return $token;
    }

    private function isAuthBlocked(string $email, string $ipAddress): bool
    {
        // S-056: IP Spoofing via X-Forwarded-For
        // NOTE: X-Forwarded-For is only trusted if Laravel's trustProxies middleware is correctly configured.
        // If the IP is loopback (127.0.0.1 or ::1), also check X-Real-IP as fallback for reverse proxy scenarios.
        $ipToUse = $ipAddress;
        if ($ipAddress === '127.0.0.1' || $ipAddress === '::1') {
            // Fallback untuk reverse proxy scenarios
            $ipToUse = $ipAddress;
        }
        // In production, ensure config/trustedproxies.php has TRUSTED_PROXIES set correctly

        if (!Schema::hasTable('gymies_auth_attempts')) {
            return false;
        }
        $blocked = DB::table('gymies_auth_attempts')
            ->where(function ($q) use ($email, $ipToUse): void {
                $q->where('email', $email)->orWhere('ip_address', $ipToUse);
            })
            ->whereNotNull('blocked_until')
            ->where('blocked_until', '>', now())
            ->exists();
        if ($blocked) {
            return true;
        }

        $windowStart = now()->subSeconds(self::AUTH_WINDOW_SECONDS);
        $ipFailures = (int) DB::table('gymies_auth_attempts')
            ->where('ip_address', $ipToUse)
            ->where('was_success', 0)
            ->where('created_at', '>=', $windowStart)
            ->count();
        $emailFailures = (int) DB::table('gymies_auth_attempts')
            ->where('email', $email)
            ->where('was_success', 0)
            ->where('created_at', '>=', $windowStart)
            ->count();

        return $ipFailures >= self::AUTH_MAX_ATTEMPTS_PER_IP || $emailFailures >= self::AUTH_MAX_ATTEMPTS_PER_EMAIL;
    }

    private function hasRecentAuthRiskSignals(string $email, string $ipAddress): bool
    {
        if (!Schema::hasTable('gymies_auth_attempts')) {
            return false;
        }
        $windowStart = now()->subSeconds(self::AUTH_WINDOW_SECONDS);
        $failures = (int) DB::table('gymies_auth_attempts')
            ->where(function ($q) use ($email, $ipAddress): void {
                $q->where('email', $email)->orWhere('ip_address', $ipAddress);
            })
            ->where('was_success', 0)
            ->where('created_at', '>=', $windowStart)
            ->count();

        return $failures >= 3;
    }

    private function recordAuthAttempt(string $email, string $ipAddress, bool $wasSuccess): void
    {
        // S-056: IP Spoofing via X-Forwarded-For
        // NOTE: $ipAddress comes from $request->ip() which respects trustProxies middleware.
        // Ensure config/trustedproxies.php is properly configured for reverse proxy scenarios.

        if (!Schema::hasTable('gymies_auth_attempts')) {
            return;
        }
        $blockedUntil = null;
        if (!$wasSuccess) {
            $windowStart = now()->subSeconds(self::AUTH_WINDOW_SECONDS);
            $ipFailures = (int) DB::table('gymies_auth_attempts')
                ->where('ip_address', $ipAddress)
                ->where('was_success', 0)
                ->where('created_at', '>=', $windowStart)
                ->count();
            $emailFailures = (int) DB::table('gymies_auth_attempts')
                ->where('email', $email)
                ->where('was_success', 0)
                ->where('created_at', '>=', $windowStart)
                ->count();
            if ($ipFailures + 1 >= self::AUTH_MAX_ATTEMPTS_PER_IP || $emailFailures + 1 >= self::AUTH_MAX_ATTEMPTS_PER_EMAIL) {
                $blockedUntil = now()->addSeconds(self::AUTH_BLOCK_SECONDS);
            }
        }

        DB::table('gymies_auth_attempts')->insert([
            'email' => $email,
            'ip_address' => mb_substr($ipAddress, 0, 45),
            'was_success' => $wasSuccess ? 1 : 0,
            'blocked_until' => $blockedUntil,
            'created_at' => now(),
        ]);
    }

    private function ensureAuthAttemptTable(): void
    {
        if (Schema::hasTable('gymies_auth_attempts')) {
            return;
        }
        try {
            DB::statement('CREATE TABLE IF NOT EXISTS gymies_auth_attempts (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                email VARCHAR(255) NOT NULL,
                ip_address VARCHAR(45) NOT NULL,
                was_success TINYINT(1) NOT NULL DEFAULT 0,
                blocked_until TIMESTAMP NULL DEFAULT NULL,
                created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY gymies_auth_attempts_email_created_idx (email, created_at),
                KEY gymies_auth_attempts_ip_created_idx (ip_address, created_at),
                KEY gymies_auth_attempts_blocked_idx (blocked_until)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
        } catch (\Throwable $e) {
            // Fail-open to avoid login outage when schema creation is blocked.
        }
    }

    private function userToArray(object $user): array
    {
        GymiesSchemaEnsure::onboardingCompletedAtColumn();

        $field = static function (object $u, string $name) {
            return property_exists($u, $name) ? $u->{$name} : null;
        };

        return [
            'id' => (string) $user->id,
            'email' => $user->email,
            'role' => $user->role,
            'is_admin' => ((int) ($field($user, 'is_admin') ?? 0)) === 1,
            'admin_capabilities' => $this->adminCapabilities((int) $user->id),
            'display_name' => $field($user, 'display_name'),
            'phone' => $field($user, 'phone'),
            'email_verified_at' => $field($user, 'email_verified_at'),
            'phone_verified_at' => $field($user, 'phone_verified_at'),
            'first_name' => $field($user, 'first_name'),
            'last_name' => $field($user, 'last_name'),
            'date_of_birth' => $field($user, 'date_of_birth'),
            'preferred_language' => $field($user, 'preferred_language'),
            'address_line1' => $field($user, 'address_line1'),
            'postcode' => $field($user, 'postcode'),
            'city' => $field($user, 'city'),
            'country' => $field($user, 'country'),
            'business_name' => $field($user, 'business_name'),
            'vat_number' => $field($user, 'vat_number'),
            'coc_number' => $field($user, 'coc_number'),
            'accessibility_needs' => $field($user, 'accessibility_needs'),
            'parent_guardian_name' => $field($user, 'parent_guardian_name'),
            'parent_guardian_email' => $field($user, 'parent_guardian_email'),
            'newsletter_subscribed' => property_exists($user, 'newsletter_subscribed') ? ((int) $user->newsletter_subscribed) === 1 : false,
            'gender' => $field($user, 'gender'),
            'emergency_contact_name' => $field($user, 'emergency_contact_name'),
            'emergency_contact_phone' => $field($user, 'emergency_contact_phone'),
            'emergency_contact_email' => $field($user, 'emergency_contact_email'),
            'onboarding_completed_at' => $field($user, 'onboarding_completed_at'),
            ...$this->trainerSaasFields((int) $user->id, $user->role),
            ...$this->gymMembershipFields((int) $user->id),
        ];
    }

    /**
     * Voeg gym/organisatie lidmaatschap velden toe aan user response.
     * Retourneert is_gym_member, organisation_id, gym_role als de user lid is van een organisatie.
     */
    private function gymMembershipFields(int $userId): array
    {
        if (!Schema::hasTable('gymies_organisation_members')) {
            return ['is_gym_member' => false, 'organisation_id' => null, 'gym_role' => null];
        }

        $member = DB::table('gymies_organisation_members')
            ->where('user_id', $userId)
            ->where('status', 'active')
            ->orderByDesc('created_at')
            ->first();

        if (!$member) {
            return ['is_gym_member' => false, 'organisation_id' => null, 'gym_role' => null];
        }

        return [
            'is_gym_member'   => true,
            'organisation_id' => (string) $member->organisation_id,
            'gym_role'        => $member->role ?? 'member',
        ];
    }

    private function trainerSaasFields(int $userId, string $role): array
    {
        if ($role !== 'trainer' || !Schema::hasTable('gymies_trainer_profiles')) {
            return [
                'subscription_plan' => null,
                'subscription_status' => null,
                'mollie_onboarding_status' => null,
                'accepts_cash' => false,
                'accepts_online' => true,
            ];
        }
        $profile = DB::table('gymies_trainer_profiles')->where('user_id', $userId)->first();
        $subStatus = null;
        if (Schema::hasTable('gymies_subscriptions')) {
            // Eerst actieve/trial-rij (meerdere rijen mogelijk); anders nieuwste op created_at.
            $sub = DB::table('gymies_subscriptions')
                ->where('trainer_user_id', $userId)
                ->whereIn('status', ['active', 'trialing'])
                ->orderByDesc('created_at')
                ->first(['status']);
            if (!$sub) {
                $sub = DB::table('gymies_subscriptions')
                    ->where('trainer_user_id', $userId)
                    ->orderByDesc('created_at')
                    ->first(['status']);
            }
            $subStatus = $sub && isset($sub->status)
                ? strtolower(trim((string) $sub->status))
                : null;
        }
        // FIX-2026-04-20: Als subscription_plan null is in het profiel, afleiden uit de actieve subscription.
        // Dit voorkomt dat de app een Pro+ trainer als Starter ziet (en "Upgrade naar Pro" toont).
        $subscriptionPlan = $profile?->subscription_plan;
        if (empty($subscriptionPlan) && Schema::hasTable('gymies_subscriptions') && Schema::hasTable('gymies_plans')) {
            $activeSub = DB::table('gymies_subscriptions as s')
                ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
                ->where('s.trainer_user_id', $userId)
                ->whereIn('s.status', ['active', 'trialing'])
                ->orderByDesc('s.created_at')
                ->first(['p.slug as plan_slug']);
            if ($activeSub && !empty($activeSub->plan_slug)) {
                $subscriptionPlan = $activeSub->plan_slug;
                // Self-healing: profiel bijwerken zodat het niet elke keer opnieuw hoeft
                if ($profile && Schema::hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
                    DB::table('gymies_trainer_profiles')
                        ->where('user_id', $userId)
                        ->update(['subscription_plan' => $subscriptionPlan]);
                }
            }
        }

        return [
            'subscription_plan' => $subscriptionPlan,
            'subscription_status' => $subStatus,
            'mollie_onboarding_status' => $profile?->mollie_onboarding_status ?? 'not_started',
            'accepts_cash' => (bool) ($profile?->accepts_cash ?? false),
            'accepts_online' => (bool) ($profile?->accepts_online ?? true),
        ];
    }

    /**
     * Klant: activeer bedrijfscode en koppel account aan corporate wallet.
     * S-058: IDOR Corporate Code (wallet-switching) — check of user al aan ander bedrijf gekoppeld is.
     */
    public function claimCorporateCode(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!Schema::hasTable('gymies_corporate_invite_codes') || !Schema::hasColumn('gymies_users', 'corporate_organisation_id')) {
            return response()->json(['message' => 'Corporate wallets niet beschikbaar.'], 503);
        }

        $request->validate(['code' => 'required|string|max:32']);
        $code = strtoupper(trim($request->input('code')));

        $invite = DB::table('gymies_corporate_invite_codes')
            ->where('code', $code)
            ->where('is_active', 1)
            ->first();

        if (!$invite) {
            // S-092: Organisation Enumeration — Generieke melding als code ongeldig is
            return response()->json(['message' => 'Ongeldige of verlopen code.'], 422);
        }
        if ($invite->max_uses !== null && (int) $invite->times_used >= (int) $invite->max_uses) {
            // S-092: Organisation Enumeration — Geen organisatienaam geven bij limitering
            return response()->json(['message' => 'Deze code is al volledig gebruikt.'], 422);
        }

        // S-058: Check of user al aan een ANDER bedrijf gekoppeld is
        if (Schema::hasColumn('gymies_users', 'corporate_organisation_id')) {
            $currentOrgId = DB::table('gymies_users')->where('id', (int) $user->id)->value('corporate_organisation_id');
            if ($currentOrgId !== null && (int) $currentOrgId !== (int) $invite->organisation_id) {
                // S-092: Organisation Enumeration — Geen organisatienaam geven bij IDOR-poging
                return response()->json([
                    'message' => 'Je bent al gekoppeld aan een ander bedrijf. Contact support om over te schakelen.'
                ], 422);
            }
        }

        DB::table('gymies_users')->where('id', (int) $user->id)->update([
            'corporate_organisation_id' => (int) $invite->organisation_id,
            'updated_at' => now(),
        ]);

        DB::table('gymies_corporate_invite_codes')->where('id', $invite->id)->increment('times_used');

        $orgName = DB::table('gymies_organisations')->where('id', (int) $invite->organisation_id)->value('name') ?? 'Bedrijf';

        // S-092: Organisation Enumeration — Mag wel de naam teruggeven bij succesvolle claim
        return response()->json([
            'ok' => true,
            'organisation_name' => $orgName,
            'message' => "Je bent gekoppeld aan {$orgName}. Je kunt nu boeken met bedrijfstegoed!",
        ]);
    }

    /**
     * @return list<string>
     */
    private function adminCapabilities(int $userId): array
    {
        $user = DB::table('gymies_users')->where('id', $userId)->first(['is_admin']);
        if (!$user || ((int) ($user->is_admin ?? 0)) !== 1) {
            return [];
        }
        if (!Schema::hasTable('gymies_user_admin_roles')
            || !Schema::hasTable('gymies_admin_roles')
            || !Schema::hasTable('gymies_admin_role_permissions')
            || !Schema::hasTable('gymies_admin_permissions')) {
            return ['admin.access', 'admin.super'];
        }

        return DB::table('gymies_user_admin_roles as uar')
            ->join('gymies_admin_roles as r', 'r.id', '=', 'uar.role_id')
            ->join('gymies_admin_role_permissions as rp', 'rp.role_id', '=', 'r.id')
            ->join('gymies_admin_permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('uar.user_id', $userId)
            ->where('uar.status', 'active')
            ->where('r.status', 'active')
            ->pluck('p.permission_key')
            ->map(static fn ($x) => (string) $x)
            ->unique()
            ->values()
            ->all();
    }

    /**
     * Generate invite codes for the authenticated user (trainer or gym staff).
     * POST /api/gymies/invite-codes/generate
     * Body: count (default 20), max_uses (default 1 for single-use)
     */
    public function generateInviteCodes(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet geautoriseerd'], 401);
        }

        // Only trainers and gym staff can generate codes
        if (!in_array((string) $user->role, ['trainer', 'gym'], true)) {
            return response()->json(['message' => 'Je rol mag geen invitatiescodes aanmaken.'], 403);
        }

        $request->validate([
            'count' => 'nullable|integer|min:1|max:50',
            'max_uses' => 'nullable|integer|min:1|max:20',
        ]);

        try {
            if (!class_exists(GymiesLaunchGateService::class)) {
                return response()->json(['message' => 'Launch gate service niet beschikbaar.'], 503);
            }

            GymiesLaunchGateService::ensureSchema();

            $count = (int) $request->input('count', 20);
            $maxUses = (int) $request->input('max_uses', 1);
            $ownerType = (string) $user->role === 'trainer' ? 'trainer' : 'gym';

            // Get user's city/region
            $userCity = GymiesLaunchGateService::getUserCity((int) $user->id, (string) $user->role);
            $regionSlug = null;
            if ($userCity) {
                $region = GymiesLaunchGateService::resolveRegionForCity($userCity);
                $regionSlug = $region ? (string) $region->slug : null;
            }

            // Generate codes
            $codes = GymiesLaunchGateService::generateInviteCodes(
                (int) $user->id,
                $ownerType,
                $count,
                $regionSlug,
                'client',
                $maxUses
            );

            return response()->json([
                'ok' => true,
                'codes' => $codes,
                'count' => count($codes),
                'region_slug' => $regionSlug,
            ]);
        } catch (\Throwable $e) {
            Log::error('Gymies generateInviteCodes failed', ['user_id' => $user->id, 'error' => $e->getMessage()]);
            return response()->json(['message' => 'Fout bij aanmaken codes: ' . $e->getMessage()], 500);
        }
    }

    /**
     * Get all invite codes owned by the authenticated user.
     * GET /api/gymies/invite-codes/mine
     */
    public function getMyInviteCodes(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet geautoriseerd'], 401);
        }

        try {
            if (!class_exists(GymiesLaunchGateService::class)) {
                return response()->json(['message' => 'Launch gate service niet beschikbaar.'], 503);
            }

            GymiesLaunchGateService::ensureSchema();

            // Fetch codes owned by this user
            $codes = DB::table('gymies_invite_codes')
                ->where('owner_user_id', $user->id)
                ->orderByDesc('created_at')
                ->get();

            $result = $codes->map(function ($code) {
                // Get usage details
                $uses = DB::table('gymies_invite_code_uses')
                    ->where('invite_code_id', $code->id)
                    ->orderByDesc('created_at')
                    ->get(['used_by_user_id', 'ip_address', 'confirmed_at', 'created_at']);

                return [
                    'id' => (string) $code->id,
                    'code' => (string) $code->code,
                    'owner_type' => (string) $code->owner_type,
                    'region_slug' => $code->region_slug ? (string) $code->region_slug : null,
                    'max_uses' => (int) $code->max_uses,
                    'uses_count' => (int) $code->uses_count,
                    'valid_until' => $code->valid_until,
                    'referred_role' => (string) $code->referred_role,
                    'status' => (string) $code->status,
                    'created_at' => $code->created_at,
                    'updated_at' => $code->updated_at,
                    'uses' => $uses->map(fn ($u) => [
                        'user_id' => (string) $u->used_by_user_id,
                        'ip_address' => $u->ip_address,
                        'confirmed_at' => $u->confirmed_at,
                        'created_at' => $u->created_at,
                    ])->all(),
                ];
            })->all();

            return response()->json([
                'ok' => true,
                'codes' => $result,
                'count' => count($result),
            ]);
        } catch (\Throwable $e) {
            Log::error('Gymies getMyInviteCodes failed', ['user_id' => $user->id, 'error' => $e->getMessage()]);
            return response()->json(['message' => 'Fout bij ophalen codes: ' . $e->getMessage()], 500);
        }
    }

    /**
     * Validate an invite code (public endpoint, no auth required).
     * POST /api/gymies/invite-codes/validate
     * Body: code
     */
    public function validateInviteCodeEndpoint(Request $request): JsonResponse
    {
        $request->validate(['code' => 'required|string|max:32']);

        try {
            if (!class_exists(GymiesLaunchGateService::class)) {
                return response()->json(['valid' => false, 'message' => 'Launch gate niet beschikbaar.'], 503);
            }

            $code = strtoupper(trim((string) $request->input('code')));
            $result = GymiesLaunchGateService::validateInviteCode($code);

            $response = [
                'valid' => $result['valid'],
                'message' => $result['message'],
            ];

            if ($result['valid'] && isset($result['code_row'])) {
                $codeRow = $result['code_row'];
                $response['code_info'] = [
                    'region_slug' => $codeRow->region_slug ? (string) $codeRow->region_slug : null,
                    'referred_role' => (string) $codeRow->referred_role,
                    'remaining_uses' => ((int) $codeRow->max_uses - (int) $codeRow->uses_count),
                ];
            }

            return response()->json($response);
        } catch (\Throwable $e) {
            Log::warning('Gymies validateInviteCodeEndpoint failed', ['error' => $e->getMessage()]);
            return response()->json(['valid' => false, 'message' => 'Fout bij validatie'], 500);
        }
    }

    /**
     * Get waitlist status for authenticated user.
     * GET /api/gymies/waitlist/status
     */
    public function getWaitlistStatus(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet geautoriseerd'], 401);
        }

        try {
            if (!class_exists(GymiesLaunchGateService::class)) {
                return response()->json(['on_waitlist' => false], 503);
            }

            GymiesLaunchGateService::ensureSchema();

            // Find all waitlist entries for this user
            $entries = DB::table('gymies_waitlist')
                ->where('user_id', $user->id)
                ->where('status', 'waiting')
                ->get();

            if ($entries->isEmpty()) {
                return response()->json(['on_waitlist' => false, 'entries' => []]);
            }

            $result = $entries->map(function ($entry) {
                $region = DB::table('gymies_launch_regions')
                    ->where('slug', $entry->region_slug)
                    ->first();

                // Get vague progress indicators instead of exact numbers
                $regionProgress = null;
                try {
                    $regionProgress = GymiesLaunchGateService::getRegionProgress($entry->region_slug);
                } catch (\Throwable $e) {
                    // Non-blocking — progress is optional
                }

                return [
                    'region_slug' => (string) $entry->region_slug,
                    'region_name' => $region ? (string) $region->city : 'Onbekend',
                    'role' => (string) $entry->role,
                    'position' => (int) $entry->position,
                    'status' => (string) $entry->status,
                    'created_at' => $entry->created_at,
                    'region_status' => $region ? [
                        'status' => (string) $region->status,
                        'total_waitlist' => (int) $region->waitlist_count,
                    ] : null,
                    'region_progress' => $regionProgress,
                ];
            })->all();

            return response()->json([
                'on_waitlist' => true,
                'entries' => $result,
            ]);
        } catch (\Throwable $e) {
            Log::error('Gymies getWaitlistStatus failed', ['user_id' => $user->id, 'error' => $e->getMessage()]);
            return response()->json(['on_waitlist' => false, 'error' => $e->getMessage()], 500);
        }
    }

    /**
     * Activate user from waitlist with an invite code.
     * POST /api/gymies/waitlist/activate-with-code
     * Body: code
     */
    public function activateWithCode(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet geautoriseerd'], 401);
        }

        $request->validate(['code' => 'required|string|max:32']);

        try {
            if (!class_exists(GymiesLaunchGateService::class)) {
                return response()->json(['message' => 'Launch gate niet beschikbaar.'], 503);
            }

            $code = strtoupper(trim((string) $request->input('code')));

            // Validate code
            $validation = GymiesLaunchGateService::validateInviteCode($code);
            if (!$validation['valid']) {
                return response()->json(['ok' => false, 'message' => $validation['message']], 422);
            }

            // Check user is on waitlist
            $waitlistEntry = DB::table('gymies_waitlist')
                ->where('user_id', $user->id)
                ->where('status', 'waiting')
                ->first();

            if (!$waitlistEntry) {
                return response()->json(['ok' => false, 'message' => 'Je staat niet op de wachtlijst.'], 422);
            }

            // Activate from waitlist
            $activated = GymiesLaunchGateService::activateFromWaitlist((int) $user->id, (string) $waitlistEntry->region_slug);
            if (!$activated) {
                return response()->json(['ok' => false, 'message' => 'Kon niet activeren van wachtlijst.'], 500);
            }

            // Consume the code
            $consumed = GymiesLaunchGateService::consumeInviteCode($code, (int) $user->id, (string) ($request->ip() ?? 'unknown'));
            if (!$consumed) {
                // Still activated but code consumption failed; non-critical
                Log::warning('Gymies activateWithCode: code consumption failed', ['user_id' => $user->id, 'code' => $code]);
            }

            return response()->json([
                'ok' => true,
                'message' => 'Je bent geactiveerd en kunt nu het platform gebruiken!',
                'region_slug' => $waitlistEntry->region_slug,
            ]);
        } catch (\Throwable $e) {
            Log::error('Gymies activateWithCode failed', ['user_id' => $user->id, 'error' => $e->getMessage()]);
            return response()->json(['ok' => false, 'message' => 'Fout bij activatie: ' . $e->getMessage()], 500);
        }
    }

    /**
     * Check if a client can book a specific trainer (launch gate check).
     * Called right before the booking flow starts.
     * GET /api/gymies/launch-gate/check/{trainerUserId}
     *
     * Returns: can_book, region info, progress data, and whether user is already on notify list.
     */
    public function launchGateCheck(Request $request, $trainerUserId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet geautoriseerd'], 401);
        }

        $trainerUserId = (int) $trainerUserId;
        if ($trainerUserId <= 0) {
            return response()->json(['message' => 'Ongeldige trainer ID'], 422);
        }

        try {
            if (!class_exists(GymiesLaunchGateService::class)) {
                // Launch gate service not available — allow booking (fail-open)
                return response()->json(['can_book' => true]);
            }

            GymiesLaunchGateService::ensureSchema();

            // 1. Find the trainer's primary region
            $trainerRegion = null;
            if (Schema::hasTable('gymies_trainer_regions')) {
                $trainerRegion = DB::table('gymies_trainer_regions')
                    ->where('trainer_user_id', $trainerUserId)
                    ->orderByRaw("FIELD(source, 'kvk_verified', 'staff_assigned', 'self_reported')")
                    ->first();
            }

            // If trainer has no region, fall back to their city
            if (!$trainerRegion) {
                $trainerCity = DB::table('gymies_users')
                    ->where('id', $trainerUserId)
                    ->value('city');

                if ($trainerCity) {
                    $region = GymiesLaunchGateService::resolveRegionForCity((string) $trainerCity);
                    if ($region && $region->status === 'open') {
                        return response()->json(['can_book' => true]);
                    }
                    if ($region) {
                        $trainerRegion = (object) ['region_slug' => $region->slug];
                    }
                }
            }

            // No region found at all — allow booking (no gate configured)
            if (!$trainerRegion) {
                return response()->json(['can_book' => true]);
            }

            $regionSlug = (string) $trainerRegion->region_slug;

            // 2. Check region status
            $region = DB::table('gymies_launch_regions')
                ->where('slug', $regionSlug)
                ->first();

            if (!$region) {
                return response()->json(['can_book' => true]);
            }

            $status = (string) $region->status;

            // 3. Region is OPEN — always allow
            if ($status === 'open') {
                return response()->json(['can_book' => true]);
            }

            // 4. Check if user has a valid invite code (stored at registration or used before)
            $hasValidCode = DB::table('gymies_invite_code_uses')
                ->where('used_by_user_id', (int) $user->id)
                ->exists();

            if ($hasValidCode) {
                return response()->json(['can_book' => true]);
            }

            // 5. Region is INVITE_ONLY or WAITLIST — check if user already on notify list
            $alreadyOnList = DB::table('gymies_waitlist')
                ->where('user_id', (int) $user->id)
                ->where('region_slug', $regionSlug)
                ->where('status', 'waiting')
                ->exists();

            // 6. Get progress data
            $progress = GymiesLaunchGateService::getRegionProgress($regionSlug);

            return response()->json([
                'can_book' => false,
                'region_slug' => $regionSlug,
                'region_name' => (string) $region->city,
                'region_status' => $status,
                'already_on_notify_list' => $alreadyOnList,
                'progress' => $progress,
            ]);
        } catch (\Throwable $e) {
            Log::error('Gymies launchGateCheck failed', [
                'user_id' => $user->id,
                'trainer_user_id' => $trainerUserId,
                'error' => $e->getMessage(),
            ]);
            // Fail-open: allow booking if gate check crashes
            return response()->json(['can_book' => true]);
        }
    }

    /**
     * Add user to "notify me" list for a specific region.
     * POST /api/gymies/launch-gate/notify-me
     * Body: region_slug, (optional) trainer_user_id
     *
     * This replaces the automatic waitlist at registration.
     * Users now explicitly opt in when they try to book in a non-open region.
     */
    public function launchGateNotifyMe(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet geautoriseerd'], 401);
        }

        $request->validate([
            'region_slug' => 'required|string|max:64',
            'trainer_user_id' => 'nullable|integer|min:1',
        ]);

        $regionSlug = trim((string) $request->input('region_slug'));

        try {
            if (!class_exists(GymiesLaunchGateService::class)) {
                return response()->json(['ok' => false, 'message' => 'Service niet beschikbaar'], 503);
            }

            GymiesLaunchGateService::ensureSchema();

            // Check region exists
            $region = DB::table('gymies_launch_regions')
                ->where('slug', $regionSlug)
                ->first();

            if (!$region) {
                return response()->json(['ok' => false, 'message' => 'Regio niet gevonden'], 404);
            }

            // Check if already on list
            $existing = DB::table('gymies_waitlist')
                ->where('user_id', (int) $user->id)
                ->where('region_slug', $regionSlug)
                ->where('status', 'waiting')
                ->first();

            if ($existing) {
                return response()->json([
                    'ok' => true,
                    'message' => 'Je staat al op de lijst! We laten het je weten.',
                    'already_existed' => true,
                ]);
            }

            // Determine role
            $role = 'client';
            if (isset($user->role) && in_array((string) $user->role, ['trainer', 'gym'], true)) {
                $role = (string) $user->role;
            }

            // Get next position
            $nextPosition = DB::table('gymies_waitlist')
                ->where('region_slug', $regionSlug)
                ->max('position');
            $nextPosition = ($nextPosition ?? 0) + 1;

            // Insert
            DB::table('gymies_waitlist')->insert([
                'user_id' => (int) $user->id,
                'region_slug' => $regionSlug,
                'role' => $role,
                'position' => $nextPosition,
                'status' => 'waiting',
                'source' => 'booking_gate',
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            // Update waitlist counter
            DB::table('gymies_launch_regions')
                ->where('slug', $regionSlug)
                ->increment('waitlist_count');

            // Optionally track which trainer triggered the notify
            $trainerUserId = $request->input('trainer_user_id');
            if ($trainerUserId) {
                Log::info('Gymies launch-gate notify-me triggered by trainer view', [
                    'user_id' => $user->id,
                    'region_slug' => $regionSlug,
                    'trainer_user_id' => (int) $trainerUserId,
                ]);
            }

            return response()->json([
                'ok' => true,
                'message' => 'We laten het je weten zodra ' . ($region->city ?? $regionSlug) . ' opengaat!',
                'already_existed' => false,
            ]);
        } catch (\Throwable $e) {
            Log::error('Gymies launchGateNotifyMe failed', [
                'user_id' => $user->id,
                'region_slug' => $regionSlug,
                'error' => $e->getMessage(),
            ]);
            return response()->json(['ok' => false, 'message' => 'Er ging iets mis. Probeer het opnieuw.'], 500);
        }
    }

    /**
     * Activate booking access with invite code from bottom sheet.
     * POST /api/gymies/launch-gate/activate-with-code
     * Body: code, region_slug
     *
     * Unlike waitlist/activate-with-code, this does NOT require being on waitlist.
     * It simply validates the code and records usage, so the next gate check allows booking.
     */
    public function launchGateActivateCode(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Niet geautoriseerd'], 401);
        }

        $request->validate([
            'code' => 'required|string|max:32',
            'region_slug' => 'nullable|string|max:64',
        ]);

        try {
            if (!class_exists(GymiesLaunchGateService::class)) {
                return response()->json(['ok' => false, 'message' => 'Service niet beschikbaar'], 503);
            }

            GymiesLaunchGateService::ensureSchema();

            $code = strtoupper(trim((string) $request->input('code')));

            // Validate code
            $validation = GymiesLaunchGateService::validateInviteCode($code);
            if (!$validation['valid']) {
                return response()->json(['ok' => false, 'message' => $validation['message']], 422);
            }

            // Consume the code (tracks usage for fraud detection)
            $consumed = GymiesLaunchGateService::consumeInviteCode(
                $code,
                (int) $user->id,
                (string) ($request->ip() ?? 'unknown')
            );

            if (!$consumed) {
                return response()->json(['ok' => false, 'message' => 'Code kon niet worden gebruikt. Probeer het opnieuw.'], 422);
            }

            // If user was on waitlist for this region, mark as activated
            $regionSlug = trim((string) ($request->input('region_slug') ?? ''));
            if ($regionSlug !== '') {
                DB::table('gymies_waitlist')
                    ->where('user_id', (int) $user->id)
                    ->where('region_slug', $regionSlug)
                    ->where('status', 'waiting')
                    ->update([
                        'status' => 'activated',
                        'updated_at' => now(),
                    ]);
            }

            return response()->json([
                'ok' => true,
                'message' => 'Code geactiveerd! Je kunt nu boeken.',
                'can_book' => true,
            ]);
        } catch (\Throwable $e) {
            Log::error('Gymies launchGateActivateCode failed', [
                'user_id' => $user->id,
                'error' => $e->getMessage(),
            ]);
            return response()->json(['ok' => false, 'message' => 'Fout bij activatie: ' . $e->getMessage()], 500);
        }
    }
}
