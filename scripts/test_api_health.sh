#!/usr/bin/env bash
# API health check – minimale integratietest.
# Gebruik: ./scripts/test_api_health.sh [BASE_URL]
# Voorbeeld: BASE_URL=https://www.gymies.nl/api/gymies ./scripts/test_api_health.sh

BASE_URL="${1:-${GYMIES_API_BASE_URL:-https://www.gymies.nl/api/gymies}}"
BASE_URL="${BASE_URL%/}"

echo "Testing API at $BASE_URL"

# Health endpoint (publiek, geen auth; voor load balancers / uptime monitoring)
HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/ops/health" 2>/dev/null || echo "000")
if [ "$HTTP" = "200" ]; then
  echo "  [OK] GET /ops/health -> 200"
else
  echo "  [FAIL] GET /ops/health -> $HTTP (expected 200)"
  exit 1
fi

# Sitemap (publiek)
HTTP=$(curl -s -o /dev/null -w "%{http_code}" "https://www.gymies.nl/sitemap.xml" 2>/dev/null || echo "000")
if [ "$HTTP" = "200" ]; then
  echo "  [OK] GET /sitemap.xml -> 200"
else
  echo "  [WARN] GET /sitemap.xml -> $HTTP (kan 404 zijn als nginx nog niet geüpdatet)"
fi

# Debug routes: in productie moeten 404 geven (niet 200)
HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/debug-auth-headers" 2>/dev/null || echo "000")
if [ "$HTTP" = "404" ]; then
  echo "  [OK] GET /debug-auth-headers -> 404 (afgeschermd in productie)"
elif [ "$HTTP" = "200" ]; then
  echo "  [WARN] GET /debug-auth-headers -> 200 (zichtbaar; zet APP_ENV=production of verwijder GYMIES_DEBUG_AUTH)"
fi

echo "Done."
