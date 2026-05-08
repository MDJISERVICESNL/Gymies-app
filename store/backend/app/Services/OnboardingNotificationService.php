<?php

declare(strict_types=1);

namespace App\Services;

use App\Http\Controllers\Gymies\FcmPushHelper;
use App\Http\Controllers\Gymies\GymiesAuditTrait;
use App\Jobs\SendGymiesNotificationEmail;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * OnboardingNotificationService
 * ─────────────────────────────
 * Alle push notificaties en e-mails voor het trainer onboarding systeem.
 *
 * Trainer notificaties (7):
 *   1. onboarding_approved       — Aanvraag goedgekeurd
 *   2. onboarding_rejected       — Aanvraag afgewezen
 *   3. trial_halfway             — Trial halverwege
 *   4. trial_expiring_soon       — Trial bijna afgelopen (3 dagen)
 *   5. trial_extended            — Trial verlengd door staff
 *   6. payment_reminder          — Betaalherinnering (mandaat mislukt)
 *   7. onboarding_nudge          — Onboarding niet afgemaakt
 *
 * Staff notificaties (4):
 *   1. new_review_request        — Nieuwe aanvraag te beoordelen
 *   2. sla_warning               — SLA waarschuwing (review > 24u)
 *   3. fraud_alert               — Fraud gedetecteerd bij aanvraag
 *   4. smart_trial_suggestion    — Trainer actief maar trial loopt af
 *
 * Operationele notificaties (12):
 *   1. new_ticket                — Nieuw ticket → staff
 *   2. ticket_reply              — Ticket antwoord → gebruiker
 *   3. ticket_escalated          — Ticket escalatie → admin
 *   4. booking_cancelled         — Booking geannuleerd → trainer + klant
 *   5. booking_rescheduled       — Booking verplaatst → trainer + klant
 *   6. refund_processed          — Refund verwerkt → gebruiker
 *   7. document_reviewed         — Document goed/afgekeurd → trainer
 *   8. dispute_message           — Geschil bericht → tegenpartij
 *   9. dispute_resolved          — Geschil opgelost → trainer + klant
 *  10. new_booking               — Nieuwe boeking → trainer (FCM push)
 *  11. subscription_changed      — Subscription wijziging → trainer
 *  12. nudge (custom)            — Via staffSendNudge → trainer/klant
 *
 * E-mail sequence (3 mails eerste week):
 *   1. welcome_onboarding        — Welkom na aanmelding
 *   2. onboarding_reminder_24h   — Herinnering na 24u als onboarding incompleet
 *   3. onboarding_nudge_72h      — Nudge na 72u als nog steeds incompleet
 */
final class OnboardingNotificationService
{
    use GymiesAuditTrait;

    // ──────────────────────────────────────────────
    //  TRAINER PUSH NOTIFICATIES (7)
    // ──────────────────────────────────────────────

    /**
     * 1. Aanvraag goedgekeurd — trainer mag naar betaalstap.
     */
    public function notifyTrainerApproved(int $trainerUserId, string $trainerName): void
    {
        try {
            FcmPushHelper::sendToUser(
                $trainerUserId,
                'Welkom bij Gymies! 🎉',
                "Hey {$trainerName}, je aanvraag is goedgekeurd! Rond je betaling af om live te gaan.",
                [
                    'type'   => 'onboarding_approved',
                    'action' => 'open_onboarding',
                    'screen' => 'trainer_onboarding',
                ]
            );
        } catch (\Throwable $e) {
            Log::warning('FCM push failed', ['user' => $trainerUserId, 'error' => $e->getMessage()]);
        }

        SendGymiesNotificationEmail::sendOrQueue($trainerUserId, 'onboarding_approved', [
            'trainer_name' => $trainerName,
        ]);

        Log::info('[OnboardingNotification] Trainer approved push sent', ['user_id' => $trainerUserId]);
    }

    /**
     * 2. Aanvraag afgewezen.
     */
    public function notifyTrainerRejected(int $trainerUserId, string $trainerName, string $reason): void
    {
        try {
            FcmPushHelper::sendToUser(
                $trainerUserId,
                'Aanvraag niet goedgekeurd',
                "Hey {$trainerName}, je aanvraag is helaas niet goedgekeurd. Bekijk de reden in de app.",
                [
                    'type'   => 'onboarding_rejected',
                    'action' => 'open_onboarding',
                    'screen' => 'trainer_onboarding',
                    'reason' => $reason,
                ]
            );
        } catch (\Throwable $e) {
            Log::warning('FCM push failed', ['user' => $trainerUserId, 'error' => $e->getMessage()]);
        }

        SendGymiesNotificationEmail::sendOrQueue($trainerUserId, 'onboarding_rejected', [
            'trainer_name' => $trainerName,
            'reason'       => $reason,
        ]);

        Log::info('[OnboardingNotification] Trainer rejected push sent', ['user_id' => $trainerUserId]);
    }

