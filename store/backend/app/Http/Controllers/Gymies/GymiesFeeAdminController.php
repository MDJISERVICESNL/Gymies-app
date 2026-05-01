<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Admin CRUD voor gymies_fee_settings.
 * Prefix: vault-console/fees
 *
 * Structuur:
 * - Platform defaults: trainer_user_id IS NULL, plan_slug = 'starter'|'pro'|'studio'|NULL
 * - Trainer overrides: trainer_user_id = X, plan_slug = NULL (of specifiek plan)
 *
 * fee_type: 'fixed' (centen) of 'percent' (basispunten, 250 = 2.5%)
 * client_pays: 1 = klant betaalt service fee, 0 = trainer betaalt
 */
class GymiesFeeAdminController
{
    private const TABLE = 'gymies_fee_settings';

    /**
     * GET vault-console/fees — Alle fee settings ophalen, gesorteerd.
     */
    public function index(Request $request): JsonResponse
    {
        GymiesSchemaEnsure::feeSettingsTable();

        if (!Schema::hasTable(self::TABLE)) {
            return response()->json(['data' => [], 'env_fallback' => $this->envFallback()]);
        }

        $rows = DB::table(self::TABLE)
            ->orderByRaw('trainer_user_id IS NOT NULL, trainer_user_id ASC')
            ->orderByRaw("FIELD(plan_slug, 'starter', 'pro', 'studio')")
            ->get()
            ->map(fn ($row) => $this->formatRow($row))
            ->values()
            ->all();

        // Splits in defaults (trainer_user_id = NULL) en overrides
        $defaults  = array_values(array_filter($rows, fn ($r) => $r['trainer_user_id'] === null));
        $overrides = array_values(array_filter($rows, fn ($r) => $r['trainer_user_id'] !== null));

        return response()->json([
            'defaults'     => $defaults,
            'overrides'    => $overrides,
            'env_fallback' => $this->envFallback(),
        ]);
    }

    /**
     * POST vault-console/fees — Nieuwe fee setting aanmaken.
     */
    public function store(Request $request): JsonResponse
    {
        GymiesSchemaEnsure::feeSettingsTable();

        $request->validate([
            'trainer_user_id' => 'nullable|integer|min:1',
            'plan_slug'       => 'nullable|string|in:starter,pro,studio',
            'fee_type'        => 'required|string|in:fixed,percent',
            'fee_value'       => 'required|integer|min:0|max:100000',
            'client_pays'     => 'required|boolean',
        ]);

        $trainerUserId = $request->input('trainer_user_id') ? (int) $request->input('trainer_user_id') : null;
        $planSlug      = $request->input('plan_slug') ?: null;

        // Check voor duplicate
        $exists = DB::table(self::TABLE)
            ->where('trainer_user_id', $trainerUserId)
            ->where('plan_slug', $planSlug)
            ->exists();
        if ($exists) {
            return response()->json([
                'message' => 'Er bestaat al een fee setting voor deze combinatie.',
            ], 422);
        }

        // Valideer dat trainer bestaat als trainer_user_id is opgegeven
        if ($trainerUserId !== null) {
            $usersTable = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
            $user = DB::table($usersTable)->where('id', $trainerUserId)->first();
            if (!$user) {
                return response()->json(['message' => 'Trainer niet gevonden.'], 404);
            }
        }

        $id = DB::table(self::TABLE)->insertGetId([
            'trainer_user_id' => $trainerUserId,
            'plan_slug'       => $planSlug,
            'fee_type'        => (string) $request->input('fee_type'),
            'fee_value'       => (int) $request->input('fee_value'),
            'client_pays'     => (bool) $request->input('client_pays') ? 1 : 0,
            'is_active'       => 1,
            'created_at'      => now(),
            'updated_at'      => now(),
        ]);

        $row = DB::table(self::TABLE)->find($id);

        return response()->json([
            'message' => 'Fee setting aangemaakt.',
            'data'    => $this->formatRow($row),
        ], 201);
    }

    /**
     * PUT vault-console/fees/{id} — Fee setting wijzigen.
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $row = DB::table(self::TABLE)->find((int) $id);
        if (!$row) {
            return response()->json(['message' => 'Fee setting niet gevonden.'], 404);
        }

        $request->validate([
            'fee_type'    => 'sometimes|required|string|in:fixed,percent',
            'fee_value'   => 'sometimes|required|integer|min:0|max:100000',
            'client_pays' => 'sometimes|required|boolean',
            'is_active'   => 'sometimes|required|boolean',
        ]);

        $update = ['updated_at' => now()];
        if ($request->has('fee_type'))    $update['fee_type']    = (string) $request->input('fee_type');
        if ($request->has('fee_value'))   $update['fee_value']   = (int) $request->input('fee_value');
        if ($request->has('client_pays')) $update['client_pays'] = (bool) $request->input('client_pays') ? 1 : 0;
        if ($request->has('is_active'))   $update['is_active']   = (bool) $request->input('is_active') ? 1 : 0;

        DB::table(self::TABLE)->where('id', (int) $id)->update($update);

        $updated = DB::table(self::TABLE)->find((int) $id);
        return response()->json([
            'message' => 'Fee setting bijgewerkt.',
            'data'    => $this->formatRow($updated),
        ]);
    }

    /**
     * DELETE vault-console/fees/{id} — Fee setting verwijderen.
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        $row = DB::table(self::TABLE)->find((int) $id);
        if (!$row) {
            return response()->json(['message' => 'Fee setting niet gevonden.'], 404);
        }

        DB::table(self::TABLE)->where('id', (int) $id)->delete();

        return response()->json(['message' => 'Fee setting verwijderd.']);
    }

    // ── Helpers ────────────────────────────────────────────

    private function formatRow(object $row): array
    {
        $trainerName = null;
        if (isset($row->trainer_user_id) && $row->trainer_user_id) {
            $usersTable = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
            $user = DB::table($usersTable)->where('id', $row->trainer_user_id)->first();
            $trainerName = $user
                ? trim(($user->display_name ?? $user->first_name ?? $user->name ?? '') . '')
                : 'Onbekend (#' . $row->trainer_user_id . ')';
            if ($trainerName === '') {
                $trainerName = $user->email ?? 'Onbekend';
            }
        }

        return [
            'id'              => (int) $row->id,
            'trainer_user_id' => $row->trainer_user_id ? (int) $row->trainer_user_id : null,
            'trainer_name'    => $trainerName,
            'plan_slug'       => $row->plan_slug ?? null,
            'fee_type'        => (string) $row->fee_type,
            'fee_value'       => (int) $row->fee_value,
            'client_pays'     => (bool) ($row->client_pays ?? true),
            'is_active'       => (bool) ($row->is_active ?? true),
            'fee_display'     => $this->feeDisplay((string) $row->fee_type, (int) $row->fee_value),
            'created_at'      => $row->created_at ?? null,
            'updated_at'      => $row->updated_at ?? null,
        ];
    }

    private function feeDisplay(string $type, int $value): string
    {
        if ($type === 'percent') {
            $pct = $value / 100;
            return rtrim(rtrim(number_format($pct, 2, ',', ''), '0'), ',') . '%';
        }
        return $value . 'ct';
    }

    private function envFallback(): array
    {
        return [
            'fee_cents' => (int) config('gymies.service_fee_cents', 49),
            'source'    => 'GYMIES_SERVICE_FEE_CENTS (env)',
        ];
    }
}
