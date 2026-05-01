<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Specialiteiten: vaste lijst, trainer-koppeling, en aanvraag-workflow.
 *
 * PUBLIEK
 *   GET  specialties                        – alle actieve specialiteiten
 *
 * TRAINER (authenticated)
 *   GET  trainer/specialties                – eigen specialiteiten + pending aanvragen
 *   PUT  trainer/specialties                – kies max 5 specialiteiten
 *   POST trainer/specialties/request        – vraag nieuwe specialiteit aan
 *
 * ADMIN (authenticated + is_admin)
 *   GET  admin/specialty-requests           – alle pending aanvragen
 *   PUT  admin/specialty-requests/{id}      – goedkeuren of afwijzen
 */
class GymiesSpecialtyController
{
    // ── Seed-data ────────────────────────────────────────────
    private const FALLBACK_SPECIALTIES = [
        ['id' => 1,  'name' => 'Krachttraining',         'icon' => 'fitness_center',        'sort_order' => 1],
        ['id' => 2,  'name' => 'Conditie & Vetverlies',  'icon' => 'local_fire_department',  'sort_order' => 2],
        ['id' => 3,  'name' => 'Hyrox & Functioneel',    'icon' => 'speed',                  'sort_order' => 3],
        ['id' => 4,  'name' => 'Kickboksen',             'icon' => 'sports_mma',             'sort_order' => 4],
        ['id' => 5,  'name' => 'Boksen',                 'icon' => 'sports_mma',             'sort_order' => 5],
        ['id' => 6,  'name' => 'Calisthenics',           'icon' => 'self_improvement',       'sort_order' => 6],
        ['id' => 7,  'name' => 'Pilates',                'icon' => 'self_improvement',       'sort_order' => 7],
        ['id' => 8,  'name' => 'Yoga',                   'icon' => 'spa',                    'sort_order' => 8],
        ['id' => 9,  'name' => 'Hardlopen',              'icon' => 'directions_run',         'sort_order' => 9],
        ['id' => 10, 'name' => 'CrossFit',               'icon' => 'fitness_center',         'sort_order' => 10],
        ['id' => 11, 'name' => 'HIIT',                   'icon' => 'bolt',                   'sort_order' => 11],
        ['id' => 12, 'name' => 'Mobility & Revalidatie', 'icon' => 'accessibility',          'sort_order' => 12],
        ['id' => 13, 'name' => 'Senior Fitness',         'icon' => 'elderly',                'sort_order' => 13],
        ['id' => 14, 'name' => 'Vrouwenkracht',          'icon' => 'woman',                  'sort_order' => 14],
        ['id' => 15, 'name' => 'Personal Training',      'icon' => 'person',                 'sort_order' => 15],
        ['id' => 16, 'name' => 'Voeding & Leefstijl',   'icon' => 'restaurant',             'sort_order' => 16],
    ];

    // ══════════════════════════════════════════════════════════
    //  PUBLIEK
    // ══════════════════════════════════════════════════════════

    /** GET /api/gymies/specialties */
    public function index(): JsonResponse
    {
        $this->ensureTable();
        return response()->json(['data' => $this->loadAll()]);
    }

    // ══════════════════════════════════════════════════════════
    //  TRAINER
    // ══════════════════════════════════════════════════════════

    /** GET /api/gymies/trainer/specialties */
    public function trainerSpecialties(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $userId = (int) $user->id;
        $this->ensureTable();
        $this->ensureRequestsTable();

        return response()->json([
            'data'             => $this->loadAll(),
            'selected_ids'     => $this->loadTrainerSpecialtyIds($userId),
            'pending_requests' => $this->loadPendingRequestsForTrainer($userId),
        ]);
    }

