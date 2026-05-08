<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Helpers\GymiesSupportSync;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Gymies Support: klant/trainer/gym kunnen een ticket aanmaken en berichten uitwisselen.
 * Alleen eigen tickets zijn zichtbaar. Admin beheert tickets via GymiesAdminController.
 */
final class GymiesSupportController extends Controller
{
    /**
     * Lijst van eigen tickets (ingelogde user).
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $this->ensureSupportTables();
        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['data' => []]);
        }

        $cols = ['id', 'subject', 'category', 'priority', 'status', 'created_at', 'updated_at'];
        if (Schema::hasColumn('gymies_support_tickets', 'submitter_name')) {
            $cols[] = 'submitter_name';
            $cols[] = 'submitter_email';
            $cols[] = 'submitter_phone';
        }
        $rows = DB::table('gymies_support_tickets')
            ->where('user_id', (int) $user->id)
            ->orderByDesc('updated_at')
            ->get($cols);

        $data = $rows->map(function ($r) {
            $item = [
                'id' => (string) $r->id,
                'subject' => (string) ($r->subject ?? ''),
                'category' => (string) ($r->category ?? 'general'),
                'priority' => (string) ($r->priority ?? 'medium'),
                'status' => (string) ($r->status ?? 'new'),
                'created_at' => $r->created_at,
                'updated_at' => $r->updated_at,
            ];
            if (isset($r->submitter_name, $r->submitter_email, $r->submitter_phone)) {
                $item['submitter_name'] = (string) ($r->submitter_name ?? '');
                $item['submitter_email'] = (string) ($r->submitter_email ?? '');
                $item['submitter_phone'] = (string) ($r->submitter_phone ?? '');
            }
            return $item;
        })->all();

        return response()->json(['data' => $data]);
    }

    /**
     * Nieuw ticket aanmaken (met eerste bericht).
     */
    public function store(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        $request->validate([
            'subject' => 'required|string|max:255',
            'message' => 'required|string|max:5000',
            'category' => 'nullable|string|max:80|in:general,booking,payment,account,technical,other',
            'priority' => 'nullable|string|max:20|in:low,medium,high,critical',
            'contact_name' => 'nullable|string|max:255',
            'contact_email' => 'nullable|string|email|max:255',
            'contact_phone' => 'nullable|string|max:32',
        ]);
        $this->ensureSupportTables();
        $this->ensureSupportTicketContactColumns();
        if (!Schema::hasTable('gymies_support_tickets') || !Schema::hasTable('gymies_support_ticket_messages')) {
            return response()->json(['message' => 'Support niet beschikbaar.'], 503);
        }

        $category = trim((string) ($request->input('category') ?? 'general'));
        $priority = trim((string) ($request->input('priority') ?? 'medium'));
        $subject = strip_tags(trim((string) $request->input('subject')));
        $message = strip_tags(trim((string) $request->input('message')));

        $userRow = DB::table('gymies_users')->where('id', (int) $user->id)->first(['email', 'display_name', 'first_name', 'last_name', 'phone']);
        $submitterName = strip_tags(trim((string) ($request->input('contact_name') ?? '')));
        $submitterEmail = trim((string) ($request->input('contact_email') ?? ''));
        $submitterPhone = strip_tags(trim((string) ($request->input('contact_phone') ?? '')));
        if ($submitterName === '' && $userRow) {
            $submitterName = trim(($userRow->first_name ?? '') . ' ' . ($userRow->last_name ?? '')) ?: (string) ($userRow->display_name ?? '');
        }
        if ($submitterEmail === '' && $userRow) {
            $submitterEmail = (string) ($userRow->email ?? '');
        }
        if ($submitterPhone === '' && $userRow) {
            $submitterPhone = (string) ($userRow->phone ?? '');
        }

        $insert = [
            'user_id' => (int) $user->id,
            'subject' => $subject,
            'category' => $category,
            'priority' => $priority,
            'status' => 'new',
            'created_at' => now(),
            'updated_at' => now(),
        ];
        if (Schema::hasColumn('gymies_support_tickets', 'submitter_name')) {
            $insert['submitter_name'] = $submitterName ?: null;
            $insert['submitter_email'] = $submitterEmail ?: null;
            $insert['submitter_phone'] = $submitterPhone ?: null;
        }
        $ticketId = DB::table('gymies_support_tickets')->insertGetId($insert);

        DB::table('gymies_support_ticket_messages')->insert([
            'ticket_id' => $ticketId,
            'author_user_id' => (int) $user->id,
            'message' => $message,
            'is_internal' => 0,
            'created_at' => now(),
        ]);

        GymiesSupportSync::ensureSupportConversationForTicket($ticketId, (int) $user->id, $message);

        $ticket = DB::table('gymies_support_tickets')->where('id', $ticketId)->first();
        $data = [
            'id' => (string) $ticketId,
            'subject' => $ticket->subject,
            'category' => $ticket->category,
            'priority' => $ticket->priority,
            'status' => $ticket->status,
            'created_at' => $ticket->created_at,
            'updated_at' => $ticket->updated_at,
        ];
        if (Schema::hasColumn('gymies_support_tickets', 'submitter_name')) {
            $data['submitter_name'] = (string) ($ticket->submitter_name ?? '');
            $data['submitter_email'] = (string) ($ticket->submitter_email ?? '');
            $data['submitter_phone'] = (string) ($ticket->submitter_phone ?? '');
        }
        return response()->json(['data' => $data], 201);
    }

