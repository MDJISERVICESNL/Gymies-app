#!/bin/bash
# =============================================================================
# Fix: Update GymiesDisputeController om ook support tickets met
#      is_dispute=true te tonen als geschillen
# =============================================================================
# Run: ssh gymies "bash -s" < backend/gymies_deploy/fix_disputes_v2.sh
# =============================================================================

set -e
cd /var/www/gymies

echo "============================================"
echo "  FIX: Geschillen — support tickets tonen   "
echo "============================================"
echo ""

CTRL="/var/www/gymies/app/Http/Controllers/Gymies/GymiesDisputeController.php"

echo "▸ Controller updaten..."

cat > "$CTRL" << 'CONTROLLEREOF'
<?php

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Client-facing dispute (geschillen) endpoints.
 * Combineert gymies_disputes + gymies_support_tickets (is_dispute=true).
 */
class GymiesDisputeController extends Controller
{
    private function user(Request $request): ?object
    {
        return $request->attributes->get('gymies_user');
    }

    private function unauthorized(): JsonResponse
    {
        return response()->json(['message' => 'Niet ingelogd.'], 401);
    }

    private function tablesMissing(): bool
    {
        return !Schema::hasTable('gymies_disputes');
    }

    // ── GET my-disputes ──────────────────────────────────────────────

