<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Client-side geschillen: indienen, bekijken, berichten sturen.
 * Admin-side (resolve) zit in GymiesAdminController.
 */
class GymiesDisputeController
{
    private const DISPUTES = 'gymies_disputes';
    private const MESSAGES = 'gymies_dispute_messages';

    /**
     * POST bookings/{id}/dispute — geschil indienen over een boeking.
     */
    public function raise(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $request->validate([
            'reason'  => 'required|string|max:255',
            'details' => 'nullable|string|max:2000',
        ]);

        $this->ensureTable();

        // Controleer boeking eigendom
        $booking = DB::table('gymies_bookings')
            ->where('id', $id)
            ->first();
        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }
        // Alleen client of trainer van deze boeking mag een geschil indienen
        $userId = (int) $user->id;
        if ($userId !== (int) $booking->client_user_id && $userId !== (int) $booking->trainer_user_id) {
            return response()->json(['message' => 'Je bent niet betrokken bij deze boeking.'], 403);
        }

        // Check of er al een open geschil is
        if (DB::table(self::DISPUTES)->where('booking_id', $id)->whereIn('status', ['open', 'in_progress'])->exists()) {
            return response()->json(['message' => 'Er loopt al een geschil voor deze boeking.'], 422);
        }

        $disputeId = DB::table(self::DISPUTES)->insertGetId([
            'booking_id'       => $id,
            'raised_by_user_id' => $userId,
            'reason'           => trim((string) $request->input('reason')),
            'details'          => $request->input('details') ? trim((string) $request->input('details')) : null,
            'status'           => 'open',
            'created_at'       => now(),
            'updated_at'       => now(),
        ]);

