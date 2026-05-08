<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use App\Helpers\GymiesChatBroadcast;
use App\Helpers\GymiesSupportSync;

/**
 * Chat voor klant: conversaties met trainers (zelfde tabellen als trainer-berichten).
 */
final class GymiesClientConversationController extends Controller
{
    /**
     * Lijst conversaties van de ingelogde klant.
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten kunnen hun gesprekken bekijken.'], 403);
        }

        if (!\Illuminate\Support\Facades\Schema::hasTable('gymies_conversations')) {
            return response()->json(['data' => []]);
        }

        $lastMessageSub = DB::table('gymies_messages')
            ->select('conversation_id', DB::raw('MAX(id) as last_message_id'))
            ->groupBy('conversation_id');

        $rows = DB::table('gymies_conversations as c')
            ->leftJoinSub($lastMessageSub, 'lm', function ($join) {
                $join->on('lm.conversation_id', '=', 'c.id');
            })
            ->leftJoin('gymies_messages as m', 'm.id', '=', 'lm.last_message_id')
            ->join('gymies_users as trainer', 'trainer.id', '=', 'c.trainer_user_id')
            ->where('c.client_user_id', (int) $user->id)
            ->orderByDesc('c.updated_at')
            ->select(
                'c.id',
                'c.client_user_id',
                'c.trainer_user_id',
                'c.booking_id',
                'c.updated_at',
                'm.body as last_message_body',
                'm.created_at as last_message_at',
                'trainer.display_name as trainer_name',
            )
            ->get();

        $unreadCounts = [];
        if ($rows->isNotEmpty() && DB::getSchemaBuilder()->hasColumn('gymies_messages', 'read_at')) {
            $convIds = $rows->pluck('id')->map(fn ($id) => (string) $id)->all();
            $counts = DB::table('gymies_messages as m')
                ->join('gymies_conversations as c', 'c.id', '=', 'm.conversation_id')
                ->whereIn('m.conversation_id', $convIds)
                ->where('c.client_user_id', (int) $user->id)
                ->where('m.from_user_id', '!=', (int) $user->id)
                ->whereNull('m.read_at')
                ->selectRaw('m.conversation_id, COUNT(*) as cnt')
                ->groupBy('m.conversation_id')
                ->pluck('cnt', 'conversation_id');
            $unreadCounts = $counts->all();
        }

        $data = $rows->map(function ($r) use ($unreadCounts) {
            return [
                'id' => (string) $r->id,
                'trainer_user_id' => (string) $r->trainer_user_id,
                'trainer_name' => (string) ($r->trainer_name ?? 'Trainer'),
                'booking_id' => $r->booking_id ? (string) $r->booking_id : null,
                'last_message_body' => $r->last_message_body ? (string) $r->last_message_body : null,
                'last_message_at' => $r->last_message_at,
                'updated_at' => $r->updated_at,
                'unread_count' => (int) ($unreadCounts[$r->id] ?? 0),
            ];
        })->all();

        return response()->json(['data' => $data]);
    }

    /**
     * Berichten van één conversatie (alleen eigen conversatie).
     */
    public function messages(Request $request, string $conversationId): JsonResponse
    {
        if (!ctype_digit($conversationId)) {
            return response()->json(['message' => 'Ongeldig conversatie-ID.'], 400);
        }
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten kunnen gesprekken bekijken.'], 403);
        }

        $conversation = DB::table('gymies_conversations')
            ->where('id', (int) $conversationId)
            ->where('client_user_id', (int) $user->id)
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $trainerId = (int) $conversation->trainer_user_id;
        $rows = DB::table('gymies_messages')
            ->where('conversation_id', $conversationId)
            ->orderBy('created_at')
            ->get(['id', 'conversation_id', 'from_user_id', 'body', 'read_at', 'created_at']);