    /**
     * 3. Trial halverwege — trainer herinneren dat de trial doorloopt.
     */
    public function notifyTrialHalfway(int $trainerUserId, string $trainerName, int $daysLeft): void
    {
        try {
            FcmPushHelper::sendToUser(
                $trainerUserId,
                'Je proefperiode is halverwege',
                "Hey {$trainerName}, je hebt nog {$daysLeft} dagen in je proefperiode. Maak het meeste eruit!",
                [
                    'type'      => 'trial_halfway',
                    'action'    => 'open_dashboard',
                    'screen'    => 'trainer_dashboard',
                    'days_left' => (string) $daysLeft,
                ]
            );
        } catch (\Throwable $e) {
            Log::warning('FCM push failed', ['user' => $trainerUserId, 'error' => $e->getMessage()]);
        }

        Log::info('[OnboardingNotification] Trial halfway push sent', [
            'user_id'   => $trainerUserId,
            'days_left' => $daysLeft,
        ]);
    }

    /**
     * 4. Trial bijna afgelopen — 3 dagen resterend.
     */
    public function notifyTrialExpiringSoon(int $trainerUserId, string $trainerName, int $daysLeft): void
    {
        try {
            FcmPushHelper::sendToUser(
                $trainerUserId,
                'Proefperiode loopt bijna af ⏰',
                "Hey {$trainerName}, nog {$daysLeft} dagen! Zorg dat je etalage klaar is voor je eerste klanten.",
                [
                    'type'      => 'trial_expiring_soon',
                    'action'    => 'open_dashboard',
                    'screen'    => 'trainer_dashboard',
                    'days_left' => (string) $daysLeft,
                ]
            );
        } catch (\Throwable $e) {
            Log::warning('FCM push failed', ['user' => $trainerUserId, 'error' => $e->getMessage()]);
        }

        SendGymiesNotificationEmail::sendOrQueue($trainerUserId, 'trial_expiring_soon', [
            'trainer_name' => $trainerName,
            'days_left'    => $daysLeft,
        ]);

        Log::info('[OnboardingNotification] Trial expiring soon push sent', [
            'user_id'   => $trainerUserId,
            'days_left' => $daysLeft,
        ]);
    }

    /**
     * 5. Trial verlengd door staff.
     */
    public function notifyTrialExtended(int $trainerUserId, string $trainerName, int $days, string $newEndDate): void
    {
        try {
            FcmPushHelper::sendToUser(
                $trainerUserId,
                'Proefperiode verlengd!',
                "Hey {$trainerName}, goed nieuws! Je proefperiode is met {$days} dagen verlengd tot {$newEndDate}.",
                [
                    'type'         => 'trial_extended',
                    'action'       => 'open_dashboard',
                    'screen'       => 'trainer_dashboard',
                    'days'         => (string) $days,
                    'new_end_date' => $newEndDate,
                ]
            );
        } catch (\Throwable $e) {
            Log::warning('FCM push failed', ['user' => $trainerUserId, 'error' => $e->getMessage()]);
        }

        Log::info('[OnboardingNotification] Trial extended push sent', [
            'user_id' => $trainerUserId,
            'days'    => $days,
        ]);
    }

    /**
     * 6. Betaalherinnering — mandaat/betaling mislukt.
     */
    public function notifyPaymentReminder(int $trainerUserId, string $trainerName, int $attempt): void
    {
        $urgency = $attempt >= 3 ? 'Laatste kans: ' : '';

        try {
            FcmPushHelper::sendToUser(
                $trainerUserId,
                "{$urgency}Betaling afronden",
                "Hey {$trainerName}, je betaling is nog niet afgerond. Rond het af om actief te blijven.",
                [
                    'type'    => 'payment_reminder',
                    'action'  => 'open_onboarding',
                    'screen'  => 'trainer_onboarding',
                    'attempt' => (string) $attempt,
                ]
            );
        } catch (\Throwable $e) {
            Log::warning('FCM push failed', ['user' => $trainerUserId, 'error' => $e->getMessage()]);
        }

        if ($attempt <= 3) {
            SendGymiesNotificationEmail::sendOrQueue($trainerUserId, 'payment_reminder', [
                'trainer_name' => $trainerName,
                'attempt'      => $attempt,
            ]);
        }

        Log::info('[OnboardingNotification] Payment reminder sent', [
            'user_id' => $trainerUserId,
            'attempt' => $attempt,
        ]);
    }

