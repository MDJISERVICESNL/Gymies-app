<?php

namespace App\Http\Middleware;

use Illuminate\Foundation\Http\Middleware\VerifyCsrfToken as Middleware;

/**
 * Voorbeeld: voeg in je bestaande VerifyCsrfToken.php
 * in de $except array toe: 'api/gymies/*'
 */
class VerifyCsrfToken extends Middleware
{
    protected $except = [
        'api/gymies/*',
    ];
}
