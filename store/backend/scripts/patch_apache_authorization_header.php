<?php
/**
 * Voeg Authorization-header door naar PHP (Apache).
 * Sommige Apache-configs strippen de Authorization header; dit script
 * voegt de benodigde RewriteRule toe aan public/.htaccess.
 *
 * Gebruik: php patch_apache_authorization_header.php [laravel_root]
 */
$base = $argv[1] ?? __DIR__ . '/../..';
$base = rtrim(realpath($base) ?: $base, '/');
$htaccess = $base . '/public/.htaccess';

if (!is_file($htaccess)) {
    echo "Geen public/.htaccess gevonden. Maak handmatig aan of gebruik Apache config.\n";
    exit(1);
}

$content = file_get_contents($htaccess);
$rule = "RewriteCond %{HTTP:Authorization} ^(.+)$\nRewriteRule .* - [E=HTTP_AUTHORIZATION:%1]";

if (strpos($content, 'HTTP_AUTHORIZATION') !== false) {
    echo "Authorization-header regel al aanwezig in .htaccess.\n";
    exit(0);
}

// Voeg toe vóór RewriteRule ^index.php
$insert = "\n# Gymies: Authorization header doorgeven voor Bearer token\n" . $rule . "\n\n";
$content = preg_replace('/(RewriteRule \^index\.php)/', $insert . '$1', $content, 1);

if (strpos($content, 'HTTP_AUTHORIZATION') === false) {
    $content .= "\n# Gymies: Authorization header\n" . $rule . "\n";
}

file_put_contents($htaccess, $content);
echo "Authorization-header toegevoegd aan public/.htaccess.\n";
