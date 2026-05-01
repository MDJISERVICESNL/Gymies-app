#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────
# Gymies Crontab Setup
# ──────────────────────────────────────────────────────────────────────
# Installeert de crontab voor alle Gymies cron endpoints.
#
# Gebruik:
#   ssh ubuntu@gymies.nl "bash -s" < setup_crontab.sh
#   OF op de server: bash /var/www/gymies/setup_crontab.sh
#
# Belangrijk: GYMIES_CRON_KEY moet in .env staan.
# ──────────────────────────────────────────────────────────────────────

BASE_URL="https://gymies.nl/api/gymies"
ENV_FILE="/var/www/gymies/.env"

# Lees cron key uit .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo "FOUT: $ENV_FILE niet gevonden."
    exit 1
fi

CRON_KEY=$(grep -oP '^GYMIES_CRON_KEY=\K.*' "$ENV_FILE" | tr -d "'\"" || true)
if [[ -z "$CRON_KEY" ]]; then
    echo "FOUT: GYMIES_CRON_KEY niet gevonden in .env"
    exit 1
fi

echo "Cron key gevonden: ${CRON_KEY:0:4}****"
echo "Crontab wordt bijgewerkt..."

# Backup huidige crontab
crontab -l > /tmp/crontab_backup_$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# Genereer nieuwe crontab
# Verwijder eerst eventuele oude gymies cron entries
(crontab -l 2>/dev/null || true) | grep -v 'api/gymies/cron/' > /tmp/crontab_clean || true

# Voeg gymies cron entries toe
cat >> /tmp/crontab_clean << CRON

# ═══════════════════════════════════════════════════════════════
# GYMIES CRON JOBS — gegenereerd op $(date +"%Y-%m-%d %H:%M:%S")
# ═══════════════════════════════════════════════════════════════

# ── VEILIGHEID (elke minuut) ──
# SOS safe-session overdue check: detecteert sessies die te lang duren
* * * * * curl -sf -X POST "${BASE_URL}/cron/safe-session-overdue?key=${CRON_KEY}" > /dev/null 2>&1

# ── BOEKINGEN (elke 15 minuten) ──
# Expire pending bookings: annuleer boekingen zonder trainer-reactie
*/15 * * * * curl -sf -X POST "${BASE_URL}/cron/expire-pending-bookings?key=${CRON_KEY}" > /dev/null 2>&1

# Expire reserved bookings (on-hold slots)
*/15 * * * * curl -sf -X POST "${BASE_URL}/cron/expire-reserved-bookings?key=${CRON_KEY}" > /dev/null 2>&1

# Expire group session payment deadline
*/15 * * * * curl -sf -X POST "${BASE_URL}/cron/expire-group-session-payment-deadline?key=${CRON_KEY}" > /dev/null 2>&1

# Expire group sessions min not reached
*/15 * * * * curl -sf -X POST "${BASE_URL}/cron/expire-group-sessions-min-not-reached?key=${CRON_KEY}" > /dev/null 2>&1

# Expire group session claim pending
*/15 * * * * curl -sf -X POST "${BASE_URL}/cron/expire-group-session-claim-pending?key=${CRON_KEY}" > /dev/null 2>&1

# Expire substitute requests
*/15 * * * * curl -sf -X POST "${BASE_URL}/cron/expire-substitute-requests?key=${CRON_KEY}" > /dev/null 2>&1

# Expire waitlist offers
*/15 * * * * curl -sf -X POST "${BASE_URL}/cron/expire-waitlist-offers?key=${CRON_KEY}" > /dev/null 2>&1

# ── SESSIES (elke 5 minuten) ──
# Auto-complete past sessions
*/5 * * * * curl -sf -X POST "${BASE_URL}/cron/auto-complete-sessions?key=${CRON_KEY}" > /dev/null 2>&1

# Booking reminders
*/5 * * * * curl -sf -X POST "${BASE_URL}/cron/booking-reminders?key=${CRON_KEY}" > /dev/null 2>&1

# Spoed inval: expire + batch1
*/5 * * * * curl -sf -X POST "${BASE_URL}/cron/expire-spoed-inval?key=${CRON_KEY}" > /dev/null 2>&1
*/5 * * * * curl -sf -X POST "${BASE_URL}/cron/spoed-inval-batch1?key=${CRON_KEY}" > /dev/null 2>&1

