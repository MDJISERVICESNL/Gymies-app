<?php

declare(strict_types=1);

namespace App\Http\Traits;

use Illuminate\Support\Facades\Schema;

/**
 * Cache Schema::hasColumn() en Schema::hasTable() resultaten per request.
 *
 * Voorkomt dat elke API-call 10-20x information_schema raakt.
 * Cache leeft alleen voor de duur van het request (static property).
 *
 * Gebruik: use GymiesSchemaCacheTrait; → $this->columnExists('gymies_bookings', 'payment_method')
 */
trait GymiesSchemaCacheTrait
{
    /** @var array<string, bool> */
    private static array $tableCache = [];

    /** @var array<string, bool> */
    private static array $columnCache = [];

    protected function tableExists(string $table): bool
    {
        if (isset(self::$tableCache[$table])) {
            return self::$tableCache[$table];
        }
        return self::$tableCache[$table] = Schema::hasTable($table);
    }

    protected function columnExists(string $table, string $column): bool
    {
        $key = "{$table}.{$column}";
        if (isset(self::$columnCache[$key])) {
            return self::$columnCache[$key];
        }
        // Tabel moet bestaan, anders is het antwoord altijd false
        if (!$this->tableExists($table)) {
            return self::$columnCache[$key] = false;
        }
        return self::$columnCache[$key] = Schema::hasColumn($table, $column);
    }

    /**
     * Laad alle kolommen van een tabel in één keer in de cache.
     * Nuttig aan het begin van methods die veel kolom-checks doen.
     */
    protected function preloadColumns(string $table): void
    {
        if (!$this->tableExists($table)) {
            return;
        }
        $columns = Schema::getColumnListing($table);
        foreach ($columns as $col) {
            self::$columnCache["{$table}.{$col}"] = true;
        }
    }

    /**
     * Reset cache (alleen nodig in tests of na schema-wijzigingen in runtime).
     */
    public static function resetSchemaCache(): void
    {
        self::$tableCache = [];
        self::$columnCache = [];
    }
}