        return response()->json([
            'message' => 'Geschil ingediend. We nemen het zo snel mogelijk in behandeling.',
            'data'    => ['id' => $disputeId, 'status' => 'open'],
        ], 201);
    }

    /**
     * GET my-disputes — eigen geschillen ophalen.
     */
    public function myDisputes(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $this->ensureTable();
        if (!Schema::hasTable(self::DISPUTES)) {
            return response()->json(['data' => []]);
        }

        $userId = (int) $user->id;

        // Geschillen waar deze user bij betrokken is (als indiener of als andere partij van de boeking)
        $disputes = DB::table(self::DISPUTES . ' as d')
            ->join('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
            ->where(function ($q) use ($userId) {
                $q->where('d.raised_by_user_id', $userId)
                  ->orWhere('b.client_user_id', $userId)
                  ->orWhere('b.trainer_user_id', $userId);
            })
            ->orderByDesc('d.created_at')
            ->select([
                'd.id', 'd.booking_id', 'd.reason', 'd.status',
                'd.resolution_type', 'd.created_at', 'd.updated_at',
                'b.trainer_user_id', 'b.client_user_id',
            ])
            ->limit(50)
            ->get()
            ->map(fn ($row) => [
                'id'              => (int) $row->id,
                'booking_id'      => (string) $row->booking_id,
                'reason'          => (string) $row->reason,
                'status'          => (string) $row->status,
                'resolution_type' => $row->resolution_type ?? null,
                'other_party'     => $this->resolveUserName(
                    $userId === (int) $row->client_user_id
                        ? (int) $row->trainer_user_id
                        : (int) $row->client_user_id
                ),
                'created_at'      => $row->created_at,
            ])
            ->values()
            ->all();

        return response()->json(['data' => $disputes]);
    }

    /**
     * GET my-disputes/{disputeId} — geschil detail met berichten.
     */
    public function detail(Request $request, string $disputeId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $dispute = DB::table(self::DISPUTES)->find((int) $disputeId);
        if (!$dispute) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        // Check betrokkenheid
        $booking = DB::table('gymies_bookings')->where('id', $dispute->booking_id)->first();
        $userId = (int) $user->id;
        if (!$booking || ($userId !== (int) $booking->client_user_id && $userId !== (int) $booking->trainer_user_id)) {
            return response()->json(['message' => 'Geen toegang tot dit geschil.'], 403);
        }

        // Berichten ophalen (alleen niet-interne)
        $messages = [];
        if (Schema::hasTable(self::MESSAGES)) {
            $messages = DB::table(self::MESSAGES)
                ->where('dispute_id', (int) $disputeId)
                ->where('is_internal', false)
                ->orderBy('created_at')
                ->get()
                ->map(fn ($m) => [
                    'id'         => (int) $m->id,
                    'author'     => $this->resolveUserName((int) ($m->author_user_id ?? 0)),
                    'is_mine'    => (int) ($m->author_user_id ?? 0) === $userId,
                    'message'    => (string) $m->message,
                    'created_at' => $m->created_at,
                ])
                ->values()
                ->all();
        }

        return response()->json([
            'data' => [
                'id'              => (int) $dispute->id,
                'booking_id'      => (string) $dispute->booking_id,
                'reason'          => (string) $dispute->reason,
                'details'         => $dispute->details ?? null,
                'status'          => (string) $dispute->status,
                'resolution_type' => $dispute->resolution_type ?? null,
                'created_at'      => $dispute->created_at,
                'messages'        => $messages,
            ],
        ]);
    }

    /**
     * POST my-disputes/{disputeId}/message — bericht toevoegen.
     */
    public function addMessage(Request $request, string $disputeId): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $request->validate([
            'message' => 'required|string|max:2000',
        ]);

        $dispute = DB::table(self::DISPUTES)->find((int) $disputeId);
        if (!$dispute) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }
        if ($dispute->status === 'resolved') {
            return response()->json(['message' => 'Dit geschil is al opgelost.'], 422);
        }

        // Check betrokkenheid
        $booking = DB::table('gymies_bookings')->where('id', $dispute->booking_id)->first();
        $userId = (int) $user->id;
        if (!$booking || ($userId !== (int) $booking->client_user_id && $userId !== (int) $booking->trainer_user_id)) {
            return response()->json(['message' => 'Geen toegang tot dit geschil.'], 403);
        }

        $this->ensureMessagesTable();

        $msgId = DB::table(self::MESSAGES)->insertGetId([
            'dispute_id'     => (int) $disputeId,
            'author_user_id' => $userId,
            'message'        => trim((string) $request->input('message')),
            'is_internal'    => false,
            'created_at'     => now(),
        ]);

        // Status naar in_progress als het nog open was
        if ($dispute->status === 'open') {
            DB::table(self::DISPUTES)->where('id', (int) $disputeId)->update([
                'status'     => 'in_progress',
                'updated_at' => now(),
            ]);
        }

        return response()->json([
            'message' => 'Bericht verstuurd.',
            'data'    => ['id' => $msgId],
        ]);
    }

    // ── Helpers ────────────────────────────────────────────

    private function ensureTable(): void
    {
        if (Schema::hasTable(self::DISPUTES)) return;
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS " . self::DISPUTES . " (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id VARCHAR(64) NOT NULL,
  raised_by_user_id BIGINT UNSIGNED NOT NULL,
  reason VARCHAR(255) NOT NULL,
  details TEXT DEFAULT NULL,
  status ENUM('open','in_progress','resolved') NOT NULL DEFAULT 'open',
  resolution_type ENUM('client','trainer','split') DEFAULT NULL,
  resolved_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_disputes_booking (booking_id),
  KEY gymies_disputes_user (raised_by_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable) {}
    }

    private function ensureMessagesTable(): void
    {
        if (Schema::hasTable(self::MESSAGES)) return;
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS " . self::MESSAGES . " (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  dispute_id BIGINT UNSIGNED NOT NULL,
  author_user_id BIGINT UNSIGNED NOT NULL,
  message TEXT NOT NULL,
  is_internal TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_dispute_messages_dispute (dispute_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable) {}
    }

    private function resolveUserName(int $userId): string
    {
        if ($userId <= 0) return 'Onbekend';
        $table = Schema::hasTable('gymies_users') ? 'gymies_users' : 'users';
        $user = DB::table($table)->where('id', $userId)->first();
        if (!$user) return 'Onbekend';
        $name = trim(($user->display_name ?? $user->first_name ?? $user->name ?? '') . '');
        return $name !== '' ? $name : ($user->email ?? 'Onbekend');
    }
}