    /** PUT /api/gymies/trainer/specialties */
    public function updateTrainerSpecialties(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $validated = $request->validate([
            'specialty_ids'   => ['required', 'array', 'max:5'],
            'specialty_ids.*' => ['integer', 'min:1'],
        ]);

        $ids    = array_unique(array_map('intval', $validated['specialty_ids']));
        $userId = (int) $user->id;

        $this->ensureTable();
        $this->ensureJunctionTable();

        $validIds = DB::table('gymies_specialties')
            ->whereIn('id', $ids)
            ->where('is_active', true)
            ->pluck('id')
            ->toArray();

        // Junction bijwerken
        DB::table('gymies_trainer_specialties')
            ->where('trainer_user_id', $userId)
            ->delete();

        $now = now();
        foreach ($validIds as $specId) {
            DB::table('gymies_trainer_specialties')->insert([
                'trainer_user_id' => $userId,
                'specialty_id'    => $specId,
                'created_at'      => $now,
            ]);
        }

        // Legacy tekstveld syncen
        $this->syncLegacyTextField($userId, $validIds);

        return response()->json([
            'data'             => $this->loadAll(),
            'selected_ids'     => $validIds,
            'pending_requests' => $this->loadPendingRequestsForTrainer($userId),
        ]);
    }

    /**
     * POST /api/gymies/trainer/specialties/request
     * Body: { "name": "Powerlifting" }
     */
    public function requestSpecialty(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $validated = $request->validate([
            'name' => ['required', 'string', 'min:2', 'max:60'],
        ]);

        $name   = self::capitalize(trim($validated['name']));
        $userId = (int) $user->id;

        $this->ensureTable();
        $this->ensureRequestsTable();

        // Check: bestaat al als actieve specialiteit?
        $exists = DB::table('gymies_specialties')
            ->whereRaw('LOWER(name) = ?', [strtolower($name)])
            ->where('is_active', true)
            ->first();

        if ($exists) {
            return response()->json([
                'message'      => 'Deze specialiteit bestaat al.',
                'specialty_id' => (int) $exists->id,
                'name'         => $exists->name,
            ], 409);
        }

        // Check: trainer heeft al een pending aanvraag voor deze naam?
        $pending = DB::table('gymies_specialty_requests')
            ->where('trainer_user_id', $userId)
            ->where('status', 'pending')
            ->whereRaw('LOWER(name) = ?', [strtolower($name)])
            ->first();

        if ($pending) {
            return response()->json([
                'message' => 'Je hebt al een aanvraag ingediend voor deze specialiteit.',
                'request' => $this->formatRequest($pending),
            ], 409);
        }

        // Max 3 pending aanvragen per trainer
        $pendingCount = DB::table('gymies_specialty_requests')
            ->where('trainer_user_id', $userId)
            ->where('status', 'pending')
            ->count();

        if ($pendingCount >= 3) {
            return response()->json([
                'message' => 'Je kunt maximaal 3 aanvragen tegelijk openstaan hebben.',
            ], 422);
        }

        $now = now();
        $id  = DB::table('gymies_specialty_requests')->insertGetId([
            'trainer_user_id' => $userId,
            'name'            => $name,
            'status'          => 'pending',
            'created_at'      => $now,
            'updated_at'      => $now,
        ]);

        $row = DB::table('gymies_specialty_requests')->find($id);

        return response()->json([
            'message' => 'Aanvraag ingediend! Een medewerker beoordeelt dit zo snel mogelijk.',
            'request' => $this->formatRequest($row),
        ], 201);
    }

    // ══════════════════════════════════════════════════════════
    //  ADMIN
    // ══════════════════════════════════════════════════════════

    /** GET /api/gymies/admin/specialty-requests */
    public function adminListRequests(Request $request): JsonResponse
    {
        if (!$this->isAdmin($request)) {
            return response()->json(['message' => 'Geen toegang.'], 403);
        }

        $this->ensureRequestsTable();

        $status = $request->input('status', 'pending');
        $query  = DB::table('gymies_specialty_requests')
            ->orderByDesc('created_at');

        if ($status !== 'all') {
            $query->where('status', $status);
        }

        // Trainer-naam joinen
        $usersTable = $this->usersTable();
        if ($usersTable) {
            $nameCol = $this->userNameColumn($usersTable);
            $query->leftJoin($usersTable, "{$usersTable}.id", '=', 'gymies_specialty_requests.trainer_user_id')
                  ->select('gymies_specialty_requests.*', "{$usersTable}.{$nameCol} as trainer_name", "{$usersTable}.email as trainer_email");
        }

        $rows = $query->limit(100)->get();

        $data = [];
        foreach ($rows as $row) {
            $item = $this->formatRequest($row);
            $r    = (array) $row;
            if (isset($r['trainer_name']))  $item['trainer_name']  = $r['trainer_name'];
            if (isset($r['trainer_email'])) $item['trainer_email'] = $r['trainer_email'];
            $data[] = $item;
        }

        return response()->json(['data' => $data]);
    }

