#!/usr/bin/env bash
set -euo pipefail

# Quick launch-readiness checks for Gymies.
# Requires:
# - API_BASE (optional, default https://gymies.nl/api/gymies)
# - Optional tokens:
#   CUSTOMER_TOKEN, TRAINER_TOKEN, GYM_TOKEN

API_BASE="${API_BASE:-https://gymies.nl/api/gymies}"

echo "== Gymies Launch Readiness Checks =="
echo "API_BASE=$API_BASE"

check_get() {
  local url="$1"
  local auth="${2:-}"
  local status
  if [[ -n "$auth" ]]; then
    status="$(curl -sS -o /dev/null -w "%{http_code}" "$url" -H "Authorization: Bearer $auth")"
  else
    status="$(curl -sS -o /dev/null -w "%{http_code}" "$url")"
  fi
  echo "$status"
}

echo
echo "[1/6] Health & metrics"
health="$(check_get "$API_BASE/ops/health" "${GYM_TOKEN:-}")"
metrics="$(check_get "$API_BASE/ops/metrics" "${GYM_TOKEN:-}")"
echo "ops/health => $health"
echo "ops/metrics => $metrics"

echo
echo "[2/6] Role endpoint smoke checks"
if [[ -n "${CUSTOMER_TOKEN:-}" ]]; then
  echo "customer /me => $(check_get "$API_BASE/me" "$CUSTOMER_TOKEN")"
  echo "customer /bookings => $(check_get "$API_BASE/bookings" "$CUSTOMER_TOKEN")"
else
  echo "customer token missing -> skipped"
fi

if [[ -n "${TRAINER_TOKEN:-}" ]]; then
  echo "trainer /trainer/summary => $(check_get "$API_BASE/trainer/summary" "$TRAINER_TOKEN")"
  echo "trainer /trainer/availability => $(check_get "$API_BASE/trainer/availability" "$TRAINER_TOKEN")"
else
  echo "trainer token missing -> skipped"
fi

if [[ -n "${GYM_TOKEN:-}" ]]; then
  echo "gym /gym/membership => $(check_get "$API_BASE/gym/membership" "$GYM_TOKEN")"
  echo "gym /gym/dashboard => $(check_get "$API_BASE/gym/dashboard" "$GYM_TOKEN")"
  echo "gym /gym/dashboard-stats => $(check_get "$API_BASE/gym/dashboard-stats?period=month&compare=1" "$GYM_TOKEN")"
else
  echo "gym token missing -> skipped"
fi

echo
echo "[3/6] Compliance endpoints"
if [[ -n "${CUSTOMER_TOKEN:-}" ]]; then
  echo "gdpr/export => $(check_get "$API_BASE/gdpr/export" "$CUSTOMER_TOKEN")"
  echo "consent => $(check_get "$API_BASE/consent" "$CUSTOMER_TOKEN")"
else
  echo "customer token missing -> skipped"
fi

echo
echo "[4/6] Notifications endpoints"
if [[ -n "${TRAINER_TOKEN:-}" ]]; then
  echo "notifications => $(check_get "$API_BASE/notifications" "$TRAINER_TOKEN")"
  echo "notifications/preferences => $(check_get "$API_BASE/notifications/preferences" "$TRAINER_TOKEN")"
else
  echo "trainer token missing -> skipped"
fi

echo
echo "[5/6] Gym exports sanity"
if [[ -n "${GYM_TOKEN:-}" ]]; then
  echo "gym/bookings/export => $(check_get "$API_BASE/gym/bookings/export" "$GYM_TOKEN")"
  echo "gym/revenue/export => $(check_get "$API_BASE/gym/revenue/export" "$GYM_TOKEN")"
else
  echo "gym token missing -> skipped"
fi

echo
echo "[6/6] Result hints"
echo "- Verwacht: alle kritieke endpoints 200/204."
echo "- 401 betekent meestal fout/missende token."
echo "- Gebruik docs/LAUNCH_READINESS_MASTER_CHECKLIST.md als gate."
echo
echo "Done."
