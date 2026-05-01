<?php

declare(strict_types=1);

namespace App\Traits;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Trait voor controllers die alleen trainers mogen gebruiken.
 * Haalt de gymies_user uit request attributes (gezet door GymiesAuthMiddleware)
 * en controleert of role=trainer.
 */
trait GymiesRequireTrainerTrait
{
    /**
     * Retourneert de trainer-user, of een JsonResponse bij fout (401/403).
     *
     * Gebruik:
     *   $user = $this->requireTrainer($request);
     *   if ($user instanceof JsonResponse) return $user;
     *
     * @return object|JsonResponse
     */
    private function requireTrainer(Request $request): mixed
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if ($user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers hebben toegang.'], 403);
        }
        return $user;
    }
}
