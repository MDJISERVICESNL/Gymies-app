<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // API gebruikt Bearer token, geen CSRF
        $middleware->validateCsrfTokens(except: ['api/*']);
        $middleware->alias([
            'gymies.auth' => \App\Http\Middleware\GymiesAuthMiddleware::class,
            'gymies.rate.limit' => \App\Http\Middleware\GymiesRateLimitMiddleware::class,
            'gymies.error_log' => \App\Http\Middleware\GymiesApiErrorLoggingMiddleware::class,
            'gymies.idempotency' => \App\Http\Middleware\GymiesIdempotencyMiddleware::class,
            'gymies.admin.ip' => \App\Http\Middleware\GymiesAdminIpAllowlistMiddleware::class,
            'gymies.admin.capability' => \App\Http\Middleware\GymiesAdminCapabilityMiddleware::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
