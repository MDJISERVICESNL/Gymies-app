#!/usr/bin/env bash
# Test: controleer of POST bookings/{id}/payments/start een payment_url teruggeeft.
#
# Gebruik:
#   bash test_booking_payment_start.sh
#   bash test_booking_payment_start.sh <email> <password>
#   bash test_booking_payment_start.sh <email> <password> <booking_id>
#
# Met env vars:
#   GYMIES_EMAIL=klant@example.com
#   GYMIES_PASSWORD=secret
#   BOOKING_ID=abc123  (optioneel - anders eerste betaalbare boeking)
#
# De API moet een payment_url (of url) teruggeven voor Mollie-betaling.

set -euo pipefail

API_BASE="${GYMIES_API_BASE:-https://www.gymies.nl/api/gymies}"
EMAIL="${1:-${GYMIES_EMAIL:-}}"
PASS="${2:-${GYMIES_PASSWORD:-}}"
BOOKING_ID="${3:-${BOOKING_ID:-}}"

if [[ -z "$EMAIL" || -z "$PASS" ]]; then
  echo "Gebruik: bash test_booking_payment_start.sh <email> <password> [booking_id]"
  echo "   of:   GYMIES_EMAIL=... GYMIES_PASSWORD=... bash test_booking_payment_start.sh"
  echo ""
  echo "Log in met een klantaccount dat een onbetaalde boeking heeft."
  exit 1
fi

echo "=== Test: Betalingslink ophalen ==="
echo "API: $API_BASE"
echo ""

# 1. Login
echo "[1/3] Inloggen..."
LOGIN_RESP=$(curl -s -X POST "$API_BASE/login" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")

TOKEN=$(echo "$LOGIN_RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [[ -z "$TOKEN" ]]; then
  echo "Login mislukt. Response:"
  echo "$LOGIN_RESP" | head -20
  exit 1
fi

echo "   Token ontvangen (${#TOKEN} chars)"
echo ""

# 2. Boeking ID ophalen als niet meegegeven
if [[ -z "$BOOKING_ID" ]]; then
  echo "[2/3] Boekingen ophalen..."
  BOOKINGS_RESP=$(curl -s -X GET "$API_BASE/bookings" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer $TOKEN")

  # Zoek eerste boeking die betaalbaar is (heeft amount, nog niet paid)
  BOOKING_ID=$(echo "$BOOKINGS_RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [[ -z "$BOOKING_ID" ]]; then
    echo "Geen boekingen gevonden of geen betaalbare boeking."
    echo "Voer handmatig een booking_id in: bash test_booking_payment_start.sh $EMAIL **** <booking_id>"
    exit 1
  fi
  echo "   Eerste boeking: $BOOKING_ID"
else
  echo "[2/3] Booking ID: $BOOKING_ID"
fi

echo ""

# 3. Betaling starten
echo "[3/3] Betaling starten (POST bookings/$BOOKING_ID/payments/start)..."
PAYMENT_RESP=$(curl -s -X POST "$API_BASE/bookings/$BOOKING_ID/payments/start" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"payment_method":"mollie","method":"mollie"}')

echo ""
echo "=== Response ==="
echo "$PAYMENT_RESP" | python3 -m json.tool 2>/dev/null || echo "$PAYMENT_RESP"
echo ""

# Check op payment_url
PAYMENT_URL=$(echo "$PAYMENT_RESP" | grep -oE '"payment_url"\s*:\s*"[^"]*"' | cut -d'"' -f4)
if [[ -z "$PAYMENT_URL" ]]; then
  PAYMENT_URL=$(echo "$PAYMENT_RESP" | grep -oE '"url"\s*:\s*"[^"]*"' | cut -d'"' -f4)
fi

if [[ -n "$PAYMENT_URL" ]]; then
  echo "=== Betalingslink gevonden ==="
  echo "$PAYMENT_URL"
  echo ""
  echo "OK: API retourneert een betalingslink."
else
  echo "=== Geen betalingslink ==="
  echo "De response bevat geen payment_url of url. Controleer de backend."
  exit 1
fi
