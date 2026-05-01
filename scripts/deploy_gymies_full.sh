#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Overschrijf via env vars indien nodig.
SSH_KEY="${SSH_KEY:-$HOME/.ssh/Trainmaat}"
SSH_USER="${SSH_USER:-Gymiesagent}"
SSH_HOST="${SSH_HOST:-51.38.113.188}"
REMOTE_LARAVEL="${REMOTE_LARAVEL:-/var/www/gymies.nl/laravel}"
REMOTE_PUBLIC="${REMOTE_PUBLIC:-/var/www/gymies.nl/public_html}"
BASE_HREF="${BASE_HREF:-/gymies/}"

echo "== Gymies one-shot deploy =="
echo "Host: ${SSH_USER}@${SSH_HOST}"
echo "Laravel: ${REMOTE_LARAVEL}"
echo "Public: ${REMOTE_PUBLIC}"
echo ""

if [ ! -f "$SSH_KEY" ]; then
  echo "ERROR: SSH key niet gevonden: $SSH_KEY"
  echo "Tip: export SSH_KEY=\"\$HOME/.ssh/Trainmaat\""
  exit 1
fi

cd "$PROJECT_DIR"

echo "1) Flutter web build..."
flutter build web --release --base-href "$BASE_HREF"

echo "2) Backend files uploaden..."
scp -i "$SSH_KEY" "$PROJECT_DIR/backend/Controllers/GymiesTrainerOpsController.php" \
  "$SSH_USER@$SSH_HOST:$REMOTE_LARAVEL/app/Http/Controllers/Gymies/"
scp -i "$SSH_KEY" "$PROJECT_DIR/backend/routes_gymies_snippet.php" \
  "$SSH_USER@$SSH_HOST:$REMOTE_LARAVEL/"
scp -i "$SSH_KEY" "$PROJECT_DIR/database/alter_gymies_payout_settings.sql" \
  "$SSH_USER@$SSH_HOST:$REMOTE_LARAVEL/database/"

echo "3) Flutter web uploaden..."
rsync -avz --delete -e "ssh -i $SSH_KEY" "$PROJECT_DIR/build/web/" \
  "$SSH_USER@$SSH_HOST:$REMOTE_PUBLIC/gymies/"

echo "4) Server-side checks + DB alter + cache clear..."
ssh -t -i "$SSH_KEY" "$SSH_USER@$SSH_HOST" "cd '$REMOTE_LARAVEL' && php -l app/Http/Controllers/Gymies/GymiesTrainerOpsController.php && php -l routes_gymies_snippet.php && php <<'PHP'
<?php
declare(strict_types=1);

function envMap(string \$path): array {
    \$map = [];
    if (!is_file(\$path)) return \$map;
    foreach (file(\$path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as \$line) {
        \$line = trim(\$line);
        if (\$line === '' || \$line[0] === '#' || strpos(\$line, '=') === false) continue;
        [\$k, \$v] = explode('=', \$line, 2);
        \$map[\$k] = trim(\$v, \"\\\"' \");
    }
    return \$map;
}

\$env = envMap('.env');
\$host = \$env['DB_HOST'] ?? '127.0.0.1';
\$port = (int) (\$env['DB_PORT'] ?? 3306);
\$db = \$env['DB_DATABASE'] ?? '';
\$user = \$env['DB_USERNAME'] ?? '';
\$pass = \$env['DB_PASSWORD'] ?? '';
\$sqlPath = __DIR__ . '/database/alter_gymies_payout_settings.sql';

if (!is_file(\$sqlPath) || \$db === '' || \$user === '') {
    fwrite(STDOUT, \"SKIP DB alter (missing sql file or DB vars).\\n\");
    exit(0);
}

try {
    \$pdo = new PDO(
        \"mysql:host={\$host};port={\$port};dbname={\$db};charset=utf8mb4\",
        \$user,
        \$pass,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    \$sql = file_get_contents(\$sqlPath) ?: '';
    foreach (array_filter(array_map('trim', explode(';', \$sql))) as \$stmt) {
        if (\$stmt === '' || str_starts_with(\$stmt, '--')) continue;
        try {
            \$pdo->exec(\$stmt);
        } catch (Throwable \$e) {
            // Idempotent: duplicate columns/tables mogen falen zonder deploy te stoppen.
        }
    }
    fwrite(STDOUT, \"DB alter attempted.\\n\");
} catch (Throwable \$e) {
    fwrite(STDOUT, \"DB alter skipped: {\$e->getMessage()}\\n\");
}
PHP
php artisan route:clear || true
php artisan config:clear || true
php artisan optimize:clear || true
php artisan route:list | rg 'trainer/(payout|revenue/export)' || true"

echo ""
echo "KLAAR. Vergeet niet op server routes/web.php te syncen met routes_gymies_snippet.php als dat nog niet automatisch gebeurt."