    /**
     * 7. Onboarding nudge — trainer heeft registratie niet afgemaakt.
     */
    public function notifyOnboardingNudge(int $trainerUserId, string $trainerName): void
    {
        try {
            FcmPushHelper::sendToUser(
                $trainerUserId,
                'Maak je aanmelding af! 💪',
                "Hey {$trainerName}, je bent er bijna. Rond je aanmelding af en start je gratis proefperiode.",
                [
                    'type'   => 'onboarding_nudge',
                    'action' => 'open_onboarding',
                    'screen' => 'trainer_onboarding',
                ]
            );
        } catch (\Throwable $e) {
            Log::warning('FCM push failed', ['user' => $trainerUserId, 'error' => $e->getMessage()]);
        }

        Log::info('[OnboardingNotification] Onboarding nudge sent', ['user_id' => $trainerUserId]);
    }

    // ──────────────────────────────────────────────
    //  STAFF PUSH NOTIFICATIES (4)
    // ──────────────────────────────────────────────

    /**
     * 1. Nieuwe aanvraag te beoordelen.
     */
    public function notifyStaffNewRequest(string $trainerName, int $trainerId): void
    {
        $staffUserIds = $this->getStaffUserIds();

        foreach ($staffUserIds as $staffId) {
            try {
                FcmPushHelper::sendToUser(
                    $staffId,
                    'Nieuwe trainer aanvraag',
                    "{$trainerName} heeft een aanvraag ingediend. Beoordeel deze in het staff dashboard.",
                    [
                        'type'       => 'new_review_request',
                        'action'     => 'open_staff_dashboard',
                        'screen'     => 'staff_dashboard',
                        'trainer_id' => (string) $trainerId,
                    ]
                );
            } catch (\Throwable $e) {
                Log::warning('FCM push failed', ['user' => $staffId, 'error' => $e->getMessage()]);
            }
        }

        Log::info('[OnboardingNotification] Staff notified of new request', [
            'trainer_id'  => $trainerId,
            'staff_count' => count($staffUserIds),
        ]);
    }

    /**
     * 2. SLA waarschuwing — review duurt langer dan 24 uur.
     */
    public function notifyStaffSlaWarning(int $trainerId, string $trainerName, int $hoursWaiting): void
    {
        $staffUserIds = $this->getStaffUserIds();

        foreach ($staffUserIds as $staffId) {
            try {
                FcmPushHelper::sendToUser(
                    $staffId,
                    'SLA Waarschuwing ⚠️',
                    "Aanvraag van {$trainerName} wacht al {$hoursWaiting} uur op beoordeling.",
                    [
                        'type'          => 'sla_warning',
                        'action'        => 'open_staff_dashboard',
                        'screen'        => 'staff_dashboard',
                        'trainer_id'    => (string) $trainerId,
                        'hours_waiting' => (string) $hoursWaiting,
                    ]
                );
            } catch (\Throwable $e) {
                Log::warning('FCM push failed', ['user' => $staffId, 'error' => $e->getMessage()]);
            }
        }

        Log::info('[OnboardingNotification] SLA warning sent', [
            'trainer_id'    => $trainerId,
            'hours_waiting' => $hoursWaiting,
        ]);
    }

    /**
     * 3. Fraud alert — verdachte aanvraag gedetecteerd.
     */
    public function notifyStaffFraudAlert(int $trainerId, string $trainerName, array $warnings): void
    {
        $warningText = implode(', ', array_map(fn($w) => $w['type'] ?? 'onbekend', $warnings));

        $staffUserIds = $this->getStaffUserIds();

        foreach ($staffUserIds as $staffId) {
            FcmPushHelper::sendToUser(
                $staffId,
                'Fraud Alert 🚨',
                "Verdachte aanvraag van {$trainerName}: {$warningText}",
                [
                    'type'       => 'fraud_alert',
                    'action'     => 'open_staff_dashboard',
                    'screen'     => 'staff_dashboard',
                    'trainer_id' => (string) $trainerId,
                    'warnings'   => $warningText,
                ]
            );
        }

        Log::info('[OnboardingNotification] Fraud alert sent to staff', [
            'trainer_id' => $trainerId,
            'warnings'   => $warningText,
        ]);
    }

