# Mollie testaccount voor trainers – testinstructies

## Doel

Trainers moeten een Mollie-account koppelen (Mollie Connect) zodat klanten sessies kunnen betalen. Het geld gaat dan naar het Mollie-account van de trainer.

## Stappen voor een trainer om te testen

### 1. Mollie (test)account aanmaken

1. Ga naar **https://www.mollie.com/dashboard**
2. Klik op **Account aanmaken** (of log in als je al een account hebt)
3. Maak een account aan met een e-mailadres (bijv. je eigen e-mail)
4. In het Mollie-dashboard: ga naar **Developers** → **API-sleutels**
5. Zorg dat je **Testmodus** aan staat (toggle bovenin)
6. Je hoeft geen betaalmethodes te activeren voor testen

### 2. Mollie Connect in de Gymies-app

1. Log in de Gymies-app als **trainer**
2. Ga naar **Onboarding** (of het scherm waar “Mollie koppelen” staat)
3. Klik op **Mollie koppelen / Connect**
4. Je wordt naar Mollie geleid → log in (of maak account aan)
5. Autoriseer de koppeling met Gymies
6. Je komt terug in de app; Mollie is dan gekoppeld

### 3. Testbetaling uitvoeren

1. Log in als **klant** (of laat een klant inloggen)
2. Maak een boeking bij de trainer die Mollie heeft gekoppeld
3. Start de betaling voor de sessie
4. Je krijgt een Mollie-checkoutlink → betaal met testgegevens (bijv. iDEAL: kies “betaald”)
5. **Trainer:** in je Mollie-dashboard (Developers → Betalingen) zie je de betaling
6. Het bedrag komt op jouw Mollie-account (in testmodus gaat er geen echt geld om)

## Demo-trainer (Jamai) testen

Voor de betalingstest:

1. Log in als demo-trainer (`demo@gymies.nl` of `jamai1210@live.nl`)
2. Doorloop Mollie Connect (stap 2 hierboven)
3. Run daarna:
   ```bash
   bash test_booking_payment_full.sh demo123!
   ```
4. Betaal via de checkoutlink; de demo-trainer zou de betaling in zijn/haar Mollie-dashboard moeten zien

## Platform testmodus

- Zorg dat op de server **test API-keys** van Mollie staan (`test_...`) als je wilt testen zonder echte betalingen
- De `MOLLIE_CLIENT_ID` en `MOLLIE_CLIENT_SECRET` voor Mollie Connect zijn dezelfde voor test en live
- In testmodus zie je betalingen in de Mollie-dashboard van zowel platform als trainer, zonder echte geldstromen

## Probleem: "Deze trainer heeft nog geen Mollie-account gekoppeld"

Dat betekent dat de trainer van de boeking Mollie Connect nog niet heeft gedaan. De trainer moet stap 1 en 2 hierboven uitvoeren.
