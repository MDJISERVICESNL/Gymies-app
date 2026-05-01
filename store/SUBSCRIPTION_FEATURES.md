# Abonnement Features – Starter / Pro / Elite

> **Single source of truth** voor welke features bij welk tier horen.  
> Pas dit bestand aan bij wijzigingen; sync daarna de app-logica waar nodig.

---

## Overzicht tiers

| Tier    | Doel                         |
|---------|------------------------------|
| Starter | Basis voor starten als trainer |
| Pro     | Meest gekozen voor groei     |
| Elite   | Volledige suite voor schaal  |

---

## Trainer features per tier

| Feature | Starter | Pro | Elite | Opmerkingen |
|---------|:-------:|:---:|:-----:|-------------|
| Sessiebeheer (boekingen, bevestigen, annuleren) | ✓ | ✓ | ✓ | Basis |
| Berichten (1-op-1 chat met klanten) | ✓ | ✓ | ✓ | Basis |
| Agenda (beschikbaarheid + uitzonderingen) | ✓ | ✓ | ✓ | |
| Factuur opstellen & versturen | ✓ | ✓ | ✓ | |
| Documenten (bedrijf, factuur, VOG, diploma) | ✓ | ✓ | ✓ | |
| Inkomstenoverzicht + filters | ✓ | ✓ | ✓ | |
| Check-in scanner | ✓ | ✓ | ✓ | |
| No-show registreren | ✓ | ✓ | ✓ | |
| Wachtlijst / standby | ✓ | ✓ | ✓ | |
| **Dossier opstellen per klant** | ✗ | ✓ | ✓ | Doelen, progressie, sessie-entries |
| **Doelen instellen per klant** | ✗ | ✓ | ✓ | |
| **Client health score** | ✗ | ✓ | ✓ | Retention, no-show risico, churn |
| **Upsell suggesties** | ✗ | ✓ | ✓ | Pakket-upgrade voorstellen |
| **Herboek suggesties** | ✗ | ✓ | ✓ | Na sessie "boek volgende" |
| **Priority support lane** | ✗ | ✓ | ✓ | Snelle support met context |
| **Bulk bericht naar klanten** | ✗ | ✓ | ✓ | |
| **Geavanceerde rapportage** | ✗ | ✗ | ✓ | Uitgebreide inzichten |
| **Organisatie Elite mode** | ✗ | ✗ | ✓ | *Later: multi-trainer, teambeheer* |
| **Videos op profiel** | ✗ | 1 | ∞ | Pro: max 1 video. Elite: onbeperkt. |
| **Story-achtig (klik op profiel)** | ✗ | 1 (10 sec) | ∞ (10 sec) | Foto/video als Instagram-story; Pro: 1 stuk, Elite: onbeperkt. |
| **Klanttags/labels** | ✗ | ✓ | ✓ | Eigen labels per klant (binnenkort, atleet, blessure, etc.) voor overzicht |
| **Aantal actieve klanten** | max 25 | ∞ | ∞ | Starter: limiet; Pro/Elite: onbeperkt |
| **Promoted profiel** | ✗ | ✗ | ✓ | Elite-trainers vaker bovenaan in zoekresultaten |

*Herinneringen:* Gymies stuurt standaard automatisch reminders naar de klant (24u/1u vooraf). Geldt voor alle tiers.

---

## Zichtbaarheid van features (gating)

**Regel:** Gebruikers zien geen features van een hogere tier in de rest van de app.  
Ze zien pas wat ze "missen" als ze **Abonnement** → **Features** openen.

| Tier | Ziet niet elders | Ziet wél bij Abonnement → Features |
|------|------------------|-------------------------------------|
| **Starter** | Geen Pro-features (dossier, doelen, etc.) in menu’s, dashboards of schermen | Overzicht welke Pro-features hij mist |
| **Pro** | Geen Elite-features (geavanceerde rapportage, unlimited video’s, etc.) elders in de app | Overzicht welke Elite-features hij mist |

- **Starter** → menu/drawer toont géén links naar Pro-only schermen; alleen bij Abonnement → Features ziet hij wat hij zou krijgen.
- **Pro** → geen Elite-only schermen of opties zichtbaar; alleen bij Abonnement → Features ziet hij de Elite-voordelen.

---

## Klant features (geërfd van trainer)

De klant ziet **geen apart abonnement**. Features die de klant ziet hangen af van **de trainer** waarmee hij werkt:

- Als **trainer Starter** → klant ziet geen dossier, doelen, progressie bij die trainer.
- Als **trainer Pro/Elite** → klant ziet wél dossier, doelen, coach-notes bij die trainer.

Bij meerdere trainers kan de klant dus:
- bij trainer A (Starter): geen doelen/dossier;
- bij trainer B (Pro): wél doelen/dossier.

| Feature (klantzicht) | Starter-trainer | Pro/Elite-trainer |
|---------------------|:---------------:|:-----------------:|
| Sessies boeken, afspraken | ✓ | ✓ |
| Berichten | ✓ | ✓ |
| Factuur bekijken / downloaden | ✓ | ✓ |
| Check-in QR | ✓ | ✓ |
| **Dossier / progressie bij trainer** | ✗ | ✓ |
| **Doelen bij trainer** | ✗ | ✓ |
| **Coach notes na sessie** | ✗ | ✓ |

---

## Upsell & onboarding

| Element | Doel |
|---------|------|
| **Vergelijkingstabel** | Eenvoudige tabel Starter vs Pro vs Elite op abonnementsscherm |
| **Feature-teasers** | Subtiele hints (“Ontgrendel met Pro”) bij gerelateerde schermen |
| **Usage nudges** | Bericht na X sessies: “Pro helpt je met dossier en doelen” |
| **Trial Pro/Elite** | Korte trial (bijv. 14 dagen) om Pro of Elite te proberen |

---

## Aanpassingen doorvoeren

1. **Dit bestand bewerken**  
   Pas de tabellen aan voor Starter/Pro/Elite.

2. **App syncen** (waar van toepassing):
   - `lib/screens/trainer_subscription_screen.dart` – feature matrix + `_features` lijst
   - `lib/models/trainer.dart` – `coachToolsEnabled` (o.b.v. tier)
   - Backend: entitlements per trainer (als dit live gaat)

3. **Backend** (als je server-side gating wilt):
   - Endpoint `trainer/{id}/entitlements` of `me/subscription`
   - Response o.a.: `dossier_enabled`, `goals_enabled`, `pro_hub_enabled`, etc.

---

## Quick reference

| Tier | Kernfeatures |
|------|--------------|
| **Starter** | Sessies, berichten, agenda, factuur, documenten, inkomsten, check-in, no-show, wachtlijst. *Geen* dossier, doelen, Pro Hub, profiel-video’s. |
| **Pro** | Alles van Starter + dossier, doelen, health score, upsell, herboek, priority support, bulk bericht. **Profiel:** 1 video, 1 story (10 sec foto/video bij klik). |
| **Elite** | Alles van Pro + geavanceerde rapportage, later organisatie-mode. **Profiel:** unlimited video’s, unlimited stories (10 sec). |
