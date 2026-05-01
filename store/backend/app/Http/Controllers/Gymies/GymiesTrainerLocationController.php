<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Traits\GymiesRequireTrainerTrait;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trainer-eigen locatiebeheer (gym, thuis, buiten, online).
 * Tabel: gymies_trainer_locations.
 */
final class GymiesTrainerLocationController extends Controller
{
    use GymiesRequireTrainerTrait;

    public function index(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        if (!Schema::hasTable('gymies_trainer_locations')) {
            return response()->json(['data' => []]);
        }

        $rows = DB::table('gymies_trainer_locations')
            ->where('trainer_user_id', $user->id)
            ->orderByDesc('is_primary')
            ->orderBy('name')
            ->get();

        $data = $rows->map(fn ($r) => self::formatRow($r))->all();

        return response()->json(['data' => $data]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        if (!Schema::hasTable('gymies_trainer_locations')) {
            return response()->json(['error' => 'Table not available'], 500);
        }

        $request->validate([
            'name' => 'required|string|max:255',
            'address_line1' => 'nullable|string|max:255',
            'postcode' => 'nullable|string|max:20',
            'city' => 'nullable|string|max:255',
            // T-012 FIXED: GPS bereik validatie
            'latitude'  => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'location_type' => 'nullable|in:gym,home,outdoor,online',
            'is_primary' => 'nullable|boolean',
        ]);

        $isPrimary = (bool) $request->input('is_primary', false);

        if ($isPrimary) {
            DB::table('gymies_trainer_locations')
                ->where('trainer_user_id', $user->id)
                ->update(['is_primary' => false]);
        }

        $id = DB::table('gymies_trainer_locations')->insertGetId([
            'trainer_user_id' => $user->id,
            'name' => $request->input('name'),
            'address_line1' => $request->input('address_line1'),
            'postcode' => $request->input('postcode'),
            'city' => $request->input('city'),
            'latitude' => $request->input('latitude'),
            'longitude' => $request->input('longitude'),
            'location_type' => $request->input('location_type', 'gym'),
            'is_primary' => $isPrimary ? 1 : 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $row = DB::table('gymies_trainer_locations')->where('id', $id)->first();

        return response()->json(['data' => self::formatRow($row)], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $row = DB::table('gymies_trainer_locations')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->first();

        if (!$row) {
            return response()->json(['error' => 'Not found'], 404);
        }

        $request->validate([
            'name' => 'sometimes|required|string|max:255',
            'address_line1' => 'nullable|string|max:255',
            'postcode' => 'nullable|string|max:20',
            'city' => 'nullable|string|max:255',
            // T-012 FIXED: GPS bereik validatie
            'latitude'  => 'nullable|numeric|between:-90,90',
            'longitude' => 'nullable|numeric|between:-180,180',
            'location_type' => 'nullable|in:gym,home,outdoor,online',
            'is_primary' => 'nullable|boolean',
        ]);

        $updates = array_filter($request->only([
            'name', 'address_line1', 'postcode', 'city',
            'latitude', 'longitude', 'location_type',
        ]), fn ($v) => $v !== null);

        if ($request->has('is_primary') && $request->boolean('is_primary')) {
            DB::table('gymies_trainer_locations')
                ->where('trainer_user_id', $user->id)
                ->where('id', '!=', $id)
                ->update(['is_primary' => false]);
            $updates['is_primary'] = true;
        } elseif ($request->has('is_primary')) {
            $updates['is_primary'] = false;
        }

        $updates['updated_at'] = now();

        DB::table('gymies_trainer_locations')
            ->where('id', $id)
            ->update($updates);

        $updated = DB::table('gymies_trainer_locations')->where('id', $id)->first();

        return response()->json(['data' => self::formatRow($updated)]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $deleted = DB::table('gymies_trainer_locations')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->delete();

        if (!$deleted) {
            return response()->json(['error' => 'Not found'], 404);
        }

        return response()->json(['message' => 'Deleted']);
    }

    private static function formatRow(object $r): array
    {
        return [
            'id' => (string) $r->id,
            'trainer_user_id' => (string) $r->trainer_user_id,
            'name' => (string) $r->name,
            'address_line1' => $r->address_line1,
            'postcode' => $r->postcode,
            'city' => $r->city,
            'latitude' => $r->latitude !== null ? (float) $r->latitude : null,
            'longitude' => $r->longitude !== null ? (float) $r->longitude : null,
            'location_type' => (string) ($r->location_type ?? 'gym'),
            'is_primary' => (bool) $r->is_primary,
            'created_at' => $r->created_at,
            'updated_at' => $r->updated_at,
        ];
    }
}
