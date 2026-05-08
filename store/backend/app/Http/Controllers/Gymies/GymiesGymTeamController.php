<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Elite: Teams & sub-teams.
 */
final class GymiesGymTeamController extends GymiesGymController
{
    public function index(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager', 'viewer', 'trainer']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_teams')) {
            return response()->json(['data' => []]);
        }

        $orgId = (int) $ctx['organisation_id'];
        $rows = DB::table('gymies_gym_teams')
            ->where('organisation_id', $orgId)
            ->orderBy('sort_order')
            ->orderBy('name')
            ->get();

        $membersCount = [];
        if (Schema::hasTable('gymies_gym_team_members')) {
            $counts = DB::table('gymies_gym_team_members')
                ->whereIn('team_id', $rows->pluck('id'))
                ->groupBy('team_id')
                ->selectRaw('team_id, COUNT(*) as cnt')
                ->pluck('cnt', 'team_id');
            $membersCount = $counts->all();
        }

        $data = $rows->map(function ($r) use ($membersCount) {
            $arr = [
                'id' => (string) $r->id,
                'organisation_id' => (string) $r->organisation_id,
                'parent_team_id' => $r->parent_team_id !== null ? (string) $r->parent_team_id : null,
                'name' => (string) $r->name,
                'description' => $r->description !== null ? (string) $r->description : null,
                'sort_order' => (int) $r->sort_order,
                'created_at' => $r->created_at,
                'updated_at' => $r->updated_at,
            ];
            $arr['members_count'] = (int) ($membersCount[$r->id] ?? 0);

            return $arr;
        })->all();

        return response()->json(['data' => $data]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_teams')) {
            return response()->json(['message' => 'Teams niet beschikbaar.'], 422);
        }

        $request->validate([
            'name' => 'required|string|max:128',
            'description' => 'nullable|string|max:500',
            'parent_team_id' => 'nullable|integer|min:1',
            'sort_order' => 'nullable|integer|min:0',
        ]);

        // BUG-011: Add transaction wrapping for atomic team creation
        return DB::transaction(function () use ($request, $ctx) {
            $orgId = (int) $ctx['organisation_id'];
            $parentTeamId = $request->filled('parent_team_id') ? (int) $request->input('parent_team_id') : null;
            if ($parentTeamId !== null) {
                $parent = DB::table('gymies_gym_teams')
                    ->where('id', $parentTeamId)
                    ->where('organisation_id', $orgId)
                    ->first();
                if (!$parent) {
                    throw new \Exception('Parent team niet gevonden.', 422);
                }
            }

            $sortOrder = (int) ($request->input('sort_order') ?? 0);

            $id = DB::table('gymies_gym_teams')->insertGetId([
                'organisation_id' => $orgId,
                'parent_team_id' => $parentTeamId,
                'name' => trim((string) $request->input('name')),
                'description' => $request->filled('description') ? trim((string) $request->input('description')) : null,
                'sort_order' => $sortOrder,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            $row = DB::table('gymies_gym_teams')->where('id', $id)->first();

            return response()->json([
                'data' => [
                    'id' => (string) $row->id,
                    'organisation_id' => (string) $row->organisation_id,
                    'parent_team_id' => $row->parent_team_id !== null ? (string) $row->parent_team_id : null,
                    'name' => (string) $row->name,
                    'description' => $row->description,
                    'sort_order' => (int) $row->sort_order,
                    'created_at' => $row->created_at,
                    'updated_at' => $row->updated_at,
                ],
            ], 201);
        });
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_teams')) {
            return response()->json(['message' => 'Teams niet beschikbaar.'], 422);
        }

        $request->validate([
            'name' => 'nullable|string|max:128',
            'description' => 'nullable|string|max:500',
            'parent_team_id' => 'nullable|integer|min:1',
            'sort_order' => 'nullable|integer|min:0',
        ]);

        // BUG-012: Add transaction wrapping for atomic team update
        return DB::transaction(function () use ($request, $id, $ctx) {
            // N-016 FIXED: IDOR voorkomen — gym ownership validatie
            $orgId = (int) $ctx['organisation_id'];
            $teamId = (int) $id;
            $row = DB::table('gymies_gym_teams')
                ->where('id', $teamId)
                ->where('organisation_id', $orgId)
                ->first();
            if (!$row) {
                throw new \Exception('Geen toegang tot dit team.', 403);
            }

            $payload = ['updated_at' => now()];
            if ($request->has('name')) {
                $payload['name'] = trim((string) $request->input('name'));
            }
            if ($request->has('description')) {
                $payload['description'] = $request->filled('description') ? trim((string) $request->input('description')) : null;
            }
            if ($request->has('parent_team_id')) {
                $parentId = $request->filled('parent_team_id') ? (int) $request->input('parent_team_id') : null;
                if ($parentId === $teamId) {
                    throw new \Exception('Team kan niet zijn eigen parent zijn.', 422);
                }
                $payload['parent_team_id'] = $parentId;
            }
            if ($request->has('sort_order')) {
                $payload['sort_order'] = (int) $request->input('sort_order');
            }

            DB::table('gymies_gym_teams')->where('id', $teamId)->update($payload);
            $row = DB::table('gymies_gym_teams')->where('id', $teamId)->first();

            return response()->json([
                'data' => [
                    'id' => (string) $row->id,
                    'organisation_id' => (string) $row->organisation_id,
                    'parent_team_id' => $row->parent_team_id !== null ? (string) $row->parent_team_id : null,
                    'name' => (string) $row->name,
                    'description' => $row->description,
                    'sort_order' => (int) $row->sort_order,
                    'created_at' => $row->created_at,
                    'updated_at' => $row->updated_at,
                ],
            ]);
        });
    }

    public function addMember(Request $request, string $teamId): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_teams') || !Schema::hasTable('gymies_gym_team_members')) {
            return response()->json(['message' => 'Teams niet beschikbaar.'], 422);
        }

        $request->validate([
            'trainer_user_id' => 'required|integer|min:1',
        ]);

        $orgId = (int) $ctx['organisation_id'];
        $tid = (int) $teamId;
        $trainerUserId = (int) $request->input('trainer_user_id');

        $team = DB::table('gymies_gym_teams')
            ->where('id', $tid)
            ->where('organisation_id', $orgId)
            ->first();
        if (!$team) {
            return response()->json(['message' => 'Team niet gevonden.'], 404);
        }

        $isTrainer = DB::table('gymies_organisation_trainers')
            ->where('organisation_id', $orgId)
            ->where('trainer_user_id', $trainerUserId)
            ->exists();
        if (!$isTrainer) {
            return response()->json(['message' => 'Trainer niet gevonden binnen deze organisatie.'], 422);
        }

        $exists = DB::table('gymies_gym_team_members')
            ->where('team_id', $tid)
            ->where('trainer_user_id', $trainerUserId)
            ->exists();
        if ($exists) {
            return response()->json(['message' => 'Trainer staat al in dit team.'], 422);
        }

        DB::table('gymies_gym_team_members')->insert([
            'team_id' => $tid,
            'trainer_user_id' => $trainerUserId,
            'role' => 'member',
            'created_at' => now(),
        ]);

        return response()->json(['ok' => true], 201);
    }

    public function removeMember(Request $request, string $teamId, string $trainerUserId): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_team_members')) {
            return response()->json(['message' => 'Teams niet beschikbaar.'], 422);
        }

        $orgId = (int) $ctx['organisation_id'];
        $tid = (int) $teamId;
        $tuid = (int) $trainerUserId;

        $team = DB::table('gymies_gym_teams')
            ->where('id', $tid)
            ->where('organisation_id', $orgId)
            ->first();
        if (!$team) {
            return response()->json(['message' => 'Team niet gevonden.'], 404);
        }

        $deleted = DB::table('gymies_gym_team_members')
            ->where('team_id', $tid)
            ->where('trainer_user_id', $tuid)
            ->delete();

        if ($deleted === 0) {
            return response()->json(['message' => 'Trainer niet in dit team.'], 404);
        }

        return response()->json(['ok' => true], 200);
    }
}
