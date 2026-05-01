#!/usr/bin/env bash
# Test: demo-klant@gymies.nl betaalt sessie bij jamai1210@live.nl.
# Controleert: prijs (amount_cents), payment_url, payment-status, paid_at.
#
# Gebruik: bash test_booking_payment_full.sh <wachtwoord>
#   Of:     GYMIES_PASSWORD=secret bash test_booking_payment_full.sh
#
# Vereist: demo-klant@gymies.nl moet een onbetaalde boeking hebben bij Jamai.

set -euo pipefail

API_BASE="${GYMIES_API_BASE:-https://www.gymies.nl/api/gymies}"
EMAIL="demo-klant@gymies.nl"
PASS="${1:-${GYMIES_PASSWORD:-}}"
TRAINER_EMAIL="jamai1210@live.nl"

if [[ -z "$PASS" ]]; then
  echo "Gebruik: bash test_booking_payment_full.sh <wachtwoord>"
  echo "   of:   GYMIES_PASSWORD=secret bash test_booking_payment_full.sh"
  echo ""
  echo "Test: demo-klant@gymies.nl betaalt sessie bij jamai1210@live.nl"
  exit 1
fi

echo "=== Test: Betaling sessie bij Jamai (demo-klant@gymies.nl) ==="
echo "API: $API_BASE"
echo ""

# 1. Login
echo "[1/4] Inloggen als $EMAIL ..."
LOGIN_RESP=$(curl -s -X POST "$API_BASE/login" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASS\"}")

TOKEN=$(echo "$LOGIN_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('token', d.get('data', {}).get('token', '')) or '')
except: print('')
" 2>/dev/null)

if [[ -z "$TOKEN" ]]; then
  echo "Login mislukt. Response:"
  echo "$LOGIN_RESP" | python3 -m json.tool 2>/dev/null || echo "$LOGIN_RESP"
  exit 1
fi

echo "   OK: token ontvangen"
echo ""

# 2. Boekingen ophalen (filter op Jamai)
echo "[2/4] Boekingen ophalen (zoek boekingen bij $TRAINER_EMAIL)..."
BOOKINGS_RESP=$(curl -s -X GET "$API_BASE/bookings" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN")

# Parse JSON en zoek eerste betaalbare boeking bij trainer jamai1210@live.nl
# Boekingen hebben trainer_name of we moeten user/email matchen – API structure kan variëren
BOOKING_ID=$(echo "$BOOKINGS_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    items = d.get('data', d) if isinstance(d.get('data'), list) else (d if isinstance(d, list) else [])
    if not isinstance(items, list):
        items = d.get('bookings', [d]) if isinstance(d.get('bookings'), list) else []
    for b in items:
        bid = b.get('id') or b.get('booking_id')
        amt = b.get('amount_cents') or b.get('amountCents') or 0
        paid = b.get('paid_at') or b.get('paidAt')
        trainer = (b.get('trainer_name') or b.get('trainerName') or b.get('trainer_email') or '').lower()
        if bid and (amt is None or int(amt or 0) > 0) and not paid:
            # Als we trainer filter hebben: trainer moet jamai bevatten
            if 'jamai' in trainer or 'jamai1210' in trainer or not trainer:
                print(bid)
                break
    # Fallback: eerste boeking
    if not items and 'id' in str(d):
        pass
except Exception as e:
    print('', file=sys.stderr)
" 2>/dev/null)

# Fallback: eerste id uit response
if [[ -z "$BOOKING_ID" ]]; then
  BOOKING_ID=$(echo "$BOOKINGS_RESP" | grep -oE '"id"\s*:\s*"[^"]+' | head -1 | cut -d'"' -f4)
fi

if [[ -z "$BOOKING_ID" ]]; then
  echo "Geen betaalbare boeking gevonden."
  echo "Response:"
  echo "$BOOKINGS_RESP" | python3 -m json.tool 2>/dev/null | head -50
  exit 1
fi

# Toon boekingsdetails (prijs)
AMOUNT_CENTS=$(echo "$BOOKINGS_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    items = d.get('data', d) if isinstance(d.get('data'), list) else (d if isinstance(d, list) else [])
    if not isinstance(items, list):
        items = d.get('bookings', [])
    for b in items:
        if (b.get('id') or b.get('booking_id')) == '$BOOKING_ID':
            print(b.get('amount_cents') or b.get('amountCents') or '0')
            break
except: print('0')
" 2>/dev/null)

echo "   Booking ID: $BOOKING_ID"
echo "   Prijs (amount_cents): ${AMOUNT_CENTS:-?} cent = €$(echo "scale=2; ${AMOUNT_CENTS:-0} / 100" | bc 2>/dev/null || echo "?")"
echo ""

# 3. Betaling starten
echo "[3/4] Betaling starten (POST bookings/$BOOKING_ID/payments/start)..."
PAYMENT_RESP=$(curl -s -X POST "$API_BASE/bookings/$BOOKING_ID/payments/start" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"payment_method":"mollie","method":"mollie"}')

echo ""
echo "=== Payment start response ==="
echo "$PAYMENT_RESP" | python3 -m json.tool 2>/dev/null || echo "$PAYMENT_RESP"
echo ""

# Check payment_url
PAYMENT_URL=$(echo "$PAYMENT_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    print(data.get('payment_url') or data.get('url') or d.get('payment_url') or d.get('url') or '')
except: print('')
" 2>/dev/null)

# Check amount in response (als backend die teruggeeft)
RESP_AMOUNT=$(echo "$PAYMENT_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    print(data.get('amount_cents') or data.get('amount') or data.get('value') or d.get('amount_cents') or '')
except: print('')
" 2>/dev/null)

if [[ -n "$PAYMENT_URL" ]]; then
  echo "=== OK: Betalingslink ==="
  echo "$PAYMENT_URL"
  echo ""
  echo "Open deze link in de browser om te betalen. Na betaling:"
  echo "  - Mollie webhook (POST webhooks/mollie) moet paid_at bijwerken"
  echo "  - GET bookings/$BOOKING_ID/payment-status moet status + paid_at tonen"
  echo ""
else
  echo "=== Geen payment_url in response ==="
  exit 1
fi

# 4. Payment status check
echo "[4/4] Betaalstatus ophalen (GET bookings/$BOOKING_ID/payment-status)..."
STATUS_RESP=$(curl -s -X GET "$API_BASE/bookings/$BOOKING_ID/payment-status" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN")

echo ""
echo "=== Payment status response ==="
echo "$STATUS_RESP" | python3 -m json.tool 2>/dev/null || echo "$STATUS_RESP"
echo ""

STATUS=$(echo "$STATUS_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    print(data.get('status') or data.get('payment_status') or d.get('status') or 'onbekend')
except: print('onbekend')
" 2>/dev/null)

PAID_AT=$(echo "$STATUS_RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    data = d.get('data', d)
    print(data.get('paid_at') or data.get('paidAt') or d.get('paid_at') or '')
except: print('')
" 2>/dev/null)

echo "=== Samenvatting ==="
echo "  Booking:      $BOOKING_ID"
echo "  Prijs:        ${AMOUNT_CENTS:-?} cent"
echo "  Status:       $STATUS"
echo "  Betaald op:   ${PAID_AT:-niet betaald}"
echo ""
echo "Na daadwerkelijke betaling via Mollie: status moet 'paid' zijn en paid_at gevuld."
echo "De Mollie webhook (POST webhooks/mollie) moet de backend bijwerken."
