#!/usr/bin/env bash
set -euo pipefail

LARAVEL="${LARAVEL:-/var/www/gymies.nl/laravel}"
SRC="${SRC:-$HOME/gymies_release}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run with sudo: sudo bash $0"
  exit 1
fi

echo "Applying Gymies release from: $SRC"
echo "Laravel path: $LARAVEL"

mkdir -p "$LARAVEL/app/Http/Controllers/Gymies" "$LARAVEL/app/Http/Middleware"

cp -f "$SRC/backend/Controllers/"*.php "$LARAVEL/app/Http/Controllers/Gymies/"
cp -f "$SRC/backend/Middleware/"*.php "$LARAVEL/app/Http/Middleware/"

cp -f "$LARAVEL/routes/web.php" "$LARAVEL/routes/web.php.bak_$(date +%Y%m%d_%H%M%S)"

php <<'PHP'
<?php
declare(strict_types=1);

$laravel = getenv('LARAVEL') ?: '/var/www/gymies.nl/laravel';
$webPath = $laravel . '/routes/web.php';
$snippetPath = getenv('SRC') ? (getenv('SRC') . '/backend/routes_gymies_snippet.php') : (getenv('HOME') ?: '/home/Gymiesagent') . '/gymies_release/backend/routes_gymies_snippet.php';

$web = file_get_contents($webPath) ?: '';
$snippet = file_get_contents($snippetPath) ?: '';

if ($snippet === '') {
    fwrite(STDERR, "Snippet missing: $snippetPath\n");
    exit(1);
}

// Remove PHP header/comments from snippet start.
$startPos = strpos($snippet, "Route::prefix('api/gymies')");
if ($startPos === false) {
    fwrite(STDERR, "Snippet has no api/gymies block.\n");
    exit(1);
}
$snippetBlock = trim(substr($snippet, $startPos));

if (strpos($web, "Route::prefix('api/gymies')") !== false) {
    $web = preg_replace("/Route::prefix\\('api\\/gymies'\\).*?name\\('gymies\\.catchall'\\);/s", '', $web) ?? $web;
}

$web = rtrim($web) . "\n\n" . $snippetBlock . "\n";
file_put_contents($webPath, $web);
echo "Routes updated.\n";
PHP

php <<'PHP'
<?php
declare(strict_types=1);

$laravel = getenv('LARAVEL') ?: '/var/www/gymies.nl/laravel';
$bootstrapPath = $laravel . '/bootstrap/app.php';
if (!is_file($bootstrapPath)) {
    fwrite(STDERR, "bootstrap/app.php not found.\n");
    exit(1);
}
$content = file_get_contents($bootstrapPath) ?: '';

$aliases = [
    "gymies.rate_limit" => "'gymies.rate_limit' => \\App\\Http\\Middleware\\GymiesRateLimitMiddleware::class,",
    "gymies.rate.limit" => "'gymies.rate.limit' => \\App\\Http\\Middleware\\GymiesRateLimitMiddleware::class,",
    "gymies.idempotency" => "'gymies.idempotency' => \\App\\Http\\Middleware\\GymiesIdempotencyMiddleware::class,",
    "gymies.error_log" => "'gymies.error_log' => \\App\\Http\\Middleware\\GymiesApiErrorLoggingMiddleware::class,",
    "gymies.admin.capability" => "'gymies.admin.capability' => \\App\\Http\\Middleware\\GymiesAdminCapabilityMiddleware::class,",
    "gymies.admin.ip" => "'gymies.admin.ip' => \\App\\Http\\Middleware\\GymiesAdminIpAllowlistMiddleware::class,",
];

if (!str_contains($content, '$middleware->alias([')) {
    fwrite(STDERR, "Alias block not found in bootstrap/app.php\n");
    exit(1);
}

foreach ($aliases as $key => $line) {
    if (str_contains($content, $key)) {
        continue;
    }
    // Hard insert direct after alias block start, onafhankelijk van spacing/format.
    $content = preg_replace(
        '/(\\$middleware->alias\\(\\[\\s*\\n)/',
        "$1            {$line}\n",
        $content,
        1
    ) ?? $content;
}

file_put_contents($bootstrapPath, $content);
echo "Middleware aliases ensured.\n";
PHP

php <<'PHP'
<?php
declare(strict_types=1);

function envMap(string $path): array {
    $map = [];
    if (!is_file($path)) return $map;
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) continue;
        [$k, $v] = explode('=', $line, 2);
        $map[$k] = trim($v, "\"' ");
    }
    return $map;
}

$laravel = getenv('LARAVEL') ?: '/var/www/gymies.nl/laravel';
$env = envMap($laravel . '/.env');
$host = $env['DB_HOST'] ?? '127.0.0.1';
$port = (int) ($env['DB_PORT'] ?? 3306);
$db = $env['DB_DATABASE'] ?? '';
$user = $env['DB_USERNAME'] ?? '';
$pass = $env['DB_PASSWORD'] ?? '';

