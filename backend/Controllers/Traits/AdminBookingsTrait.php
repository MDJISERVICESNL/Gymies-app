<?php

namespace App\Http\Controllers\Gymies\Traits;

use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

trait AdminBookingsTrait
{
    public function bookingsMonitor(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => []]);
        }
        $status = trim((string) $request->query('status', ''));
        $dateFrom = trim((string) $request->query('date_from', ''));
        $dateTo = trim((string) $request->query('date_to', ''));
        $trainerId = $request->query('trainer_id') ? (int) $request->query('trainer_id') : null;
        $clientId = $request->query('client_id') ? (int) $request->query('client_id') : null;
        $limit = min(max((int) $request->query('limit', 200), 1), 1000);

        $query = DB::table('gymies_bookings as b')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->orderByDesc('b.id')
            ->select([
                'b.id',
                'b.status',
                'b.scheduled_at',
                'b.duration_minutes',
                'b.amount_cents',
                'b.paid_at',
                'b.client_user_id',
                'b.trainer_user_id',
                'b.created_at',
                DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
            ]);
        if ($status !== '') {
            $query->where('b.status', $status);
        }
        if ($dateFrom !== '') {
            $query->where('b.scheduled_at', '>=', $dateFrom);
        }
        if ($dateTo !== '') {
            $query->where('b.scheduled_at', '<=', $dateTo . ' 23:59:59');
        }
        if ($trainerId !== null && $trainerId > 0) {
            $query->where('b.trainer_user_id', $trainerId);
        }
        if ($clientId !== null && $clientId > 0) {
            $query->where('b.client_user_id', $clientId);
        }

        return response()->json(['data' => $query->limit($limit)->get()]);
    }

    /** Eén boeking met klant/trainer en optionele velden. */
    public function bookingDetail(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }
        $id = (int) $bookingId;
        $b = DB::table('gymies_bookings as b')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->where('b.id', $id)
            ->select([
                'b.id', 'b.status', 'b.scheduled_at', 'b.duration_minutes', 'b.amount_cents',
                'b.paid_at', 'b.client_user_id', 'b.trainer_user_id', 'b.created_at', 'b.updated_at',
                'b.location_type', 'b.location_notes', 'b.client_notes', 'b.trainer_notes',
                DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                DB::raw('c.email as client_email'),
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                DB::raw('t.email as trainer_email'),
            ])
            ->first();
        if (!$b) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        return response()->json(['data' => $b]);
    }

    /** Boeking annuleren namens admin (met reden; optioneel refund-vlag voor rapportage). */
    public function cancelBooking(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        $request->validate([
            'reason' => 'required|string|max:500',
            'refund' => 'nullable|boolean',
        ]);
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }
        $id = (int) $bookingId;
        $b = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$b) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if (in_array((string) $b->status, ['cancelled', 'completed'], true)) {
            return response()->json(['message' => 'Deze boeking kan niet meer geannuleerd worden.'], 422);
        }
        $update = [
            'status' => 'cancelled',
            'updated_at' => now(),
            'cancelled_at' => now(),
            'cancelled_by_user_id' => (int) $admin->id,
        ];
        if (Schema::hasColumn('gymies_bookings', 'cancelled_by_user_id')) {
            $update['cancelled_by_user_id'] = (int) $admin->id;
        }
        DB::table('gymies_bookings')->where('id', $id)->update($update);
        $this->audit((int) $admin->id, 'admin_booking_cancelled', 'booking', $id, [
            'reason' => (string) $request->input('reason'),
            'refund' => $request->boolean('refund', false),
        ]);
        return response()->json(['ok' => true]);
    }

    /**
     * Forceer Refund / Boete kwijtschelden: bij overmacht kan admin de €25 boete van de trainer weghalen.
     * POST met reason (verplicht). Verhoogt trainer_balance_cents met 2500.
     */
    public function waiveTrainerPenalty(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        $request->validate(['reason' => 'required|string|max:500']);
        $bid = (int) $bookingId;
        $booking = DB::table('gymies_bookings')->where('id', $bid)->first(['trainer_user_id']);
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        $trainerId = (int) $booking->trainer_user_id;
        if (!Schema::hasColumn('gymies_users', 'trainer_balance_cents')) {
            return response()->json(['message' => 'Trainerbalans niet beschikbaar.'], 503);
        }
        $addCents = 2500;
        DB::table('gymies_users')->where('id', $trainerId)->increment('trainer_balance_cents', $addCents, ['updated_at' => now()]);
        $newBalance = (int) (DB::table('gymies_users')->where('id', $trainerId)->value('trainer_balance_cents') ?? 0);
        $this->audit((int) $admin->id, 'admin_waive_trainer_penalty', 'booking', $bid, [
            'reason' => (string) $request->input('reason'),
            'trainer_id' => $trainerId,
            'balance_before' => $current,
            'balance_after' => $newBalance,
        ]);
        return response()->json(['ok' => true, 'trainer_balance_cents' => $newBalance]);
    }

    /**
     * Refund of credit: volledige/gedeeltelijke terugbetaling (registratie) of credit naar wallet.
     * Bij wallet_credit wordt het bedrag aan de klant-wallet toegevoegd; bij refund alleen gelogd (Mollie later).
     * Optioneel: boeking automatisch op cancelled zetten (cancel_booking=true).
     */
    public function refundOrCredit(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        $request->validate([
            'type' => 'required|in:full_refund,partial_refund,wallet_credit,split',
            'amount_cents' => 'nullable|integer|min:1|max:5000000',
            'reason' => 'required|string|max:500',
            'cancel_booking' => 'nullable|boolean',
        ]);
        $id = (int) $bookingId;
        $type = (string) $request->input('type');
        $reason = trim((string) $request->input('reason'));
        $cancelBooking = $request->boolean('cancel_booking', true);

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }
        $b = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$b) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        $bookingStatus = (string) $b->status;
        if ($bookingStatus === 'cancelled') {
            return response()->json(['message' => 'Deze boeking kan niet worden terugbetaald of gecrediteerd.'], 422);
        }
        // Voor voltooide boekingen: alleen gedeeltelijke terugbetaling, wallet-credit of split.
        if ($bookingStatus === 'completed' && !in_array($type, ['partial_refund', 'wallet_credit', 'split'], true)) {
            return response()->json(['message' => 'Voor voltooide boekingen is alleen gedeeltelijke terugbetaling, wallet-credit of split toegestaan.'], 422);
        }
        if ($bookingStatus === 'completed') {
            $cancelBooking = false;
        }

        $bookingAmountCents = (int) ($b->amount_cents ?? 0);
        $amountCents = $request->has('amount_cents') ? (int) $request->input('amount_cents') : $bookingAmountCents;

        // Split: 50% naar klant (wallet), 50% blijft voor trainer (uitbetaling).
        if ($type === 'split') {
            $amountCents = (int) floor($bookingAmountCents / 2);
            $cancelBooking = false;
        }

        if ($type === 'partial_refund' && $amountCents <= 0) {
            return response()->json(['message' => 'Bij gedeeltelijke terugbetaling is amount_cents verplicht.'], 422);
        }
        if ($type !== 'partial_refund' && $type !== 'split' && $bookingAmountCents > 0) {
            $amountCents = $bookingAmountCents;
        }
        if ($amountCents > $bookingAmountCents) {
            $amountCents = $bookingAmountCents;
        }
        // Bij bankrefund (full/partial) wordt de admin-fee ingehouden; opgeslagen amount = bedrag dat naar klant gaat.
        if ($type === 'full_refund' || $type === 'partial_refund') {
            $feeCents = (int) $this->getSetting('bank_refund_admin_fee_cents', '99');
            $amountCents = max(0, $amountCents - $feeCents);
        }
        $clientUserId = (int) $b->client_user_id;

        if (!Schema::hasTable('gymies_admin_refunds')) {
            return response()->json(['message' => 'Refund-tabel niet beschikbaar. Draai migratie alter_gymies_wallet_and_refund.sql.'], 503);
        }

        $refundStatus = 'pending';
        if ($type === 'wallet_credit' || $type === 'split') {
            if (!Schema::hasTable('gymies_wallet_transactions') || !Schema::hasColumn('gymies_users', 'wallet_balance_cents')) {
                return response()->json(['message' => 'Wallet niet beschikbaar. Draai migratie alter_gymies_wallet_and_refund.sql.'], 503);
            }
            DB::table('gymies_users')->where('id', $clientUserId)->increment('wallet_balance_cents', $amountCents);
            $newBalance = (int) (DB::table('gymies_users')->where('id', $clientUserId)->value('wallet_balance_cents') ?? 0);
            $walletInsert = [
                'user_id' => $clientUserId,
                'amount_cents' => $amountCents,
                'balance_after_cents' => $newBalance,
                'booking_id' => $id,
                'reason' => $reason,
                'reference_type' => 'admin_refund_credit',
                'admin_user_id' => (int) $admin->id,
                'created_at' => now(),
            ];
            if (Schema::hasColumn('gymies_wallet_transactions', 'expires_at')) {
                $walletInsert['expires_at'] = now()->addYear()->toDateString();
            }
            DB::table('gymies_wallet_transactions')->insert($walletInsert);
            $refundStatus = 'completed';
        }

        DB::table('gymies_admin_refunds')->insert([
            'booking_id' => $id,
            'client_user_id' => $clientUserId,
            'type' => $type,
            'amount_cents' => $amountCents,
            'status' => $refundStatus,
            'reason' => $reason,
            'admin_user_id' => (int) $admin->id,
            'created_at' => now(),
        ]);

        if ($cancelBooking) {
            DB::table('gymies_bookings')->where('id', $id)->update([
                'status' => 'cancelled',
                'updated_at' => now(),
                'cancelled_at' => now(),
                'cancelled_by_user_id' => (int) $admin->id,
            ]);
        }

        $this->audit((int) $admin->id, 'admin_refund_or_credit', 'booking', $id, [
            'type' => $type,
            'amount_cents' => $amountCents,
            'reason' => $reason,
            'cancel_booking' => $cancelBooking,
            'refund_status' => $refundStatus,
        ]);

        return response()->json([
            'ok' => true,
            'type' => $type,
            'amount_cents' => $amountCents,
            'refund_status' => $refundStatus,
            'booking_cancelled' => $cancelBooking,
        ]);
    }

    /** Bulk: meerdere boekingen 100% refund naar wallet + annuleren (bijv. evenement geannuleerd). */
    public function bulkRefundToWallet(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'booking_ids' => 'required|array',
            'booking_ids.*' => 'integer|min:1',
            'reason' => 'required|string|max:500',
        ]);
        $ids = array_unique(array_filter(array_map('intval', $request->input('booking_ids', []))));
        if (count($ids) > 100) {
            return response()->json(['message' => 'Maximaal 100 boekingen per bulkactie.'], 422);
        }
        $reason = trim((string) $request->input('reason'));
        if (!Schema::hasTable('gymies_bookings') || !Schema::hasTable('gymies_admin_refunds')) {
            return response()->json(['message' => 'Bookings of refund-tabel niet beschikbaar.'], 503);
        }
        $hasWallet = Schema::hasTable('gymies_wallet_transactions') && Schema::hasColumn('gymies_users', 'wallet_balance_cents');
        $processed = 0;
        $skipped = 0;
        foreach ($ids as $id) {
            $b = DB::table('gymies_bookings')->where('id', $id)->first();
            if (!$b || in_array((string) $b->status, ['cancelled', 'completed'], true)) {
                $skipped++;
                continue;
            }
            $amountCents = (int) ($b->amount_cents ?? 0);
            $clientUserId = (int) $b->client_user_id;
            if ($hasWallet && $amountCents > 0) {
                DB::table('gymies_users')->where('id', $clientUserId)->increment('wallet_balance_cents', $amountCents);
                $newBalance = (int) (DB::table('gymies_users')->where('id', $clientUserId)->value('wallet_balance_cents') ?? 0);
                $walletInsert = [
                    'user_id' => $clientUserId,
                    'amount_cents' => $amountCents,
                    'balance_after_cents' => $newBalance,
                    'booking_id' => $id,
                    'reason' => $reason,
                    'reference_type' => 'admin_refund_credit',
                    'admin_user_id' => (int) $admin->id,
                    'created_at' => now(),
                ];
                if (Schema::hasColumn('gymies_wallet_transactions', 'expires_at')) {
                    $walletInsert['expires_at'] = now()->addYear()->toDateString();
                }
                DB::table('gymies_wallet_transactions')->insert($walletInsert);
            }
            DB::table('gymies_admin_refunds')->insert([
                'booking_id' => $id,
                'client_user_id' => $clientUserId,
                'type' => 'wallet_credit',
                'amount_cents' => $amountCents,
                'status' => $hasWallet ? 'completed' : 'pending',
                'reason' => $reason,
                'admin_user_id' => (int) $admin->id,
                'created_at' => now(),
            ]);
            DB::table('gymies_bookings')->where('id', $id)->update([
                'status' => 'cancelled',
                'updated_at' => now(),
                'cancelled_at' => now(),
                'cancelled_by_user_id' => (int) $admin->id,
            ]);
            $this->audit((int) $admin->id, 'admin_bulk_refund_wallet', 'booking', $id, ['amount_cents' => $amountCents, 'reason' => $reason]);
            $processed++;
        }
        return response()->json(['ok' => true, 'processed' => $processed, 'skipped' => $skipped]);
    }

    /** Boeking verplaatsen (nieuwe datum/tijd). */
    public function rescheduleBooking(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        $request->validate([
            'scheduled_at' => 'required|date',
            'reason' => 'required|string|max:500',
        ]);
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Bookings niet beschikbaar.'], 503);
        }
        $id = (int) $bookingId;
        $b = DB::table('gymies_bookings')->where('id', $id)->first();
        if (!$b) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        if (in_array((string) $b->status, ['cancelled', 'completed'], true)) {
            return response()->json(['message' => 'Deze boeking kan niet verplaatst worden.'], 422);
        }
        $newAt = $request->input('scheduled_at');
        DB::table('gymies_bookings')->where('id', $id)->update([
            'scheduled_at' => $newAt,
            'updated_at' => now(),
        ]);
        $this->audit((int) $admin->id, 'admin_booking_rescheduled', 'booking', $id, [
            'reason' => (string) $request->input('reason'),
            'old_scheduled_at' => $b->scheduled_at,
            'new_scheduled_at' => $newAt,
        ]);
        return response()->json(['ok' => true]);
    }

    public function addBookingIncident(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId)) {
            return response()->json(['message' => 'Ongeldige booking id.'], 422);
        }
        $request->validate([
            'note' => 'required|string|max:2000',
            'reason' => 'required|string|max:500',
            'create_ticket' => 'nullable|boolean',
        ]);
        if (!Schema::hasTable('gymies_admin_alerts')) {
            return response()->json(['message' => 'Admin alerts tabel ontbreekt.'], 422);
        }
        $bid = (int) $bookingId;
        $b = DB::table('gymies_bookings')->where('id', $bid)->first();
        if (!$b) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        $payload = [
            'alert_type' => 'booking_incident',
            'severity' => 'medium',
            'title' => 'Booking incident',
            'message' => trim((string) $request->input('note')),
            'entity_type' => 'booking',
            'entity_id' => $bid,
            'status' => 'open',
            'created_by_user_id' => (int) $admin->id,
            'created_at' => now(),
            'updated_at' => now(),
        ];
        if (Schema::hasColumn('gymies_admin_alerts', 'linked_ticket_id')) {
            $payload['linked_ticket_id'] = null;
        }
        $id = DB::table('gymies_admin_alerts')->insertGetId($payload);

        $linkedTicketId = null;
        $createTicket = $request->boolean('create_ticket', true);
        if ($createTicket && Schema::hasTable('gymies_support_tickets') && Schema::hasTable('gymies_support_ticket_messages')) {
            $clientUserId = (int) $b->client_user_id;
            $subject = 'Incident boeking #' . $bookingId . ' – ' . trim((string) $request->input('reason'));
            $note = trim((string) $request->input('note'));
            $ticketId = DB::table('gymies_support_tickets')->insertGetId([
                'user_id' => $clientUserId,
                'subject' => mb_substr($subject, 0, 255),
                'category' => 'booking',
                'priority' => 'high',
                'status' => 'new',
                'assigned_to_user_id' => null,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
            DB::table('gymies_support_ticket_messages')->insert([
                'ticket_id' => $ticketId,
                'author_user_id' => (int) $admin->id,
                'message' => "[Incident automatisch aangemaakt]\n\n" . $note,
                'is_internal' => 0,
                'created_at' => now(),
            ]);
            $linkedTicketId = $ticketId;
            if (Schema::hasColumn('gymies_admin_alerts', 'linked_ticket_id')) {
                DB::table('gymies_admin_alerts')->where('id', $id)->update(['linked_ticket_id' => $ticketId]);
            }
        }

        $this->audit((int) $admin->id, 'admin_booking_incident_added', 'booking', $bid, [
            'reason' => (string) $request->input('reason'),
            'incident_id' => (int) $id,
            'linked_ticket_id' => $linkedTicketId,
        ]);

        return response()->json([
            'ok' => true,
            'incident_id' => (string) $id,
            'linked_ticket_id' => $linkedTicketId ? (string) $linkedTicketId : null,
        ], 201);
    }

    /** Incidenten voor een boeking (bewijslast: ticket-berichten indien gekoppeld). */
    public function bookingIncidents(Request $request, string $bookingId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($bookingId) || !Schema::hasTable('gymies_admin_alerts')) {
            return response()->json(['data' => []]);
        }
        $bid = (int) $bookingId;
        $select = ['a.id', 'a.title', 'a.message', 'a.severity', 'a.status', 'a.created_at', DB::raw('COALESCE(u.display_name, u.email) as created_by_name')];
        if (Schema::hasColumn('gymies_admin_alerts', 'linked_ticket_id')) {
            $select[] = 'a.linked_ticket_id';
        }
        if (Schema::hasColumn('gymies_admin_alerts', 'resolution_type')) {
            $select[] = 'a.resolution_type';
            $select[] = 'a.resolution_reason';
            $select[] = 'a.resolved_at';
        }
        $alerts = DB::table('gymies_admin_alerts as a')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'a.created_by_user_id')
            ->where('a.entity_type', 'booking')
            ->where('a.entity_id', $bid)
            ->where('a.alert_type', 'booking_incident')
            ->orderByDesc('a.id')
            ->get($select);
        $hasLinkedTicket = Schema::hasColumn('gymies_admin_alerts', 'linked_ticket_id');
        $out = [];
        foreach ($alerts as $a) {
            $row = [
                'id' => (string) $a->id,
                'title' => $a->title ?? null,
                'message' => $a->message ?? null,
                'severity' => $a->severity ?? 'medium',
                'status' => $a->status ?? 'open',
                'created_at' => $a->created_at ?? null,
                'created_by_name' => $a->created_by_name ?? null,
                'resolution_type' => $a->resolution_type ?? null,
                'resolution_reason' => $a->resolution_reason ?? null,
                'resolved_at' => $a->resolved_at ?? null,
                'evidence' => [],
            ];
            if ($hasLinkedTicket && !empty($a->linked_ticket_id) && Schema::hasTable('gymies_support_ticket_messages')) {
                $messages = DB::table('gymies_support_ticket_messages as m')
                    ->leftJoin('gymies_users as u', 'u.id', '=', 'm.author_user_id')
                    ->where('m.ticket_id', $a->linked_ticket_id)
                    ->orderBy('m.id')
                    ->get(['m.id', 'm.message', 'm.is_internal', 'm.created_at', DB::raw('COALESCE(u.display_name, u.email) as author_name')]);
                $row['linked_ticket_id'] = (string) $a->linked_ticket_id;
                $row['evidence'] = $messages->map(fn ($m) => [
                    'message' => $m->message,
                    'author_name' => $m->author_name ?? null,
                    'is_internal' => (bool) $m->is_internal,
                    'created_at' => $m->created_at,
                ])->all();
            }
            $out[] = $row;
        }
        return response()->json(['data' => $out]);
    }

    /** Incident afhandelen: betaal trainer / geef klant credit / splits. */
    public function resolveIncident(Request $request, string $incidentId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        $request->validate([
            'resolution_type' => 'required|in:pay_trainer,give_client_credit,split',
            'reason' => 'required|string|max:500',
        ]);
        if (!$this->isPositiveId($incidentId) || !Schema::hasTable('gymies_admin_alerts')) {
            return response()->json(['message' => 'Incident niet gevonden.'], 404);
        }
        $id = (int) $incidentId;
        $alert = DB::table('gymies_admin_alerts')->where('id', $id)->where('alert_type', 'booking_incident')->first();
        if (!$alert || $alert->entity_type !== 'booking') {
            return response()->json(['message' => 'Incident niet gevonden.'], 404);
        }
        if (($alert->status ?? 'open') === 'resolved') {
            return response()->json(['message' => 'Dit incident is al afgehandeld.'], 422);
        }
        $resolutionType = (string) $request->input('resolution_type');
        $reason = trim((string) $request->input('reason'));
        $bookingId = (int) $alert->entity_id;
        $b = DB::table('gymies_bookings')->where('id', $bookingId)->first();
        $clientUserId = $b ? (int) $b->client_user_id : null;
        $trainerUserId = $b ? (int) $b->trainer_user_id : null;
        $amountCents = $b ? (int) ($b->amount_cents ?? 0) : 0;

        $update = [
            'status' => 'resolved',
            'updated_at' => now(),
        ];
        if (Schema::hasColumn('gymies_admin_alerts', 'resolution_type')) {
            $update['resolution_type'] = $resolutionType;
            $update['resolution_reason'] = $reason;
            $update['resolved_at'] = now();
            $update['resolved_by_user_id'] = (int) $admin->id;
        }
        DB::table('gymies_admin_alerts')->where('id', $id)->update($update);

        if ($resolutionType === 'give_client_credit' && $clientUserId && $amountCents > 0
            && Schema::hasTable('gymies_wallet_transactions') && Schema::hasColumn('gymies_users', 'wallet_balance_cents')) {
            $current = (int) (DB::table('gymies_users')->where('id', $clientUserId)->value('wallet_balance_cents') ?? 0);
            $newBalance = $current + $amountCents;
            DB::table('gymies_users')->where('id', $clientUserId)->update(['wallet_balance_cents' => $newBalance]);
            $walletInsert = [
                'user_id' => $clientUserId,
                'amount_cents' => $amountCents,
                'balance_after_cents' => $newBalance,
                'booking_id' => $bookingId,
                'reason' => 'Incident afgehandeld: credit voor klant. ' . $reason,
                'reference_type' => 'admin_refund_credit',
                'admin_user_id' => (int) $admin->id,
                'created_at' => now(),
            ];
            if (Schema::hasColumn('gymies_wallet_transactions', 'expires_at')) {
                $walletInsert['expires_at'] = now()->addYear()->toDateString();
            }
            DB::table('gymies_wallet_transactions')->insert($walletInsert);
        }
        if ($resolutionType === 'split' && $clientUserId && $amountCents > 0
            && Schema::hasTable('gymies_wallet_transactions') && Schema::hasColumn('gymies_users', 'wallet_balance_cents')) {
            $half = (int) round($amountCents / 2);
            $current = (int) (DB::table('gymies_users')->where('id', $clientUserId)->value('wallet_balance_cents') ?? 0);
            $newBalance = $current + $half;
            DB::table('gymies_users')->where('id', $clientUserId)->update(['wallet_balance_cents' => $newBalance]);
            $walletInsert = [
                'user_id' => $clientUserId,
                'amount_cents' => $half,
                'balance_after_cents' => $newBalance,
                'booking_id' => $bookingId,
                'reason' => 'Incident afgehandeld: 50% credit (splits). ' . $reason,
                'reference_type' => 'admin_refund_credit',
                'admin_user_id' => (int) $admin->id,
                'created_at' => now(),
            ];
            if (Schema::hasColumn('gymies_wallet_transactions', 'expires_at')) {
                $walletInsert['expires_at'] = now()->addYear()->toDateString();
            }
            DB::table('gymies_wallet_transactions')->insert($walletInsert);
        }

        $this->audit((int) $admin->id, 'admin_incident_resolved', 'admin_alert', $id, [
            'resolution_type' => $resolutionType,
            'reason' => $reason,
            'booking_id' => $bookingId,
        ]);

        return response()->json(['ok' => true, 'resolution_type' => $resolutionType]);
    }

    /** Dispute & Resolution: lijst open disputes. */
    public function disputes(Request $request): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!Schema::hasTable('gymies_disputes')) {
            return response()->json(['data' => []]);
        }
        $status = trim((string) $request->query('status', ''));
        $select = [
            'd.id', 'd.booking_id', 'd.raised_by_user_id', 'd.reason', 'd.details', 'd.status', 'd.closed_at', 'd.created_at',
            'b.scheduled_at', 'b.amount_cents', 'b.status as booking_status',
            DB::raw('COALESCE(c.display_name, c.email) as client_name'),
            DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
            DB::raw('COALESCE(r.display_name, r.email) as raised_by_name'),
        ];
        if (Schema::hasColumn('gymies_disputes', 'resolution_type')) {
            $select[] = 'd.resolution_type';
        }
        $query = DB::table('gymies_disputes as d')
            ->leftJoin('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->leftJoin('gymies_users as r', 'r.id', '=', 'd.raised_by_user_id')
            ->orderByDesc('d.id')
            ->select($select);
        if ($status !== '') {
            $query->where('d.status', $status);
        }
        $rows = $query->limit(100)->get();
        return response()->json(['data' => $rows]);
    }

    /** Dispute detail + berichten (chat). */
    public function disputeDetail(Request $request, string $disputeId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.view');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($disputeId) || !Schema::hasTable('gymies_disputes')) {
            return response()->json(['message' => 'Dispute niet gevonden.'], 404);
        }
        $id = (int) $disputeId;
        $d = DB::table('gymies_disputes as d')
            ->leftJoin('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->where('d.id', $id)
            ->select([
                'd.*', 'b.scheduled_at', 'b.amount_cents', 'b.status as booking_status', 'b.client_user_id', 'b.trainer_user_id',
                DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                DB::raw('c.email as client_email'),
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                DB::raw('t.email as trainer_email'),
            ])
            ->first();
        if (!$d) {
            return response()->json(['message' => 'Dispute niet gevonden.'], 404);
        }
        $messages = [];
        if (Schema::hasTable('gymies_dispute_messages')) {
            $messages = DB::table('gymies_dispute_messages as m')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'm.author_user_id')
                ->where('m.dispute_id', $id)
                ->orderBy('m.created_at')
                ->get(['m.id', 'm.author_user_id', 'm.message', 'm.is_internal', 'm.created_at', 'u.display_name as author_name'])
                ->all();
        }
        return response()->json(['data' => ['dispute' => $d, 'messages' => $messages]]);
    }

    /** Dispute oplossen: client (refund klant), trainer (payout vrij), split (50/50). */
    public function resolveDispute(Request $request, string $disputeId): JsonResponse
    {
        $admin = $this->requireAdmin($request, 'admin.bookings.manage');
        if ($admin instanceof JsonResponse) {
            return $admin;
        }
        if (!$this->isPositiveId($disputeId)) {
            return response()->json(['message' => 'Ongeldige dispute id.'], 422);
        }
        $request->validate([
            'resolution_type' => 'required|in:client,trainer,split',
            'reason' => 'required|string|max:500',
        ]);
        if (!Schema::hasTable('gymies_disputes')) {
            return response()->json(['message' => 'Disputes niet beschikbaar.'], 503);
        }
        $id = (int) $disputeId;
        $d = DB::table('gymies_disputes')->where('id', $id)->first();
        if (!$d || !in_array((string) $d->status, ['open', 'in_progress'], true)) {
            return response()->json(['message' => 'Dispute niet gevonden of al afgehandeld.'], 404);
        }
        $resolutionType = (string) $request->input('resolution_type');
        $reason = (string) $request->input('reason');
        $bookingId = (int) $d->booking_id;

        $update = ['status' => 'resolved', 'resolution_notes' => $reason, 'closed_at' => now()];
        if (Schema::hasColumn('gymies_disputes', 'resolution_type')) {
            $update['resolution_type'] = $resolutionType;
        }
        if (Schema::hasColumn('gymies_disputes', 'resolved_by_user_id')) {
            $update['resolved_by_user_id'] = (int) $admin->id;
        }
        DB::table('gymies_disputes')->where('id', $id)->update($update);

        $b = DB::table('gymies_bookings')->where('id', $bookingId)->first();
        if ($b) {
            if ($resolutionType === 'client') {
                DB::table('gymies_bookings')->where('id', $bookingId)->update([
                    'status' => 'cancelled',
                    'updated_at' => now(),
                    'cancelled_at' => now(),
                    'cancelled_by_user_id' => (int) $admin->id,
                ]);
            }
        }

        // Release payout hold when dispute is resolved
        if (Schema::hasTable('gymies_payouts') && Schema::hasColumn('gymies_payouts', 'is_held')) {
            DB::table('gymies_payouts')
                ->where('booking_id', $bookingId)
                ->where('is_held', 1)
                ->update([
                    'is_held' => 0,
                    'released_at' => now(),
                ]);
        }

        $this->audit((int) $admin->id, 'admin_dispute_resolved', 'dispute', $id, [
            'resolution_type' => $resolutionType,
            'reason' => $reason,
            'booking_id' => $bookingId,
        ]);
        return response()->json(['ok' => true, 'message' => 'Dispute afgehandeld.']);
    }
}