    public function index(Request $request): JsonResponse
    {
        $user = $this->user($request);
        if (!$user) return $this->unauthorized();

        $userId = (int) $user->id;
        $results = collect();

        // Bron 1: gymies_disputes tabel
        if (Schema::hasTable('gymies_disputes')) {
            $disputes = DB::table('gymies_disputes as d')
                ->leftJoin('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
                ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
                ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
                ->where(function ($q) use ($userId) {
                    $q->where('d.raised_by_user_id', $userId)
                      ->orWhere('b.client_user_id', $userId)
                      ->orWhere('b.trainer_user_id', $userId);
                })
                ->orderByDesc('d.created_at')
                ->select([
                    'd.id', 'd.booking_id', 'd.reason', 'd.details', 'd.status',
                    'd.created_at', 'd.closed_at',
                    DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                    DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                ])
                ->limit(50)
                ->get()
                ->map(function ($d) {
                    $d->other_party = $d->trainer_name;
                    $d->source = 'dispute';
                    if (Schema::hasColumn('gymies_disputes', 'resolution_type')) {
                        $d->resolution_type = DB::table('gymies_disputes')->where('id', $d->id)->value('resolution_type');
                    }
                    return $d;
                });
            $results = $results->merge($disputes);
        }

        // Bron 2: gymies_support_tickets met is_dispute = true
        if (Schema::hasTable('gymies_support_tickets') && Schema::hasColumn('gymies_support_tickets', 'is_dispute')) {
            $tickets = DB::table('gymies_support_tickets as st')
                ->leftJoin('gymies_bookings as b', 'b.id', '=', 'st.booking_id')
                ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
                ->where('st.user_id', $userId)
                ->where('st.is_dispute', true)
                ->orderByDesc('st.created_at')
                ->select([
                    DB::raw("CONCAT('ticket_', st.id) as id"),
                    'st.booking_id',
                    'st.subject as reason',
                    DB::raw('NULL as details'),
                    DB::raw("CASE
                        WHEN st.status IN ('closed', 'resolved') THEN 'resolved'
                        WHEN st.status = 'in_progress' THEN 'in_progress'
                        ELSE 'open'
                    END as status"),
                    'st.created_at',
                    DB::raw('NULL as closed_at'),
                    DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                    DB::raw('NULL as client_name'),
                ])
                ->limit(50)
                ->get()
                ->map(function ($t) {
                    $t->other_party = $t->trainer_name ?? 'Gymies Support';
                    $t->source = 'ticket';
                    return $t;
                });
            $results = $results->merge($tickets);
        }

        $results = $results->sortByDesc('created_at')->values()->take(50);

        return response()->json(['data' => $results]);
    }

    // ── GET my-disputes/{id} ─────────────────────────────────────────

    public function show(Request $request, string $disputeId): JsonResponse
    {
        $user = $this->user($request);
        if (!$user) return $this->unauthorized();

        $userId = (int) $user->id;

        // Support ticket dispute (id = "ticket_123")
        if (str_starts_with($disputeId, 'ticket_')) {
            return $this->showTicketDispute($request, $disputeId, $userId);
        }

        if (!is_numeric($disputeId) || $this->tablesMissing()) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        $id = (int) $disputeId;

        $d = DB::table('gymies_disputes as d')
            ->leftJoin('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->where('d.id', $id)
            ->where(function ($q) use ($userId) {
                $q->where('d.raised_by_user_id', $userId)
                  ->orWhere('b.client_user_id', $userId)
                  ->orWhere('b.trainer_user_id', $userId);
            })
            ->select(['d.*',
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                'b.scheduled_at', 'b.amount_cents', 'b.status as booking_status',
            ])
            ->first();

        if (!$d) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        $d->other_party = $d->trainer_name;

        $messages = [];
        if (Schema::hasTable('gymies_dispute_messages')) {
            $messages = DB::table('gymies_dispute_messages as m')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'm.author_user_id')
                ->where('m.dispute_id', $id)
                ->where(function ($q) {
                    $q->where('m.is_internal', false)
                      ->orWhereNull('m.is_internal');
                })
                ->orderBy('m.created_at')
                ->get(['m.id', 'm.author_user_id', 'm.message', 'm.created_at',
                    DB::raw('COALESCE(u.display_name, u.email) as author'),
                ])
                ->map(function ($m) use ($userId) {
                    $m->is_mine = ((int) $m->author_user_id === $userId);
                    return $m;
                })
                ->all();
        }

        return response()->json([
            'data' => array_merge((array) $d, ['messages' => $messages]),
        ]);
    }

    // ── Support ticket als dispute tonen ──────────────────────────────

    private function showTicketDispute(Request $request, string $disputeId, int $userId): JsonResponse
    {
        $ticketId = (int) str_replace('ticket_', '', $disputeId);

        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        $ticket = DB::table('gymies_support_tickets as st')
            ->leftJoin('gymies_bookings as b', 'b.id', '=', 'st.booking_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->where('st.id', $ticketId)
            ->where('st.user_id', $userId)
            ->first([
                'st.*',
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                'b.scheduled_at', 'b.amount_cents', 'b.status as booking_status',
            ]);

        if (!$ticket) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        $status = match (true) {
            in_array($ticket->status, ['closed', 'resolved']) => 'resolved',
            $ticket->status === 'in_progress' => 'in_progress',
            default => 'open',
        };

        $data = [
            'id'             => $disputeId,
            'booking_id'     => $ticket->booking_id,
            'reason'         => $ticket->subject ?? '',
            'details'        => '',
            'status'         => $status,
            'other_party'    => $ticket->trainer_name ?? 'Gymies Support',
            'created_at'     => $ticket->created_at,
            'closed_at'      => $status === 'resolved' ? $ticket->updated_at : null,
            'scheduled_at'   => $ticket->scheduled_at ?? null,
            'amount_cents'   => $ticket->amount_cents ?? null,
            'booking_status' => $ticket->booking_status ?? null,
        ];

        $messages = [];
        if (Schema::hasTable('gymies_support_messages')) {
            $messages = DB::table('gymies_support_messages as m')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'm.user_id')
                ->where('m.ticket_id', $ticketId)
                ->orderBy('m.created_at')
                ->get([
                    'm.id', 'm.user_id as author_user_id', 'm.message', 'm.created_at',
                    DB::raw('COALESCE(u.display_name, u.email) as author'),
                ])
                ->map(function ($m) use ($userId) {
                    $m->is_mine = ((int) $m->author_user_id === $userId);
                    return $m;
                })
                ->all();
        }

        $data['messages'] = $messages;

        return response()->json(['data' => $data]);
    }

    // ── POST my-disputes/{id}/message ────────────────────────────────

    public function addMessage(Request $request, string $disputeId): JsonResponse
    {
        $user = $this->user($request);
        if (!$user) return $this->unauthorized();

        $request->validate([
            'message' => 'required|string|max:2000',
        ]);

        $userId = (int) $user->id;
        $msgText = mb_substr(trim($request->input('message')), 0, 2000);

        // Support ticket dispute
        if (str_starts_with($disputeId, 'ticket_')) {
            return $this->addTicketMessage($disputeId, $userId, $msgText, $user);
        }

        if ($this->tablesMissing() || !is_numeric($disputeId)) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        $id = (int) $disputeId;

        $d = DB::table('gymies_disputes as d')
            ->leftJoin('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
            ->where('d.id', $id)
            ->where(function ($q) use ($userId) {
                $q->where('d.raised_by_user_id', $userId)
                  ->orWhere('b.client_user_id', $userId)
                  ->orWhere('b.trainer_user_id', $userId);
            })
            ->first(['d.id', 'd.status']);

        if (!$d) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        if ($d->status === 'resolved') {
            return response()->json(['message' => 'Dit geschil is al opgelost.'], 422);
        }

        if (!Schema::hasTable('gymies_dispute_messages')) {
            return response()->json(['message' => 'Berichten niet beschikbaar.'], 503);
        }

        $msgId = DB::table('gymies_dispute_messages')->insertGetId([
            'dispute_id'     => $id,
            'author_user_id' => $userId,
            'message'        => $msgText,
            'is_internal'    => false,
            'created_at'     => now(),
        ]);

        return response()->json([
            'data' => [
                'id'         => $msgId,
                'dispute_id' => $id,
                'message'    => $msgText,
                'author'     => $user->display_name ?? $user->email ?? 'Jij',
                'is_mine'    => true,
                'created_at' => now()->toISOString(),
            ],
        ]);
    }

    // ── Helper: bericht toevoegen aan ticket-based dispute ──────────

    private function addTicketMessage(string $disputeId, int $userId, string $msgText, object $user): JsonResponse
    {
        $ticketId = (int) str_replace('ticket_', '', $disputeId);

        if (!Schema::hasTable('gymies_support_tickets')) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        $ticket = DB::table('gymies_support_tickets')
            ->where('id', $ticketId)
            ->where('user_id', $userId)
            ->first(['id', 'status']);

        if (!$ticket) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        if (in_array($ticket->status, ['closed', 'resolved'])) {
            return response()->json(['message' => 'Dit geschil is al opgelost.'], 422);
        }

        if (!Schema::hasTable('gymies_support_messages')) {
            return response()->json(['message' => 'Berichten niet beschikbaar.'], 503);
        }

        $msgId = DB::table('gymies_support_messages')->insertGetId([
            'ticket_id'  => $ticketId,
            'user_id'    => $userId,
            'message'    => $msgText,
            'created_at' => now(),
        ]);

        return response()->json([
            'data' => [
                'id'         => $msgId,
                'dispute_id' => $disputeId,
                'message'    => $msgText,
                'author'     => $user->display_name ?? $user->email ?? 'Jij',
                'is_mine'    => true,
                'created_at' => now()->toISOString(),
            ],
        ]);
    }

    // ── POST bookings/{id}/dispute ───────────────────────────────────

    public function raise(Request $request, string $bookingId): JsonResponse
    {
        $user = $this->user($request);
        if (!$user) return $this->unauthorized();

        $request->validate([
            'reason'  => 'required|string|max:500',
            'details' => 'nullable|string|max:2000',
        ]);

        if (!is_numeric($bookingId)) {
            return response()->json(['message' => 'Ongeldige boeking.'], 422);
        }

        $userId = (int) $user->id;
        $bId = (int) $bookingId;

        $booking = DB::table('gymies_bookings')
            ->where('id', $bId)
            ->where(function ($q) use ($userId) {
                $q->where('client_user_id', $userId)
                  ->orWhere('trainer_user_id', $userId);
            })
            ->first();

        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        // Maak tabellen aan als ze niet bestaan
        if ($this->tablesMissing()) {
            Schema::create('gymies_disputes', function ($t) {
                $t->bigIncrements('id');
                $t->unsignedBigInteger('booking_id')->index();
                $t->unsignedBigInteger('raised_by_user_id')->index();
                $t->string('reason', 500);
                $t->text('details')->nullable();
                $t->enum('status', ['open', 'in_progress', 'resolved'])->default('open');
                $t->string('resolution_type', 32)->nullable();
                $t->text('resolution_notes')->nullable();
                $t->unsignedBigInteger('resolved_by_user_id')->nullable();
                $t->timestamp('closed_at')->nullable();
                $t->timestamps();
            });
        }

        if (!Schema::hasTable('gymies_dispute_messages')) {
            Schema::create('gymies_dispute_messages', function ($t) {
                $t->bigIncrements('id');
                $t->unsignedBigInteger('dispute_id')->index();
                $t->unsignedBigInteger('author_user_id')->index();
                $t->text('message');
                $t->boolean('is_internal')->default(false);
                $t->timestamp('created_at')->useCurrent();
            });
        }

        $existing = DB::table('gymies_disputes')
            ->where('booking_id', $bId)
            ->whereIn('status', ['open', 'in_progress'])
            ->first();

        if ($existing) {
            return response()->json([
                'message' => 'Er is al een lopend geschil voor deze boeking.',
                'data'    => ['id' => $existing->id],
            ], 409);
        }

        $disputeId = DB::table('gymies_disputes')->insertGetId([
            'booking_id'         => $bId,
            'raised_by_user_id'  => $userId,
            'reason'             => mb_substr(trim($request->input('reason')), 0, 500),
            'details'            => $request->input('details') ? mb_substr(trim($request->input('details')), 0, 2000) : null,
            'status'             => 'open',
            'created_at'         => now(),
            'updated_at'         => now(),
        ]);

        return response()->json([
            'data' => [
                'id'         => $disputeId,
                'booking_id' => $bId,
                'status'     => 'open',
                'reason'     => trim($request->input('reason')),
                'created_at' => now()->toISOString(),
            ],
        ], 201);
    }
}
CONTROLLEREOF

echo "  ✅ Controller updated"

echo ""
echo "▸ Caches legen..."
php artisan config:clear 2>/dev/null || true
php artisan route:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true
echo "  ✅ Done"

echo ""
echo "▸ Quick check: support tickets met is_dispute..."
php artisan tinker --execute="
if (\Illuminate\Support\Facades\Schema::hasTable('gymies_support_tickets') && \Illuminate\Support\Facades\Schema::hasColumn('gymies_support_tickets', 'is_dispute')) {
    \$count = \Illuminate\Support\Facades\DB::table('gymies_support_tickets')->where('is_dispute', true)->count();
    echo \"  📊 Support tickets met is_dispute=true: \$count\n\";
    if (\$count > 0) {
        \$tickets = \Illuminate\Support\Facades\DB::table('gymies_support_tickets')
            ->where('is_dispute', true)
            ->orderByDesc('created_at')
            ->limit(5)
            ->get(['id', 'subject', 'status', 'user_id', 'created_at']);
        foreach (\$tickets as \$t) {
            echo \"  → ticket_{\$t->id}: {\$t->subject} [status: {\$t->status}, user: {\$t->user_id}]\n\";
        }
    }
} else {
    echo \"  ℹ️ gymies_support_tickets heeft geen is_dispute kolom\n\";
}

if (\Illuminate\Support\Facades\Schema::hasTable('gymies_disputes')) {
    \$count = \Illuminate\Support\Facades\DB::table('gymies_disputes')->count();
    echo \"  📊 gymies_disputes records: \$count\n\";
}
"

echo ""
echo "============================================"
echo "  Fix complete! Test Geschillen opnieuw.     "
echo "============================================"