    /**
     * Eén ticket ophalen (alleen eigen) met berichten (alleen niet-intern).
     */
    public function show(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!ctype_digit($id) || (int) $id < 1) {
            return response()->json(['message' => 'Ongeldige ticket id.'], 422);
        }
        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['message' => 'Ticket niet gevonden.'], 404);
        }

        $ticket = DB::table('gymies_support_tickets')
            ->where('id', (int) $id)
            ->where('user_id', (int) $user->id)
            ->first();

        if (!$ticket) {
            return response()->json(['message' => 'Ticket niet gevonden.'], 404);
        }

        $messages = [];
        if (Schema::hasTable('gymies_support_ticket_messages')) {
            $rows = DB::table('gymies_support_ticket_messages')
                ->where('ticket_id', (int) $id)
                ->where('is_internal', 0)
                ->orderBy('id')
                ->get(['id', 'author_user_id', 'message', 'created_at']);
            foreach ($rows as $r) {
                $messages[] = [
                    'id' => (string) $r->id,
                    'author_user_id' => (string) $r->author_user_id,
                    'is_mine' => (int) $r->author_user_id === (int) $user->id,
                    'message' => (string) $r->message,
                    'created_at' => $r->created_at,
                ];
            }
        }

        $res = [
            'id' => (string) $ticket->id,
            'subject' => (string) $ticket->subject,
            'category' => (string) ($ticket->category ?? 'general'),
            'priority' => (string) ($ticket->priority ?? 'medium'),
            'status' => (string) ($ticket->status ?? 'new'),
            'created_at' => $ticket->created_at,
            'updated_at' => $ticket->updated_at,
            'messages' => $messages,
        ];
        if (Schema::hasColumn('gymies_support_tickets', 'submitter_name')) {
            $res['submitter_name'] = (string) ($ticket->submitter_name ?? '');
            $res['submitter_email'] = (string) ($ticket->submitter_email ?? '');
            $res['submitter_phone'] = (string) ($ticket->submitter_phone ?? '');
        }
        return response()->json(['data' => $res]);
    }

    /**
     * Bericht toevoegen aan eigen ticket (klant/trainer/gym antwoordt).
     */
    public function addMessage(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!ctype_digit($id) || (int) $id < 1) {
            return response()->json(['message' => 'Ongeldige ticket id.'], 422);
        }
        $request->validate([
            'message' => 'required|string|max:5000',
        ]);
        if (!Schema::hasTable('gymies_support_tickets') || !Schema::hasTable('gymies_support_ticket_messages')) {
            return response()->json(['message' => 'Support niet beschikbaar.'], 503);
        }

        $ticket = DB::table('gymies_support_tickets')
            ->where('id', (int) $id)
            ->where('user_id', (int) $user->id)
            ->first();

        if (!$ticket) {
            return response()->json(['message' => 'Ticket niet gevonden.'], 404);
        }

        $messageText = trim((string) $request->input('message'));
        $msgId = DB::table('gymies_support_ticket_messages')->insertGetId([
            'ticket_id' => (int) $id,
            'author_user_id' => (int) $user->id,
            'message' => $messageText,
            'is_internal' => 0,
            'created_at' => now(),
        ]);

        DB::table('gymies_support_tickets')->where('id', (int) $id)->update([
            'updated_at' => now(),
            'status' => 'in_progress', // klant heeft geantwoord; support kan opnemen
        ]);

        GymiesSupportSync::syncUserReplyToConversation((int) $id, (int) $user->id, $messageText);

        return response()->json([
            'data' => [
                'id' => (string) $msgId,
                'message' => $messageText,
                'created_at' => now()->toDateTimeString(),
            ],
        ], 201);
    }

    /**
     * Klant/trainer geeft aan "ik ben geholpen" → ticket resolven + bevestigingsbericht.
     */
    public function markHelped(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!ctype_digit($id) || (int) $id < 1) {
            return response()->json(['message' => 'Ongeldige ticket id.'], 422);
        }
        if (!Schema::hasTable('gymies_support_tickets') || !Schema::hasTable('gymies_support_ticket_messages')) {
            return response()->json(['message' => 'Support niet beschikbaar.'], 503);
        }

        $ticket = DB::table('gymies_support_tickets')
            ->where('id', (int) $id)
            ->where('user_id', (int) $user->id)
            ->first();

        if (!$ticket) {
            return response()->json(['message' => 'Ticket niet gevonden.'], 404);
        }

        $status = (string) ($ticket->status ?? '');
        if ($status === 'resolved') {
            return response()->json(['data' => ['status' => 'resolved', 'message' => 'Al afgesloten.']]);
        }

        DB::table('gymies_support_tickets')->where('id', (int) $id)->update([
            'status' => 'resolved',
            'updated_at' => now(),
            'resolved_at' => now(),
        ]);

        $confirmation = 'We sluiten dit ticket. Bedankt!';
        DB::table('gymies_support_ticket_messages')->insert([
            'ticket_id' => (int) $id,
            'author_user_id' => (int) $user->id,
            'message' => 'Ik ben geholpen.',
            'is_internal' => 0,
            'created_at' => now(),
        ]);

        if (class_exists(GymiesSupportSync::class)) {
            GymiesSupportSync::syncUserReplyToConversation((int) $id, (int) $user->id, 'Ik ben geholpen.');
            GymiesSupportSync::syncAdminReplyToConversation((int) $id, $confirmation);
        }

        return response()->json([
            'data' => [
                'status' => 'resolved',
                'confirmation' => $confirmation,
            ],
        ]);
    }

    private function ensureSupportTables(): void
    {
        if (Schema::hasTable('gymies_support_tickets') && Schema::hasTable('gymies_support_ticket_messages')) {
            return;
        }
        try {
            if (!Schema::hasTable('gymies_support_tickets')) {
                DB::statement("
                    CREATE TABLE IF NOT EXISTS gymies_support_tickets (
                        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                        user_id BIGINT UNSIGNED NOT NULL,
                        subject VARCHAR(255) NOT NULL,
                        category VARCHAR(80) NOT NULL DEFAULT 'general',
                        priority VARCHAR(20) NOT NULL DEFAULT 'medium',
                        status VARCHAR(40) NOT NULL DEFAULT 'new',
                        assigned_to_user_id BIGINT UNSIGNED DEFAULT NULL,
                        submitter_name VARCHAR(255) DEFAULT NULL,
                        submitter_email VARCHAR(255) DEFAULT NULL,
                        submitter_phone VARCHAR(32) DEFAULT NULL,
                        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                        resolved_at TIMESTAMP NULL DEFAULT NULL,
                        PRIMARY KEY (id),
                        KEY gymies_support_tickets_user_idx (user_id),
                        KEY gymies_support_tickets_status_idx (status),
                        KEY gymies_support_tickets_priority_idx (priority)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            }
            if (!Schema::hasTable('gymies_support_ticket_messages')) {
                DB::statement("
                    CREATE TABLE IF NOT EXISTS gymies_support_ticket_messages (
                        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                        ticket_id BIGINT UNSIGNED NOT NULL,
                        author_user_id BIGINT UNSIGNED NOT NULL,
                        message TEXT NOT NULL,
                        is_internal TINYINT(1) NOT NULL DEFAULT 1,
                        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                        PRIMARY KEY (id),
                        KEY gymies_support_ticket_messages_ticket_idx (ticket_id),
                        KEY gymies_support_ticket_messages_author_idx (author_user_id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            }
        } catch (\Throwable $e) {
            // Fail-open: volgende request kan opnieuw proberen
        }
    }

    private function ensureSupportTicketContactColumns(): void
    {
        if (!Schema::hasTable('gymies_support_tickets')) {
            return;
        }
        if (Schema::hasColumn('gymies_support_tickets', 'submitter_name')) {
            return;
        }
        try {
            DB::statement('ALTER TABLE gymies_support_tickets ADD COLUMN submitter_name VARCHAR(255) DEFAULT NULL');
            DB::statement('ALTER TABLE gymies_support_tickets ADD COLUMN submitter_email VARCHAR(255) DEFAULT NULL');
            DB::statement('ALTER TABLE gymies_support_tickets ADD COLUMN submitter_phone VARCHAR(32) DEFAULT NULL');
        } catch (\Throwable $e) {
            // Kolommen bestaan mogelijk al (bijv. na alter_gymies_support_ticket_contact.sql)
        }
    }
}
