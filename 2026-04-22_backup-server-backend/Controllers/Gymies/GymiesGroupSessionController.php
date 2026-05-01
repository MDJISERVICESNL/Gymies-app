<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Groepslessen: CRUD trainer, public list/detail, inschrijven, bevestigen, betaling.
 * Tabellen: gymies_group_sessions, gymies_group_session_participants.
 */
final class GymiesGroupSessionController extends Controller
{
    // SaaS 2.0: no platform fee, direct-to-trainer payments
    private const PLATFORM_FEE_CENTS = 0;
    private const MIN_PAX_DEADLINE_HOURS = 12;
    private const WAITLIST_CLAIM_MINUTES = 15;

    private function getGroupSessionTrainerPenaltyCents(): int
    {
        if (!Schema::hasTable('gymies_system_settings')) {
            return 5000;
        }
        $v = DB::table('gymies_system_settings')->where('setting_key', 'group_session_trainer_penalty_cents')->value('setting_value');
        return $v !== null && $v !== '' ? (int) $v : 5000;
    }

    /**
     * Publiek: lijst groepslessen (status collecting of confirmed_by_trainer, in de toekomst).
     * Optioneel gefilterd op trainer_id, datum.
     */
    public function index(Request $request): JsonResponse
    {
        if (!Schema::hasTable('gymies_group_sessions')) {
            return response()->json(['data' => []]);
        }

        $query = DB::table('gymies_group_sessions as g')
            ->join('gymies_users as u', 'g.trainer_user_id', '=', 'u.id')
            ->where('u.role', 'trainer')
            ->where('g.scheduled_at', '>', now()->toDateTimeString());

        $statusCol = Schema::hasColumn('gymies_group_sessions', 'status');
        if ($statusCol) {
            $query->whereIn('g.status', ['collecting', 'confirmed_by_trainer']);
        }

        $trainerId = $request->query('trainer_id');
        if ($trainerId !== null && $trainerId !== '') {
            $query->where('g.trainer_user_id', (int) $trainerId);
        }
        $from = $request->query('from'); // Y-m-d
        if ($from !== null && $from !== '') {
            $query->whereDate('g.scheduled_at', '>=', $from);
        }
        $to = $request->query('to');
        if ($to !== null && $to !== '') {
            $query->whereDate('g.scheduled_at', '<=', $to);
        }

        $maxPrice = $request->query('max_price_cents');
        if ($maxPrice !== null && $maxPrice !== '' && is_numeric($maxPrice)) {
            $query->where('g.price_cents', '<=', (int) $maxPrice);
        }

        $q = trim((string) $request->query('q', ''));
        // T-005 FIXED: DoS via grote LIKE string voorkomen
        if ($q !== '' && strlen($q) <= 100) {
            $like = '%' . addcslashes($q, '%_\\') . '%';
            $query->where(function ($sub) use ($like) {
                $sub->where('g.title', 'LIKE', $like)
                    ->orWhere('g.description', 'LIKE', $like);
            });
        }

        $region = trim((string) $request->query('region', ''));
        if ($region !== '' && Schema::hasTable('gymies_trainer_profiles')) {
            $likeReg = '%' . addcslashes($region, '%_\\') . '%';
            $query->join('gymies_trainer_profiles as tp', 'tp.user_id', '=', 'u.id')
                ->whereRaw('LOWER(COALESCE(tp.region, \'\')) LIKE LOWER(?)', [$likeReg]);
        }

        $userLat = null;
        $userLng = null;
        $radiusKm = 40.0;
        $latRaw = $request->query('latitude');
        $lngRaw = $request->query('longitude');
        if ($latRaw !== null && $latRaw !== '' && $lngRaw !== null && $lngRaw !== '' && is_numeric($latRaw) && is_numeric($lngRaw)) {
            $la = (float) $latRaw;
            $lo = (float) $lngRaw;
            if ($la >= -90.0 && $la <= 90.0 && $lo >= -180.0 && $lo <= 180.0) {
                $userLat = $la;
                $userLng = $lo;
            }
        }
        $radiusRaw = $request->query('radius_km');
        if ($userLat !== null && $userLng !== null && $radiusRaw !== null && $radiusRaw !== '' && is_numeric($radiusRaw)) {
            $radiusKm = max(1.0, min(200.0, (float) $radiusRaw));
        }

        $geoActive = $userLat !== null && $userLng !== null && Schema::hasTable('gymies_trainer_locations');
        $fetchLimit = $geoActive ? 400 : 100;

        $select = [
            'g.id',
            'g.trainer_user_id',
            'g.title',
            'g.description',
            'g.scheduled_at',
            'g.duration_minutes',
            'g.max_participants',
            'g.price_cents',
            'g.location_type',
            'g.trainer_location_id',
            'u.display_name as trainer_name',
        ];
        if (Schema::hasColumn('gymies_group_sessions', 'min_participants')) {
            $select[] = 'g.min_participants';
        }
        if (Schema::hasColumn('gymies_group_sessions', 'location_notes')) {
            $select[] = 'g.location_notes';
        }
        if ($statusCol) {
            $select[] = 'g.status';
        }

        $rows = $query->select($select)->orderBy('g.scheduled_at')->limit($fetchLimit)->get();

        if ($geoActive) {
            $rows = $this->filterGroupSessionsByRadius($rows, $userLat, $userLng, $radiusKm)->take(100);
        }

        $participantCounts = [];
        if (Schema::hasTable('gymies_group_session_participants') && $rows->isNotEmpty()) {
            $ids = $rows->pluck('id')->map(fn ($id) => (int) $id)->all();
            $counts = DB::table('gymies_group_session_participants')
                ->whereIn('group_session_id', $ids)
                ->whereIn('status', ['pending', 'registered', 'payment_pending', 'confirmed'])
                ->selectRaw('group_session_id, COUNT(*) as cnt')
                ->groupBy('group_session_id')
                ->pluck('cnt', 'group_session_id');
            $participantCounts = $counts->all();
        }

        $data = $rows->map(function ($r) use ($participantCounts) {
            $item = $this->sessionToArray($r);
            $item['participants_count'] = (int) ($participantCounts[$r->id] ?? 0);
            $item['spots_left'] = max(0, (int) $r->max_participants - (int) ($participantCounts[$r->id] ?? 0));
            return $item;
        })->all();

        $onlySpots = $request->query('only_with_spots');
        if ($onlySpots === '1' || $onlySpots === 'true' || $onlySpots === true) {
            $data = array_values(array_filter($data, static function ($row) {
                return (int) ($row['spots_left'] ?? 0) > 0;
            }));
        }

        return response()->json(['data' => $data]);
    }

    /**
     * Publiek of ingelogde gebruiker: detail van één groepsles.
     */
    public function show(Request $request, string $id): JsonResponse
    {
        if (!Schema::hasTable('gymies_group_sessions')) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }

        $session = DB::table('gymies_group_sessions as g')
            ->join('gymies_users as u', 'g.trainer_user_id', '=', 'u.id')
            ->where('g.id', (int) $id)
            ->select(array_merge(['g.*'], ['u.display_name as trainer_name']))
            ->first();

