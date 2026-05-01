<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Carbon\Carbon;

/**
 * GymiesInsightsController
 * ────────────────────────
 * AI-achtige features die data omzetten in bruikbare inzichten:
 *
 * 1. Smart Scheduling — detecteer trainingspatronen van sporters
 * 2. Trainer Insights — natuurlijke taal statistieken
 * 3. Pricing Insight — marktpositionering voor trainers
 * 4. Reschedule Suggestions — alternatieven bij annulering
 */
final class GymiesInsightsController extends Controller
{
    // ── 1. Smart Scheduling ─────────────────────────────────────────────

    /**
     * GET insights/smart-schedule
     * Detecteer het trainingspatroon van de ingelogde sporter en
     * stel beschikbare trainers voor op die momenten.
     */
    public function smartSchedule(Request $request): JsonResponse
    {
        $user = $request->user();

        // Haal boekingen van afgelopen 3 maanden
        $bookings = DB::table('gymies_bookings')
            ->where('client_user_id', $user->id)
            ->where('status', 'confirmed')
            ->where('scheduled_at', '>=', now()->subMonths(3))
            ->orderBy('scheduled_at')
            ->get(['scheduled_at', 'trainer_user_id', 'duration_minutes']);

        if ($bookings->count() < 3) {
            return response()->json([
                'success' => true,
                'data' => [
                    'has_pattern' => false,
                    'message' => 'Nog niet genoeg boekingen voor patroonherkenning.',
                    'minimum_bookings' => 3,
                    'current_bookings' => $bookings->count(),
                ],
            ]);
        }

        // Detecteer dag+tijd patroon
        $pattern = $this->detectPattern($bookings);

        // Vind beschikbare trainers op de patroon-momenten
        $suggestions = [];
        if ($pattern['has_pattern']) {
            $suggestions = $this->findAvailableTrainers(
                $user->id,
                $pattern['preferred_days'],
                $pattern['preferred_time'],
            );
        }

        return response()->json([
            'success' => true,
            'data' => [
                'has_pattern' => $pattern['has_pattern'],
                'preferred_days' => $pattern['preferred_days'],
                'preferred_time' => $pattern['preferred_time'],
                'confidence' => $pattern['confidence'],
                'message' => $pattern['message'],
                'suggestions' => $suggestions,
                'total_sessions' => $bookings->count(),
            ],
        ]);
    }

    private function detectPattern($bookings): array
    {
        $dayCounts = [];
        $hourCounts = [];

        foreach ($bookings as $b) {
            $dt = Carbon::parse($b->scheduled_at);
            $dayName = strtolower($dt->format('l')); // monday, tuesday, etc.
            $hour = $dt->format('H:00');

            $dayCounts[$dayName] = ($dayCounts[$dayName] ?? 0) + 1;
            $hourCounts[$hour] = ($hourCounts[$hour] ?? 0) + 1;
        }

        $total = $bookings->count();
        arsort($dayCounts);
        arsort($hourCounts);

        // Selecteer dagen die >25% van de boekingen uitmaken
        $preferredDays = [];
        foreach ($dayCounts as $day => $count) {
            if ($count / $total >= 0.25) {
                $preferredDays[] = $day;
            }
        }

        // Selecteer meest voorkomende tijd (±1 uur range)
        $preferredTime = array_key_first($hourCounts) ?? '18:00';
        $topTimeCount = reset($hourCounts) ?: 0;
        $timeConfidence = $total > 0 ? round($topTimeCount / $total * 100) : 0;

        $hasPattern = count($preferredDays) > 0 && $timeConfidence >= 30;
        $confidence = $hasPattern
            ? min(100, intval(($timeConfidence + (count($preferredDays) > 0 ? 50 : 0)) / 2))
            : 0;

        $dayLabels = [
            'monday' => 'maandag', 'tuesday' => 'dinsdag', 'wednesday' => 'woensdag',
            'thursday' => 'donderdag', 'friday' => 'vrijdag', 'saturday' => 'zaterdag',
            'sunday' => 'zondag',
        ];

        $message = $hasPattern
            ? sprintf(
                'Je traint vaak op %s rond %s.',
                implode(' en ', array_map(fn($d) => $dayLabels[$d] ?? $d, $preferredDays)),
                $preferredTime
            )
            : 'Nog geen duidelijk trainingspatroon gevonden.';

        return [
            'has_pattern' => $hasPattern,
            'preferred_days' => $preferredDays,
            'preferred_time' => $preferredTime,
            'confidence' => $confidence,
            'message' => $message,
        ];
    }

