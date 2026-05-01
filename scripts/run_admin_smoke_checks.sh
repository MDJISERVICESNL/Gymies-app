#!/usr/bin/env bash
set -euo pipefail

# Usage:
# BASE_URL="https://gymies.nl" \
# ADMIN_API_PREFIX="vault-console" \
# ADMIN_TOKEN="..." CUSTOMER_TOKEN="..." \
# bash scripts/run_admin_smoke_checks.sh

BASE_URL="${BASE_URL:-https://gymies.nl}"
API_BASE="$BASE_URL/api/gymies"
ADMIN_API_PREFIX="${ADMIN_API_PREFIX:-vault-console}"

check_status() {
  local name="$1"
  local expected="$2"
  local method="$3"
  local path="$4"
  local token="$5"
  local data="${6:-}"

  local headers=(-H "Accept: application/json" -H "Authorization: Bearer $token")
  if [[ -n "$data" ]]; then
    headers+=(-H "Content-Type: application/json")
  fi

  local code
  if [[ -n "$data" ]]; then
    code="$(curl -sS -o /dev/null -w "%{http_code}" -X "$method" "${headers[@]}" "$API_BASE$path" -d "$data")"
  else
    code="$(curl -sS -o /dev/null -w "%{http_code}" -X "$method" "${headers[@]}" "$API_BASE$path")"
  fi

  if [[ ",$expected," == *",$code,"* ]]; then
    echo "[PASS] $name -> $code"
  else
    echo "[FAIL] $name -> got $code expected $expected"
  fi
}

if [[ -z "${ADMIN_TOKEN:-}" ]]; then
  echo "ADMIN_TOKEN ontbreekt"
  exit 1
fi

echo "== Admin smoke checks =="
check_status "Admin overview" "200" "GET" "/$ADMIN_API_PREFIX/overview" "$ADMIN_TOKEN"
check_status "Admin users list" "200" "GET" "/$ADMIN_API_PREFIX/users" "$ADMIN_TOKEN"
check_status "Admin payments list" "200" "GET" "/$ADMIN_API_PREFIX/payments" "$ADMIN_TOKEN"
check_status "Admin tickets list" "200" "GET" "/$ADMIN_API_PREFIX/tickets" "$ADMIN_TOKEN"
check_status "Admin security events" "200" "GET" "/$ADMIN_API_PREFIX/security/events" "$ADMIN_TOKEN"
check_status "Admin audit list" "200" "GET" "/$ADMIN_API_PREFIX/audit" "$ADMIN_TOKEN"

if [[ -n "${CUSTOMER_TOKEN:-}" ]]; then
  check_status "Customer blocked from admin" "403,404" "GET" "/$ADMIN_API_PREFIX/overview" "$CUSTOMER_TOKEN"
fi

echo "== Done =="

