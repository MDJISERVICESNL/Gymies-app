# App-notificaties: volledige uitwerking

Dit document beschrijft het voorstel voor pushnotificaties in de GYMIES-app zodat gebruikers meldingen krijgen **ook wanneer de app gesloten is**. Momenteel werkt de WebSocket alleen als de app open is; voor gesloten app zijn **remote push** (FCM + APNs) nodig.

---

## Huidige situatie

| Component | Status |
|-----------|--------|
| `LocalPushService` | ✅ Bestaat – lokale notificaties (app op achtergrond) |
| `NotificationRealtimeService` | ✅ WebSocket → bij nieuw event lokale push tonen |
| Backend `notifications`-tabel | ✅ Bestaat – Laravel standaard |
| Remote push (FCM/APNs) | ❌ Ontbreekt – nodig voor app gesloten |
| Device tokens opslaan | ❌ Ontbreekt |

---

## Voorgestelde meldingen per rol

### Klanten (client)

| # | Type | Beschrijving | Voorbeeld | Actie bij tap |
|---|------|--------------|-----------|---------------|
| 1 | **Nieuwe boeking bevestigd** | Trainer heeft je sessie bevestigd | "Anna heeft je sessie op 15 maart om 14:00 bevestigd." | → Mijn afspraken |
| 2 | **Boeking afgezegd** | Trainer heeft sessie geannuleerd | "Anna heeft je sessie op 15 maart geannuleerd." | → Mijn afspraken |
| 3 | **Nieuwe chatbericht** | Bericht van trainer | "Anna: Kun je woensdag nog?" | → Chat met trainer |
| 4 | **Standby-plek vrij** | Je stond op wachtlijst, er is een plek | "Er is een plek vrij op 16 maart om 10:00 bij Anna. Boek nu!" | → Standby-boeking |
| 5 | **Nieuwe factuur** | Trainer heeft factuur aangemaakt | "Je hebt een nieuwe factuur van Anna." | → Facturen |
| 6 | **Betalingsherinnering** | Factuur nog niet betaald | "Factuur #123 is binnenkort verschuldigd." | → Facturen |
| 7 | **Reminder 24 uur** | Sessie morgen | "Morgen om 14:00: sessie met Anna." | → Mijn afspraken |
| 8 | **Reminder 2 uur** | Sessie over 2 uur | "Over 2 uur: sessie met Anna om 14:00." | → Mijn afspraken |
| 9 | **Check-in venster open** | Je kunt nu inchecken | "Check-in is nu open voor je sessie om 14:00." | → Check-in QR |
| 10 | **Gemiste check-in** | Je bent niet ingecheckt | "Je hebt je sessie vandaag gemist. Neem contact op met je trainer." | → Mijn afspraken / Chat |
| 11 | **Ticket afgehandeld** | Support heeft je ticket afgesloten | "Je ticket is afgehandeld door Gymies." | → Support |
| 12 | **Pakket-/promo-update** | Nieuwe aanbieding van trainer | "Anna heeft een nieuw pakket: 5 sessies voor €199." | → Trainerprofiel / Chat |

---

### Trainers

| # | Type | Beschrijving | Voorbeeld | Actie bij tap |
|---|------|--------------|-----------|---------------|
| 1 | **Nieuwe boeking** | Klant heeft sessie geboekt | "Marieke heeft een sessie geboekt op 15 maart om 14:00." | → Sessies / Agenda |
| 2 | **Boeking geannuleerd** | Klant heeft afgezegd | "Marieke heeft haar sessie op 15 maart geannuleerd." | → Sessies |
| 3 | **Nieuwe chatbericht** | Bericht van klant | "Marieke: Is donderdag nog een optie?" | → Berichten |
| 4 | **Nieuwe wachtlijst-inschrijving** | Iemand op standby gewacht | "Jan wil op de wachtlijst voor 16 maart." | → Wachtlijst / Sessies |
| 5 | **Standby geaccepteerd** | Klant heeft standby-plek aangenomen | "Marieke heeft de standby-plek op 16 maart geaccepteerd." | → Sessies |
| 6 | **Betaling ontvangen** | Klant heeft factuur betaald | "Betaling van €50 ontvangen van Marieke." | → Inkomsten |
| 7 | **Nieuwe factuur betaald** | Mollie-betaling geslaagd | "Factuur #456 is betaald door Marieke." | → Inkomsten |
| 8 | **Review ontvangen** | Klant heeft beoordeling gegeven | "Marieke heeft je 5 sterren gegeven." | → Profiel / Reviews |
| 9 | **Reminder 24 uur** | Sessie morgen | "Morgen: sessie met Marieke om 14:00." | → Sessies |
| 10 | **Reminder 2 uur** | Sessie over 2 uur | "Over 2 uur: sessie met Marieke." | → Sessies |
| 11 | **Check-in venster** | Tijd om klant te verwachten | "Marieke kan nu inchecken voor 14:00." | → Sessies |
| 12 | **No-show** | Klant is niet komen opdagen | "Marieke heeft niet ingecheckt voor de sessie om 14:00." | → Sessies |
| 13 | **Ticket afgehandeld** | Support heeft je ticket afgesloten | "Je ticket is afgehandeld door Gymies." | → Support |
| 14 | **Subscription/pakket** | Abonnement bijna verlopen, nieuwe Pro Hub lead | "Je Pro-abonnement verlengen?" / "Nieuwe lead voor heraanmelding." | → Instellingen / Pro Hub |

