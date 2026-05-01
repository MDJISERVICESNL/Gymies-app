#!/usr/bin/env php
<?php
/**
 * Patch GymiesAdminController: fix "unknown column start_at" in inbox/retention.
 * gymies_availability_slots has start_time/day_of_week, not start_at.
 * Gebruik created_at voor ordering en trainer_user_id i.p.v. user_id.
 *
 * Gebruik: php patch_inbox_start_at.php [pad/naar/laravel]
 */

$base = $argv[1] ?? null;
if ($base) {
    $controllerPath = is_dir($base)
        ? rtrim($base, '/') . '/app/Http/Controllers/Gymies/GymiesAdminController.php'
        : $base;
} else {
    $controllerPath = __DIR__ . '/../../app/Http/Controllers/Gymies/GymiesAdminController.php';
}

if (!file_exists($controllerPath)) {
    fwrite(STDERR, "Controller niet gevonden: $controllerPath\n");
    exit(1);
}

$content = file_get_contents($controllerPath);

if (strpos($content, "orderByDesc('created_at')->value('created_at')") !== false
    || strpos($content, 'inboxRetentionAlertsStartAtFixed') !== false) {
    echo "Patch al toegepast.\n";
    exit(0);
}

// Vervang: orderByDesc('start_at')->value('start_at')
// Door: orderByDesc('created_at')->value('created_at')
// En: where('user_id', ...) -> where('trainer_user_id', ...)
// Patch 1: single-line variant
$old1 = "DB::table('gymies_availability_slots')->where('user_id', \$tid)->orderByDesc('start_at')->value('start_at')";
$new1 = "DB::table('gymies_availability_slots')->where('trainer_user_id', \$tid)->orderByDesc('created_at')->value('created_at')";
$content = str_replace($old1, $new1, $content);

// Patch 2: multi-line variant
$old2 = "DB::table('gymies_availability_slots')\n    ->where('user_id', \$tid)\n    ->orderByDesc('start_at')\n    ->value('start_at')";
$new2 = "DB::table('gymies_availability_slots')\n    ->where('trainer_user_id', \$tid)\n    ->orderByDesc('created_at')\n    ->value('created_at')";
$content = str_replace($old2, $new2, $content);

if (strpos($content, 'start_at') !== false && strpos($content, 'gymies_availability_slots') !== false) {
    fwrite(STDERR, "Waarschuwing: mogelijk nog start_at referenties in availability query.\n");
}

file_put_contents($controllerPath, $content);
echo "GymiesAdminController: start_at/user_id patch toegepast.\n";