    /**
     * 4. Smart trial suggestie — trainer actief maar trial loopt af.
     */
    public function notifyStaffSmartTrialSuggestion(int $trainerId, string $trainerName, float $activityScore, int $daysLeft): void
    {
        $staffUserIds = $this->getStaffUserIds();

        foreach ($staffUserIds as $staffId) {
            FcmPushHelper::sendToUser(
                $staffId,
                'Trial verlenging suggestie',
                "{$trainerName} is actief (score: {$activityScore}%) maar trial loopt over {$daysLeft} dagen af.",
                [
                    'type'           => 'smart_trial_suggestion',
                    'action'         => 'open_staff_dashboard',
                    'screen'         => 'staff_dashboard',
                    'trainer_id'     => (string) $trainerId,
                    'activity_score' => (string) $activityScore,
                    'days_left'      => (string) $daysLeft,
                ]
            );
        }

        Log::info('[OnboardingNotification] Smart trial suggestion sent', [
            'trainer_id'     => $trainerId,
            'activity_score' => $activityScore,
            'days_left'      => $daysLeft,
        ]);
    }

    // ──────────────────────────────────────────────
    //  OPERATIONELE PUSH NOTIFICATIES
    // ──────────────────────────────────────────────

    /**
     * Nieuw ticket aangemaakt — staff op de hoogte stellen.
     */
    public function notifyStaffNewTicket(int $ticketId, string $subject, string $userName): void
    {
        $staffUserIds = $this->getStaffUserIds();

        foreach ($staffUserIds as $staffId) {
            try {
                FcmPushHelper::sendToUser(
                    $staffId,
                    'Nieuw support ticket 🎫',
                    "{$userName} heeft een ticket geopend: {$subject}",
                    [
                        'type'      => 'new_ticket',
                        'action'    => 'open_staff_dashboard',
                        'screen'    => 'staff_dashboard',
                        'tab'       => 'support',
                        'ticket_id' => (string) $ticketId,
                    ]
                );
            } catch (\Throwable $e) {
                Log::warning('FCM push failed', ['user' => $staffId, 'error' => $e->getMessage()]);
            }
        }

        Log::info('[Notification] Staff notified of new ticket', [
            'ticket_id' => $ticketId,
            'staff_count' => count($staffUserIds),
        ]);
    }

    /**
     * Ticket reply — gebruiker op de hoogte stellen dat er een antwoord is.
     */
    public function notifyUserTicketReply(int $userId, int $ticketId, string $subject): void
    {
        try {
            FcmPushHelper::sendToUser(
                $userId,
                'Antwoord op je ticket',
                "Er is een reactie op je ticket: {$subject}",
                [
                    'type'      => 'ticket_reply',
                    'action'    => 'open_ticket',
                    'screen'    => 'support',
                    'ticket_id' => (string) $ticketId,
                ]
            );
        } catch (\Throwable $e) {
            Log::warning('FCM push failed', ['user' => $userId, 'error' => $e->getMessage()]);
        }

        Log::info('[Notification] User notified of ticket reply', [
            'user_id'   => $userId,
            'ticket_id' => $ticketId,
        ]);
    }

    /**
     * Ticket geëscaleerd — admin(s) op de hoogte stellen.
     */
    public function notifyAdminTicketEscalated(int $ticketId, string $subject, string $reason): void
    {
        $adminIds = $this->getAdminUserIds();

        foreach ($adminIds as $adminId) {
            FcmPushHelper::sendToUser(
                $adminId,
                'Ticket geëscaleerd ⚠️',
                "Ticket #{$ticketId} ({$subject}) is geëscaleerd: {$reason}",
                [
                    'type'      => 'ticket_escalated',
                    'action'    => 'open_admin_ticket',
                    'screen'    => 'control_tower',
                    'ticket_id' => (string) $ticketId,
                ]
            );
        }

        Log::info('[Notification] Admin notified of escalated ticket', [
            'ticket_id'   => $ticketId,
            'admin_count' => count($adminIds),
        ]);
    }