    private function findAvailableTrainers(int $userId, array $days, string $time): array
    {
        // Haal trainers waarmee de sporter eerder heeft getraind
        $trainerIds = DB::table('gymies_bookings')
            ->where('client_user_id', $userId)
            ->where('status', 'confirmed')
            ->distinct()
            ->pluck('trainer_user_id')
            ->toArray();

        if (empty($trainerIds)) return [];

        $suggestions = [];
        foreach (array_slice($trainerIds, 0, 3) as $trainerId) {
            $trainer = DB::table('users')->where('id', $trainerId)->first(['id', 'name']);
            if (!$trainer) continue;

            $suggestions[] = [
                'trainer_id' => $trainer->id,
                'trainer_name' => $trainer->name ?? 'Trainer',
                'preferred_days' => $days,
                'preferred_time' => $time,
            ];
        }

        return $suggestions;
    }

    // ── 2. Trainer Insights ─────────────────────────────────────────────

    /**
     * GET insights/trainer
     * Genereer natuurlijke taal inzichten voor de ingelogde trainer.
     */
    public function trainerInsights(Request $request): JsonResponse
    {
        $user = $request->user();
        $insights = [];

        // Boekingen deze maand vs vorige maand
        $thisMonth = DB::table('gymies_bookings')
            ->where('trainer_user_id', $user->id)
            ->whereIn('status', ['confirmed', 'completed'])
            ->where('scheduled_at', '>=', now()->startOfMonth())
            ->count();

        $lastMonth = DB::table('gymies_bookings')
            ->where('trainer_user_id', $user->id)
            ->whereIn('status', ['confirmed', 'completed'])
            ->where('scheduled_at', '>=', now()->subMonth()->startOfMonth())
            ->where('scheduled_at', '<', now()->startOfMonth())
            ->count();

        if ($lastMonth > 0) {
            $change = round(($thisMonth - $lastMonth) / $lastMonth * 100);
            if ($change > 0) {
                $insights[] = [
                    'type' => 'bookings_trend',
                    'sentiment' => 'positive',
                    'message' => "Je hebt deze maand {$change}% meer boekingen dan vorige maand.",
                    'value' => $thisMonth,
                    'previous' => $lastMonth,
                ];
            } elseif ($change < 0) {
                $insights[] = [
                    'type' => 'bookings_trend',
                    'sentiment' => 'neutral',
                    'message' => "Je boekingen zijn " . abs($change) . "% gedaald t.o.v. vorige maand. Tip: update je beschikbaarheid.",
                    'value' => $thisMonth,
                    'previous' => $lastMonth,
                ];
            } else {
                $insights[] = [
                    'type' => 'bookings_trend',
                    'sentiment' => 'neutral',
                    'message' => "Je boekingen zijn stabiel: {$thisMonth} deze maand, net als vorige maand.",
                    'value' => $thisMonth,
                    'previous' => $lastMonth,
                ];
            }
        }

        // Rating trend
        if (Schema::hasTable('gymies_reviews')) {
            $avgRating = DB::table('gymies_reviews')
                ->where('trainer_user_id', $user->id)
                ->avg('rating');

            $reviewCount = DB::table('gymies_reviews')
                ->where('trainer_user_id', $user->id)
                ->count();

            if ($avgRating !== null && $reviewCount > 0) {
                $stars = round($avgRating, 1);
                $insights[] = [
                    'type' => 'rating',
                    'sentiment' => $stars >= 4.5 ? 'positive' : ($stars >= 3.5 ? 'neutral' : 'attention'),
                    'message' => "Je gemiddelde beoordeling is {$stars} sterren op basis van {$reviewCount} reviews.",
                    'value' => $stars,
                    'count' => $reviewCount,
                ];
            }
        }

        // Omzet deze maand
        $revenueCents = DB::table('gymies_bookings')
            ->where('trainer_user_id', $user->id)
            ->where('status', 'confirmed')
            ->where('scheduled_at', '>=', now()->startOfMonth())
            ->sum('amount_cents');

        if ($revenueCents > 0) {
            $euros = number_format($revenueCents / 100, 0, ',', '.');
            $insights[] = [
                'type' => 'revenue',
                'sentiment' => 'positive',
                'message' => "Je verwachte omzet deze maand is €{$euros}.",
                'value' => (int) $revenueCents,
            ];
        }

        // Populairste dag
        $popularDay = DB::table('gymies_bookings')
            ->where('trainer_user_id', $user->id)
            ->whereIn('status', ['confirmed', 'completed'])
            ->where('scheduled_at', '>=', now()->subMonths(2))
            ->selectRaw("DAYNAME(scheduled_at) as day_name, COUNT(*) as cnt")
            ->groupBy('day_name')
            ->orderByDesc('cnt')
            ->first();

        if ($popularDay) {
            $dayLabels = [
                'Monday' => 'maandag', 'Tuesday' => 'dinsdag', 'Wednesday' => 'woensdag',
                'Thursday' => 'donderdag', 'Friday' => 'vrijdag', 'Saturday' => 'zaterdag',
                'Sunday' => 'zondag',
            ];
            $dayNl = $dayLabels[$popularDay->day_name] ?? $popularDay->day_name;
            $insights[] = [
                'type' => 'popular_day',
                'sentiment' => 'info',
                'message' => "Je drukste dag is {$dayNl} met {$popularDay->cnt} sessies in de afgelopen 2 maanden.",
                'value' => $popularDay->day_name,
                'count' => (int) $popularDay->cnt,
            ];
        }

        return response()->json([
            'success' => true,
            'data' => [
                'insights' => $insights,
                'generated_at' => now()->toIso8601String(),
            ],
        ]);
    }

