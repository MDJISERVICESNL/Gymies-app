# Verificatie: Betaling sessie bij Jamai (demo-klant@gymies.nl)

## Te controleren punten

### 1. Juiste prijs

| Waar | Verwacht |
|------|----------|
| **Boeking** | `amount_cents` komt van het pakket of de sessieprijs van de trainer |
| **POST payments/start** | Backend haalt bedrag uit de boeking (`booking.amount_cents` of equivalent) |
| **Mollie payment** | `amount` in Mollie API = `amount_cents / 100` euro (Mollie wil bedrag in euro met 2 decimalen, of in cent) |

**Bron van prijs:** De boeking wordt aangemaakt via `direct-book` met een `packageId`. Het pakket heeft een prijs. Die moet in de boeking (`amount_cents`) staan en zo aan Mollie worden doorgegeven.

---

### 2. Terugkoppeling: is de betaling betaald?

| Mechanisme | Endpoint | Doel |
|------------|----------|------|
| **Mollie webhook** | `POST api/gymies/webhooks/mollie` | Mollie roept dit aan bij statuswijziging (paid, failed, etc.) |
| **Payment status** | `GET api/gymies/bookings/{id}/payment-status` | App kan handmatig status opvragen |
| **Boeking refresh** | `GET api/gymies/bookings` | `paid_at` en `payment_status` op de boeking |

**GymiesPaymentController::mollieWebhookHandler** moet:
1. Payment-ID uit Mollie-request halen
2. Bij Mollie de payment status opvragen (of uit webhook-payload)
3. Als status = `paid`: in DB `paid_at` (en evt. `payment_status`) bijwerken voor de gekoppelde boeking

---

### 3. Wanneer is de betaling betaald? (paid_at)

| Veld | Bron |
|------|------|
| `paid_at` | Datum/tijd waarop Mollie de betaling als `paid` meldt |
| Update moment | Bij verwerking van de webhook, zodra Mollie `status: paid` stuurt |

De webhook wordt asynchroon aangeroepen door Mollie. `paid_at` moet de `createdAt` of `paidAt` van de Mollie payment zijn, of `now()` op het moment van webhook-verwerking.

---

## Test uitvoeren

```bash
# Met wachtwoord van demo-klant@gymies.nl
bash test_booking_payment_full.sh <wachtwoord>
```

Het script:
1. Logt in als demo-klant@gymies.nl
2. Haalt boekingen op (zoekt boeking bij Jamai)
3. Toont prijs (amount_cents)
4. Start betaling en toont payment_url
5. Haalt payment-status op (status, paid_at)

**Na betalen via de payment_url:** Draai het script opnieuw of poll `GET bookings/{id}/payment-status` om te controleren of `status: paid` en `paid_at` gevuld zijn.

---

## Backend (GymiesPaymentController) – checklist

- [ ] `startPayment`: haalt `amount_cents` uit de boeking, niet uit de request body
- [ ] `startPayment`: maakt Mollie payment aan met het juiste bedrag
- [ ] `startPayment`: retourneert `payment_url` (en evt. `payment_id` voor webhook-koppeling)
- [ ] `startPayment`: gebruikt `redirectUrl` = `gymies://payment/complete?booking_id={id}` (of web-URL)
- [ ] `mollieWebhookHandler`: koppelt Mollie payment aan boeking (via metadata of lookup-tabel)
- [ ] `mollieWebhookHandler`: bij status `paid` → update `paid_at` en `payment_status` op de boeking
- [ ] `paymentStatus`: retourneert `status`, `paid_at` (en evt. `payment_id`)
