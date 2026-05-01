# Gymies API – volledige endpoint-map

Overzicht van alle endpoints onder base URL `https://www.gymies.nl/api/gymies`. Zie [API_BASE_AND_AUTH.md](API_BASE_AND_AUTH.md) voor auth, rate limits en overige details.

**Bron:** `backend/routes_gymies_full.php`

---

## Legenda

| Symbool | Betekenis |
|---------|-----------|
| 🔓 | Publiek (geen token) |
| 🔒 | Beveiligd (Bearer token) |
| 🛡️ | Admin (vault-console prefix + admin-capabilities) |

---

## 1. Auth – publiek

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| POST | `login` | Inloggen (rate limit: login) |
| POST | `register` | Registreren (rate limit: register) |
| POST | `auth/forgot-password` | Wachtwoord vergeten |
| POST | `auth/reset-password` | Wachtwoord resetten |
| POST | `auth/resend-verification-code` | Verificatiecode opnieuw versturen |
| POST | `auth/resend-mail` | Alias voor resend-verification-code |
| POST | `auth/verify-email` | E-mail verifiëren met code |
| POST | `auth/verify-email-link` | E-mail verifiëren via link-token |

---

## 2. Trainers – publiek

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| POST | `search-log` | Zoekopdracht loggen |
| GET | `trainers` | Trainers index (zoek/filter) |
| GET | `trainers/{id}` | Trainer profiel |
| GET | `trainers/{id}/availability` | Publieke beschikbaarheid |
| GET | `trainers/{id}/blocked-slots` | Geblokkeerde slots |
| GET | `trainers/{id}/packages` | Pakketten |
| GET | `trainers/{id}/media` | Media/foto's |

**Trainer-object** moet `boosted_until` bevatten (ISO datetime) voor stad-eerst sorteerlogica. Zie [TRAINER_STAD_AFSTAND_BOOST_SPEC.md](TRAINER_STAD_AFSTAND_BOOST_SPEC.md).

---

## 3. Site & Referral – publiek

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `site-media` | Landingspagina hero/sectie-media (Control Tower) |
| GET | `referral/validate` | Referralcode valideren vóór registratie |

---

## 4. Groepslessen – publiek

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `group-sessions` | Groepslessen index |
| GET | `group-sessions/{id}` | Groepsles detail |

---

## 5. Webhooks & Cron – server-side

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET/POST | `webhooks/mollie` | Mollie betaling webhook |
| GET/POST | `webhooks/mollie-subscription` | Mollie abonnement webhook |
| GET | `onboarding/mollie-connect/callback` | Mollie Connect OAuth callback |
| POST | `cron/expire-pending-bookings` | Verlopen pending boekingen |
| POST | `cron/expire-reserved-bookings` | Verlopen reserved boekingen |
| POST | `cron/expire-group-sessions-min-not-reached` | Groepslessen afbreken (min niet gehaald) |
| POST | `cron/expire-group-session-claim-pending` | Claim-pending groepslessen |
| GET/POST | `cron/auto-complete-sessions` | Sessies automatisch afronden |
| GET/POST | `cron/availability-check` | Beschikbaarheidscheck |
| GET/POST | `cron/auto-pilot-retention` | Retention auto-pilot |
| GET/POST | `cron/auto-pilot-low-credit` | Low-credit auto-pilot |
| GET/POST | `cron/subscription-reminders` | Abonnement herinneringen |
| GET/POST | `cron/generate-session-invoices` | Sessie-facturen genereren |
| GET/POST | `cron/expire-group-session-payment-deadline` | Betalingsdeadline groepslessen |
| GET/POST | `cron/safe-session-overdue` | Safe-session te lang open |
| GET/POST | `cron/expire-substitute-requests` | Vervangingsverzoeken verlopen |
| GET/POST | `cron/trigger-ghost-ratings` | Ghost ratings triggeren |
| GET/POST | `cron/ghost-rating-alerts` | Ghost rating alerting |

---

