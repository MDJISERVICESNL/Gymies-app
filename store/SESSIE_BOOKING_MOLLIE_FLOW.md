# Sessie boeken + betalen via Mollie – flow en uitleg

## Overzicht

**Trainers** moeten **Mollie Connect** doen (éénmalig) om hun Mollie-account te koppelen.  
**Klanten** hoeven géén aparte koppeling te doen – zij betalen gewoon als elke andere Mollie-betaling (iDEAL, kaart, etc.).

De betaling gaat naar het Mollie-account van de **trainer** (via Mollie Connect). De klant ziet het normale Mollie-checkoutscherm.

---

## Flow: klant boekt sessie en betaalt

### 1. Boeking aanmaken

- Klant kiest trainer, tijdslot, pakket → `POST bookings/direct-book`
- Boeking wordt aangemaakt met status "unpaid"

### 2. Betaling starten (in de app)

- Klant tikt op "Betaling starten" bij de boeking
- App roept `POST bookings/{id}/payments/start` aan
- Backend maakt een **Mollie payment** aan (via de trainer’s Mollie Connect token)
- Backend retourneert een **payment_url** (Mollie checkout-URL)

### 3. Naar Mollie (browser)

- De app opent de **payment_url** in de browser (Chrome, Safari, etc.)
- Klant kiest betaalmethode (iDEAL, Bancontact, kaart, etc.) en betaalt
- Dit is een **normale Mollie-betaling** – geen speciale koppeling nodig

### 4. Terug naar de app

- Mollie stuurt na betaling een **redirect** naar een URL die de app opent
- Bijvoorbeeld: `https://www.gymies.nl/app/payment/complete?booking_id=xxx`
- Via **App Links** (Android) / **Universal Links** (iOS) opent die URL de Gymies-app
- App toont het sessiescherm met bijgewerkte betaalstatus

---

## Wat is “verbonden met Mollie”?

| Rol    | Wat moet er gebeuren?                          |
|--------|-----------------------------------------------|
| **Trainer** | Mollie Connect – éénmalig in de app, dan is hun Mollie-account gekoppeld |
| **Klant**   | Niets – betaalt gewoon via het normale Mollie-checkoutscherm |

De klant hoeft alleen op "Betaling starten" te tikken en vervolgens in de browser te betalen. Geen aparte “verbinden met Mollie”-stap.

---

## Technische randvoorwaarden

### Backend (GymiesPaymentController) – **actie vereist**

Bij het aanmaken van de Mollie payment **moet** de `redirectUrl` exact zijn:

```
redirectUrl = gymies://payment/complete?booking_id={booking_id}
```

Voorbeeld: `gymies://payment/complete?booking_id=abc123`

De app luistert naar dit custom URL-scheme. Na betaling opent Mollie deze URL in de browser; de OS stuurt dat door naar de app, die dan het sessiescherm toont met "Betaling voltooid!".

**Alternatief** (als je Universal Links gebruikt):  
`https://www.gymies.nl/app/payment/complete?booking_id={id}` – vereist dat die pagina een redirect doet naar `gymies://payment/complete?booking_id={id}` of dat App Links correct geconfigureerd zijn.

### App – geïmplementeerd ✅

1. **Sessiescherm** (`client_sessions_screen.dart`): na `startBookingPayment` wordt de payment_url nu geopend met `launchUrl(payment_url, LaunchMode.externalApplication)`. De klant wordt direct doorgestuurd naar de Mollie betaalpagina.

2. **Deep links** (`gymies://payment/complete?booking_id=X`):  
   - Android: `intent-filter` voor scheme `gymies`, host `payment`  
   - iOS: `CFBundleURLTypes` voor scheme `gymies`  
   De app opent automatisch wanneer Mollie na betaling redirect naar dit URL.

### Website redirect-pagina

Op `https://www.gymies.nl/app/payment/complete` moet een pagina staan die:
- Ofwel: een redirect doet naar `gymies://payment/complete?booking_id=xxx` (custom scheme, werkt zonder App Links)
- Ofwel: een “Terug naar app”-knop toont met een deep link
- Ofwel: automatisch de app opent via App Links (als die geconfigureerd zijn)

---

## Samenvatting: wat te bouwen

| Onderdeel | Status | Actie |
|-----------|--------|-------|
| Mollie Connect (trainer) | ✅ | Al aanwezig |
| Backend: payment aanmaken | ✅ | Bestaat (GymiesPaymentController) |
| Backend: redirectUrl instellen | ❓ | Controleren of dit correct staat |
| App: payment_url openen | ❌ | `launchUrl()` toevoegen in sessiescherm |
| App Links / Universal Links | ❌ | Configureren voor `gymies.nl/app/*` |
| Website: redirect-pagina | ❓ | Controleren of die bestaat en app opent |

---

## Flow-diagram

```
[Klant in app] → Betaling starten
       ↓
[API] startPayment → Mollie payment aanmaken
       ↓
[App] launchUrl(payment_url) → externe browser opent
       ↓
[Browser] Mollie checkout (iDEAL/kaart/…)
       ↓
[Klant] Betaalt
       ↓
[Mollie] Redirect naar redirectUrl (bijv. gymies.nl/app/payment/complete?booking_id=X)
       ↓
[App Link] Opent Gymies app
       ↓
[App] Sessiescherm, betaalstatus bijgewerkt (via webhook)
```

De **Mollie webhook** (`POST webhooks/mollie`) zorgt ervoor dat de betaalstatus in de database wordt bijgewerkt. De redirect is alleen voor de gebruikerservaring (terug naar de app), niet voor de technische verwerking van de betaling.
