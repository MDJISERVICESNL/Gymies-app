# Deploy samenvatting – Mollie Connect & betalingen

## Wat is gedeployed (13 maart 2025)

### 1. Mollie Connect – sessiebetalingen naar trainer
- **GymiesPaymentController** is gepatcht om de **trainer's mollie_access_token** te gebruiken
- Betalingen voor sessies gaan nu naar het **Mollie-account van de trainer** (niet het platform)
- **Webhook** is aangepast: Connect-betalingen worden opgehaald via de trainer-token
- De tabel `gymies_booking_mollie_payments` koppelt mollie_payment_id ↔ booking_id voor webhook-verwerking

### 2. Trainer moet Mollie Connect doen
- Als een klant wil betalen bij een trainer **zonder** Mollie Connect:  
  foutmelding: *"Deze trainer heeft nog geen Mollie-account gekoppeld. Vraag de trainer om Mollie Connect te doen in de app."*
- De trainer moet in de app: **Onboarding → Mollie koppelen** doen voordat klanten kunnen betalen

### 3. Mollie dashboard structuur

| Wat | Waar te zien |
|-----|--------------|
| **Maandabonnementen** (trainer → platform) | In jouw Mollie dashboard: **Sales → Subscriptions** – klanten die een maandabonnement bij Gymies hebben |
| **Sessiebetalingen** (klant → trainer) | Via **Mollie Connect** – elke trainer heeft een eigen Mollie-account; betalingen verschijnen daar. Jij ziet ze onder **Connect** / gekoppelde accounts |

**In jouw dashboard:**
- Sales: maandelijkse abonnementen van klanten
- Connect: overzicht van gekoppelde trainers en hun betalingen (afhankelijk van jouw Connect-configuratie)

## Testen van de betaling

### Stap 1: Trainer Mollie Connect
1. Log in als trainer (bijv. `demo@gymies.nl` / `demo123!`)
2. Ga naar **Onboarding** (of Instellingen → Mollie koppelen)
3. Vul documenten in (KvK, ID, certificering)
4. Klik **Mollie koppelen** en voltooi de OAuth-flow

### Stap 2: Klant betaalt sessie
1. Log in als klant (bijv. `demo-klant@gymies.nl` / `demo123!`)
2. Maak of bevestig een boeking bij de trainer
3. Start de betaling
4. Je krijgt een Mollie checkout-URL – betaal (testmodus: iDEAL test)
5. Na betaling: webhook zet `paid_at` op de boeking

### Testscript (vanuit projectroot)
```bash
bash test_booking_payment_full.sh demo123!
```

## Trainer documenten & account actief

De **app** toont al "Activeer je account" als de trainer onboarding niet heeft voltooid. De onboarding-flow bevat:
- KvK-uittreksel
- ID-document
- Certificering
- Mollie Connect (vereist voor betalingen)
- Plan selectie

Als je wilt dat trainers **niet zichtbaar zijn** in zoekresultaten voordat zij documenten hebben ingevuld, dan moet de backend (GymiesTrainerController::index) worden aangepast om trainers zonder documenten te filteren. Dat vereist een check op documenten-status in de trainerlijst.

## Handmatig patch uitvoeren (indien nodig)

```bash
bash patch_payment_mollie.sh
```

Dit past de server’s GymiesPaymentController aan voor Mollie Connect.
