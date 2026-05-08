<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies\Traits;

use App\Helpers\GymiesChatBroadcast;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Trainer messaging and conversation management trait.
 * Extracts messaging, conversation, and chat functionality.
 */
trait TrainerMessagingTrait
{
    public function conversations(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $lastMessageSub = DB::table('gymies_messages')
            ->select('conversation_id', DB::raw('MAX(id) as last_message_id'))
            ->groupBy('conversation_id');

        $rows = DB::table('gymies_conversations as c')
            ->leftJoinSub($lastMessageSub, 'lm', function ($join) {
                $join->on('lm.conversation_id', '=', 'c.id');
            })
            ->leftJoin('gymies_messages as m', 'm.id', '=', 'lm.last_message_id')
            ->join('gymies_users as client', 'client.id', '=', 'c.client_user_id')
            ->where('c.trainer_user_id', $user->id)
            ->orderByDesc('c.updated_at')
            ->select(
                'c.id',
                'c.client_user_id',
                'c.booking_id',
                'c.updated_at',
                'client.display_name as client_name',
                'm.body as last_message',
                'm.created_at as last_message_at',
                'm.from_user_id as last_from_user_id',
                'm.read_at as last_read_at'
            )
            ->get();

        // Support-conversaties (tickets) waar trainer de indiener is: client_user_id=me, ander = GYMIES
        $supportRows = collect();
        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
            $supportRows = DB::table('gymies_conversations as c')
                ->leftJoinSub($lastMessageSub, 'lm', function ($join) {
                    $join->on('lm.conversation_id', '=', 'c.id');
                })
                ->leftJoin('gymies_messages as m', 'm.id', '=', 'lm.last_message_id')
                ->join('gymies_users as gymies', 'gymies.id', '=', 'c.trainer_user_id')
                ->where('c.client_user_id', $user->id)
                ->whereNotNull('c.support_ticket_id')
                ->orderByDesc('c.updated_at')
                ->select(
                    'c.id',
                    'c.client_user_id',
                    'c.booking_id',
                    'c.updated_at',
                    'gymies.display_name as client_name',
                    'm.body as last_message',
                    'm.created_at as last_message_at',
                    'm.from_user_id as last_from_user_id',
                    'm.read_at as last_read_at'
                )
                ->get();
        }

        $all = $rows->concat($supportRows)->sortByDesc('updated_at')->values();
        $data = $all->map(fn ($r) => [
            'id' => (string) $r->id,
            'client_user_id' => (string) $r->client_user_id,
            'client_name' => $r->client_name ?? 'Klant',
            'booking_id' => $r->booking_id ? (string) $r->booking_id : null,
            'last_message' => $r->last_message,
            'last_message_at' => $r->last_message_at,
            'last_from_user_id' => $r->last_from_user_id ? (string) $r->last_from_user_id : null,
            'last_read_at' => $r->last_read_at,
            'updated_at' => $r->updated_at,
        ])->all();

