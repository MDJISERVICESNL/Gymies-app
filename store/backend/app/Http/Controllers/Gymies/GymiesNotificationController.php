<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Notificaties: index, unread-count, mark-read, preferences.
 *
 * Leest uit gymies_notification_queue (waar alle business-logica inserts doen)
 * in plaats van Laravel's standaard notifications-tabel.
 * Ondersteunt read_at tracking via een aparte kolom (wordt toegevoegd als die ontbreekt).
 */
class GymiesNotificationController
{
    private function table(): string
    {
        return 'gymies_notification_queue';
    }

    /**
     * Zorgt dat read_at kolom bestaat op de queue-tabel.
     */
    private function ensureReadAtColumn(): void
    {
        if (Schema::hasTable($this->table()) && !Schema::hasColumn($this->table(), 'read_at')) {
            try {
                DB::unprepared("ALTER TABLE {$this->table()} ADD COLUMN read_at TIMESTAMP NULL DEFAULT NULL AFTER failed_at");
            } catch (\Throwable $e) {
                // Column might already exist due to race condition - ignore
            }
        }
    }

    /**
     * GET notifications – lijst meldingen voor ingelogde gebruiker.
     */
    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        if (!Schema::hasTable($this->table())) {
            return response()->json(['data' => []]);
        }

        $this->ensureReadAtColumn();
        $hasReadAt = Schema::hasColumn($this->table(), 'read_at');

        $rows = DB::table($this->table())
            ->where('user_id', (int) $user->id)
            ->where('channel', 'in_app')
            ->orderBy('created_at', 'desc')
            ->limit(100)
            ->get();

        $data = $rows->map(function ($row) use ($hasReadAt) {
            $payloadRaw = $row->payload_json ?? null;
            $payload = [];
            if (is_string($payloadRaw) && $payloadRaw !== '') {
                $decoded = json_decode($payloadRaw, true);
                if (is_array($decoded)) {
                    $payload = $decoded;
                }
            }

            $readAt = $hasReadAt ? ($row->read_at ?? null) : null;

            return array_merge([
                'id' => (string) $row->id,
                'notification_id' => (string) $row->id,
                'notificationId' => (string) $row->id,
                'type' => $row->event_type ?? 'notification',
                'event_type' => $row->event_type ?? '',
                'channel' => $row->channel ?? 'in_app',
                'read_at' => $readAt,
                'readAt' => $readAt,
                'unread' => empty($readAt),
                'is_unread' => empty($readAt),
                'created_at' => $row->created_at,
            ], $payload);
        })->values()->all();

        return response()->json(['data' => $data]);
    }

    /**
     * GET notifications/unread-count – aantal ongelezen meldingen.
     */
    public function unreadCount(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['unread_count' => 0]);
        }

        if (!Schema::hasTable($this->table())) {
            return response()->json(['unread_count' => 0]);
        }

        $this->ensureReadAtColumn();
        $hasReadAt = Schema::hasColumn($this->table(), 'read_at');

        $query = DB::table($this->table())
            ->where('user_id', (int) $user->id)
            ->where('channel', 'in_app');

        if ($hasReadAt) {
            $query->whereNull('read_at');
        }

        $count = $query->count();

        return response()->json([
            'unread_count' => (int) $count,
            'count' => (int) $count,
        ]);
    }

    /**
     * POST notifications/mark-read – markeer als gelezen.
     * Body: leeg = alles, of { notification_id: "123" } / { id: "123" } voor één melding.
     */
    public function markRead(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        if (!Schema::hasTable($this->table())) {
            return response()->json(['message' => 'OK']);
        }

        $this->ensureReadAtColumn();
        if (!Schema::hasColumn($this->table(), 'read_at')) {
            return response()->json(['message' => 'OK']); // Kolom kon niet aangemaakt worden
        }

        $notificationId = $request->input('notification_id') ?? $request->input('id');
        $notificationId = $notificationId ? trim((string) $notificationId) : null;

        $query = DB::table($this->table())
            ->where('user_id', (int) $user->id)
            ->where('channel', 'in_app')
            ->whereNull('read_at');

        if ($notificationId !== null && $notificationId !== '') {
            $query->where('id', $notificationId);
        }

        $query->update(['read_at' => now()]);

        return response()->json(['message' => 'OK']);
    }

    /**
     * GET notifications/preferences – meldingenvoorkeuren.
     */
    public function preferences(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        return response()->json([
            'data' => [],
            'preferences' => [],
        ]);
    }

    /**
     * PUT/POST notifications/preferences – voorkeuren bijwerken.
     */
    public function updatePreferences(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $prefs = $request->all();
        return response()->json([
            'data' => $prefs,
            'preferences' => $prefs,
        ]);
    }
}
