<?php

/**
 * Gymies API routes (prefix api/gymies).
 * Included from routes/web.php.
 * Secties: Auth (publiek), Klanten (publiek), Beveiligd (Klanten, Trainers, Gyms, Admin).
 */

// ========== GYMIES API (prefix api/gymies) ==========
Route::prefix('api/gymies')->name('api.gymies.')->group(function () {

    // Auth resend/verify buiten rate-limit-groep (404-fix + alias resend-mail)
    Route::post('auth/resend-verification-code', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'resendVerificationCode'])->name('auth.resend-verification-code');
    Route::post('auth/verify-email', [\App\Http\Controllers\Gymies\GymiesAuthController::class, 'verifyEmail'])->name('auth.verify-email');

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

    // --- Gym registratie (publiek, rate-limited) ---
    Route::middleware('gymies.rate.limit:register')->group(function () {
        Route::post('gym/register', [\App\Http\Controllers\Gymies\GymiesGymRegistrationController::class, 'register'])->name('gym.register');
        Route::post('gym/request-demo', [\App\Http\Controllers\Gymies\GymiesGymRegistrationController::class, 'requestDemo'])->name('gym.request-demo');
        Route::get('gym/validate-invite-token', [\App\Http\Controllers\Gymies\GymiesGymRegistrationController::class, 'validateInviteToken'])->name('gym.validate-invite-token');
        Route::post('gym/register-with-token', [\App\Http\Controllers\Gymies\GymiesGymRegistrationController::class, 'registerWithToken'])->name('gym.register-with-token');
        Route::get('gym/demo-status', [\App\Http\Controllers\Gymies\GymiesGymRegistrationController::class, 'demoStatus'])->name('gym.demo-status');
    });

    // --- Publiek contactformulier (rate-limited, geen auth) ---
    Route::middleware('gymies.rate.limit:register')->group(function () {
        Route::post('public/contact', [\App\Http\Controllers\Gymies\GymiesSupportController::class, 'publicContact'])->name('public.contact');
    });

    // --- Klanten (publiek): trainers zoeken, groepslessen, Mollie webhook ---
    Route::get('trainers', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'index'])->name('trainers.index');
    Route::get('trainers/landing-cities', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'landingCities'])->name('trainers.landing-cities');
    Route::get('trainers/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'show'])->name('trainers.show');
    Route::get('trainers/{id}/availability', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'publicAvailability'])->name('trainers.availability');
    Route::get('trainers/{id}/blocked-slots', [\App\Http\Controllers\Gymies\GymiesAvailabilityController::class, 'blockedSlots'])->name('trainers.blocked-slots');
    Route::get('trainers/{id}/packages', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'packages'])->name('trainers.packages');
    Route::get('trainers/{id}/media', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'media'])->name('trainers.media');
    Route::get('trainers/{id}/latest-review', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'latestReview'])->name('trainers.latest-review');
    Route::get('site-media', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'siteMediaPublic'])->name('site-media');
    Route::get('referral/validate', [\App\Http\Controllers\Gymies\GymiesReferralController::class, 'validateCode'])->name('referral.validate');
    Route::get('group-sessions', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'index'])->name('group-sessions.index');
    Route::get('group-sessions/{id}', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'show'])->name('group-sessions.show');
    Route::match(['get', 'post'], 'webhooks/mollie', [\App\Http\Controllers\Gymies\GymiesPaymentController::class, 'mollieWebhookHandler'])->name('webhooks.mollie');
    Route::match(['get', 'post'], 'webhooks/mollie-gym-subscription', [\App\Http\Controllers\Gymies\GymiesGymSubscriptionController::class, 'mollieGymWebhook'])->name('webhooks.mollie-gym-subscription');
    Route::post('cron/expire-pending-bookings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expirePendingBookings'])->name('cron.expire-pending-bookings');
    Route::post('cron/expire-reserved-bookings', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireReservedBookings'])->name('cron.expire-reserved-bookings');
    Route::post('cron/expire-group-sessions-min-not-reached', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireGroupSessionsMinNotReached'])->name('cron.expire-group-sessions-min-not-reached');
    Route::post('cron/expire-group-session-claim-pending', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireGroupSessionClaimPending'])->name('cron.expire-group-session-claim-pending');
    Route::match(['get', 'post'], 'cron/auto-complete-sessions', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'autoCompletePastSessions'])->name('cron.auto-complete-sessions');
    Route::match(['get', 'post'], 'cron/availability-check', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'availabilityCheck'])->name('cron.availability-check');
    Route::match(['get', 'post'], 'cron/auto-pilot-retention', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'autoPilotRetention'])->name('cron.auto-pilot-retention');
    Route::match(['get', 'post'], 'cron/auto-pilot-low-credit', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'autoPilotLowCredit'])->name('cron.auto-pilot-low-credit');
    Route::match(['get', 'post'], 'cron/expire-spoed-inval', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'expireSpoedInval'])->name('cron.expire-spoed-inval');
    Route::match(['get', 'post'], 'cron/spoed-inval-batch1', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'spoedInvalBatch1'])->name('cron.spoed-inval-batch1');
    Route::match(['get', 'post'], 'cron/process-notification-emails', [\App\Http\Controllers\Gymies\GymiesCronController::class, 'processNotificationEmails'])->name('cron.process-notification-emails');

    // --- Beveiligd (Bearer token): Klanten, Trainers, Gyms, Admin ---
    Route::middleware(['gymies.auth', 'gymies.rate.limit:api', 'gymies.error_log'])->group(function () {

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
        Route::post('ops/run-backup', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'runBackup'])->name('ops.run-backup');
        Route::post('ops/run-web-sync', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'runWebSync'])->name('ops.run-web-sync');
        Route::get('feature-flags', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'featureFlags'])->name('ops.feature-flags');
        Route::get('gdpr/export', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'export'])->name('gdpr.export');
        Route::post('gdpr/delete-request', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'deleteRequest'])->name('gdpr.delete-request');
        Route::get('consent', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'consent'])->name('consent.get');
        Route::put('consent', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'updateConsent'])->name('consent.update');
        Route::post('consent', [\App\Http\Controllers\Gymies\GymiesComplianceController::class, 'updateConsent'])->name('consent.update.post');
        Route::get('bookings', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'index'])->name('bookings.index');
        Route::get('trainer/summary', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'trainerSummary'])->name('trainer.summary');
        Route::get('trainer/me', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'me'])->name('trainer.me');
        Route::get('trainer/profile', [\App\Http\Controllers\Gymies\GymiesTrainerController::class, 'me'])->name('trainer.profile');
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
            Route::get('bookings/{id}/review-status', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'getReviewStatus'])->name('bookings.review-status');
            Route::post('bookings/{id}/session-status', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'sessionStatus'])->name('bookings.session-status');
            Route::post('bookings/{id}/report-trainer-no-show', [\App\Http\Controllers\Gymies\GymiesBookingController::class, 'reportTrainerNoShow'])->name('bookings.report-trainer-no-show');
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
        // Priority Pool: favoriete collega's
        Route::get('trainer/favorite-colleagues', [\App\Http\Controllers\Gymies\GymiesSpoedInvalController::class, 'getFavoriteColleagues'])->name('trainer.favorite-colleagues');
        Route::put('trainer/favorite-colleagues', [\App\Http\Controllers\Gymies\GymiesSpoedInvalController::class, 'updateFavoriteColleagues'])->name('trainer.favorite-colleagues.update');

        // Gyms: registratie onboarding
        Route::post('gym/onboarding', [\App\Http\Controllers\Gymies\GymiesGymRegistrationController::class, 'onboarding'])->name('gym.onboarding');

        // Gyms: abonnementen & billing
        Route::get('gym/plans', [\App\Http\Controllers\Gymies\GymiesGymSubscriptionController::class, 'availableGymPlans'])->name('gym.plans');
        Route::get('gym/subscription', [\App\Http\Controllers\Gymies\GymiesGymSubscriptionController::class, 'myGymSubscription'])->name('gym.subscription');
        Route::get('gym/subscription/payments', [\App\Http\Controllers\Gymies\GymiesGymSubscriptionController::class, 'paymentHistory'])->name('gym.subscription.payments');
        Route::middleware('gymies.idempotency')->group(function () {
            Route::post('gym/subscription/start', [\App\Http\Controllers\Gymies\GymiesGymSubscriptionController::class, 'startGymSubscription'])->name('gym.subscription.start');
            Route::post('gym/subscription/activate', [\App\Http\Controllers\Gymies\GymiesGymSubscriptionController::class, 'activateGymSubscription'])->name('gym.subscription.activate');
            Route::post('gym/subscription/cancel', [\App\Http\Controllers\Gymies\GymiesGymSubscriptionController::class, 'cancelGymSubscription'])->name('gym.subscription.cancel');
            Route::post('gym/subscription/billing-cycle', [\App\Http\Controllers\Gymies\GymiesGymSubscriptionController::class, 'changeBillingCycle'])->name('gym.subscription.billing-cycle');
        });

        // Gyms: locatiebeheer (meerdere vestigingen)
        Route::get('gym/locations', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'index'])->name('gym.locations.index');
        Route::get('gym/locations/{id}', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'show'])->name('gym.locations.show');
        Route::middleware('gymies.idempotency')->group(function () {
            Route::post('gym/locations', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'store'])->name('gym.locations.store');
            Route::put('gym/locations/{id}', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'update'])->name('gym.locations.update');
            Route::delete('gym/locations/{id}', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'destroy'])->name('gym.locations.destroy');
            Route::get('gym/locations/{id}/blocks', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'blocks'])->name('gym.locations.blocks');
            Route::post('gym/locations/{id}/blocks', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'storeBlock'])->name('gym.locations.blocks.store');
            Route::delete('gym/locations/{id}/blocks/{blockId}', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'destroyBlock'])->name('gym.locations.blocks.destroy');
            Route::get('gym/locations/{id}/conflicts', [\App\Http\Controllers\Gymies\GymiesGymLocationController::class, 'conflicts'])->name('gym.locations.conflicts');
        });

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
        // Trainer-locatiebeheer (gym, thuis, buiten, online)
        Route::get('trainer/locations', [\App\Http\Controllers\Gymies\GymiesTrainerLocationController::class, 'index'])->name('trainer.locations.index');
        Route::post('trainer/locations', [\App\Http\Controllers\Gymies\GymiesTrainerLocationController::class, 'store'])->name('trainer.locations.store');
        Route::put('trainer/locations/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerLocationController::class, 'update'])->name('trainer.locations.update');
        Route::delete('trainer/locations/{id}', [\App\Http\Controllers\Gymies\GymiesTrainerLocationController::class, 'destroy'])->name('trainer.locations.delete');

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
        Route::get('trainer/conversations/{id}/context', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'conversationContext'])->name('trainer.conversations.context');
        Route::get('trainer/clients', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientsIndex'])->name('trainer.clients.index');
        Route::get('trainer/retention/sleeping-clients', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sleepingClients'])->name('trainer.retention.sleeping-clients');
        Route::get('trainer/clients/{clientUserId}/progress', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientProgressIndex'])->name('trainer.clients.progress.index');
        Route::post('trainer/clients/{clientUserId}/progress', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientProgressStore'])->name('trainer.clients.progress.store');
        Route::get('trainer/clients/{clientUserId}/dossier', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientDossierGet'])->name('trainer.clients.dossier.show');
        Route::put('trainer/clients/{clientUserId}/dossier', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientDossierPut'])->name('trainer.clients.dossier.update');
        Route::get('trainer/clients/{clientUserId}/session-notes', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientSessionNotesIndex'])->name('trainer.clients.session-notes.index');
        Route::post('trainer/clients/bulk-message', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'bulkMessageClients'])->name('trainer.clients.bulk-message');
        Route::get('trainer/studio/performance-summary', [\App\Http\Controllers\Gymies\GymiesStudioAnalyticsController::class, 'performanceSummary'])->name('trainer.studio.performance-summary');
        Route::get('trainer/studio/capacity-week', [\App\Http\Controllers\Gymies\GymiesStudioAnalyticsController::class, 'capacityWeek'])->name('trainer.studio.capacity-week');
        Route::get('trainer/studio/safety-log', [\App\Http\Controllers\Gymies\GymiesStudioAnalyticsController::class, 'safetyLog'])->name('trainer.studio.safety-log');
        Route::put('trainer/bookings/{bookingId}/session-note', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sessionNotePut'])->name('trainer.bookings.session-note');

        // ── Invoices (trainer + klant) ──────────────────────────────────────────
        Route::get('trainer/invoices', [\App\Http\Controllers\Gymies\GymiesInvoiceController::class, 'trainerInvoices'])->name('trainer.invoices.index');
        Route::get('trainer/invoices/quarter-zip', [\App\Http\Controllers\Gymies\GymiesInvoiceController::class, 'trainerInvoicesQuarterZip'])->name('trainer.invoices.quarter-zip');
        Route::get('client/invoices', [\App\Http\Controllers\Gymies\GymiesInvoiceController::class, 'clientInvoices'])->name('client.invoices.index');
        Route::get('client/invoices/{id}/download', [\App\Http\Controllers\Gymies\GymiesInvoiceController::class, 'clientInvoiceDownload'])->name('client.invoices.download');

        // ── Session Entries (dossier tijdlijn per klant) ────────────────────────
        Route::get('trainer/clients/{clientUserId}/session-entries', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sessionEntriesIndex'])->name('trainer.clients.session-entries.index');
        Route::post('trainer/clients/{clientUserId}/session-entries', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sessionEntriesStore'])->name('trainer.clients.session-entries.store');
        Route::patch('trainer/clients/{clientUserId}/session-entries/{entryId}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sessionEntriesPatch'])->name('trainer.clients.session-entries.patch');
        Route::delete('trainer/clients/{clientUserId}/session-entries/{entryId}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'sessionEntriesDelete'])->name('trainer.clients.session-entries.delete');

        // ── Client Goals (doelen per klant) ─────────────────────────────────────
        Route::get('trainer/clients/{clientUserId}/goals', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientGoalsIndex'])->name('trainer.clients.goals.index');
        Route::post('trainer/clients/{clientUserId}/goals', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientGoalsStore'])->name('trainer.clients.goals.store');
        Route::patch('trainer/clients/{clientUserId}/goals/{goalId}', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientGoalsPatch'])->name('trainer.clients.goals.patch');
        Route::post('trainer/clients/{clientUserId}/goals/{goalId}/progress', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'clientGoalsProgressPointStore'])->name('trainer.clients.goals.progress.store');

        // ── Pro: client health, upsell & rebook suggesties ──────────────────────
        Route::get('trainer/pro/client-health', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'proClientHealth'])->name('trainer.pro.client-health');
        Route::get('trainer/pro/upsell-suggestions', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'proUpsellSuggestions'])->name('trainer.pro.upsell-suggestions');
        Route::post('trainer/pro/upsell-suggestions/{suggestionId}/send', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'proUpsellSuggestionsSend'])->name('trainer.pro.upsell-suggestions.send');
        Route::get('trainer/pro/rebook-suggestions', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'proRebookSuggestions'])->name('trainer.pro.rebook-suggestions');
        Route::post('trainer/pro/rebook-suggestions/{suggestionId}/send', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'proRebookSuggestionsSend'])->name('trainer.pro.rebook-suggestions.send');

        // ── Utility endpoints ───────────────────────────────────────────────────
        Route::post('trainer/conversations/{conversationId}/typing', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'typing'])->name('trainer.conversations.typing');
        Route::put('trainer/fee-preference', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'updateFeePreference'])->name('trainer.fee-preference');
        Route::post('trainer/promo-to-favorites', [\App\Http\Controllers\Gymies\GymiesTrainerOpsController::class, 'promoToFavorites'])->name('trainer.promo-to-favorites');

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

        // Klant progress-dashboard & workouts
        Route::get('client/progress-dashboard', [\App\Http\Controllers\Gymies\GymiesClientDashboardController::class, 'progressDashboard'])->name('client.progress-dashboard');
        Route::get('me/workouts', [\App\Http\Controllers\Gymies\GymiesClientDashboardController::class, 'myWorkouts'])->name('client.me.workouts');

        Route::get('conversations', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'index'])->name('client.conversations.index');
        Route::post('conversations/ensure', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'ensure'])->name('client.conversations.ensure');
        Route::get('conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'messages'])->name('client.conversations.messages');
        Route::post('conversations/{id}/messages', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'sendMessage'])->name('client.conversations.send');
        Route::post('conversations/{id}/mark-read', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'markRead'])->name('client.conversations.mark-read');
        Route::get('conversations/{id}/context', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'conversationContext'])->name('client.conversations.context');
        Route::get('me/progress', [\App\Http\Controllers\Gymies\GymiesClientConversationController::class, 'myProgressForTrainer'])->name('client.me.progress');

        Route::get('referral/my-code', [\App\Http\Controllers\Gymies\GymiesReferralController::class, 'myCode'])->name('referral.my-code');
        Route::post('group-sessions/{id}/register', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'register'])->name('group-sessions.register');
        Route::post('group-sessions/{id}/cancel-registration', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'cancelRegistration'])->name('group-sessions.cancel-registration');

        Route::get('trainer/group-sessions', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'trainerIndex'])->name('trainer.group-sessions.index');
        Route::post('trainer/group-sessions', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'store'])->name('trainer.group-sessions.store');
        Route::post('trainer/group-sessions/recurring', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'storeRecurring'])->name('trainer.group-sessions.recurring');
        Route::put('trainer/group-sessions/{id}', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'update'])->name('trainer.group-sessions.update');
        Route::post('trainer/group-sessions/{id}/publish', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'publish'])->name('trainer.group-sessions.publish');
        Route::post('trainer/group-sessions/{id}/confirm', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'confirm'])->name('trainer.group-sessions.confirm');
        Route::post('trainer/group-sessions/{id}/cancel', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'cancel'])->name('trainer.group-sessions.cancel');
        Route::get('trainer/group-sessions/{id}/participants', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'participants'])->name('trainer.group-sessions.participants');
        Route::post('trainer/group-sessions/{id}/participants/{participantId}/attended', [\App\Http\Controllers\Gymies\GymiesGroupSessionController::class, 'markParticipantAttended'])->name('trainer.group-sessions.participants.attended');

        // ── Pro+ features (tier 2+) ─ branding, newsletter, widget, QR, analytics ──
        Route::get('trainer/pro-plus/settings', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'getSettings'])->name('trainer.pro-plus.settings');
        Route::put('trainer/pro-plus/settings', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'updateSettings'])->name('trainer.pro-plus.settings.update');
        Route::post('trainer/pro-plus/newsletter', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'sendNewsletter'])->name('trainer.pro-plus.newsletter');
        Route::get('trainer/pro-plus/widget-code', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'getWidgetCode'])->name('trainer.pro-plus.widget');
        Route::get('trainer/pro-plus/qr-code', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'getQRCode'])->name('trainer.pro-plus.qr-code');
        Route::get('trainer/pro-plus/client-analytics', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'getClientAnalytics'])->name('trainer.pro-plus.analytics');
        Route::post('trainer/pro-plus/upload-logo', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'uploadLogo'])->name('trainer.pro-plus.upload-logo');
        Route::post('trainer/pro-plus/upload-banner', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'uploadBanner'])->name('trainer.pro-plus.upload-banner');
        Route::post('trainer/pro-plus/upload-video', [\App\Http\Controllers\Gymies\GymiesProPlusController::class, 'uploadVideo'])->name('trainer.pro-plus.upload-video');

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
                Route::post('bookings/{bookingId}/reschedule', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'rescheduleBooking'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('bookings.reschedule');
                Route::post('bookings/{bookingId}/incident', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'addBookingIncident'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('bookings.incident');

                Route::get('disputes', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'disputes'])
                    ->middleware('gymies.admin.capability:admin.bookings.view')
                    ->name('disputes.index');
                Route::get('disputes/{disputeId}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'disputeDetail'])
                    ->middleware('gymies.admin.capability:admin.bookings.view')
                    ->name('disputes.detail');
                Route::post('disputes/{disputeId}/resolve', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'resolveDispute'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.bookings.manage'])
                    ->name('disputes.resolve');
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

                Route::get('plans', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'plansIndex'])
                    ->middleware('gymies.admin.capability:admin.payments.view')
                    ->name('plans.index');
                Route::post('plans/{planId}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'plansUpdate'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payments.manage'])
                    ->name('plans.update');
                Route::post('plans/sync-to-site', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'plansSyncToSite'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.payments.manage'])
                    ->name('plans.sync-to-site');

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

                Route::get('audit', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'audits'])
                    ->middleware('gymies.admin.capability:admin.audit.view')
                    ->name('audit.index');
                Route::post('audit/{auditId}/revert', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'auditRevert'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.audit.view'])
                    ->name('audit.revert');
                Route::get('audit/export', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'auditsExport'])
                    ->middleware('gymies.admin.capability:admin.audit.view')
                    ->name('audit.export');

                // Gym demo-aanvragen beheer
                Route::get('demo-requests', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'demoRequests'])
                    ->middleware('gymies.admin.capability:admin.organisations.view')
                    ->name('demo-requests.index');
                Route::post('demo-requests/{id}', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateDemoRequest'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.organisations.manage'])
                    ->name('demo-requests.update');
                Route::post('demo-requests/{id}/resend-invite', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'resendDemoInvite'])
                    ->middleware(['gymies.idempotency', 'gymies.admin.capability:admin.organisations.manage'])
                    ->name('demo-requests.resend-invite');
                Route::get('demo-requests/{id}/logs', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'demoRequestLogs'])
                    ->middleware('gymies.admin.capability:admin.organisations.view')
                    ->name('demo-requests.logs');

                // Gym registraties overzicht
                Route::get('gym-registrations', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'gymRegistrations'])
                    ->middleware('gymies.admin.capability:admin.organisations.view')
                    ->name('gym-registrations.index');

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

                Route::get('site-media', [\App\Http\Controllers\Gymies\GymiesOpsController::class, 'siteMediaPublic'])
                    ->middleware('gymies.admin.capability:admin.access')
                    ->name('admin.site-media.get');
                Route::put('site-media', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateSiteMedia'])
                    ->middleware(['gymies.admin.capability:admin.payments.manage'])
                    ->name('admin.site-media.update');
                Route::post('site-media', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'updateSiteMedia'])
                    ->middleware(['gymies.admin.capability:admin.payments.manage'])
                    ->name('admin.site-media.update.post');
                Route::post('site-media/upload', [\App\Http\Controllers\Gymies\GymiesAdminController::class, 'uploadSiteMedia'])
                    ->middleware(['gymies.admin.capability:admin.payments.manage'])
                    ->name('admin.site-media.upload');
            });
    });
});
