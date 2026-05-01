#!/bin/bash
set -e

echo "=== Deploy: NotificationController → gymies_notification_queue ==="
echo ""

# 1. Upload updated controller
echo "[1/3] Controller uploaden..."
scp "$(dirname "$0")/app/Http/Controllers/Gymies/GymiesNotificationController.php" \
    gymies:/var/www/gymies/app/Http/Controllers/Gymies/GymiesNotificationController.php

# 2. Fix ownership + permissions
echo "[2/3] Permissions fixen..."
ssh gymies << 'REMOTE'
chown ubuntu:ubuntu /var/www/gymies/app/Http/Controllers/Gymies/GymiesNotificationController.php
chmod 644 /var/www/gymies/app/Http/Controllers/Gymies/GymiesNotificationController.php
REMOTE

# 3. Clear caches + add read_at column
echo "[3/3] Caches rebuilden + read_at kolom toevoegen..."
ssh gymies << 'REMOTE'
cd /var/www/gymies

php artisan config:clear
php artisan route:clear
php artisan cache:clear
php artisan view:clear

php artisan config:cache
php artisan route:cache

echo ""
echo "=== read_at kolom controleren ==="
php -r "
require '/var/www/gymies/vendor/autoload.php';
\$app = require_once '/var/www/gymies/bootstrap/app.php';
\$kernel = \$app->make(Illuminate\Contracts\Console\Kernel::class);
\$kernel->bootstrap();

if (!Schema::hasTable('gymies_notification_queue')) {
    echo 'FOUT: gymies_notification_queue tabel bestaat niet!' . PHP_EOL;
    exit(1);
}

if (Schema::hasColumn('gymies_notification_queue', 'read_at')) {
    echo '✓ read_at kolom bestaat al.' . PHP_EOL;
} else {
    DB::unprepared('ALTER TABLE gymies_notification_queue ADD COLUMN read_at TIMESTAMP NULL DEFAULT NULL AFTER failed_at');
    echo '✓ read_at kolom toegevoegd.' . PHP_EOL;
}

// Toon voorbeeld notificaties
\$count = DB::table('gymies_notification_queue')->where('channel', 'in_app')->count();
echo PHP_EOL . 'Totaal in-app notificaties: ' . \$count . PHP_EOL;

\$sample = DB::table('gymies_notification_queue')
    ->where('channel', 'in_app')
    ->orderByDesc('created_at')
    ->limit(3)
    ->get(['id', 'user_id', 'event_type', 'payload_json', 'created_at']);

foreach (\$sample as \$n) {
    echo '  ID=' . \$n->id . ' user=' . \$n->user_id . ' type=' . \$n->event_type . ' created=' . \$n->created_at . PHP_EOL;
    \$p = json_decode(\$n->payload_json ?? '{}', true);
    if (!empty(\$p)) {
        echo '    payload keys: ' . implode(', ', array_keys(\$p)) . PHP_EOL;
    }
}
" 2>&1

echo ""
echo "✅ Deploy klaar! NotificationController leest nu uit gymies_notification_queue."
echo "   Meldingen tonen nu echte event_type + payload data."
REMOTE
