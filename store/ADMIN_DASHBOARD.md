# Admin Dashboard – specificatie

> Dashboard voor Gymies-medewerkers. Inloggen, overzicht, support afhandelen en meer.

De backend (vault-console) heeft al admin-endpoints. Dit document beschrijft wat het **admin dashboard in de app** moet doen en hoe het aansluit op de bestaande API.

Zie [API_MAP.md](API_MAP.md) sectie 21 voor de volledige endpoint-lijst.

---

## Doel

- Medewerker kan inloggen (met admin-rechten).
- Dagelijks overzicht zien (boekingen, nieuwe tickets, etc.).
- Support-berichten afhandelen (tickets lezen, beantwoorden, status bijwerken).
- Extra taken uitvoeren (gebruikers, betalingen, boekingen, enz.).

---

## Toegang & auth

- **Wie:** Medewerkers met `admin.access` (en eventueel IP-allowlist op backend).
- **Hoe inloggen:** Zelfde login-flow als trainer/klant; backend controleert roles/capabilities.
- **Aparte app of in bestaande app:** Nog te bepalen.
  - Optie A: In dezelfde app, na login wordt op basis van rol admin-dashboard getoond.
  - Optie B: Aparte “Gymies Staff” app met alleen admin-functionaliteit.

---

## Hoofdschermen (voorgesteld)

### 1. Dashboard / Overzicht

| Element | Beschrijving | API |
|---------|--------------|-----|
| Inbox | Actiepunten, prioriteiten | `vault-console/inbox` |
| Overview | KPI’s, statistieken | `vault-console/overview` |
| Open tickets | Open support-tickets (snel overzicht) | `vault-console/tickets` |
| Recente boekingen | Boekingenmonitor-samenvatting | `vault-console/bookings-monitor` |
| Nieuwe gebruikers / moderation | Profielen ter goedkeuring | `vault-console/moderation/profiles` |

*“Gebruikelijke” info die medewerker dagelijks nodig heeft.*

### 2. Support / Tickets

| Actie | Beschrijving | API |
|-------|--------------|-----|
| Tickets lijst | Filter op status, auteur, datum | `vault-console/tickets` |
| Ticket detail | Gesprek + context (klant, boeking, trainer) | `vault-console/tickets/{id}`, `tickets/{id}/messages` |
| Bericht toevoegen | Antwoord sturen naar klant/trainer | `vault-console/tickets/{id}/messages` |
| Status bijwerken | Open → In behandeling → Gesloten | `vault-console/tickets/{id}` (POST) |
| Dupliceren | Ticket dupliceren indien nodig | `vault-console/tickets/duplicate` |
| Bulk acties | Meerdere tickets tegelijk verwerken | `vault-console/bulk/tickets` |

### 3. Gebruikers

| Actie | Beschrijving | API |
|-------|--------------|-----|
| Zoeken | Gebruiker opzoeken | `vault-console/search`, `vault-console/users` |
| User detail | Profiel, notities, status | `vault-console/users/{id}` |
| Notities | Interne notities toevoegen | `vault-console/users/{id}/notes` |
| Status wijzigen | Actief, gedeactiveerd, etc. | `vault-console/users/{id}/status` |
| Impersoneren | Als gebruiker inloggen (debug/support) | `vault-console/users/{id}/impersonate` |
| Abonnement toewijzen | Tier wijzigen (Starter/Pro/Elite) – **zonder betaling**; admin kan handmatig Pro/Elite toekennen | `vault-console/users/{id}/assign-subscription` |
| Force logout | Alle sessies beëindigen | `vault-console/users/{id}/force-logout-all` |
| Moderation | Profielen goedkeuren/afwijzen | `vault-console/moderation/profiles` |

### 4. Boekingen

| Actie | Beschrijving | API |
|-------|--------------|-----|
| Monitor | Overzicht boekingen (filter, status) | `vault-console/bookings-monitor` |
| Boeking detail | Afspraak, betaling, incidenten | `vault-console/bookings/{id}` |
| Annuleren | Boeking annuleren | `vault-console/bookings/{id}/cancel` |
| Refund / krediet | Terugbetaling of krediet geven | `vault-console/bookings/{id}/refund-or-credit` |
| Verzetten | Nieuwe datum/tijd | `vault-console/bookings/{id}/reschedule` |
| Boete kwijtschelden | Trainer-penalty weghalen | `vault-console/bookings/{id}/waive-trainer-penalty` |
| Incident toevoegen | Incident registreren | `vault-console/bookings/{id}/incident` |

### 5. Betalingen & uitbetalingen

| Actie | Beschrijving | API |
|-------|--------------|-----|
| Betalingen | Overzicht transacties | `vault-console/payments` |
| Uitbetalingen | Payouts naar trainers | `vault-console/payouts`, `payouts/{id}/status` |
| Promocodes | Aanmaken, beheren | `vault-console/promo-codes` |
| Bulk payout status | Meerdere payouts verwerken | `vault-console/bulk/payouts/status` |

### 6. Abonnementen & plannen

| Actie | Beschrijving | API |
|-------|--------------|-----|
| Abonnementen | Lijst actieve abonnementen | `vault-console/subscriptions` |
| Revenue | Abonnementsomzet | `vault-console/subscriptions/revenue` |
| Plannen | Plannen beheren | `vault-console/plans` |

### 7. Security & audit

| Actie | Beschrijving | API |
|-------|--------------|-----|
| Security events | Inlogpogingen, wijzigingen | `vault-console/security/events` |
| IP-allowlist | Toegestane IP’s voor admin | `vault-console/security/ip-allowlist` |
| Auditlog | Actie-historie | `vault-console/audit` |
| Broadcasts | App-brede berichten | `vault-console/broadcasts` |

### 8. Disputes & incidenten

| Actie | Beschrijving | API |
|-------|--------------|-----|
| Disputes | Overzicht geschillen | `vault-console/disputes` |
| Incident oplossen | `vault-console/incidents/{id}/resolve` | |

---

## Prioriteit (suggestie)

| Fase | Schermen | Reden |
|------|----------|-------|
| **1** | Login, Dashboard, Support/Tickets | Dagelijks gebruik: overzicht + support afhandelen |
| **2** | Gebruikers zoeken, detail, notities | Veel vragen gaan over specifieke gebruikers |
| **3** | Boekingen monitor, annuleren, refund | Ondersteuning bij betalingen/annuleringen |
| **4** | Betalingen, payouts, promo’s | Financiële taken |
| **5** | Rest (security, audit, organisaties, etc.) | Minder frequent |

---

## Technische keuzes (nog te bepalen)

- **Waar:** In bestaande Flutter-app of aparte admin-app?
- **Navigatie:** Drawer, bottom nav, of tabbar?
- **Capabilities:** Per medewerker verschillende rechten (alleen tickets vs. ook users/betalingen)?
- **Offline:** Moet support offline kunnen werken (berichten later syncen)?
- **Notificaties:** Push bij nieuw ticket of bericht?

---

## Koppeling bestaande app

- Support-tickets komen van `client_support_screen.dart` (klant) en trainer-support.
- API-client en auth kunnen hergebruikt worden; extra base URL of header voor vault-console indien nodig.
- Backend vereist `admin.access` capability + mogelijk IP-allowlist.
