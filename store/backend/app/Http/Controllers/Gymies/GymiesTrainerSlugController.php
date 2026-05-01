<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * GET trainers/by-slug/{slug}
 * Resolve trainer by profile_slug and redirect to trainers/{id}.
 * Voor persoonlijke booking links: gymies.nl/t/jouwnaam
 */
class GymiesTrainerSlugController
{
    public function show(Request $request, string $slug): RedirectResponse
    {
        $slug = trim($slug);
        if ($slug === '') {
            abort(404);
        }

        if (!Schema::hasTable('gymies_trainer_profiles')
            || !Schema::hasColumn('gymies_trainer_profiles', 'profile_slug')) {
            abort(404);
        }

        $profile = DB::table('gymies_trainer_profiles')
            ->where('profile_slug', $slug)
            ->first();

        if (!$profile || !($profile->user_id ?? null)) {
            abort(404);
        }

        $userId = (int) $profile->user_id;

        try {
            $url = route('api.gymies.trainers.show', ['id' => $userId], true);
            return redirect($url, 302);
        } catch (\Throwable $e) {
            $base = $request->getSchemeAndHttpHost() . ($request->getBaseUrl() ?: '');
            return redirect(rtrim($base, '/') . '/api/gymies/trainers/' . $userId, 302);
        }
    }
}