    /**
     * Booking geannuleerd door staff — trainer + klant op de hoogte.
     */
    public function notifyBookingCancelled(int $bookingId, int $trainerUserId, int $clientUserId, string $reason): void
    {
        FcmPushHelper::sendToUser(
            $trainerUserId,
            'Boeking geannuleerd',
            "Een boeking is geannuleerd door ons team. Reden: {$reason}",
            [
                'type'       => 'booking_cancelled',
                'action'     => 'open_bookings',
                'screen'     => 'trainer_dashboard',
                'booking_id' => (string) $bookingId,
            ]
        );

        FcmPushHelper::sendToUser(
            $clientUserId,
            'Boeking geannuleerd',
            "Je boeking is geannuleerd. Reden: {$reason}",
            [
                'type'       => 'booking_cancelled',
                'action'     => 'open_bookings',
                'screen'     => 'client_bookings',
                'booking_id' => (string) $bookingId,
            ]
        );

        Log::info('[Notification] Booking cancelled push sent', [
            'booking_id'      => $bookingId,
            'trainer_user_id' => $trainerUserId,
            'client_user_id'  => $clientUserId,
        ]);
    }

    /**
     * Booking verplaatst door staff — trainer + klant op de hoogte.
     */
    public function notifyBookingRescheduled(int $bookingId, int $trainerUserId, int $clientUserId, string $newDate): void
    {
        FcmPushHelper::sendToUser(
            $trainerUserId,
            'Boeking verplaatst 📅',
            "Een boeking is verplaatst naar {$newDate}.",
            [
                'type'       => 'booking_rescheduled',
                'action'     => 'open_bookings',
                'screen'     => 'trainer_dashboard',
                'booking_id' => (string) $bookingId,
            ]
        );

        FcmPushHelper::sendToUser(
            $clientUserId,
            'Boeking verplaatst 📅',
            "Je boeking is verplaatst naar {$newDate}.",
            [
                'type'       => 'booking_rescheduled',
                'action'     => 'open_bookings',
                'screen'     => 'client_bookings',
                'booking_id' => (string) $bookingId,
            ]
        );

        Log::info('[Notification] Booking rescheduled push sent', ['booking_id' => $bookingId]);
    }

    /**
     * Refund/credit verwerkt — gebruiker op de hoogte.
     */
    public function notifyRefundProcessed(int $userId, string $type, int $amountCents, int $bookingId): void
    {
        $amount = number_format($amountCents / 100, 2, ',', '.');
        $label = $type === 'wallet_credit' ? 'Tegoed bijgeschreven' : 'Terugbetaling verwerkt';

        FcmPushHelper::sendToUser(
            $userId,
            $label . ' 💰',
            "€{$amount} is " . ($type === 'wallet_credit' ? 'aan je wallet toegevoegd' : 'teruggestort') . ".",
            [
                'type'       => 'refund_processed',
                'action'     => 'open_wallet',
                'screen'     => 'wallet',
                'booking_id' => (string) $bookingId,
                'amount'     => (string) $amountCents,
            ]
        );

        Log::info('[Notification] Refund processed push sent', [
            'user_id'      => $userId,
            'type'         => $type,
            'amount_cents' => $amountCents,
        ]);
    }

    /**
     * Document beoordeeld — trainer op de hoogte (goedgekeurd of afgekeurd).
     */
    public function notifyDocumentReviewed(int $trainerUserId, string $docType, string $decision, ?string $rejectionReason = null): void
    {
        $approved = $decision === 'approved';
        $title = $approved ? 'Document goedgekeurd ✅' : 'Document afgekeurd ❌';
        $body = $approved
            ? "Je {$docType} is goedgekeurd."
            : "Je {$docType} is afgekeurd." . ($rejectionReason ? " Reden: {$rejectionReason}" : ' Upload een nieuw document.');

        FcmPushHelper::sendToUser(
            $trainerUserId,
            $title,
            $body,
            [
                'type'     => 'document_reviewed',
                'action'   => 'open_onboarding',
                'screen'   => 'trainer_onboarding',
                'decision' => $decision,
                'doc_type' => $docType,
            ]
        );

        Log::info('[Notification] Document review push sent', [
            'user_id'  => $trainerUserId,
            'doc_type' => $docType,
            'decision' => $decision,
        ]);
    }

    /**
     * Geschil bericht — tegenpartij op de hoogte stellen.
     */
    public function notifyDisputeMessage(int $recipientUserId, int $disputeId, string $senderName): void
    {
        FcmPushHelper::sendToUser(
            $recipientUserId,
            'Nieuw bericht in geschil',
            "{$senderName} heeft gereageerd op je geschil.",
            [
                'type'       => 'dispute_message',
                'action'     => 'open_dispute',
                'screen'     => 'disputes',
                'dispute_id' => (string) $disputeId,
            ]
        );

        Log::info('[Notification] Dispute message push sent', [
            'recipient_id' => $recipientUserId,
            'dispute_id'   => $disputeId,
        ]);
    }