if ($db === '' || $user === '') {
    fwrite(STDOUT, "DB vars missing, skipped DB patch.\n");
    exit(0);
}

$pdo = new PDO(
    "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4",
    $user,
    $pass,
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
);

$sql = [
    "ALTER TABLE gymies_users ADD COLUMN is_admin TINYINT(1) NOT NULL DEFAULT 0",
    "ALTER TABLE gymies_sessions ADD COLUMN revoked_at TIMESTAMP NULL DEFAULT NULL",
    "ALTER TABLE gymies_sessions ADD COLUMN ip_address VARCHAR(45) NULL",
    "ALTER TABLE gymies_sessions ADD COLUMN user_agent VARCHAR(255) NULL",
    "CREATE TABLE IF NOT EXISTS gymies_idempotency_keys (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      user_id BIGINT UNSIGNED DEFAULT NULL,
      endpoint VARCHAR(255) NOT NULL,
      idempotency_key VARCHAR(255) NOT NULL,
      request_hash VARCHAR(128) NOT NULL,
      status_code INT NOT NULL,
      response_json JSON DEFAULT NULL,
      created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      expires_at TIMESTAMP NULL DEFAULT NULL,
      PRIMARY KEY (id),
      UNIQUE KEY gymies_idempotency_unique (user_id, endpoint, idempotency_key),
      KEY gymies_idempotency_expires (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
    "CREATE TABLE IF NOT EXISTS gymies_notification_user_settings (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      user_id BIGINT UNSIGNED NOT NULL,
      quiet_hours_enabled TINYINT(1) NOT NULL DEFAULT 0,
      quiet_hours_start VARCHAR(5) NOT NULL DEFAULT '22:00',
      quiet_hours_end VARCHAR(5) NOT NULL DEFAULT '07:00',
      updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY gymies_notification_user_settings_user_unique (user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
    "CREATE TABLE IF NOT EXISTS gymies_admin_roles (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      role_key VARCHAR(120) NOT NULL,
      role_name VARCHAR(255) NOT NULL,
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY gymies_admin_roles_role_key_unique (role_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
    "CREATE TABLE IF NOT EXISTS gymies_admin_permissions (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      permission_key VARCHAR(160) NOT NULL,
      permission_name VARCHAR(255) NOT NULL,
      created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY gymies_admin_permissions_permission_key_unique (permission_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
    "CREATE TABLE IF NOT EXISTS gymies_admin_role_permissions (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      role_id BIGINT UNSIGNED NOT NULL,
      permission_id BIGINT UNSIGNED NOT NULL,
      created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY gymies_admin_role_permissions_role_perm_unique (role_id, permission_id),
      KEY gymies_admin_role_permissions_role_idx (role_id),
      KEY gymies_admin_role_permissions_perm_idx (permission_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
    "CREATE TABLE IF NOT EXISTS gymies_user_admin_roles (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      user_id BIGINT UNSIGNED NOT NULL,
      role_id BIGINT UNSIGNED NOT NULL,
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      assigned_by_user_id BIGINT UNSIGNED DEFAULT NULL,
      created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY gymies_user_admin_roles_user_role_unique (user_id, role_id),
      KEY gymies_user_admin_roles_user_idx (user_id),
      KEY gymies_user_admin_roles_role_idx (role_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
    "CREATE TABLE IF NOT EXISTS gymies_support_tickets (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      user_id BIGINT UNSIGNED NOT NULL,
      subject VARCHAR(255) NOT NULL,
      category VARCHAR(80) NOT NULL DEFAULT 'general',
      priority VARCHAR(20) NOT NULL DEFAULT 'medium',
      status VARCHAR(40) NOT NULL DEFAULT 'new',
      assigned_to_user_id BIGINT UNSIGNED DEFAULT NULL,
      created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      resolved_at TIMESTAMP NULL DEFAULT NULL,
      PRIMARY KEY (id),
      KEY gymies_support_tickets_user_idx (user_id),
      KEY gymies_support_tickets_status_idx (status),
      KEY gymies_support_tickets_priority_idx (priority)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
    "CREATE TABLE IF NOT EXISTS gymies_support_ticket_messages (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      ticket_id BIGINT UNSIGNED NOT NULL,
      author_user_id BIGINT UNSIGNED NOT NULL,
      message TEXT NOT NULL,
      is_internal TINYINT(1) NOT NULL DEFAULT 1,
      created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY gymies_support_ticket_messages_ticket_idx (ticket_id),
      KEY gymies_support_ticket_messages_author_idx (author_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
    "CREATE TABLE IF NOT EXISTS gymies_admin_ip_allowlist (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      ip_pattern VARCHAR(64) NOT NULL,
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      created_by_user_id BIGINT UNSIGNED DEFAULT NULL,
      created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY gymies_admin_ip_allowlist_status_idx (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
    "CREATE TABLE IF NOT EXISTS gymies_payment_transactions (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      booking_id BIGINT UNSIGNED DEFAULT NULL,
      user_id BIGINT UNSIGNED DEFAULT NULL,
      counterparty_user_id BIGINT UNSIGNED DEFAULT NULL,
      provider VARCHAR(64) NOT NULL DEFAULT 'unknown',
      provider_transaction_id VARCHAR(255) DEFAULT NULL,
      amount_cents INT NOT NULL DEFAULT 0,
      status VARCHAR(40) NOT NULL DEFAULT 'pending',
      payment_method VARCHAR(64) DEFAULT NULL,
      paid_at TIMESTAMP NULL DEFAULT NULL,
      created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY gymies_payment_transactions_booking_idx (booking_id),
      KEY gymies_payment_transactions_status_idx (status),
      KEY gymies_payment_transactions_created_idx (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
    "CREATE TABLE IF NOT EXISTS gymies_admin_alerts (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      alert_type VARCHAR(80) NOT NULL,
      severity VARCHAR(20) NOT NULL DEFAULT 'low',
      title VARCHAR(255) NOT NULL,
      message TEXT NOT NULL,
      entity_type VARCHAR(80) DEFAULT NULL,
      entity_id BIGINT UNSIGNED DEFAULT NULL,
      status VARCHAR(20) NOT NULL DEFAULT 'open',
      created_by_user_id BIGINT UNSIGNED DEFAULT NULL,
      acknowledged_by_user_id BIGINT UNSIGNED DEFAULT NULL,
      acknowledged_at TIMESTAMP NULL DEFAULT NULL,
      created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      KEY gymies_admin_alerts_status_idx (status),
      KEY gymies_admin_alerts_type_idx (alert_type)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
];

foreach ($sql as $stmt) {
    try {
        $pdo->exec($stmt);
    } catch (Throwable $e) {
        // Idempotent apply: ignore already exists/duplicate.
    }
}

$seedPermissions = [
    ['admin.access', 'Admin toegang'],
    ['admin.super', 'Super admin'],
    ['admin.users.view', 'Users bekijken'],
    ['admin.users.manage', 'Users beheren'],
    ['admin.payments.view', 'Payments bekijken'],
    ['admin.payouts.view', 'Payouts bekijken'],
    ['admin.payouts.manage', 'Payouts beheren'],
    ['admin.tickets.view', 'Tickets bekijken'],
    ['admin.tickets.manage', 'Tickets beheren'],
    ['admin.bookings.view', 'Bookings bekijken'],
    ['admin.bookings.manage', 'Bookings beheren'],
    ['admin.security.view', 'Security bekijken'],
    ['admin.security.manage', 'Security beheren'],
    ['admin.audit.view', 'Audit bekijken'],
    ['admin.organisations.view', 'Organisaties bekijken'],
    ['admin.organisations.manage', 'Organisaties beheren'],
];
foreach ($seedPermissions as [$key, $name]) {
    try {
        $stmt = $pdo->prepare("INSERT INTO gymies_admin_permissions (permission_key, permission_name, created_at, updated_at) VALUES (?, ?, NOW(), NOW()) ON DUPLICATE KEY UPDATE permission_name = VALUES(permission_name), updated_at = NOW()");
        $stmt->execute([$key, $name]);
    } catch (Throwable $e) {}
}
try {
    $pdo->exec("INSERT INTO gymies_admin_roles (role_key, role_name, status, created_at, updated_at) VALUES ('super_admin', 'Super Admin', 'active', NOW(), NOW()) ON DUPLICATE KEY UPDATE role_name = VALUES(role_name), status = VALUES(status), updated_at = NOW()");
} catch (Throwable $e) {}
try {
    $roleId = (int) ($pdo->query("SELECT id FROM gymies_admin_roles WHERE role_key='super_admin' LIMIT 1")->fetchColumn() ?: 0);
    if ($roleId > 0) {
        $permIds = $pdo->query("SELECT id FROM gymies_admin_permissions")->fetchAll(PDO::FETCH_COLUMN);
        $stmt = $pdo->prepare("INSERT IGNORE INTO gymies_admin_role_permissions (role_id, permission_id, created_at) VALUES (?, ?, NOW())");
        foreach ($permIds as $permId) {
            $stmt->execute([$roleId, (int) $permId]);
        }
    }
} catch (Throwable $e) {}
echo "DB patch attempted.\n";
PHP

cd "$LARAVEL"
php artisan route:clear || true
php artisan config:clear || true
php artisan optimize:clear || true
php artisan route:list | grep -E "gymies|trainer/live-counters|notifications/preferences|gdpr|consent|ops/health" || true

chown -R www-data:www-data "$LARAVEL/app/Http/Controllers/Gymies" "$LARAVEL/app/Http/Middleware" "$LARAVEL/routes/web.php" || true

echo "Gymies release applied."
