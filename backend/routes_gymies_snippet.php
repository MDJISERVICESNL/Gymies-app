<?php
/**
 * Gymies routes – te laden vanuit Laravel routes/web.php.
 *
 * Optie 1 (aanbevolen): plak de inhoud van backend/routes_gymies_full.php
 * onderaan je bestaande routes/web.php (onder dezelfde prefix api/gymies).
 *
 * Optie 2: voeg hieronder één regel toe in routes/web.php:
 *   require __DIR__ . '/path/to/backend/routes_gymies_snippet.php';
 */
require __DIR__ . '/routes_gymies_full.php';
