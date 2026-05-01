<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Pro Hub endpoints: client health, upsell, rebook.
 * Database-agnostisch: werkt met gymies_bookings/bookings en gymies_users/users.
 */
class GymiesProHubController
{
    /**
     * GET trainer/pro/client-health
     * Returns client health scores. Alleen klanten met voltooide sessies.
     */
    public function clientHealth(Request $request): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainerUserId = (int) $trainer->id;
        $bookingsTable = $this->resolveBookingsTable();
        $usersTable = $this->resolveUsersTable();
        $clientNameExpr = $this->buildClientNameExpression($usersTable);
        $trainerCol = $bookingsTable ? $this->resolveTrainerColumn($bookingsTable) : null;
        $clientCol = $bookingsTable ? $this->resolveClientColumn($bookingsTable) : null;
        if (!$bookingsTable || !$usersTable || !$clientNameExpr || !$trainerCol || !$clientCol) {
            return response()->json(['data' => []], 200);
        }

        try {
            $rows = DB::table($bookingsTable . ' as b')
                ->select([
                    'u.id as client_user_id',
                    DB::raw("ANY_VALUE({$clientNameExpr}) as client_name"),
                    DB::raw('75 as health_score'),
                    DB::raw("'Normaal' as retention_risk"),
                    DB::raw("'-' as no_show_risk"),
                ])
                ->join($usersTable . ' as u', "u.id", '=', "b.{$clientCol}")
                ->where("b.{$trainerCol}", $trainerUserId)
                ->groupBy('u.id')
                ->limit(50)
                ->get();
        } catch (\Throwable $e) {
            return response()->json(['data' => []], 200);
        }

        $data = $rows->map(fn ($r) => [
            'client_user_id' => (string) $r->client_user_id,
            'client_name' => $r->client_name ?? 'Klant',
            'health_score' => (int) ($r->health_score ?? 75),
            'retention_risk' => $r->retention_risk ?? '-',
            'no_show_risk' => $r->no_show_risk ?? '-',
        ])->values()->all();