    /**
     * PUT /api/gymies/admin/specialty-requests/{id}
     * Body: { "action": "approve" }  of  { "action": "reject", "reason": "..." }
     */
    public function adminHandleRequest(Request $request, string $id): JsonResponse
    {
        if (!$this->isAdmin($request)) {
            return response()->json(['message' => 'Geen toegang.'], 403);
        }

        $validated = $request->validate([
            'action' => ['required', 'string', 'in:approve,reject'],
            'reason' => ['nullable', 'string', 'max:500'],
            'icon'   => ['nullable', 'string', 'max:50'],
        ]);

        $this->ensureRequestsTable();
        $this->ensureTable();

        $row = DB::table('gymies_specialty_requests')->find((int) $id);
        if (!$row) {
            return response()->json(['message' => 'Aanvraag niet gevonden.'], 404);
        }
        if ($row->status !== 'pending') {
            return response()->json(['message' => 'Aanvraag is al verwerkt.'], 409);
        }

        $action   = $validated['action'];
        $reviewer = $request->user();
        $now      = now();

        if ($action === 'approve') {
            $name = self::capitalize(trim($row->name));

            // Check of naam al bestaat (race condition)
            $existing = DB::table('gymies_specialties')
                ->whereRaw('LOWER(name) = ?', [strtolower($name)])
                ->first();

            if ($existing) {
                // Markeer aanvraag als approved maar link naar bestaande
                DB::table('gymies_specialty_requests')
                    ->where('id', (int) $id)
                    ->update([
                        'status'        => 'approved',
                        'approved_specialty_id' => (int) $existing->id,
                        'reviewed_by'   => $reviewer ? (int) $reviewer->id : null,
                        'reviewed_at'   => $now,
                        'updated_at'    => $now,
                    ]);

                return response()->json([
                    'message'      => "Goedgekeurd — bestond al als \"{$existing->name}\".",
                    'specialty_id' => (int) $existing->id,
                ]);
            }

            // Nieuwe specialiteit aanmaken
            $maxSort = DB::table('gymies_specialties')->max('sort_order') ?? 0;
            $icon    = $validated['icon'] ?? 'star';

            $newId = DB::table('gymies_specialties')->insertGetId([
                'name'       => $name,
                'icon'       => $icon,
                'sort_order' => $maxSort + 1,
                'is_active'  => true,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            DB::table('gymies_specialty_requests')
                ->where('id', (int) $id)
                ->update([
                    'status'                => 'approved',
                    'approved_specialty_id' => $newId,
                    'reviewed_by'           => $reviewer ? (int) $reviewer->id : null,
                    'reviewed_at'           => $now,
                    'updated_at'            => $now,
                ]);

            // Automatisch toevoegen aan de trainer die het aanvroeg
            $this->ensureJunctionTable();
            $trainerId = (int) $row->trainer_user_id;
            $currentIds = DB::table('gymies_trainer_specialties')
                ->where('trainer_user_id', $trainerId)
                ->pluck('specialty_id')
                ->toArray();

            if (count($currentIds) < 5 && !in_array($newId, $currentIds)) {
                DB::table('gymies_trainer_specialties')->insert([
                    'trainer_user_id' => $trainerId,
                    'specialty_id'    => $newId,
                    'created_at'      => $now,
                ]);
                $currentIds[] = $newId;
                $this->syncLegacyTextField($trainerId, $currentIds);
            }

            return response()->json([
                'message'      => "\"{$name}\" is goedgekeurd en toegevoegd.",
                'specialty_id' => $newId,
            ]);

        } else {
            // Reject
            DB::table('gymies_specialty_requests')
                ->where('id', (int) $id)
                ->update([
                    'status'      => 'rejected',
                    'admin_note'  => $validated['reason'] ?? null,
                    'reviewed_by' => $reviewer ? (int) $reviewer->id : null,
                    'reviewed_at' => $now,
                    'updated_at'  => $now,
                ]);

            return response()->json([
                'message' => 'Aanvraag afgewezen.',
            ]);
        }
    }

    // ══════════════════════════════════════════════════════════
    //  HELPERS
    // ══════════════════════════════════════════════════════════

    /**
     * Capitalize: eerste letter hoofdletter, rest behouden.
     * "kickboksen" → "Kickboksen", "hIIT" → "HIIT" (als het al zo is).
     * Speciaal: woorden na & ook capitaliseren.
     */
    private static function capitalize(string $raw): string
    {
        $raw = trim($raw);
        if ($raw === '') return $raw;

        // Split op " & " om elk deel apart te capitaliseren
        $parts = explode(' & ', $raw);
        $result = [];
        foreach ($parts as $part) {
            $part = trim($part);
            if ($part === '') continue;
            // Als het geheel uppercase is (bv. "HIIT"), behoud het
            if (strtoupper($part) === $part && strlen($part) <= 5) {
                $result[] = $part;
            } else {
                $result[] = mb_strtoupper(mb_substr($part, 0, 1)) . mb_substr($part, 1);
            }
        }
        return implode(' & ', $result);
    }

    private function loadAll(): array
    {
        if (!Schema::hasTable('gymies_specialties')) {
            return self::FALLBACK_SPECIALTIES;
        }

        $rows = DB::table('gymies_specialties')
            ->where('is_active', true)
            ->orderBy('sort_order')
            ->get();

        if ($rows->isEmpty()) {
            return self::FALLBACK_SPECIALTIES;
        }

        $result = [];
        foreach ($rows as $row) {
            $r = (array) $row;
            $result[] = [
                'id'         => (int) ($r['id'] ?? 0),
                'name'       => $r['name'] ?? '',
                'icon'       => $r['icon'] ?? null,
                'sort_order' => (int) ($r['sort_order'] ?? 0),
            ];
        }
        return $result;
    }

    private function loadTrainerSpecialtyIds(int $userId): array
    {
        if (!Schema::hasTable('gymies_trainer_specialties')) {
            return $this->inferIdsFromLegacyText($userId);
        }

        $ids = DB::table('gymies_trainer_specialties')
            ->where('trainer_user_id', $userId)
            ->pluck('specialty_id')
            ->map(fn($v) => (int) $v)
            ->toArray();

        if (empty($ids)) {
            return $this->inferIdsFromLegacyText($userId);
        }

        return $ids;
    }

    private function loadPendingRequestsForTrainer(int $userId): array
    {
        if (!Schema::hasTable('gymies_specialty_requests')) {
            return [];
        }

        $rows = DB::table('gymies_specialty_requests')
            ->where('trainer_user_id', $userId)
            ->orderByDesc('created_at')
            ->limit(10)
            ->get();

        $data = [];
        foreach ($rows as $row) {
            $data[] = $this->formatRequest($row);
        }
        return $data;
    }

    private function formatRequest(object $row): array
    {
        $r = (array) $row;
        return [
            'id'         => (int) ($r['id'] ?? 0),
            'name'       => $r['name'] ?? '',
            'status'     => $r['status'] ?? 'pending',
            'admin_note' => $r['admin_note'] ?? null,
            'created_at' => $r['created_at'] ?? null,
            'approved_specialty_id' => isset($r['approved_specialty_id']) ? (int) $r['approved_specialty_id'] : null,
        ];
    }

    private function inferIdsFromLegacyText(int $userId): array
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return [];
        }

        $profile = DB::table('gymies_trainer_profiles')
            ->where('user_id', $userId)
            ->value('specialty');

        if (!$profile || !is_string($profile) || trim($profile) === '') {
            return [];
        }

        $tokens = preg_split('/[,&]/', $profile);
        $tokens = array_map('trim', $tokens);
        $tokens = array_filter($tokens, fn($t) => $t !== '');

        $allSpecs = $this->loadAll();
        $matched  = [];
        foreach ($tokens as $token) {
            $lower = strtolower($token);
            foreach ($allSpecs as $spec) {
                if (strtolower($spec['name']) === $lower) {
                    $matched[] = $spec['id'];
                    break;
                }
            }
        }

        return array_unique($matched);
    }