    /**
     * Geschil opgelost — beide partijen op de hoogte.
     */
    public function notifyDisputeResolved(int $clientUserId, int $trainerUserId, int $disputeId, string $resolutionType): void
    {
        $resLabel = match ($resolutionType) {
            'client_gelijk'  => 'in jouw voordeel besloten',
            'trainer_gelijk' => 'in het voordeel van de trainer besloten',
            'split'          => 'met een compromis opgelost',
            default          => 'opgelost',
        };

        FcmPushHelper::sendToUser(
            $clientUserId,
            'Geschil opgelost ✅',
            "Je geschil is {$resLabel}.",
            [
                'type'            => 'dispute_resolved',
                'action'          => 'open_dispute',
                'screen'          => 'disputes',
                'dispute_id'      => (string) $disputeId,
                'resolution_type' => $resolutionType,
            ]
        );

        $trainerResLabel = match ($resolutionType) {
            'client_gelijk'  => 'in het voordeel van de klant besloten',
            'trainer_gelijk' => 'in jouw voordeel besloten',
            'split'          => 'met een compromis opgelost',
            default          => 'opgelost',
        };

        FcmPushHelper::sendToUser(
            $trainerUserId,
            'Geschil opgelost ✅',
            "Je geschil is {$trainerResLabel}.",
            [
                'type'            => 'dispute_resolved',
                'action'          => 'open_dispute',
                'screen'          => 'disputes',
                'dispute_id'      => (string) $disputeId,
                'resolution_type' => $resolutionType,
            ]
        );

        Log::info('[Notification] Dispute resolved push sent', [
            'dispute_id'      => $disputeId,
            'resolution_type' => $resolutionType,
        ]);
    }

    /**
     * Nieuwe boeking — push naar trainer (FCM i.p.v. alleen in-app queue).
     */
    public function notifyTrainerNewBooking(int $trainerUserId, string $clientName, string $scheduledAt, int $bookingId): void
    {
        FcmPushHelper::sendToUser(
            $trainerUserId,
            'Nieuwe boeking! 🎉',
            "{$clientName} heeft een sessie geboekt op {$scheduledAt}.",
            [
                'type'       => 'new_booking',
                'action'     => 'open_bookings',
                'screen'     => 'trainer_dashboard',
                'booking_id' => (string) $bookingId,
            ]
        );

        Log::info('[Notification] New booking push sent to trainer', [
            'trainer_user_id' => $trainerUserId,
            'booking_id'      => $bookingId,
        ]);
    }

    /**
     * Subscription gewijzigd — trainer op de hoogte.
     */
    public function notifySubscriptionChanged(int $trainerUserId, string $action, ?string $planName = null): void
    {
        $title = match ($action) {
            'assigned'  => 'Abonnement toegewezen',
            'paused'    => 'Abonnement gepauzeerd ⏸️',
            'resumed'   => 'Abonnement hervat ▶️',
            default     => 'Abonnement gewijzigd',
        };

        $body = match ($action) {
            'assigned'  => "Je bent ingeschreven voor het {$planName} abonnement.",
            'paused'    => 'Je abonnement is tijdelijk gepauzeerd.',
            'resumed'   => 'Je abonnement is weer actief!',
            default     => 'Er is een wijziging in je abonnement.',
        };

        FcmPushHelper::sendToUser(
            $trainerUserId,
            $title,
            $body,
            [
                'type'   => 'subscription_changed',
                'action' => $action,
                'screen' => 'subscription',
            ]
        );

        Log::info('[Notification] Subscription change push sent', [
            'user_id' => $trainerUserId,
            'action'  => $action,
        ]);
    }

    // ──────────────────────────────────────────────
    //  E-MAIL SEQUENCE (3 mails eerste week)
    // ──────────────────────────────────────────────

    /**
     * 1. Welkom mail — direct na registratie.
     */
    public function sendWelcomeEmail(int $trainerUserId, string $trainerName): void
    {
        SendGymiesNotificationEmail::sendOrQueue($trainerUserId, 'welcome_onboarding', [
            'trainer_name' => $trainerName,
        ]);

        Log::info('[OnboardingNotification] Welcome email queued', ['user_id' => $trainerUserId]);
    }

    /**
     * 2. Herinnering na 24u — onboarding niet afgemaakt.
     */
    public function sendOnboardingReminder24h(int $trainerUserId, string $trainerName): void
    {
        SendGymiesNotificationEmail::sendOrQueue($trainerUserId, 'onboarding_reminder_24h', [
            'trainer_name' => $trainerName,
        ]);

        Log::info('[OnboardingNotification] 24h reminder email queued', ['user_id' => $trainerUserId]);
    }

