#!/usr/bin/env php
<?php
/**
 * Query storefront (stories, video, instagram) per trainer.
 * Run on server: sudo -u www-data php query_storefront.php
 */
chdir('/var/www/gymies');
$env = [];
foreach (file('.env') ?: [] as $line) {
  $line = trim($line);
  if ($line !== '' && $line[0] !== '#' && strpos($line, '=') !== false) {
    list($k, $v) = explode('=', $line, 2);
    $env[trim($k)] = trim(trim($v), '"\' ');
  }
}
$dsn = 'mysql:host=' . ($env['DB_HOST'] ?? '127.0.0.1') . ';dbname=' . ($env['DB_DATABASE'] ?? '') . ';charset=utf8mb4';
$pdo = new PDO($dsn, $env['DB_USERNAME'] ?? '', $env['DB_PASSWORD'] ?? '');

$has = $pdo->query("SHOW TABLES LIKE 'gymies_trainer_storefront'")->fetch();
if (!$has) {
  echo "Tabel gymies_trainer_storefront bestaat niet.\n";
  exit(0);
}

$r = $pdo->query("
  SELECT s.trainer_user_id, u.email, u.display_name,
         s.success_stories_json, s.video_pitch_url, s.instagram_handle
  FROM gymies_trainer_storefront s
  JOIN gymies_users u ON u.id = s.trainer_user_id
  ORDER BY s.trainer_user_id
")->fetchAll(PDO::FETCH_ASSOC);

echo "Trainers met storefront:\n";
echo str_repeat('-', 85) . "\n";
printf("%-5s %-35s %-20s %-8s %-8s %-12s\n", "ID", "Email", "Naam", "Stories", "Video", "Instagram");
echo str_repeat('-', 85) . "\n";

$full = [];
foreach ($r as $row) {
  $stories = $row['success_stories_json'] ?? '';
  $arr = $stories ? (json_decode($stories, true) ?: []) : [];
  $storiesCnt = count($arr);
  $hasVideo = !empty(trim($row['video_pitch_url'] ?? ''));
  $hasIg = !empty(trim($row['instagram_handle'] ?? ''));
  
  $storiesStr = $storiesCnt > 0 ? $storiesCnt . " items" : "-";
  $videoStr = $hasVideo ? "ja" : "-";
  $igStr = $hasIg ? ($row['instagram_handle'] ?? "ja") : "-";
  
  printf("%-5s %-35s %-20s %-8s %-8s %-12s\n",
    $row['trainer_user_id'],
    substr($row['email'], 0, 34),
    substr($row['display_name'] ?? '-', 0, 19),
    $storiesStr,
    $videoStr,
    substr($igStr, 0, 11)
  );
  
  if ($storiesCnt > 0 && $hasVideo) {
    $full[] = $row['email'] . ' (' . ($row['display_name'] ?? '') . ')';
  }
}

echo "\n=== Volledig uitgewerkt (stories + video): " . count($full) . " trainer(s) ===\n";
foreach ($full as $f) echo "  - $f\n";