    private function syncLegacyTextField(int $userId, array $specialtyIds): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) return;
        $profileCols = Schema::getColumnListing('gymies_trainer_profiles');
        if (!in_array('specialty', $profileCols)) return;

        $names = DB::table('gymies_specialties')
            ->whereIn('id', $specialtyIds)
            ->orderBy('sort_order')
            ->pluck('name')
            ->toArray();

        DB::table('gymies_trainer_profiles')
            ->where('user_id', $userId)
            ->update([
                'specialty'  => implode(', ', $names),
                'updated_at' => now(),
            ]);
    }

    private function isAdmin(Request $request): bool
    {
        $user = $request->user();
        if (!$user || !$user->id) return false;

        $r = (array) $user;
        // Check role / is_admin velden
        if (($r['role'] ?? '') === 'admin') return true;
        if (($r['is_admin'] ?? false) === true || ($r['is_admin'] ?? 0) === 1) return true;

        // Check gymies_users tabel
        $usersTable = $this->usersTable();
        if ($usersTable) {
            $cols = Schema::getColumnListing($usersTable);
            $row  = DB::table($usersTable)->where('id', (int) $user->id)->first();
            if ($row) {
                $u = (array) $row;
                if (($u['role'] ?? '') === 'admin') return true;
                if (($u['is_admin'] ?? false) == true) return true;
                if (in_array('type', $cols) && ($u['type'] ?? '') === 'admin') return true;
            }
        }

        return false;
    }

    private function usersTable(): ?string
    {
        foreach (['gymies_users', 'users'] as $t) {
            if (Schema::hasTable($t)) return $t;
        }
        return null;
    }

    private function userNameColumn(string $table): string
    {
        foreach (['display_name', 'name', 'full_name', 'first_name'] as $col) {
            if (Schema::hasColumn($table, $col)) return $col;
        }
        return 'id';
    }

    // ── Schema ensure ────────────────────────────────────────

    private function ensureTable(): void
    {
        if (Schema::hasTable('gymies_specialties')) {
            $count = DB::table('gymies_specialties')->count();
            if ($count === 0) $this->seedSpecialties();
            return;
        }

        Schema::create('gymies_specialties', function ($table) {
            $table->id();
            $table->string('name', 100)->unique();
            $table->string('icon', 50)->nullable();
            $table->integer('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        $this->seedSpecialties();
    }

    private function seedSpecialties(): void
    {
        $now = now();
        foreach (self::FALLBACK_SPECIALTIES as $spec) {
            DB::table('gymies_specialties')->insertOrIgnore([
                'id'         => $spec['id'],
                'name'       => $spec['name'],
                'icon'       => $spec['icon'],
                'sort_order' => $spec['sort_order'],
                'is_active'  => true,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
    }

    private function ensureJunctionTable(): void
    {
        if (Schema::hasTable('gymies_trainer_specialties')) return;

        Schema::create('gymies_trainer_specialties', function ($table) {
            $table->id();
            $table->unsignedBigInteger('trainer_user_id')->index();
            $table->unsignedBigInteger('specialty_id')->index();
            $table->timestamp('created_at')->nullable();
            $table->unique(['trainer_user_id', 'specialty_id']);
        });
    }

    private function ensureRequestsTable(): void
    {
        if (Schema::hasTable('gymies_specialty_requests')) return;

        Schema::create('gymies_specialty_requests', function ($table) {
            $table->id();
            $table->unsignedBigInteger('trainer_user_id')->index();
            $table->string('name', 100);
            $table->enum('status', ['pending', 'approved', 'rejected'])->default('pending')->index();
            $table->unsignedBigInteger('approved_specialty_id')->nullable();
            $table->string('admin_note', 500)->nullable();
            $table->unsignedBigInteger('reviewed_by')->nullable();
            $table->timestamp('reviewed_at')->nullable();
            $table->timestamps();
        });
    }
}
