# Gymies — Mollie Betalingen Testen

## 1. Voorbereiding

### 1.1 Mollie Test Key ophalen
1. Log in op [my.mollie.com](https://my.mollie.com)
2. Selecteer de Gymies organisatie
3. Ga naar **Developers → API keys**
4. Kopieer de **Test API key** (begint met `test_`)

### 1.2 Backend .env configureren
Voeg toe aan je `.env` (zie `.env.testing.example` voor alle variabelen):

```
MOLLIE_API_KEY=test_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
MOLLIE_TESTMODE=true
```

Daarna: `php artisan config:cache`

### 1.3 Webhook bereikbaar maken (lokaal)
Mollie moet je webhook kunnen bereiken. Voor lokaal testen:

```bash
ngrok http 8000
```

Kopieer de ngrok URL en zet in `.env`:
```
APP_URL=https://jouw-id.ngrok-free.app
```

Opnieuw: `php artisan config:cache`

De webhook URL wordt automatisch: `{APP_URL}/api/gymies/webhooks/mollie`

### 1.4 Flutter app configureren
Build de app met je test HMAC secret:

```bash
flutter run --dart-define=GYMIES_HMAC_SECRET=test-hmac-secret-alleen-voor-lokaal
```

Zorg dat `app_config.dart` naar je test-backend wijst (ngrok URL of lokaal IP).

---

## 2. Test Flows

### 2.1 Individuele Sessie (Client → Trainer)

**Stappen:**
1. Log in als **client** in de app
2. Open een trainersprofiel (via zoeken of directe link)
3. Kies een beschikbaar tijdslot
4. Tik op **Boeken** → bevestig de prijs
5. Je wordt doorgestuurd naar Mollie checkout
6. Kies **iDEAL** → selecteer **TBM Bank** (Mollie testbank)
7. Kies **Paid** (of **Failed** / **Cancelled** om foutpaden te testen)
8. Je wordt teruggestuurd naar de app via `gymies://payment/complete?booking_id=X`

**Verwacht resultaat (Paid):**
- App toont "Betaling gelukt!" na polling (max 30 seconden)
- Sessie verschijnt in "Mijn Sessies" met status `bevestigd`
- Trainer ziet de boeking in zijn dashboard
- In-app review prompt verschijnt

**Verwacht resultaat (Failed):**
- App toont foutmelding na polling
- Sessie staat als `niet betaald` — client kan opnieuw betalen via "Mijn Sessies"

### 2.2 Duo/Buddy Sessie

**Flow boeker (Client A):**
1. Log in als client A
2. Open trainersprofiel → kies tijdslot
3. Selecteer **Duo sessie**
4. Bevestig je eigen prijs (reguliere prijs minus duo_discount_percent, standaard 25% korting)
5. Betaal via Mollie (iDEAL → TBM Bank → Paid)
6. Na betaling: deel de buddy-uitnodigingslink

**Flow vriend (Client B):**
1. Open de uitnodigingslink: `gymies://buddy/join?booking_id=X&trainer_id=Y`
2. Als niet ingelogd: registreer eerst → daarna terug naar buddy flow
3. Bevestig deelname + prijs (zelfde bedrag als boeker)
4. Betaal via Mollie
5. Na betaling: sessie staat bevestigd voor beiden

**Te testen:**
- [ ] Link openen als niet-ingelogde gebruiker → registratie → redirect terug
- [ ] Link openen als al ingelogde gebruiker → direct buddy bevestiging
- [ ] Boeker annuleert voordat vriend betaalt → vriend ziet melding
- [ ] Vriend laat link verlopen → boeker krijgt melding

### 2.3 Groepssessie (Crowdfund)

**Flow trainer:**
1. Log in als trainer
2. Maak een groepssessie aan met:
   - Prijs per deelnemer
   - Minimum deelnemers (drempel, bijv. 4)
   - Deadline datum
3. Publiceer de sessie

**Flow client:**
1. Open de groepssessie
2. Meld je aan → betaling wordt **pas** geïncasseerd na bevestiging
3. Je ziet de crowdfund voortgang (bijv. "3 van 4 aanmeldingen")

**Bevestiging (drempel bereikt):**
- Wanneer minimum deelnemers bereikt: trainer bevestigt de sessie
- Alle aangemelde deelnemers ontvangen een betalingsverzoek
- Elke deelnemer betaalt individueel via Mollie
- Na betaling: sessie verschijnt in "Mijn Sessies"

**Deadline verlopen (drempel niet bereikt):**
- Cron job (`cron/crowdfund-check`) controleert dagelijks
- Sessie wordt geannuleerd
- Alle aangemelde deelnemers ontvangen melding
- Geen betalingen geïncasseerd

### 2.4 Trainer Abonnement (Pro/Elite)

**Stappen:**
1. Log in als trainer
2. Ga naar Instellingen → Abonnement
3. Kies Pro of Elite plan
4. Betaal via Mollie (iDEAL → TBM Bank)
5. Return via `gymies://subscription/complete?tier=pro`

**Verwacht resultaat:**
- Abonnement actief in dashboard
- Pro/Elite features beschikbaar

### 2.5 Mollie Connect (Trainer Onboarding)

**Stappen:**
1. Log in als trainer
2. Ga naar Instellingen → Betalingen
3. Klik "Koppel met Mollie" → OAuth flow
4. In Mollie: autoriseer de koppeling
5. Return via `gymies://mollie-connect/success`

**Verwacht resultaat:**
- Trainer heeft Mollie Connect profiel
- Betalingen gaan direct naar trainer's Mollie account
- Platform fee wordt automatisch afgetrokken

---

## 3. Mollie Test Betaalmethoden

| Methode | Hoe te testen |
|---------|---------------|
| **iDEAL** | Selecteer "TBM Bank" → kies status (Paid/Failed/Cancelled/Expired) |
| **Creditcard** | Gebruik testkaartnummer: `3782 822463 10005` (Amex) |
| **Bancontact** | Automatisch gesimuleerd in testmode |
| **Apple Pay** | Niet beschikbaar in testmode — skip |

---

## 4. Webhook Testen

### Handmatig webhook testen
Als je de webhook handmatig wilt triggeren (zonder Mollie):

```bash
curl -X POST https://jouw-ngrok-url.app/api/gymies/webhooks/mollie \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "id=tr_XXXXXXXXXX"
```

Vervang `tr_XXXXXXXXXX` met een echt Mollie payment ID uit je test dashboard.

### Webhook logs bekijken
In je Mollie Dashboard → Developers → Logs kun je zien:
- Of de webhook succesvol is afgeleverd (HTTP 200)
- Hoeveel retries er zijn geweest
- De response van je server

---

## 5. Edge Cases Checklist

### Betaling
- [ ] Dubbel klikken op "Betaal" knop → slechts 1 payment aangemaakt (idempotency middleware)
- [ ] App sluiten tijdens Mollie checkout → heropenen → betaling hervatten via "Mijn Sessies"
- [ ] Internetverbinding weg tijdens polling → app toont neutrale "wordt verwerkt" melding
- [ ] Payment expired (15 min timeout bij Mollie) → client kan opnieuw betalen

### Slot Booking
- [ ] Twee clients boeken tegelijk hetzelfde slot → slot hold voorkomt dubbele boeking
- [ ] Client navigeert weg na slot hold → hold verloopt na 5 minuten (TTL)
- [ ] Client A houdt slot vast, client B ziet slot als "niet beschikbaar"

### Deep Links
- [ ] Cold start via `gymies://payment/complete?booking_id=123` → opent Mijn Sessies
- [ ] Cold start via `gymies://buddy/join?booking_id=X&trainer_id=Y` → opent trainerprofiel
- [ ] Foreground link via `gymies://trainer/sessions` → opent trainer dashboard
- [ ] Ongeldige deep link → app opent normaal (geen crash)

### Refunds
- [ ] Trainer annuleert sessie → automatische refund via Mollie
- [ ] Gedeeltelijke refund (bij duo sessie, 1 persoon annuleert)

---

## 6. Test Accounts

Maak minimaal deze test accounts aan:
1. **Test Client** — voor het boeken van sessies
2. **Test Client B** — voor buddy/duo sessies
3. **Test Trainer** — met beschikbare tijdsloten en Mollie Connect
4. **Test Admin** — voor dashboard controle

---

## 7. Na het Testen

Wanneer alle flows werken:
1. Vervang `MOLLIE_API_KEY` door je **live** key (begint met `live_`)
2. Zet `MOLLIE_TESTMODE=false`
3. Draai `php artisan config:cache`
4. Verwijder ngrok — `APP_URL` terug naar productie URL
5. Test 1 echte iDEAL betaling van €0,01 om de live flow te valideren
