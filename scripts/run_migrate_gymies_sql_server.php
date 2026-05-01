#!/usr/bin/env php
<?php
/**
 * Voer uit op de SERVER (na SCP). Leest .env uit de huidige directory en voert het gegeven SQL-bestand uit.
 * Gebruik: cd $LARAVEL && php /tmp/run_migrate_gymies_sql_server.php /tmp/create_gymies_tables.sql
 */
declare(strict_types=1);

$sqlFile = $argv[1] ?? '';
if ($sqlFile === '' || !is_file($sqlFile)) {
    fwrite(STDERR, "Usage: php run_migrate_gymies_sql_server.php <path-to.sql>\n");
    exit(1);
}

function envMap(string $path): array
{
    $map = [];
    if (!is_file($path)) {
        return $map;
    }
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) {
            continue;
        }
        [$k, $v] = explode('=', $line, 2);
        $map[trim($k)] = trim($v, "\"' \n\r\t");
    }
    return $map;
}

$envPath = getcwd() . '/.env';
$env = envMap($envPath);
$host = $env['DB_HOST'] ?? '127.0.0.1';
$port = (int) ($env['DB_PORT'] ?? 3306);
$db = $env['DB_DATABASE'] ?? '';
$user = $env['DB_USERNAME'] ?? '';
$pass = $env['DB_PASSWORD'] ?? '';

if ($db === '' || $user === '') {
    fwrite(STDERR, "DB_DATABASE of DB_USERNAME ontbreekt in .env. Run vanuit Laravel-root.\n");
    exit(1);
}

$dsn = "mysql:host={$host};port={$port};dbname={$db};charset=utf8mb4";
try {
    $pdo = new PDO($dsn, $user, $pass, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::MYSQL_ATTR_USE_BUFFERED_QUERY => true,
    ]);
} catch (Throwable $e) {
    fwrite(STDERR, "DB connect failed: " . $e->getMessage() . "\n");
    exit(1);
}
fwrite(STDOUT, "Using database: {$db}\n");

$sql = file_get_contents($sqlFile);
if ($sql === false || $sql === '') {
    fwrite(STDERR, "SQL file empty or unreadable.\n");
    exit(1);
}

$pdo->exec('SET NAMES utf8mb4');
$pdo->exec('SET FOREIGN_KEY_CHECKS = 0');

// Split op ; maar niet: binnen '…', en niet binnen -- … tot einde regel (anders breekt `demo; x` in comments)
$statements = [];
$current = '';
$inSingle = false;
$inLineComment = false;
$len = strlen($sql);
for ($i = 0; $i < $len; $i++) {
    $c = $sql[$i];
    if ($inLineComment) {
        $current .= $c;
        if ($c === "\n") {
            $inLineComment = false;
        }
        continue;
    }
    if ($c === "'" && ($i === 0 || $sql[$i - 1] !== '\\')) {
        $inSingle = !$inSingle;
        $current .= $c;
        continue;
    }
    if (!$inSingle && $c === '-' && ($sql[$i + 1] ?? '') === '-') {
        $current .= '--';
        $i++;
        $inLineComment = true;
        continue;
    }
    if ($c === ';' && !$inSingle) {
        $stmt = trim($current);
        $stmt = preg_replace('/^(\s*|--[^\n]*\n)+/s', '', $stmt);
        if ($stmt !== '') {
            $statements[] = $stmt;
        }
        $current = '';
        continue;
    }
    $current .= $c;
}
$stmt = trim($current);
$stmt = preg_replace('/^(\s*|--[^\n]*\n)+/s', '', $stmt);
if ($stmt !== '') {
    $statements[] = $stmt;
}

$toRun = array_filter($statements, static function (string $s): bool {
    $t = trim($s);
    return $t !== '' && !str_starts_with($t, '--') && !str_starts_with($t, '/*');
});
fwrite(STDOUT, "Parsed " . count($toRun) . " statements from file (total chunks: " . count($statements) . ").\n");

$done = 0;
$errors = [];
foreach ($toRun as $stmt) {
    try {
        // prepare + execute + closeCursor voorkomt MySQL error 2014 bij INSERT…SELECT e.d.
        // (exec() laat soms een actieve resultset staan op mysqlnd).
        $ps = $pdo->prepare($stmt);
        $ps->execute();
        $ps->closeCursor();
        unset($ps);
        $done++;
    } catch (Throwable $e) {
        $preview = strlen($stmt) > 80 ? substr($stmt, 0, 77) . '...' : $stmt;
        $errors[] = sprintf('stmt: %s | %s', $e->getMessage(), $preview);
    }
}

// Schone verbinding vóór vervolg-queries
$ping = $pdo->query('SELECT 1 AS _x');
if ($ping instanceof PDOStatement) {
    $ping->fetchAll(PDO::FETCH_ASSOC);
    $ping->closeCursor();
}

