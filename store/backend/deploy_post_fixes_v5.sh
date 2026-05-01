#!/bin/bash
set -uo pipefail
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"
LP="/var/www/gymies"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
step() { echo -e "\n${BLUE}═══ $1 ═══${NC}\n"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }

# ── Diagnose: wie herstart Reverb steeds? ──
step "Diagnose — wat beheert het Reverb process?"

echo "  Alle supervisor configs met reverb:"
ssh -i "$SSH_KEY" "$SSH_HOST" "grep -rl 'reverb' /etc/supervisor/conf.d/ 2>/dev/null"

echo ""
echo "  Alle supervisor programs:"
ssh -i "$SSH_KEY" "$SSH_HOST" "sudo supervisorctl status 2>/dev/null"

echo ""
echo "  Systemd units met reverb:"
ssh -i "$SSH_KEY" "$SSH_HOST" "systemctl list-units --all 2>/dev/null | grep -i reverb || echo '  Geen systemd unit'"
ssh -i "$SSH_KEY" "$SSH_HOST" "ls /etc/systemd/system/*reverb* 2>/dev/null || echo '  Geen reverb systemd files'"

echo ""
echo "  Process tree van PID op poort 8080:"
ssh -i "$SSH_KEY" "$SSH_HOST" "PID=\$(sudo lsof -ti:8080 2>/dev/null | head -1); if [ -n \"\$PID\" ]; then ps -p \$PID -o pid,ppid,user,cmd --no-headers; echo '  Parent:'; ps -p \$(ps -p \$PID -o ppid --no-headers | tr -d ' ') -o pid,ppid,user,cmd --no-headers 2>/dev/null; else echo '  Geen process op 8080'; fi"

echo ""
echo "  Crontab reverb entries:"
ssh -i "$SSH_KEY" "$SSH_HOST" "crontab -l 2>/dev/null | grep -i reverb || echo '  Geen reverb in crontab'"

# ── Fix: Reverb draait al, onze config is overbodig ──
step "Fix — gebruik bestaande Reverb"

echo "  Test of Reverb al correct werkt op 8080..."
REVERB_RESPONSE=$(ssh -i "$SSH_KEY" "$SSH_HOST" "curl -sf -o /dev/null -w '%{http_code}' http://127.0.0.1:8080 2>/dev/null || echo 'fail'")
echo "  HTTP response van 127.0.0.1:8080: $REVERB_RESPONSE"

if [ "$REVERB_RESPONSE" != "fail" ] && [ "$REVERB_RESPONSE" != "000" ]; then
    ok "Reverb draait al en luistert op 8080!"
    echo ""
    echo "  Onze dubbele supervisor config verwijderen..."
    ssh -i "$SSH_KEY" "$SSH_HOST" "
        # Onze config stopt proberen te starten (voorkomt spawn errors)
        sudo supervisorctl stop gymies-reverb 2>/dev/null
        sudo rm -f /etc/supervisor/conf.d/gymies-reverb.conf
        sudo supervisorctl reread 2>/dev/null
        sudo supervisorctl update 2>/dev/null
        echo '  gymies-reverb.conf verwijderd'
    "
    ok "Dubbele Supervisor config opgeruimd — bestaande Reverb blijft draaien"
else
    echo "  Reverb reageert niet — er is iets anders mis"
fi

echo ""
echo -e "${GREEN}Klaar.${NC}"
