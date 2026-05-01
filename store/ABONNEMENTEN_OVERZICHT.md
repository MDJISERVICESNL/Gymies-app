# Gymies – Abonnementen & Features Overzicht

> Compleet overzicht van alle abonnementstiers, features, gating en technische implementatie.

---

## 1. Tiers

| Tier | Doel | Prijsniveau |
|------|------|-------------|
| **Starter** | Basis voor starten als trainer | Laagste |
| **Pro** | Meest gekozen voor groei | Midden |
| **Elite** | Volledige suite voor schaal | Hoogste |

---

## 2. Alle features per tier

### Basis (Starter+)

| Feature | Key | Starter | Pro | Elite |
|---------|-----|:-------:|:---:|:-----:|
| Sessiebeheer (boekingen, bevestigen, annuleren) | sessions | ✓ | ✓ | ✓ |
| Berichten (1-op-1 chat met klanten) | messages | ✓ | ✓ | ✓ |
| Agenda (beschikbaarheid + uitzonderingen) | agenda | ✓ | ✓ | ✓ |
| Factuur opstellen & versturen | invoice | ✓ | ✓ | ✓ |
| Documenten (bedrijf, factuur, VOG, diploma) | documents | ✓ | ✓ | ✓ |
| Inkomstenoverzicht + filters | income | ✓ | ✓ | ✓ |
| Check-in scanner | checkin | ✓ | ✓ | ✓ |
| No-show registreren | noshow | ✓ | ✓ | ✓ |
| Wachtlijst / standby | waitlist | ✓ | ✓ | ✓ |

### Pro-features (Pro+)

| Feature | Key | Starter | Pro | Elite |
|---------|-----|:-------:|:---:|:-----:|
| Dossier opstellen per klant | dossier | ✗ | ✓ | ✓ |
| Doelen instellen per klant | goals | ✗ | ✓ | ✓ |
| Client health score | health_score | ✗ | ✓ | ✓ |
| Upsell suggesties | upsell | ✗ | ✓ | ✓ |
| Herboek suggesties | rebook | ✗ | ✓ | ✓ |
| Priority support lane | priority_support | ✗ | ✓ | ✓ |
| Bulk bericht naar klanten | bulk_message | ✗ | ✓ | ✓ |
| Klanttags/labels | client_tags | ✗ | ✓ | ✓ |
| Videos op profiel | profile_videos | ✗ | 1 | ∞ |
| Story-achtig op profiel | profile_stories | ✗ | 1 | ∞ |

### Elite-features

| Feature | Key | Starter | Pro | Elite |
|---------|-----|:-------:|:---:|:-----:|
| Geavanceerde rapportage | advanced_reporting | ✗ | ✗ | ✓ |
| Organisatie Elite mode | suite_tools | ✗ | ✗ | ✓ |
| Promoted profiel | promoted_profile | ✗ | ✗ | ✓ |

### Limits per tier

| Feature | Key | Starter | Pro | Elite |
|---------|-----|---------|-----|------|
| Aantal actieve klanten | max_clients | ∞ | ∞ | ∞ |
| Videos op profiel | profile_videos | 0 | 1 | ∞ |
| Story op profiel | profile_stories | 0 | 1 | ∞ |

---

## 3. Gating in de app

- **Starter:** Menu/drawer toont géén links naar Dossier, Pro Hub, Suite
- **Pro:** Dossier en Pro Hub zichtbaar; geen Suite
- **Elite:** Alles zichtbaar

Trainers zien pas wat ze "missen" op het **Abonnement → Features** scherm.

---

## 4. Klant-features (geërfd van trainer)

De klant heeft geen apart abonnement. Wat hij ziet hangt af van de trainer:

| Feature | Starter-trainer | Pro/Elite-trainer |
|---------|:---------------:|:-----------------:|
| Sessies boeken, berichten, factuur, check-in | ✓ | ✓ |
| Dossier / progressie bij trainer | ✗ | ✓ |
| Doelen bij trainer | ✗ | ✓ |
| Coach notes na sessie | ✗ | ✓ |

---

## 5. Admin – Control Tower

### Abonnement handmatig toewijzen (zonder betaling)

In het admin-dashboard kunnen medewerkers een gebruiker een abonnement (Starter/Pro/Elite) toewijzen **zonder dat de gebruiker via Mollie heeft betaald**. Dit is een admin-override voor o.a.:

- Support (compensatie, goodwill)
- Proefperiode / trial
- Partnerschap / samenwerking
- Testaccounts

**API:** `POST vault-console/users/{id}/assign-subscription` – zet `subscription_plan` / tier direct in de database. Geen koppeling met Mollie-betaling vereist.

### Proefperiode met vervaldatum (geïmplementeerd)

Admins kunnen **optioneel een vervaldatum** meegeven bij het toewijzen van een abonnement. Daarmee is een proefperiode mogelijk (bijv. Pro voor 14 dagen).

**Endpoint:** `POST vault-console/users/{userId}/assign-subscription` (admin auth vereist)

