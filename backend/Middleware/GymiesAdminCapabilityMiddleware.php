<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

final class GymiesAdminCapabilityMiddleware
{
    public function handle(Request $request, Closure $next, string $required = 'admin.access'): Response
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        if (!$this->hasAdminAccess((int) $user->id)) {
            return response()->json(['message' => 'Geen admin-toegang.'], 403);
        }

        $caps = $this->userCapabilities((int) $user->id);
        if (!in_array($required, $caps, true) && !in_array('admin.super', $caps, true)) {
            return response()->json(['message' => 'Onvoldoende admin-rechten.'], 403);
        }

        $request->attributes->set('gymies_admin_capabilities', $caps);

        return $next($request);
    }

    private function hasAdminAccess(int $userId): bool
    {
        $user = DB::table('gymies_users')
            ->where('id', $userId)
            ->first(['is_admin']);
        if (!$user) {
            return false;
        }

        return ((int) ($user->is_admin ?? 0)) === 1;
    }

    /**
     * @return list<string>
     */
    private function userCapabilities(int $userId): array
    {
        if (!DB::getSchemaBuilder()->hasTable('gymies_user_admin_roles')
            || !DB::getSchemaBuilder()->hasTable('gymies_admin_roles')
            || !DB::getSchemaBuilder()->hasTable('gymies_admin_role_permissions')
            || !DB::getSchemaBuilder()->hasTable('gymies_admin_permissions')) {
            return ['admin.access', 'admin.super'];
        }

        $rows = DB::table('gymies_user_admin_roles as uar')
            ->join('gymies_admin_roles as r', 'r.id', '=', 'uar.role_id')
            ->join('gymies_admin_role_permissions as rp', 'rp.role_id', '=', 'r.id')
            ->join('gymies_admin_permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('uar.user_id', $userId)
            ->where('uar.status', 'active')
            ->where('r.status', 'active')
            ->pluck('p.permission_key')
            ->map(static fn ($x) => (string) $x)
            ->unique()
            ->values()
            ->all();

        if (empty($rows)) {
            // Geen rollen gekoppeld: is_admin=1 gebruikers krijgen volledige rechten (backwards compatibility)
            return $this->hasAdminAccess($userId) ? ['admin.access', 'admin.super'] : ['admin.access'];
        }

        return $rows;
    }
}

