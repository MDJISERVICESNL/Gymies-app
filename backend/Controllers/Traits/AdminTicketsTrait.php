<?php

namespace App\Http\Controllers\Gymies\Traits;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Schema;

trait AdminTicketsTrait
{
    public function tickets(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['data' => []]);
        }
        $status = trim((string) $request->query('status', ''));
        $priority = trim((string) $request->query('priority', ''));
        $q = trim((string) $request->query('q', ''));
        $assignedToMe = filter_var($request->query('assigned_to_me'), FILTER_VALIDATE_BOOLEAN);
        $sort = trim((string) $request->query('sort', 'created_at_desc'));
        $limit = min(max((int) $request->query('limit', 200), 1), 1000);

        $select = [
            't.id', 't.user_id', 'u.email as user_email', 'u.display_name as user_name',
            't.subject', 't.category', 't.priority', 't.status', 't.assigned_to_user_id',
            'a.email as assigned_email', 'a.display_name as assigned_name',
            't.created_at', 't.updated_at', 't.resolved_at',
        ];
        if (Schema::hasColumn('gymies_support_tickets', 'close_reason')) {
            $select[] = 't.close_reason';
        }
        if (Schema::hasColumn('gymies_support_tickets', 'submitter_name')) {
            $select[] = 't.submitter_name';
            $select[] = 't.submitter_email';
            $select[] = 't.submitter_phone';
        }
        $query = DB::table('gymies_support_tickets as t')
            ->leftJoin('gymies_users as u', 'u.id', '=', 't.user_id')
            ->leftJoin('gymies_users as a', 'a.id', '=', 't.assigned_to_user_id')
            ->select($select);
        if ($status !== '') {
            $query->where('t.status', $status);
        }
        if ($priority !== '') {
            $query->where('t.priority', $priority);
        }
        if ($assignedToMe) {
            $query->where('t.assigned_to_user_id', (int) $admin->id);
        }
        if ($q !== '') {
            $ticketIdsFromMessages = [];
            if (Schema::hasTable('gymies_support_ticket_messages')) {
                $ticketIdsFromMessages = DB::table('gymies_support_ticket_messages')
                    ->where('message', 'like', "%{$q}%")
                    ->pluck('ticket_id')
                    ->unique()
                    ->values()
                    ->all();
            }
            $query->where(function ($w) use ($q, $ticketIdsFromMessages): void {
                $w->where('t.subject', 'like', "%{$q}%")
                    ->orWhere('u.email', 'like', "%{$q}%")
                    ->orWhere('u.display_name', 'like', "%{$q}%");
                if (count($ticketIdsFromMessages) > 0) {
                    $w->orWhereIn('t.id', $ticketIdsFromMessages);
                }
            });
        }
        switch ($sort) {
            case 'created_at_asc':
                $query->orderBy('t.created_at');
                break;
            case 'priority':
                $query->orderByRaw("FIELD(t.priority, 'critical', 'high', 'medium', 'low')")->orderByDesc('t.created_at');
                break;
            case 'status':
                $query->orderBy('t.status')->orderByDesc('t.created_at');
                break;
            case 'assigned':
                $query->orderByRaw('t.assigned_to_user_id IS NULL')->orderBy('a.display_name')->orderByDesc('t.created_at');
                break;
            default:
                $query->orderByDesc('t.id');
                break;
        }

        return response()->json(['data' => $query->limit($limit)->get()]);
    }

    public function updateTicket(Request $request, string $ticketId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($ticketId)) {
            return response()->json(['message' => 'Ongeldige ticket id.'], 422);
        }
        $request->validate([
            'status' => 'required|in:new,in_progress,waiting_customer,resolved',
            'priority' => 'required|in:low,medium,high,critical',
            'reason' => 'required|string|max:500',
            'assigned_to_user_id' => 'nullable|integer|min:0',
            'close_reason' => 'nullable|string|max:255',
        ]);
        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['message' => 'Support tabel ontbreekt.'], 422);
        }
        $id = (int) $ticketId;
        $t = DB::table('gymies_support_tickets')->where('id', $id)->first();
        if (!$t) {
            return response()->json(['message' => 'Ticket niet gevonden.'], 404);
        }
        $assignedTo = $request->has('assigned_to_user_id') ? $request->input('assigned_to_user_id') : null;
        $assignedToId = $assignedTo === null || $assignedTo === '' ? null : (int) $assignedTo;
        if ($assignedToId !== null && $assignedToId < 1) {
            $assignedToId = null;
        }

        $update = [
            'status' => (string) $request->input('status'),
            'priority' => (string) $request->input('priority'),
            'updated_at' => now(),
            'resolved_at' => (string) $request->input('status') === 'resolved' ? now() : null,
        ];
        if (Schema::hasColumn('gymies_support_tickets', 'assigned_to_user_id')) {
            $update['assigned_to_user_id'] = $assignedToId;
        }
        if (Schema::hasColumn('gymies_support_tickets', 'close_reason')) {
            $update['close_reason'] = (string) $request->input('status') === 'resolved'
                ? trim((string) $request->input('close_reason', '')) ?: null
                : null;
        }
        DB::table('gymies_support_tickets')->where('id', $id)->update($update);

        $auditPayload = [
            'reason' => (string) $request->input('reason'),
            'old_status' => (string) $t->status,
            'new_status' => (string) $request->input('status'),
            'old_priority' => (string) $t->priority,
            'new_priority' => (string) $request->input('priority'),
        ];
        if ($request->has('assigned_to_user_id')) {
            $auditPayload['assigned_to_user_id'] = $assignedToId;
        }
        $this->audit((int) $admin->id, 'admin_ticket_updated', 'support_ticket', $id, $auditPayload);

        return response()->json(['ok' => true]);
    }

    public function ticketMessages(Request $request, string $ticketId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($ticketId)) {
            return response()->json(['message' => 'Ongeldige ticket id.'], 422);
        }
        if (!Schema::hasTable('gymies_support_ticket_messages')) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_support_ticket_messages')
            ->where('ticket_id', (int) $ticketId)
            ->orderBy('id')
            ->get();

        return response()->json(['data' => $rows]);
    }

    public function addTicketMessage(Request $request, string $ticketId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($ticketId)) {
            return response()->json(['message' => 'Ongeldige ticket id.'], 422);
        }
        $request->validate([
            'message' => 'required|string|max:5000',
            'is_internal' => 'nullable|boolean',
        ]);
        if (!Schema::hasTable('gymies_support_ticket_messages')) {
            return response()->json(['message' => 'Ticket messages tabel ontbreekt.'], 422);
        }
        $isInternal = $request->boolean('is_internal', true);
        $messageBody = trim((string) $request->input('message'));

        $id = DB::table('gymies_support_ticket_messages')->insertGetId([
            'ticket_id' => (int) $ticketId,
            'author_user_id' => (int) $admin->id,
            'message' => $messageBody,
            'is_internal' => $isInternal ? 1 : 0,
            'created_at' => now(),
        ]);

        if (!$isInternal && Schema::hasTable('gymies_support_tickets')) {
            $this->sendTicketReplyNotificationEmail((int) $ticketId, $messageBody);
            if (class_exists(\App\Helpers\GymiesSupportSync::class)) {
                \App\Helpers\GymiesSupportSync::syncAdminReplyToConversation((int) $ticketId, $messageBody);
            }
        }

        return response()->json(['data' => ['id' => (string) $id]], 201);
    }

    /**
     * Stuur e-mail naar de klant/trainer wanneer er een antwoord op het ticket is geplaatst.
     * Bij ontbrekende mailconfiguratie wordt alleen gelogd; de API-response faalt niet.
     */
    private function sendTicketReplyNotificationEmail(int $ticketId, string $messageBody): void
    {
        try {
            $ticket = DB::table('gymies_support_tickets')->where('id', $ticketId)->first();
            if (!$ticket || !isset($ticket->user_id)) {
                return;
            }
            $user = DB::table('gymies_users')->where('id', $ticket->user_id)->first();
            if (!$user || empty($user->email)) {
                return;
            }
            $email = (string) $user->email;
            $subject = 'TrainMate – Nieuw antwoord op je ticket';
            $preview = strlen($messageBody) > 200 ? substr($messageBody, 0, 197) . '...' : $messageBody;
            $body = "Er is een nieuw antwoord geplaatst op je supportticket.\n\n";
            $body .= "Antwoord:\n" . $preview . "\n\n";
            $body .= "Bekijk je ticket in de app onder Help → Mijn tickets.\n";

            Mail::raw($body, function ($message) use ($email, $subject): void {
                $message->to($email)->subject($subject);
            });
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->warning('Gymies ticket reply email failed', ['ticket_id' => $ticketId, 'error' => $e->getMessage()]);
            }
        }
    }

    /** Dupliceer ticket: nieuw ticket voor dezelfde klant met nieuw onderwerp (zelfde categorie/prioriteit). */
    public function duplicateTicket(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.tickets.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'source_ticket_id' => 'required|integer|min:1',
            'new_subject' => 'required|string|max:255',
        ]);
        if (!Schema::hasTable('gymies_support_tickets') || !Schema::hasTable('gymies_support_ticket_messages')) {
            return response()->json(['message' => 'Support niet beschikbaar.'], 503);
        }
        $sourceId = (int) $request->input('source_ticket_id');
        $source = DB::table('gymies_support_tickets')->where('id', $sourceId)->first();
        if (!$source) {
            return response()->json(['message' => 'Bron-ticket niet gevonden.'], 404);
        }
        $newSubject = trim((string) $request->input('new_subject'));
        $newId = DB::table('gymies_support_tickets')->insertGetId([
            'user_id' => (int) $source->user_id,
            'subject' => $newSubject,
            'category' => (string) ($source->category ?? 'general'),
            'priority' => (string) ($source->priority ?? 'medium'),
            'status' => 'new',
            'assigned_to_user_id' => null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $firstMessage = DB::table('gymies_support_ticket_messages')
            ->where('ticket_id', $sourceId)
            ->where('is_internal', 0)
            ->orderBy('id')
            ->first();
        $body = $firstMessage ? trim((string) $firstMessage->message) : 'Vervolgvraag (gedupliceerd van ticket #' . $sourceId . ').';
        if (strlen($body) > 5000) {
            $body = substr($body, 0, 4997) . '...';
        }
        DB::table('gymies_support_ticket_messages')->insert([
            'ticket_id' => $newId,
            'author_user_id' => (int) $source->user_id,
            'message' => $body,
            'is_internal' => 0,
            'created_at' => now(),
        ]);
        $this->audit((int) $admin->id, 'admin_ticket_duplicated', 'support_ticket', $newId, ['source_ticket_id' => $sourceId]);
        return response()->json(['data' => ['id' => (string) $newId]], 201);
    }
}
