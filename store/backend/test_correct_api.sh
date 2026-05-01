#!/bin/bash
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — API test op CORRECT domein                 ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)

echo "=== Test 1: www.gymiesapp.nl (Laravel direct) ==="
for TID in 27 63; do
    URL="https://www.gymiesapp.nl/api/gymies/trainers/${TID}/availability?from=${FROM}&to=${TO}"
    echo "  GET $URL"
    RESP=$(wget -qO- --header="Accept: application/json" "$URL" 2>/dev/null || echo '{"_error":"wget_failed"}')
    echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    slots = d.get('slots', [])
    settings = d.get('settings', {})
    msg = d.get('message', '')
    err = d.get('_error', '')
    print(f'  bookable_slots: {len(bs)}')
    print(f'  raw slots: {len(slots)}')
    if settings: print(f'  settings: {json.dumps(settings)}')
    if msg: print(f'  message: {msg}')
    if err: print(f'  error: {err}')
    if len(bs) > 0:
        for s in bs[:3]:
            avail = 'JA' if s.get('available') else 'NEE'
            print(f'    {s[\"date\"]} {s[\"start_time\"]}-{s[\"end_time\"]} ({avail})')
        if len(bs) > 3:
            print(f'    ... en {len(bs)-3} meer')
except Exception as e:
    raw = sys.stdin.read()
    print(f'  PARSE ERROR: {e}')
    print(f'  Raw (first 300): {raw[:300]}')
" 2>/dev/null
    echo ""
done

echo "=== Test 2: www.gymies.nl (Next.js proxy) ==="
for TID in 27 63; do
    URL="https://www.gymies.nl/api/gymies/trainers/${TID}/availability?from=${FROM}&to=${TO}"
    echo "  GET $URL"
    RESP=$(wget -qO- --header="Accept: application/json" "$URL" 2>/dev/null || echo '{"_error":"wget_failed"}')
    FIRST200=$(echo "$RESP" | head -c 200)
    echo "  Response (first 200): $FIRST200"
    echo ""
done

echo "=== Test 3: localhost via PHP-FPM directly ==="
for TID in 27 63; do
    URL="http://127.0.0.1/api/gymies/trainers/${TID}/availability?from=${FROM}&to=${TO}"
    echo "  GET $URL"
    RESP=$(wget -qO- --header="Accept: application/json" --header="Host: www.gymiesapp.nl" "$URL" 2>/dev/null || echo '{"_error":"wget_failed"}')
    echo "$RESP" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    msg = d.get('message', '')
    err = d.get('_error', '')
    print(f'  bookable_slots: {len(bs)}')
    if msg: print(f'  message: {msg}')
    if err: print(f'  error: {err}')
except:
    print(f'  Not JSON')
" 2>/dev/null
    echo ""
done
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ API test klaar                                   ║"
echo "╚══════════════════════════════════════════════════════╝"