## 6. Profiel & Auth – beveiligd

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `me` | Huidige gebruiker |
| PUT/POST | `me` | Profiel bijwerken |
| POST | `auth/change-password` | Wachtwoord wijzigen |
| GET | `auth/sessions` | Actieve sessies |
| POST | `auth/logout-device` | Uitloggen op dit apparaat |
| POST | `auth/logout-all-devices` | Uitloggen op alle apparaten |

---

## 7. Ops & Compliance – beveiligd

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `ops/health` | Health check |
| GET | `ops/metrics` | Metrieken |
| POST | `ops/run-backup` | Backup draaien |
| POST | `ops/run-web-sync` | Web sync draaien |
| GET | `feature-flags` | Feature flags |
| GET | `broadcasts/active` | Actieve broadcasts |
| GET | `gdpr/export` | GDPR data-export |
| GET | `gdpr/export/pdf` | GDPR export als PDF |
| POST | `gdpr/delete-request` | Verwijderverzoek indienen |
| POST | `gdpr/delete-account` | Account verwijderen |
| GET | `consent` | Toestemming ophalen |
| PUT/POST | `consent` | Toestemming bijwerken |

---

## 8. Boekingen – beveiligd

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `bookings` | Mijn boekingen (klant) |
| GET | `trainer/summary` | Boekingen-samenvatting trainer |
| POST | `bookings` | Boeking aanmaken |
| POST | `bookings/direct-book` | Direct boeken (trainer → klant) |
| POST | `bookings/{id}/confirm` | Boeking bevestigen |
| POST | `bookings/{id}/reschedule` | Verzetten |
| POST | `bookings/{id}/reschedule-request` | Verzetverzoek indienen |
| POST | `bookings/{id}/reschedule-respond` | Verzetverzoek beantwoorden |
| GET | `bookings/{id}/cancellation-preview` | Annuleringspreview |
| POST | `bookings/{id}/cancel` | Annuleren |
| GET | `bookings/{id}/review-status` | Review-status |
| POST | `bookings/{id}/session-status` | Sessiestatus bijwerken |
| POST | `bookings/{id}/report-trainer-no-show` | No-show melden |
| POST | `bookings/{id}/confirm-cash` | Contant betalen bevestigen |
| POST | `bookings/{id}/ghost-rating` | Ghost rating indienen |
| POST | `bookings/{id}/review` | Review plaatsen |
| GET | `bookings/{id}/review` | Review ophalen |
| POST | `bookings/{id}/review-response` | Trainer antwoord op review |
| POST | `bookings/{id}/payments/validate-promo` | Promo valideren |
| POST | `bookings/{id}/payments/start` | Betaling starten |
| GET | `bookings/{id}/payment-status` | Betalingsstatus |

---

## 9. Check-in & Safety – beveiligd

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `bookings/{id}/checkin-qr` | QR-code voor check-in |
| POST | `checkin/scan` | QR scannen (check-in) |
| POST | `checkin/manual` | Handmatige check-in (reservecode) |
| POST | `checkin/report-fraud` | Identiteitsfraude melden |
| POST | `sos/alert` | SOS-alert |
| POST | `bookings/{id}/safe-session/start` | Safe-session starten |
| POST | `bookings/{id}/checkout` | Checkout |

---

## 10. Trainer – profiel & beschikbaarheid

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `trainer/me` | Trainer-profiel |
| PUT/POST | `trainer/me` | Trainer-profiel bijwerken (incl. `visible_badges`) |

**Badge-voorkeuren:** Zie [BACKEND_BADGES_SPEC.md](BACKEND_BADGES_SPEC.md) – GET/PUT `trainer/me` en GET `trainers`/`trainers/{id}` moeten `visible_badges` ondersteunen.

| GET | `trainer/availability` | Beschikbaarheid |
| POST | `trainer/availability/slots` | Slot toevoegen |
| PUT | `trainer/availability/slots/{id}` | Slot bijwerken |
| DELETE | `trainer/availability/slots/{id}` | Slot verwijderen |
| POST | `trainer/availability/exceptions` | Uitzondering toevoegen |
| PUT | `trainer/availability/exceptions/{id}` | Uitzondering bijwerken |
| DELETE | `trainer/availability/exceptions/{id}` | Uitzondering verwijderen |

---

