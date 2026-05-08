<?php

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

class GymiesCalendarController extends Controller
{
    /**
     * POST me/calendar-token/generate — genereert/hergenereert token, retourneert feed URLs.
     */
    public function generateToken(Request $request): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user) {
            return response()->json(["message" => "Unauthorized"], 401);
        }

        if (!Schema::hasColumn("gymies_users", "calendar_token")) {
            return response()->json(["message" => "Agenda sync niet beschikbaar."], 503);
        }

        $token = Str::random(48);
        DB::table("gymies_users")
            ->where("id", (int) $user->id)
            ->update(["calendar_token" => $token]);

        $baseUrl = rtrim(config("app.url", "https://www.gymies.nl"), "/");
        $feedUrl = $baseUrl . "/api/gymies/calendar/feed/" . $token;
        $webcalUrl = str_replace(["https://", "http://"], "webcal://", $feedUrl);
        $googleUrl = "https://www.google.com/calendar/render?cid=" . urlencode($webcalUrl);

        return response()->json([
            "data" => [
                "token" => $token,
                "feed_url" => $feedUrl,
                "webcal_url" => $webcalUrl,
                "google_calendar_url" => $googleUrl,
            ],
        ]);
    }

    /**
     * GET calendar/feed/{token} — publieke iCal feed (geen auth middleware nodig).
     */
    public function feed(string $token): Response|JsonResponse
    {
        if (strlen($token) < 20) {
            return response()->json(["message" => "Ongeldige token."], 403);
        }
        if (!Schema::hasColumn("gymies_users", "calendar_token")) {
            return response()->json(["message" => "Niet beschikbaar."], 503);
        }

        $user = DB::table("gymies_users")
            ->where("calendar_token", $token)
            ->first(["id", "display_name", "email", "role"]);

        if (!$user) {
            return response()->json(["message" => "Ongeldige of verlopen token."], 403);
        }

        // BUG-002: Add date range limits to prevent querying huge ranges
        $now = now();
        $from = $now->copy()->subDays(30)->toDateTimeString();
        $to = $now->copy()->addDays(60)->toDateTimeString();

        // Enforce strict date range bounds
        $maxPastDays = 365;
        $maxFutureDays = 365;
        if ($from < $now->copy()->subDays($maxPastDays)->toDateTimeString()) {
            $from = $now->copy()->subDays($maxPastDays)->toDateTimeString();
        }
        if ($to > $now->copy()->addDays($maxFutureDays)->toDateTimeString()) {
            $to = $now->copy()->addDays($maxFutureDays)->toDateTimeString();
        }

        if ($user->role === "trainer") {
            $bookings = DB::table("gymies_bookings as b")
                ->leftJoin("gymies_users as c", "c.id", "=", "b.client_user_id")
                ->where("b.trainer_user_id", (int) $user->id)
                ->whereIn("b.status", ["confirmed", "completed", "pending"])
                ->whereBetween("b.scheduled_at", [$from, $to])
                ->orderBy("b.scheduled_at")
                ->get(["b.id", "b.scheduled_at", "b.duration_minutes", "b.status", "b.location_type", "b.location_notes", "c.display_name as client_name"]);
        } else {
            $bookings = DB::table("gymies_bookings as b")
                ->leftJoin("gymies_users as t", "t.id", "=", "b.trainer_user_id")
                ->where("b.client_user_id", (int) $user->id)
                ->whereIn("b.status", ["confirmed", "completed", "pending"])
                ->whereBetween("b.scheduled_at", [$from, $to])
                ->orderBy("b.scheduled_at")
                ->get(["b.id", "b.scheduled_at", "b.duration_minutes", "b.status", "b.location_type", "b.location_notes", "t.display_name as trainer_name"]);
        }

        $calName = "GYMIES - " . ($user->display_name ?? $user->email ?? "Agenda");
        $ical = "BEGIN:VCALENDAR\r\n";
        $ical .= "VERSION:2.0\r\n";
        $ical .= "PRODID:-//GYMIES//Agenda//NL\r\n";
        $ical .= "CALSCALE:GREGORIAN\r\n";
        $ical .= "METHOD:PUBLISH\r\n";
        $ical .= "X-WR-CALNAME:" . $this->escapeIcal($calName) . "\r\n";
        $ical .= "X-WR-TIMEZONE:Europe/Amsterdam\r\n";

        foreach ($bookings as $b) {
            $start = \Carbon\Carbon::parse($b->scheduled_at, "Europe/Amsterdam");
            $duration = max((int) ($b->duration_minutes ?? 60), 15);
            $end = $start->copy()->addMinutes($duration);

            $summary = $user->role === "trainer"
                ? "Sessie met " . ($b->client_name ?? "Klant")
                : "Training bij " . ($b->trainer_name ?? "Trainer");

            $ical .= "BEGIN:VEVENT\r\n";
            $ical .= "UID:gymies-booking-" . $b->id . "@gymies.nl\r\n";
            $ical .= "DTSTART:" . $start->format("Ymd\THis") . "\r\n";
            $ical .= "DTEND:" . $end->format("Ymd\THis") . "\r\n";
            $ical .= "SUMMARY:" . $this->escapeIcal($summary) . "\r\n";
            $loc = trim(($b->location_notes ?? "") !== "" ? (string) $b->location_notes : ucfirst((string) ($b->location_type ?? "")));
            if ($loc !== "") {
                $ical .= "LOCATION:" . $this->escapeIcal($loc) . "\r\n";
            }
            $ical .= "STATUS:" . ($b->status === "cancelled" ? "CANCELLED" : "CONFIRMED") . "\r\n";
            $ical .= "END:VEVENT\r\n";
        }

        $ical .= "END:VCALENDAR\r\n";

        return response($ical, 200)
            ->header("Content-Type", "text/calendar; charset=utf-8")
            ->header("Content-Disposition", "inline; filename=gymies-agenda.ics");
    }

    private function escapeIcal(string $text): string
    {
        return str_replace(["\r\n", "\n", "\r", ",", ";", "\\"], ["\\n", "\\n", "\\n", "\\,", "\;", "\\\\"], $text);
    }
}