        $messages = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'conversation_id' => (string) $r->conversation_id,
            'from_user_id' => (string) $r->from_user_id,
            'body' => $r->body,
            'read_at' => $r->read_at,
            'created_at' => $r->created_at,
            'type' => 'message',
        ])->all();

        $includeNotifications = $request->query('include_notifications') === '1' || $request->query('include_notifications') === 'true';
        if ($includeNotifications && $trainerId > 0 && DB::getSchemaBuilder()->hasTable('gymies_notification_queue')) {
            $notifRows = DB::table('gymies_notification_queue')
                ->where('user_id', $user->id)
                ->whereIn('event_type', [
                    'booking_pending_for_client',
                    'booking_confirmed_for_client',
                    'booking_rescheduled_for_client',
                    'booking_cancelled_for_client',
                    'cash_payment_confirmed',
                ])
                ->orderBy('created_at')
                ->limit(50)
                ->get(['id', 'event_type', 'payload_json', 'created_at']);

            foreach ($notifRows as $n) {
                $payload = $n->payload_json ? (json_decode((string) $n->payload_json, true) ?: []) : [];
                $notifTrainerId = isset($payload['trainer_user_id']) ? (int) $payload['trainer_user_id'] : 0;
                if ($notifTrainerId !== $trainerId) {
                    continue;
                }
                $body = $this->notificationToMessageBody($n->event_type, $payload);
                if ($body === null) {
                    continue;
                }
                $messages[] = [
                    'id' => 'n-' . $n->id,
                    'conversation_id' => $conversationId,
                    'from_user_id' => '0',
                    'body' => $body,
                    'read_at' => null,
                    'created_at' => $n->created_at,
                    'type' => 'notification',
                ];
            }
            usort($messages, fn ($a, $b) => strcmp($a['created_at'] ?? '', $b['created_at'] ?? ''));
        }

        return response()->json(['data' => $messages]);
    }

    /** @return string|null Human-readable bericht voor melding, of null om over te slaan. */
    private function notificationToMessageBody(string $eventType, array $payload): ?string
    {
        $scheduledAt = $payload['scheduled_at'] ?? null;
        $msg = $payload['message'] ?? null;
        if (is_string($msg) && $msg !== '') {
            return $msg;
        }
        switch ($eventType) {
            case 'booking_pending_for_client':
                return $scheduledAt
                    ? "Je boeking staat in afwachting van bevestiging (gepland: {$scheduledAt})."
                    : 'Je boeking staat in afwachting van bevestiging.';
            case 'booking_confirmed_for_client':
                return $scheduledAt
                    ? "Je trainer heeft de sessie bevestigd (gepland: {$scheduledAt})."
                    : 'Je trainer heeft de sessie bevestigd.';
            case 'booking_rescheduled_for_client':
                return 'Je sessie is verplaatst.';
            case 'booking_cancelled_for_client':
                return 'Je sessie is geannuleerd.';
            case 'cash_payment_confirmed':
                return 'Je trainer heeft de contante betaling bevestigd.';
            default:
                return null;
        }
    }

    /**
     * Bericht sturen (klant is afzender).
     */
    public function sendMessage(Request $request, string $conversationId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten kunnen berichten sturen.'], 403);
        }
        $request->validate([
            'body' => 'required|string|max:5000',
        ]);

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where('client_user_id', (int) $user->id)
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $body = strip_tags(trim((string) $request->input('body')));

        $id = DB::table('gymies_messages')->insertGetId([
            'conversation_id' => $conversationId,
            'from_user_id' => $user->id,
            'body' => $body,
            'created_at' => now(),
        ]);
        DB::table('gymies_conversations')->where('id', $conversationId)->update(['updated_at' => now()]);

        // Broadcast + support sync mogen NOOIT de 201 response blokkeren
        try {
            if (class_exists(GymiesChatBroadcast::class)) {
                GymiesChatBroadcast::afterMessageInserted($conversationId, (int) $id, (int) $user->id, $body);
            }
        } catch (\Throwable $e) {
            \Log::warning('[Chat] Broadcast fout na bericht #{id}: ' . $e->getMessage(), ['id' => $id]);
        }

        try {
            if (class_exists(\App\Helpers\GymiesSupportSync::class)) {
                \App\Helpers\GymiesSupportSync::syncConversationMessageToTicket($conversationId, (int) $user->id, $body);
            }
        } catch (\Throwable $e) {
            \Log::warning('[Chat] SupportSync fout na bericht #{id}: ' . $e->getMessage(), ['id' => $id]);
        }

        return response()->json(['data' => ['id' => (string) $id]], 201);
    }

    /**
     * Conversatie aanmaken of bestaande ophalen (klant initieert met trainer_user_id).
     */
    public function ensure(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten kunnen een gesprek starten.'], 403);
        }
        $request->validate([
            'trainer_user_id' => 'required|exists:gymies_users,id',
            'booking_id' => 'nullable|exists:gymies_bookings,id',
        ]);

        $clientId = (int) $user->id;
        $trainerId = (int) $request->input('trainer_user_id');
        $bookingId = $request->input('booking_id');

        if ($trainerId === $clientId) {
            return response()->json(['message' => 'Je kunt geen gesprek met jezelf starten.'], 422);
        }

        if ($bookingId !== null) {
            $booking = DB::table('gymies_bookings')
                ->where('id', $bookingId)
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->first();
            if (!$booking) {
                return response()->json(['message' => 'Boeking niet gevonden.'], 422);
            }
        }

        $existing = DB::table('gymies_conversations')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->when($bookingId !== null, fn ($q) => $q->where('booking_id', $bookingId))
            ->orderByDesc('id')
            ->first();

        if (!$existing && $bookingId !== null) {
            $existing = DB::table('gymies_conversations')
                ->where('client_user_id', $clientId)
                ->where('trainer_user_id', $trainerId)
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

    /**
     * Markeer berichten van de trainer als gelezen.
     */
    public function markRead(Request $request, string $conversationId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten kunnen gesprekken als gelezen markeren.'], 403);
        }

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where('client_user_id', (int) $user->id)
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
            $trainerId = (int) $conversation->trainer_user_id;
            if ($trainerId > 0) {
                try {
                    event(new \App\Events\Gymies\GymiesChatMessagesRead($trainerId, $conversationId, $readAt));
                } catch (\Throwable $e) {
                    // Broadcasting niet geconfigureerd
                }
            }
        }

        return response()->json(['data' => ['message' => 'ok']]);
    }

    /**
     * DELETE conversations/{id} – klant verwijdert eigen gesprek.
     * Verwijdert de conversatie en alle berichten permanent.
     */
    public function destroy(Request $request, string $conversationId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten kunnen gesprekken verwijderen.'], 403);
        }

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where('client_user_id', (int) $user->id)
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        // Berichten eerst verwijderen (FK constraint)
        if (\Illuminate\Support\Facades\Schema::hasTable('gymies_messages')) {
            DB::table('gymies_messages')
                ->where('conversation_id', (int) $conversationId)
                ->delete();
        }

        DB::table('gymies_conversations')
            ->where('id', (int) $conversationId)
            ->delete();

        return response()->json(['data' => ['message' => 'Gesprek verwijderd.']]);
    }

    /**
     * Klant meldt dat hij aan het typen is; broadcast naar trainer.
     */
    public function typing(Request $request, string $conversationId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten.'], 403);
        }

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where('client_user_id', (int) $user->id)
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $trainerId = (int) $conversation->trainer_user_id;
        if ($trainerId > 0 && class_exists(\App\Events\Gymies\GymiesChatUserTyping::class)) {
            try {
                $displayName = DB::table('gymies_users')->where('id', $user->id)->value('display_name') ?? 'Klant';
                event(new \App\Events\Gymies\GymiesChatUserTyping($trainerId, $conversationId, (int) $user->id, $displayName));
            } catch (\Throwable $e) {
                // Broadcasting niet geconfigureerd
            }
        }

        return response()->json(['data' => ['message' => 'ok']]);
    }

    /**
     * Contextuele header voor chat (klant): gekoppelde boeking, volgende afspraak.
     */
    public function conversationContext(Request $request, string $conversationId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || !in_array($user->role, ['klant', 'client'], true)) {
            return response()->json(['message' => 'Alleen klanten.'], 403);
        }
        $clientId = (int) $user->id;

        $select = ['id', 'trainer_user_id', 'booking_id'];
        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
            $select[] = 'support_ticket_id';
        }
        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where('client_user_id', $clientId)
            ->first($select);
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $trainerUserId = (string) $conversation->trainer_user_id;
        $bookingId = $conversation->booking_id ? (string) $conversation->booking_id : null;

        $supportTicketId = null;
        $supportTicketStatus = null;
        if (!empty($conversation->support_ticket_id) && Schema::hasTable('gymies_support_tickets')) {
            $ticket = DB::table('gymies_support_tickets')
                ->where('id', (int) $conversation->support_ticket_id)
                ->first(['id', 'status']);
            if ($ticket) {
                $supportTicketId = (string) $ticket->id;
                $supportTicketStatus = (string) ($ticket->status ?? '');
            }
        }

        $nextBooking = null;
        if (\Illuminate\Support\Facades\Schema::hasTable('gymies_bookings')) {
            $row = DB::table('gymies_bookings')
                ->where('client_user_id', $clientId)
                ->where('trainer_user_id', (int) $conversation->trainer_user_id)
                ->whereIn('status', ['pending', 'confirmed'])
                ->where('scheduled_at', '>=', now()->toDateTimeString())
                ->orderBy('scheduled_at')
                ->first(['id', 'scheduled_at', 'status']);
            if ($row) {
                $nextBooking = [
                    'id' => (string) $row->id,
                    'scheduled_at' => (string) $row->scheduled_at,
                    'status' => (string) $row->status,
                ];
            }
        }

        $data = [
            'conversation_id' => (string) $conversationId,
            'trainer_user_id' => $trainerUserId,
            'booking_id' => $bookingId,
            'next_booking' => $nextBooking,
            'duo_state' => 'none',
            'duo_state_label' => null,
        ];
        if ($supportTicketId !== null) {
            $data['support_ticket_id'] = $supportTicketId;
            $data['support_ticket_status'] = $supportTicketStatus;
        }
        return response()->json(['data' => $data]);
    }

    /**
     * Klant: eigen progressie bij één trainer (niet-private entries) — basis voor later grafieken.
     */
    public function myProgressForTrainer(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $clientId = (int) $user->id;
        $request->validate([
            'trainer_user_id' => 'required|integer|exists:gymies_users,id',
        ]);
        $trainerId = (int) $request->query('trainer_user_id');
        if (!\Illuminate\Support\Facades\Schema::hasTable('gymies_client_progress')) {
            return response()->json(['data' => []]);
        }
        $hasBooking = DB::table('gymies_bookings')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->exists();
        if (!$hasBooking) {
            return response()->json(['message' => 'Geen relatie met deze trainer.'], 403);
        }
        $rows = DB::table('gymies_client_progress')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->where('is_private', 0)
            ->orderByDesc('created_at')
            ->limit(100)
            ->get();
        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'type' => (string) $r->type,
            'value' => (string) $r->value,
            'note' => $r->note !== null ? (string) $r->note : null,
            'created_at' => $r->created_at,
        ])->all();

        return response()->json(['data' => $data]);
    }

    /**
     * Klant: gedeeld dossier van trainer — alleen als trainer "dossier voor klant open" heeft gezet.
     * Bevat nooit internal_notes of medical_background.
     */
    public function mySharedDossierFromTrainer(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $clientId = (int) $user->id;
        $request->validate([
            'trainer_user_id' => 'required|integer',
        ]);
        $trainerId = (int) $request->query('trainer_user_id');
        $hasBooking = DB::table('gymies_bookings')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->exists();
        if (!$hasBooking) {
            return response()->json(['message' => 'Geen relatie met deze trainer.'], 403);
        }
        if (!\Illuminate\Support\Facades\Schema::hasTable('gymies_client_dossier')) {
            return response()->json([
                'shared' => false,
                'message' => 'Je trainer heeft nog geen dossier met je gedeeld.',
            ]);
        }
        $row = DB::table('gymies_client_dossier')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->first();
        if ($row === null) {
            return response()->json([
                'shared' => false,
                'message' => 'Je trainer heeft nog geen dossier met je gedeeld.',
            ]);
        }
        $sharedAt = \Illuminate\Support\Facades\Schema::hasColumn('gymies_client_dossier', 'shared_with_client_at')
            ? ($row->shared_with_client_at ?? null)
            : null;
        if ($sharedAt === null || trim((string) $sharedAt) === '' || str_starts_with((string) $sharedAt, '0000-00-00')) {
            return response()->json([
                'shared' => false,
                'message' => 'Je trainer heeft het dossier nog niet voor je geopend. Vraag ernaar in je volgende sessie.',
            ]);
        }
        $summary = \Illuminate\Support\Facades\Schema::hasColumn('gymies_client_dossier', 'client_facing_summary')
            ? ($row->client_facing_summary ?? null)
            : null;
        $goals = $row->goals_long_term ?? null;

        return response()->json([
            'shared' => true,
            'shared_with_client_at' => $sharedAt,
            'trainer_user_id' => (string) $trainerId,
            'client_facing_summary' => $summary,
            'goals_long_term' => $goals,
            'hint' => 'Voor je metingen en voortgang zie ook Mijn progressie bij deze trainer.',
        ]);
    }

    /**
     * Klant: gedeelde session entries (visibility=shared) bij één trainer.
     */
    public function mySharedSessionEntriesForTrainer(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $clientId = (int) $user->id;
        $request->validate([
            'trainer_user_id' => 'required|integer',
            'page' => 'nullable|integer|min:1',
            'per_page' => 'nullable|integer|min:1|max:100',
        ]);
        $trainerId = (int) $request->query('trainer_user_id');
        $hasBooking = DB::table('gymies_bookings')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->exists();
        if (!$hasBooking) {
            return response()->json(['message' => 'Geen relatie met deze trainer.'], 403);
        }
        if (!\Illuminate\Support\Facades\Schema::hasTable('gymies_client_session_entries')) {
            return response()->json(['data' => ['session_entries' => [], 'pagination' => ['page' => 1, 'per_page' => 20, 'has_more' => false]]]);
        }

        $page = max((int) $request->query('page', 1), 1);
        $perPage = min(max((int) $request->query('per_page', 20), 1), 100);
        $offset = ($page - 1) * $perPage;

        $rows = DB::table('gymies_client_session_entries')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->where('visibility', 'shared')
            ->whereNull('deleted_at')
            ->orderByDesc('session_at')
            ->orderByDesc('id')
            ->offset($offset)
            ->limit($perPage + 1)
            ->get();
        $hasMore = $rows->count() > $perPage;
        $rows = $rows->slice(0, $perPage)->values();

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'trainer_user_id' => (string) $r->trainer_user_id,
            'client_user_id' => (string) $r->client_user_id,
            'booking_id' => $r->booking_id !== null ? (string) $r->booking_id : null,
            'session_at' => $r->session_at,
            'session_type' => $r->session_type,
            'attendance_status' => $r->attendance_status,
            'focus' => $r->focus,
            'positive_notes' => $r->positive_notes,
            'improve_notes' => $r->improve_notes,
            'homework' => $r->homework,
            'energy_score' => $r->energy_score !== null ? (int) $r->energy_score : null,
            'performance_score' => $r->performance_score !== null ? (float) $r->performance_score : null,
            'visibility' => 'shared',
            'created_at' => $r->created_at,
            'updated_at' => $r->updated_at,
        ])->all();

        return response()->json([
            'data' => [
                'session_entries' => $data,
                'pagination' => [
                    'page' => $page,
                    'per_page' => $perPage,
                    'has_more' => $hasMore,
                ],
            ],
        ]);
    }

    /**
     * Klant: gedeelde doelen van trainer (inclusief progress points), alleen als dossier gedeeld is.
     */
    public function mySharedGoalsForTrainer(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $clientId = (int) $user->id;
        $request->validate([
            'trainer_user_id' => 'required|integer',
        ]);
        $trainerId = (int) $request->query('trainer_user_id');
        $hasBooking = DB::table('gymies_bookings')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->exists();
        if (!$hasBooking) {
            return response()->json(['message' => 'Geen relatie met deze trainer.'], 403);
        }
        if (!$this->isDossierSharedForClient($trainerId, $clientId)) {
            return response()->json(['data' => ['goals' => []]]);
        }
        if (!Schema::hasTable('gymies_client_goals')) {
            return response()->json(['data' => ['goals' => []]]);
        }

        $goals = DB::table('gymies_client_goals')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->orderByDesc('created_at')
            ->get();
        $goalIds = $goals->pluck('id')->map(fn ($id) => (int) $id)->all();
        $pointsByGoal = [];
        if (!empty($goalIds) && Schema::hasTable('gymies_client_goal_progress_points')) {
            $pointsByGoal = DB::table('gymies_client_goal_progress_points')
                ->whereIn('goal_id', $goalIds)
                ->orderBy('measured_at')
                ->orderBy('id')
                ->get()
                ->groupBy('goal_id')
                ->map(fn ($items) => $items->map(fn ($p) => [
                    'id' => (string) $p->id,
                    'goal_id' => (string) $p->goal_id,
                    'value_numeric' => $p->value_numeric !== null ? (float) $p->value_numeric : null,
                    'note' => $p->note,
                    'measured_at' => $p->measured_at,
                    'created_at' => $p->created_at,
                    'updated_at' => $p->updated_at,
                ])->all())
                ->all();
        }

        return response()->json([
            'data' => [
                'goals' => $goals->map(fn ($g) => [
                    'id' => (string) $g->id,
                    'trainer_user_id' => (string) $g->trainer_user_id,
                    'client_user_id' => (string) $g->client_user_id,
                    'title' => $g->title,
                    'target_value' => $g->target_value !== null ? (float) $g->target_value : null,
                    'current_value' => $g->current_value !== null ? (float) $g->current_value : null,
                    'unit' => $g->unit,
                    'status' => $g->status,
                    'due_date' => $g->due_date,
                    'created_at' => $g->created_at,
                    'updated_at' => $g->updated_at,
                    'progress_points' => $pointsByGoal[(int) $g->id] ?? [],
                ])->all(),
            ],
        ]);
    }

    /**
     * Klant: KPI-overview voor gedeeld dossier.
     */
    public function mySharedDossierSummaryForTrainer(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $clientId = (int) $user->id;
        $request->validate([
            'trainer_user_id' => 'required|integer',
        ]);
        $trainerId = (int) $request->query('trainer_user_id');
        $hasBooking = DB::table('gymies_bookings')
            ->where('client_user_id', $clientId)
            ->where('trainer_user_id', $trainerId)
            ->exists();
        if (!$hasBooking) {
            return response()->json(['message' => 'Geen relatie met deze trainer.'], 403);
        }
        if (!$this->isDossierSharedForClient($trainerId, $clientId)) {
            return response()->json([
                'data' => [
                    'attendance_rate' => 0.0,
                    'streak_days' => 0,
                    'goals_done' => 0,
                    'goals_total' => 0,
                    'risk_flags' => ['dossier_not_shared'],
                    'next_best_action' => 'ask_trainer_to_share_dossier',
                ],
            ]);
        }

        $attendanceRate = 0.0;
        $streakDays = 0;
        $riskFlags = [];
        $nextBestAction = 'follow_homework';

        if (Schema::hasTable('gymies_client_session_entries')) {
            $entries = DB::table('gymies_client_session_entries')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->where('visibility', 'shared')
                ->whereNull('deleted_at')
                ->orderByDesc('session_at')
                ->get(['session_at', 'attendance_status']);
            $tracked = $entries
                ->whereIn('attendance_status', ['attended', 'no_show', 'cancelled', 'unknown'])
                ->count();
            $attended = $entries->where('attendance_status', 'attended')->count();
            $attendanceRate = $tracked > 0 ? round(($attended / $tracked) * 100, 1) : 0.0;
            $attendedDates = $entries
                ->where('attendance_status', 'attended')
                ->map(fn ($e) => substr((string) $e->session_at, 0, 10))
                ->filter()
                ->unique()
                ->values()
                ->all();
            $streakDays = $this->calculateDateStreakDays($attendedDates);

            $latestAt = $entries->first()->session_at ?? null;
            if ($latestAt !== null && \Carbon\Carbon::parse((string) $latestAt)->diffInDays(now()) > 14) {
                $riskFlags[] = 'no_recent_shared_session_update';
            }
            if ($tracked >= 3 && $attendanceRate < 60.0) {
                $riskFlags[] = 'low_attendance_rate';
            }
        }

        $goalsTotal = 0;
        $goalsDone = 0;
        if (Schema::hasTable('gymies_client_goals')) {
            $goals = DB::table('gymies_client_goals')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->whereNull('deleted_at')
                ->get(['status']);
            $goalsTotal = $goals->count();
            $goalsDone = $goals->where('status', 'done')->count();
            if ($goalsTotal === 0) {
                $riskFlags[] = 'no_goals_set';
            }
        }

        if (in_array('low_attendance_rate', $riskFlags, true)) {
            $nextBestAction = 'plan_next_session';
        } elseif ($goalsTotal > 0 && $goalsDone === $goalsTotal) {
            $nextBestAction = 'set_new_goal_with_trainer';
        } elseif (in_array('no_goals_set', $riskFlags, true)) {
            $nextBestAction = 'ask_trainer_for_goal_plan';
        }

        return response()->json([
            'data' => [
                'attendance_rate' => $attendanceRate,
                'streak_days' => $streakDays,
                'goals_done' => $goalsDone,
                'goals_total' => $goalsTotal,
                'risk_flags' => array_values(array_unique($riskFlags)),
                'next_best_action' => $nextBestAction,
            ],
        ]);
    }

    private function isDossierSharedForClient(int $trainerId, int $clientId): bool
    {
        if (!Schema::hasTable('gymies_client_dossier')) {
            return false;
        }
        $row = DB::table('gymies_client_dossier')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->first();
        if ($row === null) {
            return false;
        }
        $sharedAt = Schema::hasColumn('gymies_client_dossier', 'shared_with_client_at')
            ? ($row->shared_with_client_at ?? null)
            : null;
        if ($sharedAt === null) {
            return false;
        }
        $value = trim((string) $sharedAt);
        if ($value === '' || str_starts_with($value, '0000-00-00')) {
            return false;
        }
        return true;
    }

    /**
     * @param list<string> $dates yyyy-mm-dd
     */
    private function calculateDateStreakDays(array $dates): int
    {
        if (empty($dates)) {
            return 0;
        }
        rsort($dates);
        $streak = 1;
        $cursor = \Carbon\Carbon::parse($dates[0])->startOfDay();
        for ($i = 1; $i < count($dates); $i++) {
            $d = \Carbon\Carbon::parse($dates[$i])->startOfDay();
            if ($d->equalTo($cursor->copy()->subDay())) {
                $streak++;
                $cursor = $d;
                continue;
            }
            if ($d->equalTo($cursor)) {
                continue;
            }
            break;
        }
        return $streak;
    }

    /**
     * Buddy-matcher stats voor dashboard: besparingsmeter + zoekstatus + optionele match.
     */
    public function buddyStats(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $userId = (int) $user->id;

        $isSearching = false;
        if (Schema::hasTable('gymies_buddy_search_prefs')) {
            $prefs = DB::table('gymies_buddy_search_prefs')->where('user_id', $userId)->first();
            $isSearching = $prefs && (int) ($prefs->is_searching ?? 0) === 1;
        }

        $savingsCents = $this->computeBuddySavingsCents($userId);
        $match = $this->findBuddyMatch($userId, $isSearching);

        return response()->json([
            'is_searching' => $isSearching,
            'savings_cents_this_quarter' => $savingsCents,
            'match' => $match,
        ]);
    }

    /**
     * Start buddy-zoeken (server-driven).
     */
    public function buddySearchStart(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        GymiesSchemaEnsure::buddySearchPrefsTable();
        if (!Schema::hasTable('gymies_buddy_search_prefs')) {
            return response()->json(['message' => 'Buddy Matcher nog niet beschikbaar.'], 503);
        }
        $trainerId = $request->input('preferred_trainer_id') ? (int) $request->input('preferred_trainer_id') : null;
        $userId = (int) $user->id;
        $exists = DB::table('gymies_buddy_search_prefs')->where('user_id', $userId)->exists();
        if ($exists) {
            DB::table('gymies_buddy_search_prefs')->where('user_id', $userId)->update([
                'is_searching' => 1,
                'preferred_trainer_id' => $trainerId,
                'updated_at' => now(),
            ]);
        } else {
            DB::table('gymies_buddy_search_prefs')->insert([
                'user_id' => $userId,
                'is_searching' => 1,
                'preferred_trainer_id' => $trainerId,
                'updated_at' => now(),
            ]);
        }
        return response()->json(['ok' => true, 'message' => 'Buddy-zoeken gestart.']);
    }

    /**
     * Stop buddy-zoeken.
     */
    public function buddySearchStop(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (Schema::hasTable('gymies_buddy_search_prefs')) {
            DB::table('gymies_buddy_search_prefs')->where('user_id', (int) $user->id)->update([
                'is_searching' => 0,
                'updated_at' => now(),
            ]);
        }
        return response()->json(['ok' => true, 'message' => 'Buddy-zoeken gestopt.']);
    }

    private function computeBuddySavingsCents(int $userId): int
    {
        if (!Schema::hasTable('gymies_bookings')) {
            return 0;
        }
        $startOfQuarter = now()->firstOfQuarter()->toDateTimeString();
        $endOfQuarter = now()->lastOfQuarter()->endOfDay()->toDateTimeString();
        $query = DB::table('gymies_bookings as b')
            ->leftJoin('gymies_trainer_profiles as p', 'p.user_id', '=', 'b.trainer_user_id')
            ->where('b.client_user_id', $userId)
            ->where('b.status', 'completed')
            ->whereBetween('b.scheduled_at', [$startOfQuarter, $endOfQuarter]);
        // Duo: expliciet session_type/lesson_type, of split_payment, of 2+ participants
        $hasLessonType = Schema::hasColumn('gymies_bookings', 'lesson_type');
        $hasSessionType = Schema::hasColumn('gymies_bookings', 'session_type');
        if ($hasLessonType) {
            $query->where('b.lesson_type', 'duo');
        } elseif ($hasSessionType) {
            $query->where('b.session_type', 'duo');
        } else {
            $query->where(function ($q) {
                $q->where('b.split_payment_enabled', 1);
                if (Schema::hasTable('gymies_booking_participants')) {
                    $duoBookingIds = DB::table('gymies_booking_participants')
                        ->select('booking_id')
                        ->groupBy('booking_id')
                        ->havingRaw('COUNT(*) >= 2')
                        ->pluck('booking_id');
                    if ($duoBookingIds->isNotEmpty()) {
                        $q->orWhereIn('b.id', $duoBookingIds);
                    }
                }
            });
        }
        $rows = $query->select('b.amount_cents', 'b.duration_minutes', 'p.hourly_rate_cents', 'p.duo_surcharge_cents')
            ->get();
        $total = 0;
        foreach ($rows as $r) {
            $paid = (int) ($r->amount_cents ?? 0);
            $duration = max(1, (int) ($r->duration_minutes ?? 60));
            $hourly = (int) ($r->hourly_rate_cents ?? 0);
            $soloPrice = (int) round($hourly * $duration / 60);
            $soloForTwo = $soloPrice * 2;
            $saved = max(0, $soloForTwo - $paid);
            $total += $saved;
        }
        return $total;
    }

    private function findBuddyMatch(int $userId, bool $isSearching): ?array
    {
        if (!Schema::hasTable('gymies_buddy_search_prefs') || !$isSearching) {
            return null;
        }
        $prefs = DB::table('gymies_buddy_search_prefs')->where('user_id', $userId)->first();
        if (!$prefs || (int) ($prefs->is_searching ?? 0) !== 1) {
            return null;
        }
        $myTrainerId = $prefs->preferred_trainer_id ? (int) $prefs->preferred_trainer_id : null;
        $myTrainerIds = [];
        if ($myTrainerId !== null) {
            $myTrainerIds = [$myTrainerId];
        } elseif (Schema::hasTable('gymies_bookings')) {
            $myTrainerIds = DB::table('gymies_bookings')
                ->where('client_user_id', $userId)
                ->whereIn('status', ['pending', 'confirmed', 'completed'])
                ->distinct()
                ->pluck('trainer_user_id')
                ->map(fn ($id) => (int) $id)
                ->all();
        }
        $candidates = DB::table('gymies_buddy_search_prefs as bp')
            ->join('gymies_users as u', 'u.id', '=', 'bp.user_id')
            ->where('bp.user_id', '!=', $userId)
            ->where('bp.is_searching', 1)
            ->select('u.id', 'u.display_name', 'u.avatar_url', 'u.first_name', 'bp.preferred_trainer_id')
            ->get();
        foreach ($candidates as $c) {
            $cTrainerId = $c->preferred_trainer_id ? (int) $c->preferred_trainer_id : null;
            $trainerId = null;
            if ($myTrainerId !== null && $cTrainerId === $myTrainerId) {
                $trainerId = $myTrainerId;
            } elseif (!empty($myTrainerIds) && $cTrainerId !== null && in_array($cTrainerId, $myTrainerIds, true)) {
                $trainerId = $cTrainerId;
            } elseif (empty($myTrainerIds) && $cTrainerId !== null && Schema::hasTable('gymies_bookings')) {
                $hasBooking = DB::table('gymies_bookings')
                    ->where('client_user_id', $userId)
                    ->where('trainer_user_id', $cTrainerId)
                    ->whereIn('status', ['pending', 'confirmed', 'completed'])
                    ->exists();
                if ($hasBooking) {
                    $trainerId = $cTrainerId;
                }
            } elseif (!empty($myTrainerIds) && $cTrainerId === null && Schema::hasTable('gymies_bookings')) {
                foreach ($myTrainerIds as $tid) {
                    $hasBooking = DB::table('gymies_bookings')
                        ->where('client_user_id', (int) $c->id)
                        ->where('trainer_user_id', $tid)
                        ->whereIn('status', ['pending', 'confirmed', 'completed'])
                        ->exists();
                    if ($hasBooking) {
                        $trainerId = $tid;
                        break;
                    }
                }
            }
            // Beide "open" (geen voorkeur): match op trainer van de kandidaat (als die boekingen heeft)
            if ($trainerId === null && $myTrainerId === null && empty($myTrainerIds) && $cTrainerId === null && Schema::hasTable('gymies_bookings')) {
                $candidateTrainer = DB::table('gymies_bookings')
                    ->where('client_user_id', (int) $c->id)
                    ->whereIn('status', ['pending', 'confirmed', 'completed'])
                    ->orderByDesc('scheduled_at')
                    ->value('trainer_user_id');
                if ($candidateTrainer !== null) {
                    $trainerId = (int) $candidateTrainer;
                }
            }
            if ($trainerId === null) {
                continue;
            }
            $duoCents = null;
            $soloCents = null;
            if ($trainerId && Schema::hasTable('gymies_trainer_profiles')) {
                $profile = DB::table('gymies_trainer_profiles')
                    ->where('user_id', $trainerId)
                    ->first(['hourly_rate_cents', 'duo_surcharge_cents']);
                if ($profile) {
                    $hourly = (int) ($profile->hourly_rate_cents ?? 0);
                    $surcharge = (int) ($profile->duo_surcharge_cents ?? 0);
                    $soloCents = $hourly;
                    $duoCents = $hourly > 0 ? (int) round(($hourly + $surcharge) / 2) : null;
                }
            }
            $firstName = trim((string) ($c->first_name ?? ''));
            if ($firstName === '') {
                $firstName = trim((string) ($c->display_name ?? ''));
            }
            if ($firstName === '') {
                $firstName = 'Buddy';
            }
            $avatarUrl = trim((string) ($c->avatar_url ?? ''));
            $specialty = '';
            if ($trainerId && Schema::hasTable('gymies_trainer_profiles')) {
                $sp = DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->value('specialty');
                $specialty = trim((string) ($sp ?? ''));
            }
            $sharedGoals = $specialty !== '' ? array_map('trim', explode(',', $specialty)) : [];

            return [
                'user_id' => (string) $c->id,
                'first_name' => $firstName,
                'photo_url' => $avatarUrl !== '' ? $avatarUrl : null,
                'shared_goals' => array_values(array_filter($sharedGoals)),
                'trainer_user_id' => $trainerId ? (string) $trainerId : null,
                'duo_cents_per_person' => $duoCents,
                'solo_cents_per_person' => $soloCents,
            ];
        }
        return null;
    }

    public function mySessionNotes(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_session_notes')) {
            return response()->json(['data' => []]);
        }
        $notes = DB::table('gymies_session_notes as sn')
            ->leftJoin('gymies_users as t', 't.id', '=', 'sn.trainer_user_id')
            ->where('sn.client_user_id', $user->id)
            ->select('sn.*', 't.display_name as trainer_name')
            ->orderByDesc('sn.created_at')
            ->limit(100)
            ->get();
        return response()->json(['data' => $notes]);
    }

    public function mySharedDossier(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!Schema::hasTable('gymies_client_dossier')) {
            return response()->json(['data' => null]);
        }
        $hasShareCol = Schema::hasColumn('gymies_client_dossier', 'shared_with_client');
        $query = DB::table('gymies_client_dossier as d')
            ->leftJoin('gymies_users as t', 't.id', '=', 'd.trainer_user_id')
            ->where('d.client_user_id', $user->id);
        if ($hasShareCol) {
            $query->where('d.shared_with_client', true);
        }
        $dossier = $query->select('d.*', 't.display_name as trainer_name')
            ->orderByDesc('d.updated_at')
            ->first();
        return response()->json(['data' => $dossier]);
    }
}
