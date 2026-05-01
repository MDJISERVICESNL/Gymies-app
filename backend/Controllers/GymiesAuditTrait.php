<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

trait GymiesAuditTrait
{
    protected function auditLog(
        ?int $userId,
        string $action,
        string $entityType,
        ?int $entityId = null,
        ?array $oldValues = null,
        ?array $newValues = null,
        ?string $ipAddress = null
    ): void {
        if (!Schema::hasTable('gymies_audit_log')) {
            return;
        }
        try {
            // Redact sensitive fields
            $redact = ['password', 'password_hash', 'token', 'authorization', 'iban', 'iban_masked', 'iban_last4', 'mollie_access_token', 'mollie_refresh_token'];
            $clean = function (?array $data) use ($redact): ?array {
                if ($data === null) return null;
                foreach ($redact as $key) {
                    if (array_key_exists($key, $data)) {
                        $data[$key] = '***REDACTED***';
                    }
                }
                return $data;
            };
            DB::table('gymies_audit_log')->insert([
                'user_id' => $userId,
                'action' => substr($action, 0, 64),
                'entity_type' => substr($entityType, 0, 64),
                'entity_id' => $entityId,
                'old_values' => $clean($oldValues) ? json_encode($clean($oldValues)) : null,
                'new_values' => $clean($newValues) ? json_encode($clean($newValues)) : null,
                'ip_address' => $ipAddress ? substr($ipAddress, 0, 45) : null,
                'created_at' => now(),
            ]);
        } catch (\Throwable $e) {
            // Audit logging should never break the main flow
            \Log::warning('Audit log failed: ' . $e->getMessage());
        }
    }
}
