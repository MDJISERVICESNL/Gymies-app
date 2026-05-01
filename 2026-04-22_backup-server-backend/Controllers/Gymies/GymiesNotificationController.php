<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Gymies API: notificaties van de ingelogde gebruiker.
 * Tabel: gymies_notification_queue.
 */
final class GymiesNotificationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $limit = min((int) ($request->query('limit', 30)), 100);
        $unreadOnly = $request->query('unread_only') === '1' || $request->query('unread_only') === 'true';
        $query = DB::table('gymies_notification_queue')
            ->where('user_id', $user->id)
            ->orderByDesc('created_at')
            ->limit($limit);
        if ($unreadOnly && DB::getSchemaBuilder()->hasColumn('gymies_notification_queue', 'read_at')) {
            $query->whereNull('read_at');
        }
        $rows = $query->get();

        $data = $rows->map(function ($r): array {
            $payload = null;
            if (!empty($r->payload_json)) {
                $decoded = json_decode((string) $r->payload_json, true);
                if (is_array($decoded)) {
                    $payload = $decoded;
                }
            }
            $item = [
                'id' => (string) $r->id,
                'channel' => $r->channel,
                'event_type' => $r->event_type,
                'payload' => $payload,
                'scheduled_for' => $r->scheduled_for,
                'sent_at' => $r->sent_at,
                'failed_at' => $r->failed_at,
                'created_at' => $r->created_at,
            ];
            if (property_exists($r, 'read_at')) {
                $item['read_at'] = $r->read_at;
            }
            return $item;
        })->all();

        return response()->json(['data' => $data]);
    }

    public function unreadCount(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!DB::getSchemaBuilder()->hasColumn('gymies_notification_queue', 'read_at')) {
            $count = DB::table('gymies_notification_queue')->where('user_id', $user->id)->count();
            return response()->json(['data' => ['count' => $count]]);
        }
        $count = DB::table('gymies_notification_queue')
            ->where('user_id', $user->id)
            ->whereNull('read_at')
            ->count();
        return response()->json(['data' => ['count' => $count]]);
    }

    public function markRead(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }
        if (!DB::getSchemaBuilder()->hasColumn('gymies_notification_queue', 'read_at')) {
            return response()->json(['data' => ['message' => 'ok']]);
        }
        DB::table('gymies_notification_queue')
            ->where('user_id', $user->id)
            ->whereNull('read_at')
            ->update(['read_at' => now()]);
        return response()->json(['data' => ['message' => 'ok']]);
    }

    public function preferences(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        $rows = DB::table('gymies_notification_preferences')
            ->where('user_id', $user->id)
            ->get(['channel', 'type', 'enabled', 'priority_mode']);
        $prefs = [];
        foreach ($rows as $row) {
            $prefs[] = [
                'channel' => (string) $row->channel,
                'type' => (string) $row->type,
                'enabled' => (int) $row->enabled === 1,
                'priority_mode' => (string) ($row->priority_mode ?? 'all'),
            ];
        }

        $quietHours = ['enabled' => false, 'start' => '22:00', 'end' => '07:00'];
        if (DB::getSchemaBuilder()->hasTable('gymies_notification_user_settings')) {
            $settings = DB::table('gymies_notification_user_settings')
                ->where('user_id', $user->id)
                ->first();
            if ($settings) {
                $quietHours = [
                    'enabled' => (int) ($settings->quiet_hours_enabled ?? 0) === 1,
                    'start' => (string) ($settings->quiet_hours_start ?? '22:00'),
                    'end' => (string) ($settings->quiet_hours_end ?? '07:00'),
                ];
            }
        }

        return response()->json(['data' => ['preferences' => $prefs, 'quiet_hours' => $quietHours]]);
    }

    public function updatePreferences(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        // S-088: Rate limiting — max 20 updates per 5 minutes per user
        $key = 'notif_pref:' . (int) $user->id;
        $limiter = \Illuminate\Support\Facades\RateLimiter::attempt(
            $key,
            20, // max 20 attempts
            fn () => true,
            300 // per 300 seconds (5 minutes)
        );
        if (!$limiter) {
            return response()->json(['message' => 'Rate limit exceeded: max 20 preference updates per 5 minutes'], 429);
        }

        $request->validate([
            'preferences' => 'nullable|array',
            'preferences.*.channel' => 'required_with:preferences|in:email,push,sms',
            'preferences.*.type' => 'required_with:preferences|string|max:64',
            'preferences.*.enabled' => 'required_with:preferences|boolean',
            'preferences.*.priority_mode' => 'nullable|in:all,important_only',
            'quiet_hours.enabled' => 'nullable|boolean',
            'quiet_hours.start' => 'nullable|string|max:5',
            'quiet_hours.end' => 'nullable|string|max:5',
        ]);

        $prefs = $request->input('preferences', []);
        foreach ($prefs as $item) {
            DB::table('gymies_notification_preferences')->updateOrInsert(
                [
                    'user_id' => $user->id,
                    'channel' => (string) ($item['channel'] ?? 'in_app'),
                    'type' => (string) ($item['type'] ?? 'general'),
                ],
                [
                    'enabled' => !empty($item['enabled']) ? 1 : 0,
                    'priority_mode' => (string) ($item['priority_mode'] ?? 'all'),
                    'updated_at' => now(),
                ]
            );
        }

        $quiet = $request->input('quiet_hours');
        if (is_array($quiet) && DB::getSchemaBuilder()->hasTable('gymies_notification_user_settings')) {
            // S-053: Validate HH:MM time format for quiet_hours
            $quietStart = (string) ($quiet['start'] ?? '22:00');
            $quietEnd = (string) ($quiet['end'] ?? '07:00');

            $timePattern = '/^([01]\d|2[0-3]):[0-5]\d$/';
            if ($quietStart !== '' && !preg_match($timePattern, $quietStart)) {
                return response()->json(['message' => 'quiet_hours.start must be HH:MM format'], 422);
            }
            if ($quietEnd !== '' && !preg_match($timePattern, $quietEnd)) {
                return response()->json(['message' => 'quiet_hours.end must be HH:MM format'], 422);
            }

            DB::table('gymies_notification_user_settings')->updateOrInsert(
                ['user_id' => $user->id],
                [
                    'quiet_hours_enabled' => !empty($quiet['enabled']) ? 1 : 0,
                    'quiet_hours_start' => $quietStart,
                    'quiet_hours_end' => $quietEnd,
                    'updated_at' => now(),
                ]
            );
        }

        return $this->preferences($request);
    }
}

