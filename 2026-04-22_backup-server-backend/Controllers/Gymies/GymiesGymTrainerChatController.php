<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Events\Gymies\GymiesChatMessageSent;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use App\Http\Controllers\Gymies\GymiesPlanManager;

/**
 * Trainer-trainer chat binnen dezelfde gym (Elite).
 * Trainers kunnen onderling snel communiceren via de app.
 */
final class GymiesGymTrainerChatController extends Controller
{
    /**
     * Lijst conversaties van de ingelogde trainer met andere gym-trainers.
     */
    public function index(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        if (!Schema::hasTable('gymies_trainer_trainer_conversations')) {
            return response()->json(['data' => []]);
        }

        $userId = (int) $ctx['user_id'];
        $orgId = (int) $ctx['organisation_id'];

        $lastMsgSub = DB::table('gymies_trainer_trainer_messages')
            ->select('conversation_id', DB::raw('MAX(id) as last_message_id'))
            ->groupBy('conversation_id');

        $rows = DB::table('gymies_trainer_trainer_conversations as c')
            ->leftJoinSub($lastMsgSub, 'lm', fn ($j) => $j->on('lm.conversation_id', '=', 'c.id'))
            ->leftJoin('gymies_trainer_trainer_messages as m', 'm.id', '=', 'lm.last_message_id')
            ->where('c.organisation_id', $orgId)
            ->where(function ($q) use ($userId) {
                $q->where('c.trainer_a_user_id', $userId)->orWhere('c.trainer_b_user_id', $userId);
            })
            ->orderByDesc('c.updated_at')
            ->select(
                'c.id',
                'c.trainer_a_user_id',
                'c.trainer_b_user_id',
                'c.updated_at',
                'm.body as last_message_body',
                'm.created_at as last_message_at',
            )
            ->get();

        $otherIds = $rows->map(fn ($r) => (int) $r->trainer_a_user_id === $userId ? (int) $r->trainer_b_user_id : (int) $r->trainer_a_user_id)->unique()->all();
        $users = $otherIds !== [] ? DB::table('gymies_users')->whereIn('id', $otherIds)->pluck('display_name', 'id')->all() : [];

        $data = $rows->map(function ($r) use ($userId, $users) {
            $otherId = (int) $r->trainer_a_user_id === $userId ? (int) $r->trainer_b_user_id : (int) $r->trainer_a_user_id;
            return [
                'id' => (string) $r->id,
                'other_trainer_user_id' => (string) $otherId,
                'other_trainer_name' => (string) ($users[$otherId] ?? 'Trainer'),
                'last_message_body' => $r->last_message_body ? (string) $r->last_message_body : null,
                'last_message_at' => $r->last_message_at,
                'updated_at' => $r->updated_at,
            ];
        })->all();

        return response()->json(['data' => $data]);
    }

    /**
     * Conversatie aanmaken of bestaande ophalen met een andere gym-trainer.
     */
    public function ensure(Request $request): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        if (!Schema::hasTable('gymies_trainer_trainer_conversations')) {
            return response()->json(['message' => 'Trainer-chat niet beschikbaar.'], 503);
        }

        $request->validate(['trainer_user_id' => 'required|integer|min:1']);
        $userId = (int) $ctx['user_id'];
        $orgId = (int) $ctx['organisation_id'];
        $otherId = (int) $request->input('trainer_user_id');

        if ($otherId === $userId) {
            return response()->json(['message' => 'Je kunt niet met jezelf chatten.'], 422);
        }

        $isMember = DB::table('gymies_organisation_trainers')
            ->where('organisation_id', $orgId)
            ->where('trainer_user_id', $otherId)
            ->where('status', 'active')
            ->exists();
        if (!$isMember) {
            return response()->json(['message' => 'Trainer niet gevonden binnen deze gym.'], 404);
        }

        $a = min($userId, $otherId);
        $b = max($userId, $otherId);

        // T-045 FIXED: cross-gym conversation access voorkomen
        $conv = DB::table('gymies_trainer_trainer_conversations')
            ->where('trainer_a_user_id', $a)
            ->where('trainer_b_user_id', $b)
            ->where('organisation_id', $orgId)
            ->first();

        if ($conv) {
            $other = DB::table('gymies_users')->where('id', $otherId)->first();
            return response()->json([
                'data' => [
                    'id' => (string) $conv->id,
                    'other_trainer_user_id' => (string) $otherId,
                    'other_trainer_name' => (string) ($other->display_name ?? 'Trainer'),
                ],
            ]);
        }