    // ── 3. Pricing Insight ──────────────────────────────────────────────

    /**
     * GET insights/pricing
     * Vergelijk de prijs van de trainer met het marktgemiddelde in hun regio.
     */
    public function pricingInsight(Request $request): JsonResponse
    {
        $user = $request->user();

        // Haal trainer profiel
        $profile = DB::table('gymies_trainer_profiles')
            ->where('user_id', $user->id)
            ->first();

        if (!$profile) {
            return response()->json([
                'success' => true,
                'data' => ['message' => 'Geen trainerprofiel gevonden.'],
            ]);
        }

        $myRate = $profile->hourly_rate_cents ?? 0;
        $myCity = $profile->city ?? $profile->region ?? null;

        if ($myRate <= 0) {
            return response()->json([
                'success' => true,
                'data' => ['message' => 'Stel eerst je tarief in.'],
            ]);
        }

        // Marktgemiddelde in dezelfde stad/regio
        $query = DB::table('gymies_trainer_profiles')
            ->where('user_id', '!=', $user->id)
            ->where('hourly_rate_cents', '>', 0);

        if ($myCity) {
            $query->where(function ($q) use ($myCity) {
                $q->where('city', $myCity)
                  ->orWhere('region', $myCity);
            });
        }

        $marketStats = $query->selectRaw('
            AVG(hourly_rate_cents) as avg_rate,
            MIN(hourly_rate_cents) as min_rate,
            MAX(hourly_rate_cents) as max_rate,
            COUNT(*) as trainer_count
        ')->first();

        if (!$marketStats || $marketStats->trainer_count < 3) {
            return response()->json([
                'success' => true,
                'data' => [
                    'message' => 'Nog niet genoeg trainers in jouw regio voor een vergelijking.',
                    'your_rate_cents' => $myRate,
                ],
            ]);
        }

        $avgRate = (int) round($marketStats->avg_rate);
        $diff = $myRate - $avgRate;
        $diffPercent = $avgRate > 0 ? round($diff / $avgRate * 100) : 0;

        // Genereer advies in natuurlijke taal
        if ($diffPercent < -15) {
            $message = sprintf(
                'Trainers in %s vragen gemiddeld €%s. Jij vraagt €%s — %d%% lager. Dit kan meer boekingen opleveren, maar overweeg een verhoging.',
                $myCity ?? 'jouw regio',
                number_format($avgRate / 100, 0),
                number_format($myRate / 100, 0),
                abs($diffPercent)
            );
            $sentiment = 'opportunity';
        } elseif ($diffPercent > 15) {
            $message = sprintf(
                'Trainers in %s vragen gemiddeld €%s. Jij vraagt €%s — %d%% hoger. Zorg dat je profiel en reviews dit ondersteunen.',
                $myCity ?? 'jouw regio',
                number_format($avgRate / 100, 0),
                number_format($myRate / 100, 0),
                $diffPercent
            );
            $sentiment = 'attention';
        } else {
            $message = sprintf(
                'Je tarief van €%s ligt dicht bij het gemiddelde van €%s in %s. Goed gepositioneerd!',
                number_format($myRate / 100, 0),
                number_format($avgRate / 100, 0),
                $myCity ?? 'jouw regio'
            );
            $sentiment = 'positive';
        }

        return response()->json([
            'success' => true,
            'data' => [
                'your_rate_cents' => $myRate,
                'market_avg_cents' => $avgRate,
                'market_min_cents' => (int) $marketStats->min_rate,
                'market_max_cents' => (int) $marketStats->max_rate,
                'trainer_count' => (int) $marketStats->trainer_count,
                'difference_percent' => $diffPercent,
                'sentiment' => $sentiment,
                'message' => $message,
                'region' => $myCity,
            ],
        ]);
    }

    // ── 4. Reschedule Suggestions (Annulering als kans) ─────────────────

    /**
     * GET insights/reschedule-options/{bookingId}
     * Bij annulering: toon beschikbare alternatieven van dezelfde trainer.
     */
    public function rescheduleOptions(Request $request, string $bookingId): JsonResponse
    {
        $user = $request->user();

        $booking = DB::table('gymies_bookings')
            ->where('id', (int) $bookingId)
            ->where(function ($q) use ($user) {
                $q->where('client_user_id', $user->id)
                  ->orWhere('trainer_user_id', $user->id);
            })
            ->first();

        if (!$booking) {
            return response()->json(['success' => false, 'message' => 'Boeking niet gevonden.'], 404);
        }

        $trainerId = (int) $booking->trainer_user_id;
        $duration = (int) ($booking->duration_minutes ?? 60);
        $originalDate = Carbon::parse($booking->scheduled_at);

        // Zoek beschikbare slots van dezelfde trainer in komende 7 dagen
        $alternatives = [];
        $hasAvailabilityTable = Schema::hasTable('gymies_availability_slots');

        if ($hasAvailabilityTable) {
            $slots = DB::table('gymies_availability_slots')
                ->where('user_id', $trainerId)
                ->where('is_active', true)
                ->get(['day_of_week', 'start_time', 'end_time']);

            // Genereer concrete datums voor de komende 7 dagen
            for ($i = 1; $i <= 7; $i++) {
                $date = now()->addDays($i);
                $dayOfWeek = $date->dayOfWeekIso; // 1=ma, 7=zo

                foreach ($slots as $slot) {
                    if ((int) $slot->day_of_week !== $dayOfWeek) continue;

                    $slotStart = Carbon::parse($date->format('Y-m-d') . ' ' . $slot->start_time);

                    // Check of er al een boeking op dit moment is
                    $hasBooking = DB::table('gymies_bookings')
                        ->where('trainer_user_id', $trainerId)
                        ->where('id', '!=', (int) $bookingId)
                        ->whereIn('status', ['confirmed', 'pending', 'reserved'])
                        ->where('scheduled_at', $slotStart->toDateTimeString())
                        ->exists();

                    if (!$hasBooking && $slotStart->isFuture()) {
                        $alternatives[] = [
                            'date' => $slotStart->format('Y-m-d'),
                            'time' => $slotStart->format('H:i'),
                            'day_label' => $this->dutchDayName($slotStart),
                            'formatted' => $this->dutchDayName($slotStart) . ' ' . $slotStart->format('d M') . ' om ' . $slotStart->format('H:i'),
                        ];
                    }
                }
            }
        }

        // Haal trainer naam
        $trainer = DB::table('users')->where('id', $trainerId)->first(['name']);
        $trainerName = $trainer->name ?? 'Je trainer';

        $message = count($alternatives) > 0
            ? "$trainerName is ook beschikbaar op andere momenten. Wil je verplaatsen?"
            : "Helaas zijn er geen alternatieve tijden beschikbaar deze week.";

        return response()->json([
            'success' => true,
            'data' => [
                'booking_id' => (int) $bookingId,
                'trainer_id' => $trainerId,
                'trainer_name' => $trainerName,
                'original_date' => $originalDate->toIso8601String(),
                'alternatives' => array_slice($alternatives, 0, 5),
                'message' => $message,
                'has_alternatives' => count($alternatives) > 0,
            ],
        ]);
    }

    private function dutchDayName(Carbon $date): string
    {
        $days = [
            'Monday' => 'Maandag', 'Tuesday' => 'Dinsdag', 'Wednesday' => 'Woensdag',
            'Thursday' => 'Donderdag', 'Friday' => 'Vrijdag', 'Saturday' => 'Zaterdag',
            'Sunday' => 'Zondag',
        ];
        return $days[$date->format('l')] ?? $date->format('l');
    }
}