# ── NOTIFICATIES (elke 2 minuten) ──
# Process queued notification emails
*/2 * * * * curl -sf -X POST "${BASE_URL}/cron/process-notification-emails?key=${CRON_KEY}" > /dev/null 2>&1

# ── DAGELIJKS (om 03:00) ──
# Autopilot retention + low credit
0 3 * * * curl -sf -X POST "${BASE_URL}/cron/auto-pilot-retention?key=${CRON_KEY}" > /dev/null 2>&1
5 3 * * * curl -sf -X POST "${BASE_URL}/cron/auto-pilot-low-credit?key=${CRON_KEY}" > /dev/null 2>&1

# Subscription reminders
10 3 * * * curl -sf -X POST "${BASE_URL}/cron/subscription-reminders?key=${CRON_KEY}" > /dev/null 2>&1

# Expire subscription trials
15 3 * * * curl -sf -X POST "${BASE_URL}/cron/expire-subscription-trials?key=${CRON_KEY}" > /dev/null 2>&1

# Ghost rating triggers + alerts
20 3 * * * curl -sf -X POST "${BASE_URL}/cron/trigger-ghost-ratings?key=${CRON_KEY}" > /dev/null 2>&1
25 3 * * * curl -sf -X POST "${BASE_URL}/cron/ghost-rating-alerts?key=${CRON_KEY}" > /dev/null 2>&1

# Generate session invoices
30 3 * * * curl -sf -X POST "${BASE_URL}/cron/generate-session-invoices?key=${CRON_KEY}" > /dev/null 2>&1

# Crowdfund check
35 3 * * * curl -sf -X POST "${BASE_URL}/cron/crowdfund-check?key=${CRON_KEY}" > /dev/null 2>&1

# Generate recurring bookings
40 3 * * * curl -sf -X POST "${BASE_URL}/cron/generate-recurring-bookings?key=${CRON_KEY}" > /dev/null 2>&1

# Cleanup idempotency keys (24h+ old)
45 3 * * * curl -sf -X POST "${BASE_URL}/cron/cleanup-idempotency-keys?key=${CRON_KEY}" > /dev/null 2>&1

# ── WEKELIJKS (zondag 04:00) ──
# Recalculate quality scores
0 4 * * 0 curl -sf -X POST "${BASE_URL}/cron/recalculate-quality-scores?key=${CRON_KEY}" > /dev/null 2>&1

# Evaluate ambassador tiers
5 4 * * 0 curl -sf -X POST "${BASE_URL}/cron/evaluate-ambassador-tiers?key=${CRON_KEY}" > /dev/null 2>&1

# ── ELKE 30 MINUTEN ──
# Pro client health refresh + availability check
*/30 * * * * curl -sf -X POST "${BASE_URL}/cron/pro-client-health-refresh?key=${CRON_KEY}" > /dev/null 2>&1
*/30 * * * * curl -sf -X POST "${BASE_URL}/cron/availability-check?key=${CRON_KEY}" > /dev/null 2>&1

# Mollie payment reconciliatie: vang gemiste webhooks op
*/30 * * * * curl -sf -X POST "${BASE_URL}/cron/reconcile-mollie-payments?key=${CRON_KEY}" > /dev/null 2>&1

# ═══════════════════════════════════════════════════════════════
# EINDE GYMIES CRON JOBS
# ═══════════════════════════════════════════════════════════════
CRON

# Installeer nieuwe crontab
crontab /tmp/crontab_clean
rm -f /tmp/crontab_clean

echo ""
echo "Crontab succesvol bijgewerkt!"
echo ""
echo "Samenvatting:"
echo "  - safe-session-overdue:    elke 1 minuut  (was 5 min)"
echo "  - expire-pending-bookings: elke 15 minuten (was 1 uur)"
echo "  - notification-emails:     elke 2 minuten"
echo "  - sessie checks:           elke 5 minuten"
echo "  - expire-* boekingen:      elke 15 minuten"
echo "  - dagelijkse taken:        03:00"
echo "  - wekelijkse taken:        zondag 04:00"
echo ""
echo "Controleer met: crontab -l"
