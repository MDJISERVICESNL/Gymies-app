<?php
/**
 * Gymies API + Flutter catchall.
 * Gebruik in Laravel routes/web.php:
 *   require __DIR__ . '/path/to/backend/routes_gymies_full.php';
 * Of: plak de inhoud van dit bestand (vanaf regel 8) onderaan routes/web.php onder dezelfde prefix api/gymies.
 */

// ========== GYMIES API (prefix api/gymies) ==========
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
        // verify-email + resend staan hierboven (dubbele registratie voorkomen)
    });

    // --- Klanten (publiek): trainers zoeken, groepslessen, Mollie webhook ---
    Route::middleware('gymies.rate.limit:api')->group(function () {
        Route::post('search-log', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'logSearch'])->name('search.log');
    });
    Route::get('trainers', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'index'])->name('trainers.index');
    Route::get('trainers/landing-cities', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'landingCities'])->name('trainers.landing-cities');
    Route::get('trainers/landing-nearby', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'landingNearby'])->name('trainers.landing-nearby');
    Route::get('trainers/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'show'])->name('trainers.show');
    Route::get('trainers/{id}/availability', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'publicAvailability'])->name('trainers.availability');
    Route::get('trainers/{id}/blocked-slots', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'blockedSlots'])->name('trainers.blocked-slots');
    Route::get('trainers/{id}/packages', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'packages'])->name('trainers.packages');
    Route::get('trainers/{id}/media', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'media'])->name('trainers.media');
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
    Route::get('ambassador/code/validate',       [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'validateCode'])->name('ambassador.code.validate');
    Route::get('ambassador/list',               [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'publicList'])->name('ambassador.list');
    Route::get('ambassador/profile/{slug}',    [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'publicProfile'])->name('ambassador.profile');
    // Publiek: valideer gym invite token (voor registratie met invite link)
    Route::get('gym/invites/validate', [\App\Http\Controllers\Gymies\GymiesGymInviteController::class, 'validateToken'])->name('gym.invites.validate');

    Route::get('group-sessions', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'index'])->name('group-sessions.index');
    Route::get('group-sessions/{id}', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'show'])->name('group-sessions.show');
    // Mollie webhooks: rate-limited tegen flooding (60/min). Verificatie via terugbellen Mollie API.
    Route::middleware('gymies.rate.limit:webhook')->group(function () {
        Route::match(['get', 'post'], 'webhooks/mollie', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'mollieWebhookHandler'])->name('webhooks.mollie');
        Route::match(['get', 'post'], 'webhooks/mollie-subscription', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'subscriptionWebhook'])->name('webhooks.mollie-subscription');
    });
    Route::get('onboarding/mollie-connect/callback', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'mollieConnectCallback'])->name('onboarding.mollie-connect.callback');
    // --- Cron-endpoints: beveiligd met GymiesCronMiddleware (X-Cron-Secret header) ---
    Route::middleware([\App\Http\Middleware\GymiesCronMiddleware::class])->group(function () {
        Route::post('cron/expire-pending-bookings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expirePendingBookings'])->name('cron.expire-pending-bookings');
        Route::post('cron/expire-reserved-bookings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireReservedBookings'])->name('cron.expire-reserved-bookings');
        Route::match(['get', 'post'], 'cron/booking-reminders', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'bookingReminders'])->name('cron.booking-reminders');
        Route::post('cron/expire-group-sessions-min-not-reached', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireGroupSessionsMinNotReached'])->name('cron.expire-group-sessions-min-not-reached');
        Route::post('cron/expire-group-session-claim-pending', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireGroupSessionClaimPending'])->name('cron.expire-group-session-claim-pending');
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
        Route::match(['get', 'post'], 'cron/ambassador-tier-evaluation', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'evaluateAmbassadorTiers'])->name('cron.ambassador-tier-evaluation');
        Route::match(['get', 'post'], 'cron/reconcile-mollie-payments', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'reconcileMolliePayments'])->name('cron.reconcile-mollie-payments');
    });

    // --- Beveiligd (Bearer token): Klanten, Trainers, Gyms, Admin ---
    Route::middleware(['gymies.auth', \App\Http\Middleware\GymiesSentryContextMiddleware::class, 'gymies.rate.limit:api', 'gymies.error_log'])->group(function () {

        // Klanten: profiel, sessies, boekingen, support, notificaties, consent, betalingen, groepslessen, conversaties
        Route::get('me', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'me'])->name('me');
        Route::put('me', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'updateMe'])->name('me.update');
        Route::post('me', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'updateMe'])->name('me.update.post');
        Route::post('auth/change-password', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'changePassword'])->name('auth.change-password');
        Route::get('auth/sessions', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'sessions'])->name('auth.sessions');
        Route::post('auth/logout-device', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'logoutDevice'])->name('auth.logout-device');
        Route::post('auth/logout-all-devices', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'logoutAllDevices'])->name('auth.logout-all-devices');
        // ops/health is publiek (zie boven) voor load balancers; metrics blijft beveiligd
        Route::get('ops/metrics', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'metrics'])->name('ops.metrics');
        Route::post('ops/run-backup', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'runBackup'])->name('ops.run-backup');
        Route::post('ops/run-web-sync', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'runWebSync'])->name('ops.run-web-sync');
        Route::get('feature-flags', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'featureFlags'])->name('ops.feature-flags');
        Route::get('broadcasts/active', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'broadcastsActive'])->name('broadcasts.active');
        Route::get('broadcasting/config', [\App\Http\Controllers\Gymies\GymiesBroadcastController::class, 'config'])->name('broadcasting.config');
        Route::post('broadcasting/auth', [\App\Http\Controllers\Gymies\GymiesBroadcastController::class, 'authenticate'])->name('broadcasting.auth');
        Route::get('gdpr/export', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'export'])->name('gdpr.export');
        Route::get('gdpr/export/pdf', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'exportPdf'])->name('gdpr.export-pdf');
        Route::post('gdpr/delete-request', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'deleteRequest'])->name('gdpr.delete-request');
        Route::post('gdpr/delete-account', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'deleteAccount'])->name('gdpr.delete-account');
        Route::get('consent', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'consent'])->name('consent.get');
        Route::put('consent', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'updateConsent'])->name('consent.update');
        Route::post('consent', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'updateConsent'])->name('consent.update.post');
        Route::get('bookings', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'index'])->name('bookings.index');
        Route::get('trainer/summary', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'trainerSummary'])->name('trainer.summary');

        // Wachtlijst: klant-acties
        Route::get('waitlist', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'index'])->name('waitlist.index');
        Route::get('waitlist/me', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'index'])->name('waitlist.me');
        Route::post('waitlist', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'store'])->name('waitlist.store');
        Route::post('waitlist/join', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'store'])->name('waitlist.join');
        Route::delete('waitlist/{id}', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'destroy'])->name('waitlist.destroy');
        Route::delete('waitlist/leave/{id}', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'destroy'])->name('waitlist.leave');
        Route::post('waitlist/{id}/accept', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'accept'])->name('waitlist.accept');
        Route::post('waitlist/offers/{id}/accept', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'accept'])->name('waitlist.offers.accept');
        Route::post('waitlist/accept', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'accept'])->name('waitlist.accept.generic');
        Route::get('trainer/waitlist', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'trainerIndex'])->name('trainer.waitlist.index');
        Route::post('bookings/{id}/waitlist/notify', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'notify'])->name('waitlist.notify');
        Route::post('bookings/{id}/standby/notify', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'notify'])->name('standby.notify');
        Route::post('waitlist/notify', [\App\Http\Controllers\Gymies\GymiesWaitlistController::class, 'notify'])->name('waitlist.notify.generic');
        Route::get('trainer/me', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'me'])->name('trainer.me');
        Route::put('trainer/me', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'updateMe'])->name('trainer.me.update');
        Route::post('trainer/me', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'updateMe'])->name('trainer.me.update.post');
        Route::post('bookings/direct-book', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'storeDirectBook'])->name('bookings.direct-book');

        // Trainers: beschikbaarheid, pakketten, media, uitbetalingen, groepslessen, conversaties
        Route::middleware('gymies.idempotency')->group(function () {
            Route::post('bookings/{id}/confirm', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'confirm'])->name('bookings.confirm');
            Route::post('bookings/{id}/accept-reserved-cash', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'acceptReservedCash'])->name('bookings.accept-reserved-cash');
            Route::post('bookings/{id}/reschedule', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'reschedule'])->name('bookings.reschedule');
            Route::post('bookings/{id}/reschedule-request', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'rescheduleRequest'])->name('bookings.reschedule-request');
            Route::post('bookings/{id}/reschedule-respond', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'rescheduleRespond'])->name('bookings.reschedule-respond');
            Route::get('bookings/{id}/cancellation-preview', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'cancellationPreview'])->name('bookings.cancellation-preview');
            Route::post('bookings/{id}/cancel', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'cancel'])->name('bookings.cancel');
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
            Route::post('bookings/{id}/checkout', [\App\Http\Controllers\Gymies\GymiesCheckinController::class, 'checkOut'])->name('bookings.checkout');
            Route::post('bookings/{id}/confirm-cash', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'confirmCashPayment'])->middleware('gymies.idempotency')->name('bookings.confirm-cash');
            Route::post('trainer/bookings/{id}/payments/cash/confirm', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'confirmCashPayment'])->middleware('gymies.idempotency')->name('trainer.bookings.payments.cash.confirm');
            Route::post('bookings/{id}/ghost-rating', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'submitGhostRating'])->name('bookings.ghost-rating');
            Route::post('bookings/{id}/review', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'storeReview'])->name('bookings.review.store');
            Route::get('bookings/{id}/review', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'getBookingReview'])->name('bookings.review.get');
            Route::post('bookings/{id}/review-response', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'storeReviewResponse'])->name('bookings.review-response.store');
            Route::post('trainer/payouts/request-now', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'requestPayoutNow'])->name('trainer.payouts.request-now');
        });
        Route::get('trainer/availability', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'index'])->name('trainer.availability.index');
        Route::post('trainer/availability/slots', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'storeSlot'])->name('trainer.availability.slots.store');
        Route::put('trainer/availability/slots/{id}', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'updateSlot'])->name('trainer.availability.slots.update');
        Route::delete('trainer/availability/slots/{id}', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'deleteSlot'])->name('trainer.availability.slots.delete');
        Route::post('trainer/availability/exceptions', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'storeException'])->name('trainer.availability.exceptions.store');
        Route::put('trainer/availability/exceptions/{id}', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'updateException'])->name('trainer.availability.exceptions.update');
        Route::delete('trainer/availability/exceptions/{id}', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'deleteException'])->name('trainer.availability.exceptions.delete');
        Route::get('trainer/revenue', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'revenue'])->name('trainer.revenue');
        Route::patch('trainer/fee-preference', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'updateFeePreference'])->name('trainer.fee-preference');
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

        // Gyms: dashboard, trainers, boekingen, settlements, instellingen, leden
        Route::get('gym/dashboard', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'dashboard'])->name('gym.dashboard');
        Route::get('gym/dashboard-stats', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'dashboardStats'])->name('gym.dashboard.stats');
        Route::get('gym/occupancy', [\App\Http\Controllers\Gymies\GymiesGymController::class, 'occupancy'])->name('gym.occupancy');
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
        // Elite: locaties, teams, uitnodigingen
        Route::get('gym/locations', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'index'])->name('gym.locations.index');
        Route::post('gym/locations', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'store'])->name('gym.locations.store');
        Route::get('gym/locations/{id}', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'show'])->name('gym.locations.show');
        Route::get('gym/locations/{id}/blocks', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'blocks'])->name('gym.locations.blocks');
        Route::post('gym/locations/{id}/blocks', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'storeBlock'])->name('gym.locations.blocks.store');
        Route::delete('gym/locations/{id}/blocks/{blockId}', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'destroyBlock'])->name('gym.locations.blocks.destroy');
        Route::get('gym/locations/{id}/conflicts', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'conflicts'])->name('gym.locations.conflicts');
        Route::put('gym/locations/{id}', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'update'])->name('gym.locations.update');
        Route::delete('gym/locations/{id}', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'destroy'])->name('gym.locations.destroy');
        Route::get('gym/teams', [\App\Http\Controllers\Gymies\GymiesGymTeamController::class, 'index'])->name('gym.teams.index');
        Route::post('gym/teams', [\App\Http\Controllers\Gymies\GymiesGymTeamController::class, 'store'])->name('gym.teams.store');
        Route::put('gym/teams/{id}', [\App\Http\Controllers\Gymies\GymiesGymTeamController::class, 'update'])->name('gym.teams.update');
        Route::post('gym/teams/{id}/members', [\App\Http\Controllers\Gymies\GymiesGymTeamController::class, 'addMember'])->name('gym.teams.members.add');
        Route::delete('gym/teams/{id}/members/{trainerUserId}', [\App\Http\Controllers\Gymies\GymiesGymTeamController::class, 'removeMember'])->name('gym.teams.members.remove');
        Route::get('gym/invites', [\App\Http\Controllers\Gymies\GymiesGymInviteController::class, 'index'])->name('gym.invites.index');
        Route::post('gym/invites', [\App\Http\Controllers\Gymies\GymiesGymInviteController::class, 'store'])->name('gym.invites.store');
        Route::delete('gym/invites/{id}', [\App\Http\Controllers\Gymies\GymiesGymInviteController::class, 'destroy'])->name('gym.invites.destroy');
        Route::post('gym/invites/accept', [\App\Http\Controllers\Gymies\GymiesGymInviteController::class, 'accept'])->name('gym.invites.accept');
        // Trainer-trainer chat binnen gym
        Route::get('gym/trainer-chat/conversations', [\App\Http\Controllers\Gymies\GymiesGymTrainerChatController::class, 'index'])->name('gym.trainer-chat.conversations');
        Route::post('gym/trainer-chat/conversations', [\App\Http\Controllers\Gymies\GymiesGymTrainerChatController::class, 'ensure'])->name('gym.trainer-chat.ensure');
        Route::get('gym/trainer-chat/conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesGymTrainerChatController::class, 'messages'])->name('gym.trainer-chat.messages');
        Route::post('gym/trainer-chat/conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesGymTrainerChatController::class, 'send'])->name('gym.trainer-chat.send');
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
        Route::get('trainer/clients', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientsIndex'])->name('trainer.clients.index');
        Route::get('trainer/retention/sleeping-clients', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sleepingClients'])->name('trainer.retention.sleeping-clients');
        Route::get('trainer/pro/client-health', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'proClientHealth'])->name('trainer.pro.client-health');
        Route::get('trainer/pro/upsell-suggestions', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'proUpsellSuggestions'])->name('trainer.pro.upsell-suggestions.index');
        Route::post('trainer/pro/upsell-suggestions/{suggestionId}/send', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'proUpsellSuggestionsSend'])->name('trainer.pro.upsell-suggestions.send');
        Route::get('trainer/pro/rebook-suggestions', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'proRebookSuggestions'])->name('trainer.pro.rebook-suggestions.index');
        Route::post('trainer/pro/rebook-suggestions/{suggestionId}/send', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'proRebookSuggestionsSend'])->name('trainer.pro.rebook-suggestions.send');
        Route::get('trainer/clients/{clientUserId}/progress', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientProgressIndex'])->name('trainer.clients.progress.index');
        Route::post('trainer/clients/{clientUserId}/progress', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientProgressStore'])->name('trainer.clients.progress.store');
        Route::get('trainer/clients/{clientUserId}/dossier', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientDossierGet'])->name('trainer.clients.dossier.show');
        Route::put('trainer/clients/{clientUserId}/dossier', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientDossierPut'])->name('trainer.clients.dossier.update');
        Route::get('trainer/clients/{clientUserId}/dossier/summary', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientDossierSummary'])->name('trainer.clients.dossier.summary');
        Route::get('trainer/clients/{clientUserId}/session-entries', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sessionEntriesIndex'])->name('trainer.clients.session-entries.index');
        Route::post('trainer/clients/{clientUserId}/session-entries', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sessionEntriesStore'])->name('trainer.clients.session-entries.store');
        Route::patch('trainer/clients/{clientUserId}/session-entries/{entryId}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sessionEntriesPatch'])->name('trainer.clients.session-entries.patch');
        Route::delete('trainer/clients/{clientUserId}/session-entries/{entryId}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sessionEntriesDelete'])->name('trainer.clients.session-entries.delete');
        Route::get('trainer/clients/{clientUserId}/goals', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientGoalsIndex'])->name('trainer.clients.goals.index');
        Route::post('trainer/clients/{clientUserId}/goals', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientGoalsStore'])->name('trainer.clients.goals.store');
        Route::patch('trainer/clients/{clientUserId}/goals/{goalId}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientGoalsPatch'])->name('trainer.clients.goals.patch');
        Route::post('trainer/clients/{clientUserId}/goals/{goalId}/progress-points', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientGoalsProgressPointStore'])->name('trainer.clients.goals.progress-points.store');
        Route::get('trainer/clients/{clientUserId}/session-notes', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientSessionNotesIndex'])->name('trainer.clients.session-notes.index');
        Route::post('trainer/clients/bulk-message', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'bulkMessageClients'])->name('trainer.clients.bulk-message');
        Route::post('trainer/promo-to-favorites', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'promoToFavorites'])->name('trainer.promo-to-favorites');
        Route::get('trainer/studio/performance-summary', [\App\Http\Controllers\Gymies\GymiesStudioAnalyticsController::class, 'performanceSummary'])->name('trainer.studio.performance-summary');
        Route::get('trainer/studio/capacity-week', [\App\Http\Controllers\Gymies\GymiesStudioAnalyticsController::class, 'capacityWeek'])->name('trainer.studio.capacity-week');
        Route::get('trainer/studio/safety-log', [\App\Http\Controllers\Gymies\GymiesStudioAnalyticsController::class, 'safetyLog'])->name('trainer.studio.safety-log');
        Route::put('trainer/bookings/{bookingId}/session-note', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sessionNotePut'])->name('trainer.bookings.session-note');
        Route::get('trainer/storefront-cms', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'storefrontCmsGet'])->name('trainer.storefront-cms.get');
        Route::put('trainer/storefront-cms', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'storefrontCmsPut'])->name('trainer.storefront-cms.put');
        Route::post('trainer/storefront-cms', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'storefrontCmsPut'])->name('trainer.storefront-cms.post');
        Route::get('trainer/media', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'media'])->name('trainer.media');
        Route::post('trainer/media/upload', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'uploadMedia'])->name('trainer.media.upload');
        Route::post('trainer/media', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'storeMedia'])->name('trainer.media.store');
        Route::put('trainer/media/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'updateMedia'])->name('trainer.media.update');
        Route::delete('trainer/media/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'deleteMedia'])->name('trainer.media.delete');
        Route::get('trainer/conversations', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'conversations'])->name('trainer.conversations');
        Route::post('trainer/conversations/ensure', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'ensureConversation'])->name('trainer.conversations.ensure');
        Route::get('trainer/conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'messages'])->name('trainer.conversations.messages');
        Route::post('trainer/conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sendMessage'])->name('trainer.conversations.messages.send');
        Route::post('trainer/conversations/{id}/mark-read', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'markConversationRead'])->name('trainer.conversations.mark-read');
        Route::post('trainer/conversations/{id}/typing', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'typing'])->name('trainer.conversations.typing');
        Route::get('trainer/conversations/{id}/context', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'conversationContext'])->name('trainer.conversations.context');
        Route::get('trainer/live-counters', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'liveCounters'])->name('trainer.live-counters');
        Route::post('trainer/report-issue', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'reportIssue'])->name('trainer.report-issue');
        Route::get('notifications', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'index'])->name('notifications.index');
        Route::get('notifications/unread-count', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'unreadCount'])->name('notifications.unread-count');
        Route::post('notifications/mark-read', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'markRead'])->name('notifications.mark-read');
        Route::get('notifications/preferences', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'preferences'])->name('notifications.preferences');
        Route::put('notifications/preferences', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'updatePreferences'])->name('notifications.preferences.update');
        Route::post('notifications/preferences', [\App\Http\Controllers\Gymies\GymiesNotificationController::class, 'updatePreferences'])->name('notifications.preferences.update.post');
        Route::get('support/tickets', [\App\Http\Controllers\Gymies\GymiesSupportController::class, 'index'])->name('support.tickets.index');
        Route::post('support/tickets', [\App\Http\Controllers\Gymies\GymiesSupportController::class, 'store'])->name('support.tickets.store');
        Route::get('support/tickets/{id}', [\App\Http\Controllers\Gymies\GymiesSupportController::class, 'show'])->name('support.tickets.show');
        Route::post('support/tickets/{id}/messages', [\App\Http\Controllers\Gymies\GymiesSupportController::class, 'addMessage'])->name('support.tickets.messages.add');
        Route::post('support/tickets/{id}/mark-helped', [\App\Http\Controllers\Gymies\GymiesSupportController::class, 'markHelped'])->name('support.tickets.mark-helped');
        Route::post('bookings/{id}/payments/validate-promo', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'validatePromo'])->name('bookings.payments.validate-promo');
        Route::post('bookings/{id}/payments/start', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'startPayment'])->name('bookings.payments.start');
        Route::get('bookings/{id}/payment-status', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'paymentStatus'])->name('bookings.payment-status');
        Route::post('group-session-participants/{participantId}/validate-promo', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'validatePromoForGroupParticipant'])->name('group-session-participants.validate-promo');
        Route::post('group-session-participants/{participantId}/payments/start', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'startGroupParticipantPayment'])->name('group-session-participants.payments.start');
        Route::get('group-session-participants/{participantId}/payment-status', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'groupParticipantPaymentStatus'])->name('group-session-participants.payment-status');

        Route::get('my-group-registrations', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'myRegistrations'])->name('my-group-registrations');

        Route::get('conversations', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'index'])->name('client.conversations.index');
        Route::post('conversations/ensure', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'ensure'])->name('client.conversations.ensure');
        Route::get('conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'messages'])->name('client.conversations.messages');
        Route::post('conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'sendMessage'])->name('client.conversations.send');
        Route::post('conversations/{id}/mark-read', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'markRead'])->name('client.conversations.mark-read');
        Route::post('conversations/{id}/typing', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'typing'])->name('client.conversations.typing');
        Route::get('conversations/{id}/context', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'conversationContext'])->name('client.conversations.context');
        Route::get('me/progress', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'myProgressForTrainer'])->name('client.me.progress');
        Route::get('me/shared-dossier', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'mySharedDossierFromTrainer'])->name('client.me.shared-dossier');
        Route::get('me/session-entries', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'mySharedSessionEntriesForTrainer'])->name('client.me.session-entries');
        Route::get('me/goals', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'mySharedGoalsForTrainer'])->name('client.me.goals');
        Route::get('me/dossier-summary', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'mySharedDossierSummaryForTrainer'])->name('client.me.dossier-summary');
        Route::get('me/buddy-stats', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'buddyStats'])->name('client.me.buddy-stats');
        Route::post('me/buddy-search/start', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'buddySearchStart'])->name('client.me.buddy-search.start');
        // Alias: buddy/pool/join → buddy-search/start (Flutter app candidate path)
        Route::post('buddy/pool/join', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'buddySearchStart'])->name('client.buddy.pool.join');
        Route::post('buddy/pool/leave', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'buddySearchStop'])->name('client.buddy.pool.leave');
        Route::post('me/buddy-search/stop', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'buddySearchStop'])->name('client.me.buddy-search.stop');


        // Klant progress-dashboard & workouts
        Route::get('client/progress-dashboard', [\App\Http\Controllers\Gymies\GymiesClientDashboardController::class, 'progressDashboard'])->name('client.progress-dashboard');
        Route::get('me/workouts', [\App\Http\Controllers\Gymies\GymiesClientDashboardController::class, 'myWorkouts'])->name('client.me.workouts');

        Route::get('me/favorites', [\App\Http\Controllers\Gymies\GymiesFavoritesController::class, 'index'])->name('client.me.favorites');
        Route::post('me/favorites', [\App\Http\Controllers\Gymies\GymiesFavoritesController::class, 'store'])->name('client.me.favorites.store');
        Route::delete('me/favorites/{trainerId}', [\App\Http\Controllers\Gymies\GymiesFavoritesController::class, 'destroy'])->name('client.me.favorites.destroy');

        Route::get('referral/my-code', [\App\Http\Controllers\Gymies\GymiesReferralController::class, 'myCode'])->name('referral.my-code');

        // ── Ambassador: eigen dashboard ────────────────────────────────────────────
        Route::get('ambassador/my',              [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'me'])->name('ambassador.my');
        Route::post('ambassador/iban',           [\App\Http\Controllers\Gymies\GymiesAmbassadorController::class, 'saveIban'])
            ->middleware('gymies.idempotency')->name('ambassador.iban.save');

        // Trainer onboarding & subscription
        Route::get('onboarding/status', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'onboardingStatus'])->name('onboarding.status');
        Route::post('onboarding/upload-document', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'uploadDocument'])->name('onboarding.upload-document');
        Route::post('onboarding/mollie-connect/start', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'startMollieConnect'])->name('onboarding.mollie-connect.start');
        Route::post('onboarding/select-plan', [\App\Http\Controllers\Gymies\GymiesOnboardingController::class, 'selectPlan'])->name('onboarding.select-plan');
        Route::get('subscription/my', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'mySubscription'])->name('subscription.my');
        Route::post('subscription/change-plan', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'changePlan'])->name('subscription.change-plan');
        Route::post('subscription/cancel', [\App\Http\Controllers\Gymies\GymiesSubscriptionController::class, 'cancelSubscription'])->name('subscription.cancel');
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

        // Refunds & group payment overview (trainer)
        Route::get('trainer/refunds', [\App\Http\Controllers\Gymies\GymiesRefundController::class, 'trainerRefunds'])->name('trainer.refunds');
        Route::get('trainer/group-sessions/{id}/payment-overview', [\App\Http\Controllers\Gymies\GymiesRefundController::class, 'groupSessionPaymentOverview'])->name('trainer.group-sessions.payment-overview');

        // Waitlist endpoints
        Route::get('trainer/group-sessions/{id}/waitlist', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'waitlist'])->name('trainer.group-sessions.waitlist');
        Route::post('trainer/group-sessions/{sessionId}/waitlist/{clientUserId}/promote', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'promoteWaitlistParticipant'])->name('trainer.group-sessions.waitlist.promote');

        // Crowdfund cron: auto-cancel sessies voorbij deadline
        Route::post('cron/crowdfund-check', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'cronCrowdfundCheck'])->name('cron.crowdfund-check');

        // ── Gymies Points ────────────────────────────────────────────────────────
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
                Route::get('ops/filter-definitions', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'filterDefinitions'])->name('ops.filter-definitions');
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
                    ->name('users.impersonate');
                Route::post('users/{userId}/assign-subscription', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'assignSubscription'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.users.manage'])
                    ->name('users.assign-subscription');
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
                    ->name('bookings.cancel');
                Route::post('bookings/{bookingId}/waive-trainer-penalty', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'waiveTrainerPenalty'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('bookings.waive-trainer-penalty');
                Route::post('bookings/{bookingId}/refund-or-credit', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'refundOrCredit'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('bookings.refund-or-credit');
                Route::post('bookings/{bookingId}/reschedule', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'rescheduleBooking'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('bookings.reschedule');
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