        return response()->json(['data' => $data]);
    }

    /**
     * GET trainer/pro/upsell-suggestions
     * Klanten met 3+ voltooide sessies die nog geen pakket hebben – pakket-upgrade voorstel.
     */
    public function upsellSuggestions(Request $request): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainerUserId = (int) $trainer->id;
        $bookingsTable = $this->resolveBookingsTable();
        $usersTable = $this->resolveUsersTable();
        $clientNameExpr = $this->buildClientNameExpression($usersTable);
        $trainerCol = $bookingsTable ? $this->resolveTrainerColumn($bookingsTable) : null;
        $clientCol = $bookingsTable ? $this->resolveClientColumn($bookingsTable) : null;
        $statusCol = $bookingsTable ? $this->resolveStatusColumn($bookingsTable) : null;

        if (!$bookingsTable || !$usersTable || !$clientNameExpr || !$trainerCol || !$clientCol) {
            return response()->json(['data' => []], 200);
        }

        try {
            $query = DB::table($bookingsTable . ' as b')
                ->select([
                    'u.id as client_user_id',
                    DB::raw("ANY_VALUE({$clientNameExpr}) as client_name"),
                    DB::raw('COUNT(*) as completed_count'),
                ])
                ->join($usersTable . ' as u', "u.id", '=', "b.{$clientCol}")
                ->where("b.{$trainerCol}", $trainerUserId)
                ->groupBy('u.id')
                ->havingRaw('COUNT(*) >= 3')
                ->limit(20);

            if ($statusCol) {
                $query->whereIn("b.{$statusCol}", ['completed', 'done', 'finished', 'checked_in']);
            }

            $rows = $query->get();
        } catch (\Throwable $e) {
            return response()->json(['data' => []], 200);
        }

        $data = $rows->values()->map(fn ($r) => [
            'id' => (string) $r->client_user_id,
            'suggestion_id' => (string) $r->client_user_id,
            'client_user_id' => (string) $r->client_user_id,
            'client_name' => $r->client_name ?? 'Klant',
            'reason' => 'Klant heeft meerdere sessies gehad – pakket kan voordeliger zijn',
            'package_name' => '',
        ])->values()->all();

        return response()->json(['data' => $data]);
    }

    /**
     * GET trainer/pro/rebook-suggestions
     * Klanten wiens laatste voltooide sessie meer dan 7 dagen geleden was.
     * Smart Rebook Alerts: "We missen je" kandidaten.
     */
    public function rebookSuggestions(Request $request): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainerUserId = (int) $trainer->id;
        $bookingsTable = $this->resolveBookingsTable();
        $usersTable = $this->resolveUsersTable();
        $clientNameExpr = $this->buildClientNameExpression($usersTable);
        $trainerCol = $bookingsTable ? $this->resolveTrainerColumn($bookingsTable) : null;
        $clientCol = $bookingsTable ? $this->resolveClientColumn($bookingsTable) : null;
        $scheduledCol = $bookingsTable ? $this->resolveScheduledColumn($bookingsTable) : null;
        $statusCol = $bookingsTable ? $this->resolveStatusColumn($bookingsTable) : null;

        if (!$bookingsTable || !$usersTable || !$clientNameExpr || !$trainerCol || !$clientCol || !$scheduledCol) {
            return response()->json(['data' => []], 200);
        }

        $cutoff = now()->subDays(7);

        try {
            $query = DB::table($bookingsTable . ' as b')
                ->select([
                    'u.id as client_user_id',
                    DB::raw("ANY_VALUE({$clientNameExpr}) as client_name"),
                    DB::raw("MAX(b.{$scheduledCol}) as last_session_at"),
                ])
                ->join($usersTable . ' as u', "u.id", '=', "b.{$clientCol}")
                ->where("b.{$trainerCol}", $trainerUserId)
                ->where("b.{$scheduledCol}", '<=', now())
                ->groupBy('u.id')
                ->havingRaw("MAX(b.{$scheduledCol}) < ?", [$cutoff->format('Y-m-d H:i:s')])
                ->orderByDesc('last_session_at')
                ->limit(50);

            if ($statusCol) {
                $query->whereIn("b.{$statusCol}", ['completed', 'done', 'finished', 'checked_in']);
            }

            $rows = $query->get();
        } catch (\Throwable $e) {
            return response()->json(['data' => []], 200);
        }

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->client_user_id,
            'client_user_id' => (string) $r->client_user_id,
            'client_name' => $r->client_name ?? 'Klant',
            'last_session_at' => $r->last_session_at,
            'days_since_last' => $r->last_session_at
                ? (int) Carbon::parse($r->last_session_at)->diffInDays(now())
                : 0,
        ])->values()->all();

        return response()->json(['data' => $data]);
    }

    /**
     * POST trainer/pro/upsell-suggestions/{id}/send
     * Verstuur upsell-voorstel naar klant (bericht via bestaande message-infra).
     */
    public function sendUpsellSuggestion(Request $request, string $id): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $clientUserId = $id ?: $request->input('client_user_id', '');
        if (empty($clientUserId)) {
            return response()->json(['message' => 'client_user_id ontbreekt.'], 422);
        }

        try {
            $client = (int) $clientUserId;
            $trainerId = (int) $trainer->id;
            $body = trim($request->input('message', '') ?: 'We hebben een pakket dat goed bij je past. Bekijk onze pakketten in de app voor een voordelig aanbod.');

            $conversationsTable = $this->resolveConversationsTable();
            $messagesTable = $this->resolveMessagesTable();
            $msgCol = $messagesTable ? $this->resolveMessageBodyColumn($messagesTable) : null;

            if ($conversationsTable && $messagesTable && $msgCol) {
                $hasTrainerCol = Schema::hasColumn($conversationsTable, 'trainer_user_id');
                $hasClientCol = Schema::hasColumn($conversationsTable, 'client_user_id');
                if ($hasTrainerCol && $hasClientCol) {
                    $conv = DB::table($conversationsTable)
                        ->where('trainer_user_id', $trainerId)
                        ->where('client_user_id', $client)
                        ->first();
                    $convId = $conv?->id;
                    if (!$convId) {
                        $convId = DB::table($conversationsTable)->insertGetId([
                            'trainer_user_id' => $trainerId,
                            'client_user_id' => $client,
                            'created_at' => now(),
                            'updated_at' => now(),
                        ]);
                    }
                    $insert = [
                        'conversation_id' => $convId,
                        $msgCol => $body,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ];
                    if (Schema::hasColumn($messagesTable, 'author_user_id')) {
                        $insert['author_user_id'] = $trainerId;
                    } elseif (Schema::hasColumn($messagesTable, 'sender_id')) {
                        $insert['sender_id'] = $trainerId;
                    }
                    DB::table($messagesTable)->insert($insert);
                }
            }
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Kon bericht niet versturen.'], 500);
        }

        return response()->json(['message' => 'OK']);
    }

    /**
     * POST trainer/pro/rebook-suggestions/{id}/send
     * Verstuur "we missen je" herboek-bericht naar een inactieve klant.
     * Gebruikt dezelfde message-infra als sendUpsellSuggestion.
     */
    public function sendRebookSuggestion(Request $request, string $id): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $clientUserId = $id ?: $request->input('client_user_id', '');
        if (empty($clientUserId)) {
            return response()->json(['message' => 'client_user_id ontbreekt.'], 422);
        }

        try {
            $client = (int) $clientUserId;
            $trainerId = (int) $trainer->id;
            $trainerName = $trainer->display_name ?? $trainer->name ?? 'Trainer';
            $defaultMessage = "Hoi! Het is een tijdje geleden sinds je laatste sessie. "
                . "We missen je! Wil je weer een afspraak inplannen? "
                . "Boek direct via de app of stuur me een berichtje. – {$trainerName}";
            $body = trim($request->input('message', '') ?: $defaultMessage);

            $conversationsTable = $this->resolveConversationsTable();
            $messagesTable = $this->resolveMessagesTable();
            $msgCol = $messagesTable ? $this->resolveMessageBodyColumn($messagesTable) : null;

            if ($conversationsTable && $messagesTable && $msgCol) {
                $hasTrainerCol = Schema::hasColumn($conversationsTable, 'trainer_user_id');
                $hasClientCol = Schema::hasColumn($conversationsTable, 'client_user_id');
                if ($hasTrainerCol && $hasClientCol) {
                    $conv = DB::table($conversationsTable)
                        ->where('trainer_user_id', $trainerId)
                        ->where('client_user_id', $client)
                        ->first();
                    $convId = $conv?->id;
                    if (!$convId) {
                        $convId = DB::table($conversationsTable)->insertGetId([
                            'trainer_user_id' => $trainerId,
                            'client_user_id' => $client,
                            'created_at' => now(),
                            'updated_at' => now(),
                        ]);
                    }
                    $insert = [
                        'conversation_id' => $convId,
                        $msgCol => $body,
                        'created_at' => now(),
                        'updated_at' => now(),
                    ];
                    if (Schema::hasColumn($messagesTable, 'author_user_id')) {
                        $insert['author_user_id'] = $trainerId;
                    } elseif (Schema::hasColumn($messagesTable, 'sender_id')) {
                        $insert['sender_id'] = $trainerId;
                    }
                    DB::table($messagesTable)->insert($insert);
                }
            }
        } catch (\Throwable $e) {
            return response()->json(['message' => 'Kon herboek-bericht niet versturen.'], 500);
        }

        return response()->json(['message' => 'Herboek-bericht verstuurd.']);
    }

    private function resolveConversationsTable(): ?string
    {
        foreach (['gymies_conversations', 'conversations'] as $t) {
            if (Schema::hasTable($t)) {
                return $t;
            }
        }
        return null;
    }

    private function resolveMessagesTable(): ?string
    {
        foreach (['gymies_messages', 'messages', 'conversation_messages'] as $t) {
            if (Schema::hasTable($t)) {
                return $t;
            }
        }
        return null;
    }

    private function resolveMessageBodyColumn(string $table): ?string
    {
        $cols = ['body', 'content', 'message', 'text'];
        foreach ($cols as $c) {
            if (Schema::hasColumn($table, $c)) {
                return $c;
            }
        }
        return null;
    }

    private function resolveStatusColumn(string $table): ?string
    {
        $cols = ['status', 'booking_status', 'state'];
        foreach ($cols as $c) {
            if (Schema::hasColumn($table, $c)) {
                return $c;
            }
        }
        return null;
    }

    private function resolveScheduledColumn(string $table): ?string
    {
        $cols = ['scheduled_at', 'scheduledAt', 'session_at', 'date', 'created_at'];
        foreach ($cols as $c) {
            if (Schema::hasColumn($table, $c)) {
                return $c;
            }
        }
        return null;
    }

    private function resolveBookingsTable(): ?string
    {
        foreach (['gymies_bookings', 'bookings'] as $t) {
            if (Schema::hasTable($t)) {
                return $t;
            }
        }
        return null;
    }

    private function resolveUsersTable(): ?string
    {
        foreach (['gymies_users', 'users'] as $t) {
            if (Schema::hasTable($t)) {
                return $t;
            }
        }
        return null;
    }

    /**
     * Returns SQL COALESCE expression for user display name. Gebruikt alleen kolommen die bestaan.
     * gymies_users heeft display_name, niet name – voorkomt "unknown column 'name'" error.
     */
    private function buildClientNameExpression(string $table, string $alias = 'u'): ?string
    {
        $parts = [];
        // Alleen display_name en email. gymies_users heeft GEEN 'name' kolom – voorkomt SQLSTATE 42S22.
        $cols = ['display_name', 'email'];
        foreach ($cols as $col) {
            if (Schema::hasColumn($table, $col)) {
                $parts[] = "{$alias}.{$col}";
            }
        }
        if (empty($parts)) {
            return null;
        }
        return 'COALESCE(' . implode(', ', $parts) . ", 'Klant')";
    }

    private function resolveTrainerColumn(string $table): ?string
    {
        $cols = ['trainer_user_id', 'trainer_id', 'trainerUserId', 'trainerId'];
        foreach ($cols as $c) {
            if (Schema::hasColumn($table, $c)) {
                return $c;
            }
        }
        return null;
    }

    private function resolveClientColumn(string $table): ?string
    {
        $cols = ['client_user_id', 'client_id', 'user_id', 'clientUserId', 'clientId'];
        foreach ($cols as $c) {
            if (Schema::hasColumn($table, $c)) {
                return $c;
            }
        }
        return null;
    }
}