$pdo->exec('SET FOREIGN_KEY_CHECKS = 1');

fwrite(STDOUT, "Gymies SQL: $done statements executed.\n");
if (!empty($errors)) {
    fwrite(STDERR, "Failed statements:\n");
    foreach ($errors as $err) {
        fwrite(STDERR, "  " . $err . "\n");
    }
}

// Zorg dat gymies_users alle kolommen heeft (profiel, trainer, gym) – uit create_gymies_tables_if_not_exists.sql
$stUsers = $pdo->query("SHOW TABLES LIKE 'gymies_users'");
$hasUsers = $stUsers ? $stUsers->fetch() : false;
if ($stUsers) {
    $stUsers->closeCursor();
}
if (!$hasUsers) {
    $stUsers2 = $pdo->query("SHOW TABLES LIKE 'gymies_users'");
    $hasUsers = $stUsers2 ? $stUsers2->fetch() : false;
    if ($stUsers2) {
        $stUsers2->closeCursor();
    }
}
if ($hasUsers) {
    $userColumns = [
        'display_name' => 'VARCHAR(255) DEFAULT NULL',
        'first_name' => 'VARCHAR(255) DEFAULT NULL',
        'last_name' => 'VARCHAR(255) DEFAULT NULL',
        'phone' => 'VARCHAR(32) DEFAULT NULL',
        'email_verified_at' => 'TIMESTAMP NULL DEFAULT NULL',
        'phone_verified_at' => 'TIMESTAMP NULL DEFAULT NULL',
        'date_of_birth' => 'DATE DEFAULT NULL',
        'preferred_language' => "VARCHAR(10) DEFAULT 'nl'",
        'avatar_url' => 'VARCHAR(512) DEFAULT NULL',
        'is_suspended' => 'TINYINT(1) NOT NULL DEFAULT 0',
        'suspended_reason' => 'VARCHAR(255) DEFAULT NULL',
        'suspended_at' => 'TIMESTAMP NULL DEFAULT NULL',
        'trainer_approved_at' => 'TIMESTAMP NULL DEFAULT NULL',
        'business_name' => 'VARCHAR(255) DEFAULT NULL',
        'vat_number' => 'VARCHAR(64) DEFAULT NULL',
        'coc_number' => 'VARCHAR(64) DEFAULT NULL',
        'parent_guardian_name' => 'VARCHAR(255) DEFAULT NULL',
        'parent_guardian_email' => 'VARCHAR(255) DEFAULT NULL',
        'parent_consent_at' => 'TIMESTAMP NULL DEFAULT NULL',
        'accessibility_needs' => 'TEXT DEFAULT NULL',
        'address_line1' => 'VARCHAR(255) DEFAULT NULL',
        'postcode' => 'VARCHAR(20) DEFAULT NULL',
        'city' => 'VARCHAR(255) DEFAULT NULL',
        'country' => "VARCHAR(2) DEFAULT 'NL'",
        'latitude' => 'DECIMAL(10,7) DEFAULT NULL',
        'longitude' => 'DECIMAL(10,7) DEFAULT NULL',
        'data_export_requested_at' => 'TIMESTAMP NULL DEFAULT NULL',
        'data_export_completed_at' => 'TIMESTAMP NULL DEFAULT NULL',
    ];
    $added = 0;
    foreach ($userColumns as $col => $def) {
        try {
            $pdo->exec("ALTER TABLE gymies_users ADD COLUMN {$col} {$def}");
            $added++;
        } catch (Throwable $e) {
            if (strpos($e->getMessage(), 'Duplicate column') === false) {
                fwrite(STDERR, "ALTER gymies_users.{$col}: " . $e->getMessage() . "\n");
            }
        }
    }
    if ($added > 0) {
        fwrite(STDOUT, "gymies_users: {$added} column(s) added.\n");
    }
}