## 11. Trainer – pakketten, promo, media

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `trainer/packages` | Pakketten |
| POST | `trainer/packages` | Pakket aanmaken |
| PUT | `trainer/packages/{id}` | Pakket bijwerken |
| DELETE | `trainer/packages/{id}` | Pakket verwijderen |
| GET | `trainer/promo-codes` | Promocodes |
| POST | `trainer/promo-codes` | Promocode aanmaken |
| PUT | `trainer/promo-codes/{id}` | Promocode bijwerken |
| DELETE | `trainer/promo-codes/{id}` | Promocode verwijderen |
| GET | `trainer/media` | Media |
| POST | `trainer/media` | Media uploaden |
| PUT | `trainer/media/{id}` | Media bijwerken |
| DELETE | `trainer/media/{id}` | Media verwijderen |

---

## 12. Trainer – inkomsten & uitbetalingen

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `trainer/revenue` | Omzet |
| PATCH | `trainer/fee-preference` | Fee-voorkeur (eigen baas) |
| GET | `trainer/payout-settings` | Uitbetalingsinstellingen |
| PUT/POST | `trainer/payout-settings` | Uitbetalingsinstellingen bijwerken |
| GET | `trainer/payout-preview` | Uitbetalingspreview |
| GET | `trainer/payout-calendar` | Uitbetalingskalender |
| GET | `trainer/payouts` | Uitbetalingsgeschiedenis |
| POST | `trainer/payouts/request-now` | Nu uitbetalen aanvragen |
| GET | `trainer/revenue/export` | Omzet exporteren |
| GET | `trainer/revenue-forecast` | Omzetprognose |

---

## 13. Trainer – CRM & progressie

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `trainer/retention/sleeping-clients` | Sleeping clients |
| GET | `trainer/clients/{clientUserId}/progress` | Klant progressie (Transformation Log) |
| POST | `trainer/clients/{clientUserId}/progress` | Progressie toevoegen |
| GET | `trainer/clients/{clientUserId}/dossier` | Klant dossier |
| PUT | `trainer/clients/{clientUserId}/dossier` | Dossier bijwerken |
| GET | `trainer/clients/{clientUserId}/session-notes` | Sessienotities |
| POST | `trainer/clients/bulk-message` | Bulk-bericht naar klanten |
| PUT | `trainer/bookings/{bookingId}/session-note` | Sessienotitie bij boeking |
| GET | `trainer/storefront-cms` | Etalage CMS |
| PUT/POST | `trainer/storefront-cms` | Etalage CMS bijwerken |
| GET | `trainer/studio/performance-summary` | Studio-performance |
| GET | `trainer/studio/safety-log` | Safety log |
| GET | `trainer/live-counters` | Live counters |
| POST | `trainer/report-issue` | Issue melden |

---

## 14. Trainer – conversaties

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `trainer/conversations` | Conversaties |
| POST | `trainer/conversations/ensure` | Conversatie aanmaken/ophalen |
| GET | `trainer/conversations/{id}/messages` | Berichten |
| POST | `trainer/conversations/{id}/messages` | Bericht versturen |
| POST | `trainer/conversations/{id}/mark-read` | Als gelezen markeren |
| GET | `trainer/conversations/{id}/context` | Context (reschedule-card etc.) |

---