    /**
     * 3. Nudge na 72u — nog steeds incompleet.
     */
    public function sendOnboardingNudge72h(int $trainerUserId, string $trainerName): void
    {
        SendGymiesNotificationEmail::sendOrQueue($trainerUserId, 'onboarding_nudge_72h', [
            'trainer_name' => $trainerName,
        ]);

        Log::info('[OnboardingNotification] 72h nudge email queued', ['user_id' => $trainerUserId]);
    }

    // ──────────────────────────────────────────────
    //  HELPERS
    // ──────────────────────────────────────────────

    /**
     * Haal alle staff/admin/medewerker user IDs op (voor staff push notificaties).
     *
     * @return int[]
     */
    /**
     * Haal alleen admin user IDs op (voor escalaties).
     *
     * @return int[]
     */
    private function getAdminUserIds(): array
    {
        if (!Schema::hasTable('gymies_users')) {
            return [];
        }

        return DB::table('gymies_users')
            ->where('role', 'admin')
            ->where('is_active', true)
            ->pluck('id')
            ->toArray();
    }

    private function getStaffUserIds(): array
    {
        if (!Schema::hasTable('gymies_users')) {
            return [];
        }

        // Direct role check op gymies_users
        $directRoles = DB::table('gymies_users')
            ->whereIn('role', ['admin', 'staff', 'medewerker'])
            ->where('is_active', true)
            ->pluck('id')
            ->toArray();

        // Fallback: check via gymies_user_roles pivot tabel (als die bestaat)
        $pivotRoles = [];
        if (Schema::hasTable('gymies_user_roles') && Schema::hasTable('gymies_roles')) {
            $pivotRoles = DB::table('gymies_user_roles')
                ->join('gymies_roles', 'gymies_user_roles.role_id', '=', 'gymies_roles.id')
                ->whereIn('gymies_roles.name', ['admin', 'staff', 'medewerker'])
                ->pluck('gymies_user_roles.user_id')
                ->toArray();
        }

        return array_values(array_unique(array_merge($directRoles, $pivotRoles)));
    }

    // ──────────────────────────────────────────────
    //  FIX 73 & 80: Additional Notification Methods
    // ──────────────────────────────────────────────

    /**
     * Fix 73: Notify trainer of new review.
     * Sends push: "Nieuwe review van {clientName}: {rating} sterren"
     */
    public function notifyTrainerNewReview(int $trainerUserId, string $clientName, int $rating, int $bookingId): void
    {
        FcmPushHelper::sendToUser(
            $trainerUserId,
            "Nieuwe review van {$clientName}: {$rating} sterren",
            "{$clientName} heeft je een {$rating}-sterren review gegeven. Lees de volledige review in je dashboard.",
            [
                'type'        => 'new_review',
                'action'      => 'review_received',
                'screen'      => 'trainer_dashboard',
                'booking_id'  => (string) $bookingId,
                'client_name' => $clientName,
                'rating'      => (string) $rating,
            ]
        );

        Log::info('[OnboardingNotification] New review push sent to trainer', [
            'trainer_user_id' => $trainerUserId,
            'booking_id'      => $bookingId,
            'rating'          => $rating,
        ]);
    }

    /**
     * Fix 80: Notify user of available waitlist spot.
     * Sends push: "Er is een plek vrijgekomen bij {sessionTitle} op {date}!"
     */
    public function notifyWaitlistSpotAvailable(int $userId, string $sessionTitle, string $scheduledAt, int $groupSessionId): void
    {
        $date = date('j F H:i', strtotime($scheduledAt));

        FcmPushHelper::sendToUser(
            $userId,
            "Er is een plek vrijgekomen bij {$sessionTitle} op {$date}!",
            "Een plek is beschikbaar geworden bij {$sessionTitle}. Accepteer je plek voordat deze weg is!",
            [
                'type'              => 'waitlist_available',
                'action'            => 'spot_available',
                'screen'            => 'group_sessions',
                'group_session_id'  => (string) $groupSessionId,
                'session_title'     => $sessionTitle,
                'scheduled_at'      => $scheduledAt,
            ]
        );

        Log::info('[OnboardingNotification] Waitlist spot available push sent', [
            'user_id'          => $userId,
            'group_session_id' => $groupSessionId,
        ]);
    }