        return response()->json(['data' => $data]);
    }

    public function messages(Request $request, string $conversationId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where(function ($q) use ($user) {
                $q->where('trainer_user_id', $user->id)
                    ->orWhere(function ($q2) use ($user) {
                        $q2->where('client_user_id', $user->id);
                        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
                            $q2->whereNotNull('support_ticket_id');
                        }
                    });
            })
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $rows = DB::table('gymies_messages')
            ->where('conversation_id', $conversationId)
            ->orderBy('created_at')
            ->get(['id', 'conversation_id', 'from_user_id', 'body', 'read_at', 'created_at']);

        $trainerId = (int) $conversation->trainer_user_id;

        $data = $rows->map(function ($r) use ($trainerId) {
            $fromUserId = (int) $r->from_user_id;
            $senderType = $fromUserId === $trainerId ? 'trainer' : 'client';
            return [
                'id' => (string) $r->id,
                'conversation_id' => (string) $r->conversation_id,
                'from_user_id' => (string) $r->from_user_id,
                'sender_type' => $senderType,
                'body' => $r->body ?? '',
                'read_at' => $r->read_at,
                'created_at' => $r->created_at,
            ];
        })->all();

        return response()->json(['data' => $data]);
    }

    public function markConversationRead(Request $request, string $conversationId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where(function ($q) use ($user) {
                $q->where('trainer_user_id', $user->id)
                    ->orWhere(function ($q2) use ($user) {
                        $q2->where('client_user_id', $user->id);
                        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
                            $q2->whereNotNull('support_ticket_id');
                        }
                    });
            })
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $readAt = null;
        if (DB::getSchemaBuilder()->hasColumn('gymies_messages', 'read_at')) {
            $readAt = now()->toIso8601String();
            DB::table('gymies_messages')
                ->where('conversation_id', $conversationId)
                ->where('from_user_id', '!=', $user->id)
                ->whereNull('read_at')
                ->update(['read_at' => now()]);
        }

        if ($readAt !== null && class_exists(\App\Events\Gymies\GymiesChatMessagesRead::class)) {
            $otherUserId = (int) $user->id === (int) $conversation->trainer_user_id
                ? (int) $conversation->client_user_id
                : (int) $conversation->trainer_user_id;
            if ($otherUserId > 0) {
                try {
                    event(new \App\Events\Gymies\GymiesChatMessagesRead($otherUserId, $conversationId, $readAt));
                } catch (\Throwable $e) {
                    \Log::warning('[TrainerMessaging] Broadcast failed: ' . $e->getMessage());
                    if (app()->bound('sentry')) { app('sentry')->captureException($e); }
                }
            }
        }

        return response()->json(['data' => ['message' => 'ok']]);
    }

    /**
     * Trainer meldt dat hij aan het typen is; broadcast naar klant.
     */
    public function typing(Request $request, string $conversationId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where(function ($q) use ($user) {
                $q->where('trainer_user_id', $user->id)
                    ->orWhere(function ($q2) use ($user) {
                        $q2->where('client_user_id', $user->id);
                        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
                            $q2->whereNotNull('support_ticket_id');
                        }
                    });
            })
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $receiverId = (int) $user->id === (int) $conversation->trainer_user_id
            ? (int) $conversation->client_user_id
            : (int) $conversation->trainer_user_id;
        if ($receiverId > 0 && class_exists(\App\Events\Gymies\GymiesChatUserTyping::class)) {
            try {
                $displayName = DB::table('gymies_users')->where('id', $user->id)->value('display_name') ?? 'Trainer';
                event(new \App\Events\Gymies\GymiesChatUserTyping($receiverId, $conversationId, (int) $user->id, $displayName));
            } catch (\Throwable $e) {
                // Broadcasting niet geconfigureerd
            }
        }

        return response()->json(['data' => ['message' => 'ok']]);
    }

    /**
     * Contextuele header voor chat (trainer): resterende strippen, duo-status placeholder.
     * Zelfde bron als sleepingClients — packages + package_id op boekingen.
     */
    public function conversationContext(Request $request, string $conversationId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where(function ($q) use ($trainerId) {
                $q->where('trainer_user_id', $trainerId)
                    ->orWhere(function ($q2) use ($trainerId) {
                        $q2->where('client_user_id', $trainerId);
                        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
                            $q2->whereNotNull('support_ticket_id');
                        }
                    });
            })
            ->first(['id', 'client_user_id', 'booking_id', 'support_ticket_id']);
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        if (!empty($conversation->support_ticket_id)) {
            $ticketStatus = null;
            if (Schema::hasTable('gymies_support_tickets')) {
                $ticket = DB::table('gymies_support_tickets')
                    ->where('id', (int) $conversation->support_ticket_id)
                    ->first(['status']);
                $ticketStatus = $ticket ? (string) ($ticket->status ?? '') : null;
            }
            return response()->json(['data' => [
                'conversation_id' => $conversationId,
                'client_user_id' => (string) $conversation->client_user_id,
                'booking_id' => $conversation->booking_id ? (string) $conversation->booking_id : null,
                'sessions_remaining_total' => 0,
                'duo_state' => 'none',
                'duo_state_label' => null,
                'next_booking' => null,
                'support_ticket_id' => (string) $conversation->support_ticket_id,
                'support_ticket_status' => $ticketStatus ?? '',
            ]]);
        }

        $clientUserId = (int) $conversation->client_user_id;
        $sessionsRemaining = 0;
        if (Schema::hasTable('gymies_packages') && Schema::hasColumn('gymies_bookings', 'package_id')) {
            $packages = DB::table('gymies_packages')
                ->where('trainer_user_id', $trainerId)
                ->get(['id', 'sessions_count']);
            foreach ($packages as $pkg) {
                $sessionsCount = (int) ($pkg->sessions_count ?? 0);
                if ($sessionsCount <= 0) {
                    continue;
                }
                $used = (int) DB::table('gymies_bookings')
                    ->where('client_user_id', $clientUserId)
                    ->where('package_id', (int) $pkg->id)
                    ->whereNotIn('status', ['cancelled'])
                    ->count();
                $sessionsRemaining += max(0, $sessionsCount - $used);
            }
        }

        // Placeholder tot duo-voorstel entiteit bestaat (WebSocket + kaart in UI)
        $duoState = 'none';
        // Optioneel: prefs key gymies_buddy_searching_{userId} — alleen indicatie, geen PII
        // $duoState = ...;

        return response()->json([
            'data' => [
                'conversation_id' => (string) $conversationId,
                'client_user_id' => (string) $clientUserId,
                'booking_id' => $conversation->booking_id ? (string) $conversation->booking_id : null,
                'sessions_remaining_total' => $sessionsRemaining,
                'duo_state' => $duoState,
                'duo_state_label' => $duoState === 'waiting_match' ? 'Wacht op Duo-match' : null,
            ],
        ]);
    }

    public function sendMessage(Request $request, string $conversationId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $request->validate([
            'body' => 'required|string|max:5000',
        ]);

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where(function ($q) use ($user) {
                $q->where('trainer_user_id', $user->id)
                    ->orWhere(function ($q2) use ($user) {
                        $q2->where('client_user_id', $user->id);
                        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
                            $q2->whereNotNull('support_ticket_id');
                        }
                    });
            })
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $body = trim((string) $request->input('body'));
        if ($body === '') {
            return response()->json(['message' => 'Bericht mag niet leeg zijn.'], 422);
        }

        $now = now();
        $id = DB::table('gymies_messages')->insertGetId([
            'conversation_id' => $conversationId,
            'from_user_id' => $user->id,
            'body' => $body,
            'created_at' => $now,
        ]);
        DB::table('gymies_conversations')->where('id', $conversationId)->update(['updated_at' => $now]);

        if (class_exists(GymiesChatBroadcast::class)) {
            GymiesChatBroadcast::afterMessageInserted($conversationId, (int) $id, (int) $user->id, $body);
        }

        if (class_exists(\App\Helpers\GymiesSupportSync::class) && !empty($conversation->support_ticket_id)) {
            \App\Helpers\GymiesSupportSync::syncConversationMessageToTicket($conversationId, (int) $user->id, $body);
        }

        return response()->json(['data' => [
            'id' => (string) $id,
            'conversation_id' => $conversationId,
            'from_user_id' => (string) $user->id,
            'sender_type' => 'trainer',
            'body' => $body,
            'read_at' => null,
            'created_at' => $now->toIso8601String(),
        ]], 201);
    }

    public function ensureConversation(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $request->validate([
            'client_user_id' => 'required|exists:gymies_users,id',
            'booking_id' => 'nullable|exists:gymies_bookings,id',
        ]);

        $trainerId = (int) $user->id;
        $clientId = (int) $request->input('client_user_id');
        $bookingId = $request->input('booking_id');

        if ($bookingId !== null) {
            $booking = DB::table('gymies_bookings')
                ->where('id', $bookingId)
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->first();
            if (!$booking) {
                return response()->json(['message' => 'Boeking past niet bij trainer/klant.'], 422);
            }
        }

        $existing = DB::table('gymies_conversations')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->when($bookingId !== null, fn ($q) => $q->where('booking_id', $bookingId))
            ->orderByDesc('id')
            ->first();

        if (!$existing && $bookingId !== null) {
            $existing = DB::table('gymies_conversations')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->whereNull('booking_id')
                ->orderByDesc('id')
                ->first();
        }

        if ($existing) {
            return response()->json(['data' => ['id' => (string) $existing->id]]);
        }

        $id = DB::table('gymies_conversations')->insertGetId([
            'client_user_id' => $clientId,
            'trainer_user_id' => $trainerId,
            'booking_id' => $bookingId,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['data' => ['id' => (string) $id]], 201);
    }
}
