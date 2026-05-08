<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Elite: Resource Management – locaties (zalen, buiten, studio).
 */
final class GymiesGymLocationController extends GymiesGymController
{
    public function index(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager', 'viewer', 'trainer']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_locations')) {
            return response()->json(['data' => []]);
        }

        $orgId = (int) $ctx['organisation_id'];
        $rows = DB::table('gymies_gym_locations')
            ->where('organisation_id', $orgId)
            ->orderBy('sort_order')
            ->orderBy('name')
            // N-039 FIXED: exclude sensitive internal fields from public response
            ->select(['id', 'organisation_id', 'name', 'location_type', 'capacity', 'sort_order', 'created_at', 'updated_at'])
            ->get();

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'organisation_id' => (string) $r->organisation_id,
            'name' => (string) $r->name,
            'location_type' => (string) $r->location_type,
            'capacity' => $r->capacity !== null ? (int) $r->capacity : null,
            'sort_order' => (int) $r->sort_order,
            'created_at' => $r->created_at,
            'updated_at' => $r->updated_at,
        ])->all();

        $defaultLocationId = null;
        if (Schema::hasColumn('gymies_organisations', 'default_location_id')) {
            $org = DB::table('gymies_organisations')->where('id', $orgId)->first(['default_location_id']);
            if ($org && $org->default_location_id) {
                $defaultLocationId = (string) $org->default_location_id;
            }
        }

        return response()->json([
            'data' => $data,
            'default_location_id' => $defaultLocationId,
        ]);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager', 'viewer', 'trainer']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_locations')) {
            return response()->json(['message' => 'Locaties niet beschikbaar.'], 422);
        }

        $orgId = (int) $ctx['organisation_id'];
        $row = DB::table('gymies_gym_locations')
            ->where('id', $id)
            ->where('organisation_id', $orgId)
            ->first();
        if (!$row) {
            return response()->json(['message' => 'Locatie niet gevonden.'], 404);
        }

        return response()->json([
            'data' => [
                'id' => (string) $row->id,
                'organisation_id' => (string) $row->organisation_id,
                'name' => (string) $row->name,
                'location_type' => (string) $row->location_type,
                'capacity' => $row->capacity !== null ? (int) $row->capacity : null,
                'sort_order' => (int) $row->sort_order,
                'created_at' => $row->created_at,
                'updated_at' => $row->updated_at,
            ],
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_locations')) {
            return response()->json(['message' => 'Locaties niet beschikbaar.'], 422);
        }

        $request->validate([
            'name' => 'required|string|max:128',
            'location_type' => 'nullable|in:zaal,buiten,studio,overig',
            'capacity' => 'nullable|integer|min:1|max:10000',
            'sort_order' => 'nullable|integer|min:0',
        ]);

        // BUG-009: Add transaction wrapping for atomic location creation
        return DB::transaction(function () use ($request, $ctx) {
            $orgId = (int) $ctx['organisation_id'];
            $sortOrder = (int) ($request->input('sort_order') ?? 0);

            $id = DB::table('gymies_gym_locations')->insertGetId([
                'organisation_id' => $orgId,
                'name' => trim((string) $request->input('name')),
                'location_type' => (string) ($request->input('location_type') ?? 'zaal'),
                'capacity' => $request->filled('capacity') ? (int) $request->input('capacity') : null,
                'sort_order' => $sortOrder,
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            $row = DB::table('gymies_gym_locations')->where('id', $id)->first();

            return response()->json([
                'data' => [
                    'id' => (string) $row->id,
                    'organisation_id' => (string) $row->organisation_id,
                    'name' => (string) $row->name,
                    'location_type' => (string) $row->location_type,
                    'capacity' => $row->capacity !== null ? (int) $row->capacity : null,
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
        if (!Schema::hasTable('gymies_gym_locations')) {
            return response()->json(['message' => 'Locaties niet beschikbaar.'], 422);
        }

        $request->validate([
            'name' => 'nullable|string|max:128',
            'location_type' => 'nullable|in:zaal,buiten,studio,overig',
            'capacity' => 'nullable|integer|min:1|max:10000',
            'sort_order' => 'nullable|integer|min:0',
        ]);

        // BUG-010: Add transaction wrapping for atomic location update
        return DB::transaction(function () use ($request, $id, $ctx) {
            $orgId = (int) $ctx['organisation_id'];
            $row = DB::table('gymies_gym_locations')
                ->where('id', $id)
                ->where('organisation_id', $orgId)
                ->first();
            if (!$row) {
                throw new \Exception('Locatie niet gevonden.', 404);
            }

            $payload = ['updated_at' => now()];
            if ($request->has('name')) {
                $payload['name'] = trim((string) $request->input('name'));
            }
            if ($request->has('location_type')) {
                $payload['location_type'] = (string) $request->input('location_type');
            }
            if ($request->has('capacity')) {
                $payload['capacity'] = $request->filled('capacity') ? (int) $request->input('capacity') : null;
            }
            if ($request->has('sort_order')) {
                $payload['sort_order'] = (int) $request->input('sort_order');
            }

            DB::table('gymies_gym_locations')->where('id', $id)->update($payload);
            $row = DB::table('gymies_gym_locations')->where('id', $id)->first();

            return response()->json([
                'data' => [
                    'id' => (string) $row->id,
                    'organisation_id' => (string) $row->organisation_id,
                    'name' => (string) $row->name,
                    'location_type' => (string) $row->location_type,
                    'capacity' => $row->capacity !== null ? (int) $row->capacity : null,
                    'sort_order' => (int) $row->sort_order,
                    'created_at' => $row->created_at,
                    'updated_at' => $row->updated_at,
                ],
            ]);
        });
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_locations')) {
            return response()->json(['message' => 'Locaties niet beschikbaar.'], 422);
        }

        $orgId = (int) $ctx['organisation_id'];
        $deleted = DB::table('gymies_gym_locations')
            ->where('id', $id)
            ->where('organisation_id', $orgId)
            ->delete();

        if ($deleted === 0) {
            return response()->json(['message' => 'Locatie niet gevonden.'], 404);
        }

        return response()->json(['ok' => true], 200);
    }

    /**
     * Blokkades voor een locatie (onderhoud, privé).
     */
    public function blocks(Request $request, string $id): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager', 'viewer', 'trainer']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_locations') || !Schema::hasTable('gymies_gym_location_blocks')) {
            return response()->json(['data' => []]);
        }

        $orgId = (int) $ctx['organisation_id'];
        $location = DB::table('gymies_gym_locations')
            ->where('id', $id)
            ->where('organisation_id', $orgId)
            ->first();
        if (!$location) {
            return response()->json(['message' => 'Locatie niet gevonden.'], 404);
        }

        // N-038 FIXED: validate and limit date range
        $from = $request->query('from');
        $to = $request->query('to');
        if ($from || $to) {
            try {
                if ($from) {
                    $fromDate = Carbon::parse($from);
                    if ($fromDate->year < 2020 || $fromDate->year > 2030) {
                        return response()->json(['message' => 'Datum buiten bereik.'], 422);
                    }
                }
                if ($to) {
                    $toDate = Carbon::parse($to);
                    if ($toDate->year < 2020 || $toDate->year > 2030) {
                        return response()->json(['message' => 'Datum buiten bereik.'], 422);
                    }
                }
            } catch (\Exception $e) {
                return response()->json(['message' => 'Ongeldige datum.'], 422);
            }
        }

        $query = DB::table('gymies_gym_location_blocks')->where('location_id', $id);
        if ($from && $to) {
            $query->where(function ($q) use ($from, $to) {
                $q->whereBetween('start_at', [$from, $to])
                    ->orWhereBetween('end_at', [$from, $to])
                    ->orWhere(function ($q2) use ($from, $to) {
                        $q2->where('start_at', '<=', $from)->where('end_at', '>=', $to);
                    });
            });
        }
        $rows = $query->orderBy('start_at')->get();

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'location_id' => (string) $r->location_id,
            'start_at' => $r->start_at,
            'end_at' => $r->end_at,
            'reason' => $r->reason,
            'created_at' => $r->created_at,
        ])->all();

        return response()->json(['data' => $data]);
    }

    /**
     * Blokkade aanmaken (owner/manager).
     */
    public function storeBlock(Request $request, string $id): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_locations') || !Schema::hasTable('gymies_gym_location_blocks')) {
            return response()->json(['message' => 'Blokkades niet beschikbaar.'], 422);
        }

        $request->validate([
            'start_at' => 'required|date',
            'end_at' => 'required|date|after:start_at',
            'reason' => 'nullable|string|max:64|in:onderhoud,privé,overig',
        ]);

        $orgId = (int) $ctx['organisation_id'];
        $userId = (int) $ctx['user_id'];
        $location = DB::table('gymies_gym_locations')
            ->where('id', $id)
            ->where('organisation_id', $orgId)
            ->first();
        if (!$location) {
            return response()->json(['message' => 'Locatie niet gevonden.'], 404);
        }

        $blockId = DB::table('gymies_gym_location_blocks')->insertGetId([
            'location_id' => (int) $id,
            'start_at' => $request->input('start_at'),
            'end_at' => $request->input('end_at'),
            'reason' => $request->input('reason') ?: null,
            'created_by_user_id' => $userId,
            'created_at' => now(),
        ]);

        $row = DB::table('gymies_gym_location_blocks')->where('id', $blockId)->first();
        return response()->json([
            'data' => [
                'id' => (string) $row->id,
                'location_id' => (string) $row->location_id,
                'start_at' => $row->start_at,
                'end_at' => $row->end_at,
                'reason' => $row->reason,
                'created_at' => $row->created_at,
            ],
        ], 201);
    }

    /**
     * Blokkade verwijderen (owner/manager). Route: DELETE gym/locations/{id}/blocks/{blockId}
     */
    public function destroyBlock(Request $request, string $id, string $blockId): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_location_blocks')) {
            return response()->json(['message' => 'Blokkades niet beschikbaar.'], 422);
        }

        $orgId = (int) $ctx['organisation_id'];
        $block = DB::table('gymies_gym_location_blocks as b')
            ->join('gymies_gym_locations as l', 'l.id', '=', 'b.location_id')
            ->where('b.id', $blockId)
            ->where('b.location_id', $id)
            ->where('l.organisation_id', $orgId)
            ->select('b.id')
            ->first();
        if (!$block) {
            return response()->json(['message' => 'Blokkade niet gevonden.'], 404);
        }

        DB::table('gymies_gym_location_blocks')->where('id', $blockId)->delete();
        return response()->json(['ok' => true], 200);
    }

    /**
     * Conflict-check: is locatie bezet in het gegeven tijdsinterval?
     * Retourneert { available: bool, conflicts: [...] }.
     */
    public function conflicts(Request $request, string $id): JsonResponse
    {
        $ctx = $this->requireGymMember($request, ['owner', 'manager', 'viewer', 'trainer']);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }
        if (!Schema::hasTable('gymies_gym_locations')) {
            return response()->json(['available' => true, 'conflicts' => []]);
        }

        $request->validate([
            'start_at' => 'required|date',
            'end_at' => 'required|date|after:start_at',
        ]);
        $startAt = $request->input('start_at');
        $endAt = $request->input('end_at');

        $orgId = (int) $ctx['organisation_id'];
        $location = DB::table('gymies_gym_locations')
            ->where('id', $id)
            ->where('organisation_id', $orgId)
            ->first();
        if (!$location) {
            return response()->json(['message' => 'Locatie niet gevonden.'], 404);
        }

        $conflicts = [];

        // Blokkades
        if (Schema::hasTable('gymies_gym_location_blocks')) {
            $blocks = DB::table('gymies_gym_location_blocks')
                ->where('location_id', $id)
                ->where('start_at', '<', $endAt)
                ->where('end_at', '>', $startAt)
                ->get();
            foreach ($blocks as $b) {
                $conflicts[] = ['type' => 'block', 'start_at' => $b->start_at, 'end_at' => $b->end_at, 'reason' => $b->reason];
            }
        }

        // Groepslessen
        if (Schema::hasColumn('gymies_group_sessions', 'gym_location_id')) {
            $sessions = DB::table('gymies_group_sessions')
                ->where('gym_location_id', $id)
                ->whereIn('status', ['scheduled', 'published', 'crowdfund'])
                ->where('scheduled_at', '<', $endAt)
                ->whereRaw('DATE_ADD(scheduled_at, INTERVAL COALESCE(duration_minutes, 60) MINUTE) > ?', [$startAt])
                ->get();
            foreach ($sessions as $s) {
                $conflicts[] = ['type' => 'group_session', 'id' => (string) $s->id, 'title' => $s->title ?? '', 'start_at' => $s->scheduled_at];
            }
        }

        // Boekingen
        if (Schema::hasColumn('gymies_bookings', 'gym_location_id')) {
            $bookings = DB::table('gymies_bookings')
                ->where('gym_location_id', $id)
                ->whereIn('status', ['pending', 'confirmed', 'reserved'])
                ->where('scheduled_at', '<', $endAt)
                ->whereRaw('DATE_ADD(scheduled_at, INTERVAL COALESCE(duration_minutes, 60) MINUTE) > ?', [$startAt])
                ->get();
            foreach ($bookings as $b) {
                $conflicts[] = ['type' => 'booking', 'id' => (string) $b->id, 'start_at' => $b->scheduled_at, 'duration_minutes' => (int) $b->duration_minutes];
            }
        }

        return response()->json([
            'available' => count($conflicts) === 0,
            'conflicts' => $conflicts,
        ]);
    }
}