// Check: bestaat gymies_users (of gymies_users bij lower_case_table_names)?
$stHas = $pdo->query("SHOW TABLES LIKE 'gymies_users'");
$has = $stHas ? $stHas->fetch() : false;
if ($stHas) {
    $stHas->closeCursor();
}
if (!$has) {
    $stHas2 = $pdo->query("SHOW TABLES LIKE 'gymies_users'");
    $has = $stHas2 ? $stHas2->fetch() : false;
    if ($stHas2) {
        $stHas2->closeCursor();
    }
}
if (!$has) {
    fwrite(STDERR, "WARNING: Table gymies_users still missing in {$db}. Creating full users table...\n");
    $minimal = "CREATE TABLE IF NOT EXISTS gymies_users (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            email VARCHAR(255) NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            role ENUM('klant', 'trainer') NOT NULL DEFAULT 'klant',
            display_name VARCHAR(255) DEFAULT NULL,
            first_name VARCHAR(255) DEFAULT NULL,
            last_name VARCHAR(255) DEFAULT NULL,
            phone VARCHAR(32) DEFAULT NULL,
            email_verified_at TIMESTAMP NULL DEFAULT NULL,
            phone_verified_at TIMESTAMP NULL DEFAULT NULL,
            date_of_birth DATE DEFAULT NULL,
            preferred_language VARCHAR(10) DEFAULT 'nl',
            avatar_url VARCHAR(512) DEFAULT NULL,
            is_admin TINYINT(1) NOT NULL DEFAULT 0,
            is_suspended TINYINT(1) NOT NULL DEFAULT 0,
            suspended_reason VARCHAR(255) DEFAULT NULL,
            suspended_at TIMESTAMP NULL DEFAULT NULL,
            trainer_approved_at TIMESTAMP NULL DEFAULT NULL,
            business_name VARCHAR(255) DEFAULT NULL,
            vat_number VARCHAR(64) DEFAULT NULL,
            coc_number VARCHAR(64) DEFAULT NULL,
            parent_guardian_name VARCHAR(255) DEFAULT NULL,
            parent_guardian_email VARCHAR(255) DEFAULT NULL,
            parent_consent_at TIMESTAMP NULL DEFAULT NULL,
            accessibility_needs TEXT DEFAULT NULL,
            address_line1 VARCHAR(255) DEFAULT NULL,
            postcode VARCHAR(20) DEFAULT NULL,
            city VARCHAR(255) DEFAULT NULL,
            country VARCHAR(2) DEFAULT 'NL',
            latitude DECIMAL(10,7) DEFAULT NULL,
            longitude DECIMAL(10,7) DEFAULT NULL,
            data_export_requested_at TIMESTAMP NULL DEFAULT NULL,
            data_export_completed_at TIMESTAMP NULL DEFAULT NULL,
            created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY gymies_users_email_unique (email),
            KEY gymies_users_role (role),
            KEY gymies_users_postcode (postcode),
            KEY gymies_users_city (city)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    try {
        $pdo->exec($minimal);
        $pdo->exec("CREATE TABLE IF NOT EXISTS gymies_sessions (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                user_id BIGINT UNSIGNED NOT NULL,
                token VARCHAR(255) NOT NULL,
                expires_at TIMESTAMP NOT NULL,
                created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY gymies_sessions_token_unique (token),
                KEY gymies_sessions_user (user_id),
                KEY gymies_sessions_expires (expires_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
        fwrite(STDOUT, "OK: Minimal gymies_users + gymies_sessions created. Login should work now.\n");
    } catch (Throwable $e) {
        fwrite(STDERR, "Minimal CREATE failed: " . $e->getMessage() . "\n");
        exit(1);
    }
    exit(0);
}
fwrite(STDOUT, "OK: gymies_users exists.\n");

// Fallback: als gymies_bookings ontbreekt, aanmaken (bijv. door fout in statement-split of oud SQL-bestand)
$stBk = $pdo->query("SHOW TABLES LIKE 'gymies_bookings'");
$hasBookings = $stBk ? $stBk->fetch() : false;
if ($stBk) {
    $stBk->closeCursor();
}
if (!$hasBookings) {
    $stBk2 = $pdo->query("SHOW TABLES LIKE 'gymies_bookings'");
    $hasBookings = $stBk2 ? $stBk2->fetch() : false;
    if ($stBk2) {
        $stBk2->closeCursor();
    }
}
if (!$hasBookings) {
    fwrite(STDOUT, "gymies_bookings ontbreekt – aanmaken als fallback...\n");
    $pdo->exec('SET FOREIGN_KEY_CHECKS = 0');
    // Eerst eventueel ontbrekende tabellen waar bookings naar refereert (zonder FKs in fallback als ze ontbreken)
    $stPkg = $pdo->query("SHOW TABLES LIKE 'gymies_packages'");
    $hasPackages = $stPkg ? $stPkg->fetch() : false;
    if ($stPkg) {
        $stPkg->closeCursor();
    }
    if (!$hasPackages) {
        $pdo->exec("CREATE TABLE IF NOT EXISTS gymies_packages (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            trainer_user_id BIGINT UNSIGNED NOT NULL,
            name VARCHAR(255) NOT NULL,
            lesson_type ENUM('solo', 'duo', 'group') NOT NULL DEFAULT 'solo',
            sessions_count INT UNSIGNED NOT NULL,
            weeks_count INT UNSIGNED NOT NULL DEFAULT 1,
            total_cents INT UNSIGNED NOT NULL,
            valid_days INT UNSIGNED DEFAULT NULL,
            created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY gymies_packages_trainer (trainer_user_id),
            CONSTRAINT gymies_packages_user_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
    }
    $stLoc = $pdo->query("SHOW TABLES LIKE 'gymies_trainer_locations'");
    $hasLocations = $stLoc ? $stLoc->fetch() : false;
    if ($stLoc) {
        $stLoc->closeCursor();
    }
    if (!$hasLocations) {
        $pdo->exec("CREATE TABLE IF NOT EXISTS gymies_trainer_locations (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            trainer_user_id BIGINT UNSIGNED NOT NULL,
            name VARCHAR(255) NOT NULL,
            address_line1 VARCHAR(255) DEFAULT NULL,
            postcode VARCHAR(20) DEFAULT NULL,
            city VARCHAR(255) DEFAULT NULL,
            latitude DECIMAL(10,7) DEFAULT NULL,
            longitude DECIMAL(10,7) DEFAULT NULL,
            location_type ENUM('gym', 'home', 'outdoor', 'online') DEFAULT 'gym',
            is_primary TINYINT(1) NOT NULL DEFAULT 0,
            created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            KEY gymies_trainer_locations_trainer (trainer_user_id),
            CONSTRAINT gymies_trainer_locations_user_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci");
    }
    $createBookings = "CREATE TABLE IF NOT EXISTS gymies_bookings (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        client_user_id BIGINT UNSIGNED NOT NULL,
        trainer_user_id BIGINT UNSIGNED NOT NULL,
        scheduled_at DATETIME NOT NULL,
        duration_minutes INT UNSIGNED NOT NULL DEFAULT 60,
        status ENUM('pending', 'confirmed', 'cancelled', 'completed', 'no_show') NOT NULL DEFAULT 'pending',
        recurrence_parent_booking_id BIGINT UNSIGNED DEFAULT NULL,
        recurrence_interval_weeks TINYINT UNSIGNED DEFAULT NULL,
        recurrence_count INT UNSIGNED DEFAULT NULL,
        amount_cents INT UNSIGNED DEFAULT NULL,
        payment_provider_id VARCHAR(255) DEFAULT NULL,
        paid_at TIMESTAMP NULL DEFAULT NULL,
        split_payment_enabled TINYINT(1) NOT NULL DEFAULT 0,
        split_paid_cents INT UNSIGNED DEFAULT NULL,
        platform_fee_cents INT UNSIGNED DEFAULT NULL,
        trainer_payout_cents INT UNSIGNED DEFAULT NULL,
        auto_confirm_at TIMESTAMP NULL DEFAULT NULL,
        confirmation_expires_at TIMESTAMP NULL DEFAULT NULL,
        reminder_24h_sent_at TIMESTAMP NULL DEFAULT NULL,
        reminder_1h_sent_at TIMESTAMP NULL DEFAULT NULL,
        cancellation_policy_id BIGINT UNSIGNED DEFAULT NULL,
        location_type ENUM('online', 'on_site', 'gym') DEFAULT NULL,
        location_notes TEXT DEFAULT NULL,
        client_notes TEXT DEFAULT NULL,
        trainer_notes TEXT DEFAULT NULL,
        cancelled_at TIMESTAMP NULL DEFAULT NULL,
        cancelled_by_user_id BIGINT UNSIGNED DEFAULT NULL,
        package_id BIGINT UNSIGNED DEFAULT NULL,
        sessions_remaining INT UNSIGNED DEFAULT NULL,
        trainer_location_id BIGINT UNSIGNED DEFAULT NULL,
        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (id),
        KEY gymies_bookings_client (client_user_id),
        KEY gymies_bookings_trainer (trainer_user_id),
        KEY gymies_bookings_scheduled (scheduled_at),
        KEY gymies_bookings_status (status),
        KEY gymies_bookings_package (package_id),
        KEY gymies_bookings_recurrence_parent (recurrence_parent_booking_id),
        CONSTRAINT gymies_bookings_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
        CONSTRAINT gymies_bookings_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
        CONSTRAINT gymies_bookings_cancelled_by_fk FOREIGN KEY (cancelled_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL,
        CONSTRAINT gymies_bookings_recurrence_parent_fk FOREIGN KEY (recurrence_parent_booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL,
        CONSTRAINT gymies_bookings_package_fk FOREIGN KEY (package_id) REFERENCES gymies_packages (id) ON DELETE SET NULL,
        CONSTRAINT gymies_bookings_location_fk FOREIGN KEY (trainer_location_id) REFERENCES gymies_trainer_locations (id) ON DELETE SET NULL
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    try {
        $pdo->exec($createBookings);
        fwrite(STDOUT, "OK: gymies_bookings created.\n");
    } catch (Throwable $e) {
        fwrite(STDERR, "Fallback CREATE gymies_bookings failed: " . $e->getMessage() . "\n");
    }
    $pdo->exec('SET FOREIGN_KEY_CHECKS = 1');
}

exit(0);
