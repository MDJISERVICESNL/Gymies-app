<?php

use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Gymies Routes (API prefix: api/gymies)
|--------------------------------------------------------------------------
| De website (Flutter SPA) staat op / en wordt door Nginx geserveerd (index.html).
| Alleen de API-routes lopen via Laravel.
*/

// Gymies API — geladen via gymies_deploy (fix_gymies_web_routes_force)
require __DIR__ . '/gymies.php';