## 15. Gym (Studio) – beveiligd

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `gym/dashboard` | Dashboard |
| GET | `gym/dashboard-stats` | Dashboard-statistieken |
| GET | `gym/membership` | Membership |
| GET | `gym/trainers` | Trainers |
| POST | `gym/trainers` | Trainer toevoegen |
| POST | `gym/trainers/{trainerUserId}/status` | Trainerstatus bijwerken |
| GET | `gym/trainers/{trainerUserId}/stats` | Trainerstatistieken |
| GET | `gym/bookings` | Boekingen |
| GET | `gym/bookings/stats` | Boekingsstatistieken |
| GET | `gym/bookings/export` | Boekingen CSV export |
| GET | `gym/bookings/{id}` | Boekingdetail |
| POST | `gym/bookings/{id}/send-reminder` | Herinnering versturen |
| GET | `gym/settlements` | Settlements |
| GET | `gym/settlements/{id}` | Settlementdetail |
| POST | `gym/settlements/draft` | Draft settlement |
| POST | `gym/settlements/{id}/adjustments` | Adjustments |
| POST | `gym/settlements/{id}/transition` | Statuswijziging |
| GET | `gym/revenue/export` | Omzet export |
| GET | `gym/trainers/export` | Trainers export |
| GET | `gym/clients` | Klanten |
| POST | `gym/clients/{clientUserId}/reengagement` | Reengagement mail |
| POST | `gym/alerts/{alertKey}/complete` | Dashboard-alert voltooien |
| GET | `gym/settings` | Instellingen |
| PUT/POST | `gym/settings` | Instellingen bijwerken (incl. `locations`: array van `{name, address, city, postal_code}`) |
| POST | `gym/members/invite` | Lid uitnodigen |
| POST | `gym/members/{userId}/role` | Rol bijwerken |
| POST | `gym/members/{userId}/status` | Status bijwerken |
| POST | `gym/cache-invalidation-event` | Cache-invalidatie loggen |

---

## 16. Groepslessen – klant & trainer

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `my-group-registrations` | Mijn inschrijvingen |
| POST | `group-sessions/{id}/register` | Inschrijven |
| POST | `group-sessions/{id}/cancel-registration` | Inschrijving annuleren |
| POST | `group-session-participants/{participantId}/validate-promo` | Promo valideren |
| POST | `group-session-participants/{participantId}/payments/start` | Betaling starten |
| GET | `group-session-participants/{participantId}/payment-status` | Betalingsstatus |
| GET | `trainer/group-sessions` | Trainer groepslessen |
| POST | `trainer/group-sessions` | Groepsles aanmaken |
| POST | `trainer/group-sessions/recurring` | Terugkerende groepsles |
| PUT | `trainer/group-sessions/{id}` | Groepsles bijwerken |
| POST | `trainer/group-sessions/{id}/publish` | Publiceren |
| POST | `trainer/group-sessions/{id}/confirm` | Bevestigen |
| POST | `trainer/group-sessions/{id}/cancel` | Annuleren |
| POST | `trainer/group-sessions/{id}/request-substitute` | Vervanger aanvragen |
| POST | `substitute-requests/{requestId}/accept` | Vervangingsverzoek accepteren |
| GET | `trainer/group-sessions/{id}/participants` | Deelnemers |
| POST | `trainer/group-sessions/{id}/participants/{participantId}/attended` | Deelnemer aanwezig |

---

## 17. Conversaties (klant)

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `conversations` | Mijn conversaties |
| POST | `conversations/ensure` | Conversatie aanmaken/ophalen |
| GET | `conversations/{id}/messages` | Berichten |
| POST | `conversations/{id}/messages` | Bericht versturen |
| POST | `conversations/{id}/mark-read` | Als gelezen markeren |
| GET | `conversations/{id}/context` | Context |
| GET | `me/progress` | Mijn progressie (voor trainer) |
| GET | `me/shared-dossier` | Gedeeld dossier van trainer |
| GET | `me/buddy-stats` | Buddy-statistieken |

---

## 18. Referral, Onboarding & Subscription

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `referral/my-code` | Mijn referralcode |
| GET | `onboarding/status` | Onboardingstatus |
| POST | `onboarding/upload-document` | Document uploaden |
| POST | `onboarding/mollie-connect/start` | Mollie Connect starten |
| POST | `onboarding/select-plan` | Plan kiezen |
| GET | `subscription/my` | Mijn abonnement |
| POST | `subscription/cancel` | Abonnement opzeggen |
| GET | `plans` | Beschikbare plannen |

---

## 19. Facturen & Support

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `invoices/trainer` | Trainerfacturen |
| GET | `invoices/trainer/quarter-zip` | Kwartaal ZIP |
| GET | `invoices/client` | Klantfacturen |
| GET | `support/tickets` | Tickets |
| POST | `support/tickets` | Ticket aanmaken |
| GET | `support/tickets/{id}` | Ticketdetail |
| POST | `support/tickets/{id}/messages` | Bericht toevoegen |
| POST | `support/tickets/{id}/mark-helped` | Als geholpen markeren |

