#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Health DB Diagnose ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"

echo "═══ 1. DB config in .env ═══"
sudo grep -E "^DB_(CONNECTION|HOST|PORT|DATABASE|USERNAME)" "$LP/.env" 2>/dev/null || echo "  (niet gevonden)"
echo ""

echo "═══ 2. DB connectie test via artisan ═══"
sudo -u www-data php artisan tinker --execute="
try {
    \DB::select('SELECT 1 as ok');
    echo 'DB verbinding: OK' . PHP_EOL;
} catch (\Throwable \$e) {
    echo 'DB FOUT: ' . \$e->getMessage() . PHP_EOL;
}
" 2>&1
echo ""

echo "═══ 3. MySQL/MariaDB service status ═══"
sudo systemctl is-active mysql 2>/dev/null || sudo systemctl is-active mariadb 2>/dev/null || echo "  geen mysql/mariadb service gevonden"
echo ""

echo "═══ 4. Welke DB engine draait? ═══"
which mysql 2>/dev/null && mysql --version 2>/dev/null || echo "  mysql CLI niet gevonden"
which psql 2>/dev/null && psql --version 2>/dev/null || echo "  psql CLI niet gevonden"
sudo ss -tlnp | grep -E "3306|5432" 2>/dev/null || echo "  geen DB poort luisterend"
echo ""

echo "═══ 5. Health controller ping methode ═══"
sudo grep -A 30 "function ping" "$LP/app/Http/Controllers/Gymies/GymiesHealthController.php" | head -35
echo ""

echo "═══ 6. Laravel log (laatste DB errors) ═══"
sudo tail -30 "$LP/storage/logs/laravel.log" 2>/dev/null | grep -iE "database|connection|mysql|pdo|sql" | tail -10 || echo "  (geen DB errors in log)"
echo ""

echo "═══ Done ═══"
REMOTE
