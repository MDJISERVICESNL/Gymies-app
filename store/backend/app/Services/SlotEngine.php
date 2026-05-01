<?php

declare(strict_types=1);

namespace App\Services;

use Carbon\Carbon;
use Carbon\CarbonTimeZone;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * V2 Booking Architecture — Slot Engine.
 *
 * Verantwoordelijk voor:
 * 1. Availability blokken (07:00-12:00) splitsen in concrete bookbare slots
 * 2. Buffer/pauze tijd tussen slots toepassen
 * 3. Tijdzone-conversie (opslag UTC, weergave lokaal)
 * 4. Filter pipeline: lead time, max advance, al geboekt, exceptions, rate limits
 *
 * BELANGRIJK: deze service wordt aangeroepen vanuit de API controllers.
 * De publicAvailability endpoint moet deze service gebruiken i.p.v. ruwe blokken.
 */
class SlotEngine
{
    /** Platform defaults als trainer geen profiel-instelling heeft. */
    private const DEFAULT_SESSION_DURATION = 60;   // minuten
    private const DEFAULT_BUFFER = 15;             // minuten
    private const DEFAULT_LEAD_TIME_HOURS = 4;     // uur
    private const DEFAULT_MAX_ADVANCE_DAYS = 28;   // dagen
    private const DEFAULT_TIMEZONE = 'Europe/Amsterdam';

    /**
     * Haal alle bookbare slots op voor een trainer in een datumbereik.
     *
     * @param int    $trainerId    gymies_users.id van de trainer
     * @param string $fromDate     'Y-m-d' startdatum (inclusief)
     * @param string $toDate       'Y-m-d' einddatum (inclusief)
     * @param bool   $filterBooked Verwijder al geboekte slots
     * @return array<int, array{date: string, day_of_week: int, start_time: string, end_time: string, available: bool}>
     */
    public function getBookableSlots(
        int    $trainerId,
        string $fromDate,
        string $toDate,
        bool   $filterBooked = true,
    ): array {
        $settings = $this->loadTrainerSettings($trainerId);
        $sessionDuration = $settings['session_duration_min'];
        $buffer = $settings['buffer_minutes'];
        $timezone = $settings['timezone'];
        $maxPerDay = $settings['max_sessions_per_day'];
        $maxPerWeek = $settings['max_sessions_per_week'];

        // 1. Haal ruwe availability blokken op
        $blocks = $this->loadAvailabilityBlocks($trainerId);
        if (empty($blocks)) {
            return [];
        }

        // 2. Haal exceptions op (geblokkeerde datums)
        $exceptions = $this->loadExceptions($trainerId, $fromDate, $toDate);
        $blockedDates = [];
        foreach ($exceptions as $ex) {
            if (!($ex['is_available'] ?? false)) {
                $blockedDates[$ex['date']] = $ex['reason'] ?? '';
            }
        }

        // 3. Haal bestaande bookings op (voor filter)
        $existingBookings = $filterBooked
            ? $this->loadExistingBookings($trainerId, $fromDate, $toDate)
            : [];

        // 4. Genereer concrete slots per dag
        $slots = [];
        $from = Carbon::parse($fromDate);
        $to = Carbon::parse($toDate);

        // Lead time en max advance berekenen
        $now = Carbon::now($timezone);
        $leadTimeMinutes = ($settings['lead_time_minutes'] ?? self::DEFAULT_LEAD_TIME_HOURS * 60);
        $earliestBookable = $now->copy()->addMinutes($leadTimeMinutes);
        $maxAdvanceDays = $settings['max_advance_days'] ?? self::DEFAULT_MAX_ADVANCE_DAYS;
        $latestBookable = $now->copy()->addDays($maxAdvanceDays)->endOfDay();

        // Bookings per dag/week tellen voor rate limiting
        $bookingsPerDay = [];
        $bookingsPerWeek = [];
        foreach ($existingBookings as $bk) {
            $bkDate = $bk['date'];
            $bookingsPerDay[$bkDate] = ($bookingsPerDay[$bkDate] ?? 0) + 1;
            $weekKey = Carbon::parse($bkDate)->format('o-W');
            $bookingsPerWeek[$weekKey] = ($bookingsPerWeek[$weekKey] ?? 0) + 1;
        }

        for ($date = $from->copy(); $date->lte($to); $date->addDay()) {
            $dateStr = $date->format('Y-m-d');
            $dayOfWeek = (int) $date->format('N');  // ISO: 1=ma, 7=zo

            // Skip geblokkeerde datums
            if (isset($blockedDates[$dateStr])) {
                continue;
            }

            // Vind matching availability blokken voor deze dag
            $dayBlocks = $this->getBlocksForDate($blocks, $dateStr, $dayOfWeek);

            foreach ($dayBlocks as $block) {
                // Split blok in slots van session_duration + buffer
                $blockSlots = $this->splitBlock(
                    $block['start_time'],
                    $block['end_time'],
                    $sessionDuration,
                    $buffer,
                );

                foreach ($blockSlots as $slot) {
                    $slotStart = Carbon::parse("{$dateStr} {$slot['start']}", $timezone);
                    $slotEnd = Carbon::parse("{$dateStr} {$slot['end']}", $timezone);

                    // Filter: lead time
                    if ($slotStart->lt($earliestBookable)) {
                        continue;
                    }

                    // Filter: max advance
                    if ($slotStart->gt($latestBookable)) {
                        continue;
                    }

                    // Filter: al geboekt
                    $isBooked = false;
                    if ($filterBooked) {
                        foreach ($existingBookings as $bk) {
                            if ($bk['date'] === $dateStr && $this->timesOverlap(
                                $slot['start'], $slot['end'],
                                $bk['start_time'], $bk['end_time'],
                            )) {
                                $isBooked = true;
                                break;
                            }
                        }
                    }

                    // Filter: max sessies per dag
                    if ($maxPerDay !== null) {
                        $dayCount = ($bookingsPerDay[$dateStr] ?? 0);
                        if ($dayCount >= $maxPerDay) {
                            continue;
                        }
                    }

                    // Filter: max sessies per week
                    if ($maxPerWeek !== null) {
                        $weekKey = $date->format('o-W');
                        $weekCount = ($bookingsPerWeek[$weekKey] ?? 0);
                        if ($weekCount >= $maxPerWeek) {
                            continue;
                        }
                    }

                    $slots[] = [
                        'date' => $dateStr,
                        'day_of_week' => $dayOfWeek,
                        'start_time' => $slot['start'],
                        'end_time' => $slot['end'],
                        'duration_minutes' => $sessionDuration,
                        'available' => !$isBooked,
                    ];
                }
            }
        }

        return $slots;
    }

