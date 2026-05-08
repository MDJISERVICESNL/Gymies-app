<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * GymiesSecurityHeadersMiddleware
 * ──────────────────────────────
 * Adds essential security headers to all API responses:
 * - X-Content-Type-Options: nosniff (prevent MIME type sniffing)
 * - X-Frame-Options: DENY (prevent clickjacking)
 * - X-XSS-Protection: 1; mode=block (legacy XSS protection)
 * - Content-Security-Policy: default-src 'none' (strict CSP for API)
 */
class GymiesSecurityHeadersMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        /** @var Response $response */
        $response = $next($request);

        // Prevent MIME type sniffing attacks
        $response->headers->set('X-Content-Type-Options', 'nosniff');

        // Prevent clickjacking attacks
        $response->headers->set('X-Frame-Options', 'DENY');

        // Legacy XSS protection (modern browsers use CSP instead)
        $response->headers->set('X-XSS-Protection', '1; mode=block');

        // Strict Content Security Policy for API endpoints
        // default-src 'none' — API responses are data, not HTML; no inline scripts/styles allowed
        $response->headers->set('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none'");

        // Additional security headers
        $response->headers->set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload');
        $response->headers->set('Referrer-Policy', 'strict-origin-when-cross-origin');
        $response->headers->set('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');

        return $response;
    }
}
