<?php

/**
 * Gymies Logging Configuration
 *
 * Add to Laravel's config/logging.php in the 'channels' array:
 *
 *   'performance' => [
 *       'driver' => 'daily',
 *       'path' => storage_path('logs/performance.log'),
 *       'level' => env('LOG_LEVEL', 'warning'),
 *       'days' => 14,
 *   ],
 *   'queries' => [
 *       'driver' => 'daily',
 *       'path' => storage_path('logs/queries.log'),
 *       'level' => 'debug',
 *       'days' => 7,
 *   ],
 */

return [
    'performance' => [
        'driver' => 'daily',
        'path' => storage_path('logs/performance.log'),
        'level' => env('LOG_LEVEL', 'warning'),
        'days' => 14,
        'permission' => 0664,
    ],
    'queries' => [
        'driver' => 'daily',
        'path' => storage_path('logs/queries.log'),
        'level' => 'debug',
        'days' => 7,
        'permission' => 0664,
    ],
];