---

## Voorkeuren (per gebruiker, aan/uit)

| Sleutel | Rol | Label |
|---------|-----|-------|
| `booking_confirmed_push` | Klant | Boeking bevestigd/afgezegd |
| `messages_push` | Beide | Chatberichten |
| `standby_push` | Klant | Standby-plek vrij |
| `invoice_push` | Klant | Nieuwe factuur / betalingsherinnering |
| `reminder_t24h_push` | Beide | Reminder 24 uur vooraf |
| `reminder_t2h_push` | Beide | Reminder 2 uur vooraf |
| `reminder_check_in_window_push` | Beide | Check-in venster open |
| `reminder_missed_check_in_push` | Klant | Gemiste check-in |
| `no_show_push` | Trainer | No-show melding |
| `waitlist_push` | Trainer | Wachtlijst / standby geaccepteerd |
| `payment_push` | Trainer | Betaling ontvangen |
| `review_push` | Trainer | Nieuwe review |
| `support_push` | Beide | Ticket afgehandeld |
| `promo_push` | Klant | Promoties / pakket-updates |

---

## Technische architectuur (remote push)

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Laravel API    │────▶│  FCM / APNs      │────▶│  App (gesloten) │
│  (event)        │     │  Push Service    │     │  Notificatie     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                         ▲
        │  POST device-token      │
        ▼                         │
┌─────────────────┐     ┌──────────────────┐
│  device_tokens  │     │  App bij login   │
│  (user_id,      │     │  Registreert     │
│   fcm_token)    │     │  FCM-token       │
└─────────────────┘     └──────────────────┘
```

### Benodigde stappen

1. **Firebase toevoegen**
   - `firebase_core` + `firebase_messaging` in `pubspec.yaml`
   - `GoogleService-Info.plist` (iOS)
   - `google-services.json` (Android)
   - APNs key in Firebase Console

2. **App**
   - Bij login/start: FCM-token ophalen en naar backend sturen  
   - Endpoint: `POST /notifications/device-token`  
   - Deep links in push-payload voor directe navigatie

3. **Backend**
   - Tabel `gymies_device_tokens` (user_id, fcm_token, platform, updated_at)
   - Endpoint om token te registreren
   - Bij elk event (boeking, message, etc.): insert in `notifications` + push via FCM

4. **Event-triggers in backend** (waar nu nog géén push gaat)
   - Nieuwe boeking → push naar trainer
   - Boeking bevestigd/geannuleerd → push naar klant
   - Nieuw bericht → push naar ontvanger
   - Standby-plek vrij → push naar klant op wachtlijst
   - Factuur aangemaakt/betaald → push
   - Reminders (cron/scheduler) → push 24u en 2u voor sessie
   - Check-in venster open (scheduler) → push
   - No-show / gemiste check-in → push
   - Ticket afgehandeld → push (TicketClosedNotificationHelper uitbreiden)
   - Review ontvangen → push naar trainer

---

## Fase-indeling

| Fase | Scope | Geschat |
|------|-------|---------|
| **1** | Firebase setup + device token registratie + backend tabel | 1–2 dagen |
| **2** | Push voor top 3: Nieuwe boeking (trainer), Bericht (beide), Boeking bevestigd (klant) | 1 dag |
| **3** | Overige boekings- en sessie-events (annulering, standby, no-show) | 1 dag |
| **4** | Reminders (24u, 2u, check-in, gemist) via scheduler | 1–2 dagen |
| **5** | Factuur, betaling, review, support, promo | 1 dag |

---

## Volgende stap

Na goedkeuring van deze lijst:
1. Firebase-project aanmaken en configureren
2. Fase 1: device token registratie in app + backend
3. Daarna fase 2 t/m 5 uitrollen

Wil je wijzigingen in de lijst (toevoegen, verwijderen, herschrijven)? Geef dat aan, dan pas ik het document aan.
