#!/usr/bin/env php
<?php
/**
 * Voer uit op de server IN de Laravel-root:
 *   cd /var/www/mdjiservices.nl/laravel && php /tmp/run_werkbak_migration.php
 * Of kopieer dit bestand naar de Laravel-root en run: php run_werkbak_migration.php
 */
$laravelRoot = getenv('LARAVEL_ROOT');
if (!$laravelRoot) {
    if (is_file(getcwd() . '/vendor/autoload.php')) {
        $laravelRoot = getcwd();
    } elseif (is_dir(__DIR__ . '/../vendor')) {
        $laravelRoot = realpath(__DIR__ . '/..');
    } else {
        $laravelRoot = '/var/www/mdjiservices.nl/laravel';
    }
}
if (!is_file($laravelRoot . '/vendor/autoload.php')) {
    fwrite(STDERR, "Laravel root niet gevonden. Zet LARAVEL_ROOT of run vanuit Laravel-root.\n");
    exit(1);
}

require $laravelRoot . '/vendor/autoload.php';
$app = require_once $laravelRoot . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$statements = [
    "SET NAMES utf8mb4",
    "CREATE TABLE IF NOT EXISTS TrainMaat_admin_saved_views (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NULL DEFAULT NULL,
  name VARCHAR(120) NOT NULL,
  entity_type VARCHAR(32) NOT NULL,
  filters JSON NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY TrainMaat_admin_saved_views_user_entity (user_id, entity_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
    "CREATE TABLE IF NOT EXISTS TrainMaat_admin_note_templates (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(120) NOT NULL,
  body TEXT NOT NULL,
  category VARCHAR(32) NOT NULL DEFAULT 'general',
  sort_order SMALLINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY TrainMaat_admin_note_templates_category (category),
  UNIQUE KEY TrainMaat_admin_note_templates_name_category (name, category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci",
];

$done = 0;
foreach ($statements as $stmt) {
    try {
        Illuminate\Support\Facades\DB::unprepared($stmt);
        $done++;
    } catch (Throwable $e) {
        fwrite(STDERR, "Waarschuwing: " . $e->getMessage() . "\n");
    }
}

// INSERT per rij zodat puntkomma's in body geen probleem zijn
$rows = [
    ['KYC check pending', 'KYC-check loopt. Klant is geïnformeerd.', 'ticket', 10],
    ['Client contacted', 'Klant is gecontacteerd; wacht op reactie.', 'ticket', 20],
    ['Refund approved', 'Terugbetaling goedgekeurd. Verwerkt binnen 5 werkdagen.', 'ticket', 30],
    ['Escalated to specialist', 'Doorgestuurd naar specialist voor verdere afhandeling.', 'ticket', 40],
    ['Booking incident – no-show', 'No-show geregistreerd. Trainer heeft klant proberen te bereiken.', 'booking', 10],
    ['Booking incident – dispute', 'Geschil gemeld. Beide partijen gehoord; follow-up volgt.', 'booking', 20],
    ['Payout blocked – verification', 'Uitbetaling gepauzeerd tot verificatie is afgerond.', 'general', 10],
    ['Fraude review in progress', 'Fraudecheck loopt. Geen actie tot conclusie.', 'general', 20],
];
foreach ($rows as $r) {
    try {
        Illuminate\Support\Facades\DB::insert(
            'INSERT IGNORE INTO TrainMaat_admin_note_templates (name, body, category, sort_order) VALUES (?, ?, ?, ?)',
            [$r[0], $r[1], $r[2], $r[3]]
        );
        $done++;
    } catch (Throwable $e) {
        // IGNORE: duplicate name+category is ok
    }
}

echo "Klaar. $done statement(s) uitgevoerd.\n";
