#!/usr/bin/env bash
set -euo pipefail

# Usage:
# BASE_URL="https://gymies.nl" \
# CUSTOMER_TOKEN="..." TRAINER_TOKEN="..." GYM_TOKEN="..." \
# REPLAY_BOOKING_ID="123" REPLAY_MEMBER_USER_ID="456" \
# bash scripts/run_security_smoke_checks.sh

BASE_URL="${BASE_URL:-https://gymies.nl}"
API_BASE="$BASE_URL/api/gymies"
ADMIN_API_PREFIX="${ADMIN_API_PREFIX:-vault-console}"

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

if ! has_cmd curl; then
  echo "curl is required"
  exit 1
fi

check_status() {
  local name="$1"
  local expected="$2"
  local method="$3"
  local path="$4"
  local token="${5:-}"
  local data="${6:-}"

  local headers=(-H "Accept: application/json")
  if [[ -n "$token" ]]; then
    headers+=(-H "Authorization: Bearer $token")
  fi
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

check_replay() {
  local name="$1"
  local method="$2"
  local path="$3"
  local token="$4"
  local data="$5"
  local key="$6"

  local code1
  local code2
  code1="$(curl -sS -o /dev/null -w "%{http_code}" -X "$method" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $token" \
    -H "Idempotency-Key: $key" \
    "$API_BASE$path" -d "$data")"
  code2="$(curl -sS -o /dev/null -w "%{http_code}" -X "$method" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $token" \
    -H "Idempotency-Key: $key" \
    "$API_BASE$path" -d "$data")"

  if [[ "$code1" == "$code2" && ",200,201,409,422," == *",$code1,"* ]]; then
    echo "[PASS] $name -> first:$code1 second:$code2"
  else
    echo "[FAIL] $name -> first:$code1 second:$code2"
  fi
}

echo "== Security smoke checks =="
check_status "Public health endpoint" "200,401" "GET" "/ops/health"

if [[ -n "${GYM_TOKEN:-}" ]]; then
  check_status "Gym dashboard authorized" "200" "GET" "/gym/dashboard" "$GYM_TOKEN"
  check_status "Gym role-protected action" "200" "POST" "/gym/alerts/no_show_followups/complete" "$GYM_TOKEN" '{"status":"done"}'
fi

if [[ -n "${CUSTOMER_TOKEN:-}" ]]; then
  check_status "Customer cannot open gym dashboard" "403" "GET" "/gym/dashboard" "$CUSTOMER_TOKEN"
  check_status "Customer cannot update gym trainer status" "403,404,422" "POST" "/gym/trainers/1/status" "$CUSTOMER_TOKEN" '{"status":"inactive"}'
fi

if [[ -n "${TRAINER_TOKEN:-}" ]]; then
  check_status "Trainer cannot open gym dashboard" "403" "GET" "/gym/dashboard" "$TRAINER_TOKEN"
  check_status "Trainer cannot update gym member role" "403,404,422" "POST" "/gym/members/1/role" "$TRAINER_TOKEN" '{"role":"viewer"}'
fi

if [[ -n "${ADMIN_TOKEN:-}" ]]; then
  check_status "Admin overview authorized" "200" "GET" "/$ADMIN_API_PREFIX/overview" "$ADMIN_TOKEN"
  check_status "Admin users authorized" "200" "GET" "/$ADMIN_API_PREFIX/users" "$ADMIN_TOKEN"
fi

if [[ -n "${CUSTOMER_TOKEN:-}" ]]; then
  check_status "Customer blocked on admin overview" "403,404" "GET" "/$ADMIN_API_PREFIX/overview" "$CUSTOMER_TOKEN"
fi

if [[ -n "${GYM_TOKEN:-}" && -n "${REPLAY_BOOKING_ID:-}" ]]; then
  check_replay \
    "Idempotency replay gym booking reminder" \
    "POST" \
    "/gym/bookings/$REPLAY_BOOKING_ID/send-reminder" \
    "$GYM_TOKEN" \
    '{}' \
    "smoke-replay-booking-reminder-$REPLAY_BOOKING_ID"
fi

if [[ -n "${GYM_TOKEN:-}" && -n "${REPLAY_MEMBER_USER_ID:-}" ]]; then
  check_replay \
    "Idempotency replay gym member role update" \
    "POST" \
    "/gym/members/$REPLAY_MEMBER_USER_ID/role" \
    "$GYM_TOKEN" \
    '{"role":"viewer"}' \
    "smoke-replay-member-role-$REPLAY_MEMBER_USER_ID"
fi

echo "== Done =="
