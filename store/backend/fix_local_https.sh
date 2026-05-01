#!/bin/bash
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Fix local HTTPS + investigate AWS proxy    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
set -e
LP="/var/www/gymies"
FROM=$(date +%Y-%m-%d)
TO=$(date -d '+7 days' +%Y-%m-%d)

echo "=== 1. Enable APP_DEBUG temporarily ==="
sudo sed -i 's/APP_DEBUG=false/APP_DEBUG=true/' "$LP/.env"
echo "  ✓ APP_DEBUG=true"
sudo -u www-data php -r "opcache_reset();" 2>/dev/null || true
sudo systemctl restart php8.4-fpm
echo "  ✓ PHP-FPM restarted"

# Clear config cache so .env change takes effect
cd "$LP"
sudo -u www-data php artisan config:clear 2>&1

echo ""
echo "=== 2. Test local HTTPS with --resolve (see full error) ==="
echo "Testing availability endpoint..."
RESP=$(curl -sk --resolve "www.gymiesapp.nl:443:127.0.0.1" -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "  Response:"
echo "$RESP" | python3 -m json.tool 2>/dev/null || echo "$RESP"

echo ""
echo "=== 3. Check Laravel log for error details ==="
sudo truncate -s 0 "$LP/storage/logs/laravel.log"
# Make request again to generate fresh log
curl -sk --resolve "www.gymiesapp.nl:443:127.0.0.1" -H "Accept: application/json" \
  "https://www.gymiesapp.nl/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" > /dev/null 2>&1
echo "Laravel log (last 30 lines):"
sudo tail -30 "$LP/storage/logs/laravel.log" 2>/dev/null || echo "No log"

echo ""
echo "=== 4. Test HTTP localhost (which works) ==="
RESP2=$(curl -s -H "Accept: application/json" -H "Host: www.gymiesapp.nl" \
  "http://127.0.0.1/api/gymies/trainers/27/availability?from=${FROM}&to=${TO}" 2>/dev/null)
echo "$RESP2" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    bs = d.get('bookable_slots', [])
    print(f'  HTTP localhost: bookable_slots={len(bs)} ✓')
except:
    print('  HTTP localhost: not JSON')
" 2>/dev/null

echo ""
echo "=== 5. Investigate AWS proxy ==="
echo "Server IP: $(hostname -I | awk '{print $1}')"
echo "DNS www.gymiesapp.nl resolves to: $(dig +short www.gymiesapp.nl 2>/dev/null || echo 'unknown')"
echo "DNS www.gymies.nl resolves to: $(dig +short www.gymies.nl 2>/dev/null || echo 'unknown')"
echo ""
echo "Checking if there's a CDN/proxy config..."
# Check for Cloudflare, CloudFront or other proxy indicators
echo "Traceroute to www.gymiesapp.nl (first 5 hops):"
traceroute -m 5 -w 2 www.gymiesapp.nl 2>/dev/null || echo "traceroute not available"
echo ""
echo "Reverse DNS of 18.159.130.187:"
dig +short -x 18.159.130.187 2>/dev/null || host 18.159.130.187 2>/dev/null || echo "No reverse DNS"
echo ""
echo "What does the AWS proxy return for a simple request?"
curl -sv --max-time 5 "https://www.gymiesapp.nl/api/gymies/trainers/27" 2>&1 | grep -E "< HTTP|< server|< x-|< content-type|< cf-|< via|< age" || echo "No useful headers"

echo ""
echo "=== 6. Disable APP_DEBUG again ==="
sudo sed -i 's/APP_DEBUG=true/APP_DEBUG=false/' "$LP/.env"
cd "$LP"
sudo -u www-data php artisan config:clear 2>&1
sudo systemctl restart php8.4-fpm
echo "  ✓ APP_DEBUG=false restored"

echo ""
echo "--- Done ---"
REMOTE

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ Local HTTPS debug + AWS proxy investigation       ║"
echo "╚══════════════════════════════════════════════════════╝"
