<?php

declare(strict_types=1);

/**
 * Gymies API Deprecation Configuration
 * ─────────────────────────────────────
 * Beheer welke endpoints deprecated zijn, wanneer ze verdwijnen (sunset),
 * en welke opvolger clients moeten gebruiken.
 *
 * Lifecycle:
 *   1. Voeg endpoint toe aan 'endpoints' met sunset datum (minstens 3 maanden vooruit)
 *   2. Deploy → clients krijgen Deprecation + Sunset headers
 *   3. Monitor via logs welke clients nog deprecated endpoints gebruiken
 *   4. Na sunset datum: verwijder endpoint en route
 *
 * Voorbeeld:
 *   'api/gymies/trainers/search' => [
 *       'sunset'    => '2026-09-01',
 *       'successor' => '/api/gymies/v2/trainers/search',
 *       'message'   => 'Gebruik /api/gymies/v2/trainers/search met nieuwe filter syntax.',
 *   ],
 */
return [
    // ── Logging ────────────────────────────────────────────────────────────
    // Log deprecated endpoint usage (rate-limited: 1x per minuut per IP+path)
    'log_usage' => (bool) env('API_DEPRECATION_LOG', true),

    // ── Deprecated endpoints ───────────────────────────────────────────────
    // Key = URL path (zonder leading slash), waarde = configuratie.
    // Wildcards (*) worden ondersteund via fnmatch().
    //
    // Velden:
    //   sunset    → ISO datum wanneer endpoint verdwijnt (RFC 8594)
    //   successor → pad naar het nieuwe endpoint
    //   message   → waarschuwing voor developers
    'endpoints' => [
        // ── Voorbeelden (activeer wanneer v2 endpoints bestaan) ────────────
        //
        // 'api/gymies/old-endpoint' => [
        //     'sunset'    => '2026-09-01',
        //     'successor' => '/api/gymies/v2/new-endpoint',
        //     'message'   => 'Dit endpoint wordt 1 september 2026 verwijderd.',
        // ],
    ],

    // ── Versioning strategie ───────────────────────────────────────────────
    // Huidige API versie (ook gebruikt in X-API-Version header)
    'current_version' => env('API_VERSION', '1.0'),

    // Minimum ondersteunde versie
    'min_supported_version' => env('API_MIN_VERSION', '1.0'),

    // ── Sunset policy ──────────────────────────────────────────────────────
    // Minimaal aantal dagen voordat een deprecated endpoint verdwijnt
    'min_sunset_days' => 90,
];