---

## 20. Notificaties

| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `notifications` | Notificaties |
| GET | `notifications/unread-count` | Ongelezen teller |
| POST | `notifications/mark-read` | Als gelezen markeren |
| GET | `notifications/preferences` | Voorkeuren |
| PUT/POST | `notifications/preferences` | Voorkeuren bijwerken |

---

## 21. Admin (vault-console)

Base: `vault-console` (of `GYMIES_ADMIN_PREFIX`). Vereist `admin.access` + IP-allowlist.

### Inbox & Overview
| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `vault-console/inbox` | Inbox |
| GET | `vault-console/overview` | Overzicht |
| GET | `vault-console/search` | Zoeken |
| GET | `vault-console/note-templates` | Notitietemplates |
| GET | `vault-console/saved-views` | Opgeslagen weergaven |
| POST | `vault-console/saved-views` | View opslaan |
| DELETE | `vault-console/saved-views/{id}` | View verwijderen |

### Users & Moderation
| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| POST | `vault-console/bulk/users/status` | Bulk userstatus |
| GET | `vault-console/users` | Gebruikers |
| GET | `vault-console/users/export` | Users export |
| GET | `vault-console/users/{userId}` | Userdetail |
| GET | `vault-console/users/{userId}/notes` | Usernotities |
| POST | `vault-console/users/{userId}/notes` | Notitie toevoegen |
| POST | `vault-console/users/{userId}/status` | Status bijwerken |
| POST | `vault-console/users/{userId}/force-logout-all` | Force logout |
| POST | `vault-console/users/{userId}/impersonate` | Impersoneren |
| POST | `vault-console/users/{userId}/assign-subscription` | Abonnement toewijzen |
| GET | `vault-console/moderation/profiles` | Profielen moderatie |
| POST | `vault-console/moderation/profiles/{userId}/approve` | Goedkeuren |
| POST | `vault-console/moderation/profiles/{userId}/reject` | Afwijzen |
| POST | `vault-console/moderation/profiles/{userId}/quality-score` | Kwaliteitsscore |

### Payments, Payouts, Tickets
| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| POST | `vault-console/bulk/tickets` | Bulk tickets |
| POST | `vault-console/bulk/payouts/status` | Bulk payoutstatus |
| GET | `vault-console/payments` | Betalingen |
| GET | `vault-console/promo-codes` | Promocodes |
| POST | `vault-console/promo-codes` | Promocode aanmaken |
| GET | `vault-console/payouts` | Uitbetalingen |
| POST | `vault-console/payouts/{payoutId}/status` | Payoutstatus bijwerken |
| GET | `vault-console/tickets` | Tickets |
| POST | `vault-console/tickets/duplicate` | Ticket dupliceren |
| POST | `vault-console/tickets/{ticketId}` | Ticket bijwerken |
| GET | `vault-console/tickets/{ticketId}/messages` | Ticketberichten |
| POST | `vault-console/tickets/{ticketId}/messages` | Bericht toevoegen |

### Bookings & Disputes
| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `vault-console/bookings-monitor` | Boekingenmonitor |
| GET | `vault-console/bookings/{bookingId}` | Boekingdetail |
| POST | `vault-console/bookings/{bookingId}/cancel` | Annuleren |
| POST | `vault-console/bookings/{bookingId}/waive-trainer-penalty` | Boete kwijtschelden |
| POST | `vault-console/bookings/{bookingId}/refund-or-credit` | Terugbetaling/krediet |
| POST | `vault-console/bookings/{bookingId}/reschedule` | Verzetten |
| POST | `vault-console/bookings/{bookingId}/incident` | Incident toevoegen |
| GET | `vault-console/bookings/{bookingId}/incidents` | Incidents |
| POST | `vault-console/incidents/{incidentId}/resolve` | Incident oplossen |
| GET | `vault-console/disputes` | Disputes |
| GET | `vault-console/disputes/{disputeId}` | Disputedetail |
| POST | `vault-console/disputes/{disputeId}/resolve` | Dispute oplossen |