        $id = DB::table('gymies_trainer_trainer_conversations')->insertGetId([
            'trainer_a_user_id' => $a,
            'trainer_b_user_id' => $b,
            'organisation_id' => $orgId,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $other = DB::table('gymies_users')->where('id', $otherId)->first();
        return response()->json([
            'data' => [
                'id' => (string) $id,
                'other_trainer_user_id' => (string) $otherId,
                'other_trainer_name' => (string) ($other->display_name ?? 'Trainer'),
            ],
        ], 201);
    }

    /**
     * Berichten van één conversatie.
     */
    public function messages(Request $request, string $conversationId): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        if (!Schema::hasTable('gymies_trainer_trainer_messages')) {
            return response()->json(['data' => []]);
        }

        $userId = (int) $ctx['user_id'];
        $orgId = (int) $ctx['organisation_id'];
        $convId = (int) $conversationId;

        $conv = DB::table('gymies_trainer_trainer_conversations')
            ->where('id', $convId)
            ->where('organisation_id', $orgId)
            ->where(function ($q) use ($userId) {
                $q->where('trainer_a_user_id', $userId)->orWhere('trainer_b_user_id', $userId);
            })
            ->first();
        if (!$conv) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $rows = DB::table('gymies_trainer_trainer_messages as m')
            ->join('gymies_users as u', 'u.id', '=', 'm.from_user_id')
            ->where('m.conversation_id', $convId)
            ->orderBy('m.created_at')
            ->select('m.id', 'm.from_user_id', 'm.body', 'm.created_at', 'u.display_name as from_name')
            ->get();

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'from_user_id' => (string) $r->from_user_id,
            'from_name' => (string) ($r->from_name ?? 'Trainer'),
            'body' => (string) $r->body,
            'created_at' => $r->created_at,
            'is_own' => (int) $r->from_user_id === $userId,
        ])->all();

        return response()->json(['data' => $data]);
    }

    /**
     * Bericht versturen.
     */
    public function send(Request $request, string $conversationId): JsonResponse
    {
        $ctx = $this->requireGymMember($request);
        if ($ctx instanceof JsonResponse) {
            return $ctx;
        }

        if (!Schema::hasTable('gymies_trainer_trainer_messages')) {
            return response()->json(['message' => 'Trainer-chat niet beschikbaar.'], 503);
        }

        $request->validate(['body' => 'required|string|max:5000']);

        $userId = (int) $ctx['user_id'];
        $orgId = (int) $ctx['organisation_id'];
        $convId = (int) $conversationId;
        $body = trim((string) $request->input('body'));

        $conv = DB::table('gymies_trainer_trainer_conversations')
            ->where('id', $convId)
            ->where('organisation_id', $orgId)
            ->where(function ($q) use ($userId) {
                $q->where('trainer_a_user_id', $userId)->orWhere('trainer_b_user_id', $userId);
            })
            ->first();
        if (!$conv) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $receiverId = (int) $conv->trainer_a_user_id === $userId
            ? (int) $conv->trainer_b_user_id
            : (int) $conv->trainer_a_user_id;

        $msgId = (int) DB::table('gymies_trainer_trainer_messages')->insertGetId([
            'conversation_id' => $convId,
            'from_user_id' => $userId,
            'body' => $body,
            'created_at' => now(),
        ]);

        DB::table('gymies_trainer_trainer_conversations')
            ->where('id', $convId)
            ->update(['updated_at' => now()]);

        $preview = mb_substr($body, 0, 200);
        try {
            if (class_exists(GymiesChatMessageSent::class)) {
                event(new GymiesChatMessageSent(
                    $receiverId,
                    (string) $convId,
                    (string) $msgId,
                    (string) $userId,
                    $preview,
                    now()->toIso8601String(),
                    'gym_trainer',
                ));
            }
        } catch (\Throwable $e) {
            // Broadcasting niet geconfigureerd
        }

        return response()->json(['data' => ['id' => (string) $msgId]], 201);
    }

    /**
     * @param array<string>|null $allowedRoles
     * @return array<string,mixed>|JsonResponse
     */
    private function requireGymMember(Request $request, ?array $allowedRoles = null)
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers met gym-toegang.'], 403);
        }

        $memberQuery = DB::table('gymies_organisation_members')
            ->join('gymies_organisations', 'gymies_organisations.id', '=', 'gymies_organisation_members.organisation_id')
            ->where('gymies_organisation_members.user_id', (int) $user->id)
            ->select(
                'gymies_organisation_members.organisation_id',
                'gymies_organisation_members.role as member_role',
                'gymies_organisations.name as organisation_name',
            );
        if (Schema::hasColumn('gymies_organisation_members', 'status')) {
            $memberQuery->where('gymies_organisation_members.status', 'active');
        }
        if (Schema::hasColumn('gymies_organisation_members', 'deleted_at')) {
            $memberQuery->whereNull('gymies_organisation_members.deleted_at');
        }
        $member = $memberQuery->first();

        if (!$member) {
            $trainer = DB::table('gymies_organisation_trainers')
                ->join('gymies_organisations', 'gymies_organisations.id', '=', 'gymies_organisation_trainers.organisation_id')
                ->where('gymies_organisation_trainers.trainer_user_id', (int) $user->id)
                ->where('gymies_organisation_trainers.status', 'active')
                ->select(
                    'gymies_organisation_trainers.organisation_id',
                    'gymies_organisations.name as organisation_name',
                )
                ->first();
            if (!$trainer) {
                return response()->json(['message' => 'Geen gym-toegang.'], 403);
            }
            $member = (object) [
                'organisation_id' => $trainer->organisation_id,
                'member_role' => 'viewer',
                'organisation_name' => $trainer->organisation_name,
            ];
        }

        if ($allowedRoles !== null && !in_array((string) $member->member_role, $allowedRoles, true)) {
            return response()->json(['message' => 'Onvoldoende rechten.'], 403);
        }

        // T-plan: Gym chat vereist Studio (tier 3) — check plan van org-eigenaar
        $ownerId = DB::table('gymies_organisation_members')
            ->where('organisation_id', (int) $member->organisation_id)
            ->where('role', 'owner')
            ->where('status', 'active')
            ->value('user_id');
        if (!$ownerId) {
            return response()->json([
                'message' => 'Gym heeft geen actieve eigenaar. Neem contact op met support.',
                'code'    => 'plan_gym_no_owner',
            ], 403);
        }
        $planCheck = GymiesPlanManager::assertTeam((int) $ownerId);
        if (!$planCheck['allowed']) {
            return response()->json([
                'message'      => $planCheck['message'],
                'upgrade_hint' => $planCheck['upgrade_hint'],
                'code'         => 'plan_gym_locked',
            ], 403);
        }

        return [
            'user_id' => (int) $user->id,
            'organisation_id' => (int) $member->organisation_id,
            'organisation_name' => (string) $member->organisation_name,
            'member_role' => (string) $member->member_role,
        ];
    }
}
