<?php
/**
 * Gymies API + Flutter catchall.
 * Gebruik in Laravel routes/web.php:
 *   require __DIR__ . '/path/to/backend/routes_gymies_full.php';
 * Of: plak de inhoud van dit bestand (vanaf regel 8) onderaan routes/web.php onder dezelfde prefix api/gymies.
 */

// Voorkom dubbele registratie als dit bestand vanuit meerdere plekken wordt geladen
if (\Illuminate\Support\Facades\Route::has('api.gymies.login')) {
    return;
}

// ========== GYMIES API (prefix api/gymies) ==========
// HMAC middleware valideert request signing — voorkomt request tampering en replay attacks.
// Wordt overgeslagen als GYMIES_HMAC_SECRET niet is geconfigureerd of nog dev-default is.
Route::prefix('api/gymies')
    ->name('api.gymies.')
    ->middleware([
        \App\Http\Middleware\Gymies\GymiesSecurityHeadersMiddleware::class,
        \App\Http\Middleware\GymiesHmacMiddleware::class,
        \App\Http\Middleware\GymiesPerformanceMiddleware::class,
        \App\Http\Middleware\GymiesApiDeprecationMiddleware::class,
    ])
    ->group(function () {

    // --- Auth resend/verify: eigen rate-limit-profiel (verify) zodat brute-force en mail-bombing voorkomen worden ---
    Route::middleware('gymies.rate.limit:verify')->group(function () {
        Route::post('auth/resend-verification-code', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'resendVerificationCode'])->name('auth.resend-verification-code');
        Route::post('auth/verify-email', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'verifyEmail'])->name('auth.verify-email');
        Route::post('auth/verify-email-link', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'verifyEmailLink'])->name('auth.verify-email-link');
    });

    // --- Auth (publiek): login, register, wachtwoord vergeten ---
    Route::middleware('gymies.rate.limit:login')->group(function () {
        Route::post('login', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'login'])->name('login');
    });
    Route::middleware('gymies.rate.limit:register')->group(function () {
        Route::post('register', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'register'])->name('register');
    });
    Route::middleware('gymies.rate.limit:api')->group(function () {
        Route::post('auth/forgot-password', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'forgotPassword'])->name('auth.forgot-password');
        Route::post('auth/reset-password', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'resetPassword'])->name('auth.reset-password');
        // Invite codes: public validation (no auth required)
        Route::post('invite-codes/validate', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'validateInviteCodeEndpoint'])->name('invite-codes.validate');
        // verify-email + resend staan hierboven (dubbele registratie voorkomen)
    });

    // --- Klanten (publiek): trainers zoeken, groepslessen, Mollie webhook ---
    Route::middleware('gymies.rate.limit:api')->group(function () {
        Route::post('search-log', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'logSearch'])->name('search.log');
    });
    Route::get('trainers', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'index'])->name('trainers.index');
    Route::get('trainers/landing-cities', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'landingCities'])->name('trainers.landing-cities');
    Route::get('trainers/landing-nearby', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'landingNearby'])->name('trainers.landing-nearby');
    Route::get('trainers/by-slug/{slug}', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'showBySlug'])->name('trainers.by-slug');
    Route::get('trainers/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'show'])->name('trainers.show');
    Route::get('trainers/{id}/availability', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'publicAvailability'])->name('trainers.availability');
    Route::get('trainers/{id}/blocked-slots', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'blockedSlots'])->name('trainers.blocked-slots');
    Route::get('trainers/{id}/packages', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'packages'])->name('trainers.packages');
    Route::get('trainers/{id}/media', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'media'])->name('trainers.media');
    Route::get('trainers/{id}/stories', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'stories'])->name('trainers.stories');
    Route::get('trainers/{id}/has-stories', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'hasStories'])->name('trainers.has-stories');
    Route::get('trainers/{id}/gym-locations', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'gymLocations'])->name('trainers.gym-locations');
    // Publiek: landingspagina hero/sectie-media (admin vult URLs in Control Tower → gymies_system_settings).
    Route::get('site-media', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'siteMediaPublic'])->name('site-media');
    // Publiek: health check voor load balancers / uptime monitoring (geen auth vereist)
    Route::get('ops/health', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'health'])->name('ops.health.public');
    // Filterdefinities: trainers-context publiek; tickets/bookings/users/payouts/group_sessions vereisen admin
    Route::get('ops/filter-definitions', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'filterDefinitions'])->name('ops.filter-definitions');
    // Diagnose 401: alleen in local/staging of als GYMIES_DEBUG_AUTH=true (productie: uit)
    Route::middleware('gymies.debug.auth')->group(function () {
        Route::get('debug-auth-headers', fn (\Illuminate\Http\Request $r) => response()->json([
            'has_authorization' => !empty($r->header('Authorization')),
            'has_x_gymies_token' => !empty($r->header('X-Gymies-Token')),
            'has_x_authorization' => !empty($r->header('X-Authorization')),
        ]))->name('debug.auth-headers');
        Route::get('debug-auth-status', function (\Illuminate\Http\Request $r) {
            $extract = function ($req) {
                $raw = $req->bearerToken();
                if ($raw !== null && $raw !== '') return trim($raw);
                $h = $req->header('X-Authorization');
                if (is_string($h) && str_starts_with($h, 'Bearer ')) return trim(substr($h, 7));
                $h = $req->header('X-Gymies-Token');
                if (is_string($h) && $h !== '') return trim($h);
                return null;
            };
            $token = $extract($r);
            if ($token === null || $token === '') {
                return response()->json(['step' => 'no_token']);
            }
            $session = \Illuminate\Support\Facades\DB::table('gymies_sessions')->where('token', $token)->first();
            if (!$session) {
                return response()->json(['step' => 'session_not_found', 'token_len' => strlen($token)]);
            }
            $expiresAt = $session->expires_at ? (\Carbon\Carbon::parse($session->expires_at)) : null;
            if ($expiresAt && $expiresAt <= now()) {
                return response()->json(['step' => 'session_expired', 'expires_at' => (string) $expiresAt]);
            }
            if (\Illuminate\Support\Facades\Schema::hasColumn('gymies_sessions', 'revoked_at') && !empty($session->revoked_at)) {
                return response()->json(['step' => 'session_revoked']);
            }
            $user = \Illuminate\Support\Facades\DB::table('gymies_users')->where('id', $session->user_id)->first();
            if (!$user) {
                return response()->json(['step' => 'user_not_found']);
            }
            $skipUa = filter_var(env('GYMIES_SESSION_SKIP_USER_AGENT_CHECK', ''), FILTER_VALIDATE_BOOLEAN);
            if (!$skipUa && \Illuminate\Support\Facades\Schema::hasColumn('gymies_sessions', 'user_agent')) {
                $stored = mb_substr((string) ($session->user_agent ?? ''), 0, 255);
                $current = mb_substr((string) ($r->userAgent() ?? ''), 0, 255);
                if ($stored !== '' && $current !== '' && !hash_equals($stored, $current)) {
                    return response()->json(['step' => 'user_agent_mismatch']);
                }
            }
            return response()->json(['step' => 'ok', 'user_id' => $user->id]);
        })->name('debug.auth-status');
    });
    // Publiek: referralcode valideren vóór registratie (bestaat / al gebruikt)
    Route::get('referral/validate', [\App\Http\Controllers\Gymies\GymiesReferralController::class, 'validateCode'])->name('referral.validate');

    // ── Ambassador: publieke routes ────────────────────────────────────────────
    Route::post('ambassador/apply',              [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'apply'])->name('ambassador.apply');
    Route::get('ambassador/validate-code',      [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'validateCode'])->name('ambassador.validate-code');
    Route::get('ambassadors',                   [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'publicList'])->name('ambassadors.index');
    Route::get('ambassador/profile/{slug}',    [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'publicProfile'])->name('ambassador.profile');
    // Publiek: valideer gym invite token (voor registratie met invite link)
    Route::get('gym/invites/validate', [\App\Http\Controllers\Gymies\GymiesGymInviteController::class, 'validateToken'])->name('gym.invites.validate');

    // ─── Gym Registratie (publieke endpoints — token-gebaseerd) ──────────────
    Route::post('gym/request-demo',          [\App\Http\Controllers\Gymies\GymiesGymRegistrationController::class, 'requestDemo'])->name('gym.request-demo');
    Route::get('gym/validate-invite-token',  [\App\Http\Controllers\Gymies\GymiesGymRegistrationController::class, 'validateInviteToken'])->name('gym.validate-invite-token');
    Route::post('gym/register-with-token',   [\App\Http\Controllers\Gymies\GymiesGymRegistrationController::class, 'registerWithToken'])->name('gym.register-with-token');
    Route::get('gym/demo-status/{code}',     [\App\Http\Controllers\Gymies\GymiesGymRegistrationController::class, 'demoStatus'])->name('gym.demo-status');

    Route::get('group-sessions', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'index'])->name('group-sessions.index');
    Route::get('group-sessions/{id}', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'show'])->name('group-sessions.show');
    // Mollie webhooks: rate-limited tegen flooding (60/min). Verificatie via terugbellen Mollie API.
    Route::middleware('gymies.rate.limit:webhook')->group(function () {
        Route::match(['get', 'post'], 'webhooks/mollie', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'mollieWebhookHandler'])->name('webhooks.mollie');
        Route::match(['get', 'post'], 'webhooks/mollie-subscription', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'subscriptionWebhook'])->name('webhooks.mollie-subscription');
    });
    Route::get('onboarding/mollie-connect/callback', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'mollieConnectCallback'])->name('onboarding.mollie-connect.callback');
    // Mandaat webhooks (publiek — Mollie stuurt POST, callback is GET redirect)
    Route::post('webhooks/mandaat', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'mandaatWebhook'])->name('webhooks.mandaat');
    Route::get('onboarding/mandaat-callback', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'mandaatCallback'])->name('onboarding.mandaat-callback');
    // --- Cron-endpoints: beveiligd met GymiesCronMiddleware (X-Cron-Secret header) ---
    Route::middleware([\App\Http\Middleware\GymiesCronMiddleware::class])->group(function () {
        Route::post('cron/expire-pending-bookings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expirePendingBookings'])->name('cron.expire-pending-bookings');
        Route::post('cron/expire-reserved-bookings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireReservedBookings'])->name('cron.expire-reserved-bookings');
        Route::post('cron/expire-group-sessions-min-not-reached', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireGroupSessionsMinNotReached'])->name('cron.expire-group-sessions-min-not-reached');
        Route::post('cron/expire-group-session-claim-pending', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireGroupSessionClaimPending'])->name('cron.expire-group-session-claim-pending');
        Route::match(['get', 'post'], 'cron/booking-reminders', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'bookingReminders'])->name('cron.booking-reminders');
        Route::match(['get', 'post'], 'cron/auto-complete-sessions', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'autoCompletePastSessions'])->name('cron.auto-complete-sessions');
        Route::match(['get', 'post'], 'cron/availability-check', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'availabilityCheck'])->name('cron.availability-check');
        Route::match(['get', 'post'], 'cron/auto-pilot-retention', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'autoPilotRetention'])->name('cron.auto-pilot-retention');
        Route::match(['get', 'post'], 'cron/auto-pilot-low-credit', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'autoPilotLowCredit'])->name('cron.auto-pilot-low-credit');
        Route::match(['get', 'post'], 'cron/expire-spoed-inval', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireSpoedInval'])->name('cron.expire-spoed-inval');
        Route::match(['get', 'post'], 'cron/spoed-inval-batch1', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'spoedInvalBatch1'])->name('cron.spoed-inval-batch1');
        Route::match(['get', 'post'], 'cron/pro-client-health-refresh', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'refreshProClientHealth'])->name('cron.pro-client-health-refresh');
        Route::match(['get', 'post'], 'cron/subscription-reminders', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'subscriptionReminders'])->name('cron.subscription-reminders');
        Route::match(['get', 'post'], 'cron/generate-session-invoices', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'generateSessionInvoices'])->name('cron.generate-session-invoices');
        Route::match(['get', 'post'], 'cron/expire-group-session-payment-deadline', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireGroupSessionPaymentDeadline'])->name('cron.expire-group-session-payment-deadline');
        Route::match(['get', 'post'], 'cron/safe-session-overdue', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'checkSafeSessionOverdue'])->name('cron.safe-session-overdue');
        Route::match(['get', 'post'], 'cron/expire-substitute-requests', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireSubstituteRequests'])->name('cron.expire-substitute-requests');
        Route::match(['get', 'post'], 'cron/trigger-ghost-ratings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'triggerGhostRatings'])->name('cron.trigger-ghost-ratings');
        Route::match(['get', 'post'], 'cron/ghost-rating-alerts', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'ghostRatingAlerts'])->name('cron.ghost-rating-alerts');
        Route::match(['get', 'post'], 'cron/process-notification-emails', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'processNotificationEmails'])->name('cron.process-notification-emails');
        Route::match(['get', 'post'], 'cron/expire-subscription-trials', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'expireSubscriptionTrials'])->name('cron.expire-subscription-trials');
        Route::match(['get', 'post'], 'cron/recalculate-quality-scores', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'recalculateQualityScores'])->name('cron.recalculate-quality-scores');
        Route::match(['get', 'post'], 'cron/evaluate-ambassador-tiers', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'evaluateAmbassadorTiers'])->name('cron.evaluate-ambassador-tiers');
        Route::post('cron/crowdfund-check', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'cronCrowdfundCheck'])->name('cron.crowdfund-check');
        // V2: Recurring bookings genereren + waitlist offers expiren
        Route::match(['get', 'post'], 'cron/generate-recurring-bookings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'generateRecurringBookings'])->name('cron.generate-recurring-bookings');
        Route::match(['get', 'post'], 'cron/expire-waitlist-offers', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireWaitlistOffers'])->name('cron.expire-waitlist-offers');
        Route::match(['get', 'post'], 'cron/cleanup-idempotency-keys', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'cleanupIdempotencyKeys'])->name('cron.cleanup-idempotency-keys');
        Route::match(['get', 'post'], 'cron/cleanup-expired-stories', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'cleanupExpiredStories'])->name('cron.cleanup-expired-stories');
        Route::match(['get', 'post'], 'cron/reconcile-mollie-payments', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'reconcileMolliePayments'])->name('cron.reconcile-mollie-payments');
        Route::match(['get', 'post'], 'cron/process-payouts', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'processPayouts'])->name('cron.process-payouts');
        Route::match(['get', 'post'], 'cron/process-gym-settlements', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'processGymSettlements'])->name('cron.process-gym-settlements');

        // ── Onboarding cron jobs ──
        Route::match(['get', 'post'], 'cron/onboarding-trial-reminders', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'onboardingTrialReminders'])->name('cron.onboarding-trial-reminders');
        Route::match(['get', 'post'], 'cron/onboarding-nudges', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'onboardingNudges'])->name('cron.onboarding-nudges');
        Route::match(['get', 'post'], 'cron/onboarding-payment-reminders', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'onboardingPaymentReminders'])->name('cron.onboarding-payment-reminders');
        Route::match(['get', 'post'], 'cron/onboarding-smart-trial-suggestions', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'onboardingSmartTrialSuggestions'])->name('cron.onboarding-smart-trial-suggestions');
        Route::match(['get', 'post'], 'cron/onboarding-sla-warnings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'onboardingSlaWarnings'])->name('cron.onboarding-sla-warnings');
        Route::match(['get', 'post'], 'cron/evaluate-regions', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'evaluateRegions'])->name('cron.evaluate-regions');

        // Feature 1: Churn Prediction Cron
        Route::post('cron/recalculate-churn-scores', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'cronRecalculateChurnScores'])->name('cron.recalculate-churn-scores');

        // Waitlist expiry cron
        Route::post('cron/expire-waitlist-offers', function () {
            $service = new \App\Services\WaitlistService();
            $expired1 = $service->expireOffers();
            $expired2 = $service->expireGroupSessionOffers();
            return response()->json(['success' => true, 'expired_individual' => $expired1, 'expired_group' => $expired2]);
        })->name('cron.expire-waitlist-offers-v2');
    });

    // --- Beveiligd (Bearer token): Klanten, Trainers, Gyms, Admin ---
    // EnsureGymiesAuthPreempt zet user; GymiesAuthMiddleware valideert (gymies_personal_access_tokens + gymies_sessions).
    Route::middleware([
        \App\Http\Middleware\EnsureGymiesAuthPreempt::class,
        \App\Http\Middleware\GymiesAuthMiddleware::class,
        \App\Http\Middleware\GymiesSentryContextMiddleware::class,
        'gymies.rate.limit:api',
        'gymies.error_log',
    ])
        ->withoutMiddleware('auth:sanctum')
        ->group(function () {

        // Klanten: profiel, sessies, boekingen, support, notificaties, consent, betalingen, groepslessen, conversaties
        Route::get('me', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'me'])->name('me');
        Route::put('me', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'updateMe'])->name('me.update');
        Route::post('me', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'updateMe'])->name('me.update.post');
        Route::post('auth/change-password', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'changePassword'])->name('auth.change-password');
        Route::get('auth/sessions', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'sessions'])->name('auth.sessions');
        Route::post('auth/logout-device', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'logoutDevice'])->name('auth.logout-device');
        Route::post('auth/logout-all-devices', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'logoutAllDevices'])->name('auth.logout-all-devices');

        // Launch gate: invite codes + waitlist management
        Route::post('invite-codes/generate', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'generateInviteCodes'])->name('invite-codes.generate');
        Route::get('invite-codes/mine', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'getMyInviteCodes'])->name('invite-codes.mine');
        Route::get('waitlist/status', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'getWaitlistStatus'])->name('waitlist.status');
        Route::post('waitlist/activate-with-code', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'activateWithCode'])->name('waitlist.activate-with-code');

        // Launch gate: booking-time gate check + notify-me + code activation
        Route::get('launch-gate/check/{trainerUserId}', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'launchGateCheck'])->name('launch-gate.check');
        Route::post('launch-gate/notify-me', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'launchGateNotifyMe'])->name('launch-gate.notify-me');
        Route::post('launch-gate/activate-with-code', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'launchGateActivateCode'])->name('launch-gate.activate-with-code');

        Route::get('ops/health', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'health'])->name('ops.health');
        Route::get('ops/metrics', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'metrics'])->name('ops.metrics');
        Route::get('ops/queue', [\App\Http\Controllers\Gymies\GymiesHealthController::class, 'queueMetrics'])->name('ops.queue');
        Route::post('ops/run-backup', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'runBackup'])->name('ops.run-backup');
        Route::post('ops/run-web-sync', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'runWebSync'])->name('ops.run-web-sync');
        Route::get('feature-flags', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'featureFlags'])->name('ops.feature-flags');

        // Feature flag live toggle (admin only)
        Route::post('feature-flags/toggle', function (\Illuminate\Http\Request $request) {
            $user = $request->attributes->get('gymies_user');
            if (!$user || ($user->role !== 'trainer' && ((int) ($user->is_admin ?? 0)) !== 1)) {
                return response()->json(['message' => 'Unauthorized — admin only'], 403);
            }

            $request->validate([
                'key'     => 'required|string|max:100',
                'enabled' => 'required|boolean',
            ]);

            $key     = $request->input('key');
            $enabled = (bool) $request->input('enabled');

            $updated = \Illuminate\Support\Facades\DB::table('gymies_feature_flags')
                ->where('key', $key)
                ->update([
                    'enabled'    => $enabled,
                    'updated_at' => now(),
                ]);

            if ($updated === 0) {
                return response()->json(['message' => "Flag '{$key}' niet gevonden."], 404);
            }

            \App\Http\Controllers\Gymies\GymiesFeatureFlags::clearCache();

            return response()->json([
                'message' => "Flag '{$key}' is nu " . ($enabled ? 'AAN' : 'UIT'),
                'flag'    => $key,
                'enabled' => $enabled,
            ]);
        })->name('ops.feature-flags.toggle');

        // Feature flag rollout percentage aanpassen (admin only)
        Route::post('feature-flags/rollout', function (\Illuminate\Http\Request $request) {
            $user = $request->attributes->get('gymies_user');
            if (!$user || ($user->role !== 'trainer' && ((int) ($user->is_admin ?? 0)) !== 1)) {
                return response()->json(['message' => 'Unauthorized — admin only'], 403);
            }

            $request->validate([
                'key'        => 'required|string|max:100',
                'percentage' => 'required|numeric|min:0|max:100',
            ]);

            $key        = $request->input('key');
            $percentage = (float) $request->input('percentage');

            $updated = \Illuminate\Support\Facades\DB::table('gymies_feature_flags')
                ->where('key', $key)
                ->update([
                    'rollout_percentage' => $percentage,
                    'updated_at'         => now(),
                ]);

            if ($updated === 0) {
                return response()->json(['message' => "Flag '{$key}' niet gevonden."], 404);
            }

            \App\Http\Controllers\Gymies\GymiesFeatureFlags::clearCache();

            return response()->json([
                'message'            => "Flag '{$key}' rollout ingesteld op {$percentage}%",
                'flag'               => $key,
                'rollout_percentage' => $percentage,
            ]);
        })->name('ops.feature-flags.rollout');

        Route::get('broadcasts/active', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'broadcastsActive'])->name('broadcasts.active');
        Route::get('gdpr/export', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'export'])->name('gdpr.export');
        Route::get('gdpr/export/pdf', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'exportPdf'])->name('gdpr.export-pdf');
        Route::post('gdpr/delete-request', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'deleteRequest'])->name('gdpr.delete-request');
        Route::post('gdpr/delete-account', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'deleteAccount'])->name('gdpr.delete-account');
        // Flutter-aliases: account/delete → gdpr/delete-account, account/export-data → gdpr/export
        Route::post('account/delete', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'deleteAccount'])->name('account.delete');
        Route::post('account/export-data', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'export'])->name('account.export-data');
        Route::get('consent', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'consent'])->name('consent.get');
        Route::put('consent', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'updateConsent'])->name('consent.update');
        Route::post('consent', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'updateConsent'])->name('consent.update.post');
        Route::get('me/client-videos', [\App\Http\Controllers\Gymies\GymiesClientVideosController::class, 'clientIndex'])->name('me.client-videos');
        // Klant: sessie-notities en gedeeld dossier
        Route::get('me/session-notes', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'mySessionNotes'])->name('me.session-notes');
        Route::get('me/shared-dossier', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'mySharedDossier'])->name('me.shared-dossier');
        // Klant: progress dashboard
        Route::get('client/progress-dashboard', [\App\Http\Controllers\Gymies\GymiesClientDashboardController::class, 'progressDashboard'])->name('client.progress-dashboard');
        // Broadcasting: WebSocket config & auth
        Route::get('broadcasting/config', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'broadcastingConfig'])->name('broadcasting.config');
        Route::post('broadcasting/auth', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'broadcastingAuth'])->name('broadcasting.auth');

        // --- Ambassador (ingelogd) ---
        Route::get('ambassador/me', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'me'])->name('ambassador.me');
        Route::get('ambassador/conversions', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'myConversions'])->name('ambassador.conversions');
        Route::post('ambassador/iban', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'saveIban'])->name('ambassador.iban');

        Route::get('bookings', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'index'])->name('bookings.index');
        Route::get('me/bookings/export', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'exportClientBookings'])->name('me.bookings.export');
        Route::get('bookings/standby/me', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'me'])->name('bookings.standby.me');
        Route::get('waitlist/me', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'me'])->name('waitlist.me');
        Route::get('waitlist', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'me'])->name('waitlist.index');
        Route::get('trainer/summary', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'trainerSummary'])->name('trainer.summary');
        Route::get('trainer/me', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'me'])->name('trainer.me');
        // Pro Hub (client-health, upsell, rebook) – fix voor "unknown column 'name'"
        Route::get('trainer/pro/client-health', [\App\Http\Controllers\Gymies\GymiesProHubController::class, 'clientHealth'])->name('trainer.pro.client-health');
        Route::get('trainer/pro/upsell-suggestions', [\App\Http\Controllers\Gymies\GymiesProHubController::class, 'upsellSuggestions'])->name('trainer.pro.upsell-suggestions');
        Route::post('trainer/pro/upsell-suggestions/{id}/send', [\App\Http\Controllers\Gymies\GymiesProHubController::class, 'sendUpsellSuggestion'])->name('trainer.pro.upsell-send');
        Route::get('trainer/pro/rebook-suggestions', [\App\Http\Controllers\Gymies\GymiesProHubController::class, 'rebookSuggestions'])->name('trainer.pro.rebook-suggestions');
        Route::post('trainer/pro/rebook-suggestions/{id}/send', [\App\Http\Controllers\Gymies\GymiesProHubController::class, 'sendRebookSuggestion'])->name('trainer.pro.rebook-send');

        // Pro+ Newsletters
        Route::get('trainer/pro-plus/newsletters', [\App\Http\Controllers\Gymies\GymiesNewsletterController::class, 'index'])->name('trainer.pro-plus.newsletters');
        Route::post('trainer/pro-plus/newsletter', [\App\Http\Controllers\Gymies\GymiesNewsletterController::class, 'send'])->name('trainer.pro-plus.newsletter.send');
        Route::post('trainer/pro-plus/newsletters/schedule', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'scheduleNewsletter'])->name('trainer.pro-plus.newsletters.schedule');
        // Pro+ widget & analytics
        Route::patch('trainer/pro-plus/widget/settings', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'updateSettings'])->name('trainer.pro-plus.widget.settings.update');
        Route::get('trainer/pro-plus/widget/stats', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'widgetStats'])->name('trainer.pro-plus.widget.stats');
        Route::get('trainer/pro-plus/analytics/export', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'getClientAnalytics'])->name('trainer.pro-plus.analytics.export');

        Route::put('trainer/me', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'updateMe'])->name('trainer.me.update');
        Route::post('trainer/me', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'updateMe'])->name('trainer.me.update.post');
        Route::get('trainer/documents', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'documentsIndex'])->name('trainer.documents.index');
        Route::put('trainer/documents', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'documentsUpdate'])->name('trainer.documents.update');
        Route::patch('trainer/documents', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'documentsUpdate'])->name('trainer.documents.patch');
        Route::post('trainer/documents', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'documentsUpdate'])->name('trainer.documents.update.post');
        Route::post('bookings', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'store'])->name('bookings.store');
        Route::post('bookings/standby', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'store'])->name('bookings.standby.store');
        Route::post('waitlist', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'store'])->name('waitlist.store');
        Route::delete('bookings/standby/{id}', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'destroy'])->name('bookings.standby.destroy');
        Route::delete('waitlist/{id}', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'destroy'])->name('waitlist.destroy');
        Route::post('waitlist/{id}/claim', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'claim'])->name('waitlist.claim');

        // --- Recurring bookings (V2) ---
        Route::get('recurring-bookings', [\App\Http\Controllers\Gymies\GymiesRecurringBookingController::class, 'index'])->name('recurring-bookings.index');
        Route::post('recurring-bookings', [\App\Http\Controllers\Gymies\GymiesRecurringBookingController::class, 'store'])->name('recurring-bookings.store');
        Route::put('recurring-bookings/{id}/pause', [\App\Http\Controllers\Gymies\GymiesRecurringBookingController::class, 'pause'])->name('recurring-bookings.pause');
        Route::put('recurring-bookings/{id}/resume', [\App\Http\Controllers\Gymies\GymiesRecurringBookingController::class, 'resume'])->name('recurring-bookings.resume');
        Route::delete('recurring-bookings/{id}', [\App\Http\Controllers\Gymies\GymiesRecurringBookingController::class, 'cancel'])->name('recurring-bookings.cancel');

        // Trainers: specialties (skills/certificaten)
        Route::get('trainer/specialties', [\App\Http\Controllers\Gymies\GymiesSpecialtyController::class, 'trainerSpecialties'])->name('trainer.specialties.index');
        Route::put('trainer/specialties', [\App\Http\Controllers\Gymies\GymiesSpecialtyController::class, 'updateTrainerSpecialties'])->name('trainer.specialties.update');
        Route::post('trainer/specialties/request', [\App\Http\Controllers\Gymies\GymiesSpecialtyController::class, 'requestSpecialty'])->name('trainer.specialties.request');
        // Trainers: beschikbaarheid, pakketten, media, uitbetalingen, groepslessen, conversaties
        Route::get('trainer/availability', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'index'])->name('trainer.availability.index');
        Route::get('trainer/availability-settings', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'settings'])->name('trainer.availability.settings');
        Route::patch('trainer/availability-settings', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'updateSettings'])->name('trainer.availability.settings.update');
        Route::post('trainer/availability/slots', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'storeSlot'])->name('trainer.availability.slots.store');
        Route::put('trainer/availability/slots/{id}', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'updateSlot'])->name('trainer.availability.slots.update');
        Route::delete('trainer/availability/slots/{id}', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'deleteSlot'])->name('trainer.availability.slots.delete');
        Route::post('trainer/availability/exceptions', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'storeException'])->name('trainer.availability.exceptions.store');
        Route::put('trainer/availability/exceptions/{id}', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'updateException'])->name('trainer.availability.exceptions.update');
        Route::delete('trainer/availability/exceptions/{id}', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'deleteException'])->name('trainer.availability.exceptions.delete');
        Route::get('trainer/revenue', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'revenue'])->name('trainer.revenue');
        Route::get('trainer/payout-settings', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'payoutSettings'])->name('trainer.payout-settings');
        Route::put('trainer/payout-settings', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'updatePayoutSettings'])->name('trainer.payout-settings.update');
        Route::post('trainer/payout-settings', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'updatePayoutSettings'])->name('trainer.payout-settings.update.post');
        Route::get('trainer/payout-preview', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'payoutPreview'])->name('trainer.payout-preview');
        Route::get('trainer/payout-calendar', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'payoutCalendar'])->name('trainer.payout-calendar');
        Route::get('trainer/payouts', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'payoutHistory'])->name('trainer.payouts');
        Route::get('trainer/revenue/export', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'revenueExport'])->name('trainer.revenue.export');
        Route::get('trainer/revenue-forecast', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'revenueForecast'])->name('trainer.revenue-forecast');

        // Spoed Inval: trainer vraagt invaller voor sessie(s) bij overmacht
        Route::get('trainer/spoed-inval/requests', [\App\Http\Controllers\Gymies\GymiesSpoedInvalController::class, 'index'])->name('trainer.spoed-inval.index');
        Route::post('trainer/spoed-inval/request', [\App\Http\Controllers\Gymies\GymiesSpoedInvalController::class, 'createRequest'])->name('trainer.spoed-inval.create');
        Route::get('trainer/spoed-inval/requests/{id}/lesson-plan', [\App\Http\Controllers\Gymies\GymiesSpoedInvalController::class, 'getLessonPlan'])->name('trainer.spoed-inval.lesson-plan');
        Route::post('trainer/spoed-inval/requests/{id}/cancel', [\App\Http\Controllers\Gymies\GymiesSpoedInvalController::class, 'cancelRequest'])->name('trainer.spoed-inval.cancel');
        Route::post('trainer/spoed-inval/offers/{offerId}/respond', [\App\Http\Controllers\Gymies\GymiesSpoedInvalController::class, 'respondToOffer'])->name('trainer.spoed-inval.respond');
        Route::get('trainer/favorite-colleagues', [\App\Http\Controllers\Gymies\GymiesSpoedInvalController::class, 'getFavoriteColleagues'])->name('trainer.favorite-colleagues');
        Route::put('trainer/favorite-colleagues', [\App\Http\Controllers\Gymies\GymiesSpoedInvalController::class, 'updateFavoriteColleagues'])->name('trainer.favorite-colleagues.update');

        Route::middleware('gymies.idempotency')->group(function () {
            Route::post('checkin/report-fraud', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'reportIdentityFraud'])->name('checkin.report-fraud');
            Route::post('sos/alert', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'sosAlert'])->name('sos.alert');
            Route::post('bookings/{id}/safe-session/start', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'startSafeSession'])->name('bookings.safe-session.start');
            Route::post('bookings/{id}/safe-session/heartbeat', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'safeSessionHeartbeat'])->name('bookings.safe-session.heartbeat');
            Route::get('bookings/{id}/safe-session/status', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'safeSessionStatus'])->name('bookings.safe-session.status');
            Route::post('bookings/{id}/checkout', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'checkOut'])->name('bookings.checkout');
            Route::post('bookings/{id}/confirm-cash', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'confirmCashPayment'])->middleware('gymies.idempotency')->name('bookings.confirm-cash');
            Route::post('trainer/bookings/{id}/payments/cash/confirm', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'confirmCashPayment'])->middleware('gymies.idempotency')->name('trainer.bookings.payments.cash.confirm');
            Route::post('bookings/{id}/ghost-rating', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'submitGhostRating'])->name('bookings.ghost-rating');
            Route::post('bookings/{id}/review', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'storeReview'])->name('bookings.review.store');
            Route::get('bookings/{id}/review', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'getBookingReview'])->name('bookings.review.get');
            Route::post('bookings/{id}/review-response', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'storeReviewResponse'])->name('bookings.review-response.store');
            Route::post('trainer/payouts/request-now', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'requestPayoutNow'])->name('trainer.payouts.request-now');
            Route::post('group-session-participants/{participantId}/payments/start', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'startGroupParticipantPayment'])->name('group-session-participants.payments.start');
        });

        // Gym onboarding (beveiligd — gebruiker moet ingelogd zijn na registerWithToken)
        Route::post('gym/onboarding', [\App\Http\Controllers\Gymies\GymiesGymRegistrationController::class, 'onboarding'])->name('gym.onboarding');

        // Gyms: dashboard, trainers, boekingen, settlements, instellingen, leden
        Route::get('gym/dashboard', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'dashboard'])->name('gym.dashboard');
        Route::get('gym/dashboard-stats', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'dashboardStats'])->name('gym.dashboard.stats');
        Route::get('gym/membership', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'membership'])->name('gym.membership');
        Route::get('gym/trainers', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'trainers'])->name('gym.trainers');
        Route::post('gym/trainers', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'addTrainer'])->name('gym.trainers.add');
        Route::middleware('gymies.idempotency')->group(function () {
            Route::post('gym/trainers/{trainerUserId}/status', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'updateTrainerStatus'])->name('gym.trainers.status');
            Route::post('gym/bookings/{id}/send-reminder', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'sendBookingReminder'])->name('gym.bookings.send-reminder');
            Route::post('gym/clients/{clientUserId}/reengagement', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'sendClientReengagement'])->name('gym.clients.reengagement');
            Route::post('gym/members/{userId}/role', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'updateMemberRole'])->name('gym.members.role');
            Route::post('gym/members/{userId}/status', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'updateMemberStatus'])->name('gym.members.status');
        });
        Route::get('gym/trainers/{trainerUserId}/stats', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'trainerStats'])->name('gym.trainers.stats');
        Route::get('gym/bookings', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'bookings'])->name('gym.bookings');
        Route::get('gym/bookings/stats', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'bookingsStats'])->name('gym.bookings.stats');
        Route::get('gym/bookings/export', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'exportBookingsCsv'])->name('gym.bookings.export');
        Route::get('gym/bookings/{id}', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'bookingDetail'])->name('gym.bookings.detail');
        Route::get('gym/settlements', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'gymPayouts'])->name('gym.settlements');
        Route::get('gym/settlements/{id}', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'settlementDetail'])->name('gym.settlements.detail');
        Route::get('gym/revenue/export', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'exportRevenueCsv'])->name('gym.revenue.export');
        Route::get('gym/trainers/export', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'exportTrainersCsv'])->name('gym.trainers.export');
        Route::get('gym/clients', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'clients'])->name('gym.clients');
        Route::post('gym/alerts/{alertKey}/complete', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'completeDashboardAlert'])->name('gym.alerts.complete');
        Route::get('gym/settings', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'settings'])->name('gym.settings');
        Route::put('gym/settings', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'updateSettings'])->name('gym.settings.update');
        Route::post('gym/settings', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'updateSettings'])->name('gym.settings.update.post');
        Route::post('gym/members/invite', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'inviteMember'])->name('gym.members.invite');
        Route::post('gym/cache-invalidation-event', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'logCacheInvalidationEvent'])->name('gym.cache-invalidation-event');
        Route::get('gym/trainer-chat/conversations', [\App\Http\Controllers\Gymies\GymiesGymTrainerChatController::class, 'index'])->name('gym.trainer-chat.conversations');
        Route::post('gym/trainer-chat/conversations', [\App\Http\Controllers\Gymies\GymiesGymTrainerChatController::class, 'ensure'])->name('gym.trainer-chat.ensure');
        Route::get('gym/trainer-chat/conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesGymTrainerChatController::class, 'messages'])->name('gym.trainer-chat.messages');
        Route::post('gym/trainer-chat/conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesGymTrainerChatController::class, 'send'])->name('gym.trainer-chat.send');
        Route::middleware('gymies.idempotency')->group(function () {
            Route::post('gym/settlements/draft', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'createSettlementDraft'])->name('gym.settlements.draft');
            Route::post('gym/settlements/request-now', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'requestSettlementNow'])->middleware('throttle:10,1')->name('gym.settlements.request-now');
            Route::post('gym/settlements/{id}/adjustments', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'addSettlementAdjustment'])->name('gym.settlements.adjustments');
            Route::post('gym/settlements/{id}/transition', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'transitionSettlement'])->name('gym.settlements.transition');
        });
        // ── Gym Mollie & Payout ──
        Route::get('gym/mollie-status', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'mollieStatus'])->middleware('throttle:10,1')->name('gym.mollie.status');
        Route::post('gym/mollie-disconnect', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'mollieDisconnect'])->middleware('throttle:10,1')->name('gym.mollie.disconnect');
        Route::get('gym/payout-settings', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'payoutSettings'])->middleware('throttle:10,1')->name('gym.payout.settings');
        Route::put('gym/payout-settings', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'updatePayoutSettings'])->middleware('throttle:10,1')->name('gym.payout.settings.update');
        Route::get('gym/settlements/{id}/download', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'downloadSettlementInvoice'])->name('gym.settlements.download');

        
        Route::get('trainer/packages', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'packages'])->name('trainer.packages');
        Route::post('trainer/packages', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'storePackage'])->name('trainer.packages.store');
        Route::put('trainer/packages/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'updatePackage'])->name('trainer.packages.update');
        Route::delete('trainer/packages/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'deletePackage'])->name('trainer.packages.delete');
        Route::get('trainer/promo-codes', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'promoCodes'])->name('trainer.promo-codes.index');
        Route::post('trainer/promo-codes', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'storePromoCode'])->name('trainer.promo-codes.store');
        Route::put('trainer/promo-codes/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'updatePromoCode'])->name('trainer.promo-codes.update');
        Route::delete('trainer/promo-codes/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'deletePromoCode'])->name('trainer.promo-codes.delete');
        Route::get('trainer/promo-codes/stats', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'promoCodeStats'])->name('trainer.promo-codes.stats');
        // Trainer annuleringsbeleid CRUD
        Route::get('trainer/cancellation-policies', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'cancellationPolicies'])->name('trainer.cancellation-policies.index');
        Route::post('trainer/cancellation-policies', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'storeCancellationPolicy'])->name('trainer.cancellation-policies.store');
        Route::put('trainer/cancellation-policies/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'updateCancellationPolicy'])->name('trainer.cancellation-policies.update');
        Route::delete('trainer/cancellation-policies/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'deleteCancellationPolicy'])->name('trainer.cancellation-policies.delete');
        Route::get('trainer/retention/sleeping-clients', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sleepingClients'])->name('trainer.retention.sleeping-clients');
        Route::get('trainer/clients/{clientUserId}/progress', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientProgressIndex'])->name('trainer.clients.progress.index');
        Route::post('trainer/clients/{clientUserId}/progress', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientProgressStore'])->name('trainer.clients.progress.store');
        Route::get('trainer/clients/{clientUserId}/dossier', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientDossierGet'])->name('trainer.clients.dossier.show');
        Route::put('trainer/clients/{clientUserId}/dossier', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientDossierPut'])->name('trainer.clients.dossier.update');
        Route::get('trainer/clients/{clientUserId}/session-notes', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientSessionNotesIndex'])->name('trainer.clients.session-notes.index');
        Route::post('trainer/clients/{clientUserId}/session-notes', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientSessionNotesStore'])->name('trainer.clients.session-notes.store');
        Route::get('trainer/clients/{clientUserId}/payments', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'clientPayments'])->name('trainer.clients.payments.index');
        Route::get('trainer/clients/{clientUserId}/videos', [\App\Http\Controllers\Gymies\GymiesClientVideosController::class, 'index'])->name('trainer.clients.videos.index');
        Route::post('trainer/clients/{clientUserId}/videos', [\App\Http\Controllers\Gymies\GymiesClientVideosController::class, 'store'])->name('trainer.clients.videos.store');
        Route::delete('trainer/clients/{clientUserId}/videos/{id}', [\App\Http\Controllers\Gymies\GymiesClientVideosController::class, 'destroy'])->name('trainer.clients.videos.destroy');
        Route::post('trainer/clients/bulk-message', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'bulkMessageClients'])->name('trainer.clients.bulk-message');
        Route::get('trainer/studio/performance-summary', [\App\Http\Controllers\Gymies\GymiesStudioAnalyticsController::class, 'performanceSummary'])->name('trainer.studio.performance-summary');
        Route::get('trainer/studio/safety-log', [\App\Http\Controllers\Gymies\GymiesStudioAnalyticsController::class, 'safetyLog'])->name('trainer.studio.safety-log');
        Route::put('trainer/bookings/{bookingId}/session-note', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sessionNotePut'])->name('trainer.bookings.session-note');
        Route::get('trainer/storefront-cms', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'storefrontCmsGet'])->name('trainer.storefront-cms.get');
        Route::put('trainer/storefront-cms', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'storefrontCmsPut'])->name('trainer.storefront-cms.put');
        Route::post('trainer/storefront-cms', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'storefrontCmsPut'])->name('trainer.storefront-cms.post');
        Route::get('trainer/media', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'media'])->name('trainer.media');
        Route::post('trainer/story', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'uploadStory'])->name('trainer.story.upload');
        Route::get('trainer/{id}/has-stories', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'hasStoriesAuth'])->name('trainer.has-stories');
        Route::post('trainer/media', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'storeMedia'])->name('trainer.media.store');
        Route::put('trainer/media/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'updateMedia'])->name('trainer.media.update');
        Route::delete('trainer/media/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'deleteMedia'])->name('trainer.media.delete');
        Route::post('trainer/media/{mediaId}/featured', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'setMediaFeatured'])->name('trainer.media.featured');
        Route::post('trainer/media/bulk-delete', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'bulkDeleteMedia'])->name('trainer.media.bulk-delete');
        Route::get('trainer/conversations', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'conversations'])->name('trainer.conversations');
        Route::post('trainer/conversations/ensure', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'ensureConversation'])->name('trainer.conversations.ensure');
        Route::get('trainer/conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'messages'])->name('trainer.conversations.messages');
        Route::post('trainer/conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sendMessage'])->name('trainer.conversations.messages.send');
        Route::post('trainer/conversations/{id}/mark-read', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'markConversationRead'])->name('trainer.conversations.mark-read');
        Route::get('trainer/conversations/{id}/context', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'conversationContext'])->name('trainer.conversations.context');
        Route::get('trainer/live-counters', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'liveCounters'])->name('trainer.live-counters');
        Route::post('trainer/report-issue', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'reportIssue'])->name('trainer.report-issue');
        // Trainer settings (profiel-instellingen)
        Route::get('trainer/settings', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'trainerSettings'])->name('trainer.settings');
        Route::patch('trainer/settings', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'updateTrainerSettings'])->name('trainer.settings.update');
        // Pro: packages expiring soon
        Route::get('trainer/pro/packages/expiring-soon', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'packagesExpiringSoon'])->name('trainer.pro.packages.expiring-soon');
        Route::get('notifications', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'index'])->name('notifications.index');
        Route::get('notifications/unread-count', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'unreadCount'])->name('notifications.unread-count');
        Route::post('notifications/mark-read', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'markRead'])->name('notifications.mark-read');
        Route::post('devices/register', [\App\Http\Controllers\Gymies\GymiesDeviceTokenController::class, 'register'])->name('devices.register');
        Route::post('notifications/register-device', [\App\Http\Controllers\Gymies\GymiesDeviceTokenController::class, 'register'])->name('notifications.register-device'); // alias voor Flutter compatibiliteit
        Route::delete('notifications/register-device', [\App\Http\Controllers\Gymies\GymiesDeviceTokenController::class, 'unregister'])->name('notifications.unregister-device'); // alias voor Flutter compatibiliteit
        Route::post('ws-ticket', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'wsTicket'])->name('ws-ticket');
        Route::get('notifications/preferences', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'preferences'])->name('notifications.preferences');
        Route::put('notifications/preferences', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'updatePreferences'])->name('notifications.preferences.update');
        Route::post('notifications/preferences', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'updatePreferences'])->name('notifications.preferences.update.post');

        // ─── Trainer Payouts ─────────────────────────────────────────────
        Route::get('payout/balance', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'balance'])->name('payout.balance');
        Route::get('payout/transactions', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'transactions'])->name('payout.transactions');
        Route::get('payout/requests', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'requests'])->name('payout.requests');
        Route::get('payout/fees', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'fees'])->name('payout.fees');
        Route::post('payout/request', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'requestPayout'])->name('payout.request');
        Route::put('payout/settings', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'updateSettings'])->name('payout.settings');
        Route::put('payout/mode', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'updateMode'])->name('payout.mode');
        Route::get('payout/business', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'getBusinessInfo'])->name('payout.business');
        Route::put('payout/business', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'updateBusinessInfo'])->name('payout.business.update');
        Route::post('payout/self-billing-agree', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'agreeSelfBilling'])->name('payout.self-billing');
        Route::get('payout/invoices', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'trainerInvoices'])->name('payout.invoices');
        Route::get('payout/invoices/{id}/download', [\App\Http\Controllers\Gymies\GymiesPayoutController::class, 'downloadInvoice'])->name('payout.invoices.download');

        // ─── Admin Payouts ──────────────────────────────────────────────
        Route::get('admin/payouts', [\App\Http\Controllers\Gymies\GymiesAdminPayoutController::class, 'pending'])->name('admin.payouts.pending');
        Route::get('admin/payouts/history', [\App\Http\Controllers\Gymies\GymiesAdminPayoutController::class, 'history'])->name('admin.payouts.history');
        Route::get('admin/payouts/stats', [\App\Http\Controllers\Gymies\GymiesAdminPayoutController::class, 'stats'])->name('admin.payouts.stats');
        Route::get('admin/payouts/trainers', [\App\Http\Controllers\Gymies\GymiesAdminPayoutController::class, 'trainers'])->name('admin.payouts.trainers');
        Route::post('admin/payouts/{id}/mark-paid', [\App\Http\Controllers\Gymies\GymiesAdminPayoutController::class, 'markPaid'])->name('admin.payouts.mark-paid');
        Route::post('admin/payouts/{id}/cancel', [\App\Http\Controllers\Gymies\GymiesAdminPayoutController::class, 'cancel'])->name('admin.payouts.cancel');
        Route::get('admin/payouts/invoices', [\App\Http\Controllers\Gymies\GymiesAdminPayoutController::class, 'invoices'])->name('admin.payouts.invoices');

        // Klant: intake formulier (goals, trainingfrequentie, etc.)
        Route::get('me/intake', [\App\Http\Controllers\Gymies\GymiesIntakeController::class, 'getMyIntake'])->name('me.intake');
        Route::put('me/intake', [\App\Http\Controllers\Gymies\GymiesIntakeController::class, 'updateMyIntake'])->name('me.intake.update');
        Route::post('me/intake', [\App\Http\Controllers\Gymies\GymiesIntakeController::class, 'updateMyIntake'])->name('me.intake.update.post');

        // Klant-favorieten: trainers als favoriet bewaren
        Route::get('me/favorites', [\App\Http\Controllers\Gymies\GymiesFavoritesController::class, 'index'])->name('me.favorites.index');
        Route::post('me/favorites', [\App\Http\Controllers\Gymies\GymiesFavoritesController::class, 'store'])->name('me.favorites.store');
        Route::delete('me/favorites/{trainerId}', [\App\Http\Controllers\Gymies\GymiesFavoritesController::class, 'destroy'])->name('me.favorites.destroy');

        // Klant: verborgen trainers (niet meer tonen in zoekresultaten)
        Route::get('me/hidden-trainers', [\App\Http\Controllers\Gymies\GymiesHiddenTrainersController::class, 'index'])->name('me.hidden-trainers.index');
        Route::post('me/hidden-trainers', [\App\Http\Controllers\Gymies\GymiesHiddenTrainersController::class, 'store'])->name('me.hidden-trainers.store');
        Route::delete('me/hidden-trainers/{trainerId}', [\App\Http\Controllers\Gymies\GymiesHiddenTrainersController::class, 'destroy'])->name('me.hidden-trainers.destroy');

        // Ambassador personal endpoints (unified → AmbassadorController)
        Route::get('me/ambassador/stats', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'myStats']);
        Route::get('me/ambassador/referrals', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'myReferrals']);
        Route::get('me/ambassador/payouts', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'myPayouts']);
        Route::post('me/ambassador/request-payout', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'myRequestPayout']);

        // Trainer community chat
        Route::get('me/gym-chats', [GymiesStaffDashboardController::class, 'myGymChats']);
        Route::get('me/gym-chats/{chatId}/messages', [GymiesStaffDashboardController::class, 'gymChatMessages']);
        Route::post('me/gym-chats/{chatId}/messages', [GymiesStaffDashboardController::class, 'sendGymChatMessage']);
        Route::post('me/gym-chats/{chatId}/mute', [GymiesStaffDashboardController::class, 'toggleGymChatMute']);
        Route::get('me/gym-trainers', [GymiesStaffDashboardController::class, 'myGymTrainers']);

        Route::get('support/tickets', [\App\Http\Controllers\Gymies\GymiesSupportController::class, 'index'])->name('support.tickets.index');
        Route::post('support/tickets', [\App\Http\Controllers\Gymies\GymiesSupportController::class, 'store'])->name('support.tickets.store');
        Route::get('support/tickets/{id}', [\App\Http\Controllers\Gymies\GymiesSupportController::class, 'show'])->name('support.tickets.show');
        Route::post('support/tickets/{id}/messages', [\App\Http\Controllers\Gymies\GymiesSupportController::class, 'addMessage'])->name('support.tickets.messages.add');
        // Promo aliases (Flutter gebruikt promo/validate, promo/active, promo/activate)
        Route::post('promo/validate', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'validatePromo'])->name('promo.validate');
        Route::get('promo/active', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'activePromo'])->name('promo.active');
        Route::post('promo/activate', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'activatePromo'])->name('promo.activate');
        Route::post('bookings/{id}/payments/validate-promo', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'validatePromo'])->name('bookings.payments.validate-promo');
        Route::get('bookings/{id}/payment-status', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'paymentStatus'])->name('bookings.payment-status');
        Route::post('group-session-participants/{participantId}/validate-promo', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'validatePromoForGroupParticipant'])->name('group-session-participants.validate-promo');
        Route::get('group-session-participants/{participantId}/payment-status', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'groupParticipantPaymentStatus'])->name('group-session-participants.payment-status');

        Route::get('my-group-registrations', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'myRegistrations'])->name('my-group-registrations');

        Route::get('conversations', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'index'])->name('client.conversations.index');
        Route::post('conversations/ensure', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'ensure'])->name('client.conversations.ensure');
        Route::get('conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'messages'])->name('client.conversations.messages');
        Route::post('conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'sendMessage'])->name('client.conversations.send');
        Route::post('conversations/{id}/mark-read', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'markRead'])->name('client.conversations.mark-read');
        Route::delete('conversations/{id}', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'destroy'])->name('client.conversations.destroy');
        Route::get('conversations/{id}/context', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'conversationContext'])->name('client.conversations.context');
        Route::get('me/progress', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'myProgressForTrainer'])->name('client.me.progress');

        Route::get('referral/my-code', [\App\Http\Controllers\Gymies\GymiesReferralController::class, 'myCode'])->name('referral.my-code');

        // Trainer onboarding & subscription
        Route::get('onboarding/status', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'onboardingStatus'])->name('onboarding.status');
        Route::post('onboarding/upload-document', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'uploadDocument'])->name('onboarding.upload-document');
        Route::post('onboarding/mollie-connect/start', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'startMollieConnect'])->name('onboarding.mollie-connect.start');
        Route::post('onboarding/select-plan', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'selectPlan'])->name('onboarding.select-plan');

        // ─── Nieuwe onboarding flow (Fase B) ─────────────────────────────
        Route::post('onboarding/submit', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'submitOnboarding'])->name('onboarding.submit');
        Route::put('onboarding/billing-cycle', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'selectBillingCycle'])->name('onboarding.billing-cycle');
        Route::put('onboarding/plan-selection', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'savePlanSelection'])->name('onboarding.plan-selection');
        Route::post('onboarding/validate-code', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'validateInvitationCode'])->name('onboarding.validate-code');
        Route::post('onboarding/initiate-mandaat', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'initiateMandaat'])->name('onboarding.initiate-mandaat');
        Route::get('onboarding/pricing-preview', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'pricingPreview'])->name('onboarding.pricing-preview');
        Route::post('onboarding/referral-code', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'generateReferralCode'])->name('onboarding.referral-code');

        // ─── Staff/Medewerkers Dashboard ──────────────────────────────────
        Route::prefix('staff')->name('staff.')->group(function () {
            Route::get('dashboard', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'dashboard'])->name('dashboard');
            Route::get('pending-reviews', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'pendingReviews'])->name('pending-reviews');
            Route::post('review/{trainerId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'reviewTrainer'])->name('review');
            Route::post('suspend/{trainerId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'suspendTrainer'])->name('suspend');
            Route::post('reactivate/{trainerId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'reactivateTrainer'])->name('reactivate');
            Route::get('trials', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'trialOverview'])->name('trials');
            Route::post('trials/{trainerId}/extend', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'extendTrial'])->name('trials.extend');
            Route::get('trials/{trainerId}/extendability', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'trialExtendability'])->name('trials.extendability');
            Route::get('audit-log', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'auditLog'])->name('audit-log');
            Route::get('invitation-codes', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'invitationCodes'])->name('invitation-codes');
            Route::post('invitation-codes', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'createInvitationCode'])->name('invitation-codes.create');
            Route::delete('invitation-codes/{codeId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'deactivateInvitationCode'])->name('invitation-codes.deactivate');
            Route::get('fraud-check/{trainerId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'fraudCheck'])->name('fraud-check');
            Route::get('feature-flags', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'featureFlags'])->name('feature-flags');
            Route::put('feature-flags/{key}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'updateFeatureFlag'])->name('feature-flags.update');

            // ─── Support Ticket Beheer ───────────────────────────────
            Route::get('tickets', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffTickets'])->name('tickets');
            Route::get('tickets/stats', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffTicketStats'])->name('tickets.stats');
            Route::get('tickets/{ticketId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffTicketDetail'])->name('tickets.detail');
            Route::put('tickets/{ticketId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffUpdateTicket'])->name('tickets.update');
            Route::post('tickets/{ticketId}/messages', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffAddTicketMessage'])->name('tickets.messages.add');

            // ─── Interne Staff Chat ──────────────────────────────────
            Route::get('chat/messages', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffChatMessages'])->name('chat.messages');
            Route::post('chat/messages', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffChatSend'])->name('chat.send');
            Route::get('chat/channels', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffChatChannels'])->name('chat.channels');
            Route::post('chat/mark-read', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffChatMarkRead'])->name('chat.mark-read');
            Route::get('chat/unread-counts', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffChatUnreadCounts'])->name('chat.unread-counts');

            // ─── Fase H: Uitgebreide Staff Features ─────────────────
            Route::get('trainer-detail/{trainerId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffTrainerDetail'])->name('trainer-detail');
            Route::get('trainers', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffTrainers'])->name('trainers');
            Route::get('bookings-monitor', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffBookingsMonitor'])->name('bookings-monitor');
            Route::get('onboarding-pipeline', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffOnboardingPipeline'])->name('onboarding-pipeline');
            Route::get('canned-responses', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffCannedResponses'])->name('canned-responses');
            Route::post('canned-responses', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffCreateCannedResponse'])->name('canned-responses.create');
            Route::delete('canned-responses/{id}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffDeleteCannedResponse'])->name('canned-responses.delete');
            Route::get('disputes', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffDisputes'])->name('disputes');
            Route::post('auto-assign-tickets', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffAutoAssignTickets'])->name('auto-assign-tickets');
            Route::get('trial-extensions/{trainerId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffTrialExtensions'])->name('trial-extensions');
            Route::get('dashboard-extended', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffDashboardExtended'])->name('dashboard-extended');
            Route::get('audit-export', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffAuditExport'])->name('audit-export');
            Route::get('feature-flags-extended', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffFeatureFlagsExtended'])->name('feature-flags-extended');

            // ─── Fase I: Volledige Staff Operaties ──────────────────
            // I.1 Geschillen oplossen + berichten
            Route::get('disputes/{disputeId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffDisputeDetail'])->name('disputes.detail');
            Route::post('disputes/{disputeId}/resolve', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffResolveDispute'])->name('disputes.resolve');
            Route::post('disputes/{disputeId}/message', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffAddDisputeMessage'])->name('disputes.message');

            // I.2 Ticket aanmaken namens klant/trainer
            Route::post('tickets', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffCreateTicket'])->name('tickets.create');

            // I.3 Booking annuleren + herschikken + detail
            Route::get('bookings/{bookingId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffBookingDetail'])->name('bookings.detail');
            Route::post('bookings/{bookingId}/cancel', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffCancelBooking'])->name('bookings.cancel');
            Route::post('bookings/{bookingId}/reschedule', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffRescheduleBooking'])->name('bookings.reschedule');

            // I.4 Refund/credit toekennen (max €50)
            Route::post('bookings/{bookingId}/refund', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffRefundOrCredit'])->name('bookings.refund');

            // I.5 Trainer documenten goedkeuren/afkeuren
            Route::post('documents/{documentId}/review', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffReviewDocument'])->name('documents.review');

            // I.6 Trainer notities
            Route::get('notes/{userId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffTrainerNotes'])->name('notes.index');
            Route::post('notes/{userId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffAddTrainerNote'])->name('notes.add');

            // I.7 Nudge push notificatie
            Route::post('nudge', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffSendNudge'])->name('nudge');

            // I.8 Trainer-klant chat inzien (read-only)
            Route::get('conversations/{conversationId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffViewConversation'])->name('conversations.view');
            Route::get('user-conversations/{userId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffUserConversations'])->name('user-conversations');

            // I.9 Groepslessen monitor
            Route::get('group-sessions', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffGroupSessions'])->name('group-sessions');
            Route::get('group-sessions/{sessionId}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffGroupSessionDetail'])->name('group-sessions.detail');

            // I.10 Betalingen overzicht
            Route::get('payments', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffPaymentsOverview'])->name('payments');

            // I.11 Subscription toewijzen/pauzeren
            Route::post('subscriptions/{userId}/assign', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffAssignSubscription'])->name('subscriptions.assign');
            Route::post('subscriptions/{userId}/toggle', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffToggleSubscription'])->name('subscriptions.toggle');

            // I.12 Ticket samenvoegen + escalatie
            Route::post('tickets/merge', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffMergeTickets'])->name('tickets.merge');
            Route::post('tickets/{ticketId}/escalate', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffEscalateTicket'])->name('tickets.escalate');

            // I.13 Gym/studio overzicht
            Route::get('gyms', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffGymsOverview'])->name('gyms');

            // Fix #82: Gym Revenue Analytics
            Route::get('gyms/{gymId}/revenue', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'gymRevenueAnalytics'])->name('gyms.revenue');

            // Fix #83: Bulk Member Import
            Route::post('gyms/{gymId}/import-members', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'gymBulkImportMembers'])->name('gyms.import-members');

            // Fix #88: Gym Occupancy Stats
            Route::get('gyms/{gymId}/occupancy', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'gymOccupancyStats'])->name('gyms.occupancy');

            // Feature 1: Churn Prediction
            Route::get('gyms/{gymId}/churn-report', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'gymChurnReport'])->name('gyms.churn-report');

            // Fix #90: Ambassador Dashboard
            Route::get('ambassadors/{userId}/dashboard', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'ambassadorDashboard'])->name('ambassadors.dashboard');

            // Fix #94: Ambassador Payout History
            Route::get('ambassadors/{userId}/payouts', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'ambassadorPayoutHistory'])->name('ambassadors.payouts');

            // I.14-17: Trainer Reports & Analytics (Fix 64-69)
            Route::get('trainers/{userId}/earnings', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'trainerEarningsReport'])->name('trainers.earnings');
            Route::get('trainers/{userId}/profile-completeness', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'trainerProfileCompleteness'])->name('trainers.profile-completeness');
            Route::get('trainers/{userId}/tax-report', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'trainerTaxReport'])->name('trainers.tax-report');
            Route::get('trainers/{userId}/booking-stats', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'trainerBookingStats'])->name('trainers.booking-stats');

            // Feature 2: Multi-locatie Coördinatie
            Route::get('gyms/{orgId}/locations', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'gymLocations'])->name('gyms.locations');
            Route::get('gyms/{orgId}/locations/{locId}/stats', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'gymLocationStats'])->name('gyms.location-stats');
            Route::post('gyms/{orgId}/trainers/{userId}/transfer', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'transferTrainer'])->name('gyms.transfer-trainer');
            Route::post('gyms/{orgId}/group-sessions/{sessionId}/duplicate', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'duplicateGroupSession'])->name('gyms.duplicate-session');

            // ─── Activity Heatmap ───────────────────────────────────
            Route::get('activity-heatmap', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'staffActivityHeatmap'])->name('activity-heatmap');

            // ─── Launch Regions Management ──────────────────────────
            Route::get('regions', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'getRegions'])->name('regions');
            Route::get('regions/{slug}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'getRegionDetail'])->name('regions.detail');
            Route::put('regions/{slug}', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'updateRegionStatus'])->name('regions.update');
            Route::post('regions', [\App\Http\Controllers\Gymies\GymiesStaffDashboardController::class, 'createRegion'])->name('regions.create');
        });
        Route::get('subscription/my', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'mySubscription'])->name('subscription.my');
        Route::get('subscription/features', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'subscriptionFeatures'])->name('subscription.features');
        Route::post('subscription/cancel', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'cancelSubscription'])->name('subscription.cancel');
        Route::post('subscription/change', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'changeSubscription'])->name('subscription.change');
        Route::post('subscription/start-payment', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'startSubscriptionPayment'])->name('subscription.start-payment');
        Route::post('subscription/pause', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'pauseSubscription'])->name('subscription.pause');
        Route::post('subscription/resume', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'resumeSubscription'])->name('subscription.resume');
        Route::get('subscription/payment-history', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'paymentHistory'])->name('subscription.payment-history');
        Route::get('plans', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'availablePlans'])->name('plans.index');

        // Invoices
        Route::get('invoices/trainer', [\App\Http\Controllers\Gymies\GymiesInvoiceController::class, 'trainerInvoices'])->name('invoices.trainer');
        Route::get('invoices/trainer/quarter-zip', [\App\Http\Controllers\Gymies\GymiesInvoiceController::class, 'trainerInvoicesQuarterZip'])->name('invoices.trainer.quarter-zip');
        Route::get('invoices/client', [\App\Http\Controllers\Gymies\GymiesInvoiceController::class, 'clientInvoices'])->name('invoices.client');
        Route::get('invoices/client/{id}/download', [\App\Http\Controllers\Gymies\GymiesInvoiceController::class, 'clientInvoiceDownload'])->name('invoices.client.download');
        Route::post('group-sessions/{id}/register', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'register'])->name('group-sessions.register');
        Route::post('group-sessions/{id}/cancel-registration', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'cancelRegistration'])->name('group-sessions.cancel-registration');

        // Refunds & group payment overview (trainer)
        Route::get('trainer/refunds', [\App\Http\Controllers\Gymies\GymiesRefundController::class, 'trainerRefunds'])->name('trainer.refunds');
        Route::get('trainer/group-sessions/{id}/payment-overview', [\App\Http\Controllers\Gymies\GymiesRefundController::class, 'groupSessionPaymentOverview'])->name('trainer.group-sessions.payment-overview');

        Route::get('trainer/group-sessions', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'trainerIndex'])->name('trainer.group-sessions.index');
        Route::post('trainer/group-sessions', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'store'])->name('trainer.group-sessions.store');
        Route::post('trainer/group-sessions/recurring', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'storeRecurring'])->name('trainer.group-sessions.recurring');
        Route::put('trainer/group-sessions/{id}', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'update'])->name('trainer.group-sessions.update');
        Route::post('trainer/group-sessions/{id}/publish', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'publish'])->name('trainer.group-sessions.publish');
        Route::post('trainer/group-sessions/{id}/confirm', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'confirm'])->name('trainer.group-sessions.confirm');
        Route::post('trainer/group-sessions/{id}/cancel', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'cancel'])->name('trainer.group-sessions.cancel');
        Route::post('trainer/group-sessions/{id}/request-substitute', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'requestSubstitute'])->name('trainer.group-sessions.request-substitute');
        Route::post('substitute-requests/{requestId}/accept', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'acceptSubstitute'])->name('substitute-requests.accept');
        Route::get('trainer/group-sessions/{id}/participants', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'participants'])->name('trainer.group-sessions.participants');
        Route::post('trainer/group-sessions/{id}/participants/{participantId}/attended', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'markParticipantAttended'])->name('trainer.group-sessions.participants.attended');

        // Waitlist endpoints
        Route::get('trainer/group-sessions/{id}/waitlist', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'waitlist'])->name('trainer.group-sessions.waitlist');
        Route::post('trainer/group-sessions/{sessionId}/waitlist/{clientUserId}/promote', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'promoteWaitlistParticipant'])->name('trainer.group-sessions.waitlist.promote');

        // ── Geschillen (client-side) ────────────────────────────────
        Route::post('bookings/{id}/dispute', [\App\Http\Controllers\Gymies\GymiesDisputeController::class, 'raise'])->name('bookings.dispute');
        Route::get('my-disputes', [\App\Http\Controllers\Gymies\GymiesDisputeController::class, 'myDisputes'])->name('my-disputes.index');
        Route::get('my-disputes/{disputeId}', [\App\Http\Controllers\Gymies\GymiesDisputeController::class, 'detail'])->name('my-disputes.detail');
        Route::post('my-disputes/{disputeId}/message', [\App\Http\Controllers\Gymies\GymiesDisputeController::class, 'addMessage'])->name('my-disputes.message');

        // ── Insights (smart scheduling, trainer stats, pricing, reschedule) ──
        Route::get('insights/smart-schedule', [\App\Http\Controllers\Gymies\GymiesInsightsController::class, 'smartSchedule'])->name('insights.smart-schedule');
        Route::get('insights/trainer', [\App\Http\Controllers\Gymies\GymiesInsightsController::class, 'trainerInsights'])->name('insights.trainer');
        Route::get('insights/pricing', [\App\Http\Controllers\Gymies\GymiesInsightsController::class, 'pricingInsight'])->name('insights.pricing');
        Route::get('insights/reschedule-options/{bookingId}', [\App\Http\Controllers\Gymies\GymiesInsightsController::class, 'rescheduleOptions'])->name('insights.reschedule-options');

        // ── Gymies Points ───────────────────────────────────────────
        Route::get('points/balance',  [\App\Http\Controllers\Gymies\GymiesPointsController::class, 'balance'])->name('points.balance');
        Route::get('points/history',  [\App\Http\Controllers\Gymies\GymiesPointsController::class, 'history'])->name('points.history');
        Route::post('points/redeem',  [\App\Http\Controllers\Gymies\GymiesPointsController::class, 'redeem'])->name('points.redeem');

        // Admin (vault-console): users, tickets, payouts, bookings, security, audit, organisaties
        Route::prefix(trim((string) (env('GYMIES_ADMIN_PREFIX') ?? env('TRAINMAAT_ADMIN_PREFIX', 'vault-console'))) ?: 'vault-console')
            ->name('admin.')
            ->middleware(['gymies.admin.ip', 'gymies.admin.capability:admin.access'])
            ->group(function () {
                Route::get('inbox', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'inbox'])->name('inbox');
                Route::get('overview', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'overview'])->name('overview');
                Route::get('search', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'search'])->name('search');
                Route::get('note-templates', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'noteTemplates'])->name('note-templates.index');
                Route::get('saved-views', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'savedViews'])->name('saved-views.index');
                Route::post('saved-views', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'storeSavedView'])
                    ->middleware(['gymies.idempotency'])
                    ->name('saved-views.store');
                Route::delete('saved-views/{id}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'destroySavedView'])->name('saved-views.destroy');
                Route::post('bulk/users/status', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'bulkUsersStatus'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('bulk.users.status');
                Route::post('bulk/tickets', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'bulkTickets'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.tickets.manage'])
                    ->name('bulk.tickets');
                Route::post('bulk/payouts/status', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'bulkPayoutsStatus'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payouts.manage'])
                    ->name('bulk.payouts.status');
                Route::get('users', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'users'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('users.index');
                Route::get('users/export', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'usersExport'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('users.export');
                Route::get('users/{userId}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'userDetail'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('users.detail');
                Route::get('users/{userId}/notes', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'userNotes'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('users.notes.index');
                Route::post('users/{userId}/notes', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'addUserNote'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('users.notes.add');
                Route::post('users/{userId}/status', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateUserStatus'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('users.status');
                Route::post('users/{userId}/force-logout-all', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'forceLogoutAll'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('users.force-logout-all');
                Route::post('users/{userId}/impersonate', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'impersonate'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('users.impersonate');
                Route::get('moderation/profiles', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'moderationProfiles'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('moderation.profiles');
                Route::post('moderation/profiles/{userId}/approve', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'moderationApprove'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('moderation.approve');
                Route::post('moderation/profiles/{userId}/reject', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'moderationReject'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('moderation.reject');
                Route::post('moderation/profiles/{userId}/quality-score', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'moderationQualityScore'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('moderation.quality-score');

                Route::get('payments', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'payments'])
                    ->middleware('gymies.admin.capability:admin.payments.view')
                    ->name('payments.index');
                Route::get('promo-codes', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'promoCodes'])
                    ->middleware('gymies.admin.capability:admin.payments.view')
                    ->name('promo-codes.index');
                Route::post('promo-codes', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'storePromoCode'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payments.view'])
                    ->name('promo-codes.store');
                Route::get('payouts', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'payouts'])
                    ->middleware('gymies.admin.capability:admin.payouts.view')
                    ->name('payouts.index');
                Route::post('payouts/{payoutId}/status', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updatePayoutStatus'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payouts.manage'])
                    ->name('payouts.status');

                // Fee beheer (platform fees per trainer / per plan / globaal)
                Route::get('fees', [\App\Http\Controllers\Gymies\GymiesFeeAdminController::class, 'index'])
                    ->middleware('gymies.admin.capability:admin.payments.view')
                    ->name('fees.index');
                Route::post('fees', [\App\Http\Controllers\Gymies\GymiesFeeAdminController::class, 'store'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payments.manage'])
                    ->name('fees.store');
                Route::put('fees/{id}', [\App\Http\Controllers\Gymies\GymiesFeeAdminController::class, 'update'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payments.manage'])
                    ->name('fees.update');
                Route::delete('fees/{id}', [\App\Http\Controllers\Gymies\GymiesFeeAdminController::class, 'destroy'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payments.manage'])
                    ->name('fees.destroy');

                Route::get('tickets', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'tickets'])
                    ->middleware('gymies.admin.capability:admin.tickets.view')
                    ->name('tickets.index');
                Route::post('tickets/duplicate', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'duplicateTicket'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.tickets.manage'])
                    ->name('tickets.duplicate');
                Route::post('tickets/{ticketId}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateTicket'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.tickets.manage'])
                    ->name('tickets.update');
                Route::get('tickets/{ticketId}/messages', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'ticketMessages'])
                    ->middleware('gymies.admin.capability:admin.tickets.view')
                    ->name('tickets.messages.index');
                Route::post('tickets/{ticketId}/messages', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'addTicketMessage'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.tickets.manage'])
                    ->name('tickets.messages.add');

                Route::get('bookings-monitor', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'bookingsMonitor'])
                    ->middleware('gymies.admin.capability:admin.bookings.view')
                    ->name('bookings.monitor');
                Route::get('bookings/{bookingId}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'bookingDetail'])
                    ->middleware('gymies.admin.capability:admin.bookings.view')
                    ->name('bookings.detail');
                Route::post('bookings/{bookingId}/cancel', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'cancelBooking'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('admin.bookings.cancel');
                Route::post('bookings/{bookingId}/waive-trainer-penalty', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'waiveTrainerPenalty'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('bookings.waive-trainer-penalty');
                Route::post('bookings/{bookingId}/refund-or-credit', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'refundOrCredit'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('bookings.refund-or-credit');
                Route::post('bookings/{bookingId}/reschedule', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'rescheduleBooking'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('admin.bookings.reschedule');
                Route::post('bookings/{bookingId}/incident', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'addBookingIncident'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('bookings.incident');
                Route::get('bookings/{bookingId}/incidents', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'bookingIncidents'])
                    ->middleware('gymies.admin.capability:admin.bookings.view')
                    ->name('bookings.incidents');
                Route::post('incidents/{incidentId}/resolve', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'resolveIncident'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('incidents.resolve');
                Route::get('disputes', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'disputes'])
                    ->middleware('gymies.admin.capability:admin.bookings.view')
                    ->name('disputes.index');
                Route::get('disputes/{disputeId}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'disputeDetail'])
                    ->middleware('gymies.admin.capability:admin.bookings.view')
                    ->name('disputes.detail');
                Route::post('disputes/{disputeId}/resolve', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'resolveDispute'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('disputes.resolve');
                Route::get('subscriptions', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'subscriptions'])
                    ->middleware('gymies.admin.capability:admin.payments.view')
                    ->name('subscriptions.index');
                Route::get('subscriptions/revenue', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'subscriptionRevenue'])
                    ->middleware('gymies.admin.capability:admin.payments.view')
                    ->name('subscriptions.revenue');
                Route::get('plans', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'plansIndex'])
                    ->middleware('gymies.admin.capability:admin.payments.view')
                    ->name('plans.index');
                Route::post('plans/{planId}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'plansUpdate'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payments.manage'])
                    ->name('plans.update');
                Route::post('plans/sync-to-site', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'plansSyncToSite'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payments.manage'])
                    ->name('plans.sync-to-site');
                Route::post('availability-override', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'addAvailabilityOverride'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('availability.override');
                Route::post('packages/{packageId}/admin', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updatePackageAdmin'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('packages.admin');
                Route::post('bulk/assign-tickets-yesterday', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'bulkAssignTicketsFromYesterday'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.tickets.manage'])
                    ->name('bulk.assign-tickets-yesterday');
                Route::get('trainers-pending-payout', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'trainersWithPendingPayout'])
                    ->middleware('gymies.admin.capability:admin.payouts.view')
                    ->name('trainers.pending-payout');

                Route::get('security/events', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'securityEvents'])
                    ->middleware('gymies.admin.capability:admin.security.view')
                    ->name('security.events');
                Route::get('security/ip-allowlist', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'ipAllowlist'])
                    ->middleware('gymies.admin.capability:admin.security.manage')
                    ->name('security.ip.index');
                Route::post('security/ip-allowlist', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'addIpAllowlist'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.security.manage'])
                    ->name('security.ip.add');
                Route::post('security/ip-allowlist/{id}/remove', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'removeIpAllowlist'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.security.manage'])
                    ->name('security.ip.remove');

                Route::get('broadcasts', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'broadcastsIndex'])
                    ->middleware('gymies.admin.capability:admin.security.view')
                    ->name('broadcasts.index');
                Route::post('broadcasts', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'broadcastStore'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.security.manage'])
                    ->name('broadcasts.store');
                Route::delete('broadcasts/{id}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'broadcastDestroy'])
                    ->middleware(['gymies.admin.capability:admin.security.manage'])
                    ->name('broadcasts.destroy');

                Route::get('audit', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'audits'])
                    ->middleware('gymies.admin.capability:admin.audit.view')
                    ->name('audit.index');
                Route::post('audit/{auditId}/revert', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'auditRevert'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.audit.view'])
                    ->name('audit.revert');
                Route::get('audit/export', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'auditsExport'])
                    ->middleware('gymies.admin.capability:admin.audit.view')
                    ->name('audit.export');

                Route::get('profitability/overview', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'profitabilityOverview'])
                    ->middleware('gymies.admin.capability:admin.payments.view')
                    ->name('profitability.overview');
                Route::get('profitability/settings', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'profitabilitySettings'])
                    ->middleware('gymies.admin.capability:admin.payments.view')
                    ->name('profitability.settings');
                Route::post('profitability/settings', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateProfitabilitySettings'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payments.manage'])
                    ->name('profitability.settings.update');

                Route::get('site-media', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'siteMediaPublic'])
                    ->middleware('gymies.admin.capability:admin.access')
                    ->name('admin.site-media.get');
                // Geen idempotency-cache: elke save moet opnieuw naar DB (cache gaf oude response → "niks doorgevoerd").
                Route::put('site-media', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateSiteMedia'])
                    ->middleware(['gymies.admin.capability:admin.payments.manage'])
                    ->name('admin.site-media.update');
                Route::post('site-media', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateSiteMedia'])
                    ->middleware(['gymies.admin.capability:admin.payments.manage'])
                    ->name('admin.site-media.update.post');
                Route::post('site-media/upload', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'uploadSiteMedia'])
                    ->middleware(['gymies.admin.capability:admin.payments.manage'])
                    ->name('admin.site-media.upload');

                Route::get('retention/sleeping-wallets', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'sleepingWallets'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('retention.sleeping-wallets');
                Route::get('retention/trainer-dropoff', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'trainerDropoffAlerts'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('retention.trainer-dropoff');
                Route::post('nudge', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'sendNudge'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('nudge.send');

                Route::get('leakage/flags', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'chatLeakageFlags'])
                    ->middleware('gymies.admin.capability:admin.tickets.view')
                    ->name('leakage.flags');
                Route::post('leakage/scan', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'scanChatKeywords'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.tickets.manage'])
                    ->name('leakage.scan');
                Route::post('leakage/flags/{flagId}/review', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'reviewLeakageFlag'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.tickets.manage'])
                    ->name('leakage.review');

                Route::get('trainers/tiers', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'trainerTiers'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('trainers.tiers');
                Route::post('users/{userId}/tier', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateUserTier'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('users.tier');
                Route::get('onboarding/pipeline', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'onboardingPipeline'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('onboarding.pipeline');
                Route::get('campaigns', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'bulkCampaigns'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('campaigns.index');
                Route::post('campaigns', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'bulkCampaignStore'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('campaigns.store');
                Route::post('campaigns/{campaignId}/send', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'bulkCampaignSend'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('campaigns.send');
                Route::get('heatmap', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'heatmap'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('heatmap');
                Route::get('heatmap/demand-supply', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'heatmapDemandSupply'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('heatmap.demand-supply');

                Route::get('organisations', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'organisations'])
                    ->middleware('gymies.admin.capability:admin.organisations.view')
                    ->name('organisations.index');
                Route::post('organisations/{orgId}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateOrganisation'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.organisations.manage'])
                    ->name('organisations.update');
                Route::get('organisations/{orgId}/members', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'organisationMembers'])
                    ->middleware('gymies.admin.capability:admin.organisations.view')
                    ->name('organisations.members');
                Route::post('organisations/{orgId}/members/{userId}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateOrganisationMember'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.organisations.manage'])
                    ->name('organisations.members.update');
                Route::get('organisations/{orgId}/settlement-overview', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'organisationSettlementOverview'])
                    ->middleware('gymies.admin.capability:admin.organisations.view')
                    ->name('organisations.settlement-overview');
                Route::get('organisations/{orgId}/settlement-report', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'organisationSettlementReport'])
                    ->middleware('gymies.admin.capability:admin.organisations.view')
                    ->name('organisations.settlement-report');

                // ─── Gym Demo Requests (admin) ──────────────────────────────
                Route::get('demo-requests', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'demoRequests'])
                    ->middleware('gymies.admin.capability:admin.organisations.view')
                    ->name('demo-requests.index');
                Route::put('demo-requests/{id}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateDemoRequest'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.organisations.manage'])
                    ->name('demo-requests.update');
                Route::get('demo-requests/{id}/logs', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'demoRequestLogs'])
                    ->middleware('gymies.admin.capability:admin.organisations.view')
                    ->name('demo-requests.logs');
                Route::post('demo-requests/{id}/resend-invite', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'resendDemoInvite'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.organisations.manage'])
                    ->name('demo-requests.resend-invite');

                Route::get('ghost-ratings', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'ghostRatingDashboard'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('ghost-ratings.dashboard');

                // ── Ambassador beheer (admin) ────────────────────────────────────────────
                Route::prefix('ambassador')->name('ambassador.')->group(function () {
                    // Aanvragen
                    Route::get('applications',                  [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminApplications'])
                        ->middleware('gymies.admin.capability:admin.access')->name('applications.index');
                    // Route: applications/{id} show — handled by adminApplications with ?id= filter
                    Route::post('applications/{id}/approve',    [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminApprove'])
                        ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])->name('applications.approve');
                    Route::post('applications/{id}/reject',     [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminReject'])
                        ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])->name('applications.reject');
                    // Ambassadeurs overzicht
                    Route::get('list',                          [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminList'])
                        ->middleware('gymies.admin.capability:admin.access')->name('list');
                    // Route: {id} show — use adminList with filter; no dedicated show method in controller
                    Route::post('{id}/toggle-active',           [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminToggleActive'])
                        ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])->name('toggle-active');
                    Route::post('{id}/set-tier',                [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminSetTier'])
                        ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])->name('set-tier');
                    // Conversies & uitbetalingen
                    Route::get('list',                          [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminList'])
                        ->middleware('gymies.admin.capability:admin.access')->name('list.index');
                    Route::post('payouts/{id}/mark-paid',       [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminMarkPaid'])
                        ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payouts.manage'])->name('payouts.mark-paid');
                });
            });

        // ── Cyber Security Dashboard ──────────────────────────────────────────
        // Niveau 1+2 beveiligde omgeving:
        //   • gymies.admin.ip    — IP-whitelist (alleen bekende IPs)
        //   • throttle:5,1       — max 5 verzoeken/minuut extra bescherming
        //   • gymies.cyber       — is_cyber check + X-Cyber-Token sessie validatie + audit log
        //
        // Auth endpoints: los van de cyber middleware (geen X-Cyber-Token vereist voor inloggen)
        Route::prefix('cyber')
            ->name('cyber.')
            ->middleware(['gymies.admin.ip', 'throttle:120,1'])
            ->group(function () {

                // ── Cyber Auth (PIN + sessie beheer) — geen cyber token vereist ──
                // Rate limit strenger: max 10 verzoeken per minuut (brute-force bescherming)
                Route::prefix('auth')
                    ->name('auth.')
                    ->middleware(['throttle:10,1'])
                    ->group(function () {
                        Route::post('',           [\App\Http\Controllers\Gymies\GymiesCyberAuthController::class, 'login'])
                            ->name('login');
                        Route::post('setup-pin',  [\App\Http\Controllers\Gymies\GymiesCyberAuthController::class, 'setupPin'])
                            ->name('setup-pin');
                        Route::delete('',         [\App\Http\Controllers\Gymies\GymiesCyberAuthController::class, 'logout'])
                            ->name('logout');
                        Route::get('status',      [\App\Http\Controllers\Gymies\GymiesCyberAuthController::class, 'status'])
                            ->name('status');
                    });

                // ── Beveiligde panelen: vereisen X-Cyber-Token ───────────────────
                Route::middleware(['gymies.cyber:cyber.access'])
                    ->group(function () {
                // Systeem health overzicht
                Route::get('health',        [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'health'])
                    ->name('health');

                // ── Cyber: Gebruikersbeheer ───────────────────────────────────────────────
                Route::get('users',                      [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'userList'])->middleware('gymies.cyber:cyber.access');
                Route::get('users/{id}',                 [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'userDetail'])->middleware('gymies.cyber:cyber.access');
                Route::post('users/{id}/promote',        [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'promoteToTrainer'])->middleware(['gymies.idempotency', 'gymies.cyber:cyber.access']);
                Route::post('users/{id}/assign-sub',     [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'assignSubscription'])->middleware(['gymies.idempotency', 'gymies.cyber:cyber.access']);
                Route::post('users/{id}/partner',        [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'togglePartner'])->middleware(['gymies.idempotency', 'gymies.cyber:cyber.access']);
                Route::post('users/{id}/pause',          [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'pauseAccount'])->middleware(['gymies.idempotency', 'gymies.cyber:cyber.access']);
                Route::get('points/leaderboard',         [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'pointsLeaderboard'])->middleware('gymies.cyber:cyber.access');
                Route::post('points/adjust/{userId}',    [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'adjustPoints'])->middleware(['gymies.idempotency', 'gymies.cyber:cyber.access']);
                Route::get('points/rules',               [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'pointsRules'])->middleware('gymies.cyber:cyber.access');
                Route::put('points/rules/{id}',          [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'updatePointsRule'])->middleware(['gymies.idempotency', 'gymies.cyber:cyber.access']);

                // Nginx status
                Route::get('nginx',         [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'nginx'])
                    ->middleware('gymies.cyber:cyber.nginx.view')
                    ->name('nginx');

                // API health (Mollie + Brevo)
                Route::get('api-health',    [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'apiHealth'])
                    ->middleware('gymies.cyber:cyber.api.view')
                    ->name('api-health');

                // Netwerk traffic
                Route::get('network-traffic', [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'networkTraffic'])
                    ->middleware('gymies.cyber:cyber.network.view')
                    ->name('network-traffic');

                // Berichten monitor
                Route::get('messages',      [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'messages'])
                    ->middleware('gymies.cyber:cyber.messages.view')
                    ->name('messages');

                // Security events
                Route::get('security-events', [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'securityEvents'])
                    ->middleware('gymies.cyber:cyber.security.view')
                    ->name('security-events');

                // Actieve sessies
                Route::get('sessions',      [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'activeSessions'])
                    ->middleware('gymies.cyber:cyber.sessions.view')
                    ->name('sessions');

                // Auth log
                Route::get('auth-log',      [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'authLog'])
                    ->middleware('gymies.cyber:cyber.auth.view')
                    ->name('auth-log');

                // Rate limit monitor
                Route::get('rate-limits',   [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'rateLimits'])
                    ->middleware('gymies.cyber:cyber.ratelimit.view')
                    ->name('rate-limits');

                // Geo & IP reputatie
                Route::get('geo',           [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'geo'])
                    ->middleware('gymies.cyber:cyber.geo.view')
                    ->name('geo');

                // Webhook integriteit
                Route::get('webhooks',      [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'webhooks'])
                    ->middleware('gymies.cyber:cyber.webhook.view')
                    ->name('webhooks');

                // API error log
                Route::get('error-log',     [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'errorLog'])
                    ->middleware('gymies.cyber:cyber.errorlog.view')
                    ->name('error-log');

                // Server resources (CPU, RAM, disk)
                Route::get('server',        [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'server'])
                    ->middleware('gymies.cyber:cyber.server.view')
                    ->name('server');

                // Cron job status
                Route::get('crons',         [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'crons'])
                    ->middleware('gymies.cyber:cyber.cron.view')
                    ->name('crons');

                // Log viewer (Laravel logs)
                Route::get('logs',          [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'logs'])
                    ->middleware('gymies.cyber:cyber.logs.view')
                    ->name('logs');

                // SSL/TLS details
                Route::get('ssl',           [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'ssl'])
                    ->middleware('gymies.cyber:cyber.ssl.view')
                    ->name('ssl');

                // File integrity check
                Route::get('integrity',     [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'integrity'])
                    ->middleware('gymies.cyber:cyber.integrity.view')
                    ->name('integrity');
                Route::post('integrity/snapshot', [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'integritySnapshot'])
                    ->middleware(['gymies.idempotency', 'gymies.cyber:cyber.integrity.view'])
                    ->name('integrity.snapshot');

                // Backup status
                Route::get('backup',        [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'backup'])
                    ->middleware('gymies.cyber:cyber.backup.view')
                    ->name('backup');

                // Alert management
                Route::post('alerts/{id}/acknowledge', [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'acknowledgeAlert'])
                    ->middleware(['gymies.idempotency', 'gymies.cyber:cyber.security.view'])
                    ->name('alerts.acknowledge');
                Route::post('alerts/{id}/resolve', [\App\Http\Controllers\Gymies\GymiesCyberController::class, 'resolveAlert'])
                    ->middleware(['gymies.idempotency', 'gymies.cyber:cyber.security.view'])
                    ->name('alerts.resolve');

                    }); // einde beveiligde panelen (gymies.cyber middleware)
            }); // einde cyber prefix groep
    });
});

// ========== GYMIES WEBAPP (Flutter op /gymies) ==========
Route::get('/gymies', fn () => response()->file(public_path('gymies/index.html')));
Route::get('/gymies/{path}', function (string $path) {
    $path = str_replace(['..', '\\'], '', $path);
    $file = public_path('gymies/' . $path);
    if (is_file($file)) {
        return response()->file($file);
    }
    return response()->file(public_path('gymies/index.html'));
})->where('path', '.*')->name('gymies.catchall');