**Request body:**
```json
{
  "tier": "pro",
  "valid_until": "2025-04-01"
}
```
- `tier` (verplicht): starter | pro | elite
- `valid_until` (optioneel): ISO-datum waarop het abonnement terugloopt naar Starter. Zonder dit veld = onbeperkt geldig.

**Implementatie:**
- Kolom `subscription_valid_until` in `gymies_trainer_profiles`
- Entitlements (subscription/features, dossier, GymiesPlanManager): als `valid_until < vandaag` → Starter
- Cron: `POST api/gymies/cron/expire-subscription-trials` – zet verlopen proefabonnementen dagelijks terug naar Starter (planneer in crontab)

**Admin UI:** Datumkiezer of dropdown (7 dagen / 14 dagen / 30 dagen / onbeperkt) naast tier-selectie.

### Upgrade now, Downgrade later (geïmplementeerd)

**Beleid:** Trainers behouden hun huidige tier tot het einde van de factuurperiode. Downgrades gaan pas in na de factuurdatum.

**Techniek – `is_pending_downgrade`:**

| Kolom | Type | Doel |
|-------|------|------|
| `subscription_pending_downgrade` | boolean | 1 = downgrade gepland |
| `subscription_downgrades_at` | date (nullable) | Datum waarop downgrade ingaat (einde factuurcyclus) |
| `subscription_downgrade_to` | string | Doeltier: starter \| pro \| elite |

**Resolution:** Tot `downgrades_at` behoudt de trainer de huidige tier. Op en na `downgrades_at` telt `downgrade_to`.

**API `assign-subscription` – downgrade plannen:**
```json
{
  "tier": "elite",
  "pending_downgrade": true,
  "downgrades_at": "2025-03-30",
  "downgrade_to": "pro"
}
```

**Response `subscription/features` bevat:** `is_pending_downgrade`, `downgrades_at`, `downgrade_to` voor UI (banner: "Je abonnement wijzigt naar Pro op 30 maart").

**Cron:** `expire-subscription-trials` werkt ook pending downgrades: zet `subscription_plan` op `downgrade_to` en wist de pending-flags als `downgrades_at <= vandaag`.

**Admin-overzicht:**

| Case | Actie systeem | Rol Admin |
|------|---------------|-----------|
| Upgrade Pro → Elite | Ontgrendel direct (pro-rata betaling) | Check transactie |
| Downgrade Elite → Pro | Zet `pending_downgrade`, `downgrades_at` = einde cyclus | Automatisch |
| Opzegging (Churn) | Starter na einddatum | Optioneel exit-interview |
| Betalingsfout | Grace period + herinnering | Handmatig verlengen bij klacht |

**Data-retention:** Bij downgrade Elite → Pro: extra video's (2 t/m n) worden niet verwijderd maar niet getoond op profiel. Advies: e-mail 3 dagen vóór downgrade om trainer te laten kiezen welke video zichtbaar blijft.

### Hoofdscherm
- Zoek gebruiker (e-mail, naam)
- Open tickets (aantal + lijst)
- Actiepunten (inbox)
- Menu: Abonnement features | Uitloggen

### Abonnement features scherm
- Tabel: Feature | Starter | Pro | Elite
- Per feature: dropdown voor tier, limits invoeren
- Opslaan → PUT naar backend

---

## 6. API-endpoints

| Methode | Endpoint | Doel |
|---------|----------|------|
| GET | `vault-console/subscription-features` | Admin: feature-matrix ophalen |
| PUT | `vault-console/subscription-features` | Admin: feature-matrix opslaan |
| GET | `subscription/features` | Trainer: entitlements ophalen (tier + features) |
| GET | `subscription/my` | Trainer: eigen abonnement |

---

## 7. Database

Tabel: `gymies_subscription_features`

| Kolom | Type |
|-------|------|
| key | string (unique) |
| label | string |
| enabled_from | starter \| pro \| elite |
| type | boolean \| limit |
| limit_starter, limit_pro, limit_elite | int (nullable) |
| sort_order | int |

---

## 8. App-bestanden

| Bestand | Doel |
|---------|------|
| `lib/services/subscription_entitlements_service.dart` | Haalt entitlements, berekent gating |
| `lib/screens/trainer_subscription_screen.dart` | Abonnement-overzicht voor trainers |
| `lib/screens/trainer_dashboard_screen.dart` | Drawer gating (Dossier, Pro Hub, Suite) |
| `lib/screens/control_tower_screen.dart` | Admin-dashboard |
| `lib/screens/admin_subscription_features_screen.dart` | Feature-matrix beheer |

---

## 9. Quick reference per tier

| Tier | Kern |
|------|------|
| **Starter** | Sessies, berichten, agenda, factuur, documenten, inkomsten, check-in, no-show, wachtlijst. Max 25 klanten. Geen dossier, doelen, profiel-video's. |
| **Pro** | Alles Starter + dossier, doelen, health score, upsell, herboek, priority support, bulk bericht. 1 video, 1 story. Onbeperkt klanten. |
| **Elite** | Alles Pro + geavanceerde rapportage, organisatie-mode. Unlimited video's en stories. Promoted profiel. |
