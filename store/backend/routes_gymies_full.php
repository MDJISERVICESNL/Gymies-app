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
Route::prefix('api/gymies')->name('api.gymies.')->middleware([\App\Http\Middleware\GymiesHmacMiddleware::class])->group(function () {

    // Auth resend/verify buiten rate-limit-groep (404-fix) + alias auth/resend-mail
    Route::post('auth/resend-verification-code', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'resendVerificationCode'])->name('auth.resend-verification-code');
    Route::post('auth/resend-mail', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'resendVerificationCode'])->name('auth.resend-mail');
    Route::post('auth/verify-email', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'verifyEmail'])->name('auth.verify-email');
    Route::post('auth/verify-email-link', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'verifyEmailLink'])->name('auth.verify-email-link');

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
    });

    // --- App versie check (publiek, geen auth nodig) ---
    Route::get('app-version', [\App\Http\Controllers\Gymies\GymiesHealthController::class, 'appVersion'])->name('app-version');

    // --- Health check (publiek, geen auth nodig — voor uptime monitoring / load balancers) ---
    Route::get('health', [\App\Http\Controllers\Gymies\GymiesHealthController::class, 'ping'])->name('health');

    // --- Feature flags (publiek, Flutter haalt flags op bij startup) ---
    // Optioneel: stuur access_token mee voor user-specifieke flags (rollout %).
    Route::get('feature-flags', function (\Illuminate\Http\Request $request) {
        $userId = null;
        $role   = null;

        // Probeer user uit token te halen (optioneel — endpoint werkt ook zonder auth)
        $token = $request->bearerToken() ?? $request->query('access_token');
        if ($token) {
            $session = \Illuminate\Support\Facades\DB::table('gymies_personal_access_tokens')
                ->where('token', hash('sha256', $token))
                ->where(function ($q) {
                    $q->whereNull('expires_at')->orWhere('expires_at', '>', now());
                })
                ->first();
            if ($session) {
                $user = \Illuminate\Support\Facades\DB::table('gymies_users')->where('id', $session->user_id)->first();
                if ($user) {
                    $userId = (int) $user->id;
                    $role   = $user->role ?? null;
                }
            }
        }

        return response()->json([
            'flags' => \App\Http\Controllers\Gymies\GymiesFeatureFlags::all($userId, $role),
        ]);
    })->name('feature-flags');

    // --- Klanten (publiek): trainers zoeken, groepslessen, Mollie webhook ---
    // Rate limited: search & publieke data endpoints (60 req/min per IP)
    Route::middleware('gymies.rate.limit:api')->group(function () {
        Route::post('search-log', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'logSearch'])->name('search.log');
        Route::get('specialties', [\App\Http\Controllers\Gymies\GymiesSpecialtyController::class, 'index'])->name('specialties.index');
        Route::get('trainers', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'index'])->name('trainers.index');
        Route::get('trainers/by-slug/{slug}', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'showBySlug'])->name('trainers.by-slug');
        Route::get('trainers/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'show'])->name('trainers.show');
        Route::get('trainers/{id}/availability', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'publicAvailability'])->name('trainers.availability');
        Route::get('trainers/{id}/blocked-slots', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'blockedSlots'])->name('trainers.blocked-slots');
        Route::get('trainers/{id}/packages', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'packages'])->name('trainers.packages');
        Route::get('trainers/{id}/media', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'media'])->name('trainers.media');
        Route::get('trainers/{id}/reviews', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'reviews'])->name('trainers.reviews');
        Route::get('site-media', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'siteMediaPublic'])->name('site-media');
        Route::get('referral/validate', [\App\Http\Controllers\Gymies\GymiesReferralController::class, 'validateCode'])->name('referral.validate');
    });

    // --- Ambassador (publiek, rate limited) ---
    Route::middleware('gymies.rate.limit:api')->group(function () {
        Route::get('ambassador/validate-code', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'validateCode'])->name('ambassador.validate-code');
        Route::get('ambassadors', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'publicList'])->name('ambassadors.index');
        Route::get('ambassador/profile/{slug}', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'publicProfile'])->name('ambassador.profile');
    });
    Route::middleware('gymies.rate.limit:register')->group(function () {
        Route::post('ambassador/apply', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'apply'])->name('ambassador.apply');
    });
    Route::get('group-sessions', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'index'])->name('group-sessions.index');
    Route::get('group-sessions/{id}', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'show'])->name('group-sessions.show');
    Route::match(['get', 'post'], 'webhooks/mollie', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'mollieWebhookHandler'])->name('webhooks.mollie');
    Route::match(['get', 'post'], 'webhooks/mollie-subscription', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'subscriptionWebhook'])->name('webhooks.mollie-subscription');
    Route::get('onboarding/mollie-connect/callback', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'mollieConnectCallback'])->name('onboarding.mollie-connect.callback');
    // --- Cron-endpoints: beveiligd met GymiesCronMiddleware (X-Cron-Secret header) ---
    Route::middleware([\App\Http\Middleware\GymiesCronMiddleware::class])->group(function () {
        Route::post('cron/expire-pending-bookings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expirePendingBookings'])->name('cron.expire-pending-bookings');
        Route::post('cron/expire-reserved-bookings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireReservedBookings'])->name('cron.expire-reserved-bookings');
        Route::post('cron/expire-group-sessions-min-not-reached', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireGroupSessionsMinNotReached'])->name('cron.expire-group-sessions-min-not-reached');
        Route::post('cron/expire-group-session-claim-pending', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireGroupSessionClaimPending'])->name('cron.expire-group-session-claim-pending');
        Route::match(['get', 'post'], 'cron/auto-complete-sessions', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'autoCompletePastSessions'])->name('cron.auto-complete-sessions');
        Route::match(['get', 'post'], 'cron/availability-check', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'availabilityCheck'])->name('cron.availability-check');
        Route::match(['get', 'post'], 'cron/auto-pilot-retention', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'autoPilotRetention'])->name('cron.auto-pilot-retention');
        Route::match(['get', 'post'], 'cron/auto-pilot-low-credit', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'autoPilotLowCredit'])->name('cron.auto-pilot-low-credit');
        Route::match(['get', 'post'], 'cron/subscription-reminders', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'subscriptionReminders'])->name('cron.subscription-reminders');
        Route::match(['get', 'post'], 'cron/generate-session-invoices', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'generateSessionInvoices'])->name('cron.generate-session-invoices');
        Route::match(['get', 'post'], 'cron/expire-group-session-payment-deadline', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireGroupSessionPaymentDeadline'])->name('cron.expire-group-session-payment-deadline');
        Route::match(['get', 'post'], 'cron/safe-session-overdue', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'checkSafeSessionOverdue'])->name('cron.safe-session-overdue');
        Route::match(['get', 'post'], 'cron/expire-substitute-requests', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireSubstituteRequests'])->name('cron.expire-substitute-requests');
        Route::match(['get', 'post'], 'cron/trigger-ghost-ratings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'triggerGhostRatings'])->name('cron.trigger-ghost-ratings');
        Route::match(['get', 'post'], 'cron/ghost-rating-alerts', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'ghostRatingAlerts'])->name('cron.ghost-rating-alerts');
        Route::match(['get', 'post'], 'cron/expire-subscription-trials', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'expireSubscriptionTrials'])->name('cron.expire-subscription-trials');
        Route::match(['get', 'post'], 'cron/recalculate-quality-scores', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'recalculateQualityScores'])->name('cron.recalculate-quality-scores');
        Route::match(['get', 'post'], 'cron/evaluate-ambassador-tiers', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'evaluateAmbassadorTiers'])->name('cron.evaluate-ambassador-tiers');
        Route::post('cron/crowdfund-check', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'cronCrowdfundCheck'])->name('cron.crowdfund-check');
        // V2: Recurring bookings genereren + waitlist offers expiren
        Route::match(['get', 'post'], 'cron/generate-recurring-bookings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'generateRecurringBookings'])->name('cron.generate-recurring-bookings');
        Route::match(['get', 'post'], 'cron/expire-waitlist-offers', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireWaitlistOffers'])->name('cron.expire-waitlist-offers');
        Route::match(['get', 'post'], 'cron/cleanup-idempotency-keys', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'cleanupIdempotencyKeys'])->name('cron.cleanup-idempotency-keys');
        Route::match(['get', 'post'], 'cron/reconcile-mollie-payments', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'reconcileMolliePayments'])->name('cron.reconcile-mollie-payments');
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

        Route::post('bookings/direct-book', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'storeDirectBook'])->name('bookings.direct-book');
        Route::post('bookings/hold-slot', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'holdSlot'])->name('bookings.hold-slot');
        Route::delete('bookings/hold-slot/{holdId}', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'releaseSlot'])->name('bookings.release-slot');
        Route::post('bookings/hold-slot/{holdId}/extend', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'extendSlotHold'])->name('bookings.extend-slot');

        // Trainers: beschikbaarheid, pakketten, media, uitbetalingen, groepslessen, conversaties
        Route::middleware('gymies.idempotency')->group(function () {
            Route::post('bookings/{id}/confirm', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'confirm'])->name('bookings.confirm');
            Route::post('bookings/{id}/reschedule', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'reschedule'])->name('bookings.reschedule');
            Route::post('bookings/{id}/reschedule-request', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'rescheduleRequest'])->name('bookings.reschedule-request');
            Route::post('bookings/{id}/reschedule-respond', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'rescheduleRespond'])->name('bookings.reschedule-respond');
            Route::get('bookings/{id}/cancellation-preview', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'cancellationPreview'])->name('bookings.cancellation-preview');
            Route::post('bookings/{id}/cancel', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'cancel'])->name('bookings.cancel');
            Route::post('trainer/bookings/{id}/reject', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'reject'])->name('bookings.reject');
            // Refunds
            Route::get('bookings/{id}/refund-preview', [\App\Http\Controllers\Gymies\GymiesRefundController::class, 'bookingRefundPreview'])->name('bookings.refund-preview');
            Route::post('bookings/{id}/refund', [\App\Http\Controllers\Gymies\GymiesRefundController::class, 'refundBooking'])->name('bookings.refund');
            Route::get('group-session-participants/{participantId}/refund-preview', [\App\Http\Controllers\Gymies\GymiesRefundController::class, 'groupParticipantRefundPreview'])->name('group-session-participants.refund-preview');
            Route::post('group-session-participants/{participantId}/refund', [\App\Http\Controllers\Gymies\GymiesRefundController::class, 'refundGroupParticipant'])->name('group-session-participants.refund');
            Route::get('bookings/{id}/review-status', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'getReviewStatus'])->name('bookings.review-status');
            Route::post('bookings/{id}/session-status', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'sessionStatus'])->name('bookings.session-status');
            Route::post('bookings/{id}/report-trainer-no-show', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'reportTrainerNoShow'])->name('bookings.report-trainer-no-show');
            // QR Check-in systeem
            Route::get('bookings/{id}/checkin-qr', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'getCheckinQr'])->name('bookings.checkin-qr');
            Route::post('checkin/scan', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'scanCheckin'])->name('checkin.scan');
            Route::post('checkin/manual', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'manualCheckin'])->name('checkin.manual');
            // Women's Safety: fraude, SOS, safe-session
            Route::post('checkin/report-fraud', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'reportIdentityFraud'])->name('checkin.report-fraud');
            Route::post('sos/alert', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'sosAlert'])->name('sos.alert');
            Route::post('bookings/{id}/safe-session/start', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'startSafeSession'])->name('bookings.safe-session.start');
            Route::post('bookings/{id}/safe-session/heartbeat', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'safeSessionHeartbeat'])->name('bookings.safe-session.heartbeat');
            Route::get('bookings/{id}/safe-session/status', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'safeSessionStatus'])->name('bookings.safe-session.status');
            Route::post('bookings/{id}/checkout', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'checkOut'])->name('bookings.checkout');
            Route::post('bookings/{id}/invoice-request', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'invoiceRequest'])->name('bookings.invoice-request');
            Route::post('bookings/{id}/confirm-cash', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'confirmCashPayment'])->middleware('gymies.idempotency')->name('bookings.confirm-cash');
            Route::post('bookings/{id}/ghost-rating', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'submitGhostRating'])->name('bookings.ghost-rating');
            Route::post('bookings/{id}/review', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'storeReview'])->name('bookings.review.store');
            Route::get('bookings/{id}/review', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'getBookingReview'])->name('bookings.review.get');
            Route::post('bookings/{id}/review-response', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'storeReviewResponse'])->name('bookings.review-response.store');
            Route::post('trainer/payouts/request-now', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'requestPayoutNow'])->name('trainer.payouts.request-now');
            // Payment start routes (idempotent — DB lock prevents race conditions)
            Route::post('bookings/{id}/payments/start', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'startPayment'])->name('bookings.payments.start');
            // BELANGRIJK: promo code use_count moet in de Mollie webhook handler worden verhoogd (na betaling),
            // niet in startPayment (voor betaling). Zie GymiesPaymentController::mollieWebhookHandler().
            Route::post('group-session-participants/{participantId}/payments/start', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'startGroupParticipantPayment'])->name('group-session-participants.payments.start');
        });
        Route::get('trainer/specialties', [\App\Http\Controllers\Gymies\GymiesSpecialtyController::class, 'trainerSpecialties'])->name('trainer.specialties.index');
        Route::put('trainer/specialties', [\App\Http\Controllers\Gymies\GymiesSpecialtyController::class, 'updateTrainerSpecialties'])->name('trainer.specialties.update');
        Route::post('trainer/specialties/request', [\App\Http\Controllers\Gymies\GymiesSpecialtyController::class, 'requestSpecialty'])->name('trainer.specialties.request');
        Route::get('admin/specialty-requests', [\App\Http\Controllers\Gymies\GymiesSpecialtyController::class, 'adminListRequests'])->name('admin.specialty-requests.index');
        Route::put('admin/specialty-requests/{id}', [\App\Http\Controllers\Gymies\GymiesSpecialtyController::class, 'adminHandleRequest'])->name('admin.specialty-requests.handle');
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
        Route::get('gym/settlements', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'settlements'])->name('gym.settlements');
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
        Route::middleware('gymies.idempotency')->group(function () {
            Route::post('gym/settlements/draft', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'createSettlementDraft'])->name('gym.settlements.draft');
            Route::post('gym/settlements/{id}/adjustments', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'addSettlementAdjustment'])->name('gym.settlements.adjustments');
            Route::post('gym/settlements/{id}/transition', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'transitionSettlement'])->name('gym.settlements.transition');
        });
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
                    ->name('admin.plans.index');
                Route::post('plans/{planId}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'plansUpdate'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payments.manage'])
                    ->name('plans.update');
                Route::get('subscription-features', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'subscriptionFeatures'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('subscription-features.index');
                Route::put('subscription-features', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateSubscriptionFeatures'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('subscription-features.update');
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

                Route::post('trainers/{trainerUserId}/boost', [\App\Http\Controllers\Gymies\TrainerBoostAdminController::class, 'setBoost'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('trainers.boost');
                Route::get('trainers/{trainerUserId}/boost', [\App\Http\Controllers\Gymies\TrainerBoostAdminController::class, 'getBoost'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('trainers.boost.get');
                Route::delete('trainers/{trainerUserId}/boost', [\App\Http\Controllers\Gymies\TrainerBoostAdminController::class, 'removeBoost'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('trainers.boost.remove');
                Route::get('trainers/tiers', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'trainerTiers'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('trainers.tiers');
                Route::post('users/{userId}/tier', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateUserTier'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('users.tier');
                Route::post('users/{userId}/assign-subscription', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'performAssignSubscription'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('subscription.assign-to-user');
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

                Route::get('ghost-ratings', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'ghostRatingDashboard'])
                    ->middleware('gymies.admin.capability:admin.users.view')
                    ->name('ghost-ratings.dashboard');

                // --- Admin: Ambassador beheer ---
                Route::get('ambassador/applications', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminApplications'])->name('ambassador.applications');
                Route::post('ambassador/applications/{id}/approve', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminApprove'])->name('ambassador.applications.approve');
                Route::post('ambassador/applications/{id}/reject', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminReject'])->name('ambassador.applications.reject');
                Route::get('ambassador/list', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminList'])->name('ambassador.list');
                Route::post('ambassador/{id}/tier', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminSetTier'])->name('ambassador.set-tier');
                Route::post('ambassador/{id}/toggle-featured', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminToggleFeatured'])->name('ambassador.toggle-featured');
                Route::post('ambassador/{id}/toggle-active', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminToggleActive'])->name('ambassador.toggle-active');
                Route::post('ambassador/{id}/verify-iban', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminVerifyIban'])->name('ambassador.verify-iban');
                Route::post('ambassador/{id}/mark-paid', [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'adminMarkPaid'])->name('ambassador.mark-paid');

                // --- Admin: Fee-beheer ---
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
                    ->middleware(['gymies.admin.capability:admin.payments.manage'])
                    ->name('fees.destroy');
            });
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