### Subscriptions, Plans, Availability
| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `vault-console/subscriptions` | Abonnementen |
| GET | `vault-console/subscriptions/revenue` | Abonnementsomzet |
| GET | `vault-console/plans` | Plannen |
| POST | `vault-console/plans/{planId}` | Plan bijwerken |
| POST | `vault-console/availability-override` | Beschikbaarheid override |
| POST | `vault-console/packages/{packageId}/admin` | Pakket admin-update |
| POST | `vault-console/bulk/assign-tickets-yesterday` | Tickets gisteren toewijzen |
| GET | `vault-console/trainers-pending-payout` | Trainers met pending payout |

### Security & Broadcasts
| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `vault-console/security/events` | Security events |
| GET | `vault-console/security/ip-allowlist` | IP-allowlist |
| POST | `vault-console/security/ip-allowlist` | IP toevoegen |
| POST | `vault-console/security/ip-allowlist/{id}/remove` | IP verwijderen |
| GET | `vault-console/broadcasts` | Broadcasts |
| POST | `vault-console/broadcasts` | Broadcast aanmaken |
| DELETE | `vault-console/broadcasts/{id}` | Broadcast verwijderen |

### Audit, Profitability, Site media
| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `vault-console/audit` | Auditlog |
| POST | `vault-console/audit/{auditId}/revert` | Revert |
| GET | `vault-console/audit/export` | Audit export |
| GET | `vault-console/profitability/overview` | Winstoverzicht |
| GET | `vault-console/profitability/settings` | Winstinstellingen |
| POST | `vault-console/profitability/settings` | Winstinstellingen bijwerken |
| GET | `vault-console/site-media` | Site media (Control Tower) |
| PUT/POST | `vault-console/site-media` | Site media bijwerken |

### Retention, Leakage, Campaigns
| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `vault-console/retention/sleeping-wallets` | Sleeping wallets |
| GET | `vault-console/retention/trainer-dropoff` | Trainer dropoff |
| POST | `vault-console/nudge` | Nudge versturen |
| GET | `vault-console/leakage/flags` | Chat leakage flags |
| POST | `vault-console/leakage/scan` | Keywords scannen |
| POST | `vault-console/leakage/flags/{flagId}/review` | Flag beoordelen |
| GET | `vault-console/trainers/tiers` | Trainer tiers |
| POST | `vault-console/trainers/{trainerUserId}/boost` | Trainer boosten (top 5 in stad) |
| GET | `vault-console/trainers/{trainerUserId}/boost` | Boost-status ophalen |
| DELETE | `vault-console/trainers/{trainerUserId}/boost` | Boost verwijderen |
| POST | `vault-console/users/{userId}/tier` | Tier bijwerken |
| GET | `vault-console/onboarding/pipeline` | Onboarding pipeline |
| GET | `vault-console/campaigns` | Campagnes |
| POST | `vault-console/campaigns` | Campagne aanmaken |
| POST | `vault-console/campaigns/{campaignId}/send` | Campagne versturen |
| GET | `vault-console/heatmap` | Heatmap |
| GET | `vault-console/heatmap/demand-supply` | Vraag/aanbod heatmap |
| GET | `vault-console/ghost-ratings` | Ghost ratings dashboard |

### Organisations
| Methode | Endpoint | Beschrijving |
|---------|----------|--------------|
| GET | `vault-console/organisations` | Organisaties |
| POST | `vault-console/organisations/{orgId}` | Organisatie bijwerken |
| GET | `vault-console/organisations/{orgId}/members` | Leden |
| POST | `vault-console/organisations/{orgId}/members/{userId}` | Lid bijwerken |
| GET | `vault-console/organisations/{orgId}/settlement-overview` | Settlement overzicht |
| GET | `vault-console/organisations/{orgId}/settlement-report` | Settlement rapport |

---

## Externe APIs (Mollie, Brevo, etc.)

De backend praat met:

- **Mollie API** – betalingen, abonnementen, Connect OAuth
- **Brevo (Sendinblue)** – transactionele e-mail
- **Mollie Connect** – OAuth voor trainers (eigen baas)

Configuratie: zie `.env` en `deploy/env_mollie_connect.example`.