    // ──────────────────────────────────────────────
    //  GYM NOTIFICATION METHODS
    // ──────────────────────────────────────────────

    /**
     * Notify all gym owners when a settlement has been created.
     *
     * @param int $organisationId
     * @param array $settlementData ['period', 'net_amount', 'settlement_id']
     */
    public function notifyGymSettlementCreated(int $organisationId, array $settlementData): void
    {
        $period = $settlementData['period'] ?? 'onbekend';
        $netAmount = $settlementData['net_amount'] ?? 0;
        $settlementId = $settlementData['settlement_id'] ?? null;
        $formattedAmount = number_format($netAmount / 100, 2, ',', '.');

        // Get all active org owners
        $ownerEmails = $this->getOrgOwnerEmails($organisationId);

        foreach ($ownerEmails as $email) {
            SendGymiesNotificationEmail::sendOrQueue(
                $email,
                'gym_settlement_created',
                [
                    'period'      => $period,
                    'net_amount'  => "€{$formattedAmount}",
                    'app_url'     => config('app.url'),
                ]
            );
        }

        Log::info('[GymNotification] Settlement created notifications sent', [
            'organisation_id' => $organisationId,
            'settlement_id'   => $settlementId,
            'owner_count'     => count($ownerEmails),
        ]);
    }

    /**
     * Notify all gym owners when a settlement has been paid out.
     *
     * @param int $organisationId
     * @param array $settlementData ['amount', 'iban_last4', 'expected_arrival']
     */
    public function notifyGymSettlementPaid(int $organisationId, array $settlementData): void
    {
        $amount = $settlementData['amount'] ?? 0;
        $ibanLast4 = $settlementData['iban_last4'] ?? 'XXXX';
        $expectedArrival = $settlementData['expected_arrival'] ?? 'onbekend';
        $formattedAmount = number_format($amount / 100, 2, ',', '.');

        // Get all active org owners
        $ownerEmails = $this->getOrgOwnerEmails($organisationId);

        foreach ($ownerEmails as $email) {
            SendGymiesNotificationEmail::sendOrQueue(
                $email,
                'gym_settlement_paid',
                [
                    'amount'           => "€{$formattedAmount}",
                    'iban_last4'       => $ibanLast4,
                    'expected_arrival' => $expectedArrival,
                    'app_url'          => config('app.url'),
                ]
            );
        }

        Log::info('[GymNotification] Settlement paid notifications sent', [
            'organisation_id' => $organisationId,
            'owner_count'     => count($ownerEmails),
        ]);
    }

    /**
     * Notify all gym owners when a new trainer has joined the gym.
     *
     * @param int $organisationId
     * @param int $trainerUserId
     */
    public function notifyGymTrainerJoined(int $organisationId, int $trainerUserId): void
    {
        // Get trainer details
        $trainer = DB::table('users')
            ->where('id', $trainerUserId)
            ->first();

        if (!$trainer) {
            Log::warning('[GymNotification] Trainer not found', ['trainer_user_id' => $trainerUserId]);
            return;
        }

        $trainerName = $trainer->name ?? 'Onbekende trainer';
        $joinedDate = now()->format('d-m-Y');

        // Get all active org owners
        $ownerEmails = $this->getOrgOwnerEmails($organisationId);

        foreach ($ownerEmails as $email) {
            SendGymiesNotificationEmail::sendOrQueue(
                $email,
                'gym_trainer_joined',
                [
                    'trainer_name' => $trainerName,
                    'joined_date'  => $joinedDate,
                    'app_url'      => config('app.url'),
                ]
            );
        }

        Log::info('[GymNotification] Trainer joined notifications sent', [
            'organisation_id' => $organisationId,
            'trainer_user_id' => $trainerUserId,
            'owner_count'     => count($ownerEmails),
        ]);
    }

    /**
     * Helper: Get all active owner emails for an organisation.
     *
     * @param int $organisationId
     * @return array Email addresses
     */
    private function getOrgOwnerEmails(int $organisationId): array
    {
        if (!Schema::hasTable('gymies_organisation_members') || !Schema::hasTable('users')) {
            return [];
        }

        return DB::table('gymies_organisation_members')
            ->join('users', 'gymies_organisation_members.user_id', '=', 'users.id')
            ->where('gymies_organisation_members.organisation_id', $organisationId)
            ->where('gymies_organisation_members.role', 'owner')
            ->where('gymies_organisation_members.status', 'active')
            ->where('users.is_active', true)
            ->pluck('users.email')
            ->toArray();
    }

}