    /**
     * Split een tijdblok in slots van $duration minuten met $buffer ertussen.
     *
     * Voorbeeld: 07:00-12:00 met duration=60, buffer=15
     * → 07:00-08:00, 08:15-09:15, 09:30-10:30, 10:45-11:45
     *
     * @return array<int, array{start: string, end: string}>
     */
    public function splitBlock(string $blockStart, string $blockEnd, int $duration, int $buffer): array
    {
        $slots = [];
        $start = $this->timeToMinutes($blockStart);
        $end = $this->timeToMinutes($blockEnd);

        $cursor = $start;
        while ($cursor + $duration <= $end) {
            $slotEnd = $cursor + $duration;
            $slots[] = [
                'start' => $this->minutesToTime($cursor),
                'end' => $this->minutesToTime($slotEnd),
            ];
            $cursor = $slotEnd + $buffer;
        }

        return $slots;
    }

    /**
     * Laad trainer-specifieke instellingen met platform defaults als fallback.
     */
    public function loadTrainerSettings(int $trainerId): array
    {
        $defaults = [
            'session_duration_min' => self::DEFAULT_SESSION_DURATION,
            'buffer_minutes' => self::DEFAULT_BUFFER,
            'timezone' => self::DEFAULT_TIMEZONE,
            'max_sessions_per_day' => null,
            'max_sessions_per_week' => null,
            'min_break_minutes' => self::DEFAULT_BUFFER,
            'lead_time_minutes' => self::DEFAULT_LEAD_TIME_HOURS * 60,
            'max_advance_days' => self::DEFAULT_MAX_ADVANCE_DAYS,
        ];

        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return $defaults;
        }

        $profile = DB::table('gymies_trainer_profiles')
            ->where('user_id', $trainerId)
            ->first();

        if (!$profile) {
            return $defaults;
        }

        $row = (array) $profile;

