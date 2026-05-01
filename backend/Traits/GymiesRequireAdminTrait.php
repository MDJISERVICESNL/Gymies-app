<?php

declare(strict_types=1);

namespace App\Traits;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

trait GymiesRequireAdminTrait
{
    /**
     * Ensure the authenticated user is an admin with the given capability.
     * Returns user on success, JsonResponse on failure.
     *
     * @return object|JsonResponse
     */
    private function requireAdmin(Request $request, string $capability = 'admin.access')
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (((int) ($user->is_admin ?? 0)) !== 1) {
            return response()->json(['message' => 'Geen admin toegang.'], 403);
        }
        $caps = $request->attributes->get('gymies_admin_capabilities');
        if (is_array($caps) && !in_array('admin.super', $caps, true) && !in_array($capability, $caps, true)) {
            return response()->json(['message' => 'Onvoldoende admin-rechten.'], 403);
        }

        return $user;
    }
}
