<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Betalingen per klant voor trainers.
 * GET trainer/clients/{clientUserId}/payments
 */
class GymiesTrainerClientPaymentsController
{
    public function index(Request $request, string $clientUserId): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainerUserId = (int) $trainer->id;

        $bookingsTable = $this->resolveBookingsTable();
        if (!$bookingsTable) {
            return response()->json(['data' => []], 200);
        }

        $trainerCol = $this->resolveTrainerColumn($bookingsTable);
        $clientCol = $this->resolveClientColumn($bookingsTable);
        $paidAtCol = $this->resolvePaidAtColumn($bookingsTable);
        $amountCol = $this->resolveAmountColumn($bookingsTable);
        $scheduledCol = $this->resolveScheduledColumn($bookingsTable);

        if (!$trainerCol || !$clientCol) {
            return response()->json(['data' => []], 200);
        }

        $query = DB::table($bookingsTable)
            ->where($trainerCol, $trainerUserId)
            ->where($clientCol, $clientUserId);

        if ($paidAtCol && Schema::hasColumn($bookingsTable, $paidAtCol)) {
            $query->whereNotNull($paidAtCol);
        }

        $rows = $query
            ->orderByDesc($scheduledCol ?? $paidAtCol ?? 'id')
            ->limit(100)
            ->get();

        $payments = [];
        foreach ($rows as $row) {
            $rowArr = (array) $row;
            $id = $rowArr['id'] ?? $rowArr['booking_id'] ?? null;
            $amountCents = (int) ($rowArr[$amountCol] ?? $rowArr['amount_cents'] ?? $rowArr['amountCents'] ?? 0);
            $paidAt = $rowArr[$paidAtCol] ?? $rowArr['paid_at'] ?? $rowArr['paidAt'] ?? null;
            $scheduledAt = $rowArr[$scheduledCol] ?? $rowArr['scheduled_at'] ?? $rowArr['scheduledAt'] ?? $paidAt;

            $payments[] = [
                'booking_id' => (string) $id,
                'amount_cents' => $amountCents,
                'currency' => 'EUR',
                'status' => 'paid',
                'paid_at' => $paidAt ? date('c', strtotime($paidAt)) : null,
                'session_date' => $scheduledAt ? date('Y-m-d', strtotime($scheduledAt)) : null,
                'reference_id' => $rowArr['mollie_payment_id'] ?? $rowArr['reference_id'] ?? null,
            ];
        }

        return response()->json(['data' => $payments]);
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

    private function resolvePaidAtColumn(string $table): ?string
    {
        $cols = ['paid_at', 'paidAt', 'payment_date'];
        foreach ($cols as $c) {
            if (Schema::hasColumn($table, $c)) {
                return $c;
            }
        }
        return null;
    }

    private function resolveAmountColumn(string $table): ?string
    {
        $cols = ['amount_cents', 'amountCents', 'amount'];
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
}
