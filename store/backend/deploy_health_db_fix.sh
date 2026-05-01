#!/bin/bash
set -e

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ GYMIES Health DB Fix ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
LP="/var/www/gymies"
cd "$LP"

echo "═══ 1. RDS bereikbaarheid ═══"
DB_HOST=$(sudo grep "^DB_HOST=" "$LP/.env" | cut -d= -f2)
echo "  Host: $DB_HOST"
# TCP connect test
timeout 5 bash -c "echo > /dev/tcp/$DB_HOST/3306" 2>/dev/null && echo "  ✓ Poort 3306 bereikbaar" || echo "  ✗ Poort 3306 NIET bereikbaar"
echo ""

echo "═══ 2. MySQL connect test ═══"
DB_USER=$(sudo grep "^DB_USERNAME=" "$LP/.env" | cut -d= -f2)
DB_PASS=$(sudo grep "^DB_PASSWORD=" "$LP/.env" | cut -d= -f2)
DB_NAME=$(sudo grep "^DB_DATABASE=" "$LP/.env" | cut -d= -f2)
mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 1 AS ok;" 2>&1 && echo "  ✓ MySQL connectie OK" || echo "  ✗ MySQL connectie MISLUKT"
echo ""

echo "═══ 3. PHP PDO test (zoals Laravel het doet) ═══"
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

    try {
        \$result = \Illuminate\Support\Facades\DB::select('SELECT 1 as ok');
        echo '  ✓ DB::select OK: ' . json_encode(\$result) . PHP_EOL;
    } catch (\Throwable \$e) {
        echo '  ✗ DB FOUT: ' . \$e->getMessage() . PHP_EOL;
        echo '  Code: ' . \$e->getCode() . PHP_EOL;
    }
" 2>&1
echo ""

echo "═══ 4. Health controller checkDatabase methode ═══"
sudo grep -A 20 "function checkDatabase" "$LP/app/Http/Controllers/Gymies/GymiesHealthController.php" | head -25
echo ""

echo "═══ 5. Config cache DB settings ═══"
sudo -u www-data php -r "
    require '$LP/vendor/autoload.php';
    \$app = require '$LP/bootstrap/app.php';
    \$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

    echo '  driver:   ' . config('database.default') . PHP_EOL;
    echo '  host:     ' . config('database.connections.mysql.host') . PHP_EOL;
    echo '  port:     ' . config('database.connections.mysql.port') . PHP_EOL;
    echo '  database: ' . config('database.connections.mysql.database') . PHP_EOL;
    echo '  username: ' . config('database.connections.mysql.username') . PHP_EOL;
    echo '  password: ' . (config('database.connections.mysql.password') ? '***set***' : '***LEEG***') . PHP_EOL;
" 2>&1
echo ""

echo "═══ Done ═══"
REMOTE