        if (!$session) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }

        $user = $request->attributes->get('gymies_user');
        $isTrainer = $user && $user->role === 'trainer' && (int) $session->trainer_user_id === (int) $user->id;
        $statusCol = Schema::hasColumn('gymies_group_sessions', 'status');
        $pubStatuses = ['collecting', 'confirmed_by_trainer'];
        if ($statusCol && !$isTrainer && !in_array($session->status ?? 'draft', $pubStatuses, true)) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }

        $participantsCount = 0;
        $myRegistration = null;
        if (Schema::hasTable('gymies_group_session_participants')) {
            $participantsCount = (int) DB::table('gymies_group_session_participants')
                ->where('group_session_id', (int) $id)
                ->whereIn('status', ['pending', 'registered', 'payment_pending', 'confirmed'])
                ->count();
            if ($user && $user->role === 'klant') {
                $reg = DB::table('gymies_group_session_participants')
                    ->where('group_session_id', (int) $id)
                    ->where('client_user_id', (int) $user->id)
                    ->first(['id', 'status', 'paid_at', 'amount_cents']);
                if ($reg) {
                    $myRegistration = [
                        'id' => (string) $reg->id,
                        'status' => (string) $reg->status,
                        'paid_at' => $reg->paid_at,
                        'amount_cents' => $reg->amount_cents ? (int) $reg->amount_cents : null,
                    ];
                }
            }
        }

        $out = $this->sessionToArray($session);
        $out['participants_count'] = $participantsCount;
        $out['spots_left'] = max(0, (int) $session->max_participants - $participantsCount);
        $out['my_registration'] = $myRegistration;

        return response()->json(['data' => $out]);
    }

    /**
     * Trainer: lijst eigen groepslessen.
     */
    public function trainerIndex(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen groepslessen beheren.'], 403);
        }
        if (!Schema::hasTable('gymies_group_sessions')) {
            return response()->json(['data' => []]);
        }

        $query = DB::table('gymies_group_sessions as g')
            ->where('g.trainer_user_id', (int) $user->id)
            ->limit(200);

        $status = $request->query('status');
        if ($status !== null && $status !== '' && Schema::hasColumn('gymies_group_sessions', 'status')) {
            $query->where('g.status', $status);
        }
        $from = $request->query('from');
        if ($from !== null && $from !== '') {
            $query->whereDate('g.scheduled_at', '>=', $from);
        }
        $to = $request->query('to');
        if ($to !== null && $to !== '') {
            $query->whereDate('g.scheduled_at', '<=', $to);
        }
        // Eén dag (from=to): chronologisch; anders nieuwste eerst.
        if ($from !== null && $from !== '' && $to !== null && $to !== '' && $from === $to) {
            $query->orderBy('g.scheduled_at');
        } else {
            $query->orderByDesc('g.scheduled_at');
        }

        $rows = $query->get(['g.*']);
        $ids = $rows->pluck('id')->map(fn ($id) => (int) $id)->all();
        $participantCounts = [];
        if (Schema::hasTable('gymies_group_session_participants') && !empty($ids)) {
            $counts = DB::table('gymies_group_session_participants')
                ->whereIn('group_session_id', $ids)
                ->whereIn('status', ['pending', 'registered', 'payment_pending', 'confirmed'])
                ->selectRaw('group_session_id, COUNT(*) as cnt')
                ->groupBy('group_session_id')
                ->pluck('cnt', 'group_session_id');
            $participantCounts = $counts->all();
        }

        $data = $rows->map(function ($r) use ($participantCounts) {
            $item = $this->sessionToArray($r);
            $item['participants_count'] = (int) ($participantCounts[$r->id] ?? 0);
            $item['spots_left'] = max(0, (int) $r->max_participants - (int) ($participantCounts[$r->id] ?? 0));
            return $item;
        })->all();

        return response()->json(['data' => $data]);
    }

    /**
     * Trainer: groepsles aanmaken (status draft).
     */
    public function store(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen groepslessen aanmaken.'], 403);
        }
        $planCheck = GymiesPlanManager::assertGroupSessions((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json([
                'message' => $planCheck['message'],
                'upgrade_hint' => $planCheck['upgrade_hint'],
                'code' => 'plan_group_sessions_locked',
            ], 403);
        }
        $request->validate([
            'title' => 'required|string|max:255',
            'description' => 'nullable|string|max:5000',
            'scheduled_at' => 'required|date',
            'duration_minutes' => 'required|integer|min:15|max:240',
            'max_participants' => 'required|integer|min:2|max:200',
            'min_participants' => 'nullable|integer|min:1',
            // T-004 FIXED: price_cents maximum begrensd om integer overflow te voorkomen
            'price_cents' => 'required|integer|min:0|max:99999900', // max €999.999
            'location_type' => 'nullable|string|in:online,on_site,gym',
            'location_notes' => 'nullable|string|max:2000',
            'trainer_location_id' => 'nullable|integer|min:1',
            'gym_location_id' => 'nullable|integer|min:1',
            'waitlist_enabled' => 'nullable|boolean',
        ]);

        $minParticipants = (int) ($request->input('min_participants') ?? $request->input('max_participants'));
        $maxParticipants = (int) $request->input('max_participants');
        if ($minParticipants > $maxParticipants) {
            $minParticipants = $maxParticipants;
        }

        $insert = [
            'trainer_user_id' => (int) $user->id,
            'title' => $request->input('title'),
            'description' => $request->input('description') ?: null,
            'scheduled_at' => $request->input('scheduled_at'),
            'duration_minutes' => (int) $request->input('duration_minutes'),
            'max_participants' => $maxParticipants,
            'price_cents' => (int) $request->input('price_cents'),
            'location_type' => $request->input('location_type') ?: 'gym',
            'trainer_location_id' => $request->input('trainer_location_id') ? (int) $request->input('trainer_location_id') : null,
            'created_at' => now(),
            'updated_at' => now(),
        ];
        if (Schema::hasColumn('gymies_group_sessions', 'status')) {
            $insert['status'] = 'draft';
        }
        if (Schema::hasColumn('gymies_group_sessions', 'min_participants')) {
            $insert['min_participants'] = $minParticipants;
        }
        if (Schema::hasColumn('gymies_group_sessions', 'location_notes')) {
            $insert['location_notes'] = $request->input('location_notes') ?: null;
        }
        if (Schema::hasColumn('gymies_group_sessions', 'waitlist_enabled')) {
            $insert['waitlist_enabled'] = $request->has('waitlist_enabled')
                ? ($request->boolean('waitlist_enabled') ? 1 : 0)
                : 1;
        }
        if (Schema::hasColumn('gymies_group_sessions', 'gym_location_id') && $request->filled('gym_location_id')) {
            $insert['gym_location_id'] = (int) $request->input('gym_location_id');
        }

        $id = DB::table('gymies_group_sessions')->insertGetId($insert);
        $row = DB::table('gymies_group_sessions')->where('id', $id)->first();
        $trainerName = DB::table('gymies_users')->where('id', $row->trainer_user_id)->value('display_name');

        return response()->json(['data' => $this->sessionToArray((object) array_merge((array) $row, ['trainer_name' => $trainerName ?? 'Trainer']))], 201);
    }

    /**
     * Trainer: herhalende groepslessen in één keer aanmaken (kopieer naar X weken).
     * Body: zelfde velden als store + repeat_weeks (2–52). Alle sessies als draft.
     */
    public function storeRecurring(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen herhalende groepslessen aanmaken.'], 403);
        }
        $planCheck = GymiesPlanManager::assertGroupSessions((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json([
                'message' => $planCheck['message'],
                'upgrade_hint' => $planCheck['upgrade_hint'],
                'code' => 'plan_group_sessions_locked',
            ], 403);
        }

        $request->validate([
            'title' => 'required|string|max:255',
            'description' => 'nullable|string|max:5000',
            'scheduled_at' => 'required|date',
            'duration_minutes' => 'required|integer|min:15|max:240',
            'max_participants' => 'required|integer|min:2|max:200',
            'min_participants' => 'nullable|integer|min:1',
            // T-004 FIXED: price_cents maximum begrensd om integer overflow te voorkomen
            'price_cents' => 'required|integer|min:0|max:99999900', // max €999.999
            'location_type' => 'nullable|string|in:online,on_site,gym',
            'location_notes' => 'nullable|string|max:2000',
            'trainer_location_id' => 'nullable|integer|min:1',
            'gym_location_id' => 'nullable|integer|min:1',
            'repeat_weeks' => 'required|integer|min:2|max:52',
            'waitlist_enabled' => 'nullable|boolean',
        ]);

        $minParticipants = (int) ($request->input('min_participants') ?? $request->input('max_participants'));
        $maxParticipants = (int) $request->input('max_participants');
        if ($minParticipants > $maxParticipants) {
            $minParticipants = $maxParticipants;
        }

        $repeatWeeks = (int) $request->input('repeat_weeks');
        $firstAt = Carbon::parse($request->input('scheduled_at'));
        $created = [];

        for ($i = 0; $i < $repeatWeeks; $i++) {
            $scheduledAt = $firstAt->copy()->addWeeks($i)->toDateTimeString();
            $insert = [
                'trainer_user_id' => (int) $user->id,
                'title' => $request->input('title'),
                'description' => $request->input('description') ?: null,
                'scheduled_at' => $scheduledAt,
                'duration_minutes' => (int) $request->input('duration_minutes'),
                'max_participants' => $maxParticipants,
                'price_cents' => (int) $request->input('price_cents'),
                'location_type' => $request->input('location_type') ?: 'gym',
                'trainer_location_id' => $request->input('trainer_location_id') ? (int) $request->input('trainer_location_id') : null,
                'created_at' => now(),
                'updated_at' => now(),
            ];
            if (Schema::hasColumn('gymies_group_sessions', 'status')) {
                $insert['status'] = 'draft';
            }
            if (Schema::hasColumn('gymies_group_sessions', 'min_participants')) {
                $insert['min_participants'] = $minParticipants;
            }
            if (Schema::hasColumn('gymies_group_sessions', 'location_notes')) {
                $insert['location_notes'] = $request->input('location_notes') ?: null;
            }
            if (Schema::hasColumn('gymies_group_sessions', 'waitlist_enabled')) {
                $insert['waitlist_enabled'] = $request->has('waitlist_enabled')
                    ? ($request->boolean('waitlist_enabled') ? 1 : 0)
                    : 1;
            }
            if (Schema::hasColumn('gymies_group_sessions', 'gym_location_id') && $request->filled('gym_location_id')) {
                $insert['gym_location_id'] = (int) $request->input('gym_location_id');
            }

            $id = DB::table('gymies_group_sessions')->insertGetId($insert);
            $created[] = ['id' => (string) $id, 'scheduled_at' => $scheduledAt];
        }

        return response()->json([
            'data' => ['created' => $created, 'count' => count($created)],
            'message' => count($created) . ' groepslessen aangemaakt (concept). Je kunt ze apart publiceren.',
        ], 201);
    }

    /**
     * Trainer: groepsles bewerken (alleen draft of geen betaalde inschrijvingen).
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen groepslessen bewerken.'], 403);
        }

        $session = DB::table('gymies_group_sessions')->where('id', (int) $id)->where('trainer_user_id', (int) $user->id)->first();
        if (!$session) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }

        $status = Schema::hasColumn('gymies_group_sessions', 'status') ? ($session->status ?? 'draft') : 'draft';
        $hasPaid = false;
        if (Schema::hasTable('gymies_group_session_participants')) {
            $hasPaid = DB::table('gymies_group_session_participants')
                ->where('group_session_id', (int) $id)
                ->where('status', 'confirmed')
                ->exists();
        }
        if ($hasPaid && !in_array($status, ['draft'], true)) {
            return response()->json(['message' => 'Bewerken niet toegestaan nadat er betaalde inschrijvingen zijn.'], 422);
        }

        $request->validate([
            'title' => 'sometimes|required|string|max:255',
            'description' => 'nullable|string|max:5000',
            'scheduled_at' => 'sometimes|date',
            'duration_minutes' => 'sometimes|integer|min:15|max:240',
            'max_participants' => 'sometimes|integer|min:2|max:200',
            'min_participants' => 'nullable|integer|min:1',
            // T-004 FIXED: price_cents maximum begrensd om integer overflow te voorkomen
            'price_cents' => 'sometimes|integer|min:0|max:99999900', // max €999.999
            'location_type' => 'nullable|string|in:online,on_site,gym',
            'location_notes' => 'nullable|string|max:2000',
            'trainer_location_id' => 'nullable|integer|min:1',
        ]);

        $update = ['updated_at' => now()];
        foreach (['title', 'description', 'scheduled_at', 'duration_minutes', 'max_participants', 'price_cents', 'location_type', 'location_notes', 'trainer_location_id'] as $key) {
            if ($request->has($key)) {
                $v = $request->input($key);
                if ($key === 'trainer_location_id') {
                    $update[$key] = $v ? (int) $v : null;
                } elseif (in_array($key, ['duration_minutes', 'max_participants', 'price_cents'], true)) {
                    $update[$key] = (int) $v;
                } else {
                    $update[$key] = $v;
                }
            }
        }
        if ($request->has('min_participants') && Schema::hasColumn('gymies_group_sessions', 'min_participants')) {
            $update['min_participants'] = $request->input('min_participants') ? (int) $request->input('min_participants') : (int) $session->max_participants;
        }
        if ($request->has('waitlist_enabled') && Schema::hasColumn('gymies_group_sessions', 'waitlist_enabled')) {
            $update['waitlist_enabled'] = $request->boolean('waitlist_enabled') ? 1 : 0;
        }

        DB::table('gymies_group_sessions')->where('id', (int) $id)->update($update);
        $row = DB::table('gymies_group_sessions as g')
            ->join('gymies_users as u', 'g.trainer_user_id', '=', 'u.id')
            ->where('g.id', (int) $id)
            ->select(['g.*', 'u.display_name as trainer_name'])
            ->first();

        return response()->json(['data' => $this->sessionToArray($row)]);
    }

    /**
     * Trainer: publiceren (draft → collecting).
     */
    public function publish(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen groepslessen publiceren.'], 403);
        }
        if (!Schema::hasColumn('gymies_group_sessions', 'status')) {
            GymiesSchemaEnsure::groupSessionsStatusColumn();
            GymiesSchemaEnsure::groupSessionParticipantsWaitlistEnum();
        }
        if (!Schema::hasColumn('gymies_group_sessions', 'status')) {
            return response()->json(['message' => 'Publiceren wordt niet ondersteund. Draai alter_gymies_group_sessions_add_status.sql op de server.'], 503);
        }

        $session = DB::table('gymies_group_sessions')->where('id', (int) $id)->where('trainer_user_id', (int) $user->id)->first();
        if (!$session) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }
        if (($session->status ?? 'draft') !== 'draft') {
            return response()->json(['message' => 'Alleen conceptlessen kunnen worden gepubliceerd.'], 422);
        }

        DB::table('gymies_group_sessions')->where('id', (int) $id)->update(['status' => 'collecting', 'updated_at' => now()]);
        $row = DB::table('gymies_group_sessions as g')
            ->join('gymies_users as u', 'g.trainer_user_id', '=', 'u.id')
            ->where('g.id', (int) $id)
            ->select(['g.*', 'u.display_name as trainer_name'])
            ->first();

        return response()->json(['data' => $this->sessionToArray($row), 'message' => 'Groepsles is gepubliceerd. Klanten kunnen zich nu inschrijven.']);
    }

    /**
     * Trainer: les gaat door – status confirmed_by_trainer, betaallinks naar alle registered/pending deelnemers.
     */
    public function confirm(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen een les bevestigen.'], 403);
        }
        if (!Schema::hasColumn('gymies_group_sessions', 'status')) {
            GymiesSchemaEnsure::groupSessionsStatusColumn();
            GymiesSchemaEnsure::groupSessionParticipantsWaitlistEnum();
        }
        if (!Schema::hasColumn('gymies_group_sessions', 'status')) {
            return response()->json(['message' => 'Bevestigen wordt niet ondersteund. Draai alter_gymies_group_sessions_add_status.sql op de server.'], 503);
        }

        $session = DB::table('gymies_group_sessions')->where('id', (int) $id)->where('trainer_user_id', (int) $user->id)->first();
        if (!$session) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }
        if (($session->status ?? 'draft') !== 'collecting') {
            return response()->json(['message' => 'Alleen lessen in status "inschrijvingen verzamelen" kunnen worden bevestigd.'], 422);
        }

        // Controleer of het minimum aantal deelnemers bereikt is
        if (Schema::hasColumn('gymies_group_sessions', 'min_participants') && !empty($session->min_participants)) {
            $registeredCount = DB::table('gymies_group_session_participants')
                ->where('group_session_id', (int) $id)
                ->whereIn('status', ['pending', 'registered'])
                ->count();
            $minParticipants = (int) $session->min_participants;
            if ($registeredCount < $minParticipants) {
                return response()->json([
                    'message' => "Nog niet genoeg deelnemers om te bevestigen. Minimum is {$minParticipants}, momenteel ingeschreven: {$registeredCount}.",
                    'min_participants' => $minParticipants,
                    'registered_count' => $registeredCount,
                ], 422);
            }
        }

        DB::table('gymies_group_sessions')->where('id', (int) $id)->update(['status' => 'confirmed_by_trainer', 'updated_at' => now()]);

        $participants = DB::table('gymies_group_session_participants')
            ->where('group_session_id', (int) $id)
            ->whereIn('status', ['pending', 'registered'])
            ->get();

        $priceCents = (int) $session->price_cents;
        $feeCents = self::PLATFORM_FEE_CENTS;
        $payoutCents = max(0, $priceCents - $feeCents);

        foreach ($participants as $p) {
            DB::table('gymies_group_session_participants')->where('id', $p->id)->update([
                'status' => 'payment_pending',
                'amount_cents' => $priceCents,
                'platform_fee_cents' => $feeCents,
                'trainer_payout_cents' => $payoutCents,
            ]);
            if (Schema::hasTable('gymies_notification_queue')) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $p->client_user_id,
                    'channel' => 'in_app',
                    'event_type' => 'group_session_confirmed',
                    'payload_json' => json_encode([
                        'group_session_id' => (string) $id,
                        'title' => $session->title,
                        'scheduled_at' => $session->scheduled_at,
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => now(),
                    'created_at' => now(),
                ]);
            }
        }

        $row = DB::table('gymies_group_sessions as g')
            ->join('gymies_users as u', 'g.trainer_user_id', '=', 'u.id')
            ->where('g.id', (int) $id)
            ->select(['g.*', 'u.display_name as trainer_name'])
            ->first();

        return response()->json([
            'data' => $this->sessionToArray($row),
            'message' => 'Les bevestigd. Betaallinks zijn naar ' . count($participants) . ' deelnemer(s) gestuurd.',
        ]);
    }

    /**
     * Crowdfund: Min_Pax bereikt – les gaat door, alle ingeschrevenen naar payment_pending + notificaties.
     */
    private function autoConfirmSessionMinReached(int $sessionId): void
    {
        // T-019 FIXED: atomaire status-update voorkomt dubbele auto-confirm
        $updated = DB::table('gymies_group_sessions')
            ->where('id', $sessionId)
            ->where('status', 'collecting') // alleen als nog niet bevestigd
            ->update(['status' => 'auto_confirmed', 'updated_at' => now()]);
        if ($updated === 0) {
            return; // al bevestigd door parallel request
        }

        $session = DB::table('gymies_group_sessions')->where('id', $sessionId)->first();
        if (!$session) {
            return;
        }

        $participants = DB::table('gymies_group_session_participants')
            ->where('group_session_id', $sessionId)
            ->whereIn('status', ['pending', 'registered'])
            ->get();

        $priceCents = (int) $session->price_cents;
        $feeCents = self::PLATFORM_FEE_CENTS;
        $payoutCents = max(0, $priceCents - $feeCents);

        $paymentDeadline = now()->addMinutes(60);
        foreach ($participants as $p) {
            // S-034: Auto Confirm zonder deelnemers-check — skip cancelled/refunded deelnemers
            if (in_array($p->status, ['cancelled', 'refunded'], true)) {
                continue;
            }

            $update = [
                'status' => 'payment_pending',
                'amount_cents' => $priceCents,
            ];
            if (Schema::hasColumn('gymies_group_session_participants', 'platform_fee_cents')) {
                $update['platform_fee_cents'] = $feeCents;
                $update['trainer_payout_cents'] = $payoutCents;
            }
            if (Schema::hasColumn('gymies_group_session_participants', 'payment_deadline_at')) {
                $update['payment_deadline_at'] = $paymentDeadline;
            }
            DB::table('gymies_group_session_participants')->where('id', $p->id)->update($update);

            if (Schema::hasTable('gymies_notification_queue')) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $p->client_user_id,
                    'channel' => 'in_app',
                    'event_type' => 'group_session_min_reached_confirmed',
                    'payload_json' => json_encode([
                        'group_session_id' => (string) $sessionId,
                        'title' => $session->title,
                        'scheduled_at' => $session->scheduled_at,
                        'payment_deadline_minutes' => 60,
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => now(),
                    'created_at' => now(),
                ]);
            }
        }

        if (Schema::hasTable('gymies_notification_queue')) {
            DB::table('gymies_notification_queue')->insert([
                'user_id' => (int) $session->trainer_user_id,
                'channel' => 'in_app',
                'event_type' => 'group_session_min_reached_for_trainer',
                'payload_json' => json_encode([
                    'group_session_id' => (string) $sessionId,
                    'title' => $session->title,
                    'scheduled_at' => $session->scheduled_at,
                    'participants_count' => count($participants),
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => now(),
                'created_at' => now(),
            ]);
        }
    }

    /**
     * Trainer: groepsles annuleren.
     */
    public function cancel(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen een groepsles annuleren.'], 403);
        }

        // B23: lockForUpdate voorkomt race condition bij gelijktijdige annuleringsverzoeken.
        DB::beginTransaction();
        try {
            $session = DB::table('gymies_group_sessions')
                ->where('id', (int) $id)
                ->where('trainer_user_id', (int) $user->id)
                ->lockForUpdate()
                ->first();
            if (!$session) {
                DB::rollBack();
                return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
            }

            // Voorkom dubbele annulering bij gelijktijdige requests.
            if (Schema::hasColumn('gymies_group_sessions', 'status') && ($session->status ?? '') === 'cancelled') {
                DB::rollBack();
                return response()->json(['message' => 'Groepsles is al geannuleerd.'], 422);
            }

            $wasConfirmed = (Schema::hasColumn('gymies_group_sessions', 'status') && ($session->status ?? '') === 'confirmed_by_trainer');
            $hadConfirmedParticipants = DB::table('gymies_group_session_participants')
                ->where('group_session_id', (int) $id)
                ->where('status', 'confirmed')
                ->exists();
            if ($wasConfirmed || $hadConfirmedParticipants) {
                // P-FIX-GS-1: Refund all paid participants when trainer cancels
                $confirmedBookings = DB::table('gymies_group_session_participants')
                    ->where('group_session_id', (int) $id)
                    ->where('status', 'confirmed')
                    ->lockForUpdate()
                    ->get();

                foreach ($confirmedBookings as $booking) {
                    $refundAmount = (int) ($booking->amount_cents ?? 0);
                    if ($refundAmount > 0) {
                        // Refund to client wallet
                        DB::table('gymies_users')
                            ->where('id', (int) $booking->client_user_id)
                            ->increment('wallet_balance_cents', $refundAmount);

                        // Mark booking as cancelled with refund info
                        $refundUpdate = [
                            'status' => 'cancelled',
                            'cancelled_by_user_id' => (int) $user->id,
                        ];
                        if (Schema::hasColumn('gymies_group_session_participants', 'cancelled_at')) {
                            $refundUpdate['cancelled_at'] = now();
                        }
                        if (Schema::hasColumn('gymies_group_session_participants', 'refunded_at')) {
                            $refundUpdate['refunded_at'] = now();
                        }
                        if (Schema::hasColumn('gymies_group_session_participants', 'refunded_cents')) {
                            $refundUpdate['refunded_cents'] = $refundAmount;
                        }
                        DB::table('gymies_group_session_participants')
                            ->where('id', (int) $booking->id)
                            ->update($refundUpdate);
                    }
                }

                // Reverse trainer payout if allocated
                if (Schema::hasColumn('gymies_group_sessions', 'trainer_payout_cents')) {
                    $payoutAmount = (int) ($session->trainer_payout_cents ?? 0);
                    if ($payoutAmount > 0 && Schema::hasColumn('gymies_group_sessions', 'payout_processed_at')) {
                        $payoutProcessedAt = $session->payout_processed_at ?? null;
                        if (!empty($payoutProcessedAt)) {
                            DB::table('gymies_users')
                                ->where('id', (int) $session->trainer_user_id)
                                ->decrement('trainer_balance_cents', $payoutAmount);
                        }
                    }
                }

                $penaltyCents = $this->getGroupSessionTrainerPenaltyCents();
                if ($penaltyCents > 0 && Schema::hasTable('gymies_users') && Schema::hasColumn('gymies_users', 'trainer_balance_cents')) {
                    $trainerId = (int) $session->trainer_user_id;
                    DB::table('gymies_users')->where('id', $trainerId)->update([
                        'trainer_balance_cents' => DB::raw('trainer_balance_cents - ' . (int) $penaltyCents),
                        'updated_at' => now(),
                    ]);
                    if (Schema::hasTable('gymies_trainer_penalties')) {
                        $balanceAfter = (int) DB::table('gymies_users')->where('id', $trainerId)->value('trainer_balance_cents');
                        $insert = [
                            'trainer_user_id' => $trainerId,
                            'amount_cents' => -(int) $penaltyCents,
                            'booking_id' => null,
                            'reason' => 'group_session_cancellation',
                            'balance_after_cents' => $balanceAfter,
                            'created_at' => now(),
                        ];
                        if (Schema::hasColumn('gymies_trainer_penalties', 'group_session_id')) {
                            $insert['group_session_id'] = (int) $id;
                        }
                        DB::table('gymies_trainer_penalties')->insert($insert);
                    }
                }
            }
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        $update = ['updated_at' => now()];
        if (Schema::hasColumn('gymies_group_sessions', 'status')) {
            $update['status'] = 'cancelled';
        }
        if (Schema::hasColumn('gymies_group_sessions', 'cancelled_at')) {
            $update['cancelled_at'] = now();
            $update['cancelled_by_user_id'] = (int) $user->id;
        }
        DB::table('gymies_group_sessions')->where('id', (int) $id)->update($update);

        $participants = DB::table('gymies_group_session_participants')
            ->where('group_session_id', (int) $id)
            ->where('status', 'confirmed')
            ->get();
        foreach ($participants as $p) {
            if (Schema::hasColumn('gymies_group_session_participants', 'cancelled_at')) {
                DB::table('gymies_group_session_participants')->where('id', $p->id)->update([
                    'status' => 'cancelled',
                    'cancelled_at' => now(),
                    'cancelled_by_user_id' => (int) $user->id,
                ]);
            }
            if (Schema::hasTable('gymies_notification_queue')) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $p->client_user_id,
                    'channel' => 'in_app',
                    'event_type' => 'group_session_cancelled',
                    'payload_json' => json_encode([
                        'group_session_id' => (string) $id,
                        'title' => $session->title,
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => now(),
                    'created_at' => now(),
                ]);
            }
        }

        DB::commit();
        return response()->json(['message' => 'Groepsles is geannuleerd.']);
    }

    /**
     * Trainer: zoek vervanger (Emergency Sub). Stuurt SOS naar beschikbare trainers in de buurt.
     * Als een vervanger accepteert, vervalt de boete en gaat de payout naar de vervanger.
     */
    public function requestSubstitute(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen een vervanger zoeken.'], 403);
        }

        $session = DB::table('gymies_group_sessions')->where('id', (int) $id)->where('trainer_user_id', (int) $user->id)->first();
        if (!$session) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }
        if (!in_array($session->status ?? '', ['confirmed_by_trainer', 'collecting'], true)) {
            return response()->json(['message' => 'Alleen actieve lessen kunnen een vervanger krijgen.'], 422);
        }
        if (!Schema::hasTable('gymies_substitute_requests')) {
            return response()->json(['message' => 'Substitute-systeem niet beschikbaar. Draai migratie.'], 503);
        }

        $existing = DB::table('gymies_substitute_requests')
            ->where('group_session_id', (int) $id)
            ->whereIn('status', ['open', 'accepted'])
            ->first();
        if ($existing) {
            return response()->json(['message' => 'Er loopt al een vervangingsverzoek voor deze les.'], 422);
        }

        $request->validate(['reason' => 'nullable|string|max:500']);

        $scheduledAt = Carbon::parse($session->scheduled_at);
        $expiresAt = $scheduledAt->copy()->subHour(); // tot 1u voor les

        $subId = DB::table('gymies_substitute_requests')->insertGetId([
            'group_session_id' => (int) $id,
            'original_trainer_id' => (int) $user->id,
            'specialty_filter' => $session->title ?? null,
            'reason' => $request->input('reason'),
            'expires_at' => $expiresAt,
            'created_at' => now(),
        ]);

        // SOS naar beschikbare trainers (zelfde specialisatie of alle trainers)
        $candidates = DB::table('gymies_users')
            ->where('role', 'trainer')
            ->where('id', '!=', (int) $user->id)
            ->where('is_suspended', 0)
            ->pluck('id');

        if (Schema::hasTable('gymies_notification_queue')) {
            foreach ($candidates as $trainerId) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $trainerId,
                    'channel' => 'in_app',
                    'event_type' => 'substitute_request',
                    'payload_json' => json_encode([
                        'substitute_request_id' => $subId,
                        'group_session_id' => (string) $id,
                        'title' => $session->title,
                        'scheduled_at' => $session->scheduled_at,
                        'price_cents' => (int) $session->price_cents,
                        'message' => 'Noodvervanging: een trainer kan niet, kun jij inspringen?',
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => now(),
                    'created_at' => now(),
                ]);
            }
        }

        return response()->json([
            'ok' => true,
            'substitute_request_id' => $subId,
            'candidates_notified' => $candidates->count(),
            'expires_at' => $expiresAt->toIso8601String(),
            'message' => 'Vervangingsverzoek verstuurd naar ' . $candidates->count() . ' trainers.',
        ]);
    }

    /**
     * Trainer: accepteer vervangingsverzoek. Neemt de les over.
     */
    public function acceptSubstitute(Request $request, string $requestId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen een vervanging accepteren.'], 403);
        }

        if (!Schema::hasTable('gymies_substitute_requests')) {
            return response()->json(['message' => 'Substitute-systeem niet beschikbaar.'], 503);
        }

        $sub = DB::table('gymies_substitute_requests')->where('id', (int) $requestId)->where('status', 'open')->first();
        if (!$sub) {
            return response()->json(['message' => 'Vervangingsverzoek niet gevonden of al ingevuld.'], 404);
        }
        if ((int) $sub->original_trainer_id === (int) $user->id) {
            return response()->json(['message' => 'Je kunt je eigen les niet overnemen.'], 422);
        }
        if ($sub->expires_at !== null && Carbon::parse($sub->expires_at)->isPast()) {
            DB::table('gymies_substitute_requests')->where('id', (int) $requestId)->update(['status' => 'expired']);
            return response()->json(['message' => 'Verzoek is verlopen.'], 422);
        }

        DB::beginTransaction();
        try {
            // S-033: Race Condition acceptSubstitute — vergrendel sessiegrij
            $sessionId = (int) $sub->group_session_id;
            $session = DB::table('gymies_group_sessions')
                ->where('id', $sessionId)
                ->lockForUpdate()
                ->first();

            if (!$session) {
                DB::rollBack();
                return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
            }

            // Controleer of de les niet al overgenomen is door een ander
            if (!empty($session->trainer_user_id) && (int) $session->trainer_user_id !== (int) $sub->original_trainer_id) {
                DB::rollBack();
                return response()->json(['message' => 'Deze les is al overgenomen door een ander.'], 409);
            }

            // Mark request as accepted
            DB::table('gymies_substitute_requests')->where('id', (int) $requestId)->update([
                'substitute_trainer_id' => (int) $user->id,
                'status' => 'accepted',
                'accepted_at' => now(),
            ]);

            // Transfer session to substitute trainer
            DB::table('gymies_group_sessions')->where('id', $sessionId)->update([
                'trainer_user_id' => (int) $user->id,
                'updated_at' => now(),
            ]);

            // Reverse penalty for original trainer if one was applied
            $originalTrainerId = (int) $sub->original_trainer_id;
            if (Schema::hasTable('gymies_trainer_penalties')) {
                $penalty = DB::table('gymies_trainer_penalties')
                    ->where('group_session_id', $sessionId)
                    ->where('trainer_user_id', $originalTrainerId)
                    ->where('reason', 'group_session_cancellation')
                    ->first();
                if ($penalty && Schema::hasColumn('gymies_users', 'trainer_balance_cents')) {
                    $refundCents = abs((int) $penalty->amount_cents);
                    DB::table('gymies_users')->where('id', $originalTrainerId)->increment('trainer_balance_cents', $refundCents);
                    DB::table('gymies_trainer_penalties')->insert([
                        'trainer_user_id' => $originalTrainerId,
                        'amount_cents' => $refundCents,
                        'booking_id' => null,
                        'reason' => 'group_session_substitute_found',
                        'balance_after_cents' => (int) DB::table('gymies_users')->where('id', $originalTrainerId)->value('trainer_balance_cents'),
                        'group_session_id' => $sessionId,
                        'created_at' => now(),
                    ]);
                }
            }

            // Notify participants + original trainer
            if (Schema::hasTable('gymies_notification_queue')) {
                $participants = DB::table('gymies_group_session_participants')
                    ->where('group_session_id', $sessionId)
                    ->whereIn('status', ['registered', 'payment_pending', 'confirmed'])
                    ->pluck('client_user_id');
                foreach ($participants as $clientId) {
                    DB::table('gymies_notification_queue')->insert([
                        'user_id' => (int) $clientId,
                        'channel' => 'in_app',
                        'event_type' => 'group_session_substitute_trainer',
                        'payload_json' => json_encode([
                            'group_session_id' => (string) $sessionId,
                            'new_trainer_name' => $user->display_name ?? 'Vervanger',
                            'message' => 'Je groepsles wordt overgenomen door een andere trainer. De les gaat gewoon door!',
                        ], JSON_UNESCAPED_UNICODE),
                        'scheduled_for' => now(),
                        'created_at' => now(),
                    ]);
                }
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => $originalTrainerId,
                    'channel' => 'in_app',
                    'event_type' => 'substitute_accepted',
                    'payload_json' => json_encode([
                        'group_session_id' => (string) $sessionId,
                        'substitute_name' => $user->display_name ?? 'Vervanger',
                        'message' => 'Goed nieuws: je les is overgenomen! Boete is teruggedraaid.',
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => now(),
                    'created_at' => now(),
                ]);
            }

            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        return response()->json([
            'ok' => true,
            'message' => 'Je hebt de les overgenomen! De payout gaat naar jou.',
        ]);
    }

    /**
     * Klant: inschrijven ("Ik doe mee") – status registered of waitlist.
     */
    public function register(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'klant') {
            return response()->json(['message' => 'Alleen klanten kunnen zich inschrijven.'], 403);
        }

        $session = DB::table('gymies_group_sessions')->where('id', (int) $id)->first();
        if (!$session) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }
        $statusCol = Schema::hasColumn('gymies_group_sessions', 'status');
        if ($statusCol && !in_array($session->status ?? 'draft', ['collecting', 'confirmed_by_trainer'], true)) {
            return response()->json(['message' => 'Deze les neemt geen inschrijvingen meer aan.'], 422);
        }
        if ($session->scheduled_at && Carbon::parse($session->scheduled_at)->isPast()) {
            return response()->json(['message' => 'Deze les is al geweest.'], 422);
        }

        $participantId = null;
        $participantStatus = 'registered';
        $isWaitlist = false;
        $existingStatus = null;

        DB::beginTransaction();
        try {
            // B39: Vergrendel de sessiegrij zodat gelijktijdige inschrijvingen niet beide
            // de capaciteitscheck doorstaan (overbooking race condition).
            DB::table('gymies_group_sessions')->where('id', (int) $id)->lockForUpdate()->value('id');

            // T-003 FIXED: duplicate insert voorkomen binnen transaction
            $alreadyIn = DB::table('gymies_group_session_participants')
                ->where('group_session_id', (int) $id)
                ->where('client_user_id', (int) $user->id)
                ->lockForUpdate()
                ->exists();
            if ($alreadyIn) {
                DB::rollBack();
                return response()->json(['message' => 'Je bent al ingeschreven voor deze sessie.'], 409);
            }

            $count = (int) DB::table('gymies_group_session_participants')
                ->where('group_session_id', (int) $id)
                ->whereIn('status', ['pending', 'registered', 'payment_pending', 'confirmed'])
                ->count();
            $maxParticipants = (int) $session->max_participants;
            $isWaitlist = $count >= $maxParticipants;
            // Wachtlijst is klant-feature: standaard aan (waitlist_enabled=1). Alleen als trainer expliciet uitzet: vol = geen inschrijving meer.
            if ($isWaitlist && Schema::hasColumn('gymies_group_sessions', 'waitlist_enabled')) {
                $waitlistOn = (int) ($session->waitlist_enabled ?? 1) === 1;
                if (!$waitlistOn) {
                    DB::rollBack();
                    return response()->json(['message' => 'Deze les is vol. Er is geen wachtlijst voor deze les.'], 422);
                }
            }
            $participantStatus = $isWaitlist ? 'waitlist' : 'registered';
            if (!Schema::hasColumn('gymies_group_session_participants', 'registered')) {
                $participantStatus = $isWaitlist ? 'waitlist' : 'pending';
            }

            $insertData = [
                'group_session_id' => (int) $id,
                'client_user_id' => (int) $user->id,
                'status' => $participantStatus,
                'amount_cents' => null,
                'paid_at' => null,
                'created_at' => now(),
            ];
            DB::table('gymies_group_session_participants')->insert($insertData);
            $participantId = (int) DB::getPdo()->lastInsertId();
            DB::commit();
        } catch (\Throwable $e) {
            DB::rollBack();
            throw $e;
        }

        $countAfter = (int) DB::table('gymies_group_session_participants')
            ->where('group_session_id', (int) $id)
            ->whereIn('status', ['pending', 'registered', 'payment_pending', 'confirmed'])
            ->count();
        $minParticipants = (int) ($session->min_participants ?? $session->max_participants ?? 1);
        $statusCol = Schema::hasColumn('gymies_group_sessions', 'status');
        if ($statusCol && ($session->status ?? '') === 'collecting' && $countAfter >= $minParticipants) {
            $this->autoConfirmSessionMinReached((int) $id);
            $session = DB::table('gymies_group_sessions')->where('id', (int) $id)->first();
        }

        if (Schema::hasTable('gymies_notification_queue')) {
            DB::table('gymies_notification_queue')->insert([
                [
                    'user_id' => (int) $session->trainer_user_id,
                    'channel' => 'in_app',
                    'event_type' => 'group_session_new_registration',
                    'payload_json' => json_encode([
                        'group_session_id' => (string) $id,
                        'title' => $session->title,
                        'client_user_id' => (string) $user->id,
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => now(),
                    'created_at' => now(),
                ],
            ]);
        }

        $row = DB::table('gymies_group_sessions as g')
            ->join('gymies_users as u', 'g.trainer_user_id', '=', 'u.id')
            ->where('g.id', (int) $id)
            ->select(['g.*', 'u.display_name as trainer_name'])
            ->first();

        $sessionJustConfirmed = $statusCol && ($session->status ?? '') === 'confirmed_by_trainer';
        $responseStatus = $sessionJustConfirmed ? 'payment_pending' : $participantStatus;
        $message = $isWaitlist
            ? 'Je staat op de wachtlijst.'
            : ($sessionJustConfirmed
                ? 'Het minimum aantal deelnemers is bereikt. De les gaat door! Betaal nu om je plek te bevestigen.'
                : 'Je bent ingeschreven. Je ontvangt een betaallink zodra het minimum aantal deelnemers is bereikt of de trainer bevestigt.');

        return response()->json([
            'data' => [
                'participant_id' => (string) $participantId,
                'status' => $responseStatus,
                'session' => $this->sessionToArray($row),
            ],
            'message' => $message,
        ], 201);
    }

    /**
     * Klant: inschrijving annuleren (vóór betaling kosteloos).
     */
    public function cancelRegistration(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $session = DB::table('gymies_group_sessions')->where('id', (int) $id)->first();
        if (!$session) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }

        $participant = DB::table('gymies_group_session_participants')
            ->where('group_session_id', (int) $id)
            ->where('client_user_id', (int) $user->id)
            ->first();
        if (!$participant) {
            return response()->json(['message' => 'Je bent niet ingeschreven voor deze les.'], 404);
        }
        if (in_array($participant->status, ['cancelled'], true)) {
            return response()->json(['message' => 'Deze inschrijving is al geannuleerd.'], 422);
        }
        if ($participant->status === 'confirmed' && !empty($participant->paid_at)) {
            return response()->json(['message' => 'Betaalde inschrijvingen annuleren kan via de annuleerflow (restitutie volgens beleid).'], 422);
        }

        $update = ['status' => 'cancelled'];
        if (Schema::hasColumn('gymies_group_session_participants', 'cancelled_at')) {
            $update['cancelled_at'] = now();
            $update['cancelled_by_user_id'] = (int) $user->id;
        }
        DB::table('gymies_group_session_participants')->where('id', $participant->id)->update($update);

        $this->promoteFirstWaitlistForSession((int) $id);

        return response()->json(['message' => 'Inschrijving geannuleerd.']);
    }

    /**
     * Na een vrijgekomen plek: eerste wachtlijst-deelnemer naar registered (of payment_pending) + notificatie.
     */
    private function promoteFirstWaitlistForSession(int $sessionId): void
    {
        $session = DB::table('gymies_group_sessions')->where('id', $sessionId)->first();
        if (!$session) {
            return;
        }
        $statusCol = Schema::hasColumn('gymies_group_sessions', 'status');
        $sessionStatus = $statusCol ? ($session->status ?? 'draft') : 'draft';
        if (!in_array($sessionStatus, ['collecting', 'confirmed_by_trainer'], true)) {
            return;
        }

        $first = DB::table('gymies_group_session_participants')
            ->where('group_session_id', $sessionId)
            ->where('status', 'waitlist')
            ->orderBy('created_at')
            ->first();
        if (!$first) {
            return;
        }

        $newStatus = $sessionStatus === 'confirmed_by_trainer' ? 'payment_pending' : (Schema::hasColumn('gymies_group_session_participants', 'registered') ? 'registered' : 'pending');
        $priceCents = (int) $session->price_cents;
        $feeCents = self::PLATFORM_FEE_CENTS;
        $payoutCents = max(0, $priceCents - $feeCents);

        $update = [
            'status' => $newStatus,
            'amount_cents' => $priceCents,
        ];
        if (Schema::hasColumn('gymies_group_session_participants', 'platform_fee_cents')) {
            $update['platform_fee_cents'] = $feeCents;
            $update['trainer_payout_cents'] = $payoutCents;
        }
        if ($sessionStatus === 'confirmed_by_trainer' && Schema::hasColumn('gymies_group_session_participants', 'claim_deadline_at')) {
            $update['claim_deadline_at'] = now()->addMinutes(self::WAITLIST_CLAIM_MINUTES);
        }
        DB::table('gymies_group_session_participants')->where('id', $first->id)->update($update);

        if (Schema::hasTable('gymies_notification_queue')) {
            DB::table('gymies_notification_queue')->insert([
                'user_id' => (int) $first->client_user_id,
                'channel' => 'in_app',
                'event_type' => 'group_session_waitlist_spot_available',
                'payload_json' => json_encode([
                    'group_session_id' => (string) $sessionId,
                    'title' => $session->title,
                    'scheduled_at' => $session->scheduled_at,
                    'claim_minutes' => self::WAITLIST_CLAIM_MINUTES,
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => now(),
                'created_at' => now(),
            ]);
        }
    }

    /**
     * Klant: mijn groepsles-inschrijvingen.
     */
    public function myRegistrations(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_group_session_participants') || !Schema::hasTable('gymies_group_sessions')) {
            return response()->json(['data' => []]);
        }

        $select = [
            'p.id as participant_id',
            'p.group_session_id',
            'p.status as participant_status',
            'p.amount_cents',
            'p.paid_at',
            'p.created_at as registered_at',
            'g.title',
            'g.scheduled_at',
            'g.duration_minutes',
            'g.max_participants',
            'g.price_cents',
            'g.location_type',
            'u.display_name as trainer_name',
            'g.trainer_user_id',
        ];
        if (Schema::hasColumn('gymies_group_sessions', 'location_notes')) {
            $select[] = 'g.location_notes';
        }
        if (Schema::hasColumn('gymies_group_sessions', 'status')) {
            $select[] = 'g.status as session_status';
        }

        $rows = DB::table('gymies_group_session_participants as p')
            ->join('gymies_group_sessions as g', 'p.group_session_id', '=', 'g.id')
            ->join('gymies_users as u', 'g.trainer_user_id', '=', 'u.id')
            ->where('p.client_user_id', (int) $user->id)
            ->where('g.scheduled_at', '>', now()->toDateTimeString())
            ->whereNotIn('p.status', ['cancelled'])
            ->select($select)
            ->orderBy('g.scheduled_at')
            ->get();

        $data = $rows->map(function ($r) {
            $participantsCount = (int) DB::table('gymies_group_session_participants')
                ->where('group_session_id', $r->group_session_id)
                ->whereNotIn('status', ['cancelled'])
                ->count();
            return [
                'participant_id' => (string) $r->participant_id,
                'group_session_id' => (string) $r->group_session_id,
                'participant_status' => (string) $r->participant_status,
                'amount_cents' => $r->amount_cents ? (int) $r->amount_cents : null,
                'paid_at' => $r->paid_at,
                'registered_at' => $r->registered_at,
                'title' => (string) $r->title,
                'scheduled_at' => $r->scheduled_at,
                'duration_minutes' => (int) $r->duration_minutes,
                'max_participants' => (int) $r->max_participants,
                'participants_count' => $participantsCount,
                'price_cents' => (int) $r->price_cents,
                'location_type' => $r->location_type ? (string) $r->location_type : null,
                'location_notes' => isset($r->location_notes) ? (string) $r->location_notes : null,
                'session_status' => (string) ($r->session_status ?? 'collecting'),
                'trainer_name' => (string) ($r->trainer_name ?? 'Trainer'),
                'trainer_user_id' => (string) $r->trainer_user_id,
            ];
        })->all();

        return response()->json(['data' => $data]);
    }

    /**
     * Trainer: deelnemers van een groepsles.
     */
    public function participants(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen deelnemers bekijken.'], 403);
        }

        $session = DB::table('gymies_group_sessions')->where('id', (int) $id)->where('trainer_user_id', (int) $user->id)->first();
        if (!$session) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }

        // S-073: Missing Pagination — voeg limit toe aan deelnemerslijst
        $limit = (int) ($request->query('limit', 200));
        $limit = max(1, min($limit, 500)); // Clamp tussen 1 en 500

        // T-007 FIXED: cursor-based pagination voor participants list
        $page   = max(1, (int)($request->query('page', 1)));
        $perPage = min((int)($request->query('limit', 50)), 100);
        $offset = ($page - 1) * $perPage;

        $participantCols = ['p.id', 'p.client_user_id', 'p.status', 'p.amount_cents', 'p.paid_at', 'p.created_at', 'u.display_name as client_name'];
        if (Schema::hasColumn('gymies_group_session_participants', 'attended')) {
            $participantCols[] = 'p.attended';
        }
        $rows = DB::table('gymies_group_session_participants as p')
            ->join('gymies_users as u', 'p.client_user_id', '=', 'u.id')
            ->join('gymies_group_sessions as g', 'p.group_session_id', '=', 'g.id')
            ->where('p.group_session_id', (int) $id)
            // T-006 FIXED: trainer mag alleen participants van eigen sessies zien
            ->where('g.trainer_user_id', (int) $user->id)
            ->select($participantCols)
            ->orderBy('p.created_at')
            ->limit($perPage)->offset($offset)
            ->get();

        $data = $rows->map(function ($r) {
            $item = [
                'id' => (string) $r->id,
                'client_user_id' => (string) $r->client_user_id,
                'client_name' => (string) ($r->client_name ?? 'Klant'),
                'status' => (string) $r->status,
                'amount_cents' => $r->amount_cents ? (int) $r->amount_cents : null,
                'paid_at' => $r->paid_at,
                'created_at' => $r->created_at,
            ];
            if (property_exists($r, 'attended') && $r->attended !== null) {
                $item['attended'] = (bool) $r->attended;
            }
            return $item;
        })->all();

        return response()->json(['data' => $data]);
    }

    /**
     * Trainer: aanwezigheid registreren voor een deelnemer (attended = true/false).
     */
    public function markParticipantAttended(Request $request, string $id, string $participantId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers kunnen aanwezigheid registreren.'], 403);
        }
        if (!Schema::hasColumn('gymies_group_session_participants', 'attended')) {
            return response()->json(['message' => 'Aanwezigheid wordt niet ondersteund.'], 503);
        }

        $session = DB::table('gymies_group_sessions')->where('id', (int) $id)->where('trainer_user_id', (int) $user->id)->first();
        if (!$session) {
            return response()->json(['message' => 'Groepsles niet gevonden.'], 404);
        }

        $participant = DB::table('gymies_group_session_participants')
            ->where('id', (int) $participantId)
            ->where('group_session_id', (int) $id)
            ->first();
        if (!$participant) {
            return response()->json(['message' => 'Deelnemer niet gevonden.'], 404);
        }

        $attended = $request->boolean('attended');
        DB::table('gymies_group_session_participants')->where('id', (int) $participantId)->update(['attended' => $attended ? 1 : 0]);

        $row = DB::table('gymies_group_session_participants as p')
            ->join('gymies_users as u', 'p.client_user_id', '=', 'u.id')
            ->where('p.id', (int) $participantId)
            ->select(['p.id', 'p.client_user_id', 'p.status', 'p.amount_cents', 'p.paid_at', 'p.attended', 'p.created_at', 'u.display_name as client_name'])
            ->first();

        return response()->json([
            'data' => [
                'id' => (string) $row->id,
                'client_user_id' => (string) $row->client_user_id,
                'client_name' => (string) ($row->client_name ?? 'Klant'),
                'status' => (string) $row->status,
                'amount_cents' => $row->amount_cents ? (int) $row->amount_cents : null,
                'paid_at' => $row->paid_at,
                'attended' => (bool) $row->attended,
                'created_at' => $row->created_at,
            ],
        ]);
    }

    /**
     * Houdt alleen sessies waarvan de gekoppelde trainerlocatie (of primaire locatie) binnen radius_km valt.
     * Coördinaten: eerst trainer_location_id van de sessie, anders primaire trainerlocatie (zelfde idee als trainerzoeken).
     * Sessies zonder bruikbare lat/lng vallen weg zolang deze filter actief is.
     *
     * @param \Illuminate\Support\Collection<int, object> $rows
     * @return \Illuminate\Support\Collection<int, object>
     */
    private function filterGroupSessionsByRadius($rows, float $userLat, float $userLng, float $radiusKm)
    {
        if ($rows->isEmpty()) {
            return $rows;
        }

        $trainerIds = $rows->pluck('trainer_user_id')->map(static fn ($id) => (int) $id)->unique()->values()->all();
        if ($trainerIds === []) {
            return collect();
        }

        $locs = DB::table('gymies_trainer_locations')
            ->whereIn('trainer_user_id', $trainerIds)
            ->whereNotNull('latitude')
            ->whereNotNull('longitude')
            ->orderByDesc('is_primary')
            ->get(['id', 'trainer_user_id', 'latitude', 'longitude']);

        $coordsByLocationId = [];
        $primaryCoordsByTrainer = [];
        foreach ($locs as $loc) {
            $tid = (int) $loc->trainer_user_id;
            $coords = [(float) $loc->latitude, (float) $loc->longitude];
            $coordsByLocationId[(int) $loc->id] = $coords;
            if (!isset($primaryCoordsByTrainer[$tid])) {
                $primaryCoordsByTrainer[$tid] = $coords;
            }
        }

        $userLatRad = deg2rad($userLat);
        $userLngRad = deg2rad($userLng);
        $earthKm = 6371.0;

        $annotated = $rows->map(function ($r) use ($coordsByLocationId, $primaryCoordsByTrainer, $userLatRad, $userLngRad, $earthKm) {
            $coords = null;
            $tlid = $r->trainer_location_id ?? null;
            if ($tlid !== null && (int) $tlid > 0) {
                $coords = $coordsByLocationId[(int) $tlid] ?? null;
            }
            if ($coords === null) {
                $coords = $primaryCoordsByTrainer[(int) $r->trainer_user_id] ?? null;
            }
            $r->__distance_km = null;
            if ($coords !== null) {
                $latRad = deg2rad($coords[0]);
                $lngRad = deg2rad($coords[1]);
                $distance = $earthKm * 2 * asin(sqrt(
                    pow(sin(($userLatRad - $latRad) / 2), 2) +
                    cos($userLatRad) * cos($latRad) * pow(sin(($userLngRad - $lngRad) / 2), 2)
                ));
                // S-087: NaN/Inf GPS Coördinaten — valideer resultaat
                if (is_finite($distance)) {
                    $r->__distance_km = $distance;
                }
            }
            return $r;
        });

        $filtered = $annotated->filter(static function ($r) use ($radiusKm) {
            return $r->__distance_km !== null && $r->__distance_km <= $radiusKm;
        });

        $sorted = $filtered->sort(function ($a, $b) {
            $cmp = ($a->__distance_km <=> $b->__distance_km);
            if ($cmp !== 0) {
                return $cmp;
            }
            return strcmp((string) $a->scheduled_at, (string) $b->scheduled_at);
        })->values();

        foreach ($sorted as $r) {
            unset($r->__distance_km);
        }

        return $sorted;
    }

    /**
     * S-087: NaN/Inf GPS Coördinaten — valideer dat GPS-berekening eindige waarden oplevert.
     * Dit voorkomt dat NaN/Inf-waarden in afstandsberekeningen eindigen.
     */
    private function validateGpsCalculationResult($result): bool
    {
        if ($result === null) {
            return true; // null is OK
        }
        if (!is_numeric($result)) {
            return false;
        }
        return is_finite($result);
    }

    private function sessionToArray($r): array
    {
        $arr = [
            'id' => (string) $r->id,
            'trainer_user_id' => (string) $r->trainer_user_id,
            'trainer_name' => (string) ($r->trainer_name ?? 'Trainer'),
            'title' => (string) $r->title,
            'description' => $r->description ? (string) $r->description : null,
            'scheduled_at' => $r->scheduled_at,
            'duration_minutes' => (int) $r->duration_minutes,
            'max_participants' => (int) $r->max_participants,
            'price_cents' => (int) $r->price_cents,
            'location_type' => $r->location_type ? (string) $r->location_type : null,
            'trainer_location_id' => $r->trainer_location_id ? (string) $r->trainer_location_id : null,
            'gym_location_id' => (property_exists($r, 'gym_location_id') && $r->gym_location_id) ? (string) $r->gym_location_id : null,
        ];
        if (Schema::hasColumn('gymies_group_sessions', 'status')) {
            $arr['status'] = (string) ($r->status ?? 'draft');
        }
        if (property_exists($r, 'min_participants')) {
            $arr['min_participants'] = (int) ($r->min_participants ?? 1);
        }
        if (property_exists($r, 'location_notes')) {
            $arr['location_notes'] = $r->location_notes ? (string) $r->location_notes : null;
        }
        if (Schema::hasColumn('gymies_group_sessions', 'waitlist_enabled')) {
            $arr['waitlist_enabled'] = (int) ($r->waitlist_enabled ?? 1) === 1;
        }
        return $arr;
    }
}