        return [
            'session_duration_min' => (int) ($row['session_duration_min'] ?? $defaults['session_duration_min']),
            'buffer_minutes' => (int) ($row['buffer_minutes'] ?? $row['min_break_minutes'] ?? $defaults['buffer_minutes']),
            'timezone' => $row['timezone'] ?? $defaults['timezone'],
            'max_sessions_per_day' => isset($row['max_sessions_per_day']) ? (int) $row['max_sessions_per_day'] : null,
            'max_sessions_per_week' => isset($row['max_sessions_per_week']) ? (int) $row['max_sessions_per_week'] : null,
            'min_break_minutes' => (int) ($row['min_break_minutes'] ?? $defaults['min_break_minutes']),
            'lead_time_minutes' => (int) ($row['lead_time_minutes'] ?? $defaults['lead_time_minutes']),
            'max_advance_days' => (int) ($row['booking_advance_days'] ?? $row['booking_max_days_ahead'] ?? $defaults['max_advance_days']),
        ];
    }

    /**
     * Laad ruwe availability blokken uit de database.
     *
     * @return array<int, array{start_time: string, end_time: string, day_of_week: int, slot_date: ?string}>
     */
    private function loadAvailabilityBlocks(int $trainerId): array
    {
        if (!Schema::hasTable('gymies_availability_slots')) {
            return [];
        }

        $columns = Schema::getColumnListing('gymies_availability_slots');
        $userIdCol = in_array('trainer_user_id', $columns) ? 'trainer_user_id' : 'user_id';

        $query = DB::table('gymies_availability_slots')
            ->where($userIdCol, $trainerId);

        // Only filter on is_active if the column exists
        if (in_array('is_active', $columns)) {
            $query->where('is_active', true);
        }

        $rows = $query->orderBy('start_time')->get();

        $blocks = [];
        foreach ($rows as $row) {
            $r = (array) $row;
            $blocks[] = [
                'start_time' => $this->normalizeTime($r['start_time'] ?? '09:00'),
                'end_time' => $this->normalizeTime($r['end_time'] ?? '17:00'),
                'day_of_week' => (int) ($r['weekday'] ?? $r['day_of_week'] ?? 1),
                'slot_date' => $r['slot_date'] ?? null,
            ];
        }

        return $blocks;
    }

    /**
     * Vind availability blokken die van toepassing zijn op een specifieke datum.
     * Prioriteit: exacte datum match > weekdag match.
     */
    private function getBlocksForDate(array $allBlocks, string $dateStr, int $dayOfWeek): array
    {
        // Eerst: exacte datum matches
        $dateBlocks = array_filter($allBlocks, fn($b) => $b['slot_date'] === $dateStr);
        if (!empty($dateBlocks)) {
            return array_values($dateBlocks);
        }

        // Fallback: weekdag matches (zonder specifieke datum)
        return array_values(array_filter(
            $allBlocks,
            fn($b) => $b['day_of_week'] === $dayOfWeek && $b['slot_date'] === null,
        ));
    }

    /**
     * Laad exceptions (geblokkeerde datums) voor een trainer.
     */
    private function loadExceptions(int $trainerId, string $fromDate, string $toDate): array
    {
        if (!Schema::hasTable('gymies_availability_exceptions')) {
            return [];
        }

        // Detect columns dynamically via column listing (Schema::hasColumn can be cached)
        $columns = Schema::getColumnListing('gymies_availability_exceptions');

        $userIdCol = in_array('trainer_user_id', $columns) ? 'trainer_user_id' : 'user_id';

        // Try blocked_date first, then exception_date, then date
        $dateCol = 'blocked_date';
        if (!in_array('blocked_date', $columns)) {
            $dateCol = in_array('exception_date', $columns) ? 'exception_date' : 'date';
        }

        // Safety: if detected date column doesn't exist, skip silently
        if (!in_array($dateCol, $columns)) {
            return [];
        }

        $rows = DB::table('gymies_availability_exceptions')
            ->where($userIdCol, $trainerId)
            ->whereBetween($dateCol, [$fromDate, $toDate])
            ->get();

        $exceptions = [];
        foreach ($rows as $row) {
            $r = (array) $row;
            $exceptions[] = [
                'date' => $r[$dateCol] ?? '',
                'reason' => $r['reason'] ?? null,
                'is_available' => (bool) ($r['is_available'] ?? false),
            ];
        }

        return $exceptions;
    }

    /**
     * Laad bestaande bookings voor overlap-check.
     */
    private function loadExistingBookings(int $trainerId, string $fromDate, string $toDate): array
    {
        if (!Schema::hasTable('gymies_bookings')) {
            return [];
        }

        $rows = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereIn('status', ['pending', 'confirmed', 'reserved'])
            ->whereDate('scheduled_at', '>=', $fromDate)
            ->whereDate('scheduled_at', '<=', $toDate)
            ->select('scheduled_at', 'duration_minutes')
            ->get();

        $bookings = [];
        foreach ($rows as $row) {
            $start = Carbon::parse($row->scheduled_at);
            $bookings[] = [
                'date' => $start->format('Y-m-d'),
                'start_time' => $start->format('H:i'),
                'end_time' => $start->copy()->addMinutes((int) $row->duration_minutes)->format('H:i'),
            ];
        }

        return $bookings;
    }

    /**
     * Check of twee tijdintervallen overlappen.
     */
    private function timesOverlap(string $start1, string $end1, string $start2, string $end2): bool
    {
        $s1 = $this->timeToMinutes($start1);
        $e1 = $this->timeToMinutes($end1);
        $s2 = $this->timeToMinutes($start2);
        $e2 = $this->timeToMinutes($end2);

        return $s1 < $e2 && $s2 < $e1;
    }

    /**
     * Converteer 'HH:MM' of 'HH:MM:SS' naar minuten sinds middernacht.
     */
    private function timeToMinutes(string $time): int
    {
        $parts = explode(':', $time);
        return ((int) $parts[0]) * 60 + ((int) ($parts[1] ?? 0));
    }

    /**
     * Converteer minuten sinds middernacht naar 'HH:MM'.
     */
    private function minutesToTime(int $minutes): string
    {
        $h = intdiv($minutes, 60);
        $m = $minutes % 60;
        return sprintf('%02d:%02d', $h, $m);
    }

    /**
     * Normaliseer tijd naar 'HH:MM' (strip seconden als aanwezig).
     */
    private function normalizeTime(string $time): string
    {
        $parts = explode(':', $time);
        return sprintf('%02d:%02d', (int) $parts[0], (int) ($parts[1] ?? 0));
    }
}
