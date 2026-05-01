# Mollie Connect: Betalingen naar trainer + zichtbaar onder Klanten

## Probleem
- Betalingen verschijnen nu in het **centrale Gymies Mollie-account** (de "Mollie app").
- **Gewenst:** Betalingen gaan **rechtstreeks naar het Mollie-account van de trainer** (Mollie Connect).
- **Gewenst:** Trainers zien betalingen **onder Klanten** – per klant de betalingen die die klant heeft gedaan.

---

## Deel 1: Backend – Betaling via trainer's Mollie Connect

### Huidige situatie
`GymiesPaymentController::startPayment` maakt waarschijnlijk een Mollie payment aan met `MOLLIE_API_KEY` (platform key). Daardoor gaat het geld naar het centrale Gymies account.

### Gewenste situatie
De payment moet worden aangemaakt **met de trainer's Mollie Connect token** (`mollie_access_token` in `gymies_trainer_profiles`). Mollie API ondersteunt dit via **On-behalf-of payments**: je roept de API aan met de OAuth access token van de trainer.

### Aanpassing in GymiesPaymentController::startPayment

1. **Boeking ophalen** → trainer_id / user_id van de trainer bepalen.
2. **Trainer profile ophalen** → `gymies_trainer_profiles` waar `user_id` = trainer.
3. **Controleren of trainer Mollie Connect heeft gedaan**:
   - `mollie_access_token` moet gevuld zijn.
   - Zo niet: foutmelding: *"Deze trainer heeft nog geen Mollie-account gekoppeld. Vraag de trainer om Mollie Connect te doen in de app."*
4. **Token decoderen** → `decrypt($profile->mollie_access_token)`.
5. **Mollie payment aanmaken via trainer's token**:
   - Niet: `new \Mollie\Api\MollieApiClient()` met platform key
   - Wel: Mollie API aanroepen met `Authorization: Bearer {trainer_access_token}`

**Mollie API (on-behalf-of):**
```
POST https://api.mollie.com/v2/payments
Authorization: Bearer {trainer_access_token}   // trainer's OAuth token
Content-Type: application/json

{
  "amount": { "currency": "EUR", "value": "65.00" },
  "description": "Sessie bij {trainer_naam}",
  "redirectUrl": "gymies://payment/complete?booking_id={id}",
  "metadata": { "booking_id": "{id}" },
  "webhookUrl": "https://www.gymies.nl/api/gymies/webhooks/mollie"
}
```

**Let op:** Bij Mollie Connect moet de webhook vaak op platform-niveau blijven (Mollie roept jouw server aan). De `metadata.booking_id` zorgt dat de webhook de juiste boeking bijwerkt. De **betaal-link** en het **geld** gaan naar de trainer's account.

### Webhook
`mollieWebhookHandler` blijft hetzelfde: Mollie stuurt de webhook naar jouw URL. Je moet de payment kunnen koppelen aan de boeking (via metadata). De status-update (paid_at) werkt ongeacht welk Mollie-account de payment heeft: jij hebt de payment_id en kunt de status ophalen.

**Belangrijk:** Bij Connect kan de webhook een `testmode`-parameter bevatten. Controleer of je in productie/live de juiste webhook-URL gebruikt.

---

## Deel 2: Backend – API voor betalingen per klant (trainer)

### Nieuw endpoint
```
GET trainer/clients/{clientUserId}/payments
```
**Response:**
```json
{
  "data": [
    {
      "booking_id": "33",
      "amount_cents": 6500,
      "currency": "EUR",
      "status": "paid",
      "paid_at": "2025-03-13T14:30:00Z",
      "session_date": "2025-03-15",
      "reference_id": "tr_xxx"
    }
  ]
}
```

**Logica:**
- Haal alle boekingen waar `trainer_user_id` = ingelogde trainer EN `client_user_id` = clientUserId
- Filter op boekingen met `paid_at` niet null (of status betaald)
- Optioneel: ook "open" / "pending" betalingen tonen

**Alternatief:** Uitbreiden van `GET trainer/clients/{clientUserId}/dossier` met een `payments`-array.

---

## Deel 3: App – Betalingen zichtbaar onder Klanten

### Locatie
- **Klanten / CRM** (`TrainerSuiteScreen` → `TrainerClientsScreen`)
- Of: **Klantdossier** (`TrainerClientDossierScreen`)

### Optie A: In klantdossier (per klant)
Open `TrainerClientDossierScreen` → voeg een sectie **"Betalingen"** toe:
- Lijst van betaalde sessies (booking + amount + paid_at)
- Alleen-lezen; bron: `GET trainer/clients/{clientUserId}/payments`

### Optie B: Aparte "Betalingen" tab in Klanten
In `TrainerClientsScreen`: naast "Sleeping clients" een tab of sectie "Betalingen" die alle betalingen van alle klanten toont, met client-naam erbij.

**Aanbeveling:** Start met **Optie A** (in dossier): wanneer je een klant opent, zie je hun betalingen. Dat sluit aan bij "onder klanten ... dan zie je de betalingen".

---

## Checklist implementatie

### Backend (server)
- [ ] `GymiesPaymentController::startPayment`: gebruik trainer's `mollie_access_token` i.p.v. platform key
- [ ] Fallback: als trainer geen Mollie Connect heeft → duidelijke foutmelding
- [ ] `GET trainer/clients/{clientUserId}/payments` endpoint toevoegen (of uitbreiden dossier)
- [ ] Webhook: metadata.booking_id correct verwerken (blijft waarschijnlijk werken)

### App
- [ ] `GymiesApi`: methode `getTrainerClientPayments(clientUserId)` 
- [ ] `TrainerClientDossierScreen`: sectie "Betalingen" met lijst
- [ ] Of: extra tab/sectie in Klanten-overzicht

---

## Mollie Connect – technische referentie

- [Mollie Connect – On-behalf-of](https://docs.mollie.com/connect/on-behalf-of-payments): payments aanmaken met de token van de connected account
- [Mollie API – Create payment](https://docs.mollie.com/reference/v2/payments-api/create-payment)
- Scope die trainers al hebben: `payments.read payments.write` (zie MollieConnectOAuthTrait)
