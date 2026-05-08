<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Carbon\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Pro+ Newsletter endpoints.
 * Trainers kunnen nieuwsbrieven versturen naar hun actieve klanten.
 *
 * Tabel: gymies_newsletters (of newsletters)
 * Kolommen: id, trainer_user_id, subject, body, recipient_count, sent_at, created_at, updated_at
 *
 * Tabel: gymies_newsletter_recipients (of newsletter_recipients)
 * Kolommen: id, newsletter_id, client_user_id, email, opened_at, created_at
 */
class GymiesNewsletterController
{
    // ──────────────────────────────────────────────────────────────
    // GET trainer/pro-plus/newsletters
    // ──────────────────────────────────────────────────────────────

    /**
     * Lijst van alle verstuurde nieuwsbrieven voor de ingelogde trainer.
     * Response: { data: [{ id, subject, body_preview, recipient_count, open_rate, sent_at }] }
     */
    public function index(Request $request): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $trainerId = (int) $trainer->id;
        $table = $this->resolveNewslettersTable();
        $recipientsTable = $this->resolveRecipientsTable();

        if (!$table) {
            return response()->json(['data' => []], 200);
        }

        try {
            $query = DB::table($table)
                ->where('trainer_user_id', $trainerId)
                ->orderByDesc('sent_at')
                ->limit(50);

            $newsletters = $query->get();

            $data = $newsletters->map(function ($nl) use ($recipientsTable) {
                $recipientCount = (int) ($nl->recipient_count ?? 0);
                $openRate = null;

                // Bereken open_rate als we een recipients-tabel hebben
                if ($recipientsTable && $recipientCount > 0) {
                    try {
                        $opened = DB::table($recipientsTable)
                            ->where('newsletter_id', $nl->id)
                            ->whereNotNull('opened_at')
                            ->count();
                        $openRate = round($opened / $recipientCount, 2);
                    } catch (\Throwable) {
                        // open_rate blijft null als recipients-tabel problemen geeft
                    }
                }

                return [
                    'id' => (string) $nl->id,
                    'subject' => $nl->subject ?? '',
                    'title' => $nl->subject ?? '',
                    'body_preview' => Str::limit($nl->body ?? '', 120),
                    'recipient_count' => $recipientCount,
                    'recipients' => $recipientCount,
                    'open_rate' => $openRate,
                    'sent_at' => $nl->sent_at,
                    'created_at' => $nl->created_at,
                ];
            })->values()->all();

            return response()->json(['data' => $data]);
        } catch (\Throwable $e) {
            return response()->json(['data' => []], 200);
        }
    }

    // ──────────────────────────────────────────────────────────────
    // POST trainer/pro-plus/newsletter
    // ──────────────────────────────────────────────────────────────

    /**
     * Verstuur een nieuwsbrief naar alle actieve klanten van de trainer.
     *
     * Request body:
     *   - subject (string, required): onderwerpregel
     *   - body (string, required): inhoud van de nieuwsbrief (plain text of HTML)
     *
     * Response: { ok: true, message: "...", sent_to: 12, newsletter_id: "42" }
     *
     * "Actieve klanten" = klanten met minimaal 1 voltooide boeking in de
     * afgelopen 90 dagen bij deze trainer.
     */
    public function send(Request $request): JsonResponse
    {
        $trainer = $request->user();
        if (!$trainer || !$trainer->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $subject = strip_tags(trim($request->input('subject', '')));
        $body = strip_tags(trim($request->input('body', '')));

        if (empty($subject)) {
            return response()->json(['message' => 'Onderwerp is verplicht.'], 422);
        }
        if (empty($body)) {
            return response()->json(['message' => 'Inhoud is verplicht.'], 422);
        }
        if (mb_strlen($subject) > 200) {
            return response()->json(['message' => 'Onderwerp mag max. 200 tekens zijn.'], 422);
        }

        $trainerId = (int) $trainer->id;
        $trainerName = $trainer->display_name ?? $trainer->name ?? 'Trainer';
        $trainerEmail = $trainer->email ?? null;

        // Haal actieve klanten op (voltooide sessie in afgelopen 90 dagen)
        $recipients = $this->getActiveClientEmails($trainerId);

        if (empty($recipients)) {
            return response()->json([
                'message' => 'Geen actieve klanten gevonden om de nieuwsbrief naar te versturen.',
            ], 422);
        }

        // Opslaan in database
        $table = $this->resolveNewslettersTable();
        $recipientsTable = $this->resolveRecipientsTable();
        $newsletterId = null;

        if ($table) {
            try {
                $newsletterId = DB::table($table)->insertGetId([
                    'trainer_user_id' => $trainerId,
                    'subject' => $subject,
                    'body' => $body,
                    'recipient_count' => count($recipients),
                    'sent_at' => now(),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);

                // Sla individuele recipients op voor open-tracking
                if ($recipientsTable && $newsletterId) {
                    $inserts = [];
                    foreach ($recipients as $r) {
                        $inserts[] = [
                            'newsletter_id' => $newsletterId,
                            'client_user_id' => $r['user_id'],
                            'email' => $r['email'],
                            'opened_at' => null,
                            'created_at' => now(),
                        ];
                    }
                    // Bulk insert in chunks van 100
                    foreach (array_chunk($inserts, 100) as $chunk) {
                        DB::table($recipientsTable)->insert($chunk);
                    }
                }
            } catch (\Throwable $e) {
                // Log maar ga door met versturen
                report($e);
            }
        }

        // Sanitize HTML: sta veilige tags toe, strip de rest
        $safeBody = strip_tags($body, [
            'p', 'br', 'b', 'strong', 'i', 'em', 'u', 'ul', 'ol', 'li',
            'h1', 'h2', 'h3', 'h4', 'blockquote', 'a', 'span', 'div',
            'table', 'tr', 'td', 'th', 'thead', 'tbody', 'img', 'hr',
        ]);

        // Wrap in een basis HTML-template voor e-mailclients
        $htmlBody = '<!DOCTYPE html><html><head><meta charset="utf-8">'
            . '<meta name="viewport" content="width=device-width,initial-scale=1">'
            . '<style>body{font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,Helvetica,Arial,sans-serif;'
            . 'line-height:1.6;color:#1E3A5F;max-width:600px;margin:0 auto;padding:20px;}'
            . 'h1,h2,h3{color:#1E3A5F;}a{color:#FEBE23;}blockquote{border-left:3px solid #FEBE23;'
            . 'padding-left:12px;margin-left:0;color:#555;}img{max-width:100%;height:auto;}</style>'
            . '</head><body>' . $safeBody . '</body></html>';

        // Verstuur e-mails als HTML
        $sentCount = 0;
        foreach ($recipients as $recipient) {
            try {
                Mail::html($htmlBody, function ($message) use ($recipient, $subject, $trainerName, $trainerEmail) {
                    $message->to($recipient['email']);
                    $message->subject($subject);
                    if ($trainerEmail) {
                        $message->replyTo($trainerEmail, $trainerName);
                    }
                });
                $sentCount++;
            } catch (\Throwable) {
                // Skip mislukte verzending, ga door met volgende
                continue;
            }
        }

        return response()->json([
            'ok' => true,
            'message' => "Nieuwsbrief verstuurd naar {$sentCount} klanten.",
            'sent_to' => $sentCount,
            'newsletter_id' => $newsletterId ? (string) $newsletterId : null,
        ]);
    }

    // ──────────────────────────────────────────────────────────────
    // Private helpers
    // ──────────────────────────────────────────────────────────────

    /**
     * Haal e-mailadressen op van actieve klanten (sessie in afgelopen 90 dagen).
     * @return array<array{user_id: int, email: string}>
     */
    private function getActiveClientEmails(int $trainerId): array
    {
        $bookingsTable = $this->resolveTable(['gymies_bookings', 'bookings']);
        $usersTable = $this->resolveTable(['gymies_users', 'users']);

        if (!$bookingsTable || !$usersTable) {
            return [];
        }

        $trainerCol = $this->resolveColumn($bookingsTable, ['trainer_user_id', 'trainer_id']);
        $clientCol = $this->resolveColumn($bookingsTable, ['client_user_id', 'client_id', 'user_id']);
        $statusCol = $this->resolveColumn($bookingsTable, ['status', 'booking_status', 'state']);

        if (!$trainerCol || !$clientCol) {
            return [];
        }

        $cutoff = now()->subDays(90);

        try {
            $query = DB::table($bookingsTable . ' as b')
                ->select([
                    'u.id as user_id',
                    'u.email',
                ])
                ->join($usersTable . ' as u', 'u.id', '=', "b.{$clientCol}")
                ->where("b.{$trainerCol}", $trainerId)
                ->whereNotNull('u.email')
                ->where('u.email', '!=', '')
                ->groupBy('u.id', 'u.email');

            if ($statusCol) {
                $query->whereIn("b.{$statusCol}", ['completed', 'done', 'finished', 'checked_in']);
            }

            // Alleen klanten met recente activiteit
            $scheduledCol = $this->resolveColumn($bookingsTable, ['scheduled_at', 'session_at', 'created_at']);
            if ($scheduledCol) {
                $query->havingRaw("MAX(b.{$scheduledCol}) >= ?", [$cutoff->format('Y-m-d H:i:s')]);
            }

            return $query->limit(500)->get()->map(fn ($r) => [
                'user_id' => (int) $r->user_id,
                'email' => $r->email,
            ])->all();
        } catch (\Throwable) {
            return [];
        }
    }

    private function resolveNewslettersTable(): ?string
    {
        return $this->resolveTable(['gymies_newsletters', 'newsletters']);
    }

    private function resolveRecipientsTable(): ?string
    {
        return $this->resolveTable(['gymies_newsletter_recipients', 'newsletter_recipients']);
    }

    private function resolveTable(array $candidates): ?string
    {
        foreach ($candidates as $t) {
            if (Schema::hasTable($t)) {
                return $t;
            }
        }
        return null;
    }

    private function resolveColumn(string $table, array $candidates): ?string
    {
        foreach ($candidates as $c) {
            if (Schema::hasColumn($table, $c)) {
                return $c;
            }
        }
        return null;
    }
}
