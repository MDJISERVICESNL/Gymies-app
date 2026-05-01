<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Traits\GymiesRequireTrainerTrait;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use App\Helpers\GymiesChatBroadcast;
use App\Http\Controllers\Gymies\GymiesPlanManager;

/**
 * Trainer operationele endpoints: inkomsten en berichten.
 */
final class GymiesTrainerOpsController extends Controller
{
    use GymiesRequireTrainerTrait;

    private const PAYOUT_FEE_PERCENT = [
        'weekly' => 1.5,
        'biweekly' => 1.0,
        'monthly' => 0.0,
    ];

    public function revenue(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        try {

        $trainerId = (int) $user->id;

        // Veiligheidscheck: tabel moet bestaan
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json([
                'data' => [
                    'total_revenue_cents' => 0,
                    'paid_revenue_cents' => 0,
                    'pending_payout_cents' => 0,
                    'monthly_revenue_cents' => [],
                    'items' => [],
                ],
            ]);
        }

        $statusFilter = strtolower(trim((string) $request->query('status', '')));
        $allowedFilters = ['paid', 'cash', 'open', 'cancelled'];
        if ($statusFilter !== '' && !in_array($statusFilter, $allowedFilters, true)) {
            return response()->json(['message' => 'Ongeldige statusfilter. Gebruik paid, cash, open of cancelled.'], 422);
        }

        $bookingSelect = ['id'];
        // Elke kolom veilig checken
        foreach (['scheduled_at', 'status', 'amount_cents', 'paid_at', 'payment_method'] as $col) {
            if (Schema::hasColumn('gymies_bookings', $col)) {
                $bookingSelect[] = $col;
            }
        }

        $rows = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereNotNull('amount_cents')
            ->orderByDesc('scheduled_at')
            ->limit(250)
            ->get($bookingSelect);

        $bookingIds = $rows->pluck('id')->map(fn ($id) => (int) $id)->all();
        $latestTxByBooking = [];
        if (!empty($bookingIds) && Schema::hasTable('gymies_payment_transactions')) {
            $latestIds = DB::table('gymies_payment_transactions')
                ->whereIn('booking_id', $bookingIds)
                ->selectRaw('MAX(id) as id')
                ->groupBy('booking_id')
                ->pluck('id')
                ->map(fn ($id) => (int) $id)
                ->all();
            if (!empty($latestIds)) {
                $latestTxByBooking = DB::table('gymies_payment_transactions')
                    ->whereIn('id', $latestIds)
                    ->get(['booking_id', 'status', 'payment_method', 'provider', 'provider_transaction_id', 'paid_at', 'amount_cents'])
                    ->keyBy(fn ($r) => (int) $r->booking_id)
                    ->all();
            }
        }

        $items = [];
        $totalRevenue = 0;
        $paidRevenue = 0;
        $pendingPayout = 0;
        $monthly = [];

        foreach ($rows as $r) {
            $bookingId = (int) $r->id;
            $tx = $latestTxByBooking[$bookingId] ?? null;
            $scheduledAt = $r->scheduled_at ?? null;
            $bookingPaidAt = $r->paid_at ?? null;
            $bookingPaymentMethod = $r->payment_method ?? '';
            $bookingStatus = $r->status ?? '';
            $bookingAmountCents = $r->amount_cents ?? 0;

            $storedPaymentMethod = $tx ? (string) ($tx->payment_method ?? '') : (string) $bookingPaymentMethod;
            $provider = $tx ? (string) ($tx->provider ?? '') : '';
            $paymentMethod = $this->toCanonicalPaymentMethod($storedPaymentMethod, $provider);
            $rawStatus = $tx ? (string) ($tx->status ?? '') : (!empty($bookingPaidAt) ? 'paid' : 'pending');
            $paymentStatus = $this->toCanonicalPaymentStatus($rawStatus, $paymentMethod, (string) $bookingStatus);
            if ($statusFilter !== '' && $paymentStatus !== $statusFilter) {
                continue;
            }

            $amountCents = (int) ($tx->amount_cents ?? $bookingAmountCents);
            $paidAt = $tx && !empty($tx->paid_at) ? $tx->paid_at : $bookingPaidAt;
            $paymentReference = $tx ? (string) ($tx->provider_transaction_id ?? '') : null;

            if ($paymentStatus !== 'cancelled') {
                $totalRevenue += $amountCents;
            }
            if (in_array($paymentStatus, ['paid', 'cash'], true)) {
                $paidRevenue += $amountCents;
            }
            if ($paymentStatus === 'open') {
                $pendingPayout += $amountCents;
            }
            if (!empty($scheduledAt) && $paymentStatus !== 'cancelled') {
                $monthKey = substr((string) $scheduledAt, 0, 7);
                $monthly[$monthKey] = ($monthly[$monthKey] ?? 0) + $amountCents;
            }

            $items[] = [
                'id' => (string) $bookingId,
                'booking_id' => (string) $bookingId,
                'scheduled_at' => $scheduledAt,
                'amount_cents' => $amountCents,
                'status' => (string) $bookingStatus,
                'payment_status' => $paymentStatus,
                'payment_method' => $paymentMethod,
                'payment_reference' => $paymentReference !== '' ? $paymentReference : null,
                'paid_at' => $paidAt,
            ];
        }

        return response()->json([
            'data' => [
                'total_revenue_cents' => $totalRevenue,
                'paid_revenue_cents' => $paidRevenue,
                'pending_payout_cents' => $pendingPayout,
                'monthly_revenue_cents' => $monthly,
                'items' => $items,
            ],
        ]);

        } catch (\Throwable $e) {
            \Log::error('[GymiesTrainerOpsController::revenue] Error for trainer ' . ($user->id ?? '?') . ': ' . $e->getMessage());
            return response()->json([
                'data' => [
                    'total_revenue_cents' => 0,
                    'paid_revenue_cents' => 0,
                    'pending_payout_cents' => 0,
                    'monthly_revenue_cents' => [],
                    'items' => [],
                    '_error' => 'Kon inkomsten niet laden: ' . $e->getMessage(),
                ],
            ]);
        }
    }

    /**
     * Omzet-voorspeller (Pro/Studio): geplande sessies deze maand + churn-proxy uit sleeping wallets.
     * Starter krijgt 403 of lege payload met upgrade hint.
     */
    public function revenueForecast(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        if (!$this->trainerCanEditPackages($trainerId)) {
            return response()->json([
                'data' => [
                    'available' => false,
                    'message' => 'Omzet-voorspeller is beschikbaar vanaf Pro. Upgrade om vooruit te kijken.',
                ],
            ]);
        }
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => ['available' => true, 'forecast_cents' => 0, 'message' => 'Geen boekingen.']]);
        }

        $now = CarbonImmutable::now();
        $monthStart = $now->startOfMonth();
        $monthEnd = $now->endOfMonth();
        $prevStart = $monthStart->subMonth();
        $prevEnd = $monthStart->subSecond();

        $statuses = ['confirmed', 'pending', 'completed', 'reserved', 'no_show'];
        $splitDeduct = [];
        $sumMonth = function (CarbonImmutable $from, CarbonImmutable $to, bool $onlyCompleted = false) use ($trainerId, $statuses, &$splitDeduct): int {
            $q = DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerId)
                ->whereNotNull('amount_cents')
                ->where('scheduled_at', '>=', $from->toDateTimeString())
                ->where('scheduled_at', '<=', $to->toDateTimeString());
            if ($onlyCompleted) {
                $q->whereIn('status', ['confirmed', 'completed', 'no_show']);
            } else {
                $q->whereIn('status', $statuses);
            }
            $rows = $q->get(['id', 'amount_cents', 'status']);
            if ($rows->isEmpty()) {
                return 0;
            }
            $ids = $rows->pluck('id')->all();
            if (!empty($ids) && Schema::hasTable('gymies_admin_refunds')) {
                $splitDeduct = DB::table('gymies_admin_refunds')
                    ->where('type', 'split')
                    ->whereIn('booking_id', $ids)
                    ->pluck('amount_cents', 'booking_id')
                    ->map(fn ($c) => (int) $c)
                    ->all();
            } else {
                $splitDeduct = [];
            }
            $sum = 0;
            foreach ($rows as $r) {
                if ($onlyCompleted && !in_array((string) $r->status, ['confirmed', 'completed', 'no_show'], true)) {
                    continue;
                }
                $sum += (int) ($r->amount_cents ?? 0) - (int) ($splitDeduct[(int) $r->id] ?? 0);
            }
            return max($sum, 0);
        };

        $forecastCents = $sumMonth($monthStart, $monthEnd, false);
        $realizedPrevCents = $sumMonth($prevStart, $prevEnd, true);

        // Churn-proxy: klanten met resterende strippen-sessies maar 14d niet geboekt × gem. sessiewaarde
        $sleepingCount = 0;
        if (Schema::hasTable('gymies_packages') && Schema::hasColumn('gymies_bookings', 'package_id')) {
            $cutoff = $now->subDays(14)->toDateTimeString();
            $packages = DB::table('gymies_packages')->where('trainer_user_id', $trainerId)->get(['id', 'sessions_count']);
            if (!$packages->isEmpty()) {
                $clientIds = DB::table('gymies_bookings')
                    ->where('trainer_user_id', $trainerId)
                    ->distinct()
                    ->pluck('client_user_id')
                    ->filter()
                    ->unique()
                    ->values()
                    ->all();
                $bookingCountPrev = DB::table('gymies_bookings')
                    ->where('trainer_user_id', $trainerId)
                    ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                    ->where('scheduled_at', '>=', $prevStart->toDateTimeString())
                    ->where('scheduled_at', '<=', $prevEnd->toDateTimeString())
                    ->count();
                $avgPrev = $bookingCountPrev > 0 ? (int) round($realizedPrevCents / $bookingCountPrev) : 0;
                foreach ($clientIds as $cid) {
                    $remainingTotal = 0;
                    foreach ($packages as $pkg) {
                        $sessionsCount = (int) ($pkg->sessions_count ?? 0);
                        if ($sessionsCount <= 0) {
                            continue;
                        }
                        $used = (int) DB::table('gymies_bookings')
                            ->where('client_user_id', $cid)
                            ->where('package_id', (int) $pkg->id)
                            ->whereNotIn('status', ['cancelled'])
                            ->count();
                        $remainingTotal += max(0, $sessionsCount - $used);
                    }
                    if ($remainingTotal < 1) {
                        continue;
                    }
                    $lastBooking = DB::table('gymies_bookings')
                        ->where('client_user_id', $cid)
                        ->where('trainer_user_id', $trainerId)
                        ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                        ->orderByDesc('scheduled_at')
                        ->value('scheduled_at');
                    if ($lastBooking !== null && (string) $lastBooking >= $cutoff) {
                        continue;
                    }
                    $sleepingCount++;
                }
                if ($sleepingCount > 0 && $avgPrev > 0) {
                    $churnRisk = (int) round($sleepingCount * $avgPrev * 0.3);
                    $forecastCents = max($forecastCents - $churnRisk, 0);
                }
            }
        }

        $growthPercent = null;
        if ($realizedPrevCents > 0) {
            $growthPercent = (int) round(($forecastCents - $realizedPrevCents) / $realizedPrevCents * 100);
        }

        $monthNamesNl = [
            1 => 'januari', 2 => 'februari', 3 => 'maart', 4 => 'april',
            5 => 'mei', 6 => 'juni', 7 => 'juli', 8 => 'augustus',
            9 => 'september', 10 => 'oktober', 11 => 'november', 12 => 'december',
        ];
        $monthName = $monthNamesNl[(int) $now->format('n')] ?? $now->format('F');
        // Gebruik 2 decimalen om afrondingsverlies (bijv. €49,50 → €50) te voorkomen
        $euro = number_format($forecastCents / 100, 2, ',', '.');
        $growthText = $growthPercent === null
            ? 'Nog geen vergelijking mogelijk (vorige maand leeg).'
            : ($growthPercent >= 0
                ? "Op schema voor +{$growthPercent}% groei t.o.v. vorige maand."
                : "{$growthPercent}% t.o.v. vorige maand; focus op retentie.");

        $message = "Verwachte omzet {$monthName}: €{$euro},- ({$growthText})";

        return response()->json([
            'data' => [
                'available' => true,
                'forecast_cents' => $forecastCents,
                'realized_previous_month_cents' => $realizedPrevCents,
                'growth_percent_vs_previous' => $growthPercent,
                'sleeping_clients_count' => $sleepingCount,
                'month_label' => $monthName,
                'message' => $message,
            ],
        ]);
    }

    public function conversations(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        try {

        // Veiligheidscheck: tabellen moeten bestaan
        if (!Schema::hasTable('gymies_conversations')) {
            return response()->json(['data' => []]);
        }

        $hasMessages = Schema::hasTable('gymies_messages');
        $hasDisplayName = Schema::hasColumn('gymies_users', 'display_name');

        // Client-naam kolom: display_name of email als fallback
        $clientNameCol = $hasDisplayName ? 'client.display_name as client_name' : 'client.email as client_name';

        // Bouw select-kolommen veilig op
        $selectCols = ['c.id', 'c.client_user_id', 'c.updated_at'];
        if (Schema::hasColumn('gymies_conversations', 'booking_id')) {
            $selectCols[] = 'c.booking_id';
        }
        $selectCols[] = $clientNameCol;

        $query = DB::table('gymies_conversations as c')
            ->join('gymies_users as client', 'client.id', '=', 'c.client_user_id')
            ->where('c.trainer_user_id', $user->id)
            ->orderByDesc('c.updated_at');

        if ($hasMessages) {
            $lastMessageSub = DB::table('gymies_messages')
                ->select('conversation_id', DB::raw('MAX(id) as last_message_id'))
                ->groupBy('conversation_id');

            $query->leftJoinSub($lastMessageSub, 'lm', function ($join) {
                $join->on('lm.conversation_id', '=', 'c.id');
            })
            ->leftJoin('gymies_messages as m', 'm.id', '=', 'lm.last_message_id');

            $selectCols[] = 'm.body as last_message';
            $selectCols[] = 'm.created_at as last_message_at';
            $selectCols[] = 'm.from_user_id as last_from_user_id';
            if (Schema::hasColumn('gymies_messages', 'read_at')) {
                $selectCols[] = 'm.read_at as last_read_at';
            }
        }

        $rows = $query->select($selectCols)->get();

        // Support-conversaties (tickets) waar trainer de indiener is
        $supportRows = collect();
        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
            $supportNameCol = $hasDisplayName ? 'gymies.display_name as client_name' : 'gymies.email as client_name';
            $supportSelectCols = ['c.id', 'c.client_user_id', 'c.updated_at'];
            if (Schema::hasColumn('gymies_conversations', 'booking_id')) {
                $supportSelectCols[] = 'c.booking_id';
            }
            $supportSelectCols[] = $supportNameCol;

            $supportQuery = DB::table('gymies_conversations as c')
                ->join('gymies_users as gymies', 'gymies.id', '=', 'c.trainer_user_id')
                ->where('c.client_user_id', $user->id)
                ->whereNotNull('c.support_ticket_id')
                ->orderByDesc('c.updated_at');

            if ($hasMessages) {
                $lastMessageSub2 = DB::table('gymies_messages')
                    ->select('conversation_id', DB::raw('MAX(id) as last_message_id'))
                    ->groupBy('conversation_id');

                $supportQuery->leftJoinSub($lastMessageSub2, 'lm', function ($join) {
                    $join->on('lm.conversation_id', '=', 'c.id');
                })
                ->leftJoin('gymies_messages as m', 'm.id', '=', 'lm.last_message_id');

                $supportSelectCols[] = 'm.body as last_message';
                $supportSelectCols[] = 'm.created_at as last_message_at';
                $supportSelectCols[] = 'm.from_user_id as last_from_user_id';
                if (Schema::hasColumn('gymies_messages', 'read_at')) {
                    $supportSelectCols[] = 'm.read_at as last_read_at';
                }
            }

            $supportRows = $supportQuery->select($supportSelectCols)->get();
        }

        $all = $rows->concat($supportRows)->sortByDesc('updated_at')->values();
        $data = $all->map(fn ($r) => [
            'id' => (string) $r->id,
            'client_user_id' => (string) $r->client_user_id,
            'client_name' => $r->client_name ?? 'Klant',
            'booking_id' => property_exists($r, 'booking_id') && $r->booking_id ? (string) $r->booking_id : null,
            'last_message' => $r->last_message ?? null,
            'last_message_at' => $r->last_message_at ?? null,
            'last_from_user_id' => property_exists($r, 'last_from_user_id') && $r->last_from_user_id ? (string) $r->last_from_user_id : null,
            'last_read_at' => $r->last_read_at ?? null,
            'updated_at' => $r->updated_at,
        ])->all();

        return response()->json(['data' => $data]);

        } catch (\Throwable $e) {
            \Log::error('[GymiesTrainerOpsController::conversations] Error for trainer ' . ($user->id ?? '?') . ': ' . $e->getMessage());
            return response()->json(['data' => [], '_error' => $e->getMessage()], 500);
        }
    }

    public function media(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        if (!DB::getSchemaBuilder()->hasTable('gymies_trainer_media')) {
            return response()->json(['data' => []]);
        }

        $rows = DB::table('gymies_trainer_media')
            ->where('trainer_user_id', $user->id)
            ->orderBy('sort_order')
            ->orderByDesc('id')
            ->get();

        $data = $rows->map(fn ($r) => $this->mediaRowToArray($r))->all();
        return response()->json(['data' => $data]);
    }

    /**
     * Upload foto of video via multipart (drag & drop of file picker).
     * Max 1 bestand per upload. Limiet: 4K-kwaliteit – foto max 50MB, video max 100MB.
     */
    public function uploadMedia(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        if (!DB::getSchemaBuilder()->hasTable('gymies_trainer_media')) {
            return response()->json(['message' => 'Media tabel ontbreekt op deze omgeving.'], 422);
        }

        $file = $request->file('file');
        if (!$file || !$file->isValid()) {
            return response()->json(['message' => 'Geen geldig bestand ontvangen. Sleep een bestand of kies via upload.'], 422);
        }

        $ext = strtolower($file->getClientOriginalExtension() ?: $file->guessExtension() ?: 'bin');
        $allowedImages = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
        $allowedVideo = ['mp4', 'webm'];
        if (in_array($ext, $allowedVideo)) {
            $mediaType = 'video';
            $maxMb = 100; // 4K video
        } elseif (in_array($ext, $allowedImages)) {
            $mediaType = 'image';
            $maxMb = 50; // 4K foto
        } else {
            return response()->json(['message' => 'Alleen afbeeldingen (jpg, png, gif, webp) of video (mp4, webm) toegestaan.'], 422);
        }
        if ($file->getSize() > $maxMb * 1024 * 1024) {
            return response()->json(['message' => "Bestand te groot. Max {$maxMb} MB voor " . ($mediaType === 'video' ? 'video' : 'foto') . '.'], 422);
        }

        $dir = public_path('gymies-media');
        if (!is_dir($dir)) {
            @mkdir($dir, 0775, true);
        }
        $name = Str::uuid()->toString() . '.' . $ext;
        $absolute = $dir . DIRECTORY_SEPARATOR . $name;
        if (!$file->move($dir, $name)) {
            return response()->json(['message' => 'Opslaan mislukt.'], 500);
        }
        $filePath = '/gymies-media/' . $name;

        $caption = trim((string) $request->input('caption', ''));
        $isPublic = $request->boolean('is_public', true);
        $sortOrder = (int) $request->input('sort_order', 0);

        $id = DB::table('gymies_trainer_media')->insertGetId([
            'trainer_user_id' => (int) $user->id,
            'media_type' => $mediaType,
            'source_type' => 'upload',
            'file_path' => $filePath,
            'external_url' => null,
            'thumbnail_url' => null,
            'caption' => $caption !== '' ? $caption : null,
            'is_public' => $isPublic ? 1 : 0,
            'sort_order' => $sortOrder,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $row = DB::table('gymies_trainer_media')->where('id', $id)->first();
        return response()->json(['data' => $this->mediaRowToArray($row)], 201);
    }

    public function storeMedia(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        if (!DB::getSchemaBuilder()->hasTable('gymies_trainer_media')) {
            return response()->json(['message' => 'Media tabel ontbreekt op deze omgeving.'], 422);
        }

        $request->validate([
            'media_type' => 'required|in:image,video',
            'source_type' => 'nullable|in:upload,external',
            'external_url' => 'nullable|url|max:1000',
            'image_base64' => 'nullable|string',
            'thumbnail_url' => 'nullable|url|max:1000',
            'caption' => 'nullable|string|max:500',
            'is_public' => 'nullable|boolean',
            'sort_order' => 'nullable|integer|min:0|max:10000',
        ]);

        $mediaType = (string) $request->input('media_type');
        $sourceType = (string) $request->input('source_type', 'external');
        $externalUrl = trim((string) $request->input('external_url', ''));
        $imageBase64 = trim((string) $request->input('image_base64', ''));

        if ($sourceType === 'upload' && $mediaType !== 'image') {
            return response()->json(['message' => 'Upload is voor nu alleen beschikbaar voor afbeeldingen.'], 422);
        }
        if ($sourceType === 'upload' && $imageBase64 === '') {
            return response()->json(['message' => 'image_base64 is verplicht voor upload.'], 422);
        }
        if ($sourceType === 'external' && $externalUrl === '') {
            return response()->json(['message' => 'external_url is verplicht voor externe media.'], 422);
        }

        $resolvedUrl = $externalUrl;
        if ($sourceType === 'upload') {
            $saved = $this->saveBase64Image($imageBase64);
            if ($saved === null) {
                return response()->json(['message' => 'Ongeldige afbeelding upload.'], 422);
            }
            $resolvedUrl = $saved;
        }

        $id = DB::table('gymies_trainer_media')->insertGetId([
            'trainer_user_id' => (int) $user->id,
            'media_type' => $mediaType,
            'source_type' => $sourceType,
            'file_path' => $sourceType === 'upload' ? $resolvedUrl : null,
            'external_url' => $sourceType === 'external' ? $resolvedUrl : null,
            'thumbnail_url' => $request->input('thumbnail_url'),
            'caption' => $request->input('caption'),
            'is_public' => $request->boolean('is_public', true) ? 1 : 0,
            'sort_order' => (int) $request->input('sort_order', 0),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $row = DB::table('gymies_trainer_media')->where('id', $id)->first();
        return response()->json(['data' => $this->mediaRowToArray($row)], 201);
    }

    public function updateMedia(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $request->validate([
            'caption' => 'nullable|string|max:500',
            'is_public' => 'nullable|boolean',
            'sort_order' => 'nullable|integer|min:0|max:10000',
            'thumbnail_url' => 'nullable|url|max:1000',
        ]);

        $row = DB::table('gymies_trainer_media')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->first();
        if (!$row) {
            return response()->json(['message' => 'Media niet gevonden.'], 404);
        }

        $payload = [];
        foreach (['caption', 'thumbnail_url', 'sort_order'] as $key) {
            if ($request->has($key)) {
                $payload[$key] = $request->input($key);
            }
        }
        if ($request->has('is_public')) {
            $payload['is_public'] = $request->boolean('is_public') ? 1 : 0;
        }
        if (!empty($payload)) {
            $payload['updated_at'] = now();
            DB::table('gymies_trainer_media')->where('id', $id)->update($payload);
        }

        $fresh = DB::table('gymies_trainer_media')->where('id', $id)->first();
        return response()->json(['data' => $this->mediaRowToArray($fresh)]);
    }

    public function deleteMedia(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        DB::table('gymies_trainer_media')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->delete();

        return response()->json(['ok' => true]);
    }

    public function packages(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        if (!DB::getSchemaBuilder()->hasTable('gymies_packages')) {
            return response()->json(['data' => []]);
        }

        $hasLessonType = DB::getSchemaBuilder()->hasColumn('gymies_packages', 'lesson_type');
        $hasWeeksCount = DB::getSchemaBuilder()->hasColumn('gymies_packages', 'weeks_count');

        $select = ['id', 'name', 'sessions_count', 'total_cents', 'valid_days'];
        if ($hasLessonType) {
            $select[] = 'lesson_type';
        }
        if ($hasWeeksCount) {
            $select[] = 'weeks_count';
        }

        $rows = DB::table('gymies_packages')
            ->where('trainer_user_id', $user->id)
            ->orderByDesc('id')
            ->get($select);

        $data = $rows->map(function ($r) use ($hasLessonType, $hasWeeksCount) {
            $weeks = $hasWeeksCount
                ? (int) ($r->weeks_count ?? 1)
                : max((int) ceil(((int) ($r->valid_days ?? 7)) / 7), 1);

            return [
                'id' => (string) $r->id,
                'name' => (string) ($r->name ?? ''),
                'lesson_type' => $hasLessonType ? (string) ($r->lesson_type ?? 'solo') : 'solo',
                'sessions_count' => (int) ($r->sessions_count ?? 1),
                'weeks_count' => $weeks,
                'price_cents' => (int) ($r->total_cents ?? 0),
            ];
        })->all();

        return response()->json(['data' => $data]);
    }

    public function storePackage(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        if (!$this->trainerCanEditPackages((int) $user->id)) {
            return response()->json(['message' => 'Pakketten beheren vereist Pro of Studio. Upgrade via Inkomsten.'], 403);
        }

        if (!DB::getSchemaBuilder()->hasTable('gymies_packages')) {
            return response()->json(['message' => 'Pakkettentabel ontbreekt op deze omgeving.'], 422);
        }

        $request->validate([
            'name' => 'required|string|max:255',
            'lesson_type' => 'required|in:solo,duo,group',
            'sessions_count' => 'required|integer|min:1|max:500',
            'weeks_count' => 'required|integer|min:1|max:104',
            'price_cents' => 'required|integer|min:0|max:100000000',
        ]);

        $hasLessonType = DB::getSchemaBuilder()->hasColumn('gymies_packages', 'lesson_type');
        $hasWeeksCount = DB::getSchemaBuilder()->hasColumn('gymies_packages', 'weeks_count');
        $weeks = (int) $request->input('weeks_count');
        $payload = [
            'trainer_user_id' => (int) $user->id,
            'name' => trim((string) $request->input('name')),
            'sessions_count' => (int) $request->input('sessions_count'),
            'total_cents' => (int) $request->input('price_cents'),
            'valid_days' => $weeks * 7,
            'created_at' => now(),
            'updated_at' => now(),
        ];
        if ($hasLessonType) {
            $payload['lesson_type'] = (string) $request->input('lesson_type');
        }
        if ($hasWeeksCount) {
            $payload['weeks_count'] = $weeks;
        }

        $id = DB::table('gymies_packages')->insertGetId($payload);

        return response()->json([
            'data' => [
                'id' => (string) $id,
                'name' => $payload['name'],
                'lesson_type' => (string) $request->input('lesson_type'),
                'sessions_count' => (int) $request->input('sessions_count'),
                'weeks_count' => $weeks,
                'price_cents' => (int) $request->input('price_cents'),
            ],
        ], 201);
    }

    public function updatePackage(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        if (!$this->trainerCanEditPackages((int) $user->id)) {
            return response()->json(['message' => 'Pakketten beheren vereist Pro of Studio.'], 403);
        }

        $request->validate([
            'name' => 'required|string|max:255',
            'lesson_type' => 'required|in:solo,duo,group',
            'sessions_count' => 'required|integer|min:1|max:500',
            'weeks_count' => 'required|integer|min:1|max:104',
            'price_cents' => 'required|integer|min:0|max:100000000',
        ]);

        $existing = DB::table('gymies_packages')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->first();
        if (!$existing) {
            return response()->json(['message' => 'Pakket niet gevonden.'], 404);
        }

        $hasLessonType = DB::getSchemaBuilder()->hasColumn('gymies_packages', 'lesson_type');
        $hasWeeksCount = DB::getSchemaBuilder()->hasColumn('gymies_packages', 'weeks_count');
        $weeks = (int) $request->input('weeks_count');
        $payload = [
            'name' => trim((string) $request->input('name')),
            'sessions_count' => (int) $request->input('sessions_count'),
            'total_cents' => (int) $request->input('price_cents'),
            'valid_days' => $weeks * 7,
            'updated_at' => now(),
        ];
        if ($hasLessonType) {
            $payload['lesson_type'] = (string) $request->input('lesson_type');
        }
        if ($hasWeeksCount) {
            $payload['weeks_count'] = $weeks;
        }

        DB::table('gymies_packages')->where('id', $id)->update($payload);

        return response()->json([
            'data' => [
                'id' => (string) $id,
                'name' => $payload['name'],
                'lesson_type' => (string) $request->input('lesson_type'),
                'sessions_count' => (int) $request->input('sessions_count'),
                'weeks_count' => $weeks,
                'price_cents' => (int) $request->input('price_cents'),
            ],
        ]);
    }

    public function deletePackage(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        if (!$this->trainerCanEditPackages((int) $user->id)) {
            return response()->json(['message' => 'Pakketten beheren vereist Pro of Studio.'], 403);
        }

        DB::table('gymies_packages')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->delete();

        return response()->json(['ok' => true]);
    }

    private const PROGRESS_TYPES = ['foto', 'gewicht', 'vetpercentage', 'pr_oefening'];

    /**
     * Transformation Log: lijst progressie voor één klant (alleen als er boeking met trainer is).
     */
    public function clientProgressIndex(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0) {
            return response()->json(['message' => 'Ongeldige klant.'], 422);
        }
        $hasRelation = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->exists();
        if (!$hasRelation) {
            return response()->json(['message' => 'Geen relatie met deze klant.'], 403);
        }
        if (!Schema::hasTable('gymies_client_progress')) {
            return response()->json([
                'data' => [],
                'charts_available' => false,
                'upgrade_hint' => 'Upgrade naar Elite om grafieken uit progressiedata te genereren.',
            ]);
        }
        $rows = DB::table('gymies_client_progress')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->orderByDesc('created_at')
            ->limit(200)
            ->get();
        $plan = GymiesPlanManager::trainerPlanSlug($trainerId);
        $chartsAvailable = $plan === 'studio'; // elite valt onder studio in slug

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'type' => (string) $r->type,
            'value' => (string) $r->value,
            'note' => $r->note !== null ? (string) $r->note : null,
            'is_private' => (int) ($r->is_private ?? 0) === 1,
            'created_at' => $r->created_at,
        ])->all();

        return response()->json([
            'data' => $data,
            'charts_available' => $chartsAvailable,
            'upgrade_hint' => $chartsAvailable
                ? null
                : 'Wil je grafieken genereren van deze data voor je klant? Upgrade naar Elite.',
        ]);
    }

    /**
     * Transformation Log: nieuwe meting toevoegen.
     */
    public function clientProgressStore(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0) {
            return response()->json(['message' => 'Ongeldige klant.'], 422);
        }
        $hasRelation = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->exists();
        if (!$hasRelation) {
            return response()->json(['message' => 'Geen relatie met deze klant.'], 403);
        }
        if (!Schema::hasTable('gymies_client_progress')) {
            GymiesSchemaEnsure::clientProgressTable();
        }
        if (!Schema::hasTable('gymies_client_progress')) {
            return response()->json(['message' => 'Progressie-tabel ontbreekt. Voer alter_gymies_client_progress.sql uit.'], 503);
        }
        $request->validate([
            'type' => 'required|string|in:' . implode(',', self::PROGRESS_TYPES),
            'value' => 'required|string|max:2000',
            'note' => 'nullable|string|max:500',
            'is_private' => 'nullable|boolean',
        ]);
        $type = (string) $request->input('type');
        $value = trim((string) $request->input('value'));
        $note = trim((string) ($request->input('note') ?? ''));
        $isPrivate = $request->boolean('is_private', false);
        // is_private als Elite-feature: alleen studio/elite mag opslaan met private
        $plan = GymiesPlanManager::trainerPlanSlug($trainerId);
        if ($isPrivate && $plan !== 'studio') {
            $isPrivate = false;
        }

        $id = DB::table('gymies_client_progress')->insertGetId([
            'client_user_id' => $clientId,
            'trainer_user_id' => $trainerId,
            'type' => $type,
            'value' => $value,
            'note' => $note !== '' ? $note : null,
            'is_private' => $isPrivate ? 1 : 0,
            'created_at' => now(),
        ]);

        return response()->json([
            'data' => [
                'id' => (string) $id,
                'type' => $type,
                'value' => $value,
                'note' => $note !== '' ? $note : null,
                'is_private' => $isPrivate,
            ],
        ], 201);
    }

    /**
     * Klantenbestand: alle klanten met minstens één boeking bij deze trainer.
     * Zoek op naam/e-mail; filter op datum: session_date (YYYY-MM-DD) = klanten die op die datum hebben getraind.
     */
    public function clientsIndex(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $query = trim((string) $request->query('query', ''));
        $sessionDate = trim((string) $request->query('session_date', ''));

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => []]);
        }

        // N-014 FIXED: LIKE wildcard injection voorkomen
        $safeQuery = '';
        if ($query !== '') {
            $safeQuery = addcslashes($query, '%_\\');
        }
        $clients = DB::table('gymies_bookings as b')
            ->join('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->where('b.trainer_user_id', $trainerId)
            ->when($safeQuery !== '', function ($q) use ($safeQuery): void {
                $q->where(function ($nested) use ($safeQuery): void {
                    $nested->where('c.display_name', 'like', '%' . $safeQuery . '%')
                        ->orWhere('c.email', 'like', '%' . $safeQuery . '%');
                });
            })
            ->when($sessionDate !== '', function ($q) use ($sessionDate, $trainerId): void {
                $q->whereIn('b.client_user_id', function ($sub) use ($sessionDate, $trainerId): void {
                    $sub->select('client_user_id')
                        ->from('gymies_bookings')
                        ->where('trainer_user_id', $trainerId)
                        ->whereNotNull('scheduled_at')
                        ->whereRaw('DATE(scheduled_at) = ?', [$sessionDate]);
                });
            })
            ->groupBy('b.client_user_id', 'c.display_name', 'c.email')
            ->selectRaw('b.client_user_id')
            ->selectRaw('COALESCE(NULLIF(TRIM(c.display_name), ""), c.email, "Klant") as client_name')
            ->selectRaw('c.email as client_email')
            ->selectRaw('COUNT(*) as bookings_count')
            ->selectRaw('COALESCE(SUM(CASE WHEN b.status IN ("confirmed","completed","no_show") THEN COALESCE(b.amount_cents, 0) ELSE 0 END), 0) as gross_cents')
            ->selectRaw('MAX(b.scheduled_at) as last_booking_at')
            ->orderByDesc('last_booking_at')
            ->limit(500)
            ->get();

        return response()->json([
            'data' => $clients->map(fn ($c) => [
                'client_user_id' => (string) $c->client_user_id,
                'client_name' => (string) $c->client_name,
                'client_email' => (string) ($c->client_email ?? ''),
                'bookings_count' => (int) $c->bookings_count,
                'gross_cents' => (int) $c->gross_cents,
                'last_booking_at' => $c->last_booking_at,
            ])->all(),
        ]);
    }

    /**
     * CRM: klanten met resterende strippenkaart-sessies bij deze trainer maar X dagen niet geboekt.
     * Bron: gymies_packages + boekingen met package_id (geen wallet).
     */
    public function sleepingClients(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $daysInactive = min(max((int) $request->query('days_inactive', 14), 1), 365);
        // Minimaal aantal resterende sessies (strippenkaart) om mee te nemen
        $minRemaining = min(max((int) $request->query('min_remaining_sessions', 1), 1), 1000);
        $cutoff = now()->subDays($daysInactive)->toDateTimeString();

        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['data' => []]);
        }
        if (!Schema::hasTable('gymies_packages') || !Schema::hasColumn('gymies_bookings', 'package_id')) {
            return response()->json(['data' => []]);
        }

        $clientIds = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->distinct()
            ->pluck('client_user_id')
            ->filter()
            ->unique()
            ->values()
            ->all();
        if ($clientIds === []) {
            return response()->json(['data' => []]);
        }

        $packages = DB::table('gymies_packages')
            ->where('trainer_user_id', $trainerId)
            ->get(['id', 'sessions_count', 'name']);
        if ($packages->isEmpty()) {
            return response()->json(['data' => []]);
        }

        $out = [];
        foreach ($clientIds as $clientUserId) {
            $remainingTotal = 0;
            foreach ($packages as $pkg) {
                $sessionsCount = (int) ($pkg->sessions_count ?? 0);
                if ($sessionsCount <= 0) {
                    continue;
                }
                $used = (int) DB::table('gymies_bookings')
                    ->where('client_user_id', $clientUserId)
                    ->where('package_id', (int) $pkg->id)
                    ->whereNotIn('status', ['cancelled'])
                    ->count();
                $remainingTotal += max(0, $sessionsCount - $used);
            }
            if ($remainingTotal < $minRemaining) {
                continue;
            }
            $lastBooking = DB::table('gymies_bookings')
                ->where('client_user_id', $clientUserId)
                ->where('trainer_user_id', $trainerId)
                ->whereIn('status', ['confirmed', 'completed', 'no_show'])
                ->orderByDesc('scheduled_at')
                ->value('scheduled_at');
            if ($lastBooking !== null && (string) $lastBooking >= $cutoff) {
                continue;
            }
            $u = DB::table('gymies_users')->where('id', $clientUserId)->first();
            $out[] = [
                'client_user_id' => (string) $clientUserId,
                'display_name' => $u ? (string) ($u->display_name ?? '') : '',
                'email' => $u ? (string) ($u->email ?? '') : '',
                'sessions_remaining_total' => $remainingTotal,
                // Legacy: CRM gebruikte balance_cents — niet meer wallet; 0 = toon sessies
                'balance_cents' => 0,
                'last_booking_at' => $lastBooking,
            ];
        }
        usort($out, static fn ($a, $b) => ($b['sessions_remaining_total'] <=> $a['sessions_remaining_total']));

        return response()->json(['data' => array_slice($out, 0, 100)]);
    }

    /**
     * Pro: Client Health score (0-100) + risico-indicatoren.
     */
    public function proClientHealth(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        if (!$this->trainerCanEditPackages($trainerId)) {
            return response()->json([
                'message' => 'Client Health Score is beschikbaar vanaf Pro.',
            ], 403);
        }
        $items = $this->buildClientHealthItems($trainerId);
        return response()->json(['data' => $items]);
    }

    /**
     * Pro: suggesties voor upsell (bijv. nieuw pakket of verlenging).
     */
    public function proUpsellSuggestions(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        if (!$this->trainerCanEditPackages($trainerId)) {
            return response()->json([
                'message' => 'Upsell Engine is beschikbaar vanaf Pro.',
            ], 403);
        }

        $suggestions = $this->buildUpsellSuggestions($trainerId);
        return response()->json(['data' => $suggestions]);
    }

    /**
     * Pro: stuur upsell-suggestie naar klant als in-app notificatie.
     */
    public function proUpsellSuggestionsSend(Request $request, string $suggestionId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        if (!$this->trainerCanEditPackages($trainerId)) {
            return response()->json([
                'message' => 'Upsell Engine is beschikbaar vanaf Pro.',
            ], 403);
        }
        if (!Schema::hasTable('gymies_trainer_upsell_suggestions')) {
            return response()->json(['message' => 'Upsell suggesties tabel ontbreekt.'], 503);
        }
        if (!ctype_digit($suggestionId)) {
            return response()->json(['message' => 'Ongeldige suggestie.'], 422);
        }
        $id = (int) $suggestionId;
        $target = DB::table('gymies_trainer_upsell_suggestions')
            ->where('id', $id)
            ->where('trainer_user_id', $trainerId)
            ->first();
        if (!$target) {
            return response()->json(['message' => 'Suggestie niet gevonden.'], 404);
        }
        $clientUserId = (int) ($target->client_user_id ?? 0);
        $packageId = (int) ($target->package_id ?? 0);
        if ($clientUserId < 1 || $packageId < 1) {
            return response()->json(['message' => 'Suggestie ongeldig.'], 422);
        }
        $alreadySent = ((string) ($target->status ?? '')) === 'sent' && $target->sent_at !== null;
        if (!$alreadySent) {
            DB::table('gymies_trainer_upsell_suggestions')->where('id', $id)->update([
                'status' => 'sent',
                'sent_at' => now(),
                'updated_at' => now(),
            ]);
        }

        if (Schema::hasTable('gymies_trainer_upsell_suggestion_sends') && !$alreadySent) {
            DB::table('gymies_trainer_upsell_suggestion_sends')->insert([
                'suggestion_id' => (string) $id,
                'trainer_user_id' => $trainerId,
                'client_user_id' => $clientUserId,
                'package_id' => $packageId,
                'reason' => (string) ($target->reason ?? ''),
                'created_at' => now(),
            ]);
        }

        if (Schema::hasTable('gymies_notification_queue') && !$alreadySent) {
            DB::table('gymies_notification_queue')->insert([
                'user_id' => $clientUserId,
                'channel' => 'in_app',
                'event_type' => 'trainer_upsell_suggestion',
                'payload_json' => json_encode([
                    'suggestion_id' => (string) $id,
                    'trainer_user_id' => (string) $trainerId,
                    'package_id' => (string) $packageId,
                    'title' => 'Voorstel van je trainer',
                    'message' => 'Je trainer heeft een passend vervolgpakket voor je klaarstaan.',
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => now(),
                'created_at' => now(),
            ]);
        }

        return response()->json([
            'data' => [
                'suggestion_id' => (string) $id,
                'sent' => !$alreadySent,
                'already_sent' => $alreadySent,
                'sent_at' => now()->toDateTimeString(),
            ],
        ]);
    }

    public function proRebookSuggestions(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        if (!$this->trainerCanEditPackages($trainerId)) {
            return response()->json([
                'message' => 'Rebook suggesties zijn beschikbaar vanaf Pro.',
            ], 403);
        }
        if (!Schema::hasTable('gymies_trainer_rebook_suggestions')) {
            return response()->json(['data' => []]);
        }
        $this->seedRebookSuggestions($trainerId);
        $rows = DB::table('gymies_trainer_rebook_suggestions')
            ->where('trainer_user_id', $trainerId)
            ->whereIn('status', ['pending', 'sent', 'accepted'])
            ->orderByDesc('confidence')
            ->orderByDesc('created_at')
            ->limit(100)
            ->get();
        $clientNameById = DB::table('gymies_users')
            ->whereIn('id', $rows->pluck('client_user_id')->map(fn ($id) => (int) $id)->all())
            ->get(['id', 'display_name', 'email'])
            ->mapWithKeys(fn ($u) => [(int) $u->id => $this->displayNameFromUserRow($u)])
            ->all();
        $data = $rows->map(fn ($r) => [
            'suggestion_id' => (string) $r->id,
            'client_user_id' => (string) $r->client_user_id,
            'client_name' => (string) ($clientNameById[(int) $r->client_user_id] ?? 'Klant'),
            'booking_id' => $r->booking_id !== null ? (string) $r->booking_id : null,
            'next_slot_at' => $r->next_slot_at,
            'reason' => $r->reason,
            'confidence' => $r->confidence !== null ? (float) $r->confidence : null,
            'status' => (string) $r->status,
            'sent_at' => $r->sent_at,
        ])->all();
        return response()->json(['data' => $data]);
    }

    public function proRebookSuggestionsSend(Request $request, string $suggestionId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        if (!$this->trainerCanEditPackages($trainerId)) {
            return response()->json([
                'message' => 'Rebook suggesties zijn beschikbaar vanaf Pro.',
            ], 403);
        }
        if (!Schema::hasTable('gymies_trainer_rebook_suggestions')) {
            return response()->json(['message' => 'Rebook suggesties tabel ontbreekt.'], 503);
        }
        if (!ctype_digit($suggestionId)) {
            return response()->json(['message' => 'Ongeldige suggestie.'], 422);
        }
        $id = (int) $suggestionId;
        $row = DB::table('gymies_trainer_rebook_suggestions')
            ->where('id', $id)
            ->where('trainer_user_id', $trainerId)
            ->first();
        if (!$row) {
            return response()->json(['message' => 'Suggestie niet gevonden.'], 404);
        }
        $alreadySent = ((string) ($row->status ?? '')) === 'sent' && $row->sent_at !== null;
        if (!$alreadySent) {
            DB::table('gymies_trainer_rebook_suggestions')->where('id', $id)->update([
                'status' => 'sent',
                'sent_at' => now(),
                'updated_at' => now(),
            ]);
            if (Schema::hasTable('gymies_notification_queue')) {
                DB::table('gymies_notification_queue')->insert([
                    'user_id' => (int) $row->client_user_id,
                    'channel' => 'in_app',
                    'event_type' => 'trainer_rebook_suggestion',
                    'payload_json' => json_encode([
                        'suggestion_id' => (string) $id,
                        'trainer_user_id' => (string) $trainerId,
                        'booking_id' => $row->booking_id !== null ? (string) $row->booking_id : null,
                        'next_slot_at' => $row->next_slot_at,
                        'title' => 'Nieuwe rebook suggestie',
                        'message' => 'Je trainer stelt voor om je volgende sessie in te plannen.',
                    ], JSON_UNESCAPED_UNICODE),
                    'scheduled_for' => now(),
                    'created_at' => now(),
                ]);
            }
        }
        return response()->json([
            'data' => [
                'suggestion_id' => (string) $id,
                'sent' => !$alreadySent,
                'already_sent' => $alreadySent,
                'sent_at' => now()->toDateTimeString(),
            ],
        ]);
    }

    /**
     * CRM dossier: GET internal_notes, medical_background, goals_long_term voor client van deze trainer.
     */
    public function clientDossierGet(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $planCheck = GymiesPlanManager::assertPro((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json(['message' => $planCheck['message'], 'upgrade_hint' => $planCheck['upgrade_hint'], 'code' => 'plan_crm_locked'], 403);
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0) {
            return response()->json(['message' => 'Ongeldige klant'], 422);
        }
        if (!$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_dossier')) {
            GymiesSchemaEnsure::clientDossierTableAndShareColumns();
        }
        if (!Schema::hasTable('gymies_client_dossier')) {
            return response()->json([
                'data' => [
                    'internal_notes' => null,
                    'medical_background' => null,
                    'goals_long_term' => null,
                    'client_facing_summary' => null,
                    'shared_with_client' => false,
                    'shared_with_client_at' => null,
                    'updated_at' => null,
                ],
            ]);
        }
        $row = DB::table('gymies_client_dossier')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->first();
        if ($row === null) {
            return response()->json([
                'data' => [
                    'internal_notes' => null,
                    'medical_background' => null,
                    'goals_long_term' => null,
                    'client_facing_summary' => null,
                    'shared_with_client' => false,
                    'shared_with_client_at' => null,
                    'updated_at' => null,
                ],
            ]);
        }

        $sharedAt = property_exists($row, 'shared_with_client_at') ? $row->shared_with_client_at : null;

        return response()->json([
            'data' => [
                'internal_notes' => $row->internal_notes ?? null,
                'medical_background' => $row->medical_background ?? null,
                'goals_long_term' => $row->goals_long_term ?? null,
                'client_facing_summary' => property_exists($row, 'client_facing_summary') ? ($row->client_facing_summary ?? null) : null,
                'shared_with_client' => $sharedAt !== null && trim((string) $sharedAt) !== '' && !str_starts_with((string) $sharedAt, '0000-00-00'),
                'shared_with_client_at' => $sharedAt,
                'updated_at' => $row->updated_at ?? null,
            ],
        ]);
    }

    /**
     * CRM dossier: PUT — upsert notities (max lengte beperkt tegen abuse).
     */
    public function clientDossierPut(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $planCheck = GymiesPlanManager::assertPro((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json(['message' => $planCheck['message'], 'upgrade_hint' => $planCheck['upgrade_hint'], 'code' => 'plan_crm_locked'], 403);
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0) {
            return response()->json(['message' => 'Ongeldige klant'], 422);
        }
        if (!$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_dossier')) {
            GymiesSchemaEnsure::clientDossierTableAndShareColumns();
        }
        if (!Schema::hasTable('gymies_client_dossier')) {
            return response()->json(['message' => 'Dossier nog niet beschikbaar — migratie uitvoeren alter_gymies_client_dossier.sql'], 503);
        }

        $request->validate([
            'internal_notes' => 'nullable|string|max:65535',
            'medical_background' => 'nullable|string|max:65535',
            'goals_long_term' => 'nullable|string|max:65535',
            'client_facing_summary' => 'nullable|string|max:65535',
            'shared_with_client' => 'nullable|boolean',
        ]);

        $now = now();
        $existing = DB::table('gymies_client_dossier')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->first();
        $payload = [
            'trainer_user_id' => $trainerId,
            'client_user_id' => $clientId,
            'internal_notes' => $request->has('internal_notes') ? $request->input('internal_notes') : ($existing?->internal_notes ?? null),
            'medical_background' => $request->has('medical_background') ? $request->input('medical_background') : ($existing?->medical_background ?? null),
            'goals_long_term' => $request->has('goals_long_term') ? $request->input('goals_long_term') : ($existing?->goals_long_term ?? null),
            'updated_at' => $now,
        ];
        if (Schema::hasColumn('gymies_client_dossier', 'client_facing_summary') && $request->has('client_facing_summary')) {
            $payload['client_facing_summary'] = $request->input('client_facing_summary');
        }
        if (Schema::hasColumn('gymies_client_dossier', 'shared_with_client_at')) {
            if ($request->has('shared_with_client')) {
                $payload['shared_with_client_at'] = $request->boolean('shared_with_client') ? $now : null;
            }
        }
        DB::table('gymies_client_dossier')->updateOrInsert(
            ['trainer_user_id' => $trainerId, 'client_user_id' => $clientId],
            $payload
        );

        return response()->json(['data' => ['ok' => true]]);
    }

    /**
     * Session Entry timeline per klant (first-class resource).
     */
    public function sessionEntriesIndex(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_session_entries')) {
            return response()->json([
                'data' => [
                    'session_entries' => [],
                    'pagination' => ['page' => 1, 'per_page' => 20, 'has_more' => false],
                ],
            ]);
        }

        $page = max((int) $request->query('page', 1), 1);
        $perPage = min(max((int) $request->query('per_page', 20), 1), 100);
        $offset = ($page - 1) * $perPage;

        $rows = DB::table('gymies_client_session_entries')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->orderByDesc('session_at')
            ->orderByDesc('id')
            ->offset($offset)
            ->limit($perPage + 1)
            ->get();

        $hasMore = $rows->count() > $perPage;
        $rows = $rows->slice(0, $perPage)->values();

        return response()->json([
            'data' => [
                'session_entries' => $rows->map(fn ($r) => $this->sessionEntryToArray($r))->all(),
                'pagination' => [
                    'page' => $page,
                    'per_page' => $perPage,
                    'has_more' => $hasMore,
                ],
            ],
        ]);
    }

    public function sessionEntriesStore(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_session_entries')) {
            return response()->json(['message' => 'Session entries tabel ontbreekt. Voer migratie uit.'], 503);
        }

        $request->validate([
            'booking_id' => 'nullable|integer|min:1',
            'session_at' => 'required|date',
            'session_type' => 'required|string|max:64',
            'attendance_status' => 'required|in:attended,no_show,cancelled,unknown',
            'focus' => 'nullable|string|max:5000',
            'positive_notes' => 'nullable|string|max:5000',
            'improve_notes' => 'nullable|string|max:5000',
            'homework' => 'nullable|string|max:5000',
            'energy_score' => 'nullable|integer|min:1|max:5',
            'performance_score' => 'nullable|numeric|min:0|max:1000000',
            'visibility' => 'nullable|in:shared,internal',
        ]);

        $bookingId = $request->input('booking_id') !== null ? (int) $request->input('booking_id') : null;
        if ($bookingId !== null) {
            $booking = DB::table('gymies_bookings')
                ->where('id', $bookingId)
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->first();
            if (!$booking) {
                return response()->json(['message' => 'Boeking hoort niet bij trainer/klant.'], 422);
            }
        }

        $id = DB::table('gymies_client_session_entries')->insertGetId([
            'trainer_user_id' => $trainerId,
            'client_user_id' => $clientId,
            'booking_id' => $bookingId,
            'session_at' => (string) $request->input('session_at'),
            'session_type' => trim((string) $request->input('session_type')),
            'attendance_status' => (string) $request->input('attendance_status'),
            'focus' => $request->input('focus'),
            'positive_notes' => $request->input('positive_notes'),
            'improve_notes' => $request->input('improve_notes'),
            'homework' => $request->input('homework'),
            'energy_score' => $request->input('energy_score'),
            'performance_score' => $request->input('performance_score'),
            'visibility' => (string) $request->input('visibility', 'internal'),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $row = DB::table('gymies_client_session_entries')->where('id', $id)->first();
        return response()->json(['data' => $this->sessionEntryToArray($row)], 201);
    }

    public function sessionEntriesPatch(Request $request, string $clientUserId, string $entryId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if (!Schema::hasTable('gymies_client_session_entries')) {
            return response()->json(['message' => 'Session entries tabel ontbreekt.'], 503);
        }
        $entry = DB::table('gymies_client_session_entries')
            ->where('id', (int) $entryId)
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->first();
        if (!$entry) {
            return response()->json(['message' => 'Session entry niet gevonden.'], 404);
        }

        $request->validate([
            'session_at' => 'sometimes|date',
            'session_type' => 'sometimes|string|max:64',
            'attendance_status' => 'sometimes|in:attended,no_show,cancelled,unknown',
            'focus' => 'sometimes|nullable|string|max:5000',
            'positive_notes' => 'sometimes|nullable|string|max:5000',
            'improve_notes' => 'sometimes|nullable|string|max:5000',
            'homework' => 'sometimes|nullable|string|max:5000',
            'energy_score' => 'sometimes|nullable|integer|min:1|max:5',
            'performance_score' => 'sometimes|nullable|numeric|min:0|max:1000000',
            'visibility' => 'sometimes|in:shared,internal',
        ]);

        $payload = ['updated_at' => now()];
        foreach ([
            'session_at',
            'session_type',
            'attendance_status',
            'focus',
            'positive_notes',
            'improve_notes',
            'homework',
            'energy_score',
            'performance_score',
            'visibility',
        ] as $key) {
            if ($request->has($key)) {
                $payload[$key] = $request->input($key);
            }
        }

        $oldVisibility = (string) ($entry->visibility ?? 'internal');
        DB::table('gymies_client_session_entries')->where('id', (int) $entryId)->update($payload);
        $fresh = DB::table('gymies_client_session_entries')->where('id', (int) $entryId)->first();
        $newVisibility = (string) ($fresh->visibility ?? 'internal');
        if ($oldVisibility !== $newVisibility) {
            $this->logAudit(
                $trainerId,
                'session_entry_visibility_changed',
                'session_entry',
                (int) $entryId,
                ['visibility' => $oldVisibility],
                ['visibility' => $newVisibility]
            );
        }

        return response()->json(['data' => $this->sessionEntryToArray($fresh)]);
    }

    public function sessionEntriesDelete(Request $request, string $clientUserId, string $entryId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if (!Schema::hasTable('gymies_client_session_entries')) {
            return response()->json(['message' => 'Session entries tabel ontbreekt.'], 503);
        }

        $affected = DB::table('gymies_client_session_entries')
            ->where('id', (int) $entryId)
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->update([
                'deleted_at' => now(),
                'updated_at' => now(),
            ]);
        if ($affected === 0) {
            return response()->json(['message' => 'Session entry niet gevonden.'], 404);
        }
        return response()->json(['data' => ['deleted' => true]]);
    }

    public function clientGoalsIndex(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_goals')) {
            return response()->json(['data' => ['goals' => []]]);
        }

        $goals = DB::table('gymies_client_goals')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->orderByDesc('created_at')
            ->get();

        $goalIds = $goals->pluck('id')->map(fn ($id) => (int) $id)->all();
        $pointsByGoal = [];
        if (!empty($goalIds) && Schema::hasTable('gymies_client_goal_progress_points')) {
            $pointsByGoal = DB::table('gymies_client_goal_progress_points')
                ->whereIn('goal_id', $goalIds)
                ->orderBy('measured_at')
                ->orderBy('id')
                ->get()
                ->groupBy('goal_id')
                ->map(fn ($items) => $items->map(fn ($p) => [
                    'id' => (string) $p->id,
                    'goal_id' => (string) $p->goal_id,
                    'value_numeric' => $p->value_numeric !== null ? (float) $p->value_numeric : null,
                    'note' => $p->note,
                    'measured_at' => $p->measured_at,
                    'created_at' => $p->created_at,
                    'updated_at' => $p->updated_at,
                ])->all())
                ->all();
        }

        return response()->json([
            'data' => [
                'goals' => $goals->map(fn ($g) => [
                    'id' => (string) $g->id,
                    'trainer_user_id' => (string) $g->trainer_user_id,
                    'client_user_id' => (string) $g->client_user_id,
                    'title' => $g->title,
                    'target_value' => $g->target_value !== null ? (float) $g->target_value : null,
                    'current_value' => $g->current_value !== null ? (float) $g->current_value : null,
                    'unit' => $g->unit,
                    'status' => $g->status,
                    'due_date' => $g->due_date,
                    'created_at' => $g->created_at,
                    'updated_at' => $g->updated_at,
                    'progress_points' => $pointsByGoal[(int) $g->id] ?? [],
                ])->all(),
            ],
        ]);
    }

    public function clientGoalsStore(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }
        if (!Schema::hasTable('gymies_client_goals')) {
            return response()->json(['message' => 'Goals tabel ontbreekt. Voer migratie uit.'], 503);
        }
        $request->validate([
            'title' => 'required|string|max:255',
            'target_value' => 'nullable|numeric',
            'current_value' => 'nullable|numeric',
            'unit' => 'nullable|string|max:40',
            'status' => 'nullable|in:active,done,paused,cancelled',
            'due_date' => 'nullable|date',
        ]);

        $id = DB::table('gymies_client_goals')->insertGetId([
            'trainer_user_id' => $trainerId,
            'client_user_id' => $clientId,
            'title' => trim((string) $request->input('title')),
            'target_value' => $request->input('target_value'),
            'current_value' => $request->input('current_value'),
            'unit' => $request->input('unit'),
            'status' => (string) $request->input('status', 'active'),
            'due_date' => $request->input('due_date'),
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $goal = DB::table('gymies_client_goals')->where('id', $id)->first();

        return response()->json([
            'data' => [
                'id' => (string) $goal->id,
                'trainer_user_id' => (string) $goal->trainer_user_id,
                'client_user_id' => (string) $goal->client_user_id,
                'title' => $goal->title,
                'target_value' => $goal->target_value !== null ? (float) $goal->target_value : null,
                'current_value' => $goal->current_value !== null ? (float) $goal->current_value : null,
                'unit' => $goal->unit,
                'status' => $goal->status,
                'due_date' => $goal->due_date,
                'created_at' => $goal->created_at,
                'updated_at' => $goal->updated_at,
                'progress_points' => [],
            ],
        ], 201);
    }

    public function clientGoalsPatch(Request $request, string $clientUserId, string $goalId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if (!Schema::hasTable('gymies_client_goals')) {
            return response()->json(['message' => 'Goals tabel ontbreekt.'], 503);
        }
        $goal = DB::table('gymies_client_goals')
            ->where('id', (int) $goalId)
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->first();
        if (!$goal) {
            return response()->json(['message' => 'Goal niet gevonden.'], 404);
        }
        $request->validate([
            'title' => 'sometimes|string|max:255',
            'target_value' => 'sometimes|nullable|numeric',
            'current_value' => 'sometimes|nullable|numeric',
            'unit' => 'sometimes|nullable|string|max:40',
            'status' => 'sometimes|in:active,done,paused,cancelled',
            'due_date' => 'sometimes|nullable|date',
        ]);

        $payload = ['updated_at' => now()];
        foreach (['title', 'target_value', 'current_value', 'unit', 'status', 'due_date'] as $key) {
            if ($request->has($key)) {
                $payload[$key] = $request->input($key);
            }
        }
        DB::table('gymies_client_goals')->where('id', (int) $goalId)->update($payload);
        $fresh = DB::table('gymies_client_goals')->where('id', (int) $goalId)->first();
        return response()->json([
            'data' => [
                'id' => (string) $fresh->id,
                'trainer_user_id' => (string) $fresh->trainer_user_id,
                'client_user_id' => (string) $fresh->client_user_id,
                'title' => $fresh->title,
                'target_value' => $fresh->target_value !== null ? (float) $fresh->target_value : null,
                'current_value' => $fresh->current_value !== null ? (float) $fresh->current_value : null,
                'unit' => $fresh->unit,
                'status' => $fresh->status,
                'due_date' => $fresh->due_date,
                'created_at' => $fresh->created_at,
                'updated_at' => $fresh->updated_at,
            ],
        ]);
    }

    public function clientGoalsProgressPointStore(Request $request, string $clientUserId, string $goalId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if (!Schema::hasTable('gymies_client_goals') || !Schema::hasTable('gymies_client_goal_progress_points')) {
            return response()->json(['message' => 'Goal-progress tabel ontbreekt. Voer migratie uit.'], 503);
        }
        $goal = DB::table('gymies_client_goals')
            ->where('id', (int) $goalId)
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->whereNull('deleted_at')
            ->first();
        if (!$goal) {
            return response()->json(['message' => 'Goal niet gevonden.'], 404);
        }
        $request->validate([
            'value_numeric' => 'nullable|numeric',
            'note' => 'nullable|string|max:1000',
            'measured_at' => 'nullable|date',
        ]);

        $id = DB::table('gymies_client_goal_progress_points')->insertGetId([
            'goal_id' => (int) $goalId,
            'value_numeric' => $request->input('value_numeric'),
            'note' => $request->input('note'),
            'measured_at' => $request->input('measured_at') ?? now(),
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        if ($request->input('value_numeric') !== null) {
            DB::table('gymies_client_goals')->where('id', (int) $goalId)->update([
                'current_value' => $request->input('value_numeric'),
                'updated_at' => now(),
            ]);
        }
        $point = DB::table('gymies_client_goal_progress_points')->where('id', $id)->first();

        return response()->json([
            'data' => [
                'id' => (string) $point->id,
                'goal_id' => (string) $point->goal_id,
                'value_numeric' => $point->value_numeric !== null ? (float) $point->value_numeric : null,
                'note' => $point->note,
                'measured_at' => $point->measured_at,
                'created_at' => $point->created_at,
                'updated_at' => $point->updated_at,
            ],
        ], 201);
    }

    public function clientDossierSummary(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen relatie met deze klant'], 403);
        }

        $attendanceRate = 0.0;
        $streakDays = 0;
        $riskFlags = [];
        $nextBestAction = 'log_next_session_entry';

        if (Schema::hasTable('gymies_client_session_entries')) {
            $entries = DB::table('gymies_client_session_entries')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->whereNull('deleted_at')
                ->orderByDesc('session_at')
                ->get(['session_at', 'attendance_status']);

            $totalAttendanceTracked = $entries
                ->whereIn('attendance_status', ['attended', 'no_show', 'cancelled', 'unknown'])
                ->count();
            $attended = $entries->where('attendance_status', 'attended')->count();
            $attendanceRate = $totalAttendanceTracked > 0 ? round(($attended / $totalAttendanceTracked) * 100, 1) : 0.0;

            $attendedDates = $entries
                ->where('attendance_status', 'attended')
                ->map(fn ($e) => substr((string) $e->session_at, 0, 10))
                ->filter()
                ->unique()
                ->values()
                ->all();
            if (!empty($attendedDates)) {
                $streakDays = $this->calculateDateStreakDays($attendedDates);
            }

            $latestAt = $entries->first()->session_at ?? null;
            if ($latestAt !== null && \Carbon\Carbon::parse((string) $latestAt)->diffInDays(now()) > 14) {
                $riskFlags[] = 'no_recent_session_entry';
            }
            if ($totalAttendanceTracked >= 3 && $attendanceRate < 60.0) {
                $riskFlags[] = 'low_attendance_rate';
            }
        }

        $goalsTotal = 0;
        $goalsDone = 0;
        if (Schema::hasTable('gymies_client_goals')) {
            $goals = DB::table('gymies_client_goals')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->whereNull('deleted_at')
                ->get(['status']);
            $goalsTotal = $goals->count();
            $goalsDone = $goals->where('status', 'done')->count();
            if ($goalsTotal === 0) {
                $riskFlags[] = 'no_active_goals';
            }
        }

        if (in_array('low_attendance_rate', $riskFlags, true)) {
            $nextBestAction = 'schedule_reengagement_message';
        } elseif (in_array('no_active_goals', $riskFlags, true)) {
            $nextBestAction = 'create_first_goal';
        } elseif ($streakDays >= 7) {
            $nextBestAction = 'raise_goal_difficulty';
        }

        return response()->json([
            'data' => [
                'attendance_rate' => $attendanceRate,
                'streak_days' => $streakDays,
                'goals_done' => $goalsDone,
                'goals_total' => $goalsTotal,
                'risk_flags' => array_values(array_unique($riskFlags)),
                'next_best_action' => $nextBestAction,
            ],
        ]);
    }

    /**
     * Bulk in-app bericht naar geselecteerde klanten (queue). Alleen klanten met boeking bij deze trainer.
     * Max 25 per request. Payload message wordt in notificatie getoond (trainer_personal_nudge).
     */
    public function bulkMessageClients(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        if (!GymiesSchemaEnsure::notificationQueueTable()) {
            return response()->json(['message' => 'Notificatie-queue niet beschikbaar'], 503);
        }

        $request->validate([
            'client_user_ids' => 'required|array|max:25',
            'client_user_ids.*' => 'required|string',
            'message' => 'required|string|min:1|max:2000',
        ]);
        $message = trim((string) $request->input('message'));
        if ($message === '') {
            return response()->json(['message' => 'Bericht mag niet leeg zijn'], 422);
        }

        $trainerName = (string) (DB::table('gymies_users')->where('id', $trainerId)->value('display_name') ?? 'Je trainer');
        $now = now();
        $queued = 0;
        foreach ($request->input('client_user_ids') as $cid) {
            $clientId = (int) $cid;
            if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
                continue;
            }
            DB::table('gymies_notification_queue')->insert([
                'user_id' => $clientId,
                'channel' => 'in_app',
                'event_type' => 'trainer_personal_nudge',
                'payload_json' => json_encode([
                    'trainer_user_id' => (string) $trainerId,
                    'trainer_name' => $trainerName,
                    'message' => $message,
                    'action_url' => '/berichten',
                ], JSON_UNESCAPED_UNICODE),
                'scheduled_for' => $now,
                'created_at' => $now,
            ]);
            $queued++;
        }

        return response()->json(['data' => ['queued' => $queued]]);
    }

    /**
     * Stuur aanbieding/promo naar alle klanten die jou als favoriet hebben.
     * POST /trainer/promo-to-favorites { message, discount_code? }
     */
    public function promoToFavorites(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;
        if (!GymiesSchemaEnsure::notificationQueueTable()) {
            return response()->json(['message' => 'Notificatie-queue niet beschikbaar'], 503);
        }
        if (!Schema::hasTable('gymies_favorites')) {
            return response()->json(['message' => 'Favorieten nog niet beschikbaar.'], 503);
        }

        $request->validate([
            'message' => 'required|string|min:1|max:2000',
            'discount_code' => 'nullable|string|max:64',
        ]);
        $message = trim((string) $request->input('message'));
        $discountCode = trim((string) ($request->input('discount_code') ?? ''));
        if ($message === '') {
            return response()->json(['message' => 'Bericht mag niet leeg zijn'], 422);
        }

        $trainerName = (string) (DB::table('gymies_users')->where('id', $trainerId)->value('display_name') ?? 'Je trainer');
        $clientIds = DB::table('gymies_favorites')
            ->where('trainer_user_id', $trainerId)
            ->pluck('client_user_id')
            ->map(fn ($id) => (int) $id)
            ->all();

        $now = now();
        $queued = 0;
        foreach ($clientIds as $clientId) {
            $payload = [
                'trainer_user_id' => (string) $trainerId,
                'trainer_name' => $trainerName,
                'message' => $message,
                'action_url' => "/boeken?trainerId={$trainerId}",
            ];
            if ($discountCode !== '') {
                $payload['discount_code'] = $discountCode;
            }
            DB::table('gymies_notification_queue')->insert([
                'user_id' => $clientId,
                'channel' => 'in_app',
                'event_type' => 'trainer_promo_to_favorites',
                'payload_json' => json_encode($payload, JSON_UNESCAPED_UNICODE),
                'scheduled_for' => $now,
                'created_at' => $now,
            ]);
            $queued++;
        }

        return response()->json(['data' => ['queued' => $queued, 'message' => "Aanbieding verstuurd naar {$queued} favorieten."]]);
    }

    /**
     * Sessienotitie na afloop: upsert op booking_id (één note per boeking).
     */
    public function sessionNotePut(Request $request, string $bookingId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        // T-plan: sessienotities vereisen Pro
        $planCheck = GymiesPlanManager::assertPro((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json(['message' => $planCheck['message'], 'upgrade_hint' => $planCheck['upgrade_hint'], 'code' => 'plan_session_notes_locked'], 403);
        }
        $trainerId = (int) $user->id;
        $bid = (int) $bookingId;
        if ($bid <= 0 || !Schema::hasTable('gymies_client_session_notes')) {
            return response()->json(['message' => 'Niet beschikbaar'], 503);
        }
        $booking = DB::table('gymies_bookings')->where('id', $bid)->first();
        if ($booking === null || (int) $booking->trainer_user_id !== $trainerId) {
            return response()->json(['message' => 'Boeking niet gevonden'], 404);
        }
        $request->validate([
            'note' => 'required|string|min:1|max:16000',
        ]);
        $note = trim((string) $request->input('note'));
        $now = now();
        DB::table('gymies_client_session_notes')->updateOrInsert(
            ['booking_id' => $bid],
            [
                'booking_id' => $bid,
                'trainer_user_id' => $trainerId,
                'note' => $note,
                'created_at' => $now,
            ]
        );

        return response()->json(['data' => ['ok' => true]]);
    }

    /**
     * Lijst sessienotities voor klant (laatste eerst), alleen boekingen van deze trainer.
     */
    public function clientSessionNotesIndex(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        // T-plan: sessienotities vereisen Pro
        $planCheck = GymiesPlanManager::assertPro((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json(['message' => $planCheck['message'], 'upgrade_hint' => $planCheck['upgrade_hint'], 'code' => 'plan_session_notes_locked'], 403);
        }
        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;
        if ($clientId <= 0 || !$this->trainerHasClientRelation($trainerId, $clientId)) {
            return response()->json(['message' => 'Geen toegang'], 403);
        }
        if (!Schema::hasTable('gymies_client_session_notes')) {
            return response()->json(['data' => []]);
        }
        $bookingIds = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->pluck('id')
            ->all();
        if ($bookingIds === []) {
            return response()->json(['data' => []]);
        }
        $rows = DB::table('gymies_client_session_notes as n')
            ->join('gymies_bookings as b', 'b.id', '=', 'n.booking_id')
            ->whereIn('n.booking_id', $bookingIds)
            ->orderByDesc('b.scheduled_at')
            ->limit(100)
            ->get(['n.booking_id', 'n.note', 'n.created_at', 'b.scheduled_at']);

        $out = [];
        foreach ($rows as $r) {
            $out[] = [
                'booking_id' => (string) $r->booking_id,
                'scheduled_at' => $r->scheduled_at ?? null,
                'note' => $r->note ?? '',
                'created_at' => $r->created_at ?? null,
            ];
        }

        return response()->json(['data' => $out]);
    }

    private function trainerHasClientRelation(int $trainerId, int $clientId): bool
    {
        if (!Schema::hasTable('gymies_bookings')) {
            return false;
        }

        return DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->exists();
    }

    /**
     * Fee Switcher alleen (geen volledige bankpayload nodig).
     */
    public function updateFeePreference(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        if (!Schema::hasTable('gymies_trainer_bank_accounts')
            || !Schema::hasColumn('gymies_trainer_bank_accounts', 'client_pays_service_fee')) {
            return response()->json(['message' => 'Niet beschikbaar op deze omgeving. Voer de SQL-migratie uit.'], 422);
        }
        $request->validate(['client_pays_service_fee' => 'required|boolean']);
        $trainerId = (int) $user->id;
        $exists = DB::table('gymies_trainer_bank_accounts')->where('trainer_user_id', $trainerId)->exists();
        if (!$exists) {
            return response()->json([
                'message' => 'Stel eerst je uitbetalingsgegevens in (IBAN e.d.); daarna kun je de fee-optie wisselen.',
            ], 422);
        }
        DB::table('gymies_trainer_bank_accounts')
            ->where('trainer_user_id', $trainerId)
            ->update([
                'client_pays_service_fee' => $request->boolean('client_pays_service_fee') ? 1 : 0,
                'updated_at' => now(),
            ]);

        return response()->json(['data' => $this->readPayoutSettings($trainerId)]);
    }

    public function payoutSettings(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        return response()->json([
            'data' => $this->readPayoutSettings((int) $user->id),
        ]);
    }

    public function updatePayoutSettings(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $request->validate([
            'account_holder_first_name' => 'required|string|max:120',
            'account_holder_last_name' => 'required|string|max:120',
            'iban' => 'nullable|string|min:8|max:34',
            'payout_frequency' => 'required|in:weekly,biweekly,monthly',
            'minimum_payout_cents' => 'nullable|integer|min:0|max:100000000',
            'notify_payout_paid' => 'nullable|boolean',
            'notify_payout_failed' => 'nullable|boolean',
            // Fee Switcher: true = klant betaalt toeslag bovenop tarief; false = trainer neemt in marge.
            'client_pays_service_fee' => 'nullable|boolean',
        ]);

        if (!DB::getSchemaBuilder()->hasTable('gymies_trainer_bank_accounts')) {
            return response()->json(['message' => 'Bankrekening tabel ontbreekt op deze omgeving.'], 422);
        }

        $trainerId = (int) $user->id;
        $existing = DB::table('gymies_trainer_bank_accounts')
            ->where('trainer_user_id', $trainerId)
            ->first();

        $firstName = trim((string) $request->input('account_holder_first_name'));
        $lastName = trim((string) $request->input('account_holder_last_name'));
        $holderName = trim($firstName . ' ' . $lastName);
        $ibanRawInput = trim((string) $request->input('iban', ''));
        $ibanRaw = strtoupper(preg_replace('/\s+/', '', $ibanRawInput));
        if ($ibanRaw !== '' && !$this->looksLikeIban($ibanRaw)) {
            return response()->json(['message' => 'Ongeldig IBAN-formaat.'], 422);
        }
        if ($ibanRaw === '' && !$existing) {
            return response()->json(['message' => 'IBAN is verplicht.'], 422);
        }
        $frequency = (string) $request->input('payout_frequency');
        $minimum = (int) $request->input('minimum_payout_cents', 0);
        $now = now();

        $payload = [
            'trainer_user_id' => $trainerId,
            'account_holder_name' => $holderName,
            'account_holder_first_name' => $firstName,
            'account_holder_last_name' => $lastName,
            'iban_masked' => $ibanRaw !== '' ? $this->maskIban($ibanRaw) : ($existing->iban_masked ?? ''),
            'iban_last4' => $ibanRaw !== '' ? substr($ibanRaw, -4) : ($existing->iban_last4 ?? null),
            'payout_frequency' => $frequency,
            'minimum_payout_cents' => $minimum,
            'notify_payout_paid' => $request->boolean('notify_payout_paid', true),
            'notify_payout_failed' => $request->boolean('notify_payout_failed', true),
            'status' => 'pending',
            'updated_at' => $now,
        ];
        if (Schema::hasColumn('gymies_trainer_bank_accounts', 'client_pays_service_fee')) {
            $payload['client_pays_service_fee'] = $request->boolean('client_pays_service_fee', true) ? 1 : 0;
        }

        if ($existing) {
            DB::table('gymies_trainer_bank_accounts')
                ->where('trainer_user_id', $trainerId)
                ->update($payload);
        } else {
            $payload['created_at'] = $now;
            DB::table('gymies_trainer_bank_accounts')->insert($payload);
        }

        return response()->json([
            'data' => $this->readPayoutSettings($trainerId),
        ]);
    }

    public function payoutPreview(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $trainerId = (int) $user->id;
        $settings = $this->readPayoutSettings($trainerId);
        $totals = $this->trainerRevenueTotals($trainerId);
        $preview = $this->buildPayoutPreview($totals['pending_payout_cents'], $settings);

        return response()->json([
            'data' => $preview,
        ]);
    }

    public function payoutCalendar(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $trainerId = (int) $user->id;
        $settings = $this->readPayoutSettings($trainerId);
        $totals = $this->trainerRevenueTotals($trainerId);
        $preview = $this->buildPayoutPreview($totals['pending_payout_cents'], $settings);
        $dates = $this->nextPayoutDates((string) ($settings['payout_frequency'] ?? 'monthly'), 3);

        $data = array_map(fn (string $date) => [
            'date' => $date,
            'is_eligible' => (bool) $preview['is_eligible'],
            'remaining_to_minimum_cents' => (int) $preview['remaining_to_minimum_cents'],
        ], $dates);

        return response()->json(['data' => $data]);
    }

    public function payoutHistory(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        if (!DB::getSchemaBuilder()->hasTable('gymies_payouts')) {
            return response()->json(['data' => []]);
        }

        $rows = DB::table('gymies_payouts')
            ->where('trainer_user_id', $user->id)
            ->orderByDesc('id')
            ->limit(100)
            ->get([
                'id',
                'amount_cents',
                'gross_cents',
                'fee_cents',
                'payout_frequency',
                'status',
                'reference',
                'requested_at',
                'paid_at',
                'created_at',
            ]);

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'amount_cents' => (int) ($r->amount_cents ?? 0),
            'gross_cents' => (int) ($r->gross_cents ?? $r->amount_cents ?? 0),
            'fee_cents' => (int) ($r->fee_cents ?? 0),
            'payout_frequency' => $r->payout_frequency ?: 'monthly',
            'status' => $r->status ?? 'pending',
            'reference' => $r->reference,
            'requested_at' => $r->requested_at ?? $r->created_at,
            'paid_at' => $r->paid_at,
        ])->all();

        return response()->json(['data' => $data]);
    }

    public function requestPayoutNow(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        if (!DB::getSchemaBuilder()->hasTable('gymies_payouts')) {
            return response()->json(['message' => 'Uitbetalingstabel ontbreekt op deze omgeving.'], 422);
        }

        $trainerId = (int) $user->id;
        $settings = $this->readPayoutSettings($trainerId);
        $totals = $this->trainerRevenueTotals($trainerId);
        $preview = $this->buildPayoutPreview($totals['pending_payout_cents'], $settings);

        if (!$preview['is_eligible']) {
            return response()->json(['message' => 'Minimum saldo nog niet gehaald voor uitbetaling.'], 422);
        }
        if ((int) $preview['net_cents'] <= 0) {
            return response()->json(['message' => 'Geen uitbetaalbaar saldo beschikbaar.'], 422);
        }

        $pendingExists = DB::table('gymies_payouts')
            ->where('trainer_user_id', $trainerId)
            ->where('status', 'pending')
            ->exists();
        if ($pendingExists) {
            return response()->json(['message' => 'Er staat al een uitbetalingsverzoek open.'], 422);
        }

        $reference = 'TM-' . strtoupper(substr((string) md5((string) microtime(true) . '-' . $trainerId), 0, 10));
        $now = now();
        $id = DB::table('gymies_payouts')->insertGetId([
            'trainer_user_id' => $trainerId,
            'amount_cents' => (int) $preview['net_cents'],
            'gross_cents' => (int) $preview['gross_cents'],
            'fee_cents' => (int) $preview['fee_cents'],
            'payout_frequency' => (string) ($settings['payout_frequency'] ?? 'monthly'),
            'status' => 'pending',
            'reference' => $reference,
            'requested_at' => $now,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $this->logAudit(
            (int) $user->id,
            'payout_requested',
            'payout',
            (int) $id,
            null,
            ['amount_cents' => (int) $preview['net_cents'], 'reference' => $reference]
        );

        return response()->json([
            'data' => [
                'id' => (string) $id,
                'status' => 'pending',
                'reference' => $reference,
                'amount_cents' => (int) $preview['net_cents'],
            ],
        ], 201);
    }

    public function revenueExport(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $trainerId = (int) $user->id;
        $bookingRows = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereNotNull('amount_cents')
            ->orderByDesc('scheduled_at')
            ->limit(1000)
            ->get(['id', 'scheduled_at', 'status', 'amount_cents', 'paid_at']);

        $payoutRows = DB::getSchemaBuilder()->hasTable('gymies_payouts')
            ? DB::table('gymies_payouts')
                ->where('trainer_user_id', $trainerId)
                ->orderByDesc('id')
                ->limit(1000)
                ->get([
                    'id',
                    'amount_cents',
                    'gross_cents',
                    'fee_cents',
                    'payout_frequency',
                    'status',
                    'reference',
                    'requested_at',
                    'paid_at',
                ])
            : collect();

        $lines = [];
        $lines[] = 'section,id,scheduled_at,status,amount_cents,paid_at,reference,gross_cents,fee_cents,payout_frequency,requested_at';
        foreach ($bookingRows as $b) {
            $lines[] = implode(',', [
                'income',
                $this->csvCell((string) $b->id),
                $this->csvCell((string) ($b->scheduled_at ?? '')),
                $this->csvCell((string) ($b->status ?? '')),
                (string) ((int) ($b->amount_cents ?? 0)),
                $this->csvCell((string) ($b->paid_at ?? '')),
                '',
                '',
                '',
                '',
                '',
            ]);
        }
        foreach ($payoutRows as $p) {
            $lines[] = implode(',', [
                'payout',
                $this->csvCell((string) $p->id),
                '',
                $this->csvCell((string) ($p->status ?? '')),
                (string) ((int) ($p->amount_cents ?? 0)),
                $this->csvCell((string) ($p->paid_at ?? '')),
                $this->csvCell((string) ($p->reference ?? '')),
                (string) ((int) ($p->gross_cents ?? 0)),
                (string) ((int) ($p->fee_cents ?? 0)),
                $this->csvCell((string) ($p->payout_frequency ?? '')),
                $this->csvCell((string) ($p->requested_at ?? '')),
            ]);
        }

        return response()->json([
            'data' => [
                'generated_at' => now()->toIso8601String(),
                'csv' => implode("\n", $lines),
                'income_count' => $bookingRows->count(),
                'payout_count' => $payoutRows->count(),
            ],
        ]);
    }

    public function messages(Request $request, string $conversationId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where(function ($q) use ($user) {
                $q->where('trainer_user_id', $user->id)
                    ->orWhere(function ($q2) use ($user) {
                        $q2->where('client_user_id', $user->id);
                        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
                            $q2->whereNotNull('support_ticket_id');
                        }
                    });
            })
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $rows = DB::table('gymies_messages')
            ->where('conversation_id', $conversationId)
            ->orderBy('created_at')
            ->get(['id', 'conversation_id', 'from_user_id', 'body', 'read_at', 'created_at']);

        $data = $rows->map(fn ($r) => [
            'id' => (string) $r->id,
            'conversation_id' => (string) $r->conversation_id,
            'from_user_id' => (string) $r->from_user_id,
            'body' => $r->body,
            'read_at' => $r->read_at,
            'created_at' => $r->created_at,
        ])->all();

        return response()->json(['data' => $data]);
    }

    public function markConversationRead(Request $request, string $conversationId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where(function ($q) use ($user) {
                $q->where('trainer_user_id', $user->id)
                    ->orWhere(function ($q2) use ($user) {
                        $q2->where('client_user_id', $user->id);
                        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
                            $q2->whereNotNull('support_ticket_id');
                        }
                    });
            })
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $readAt = null;
        if (DB::getSchemaBuilder()->hasColumn('gymies_messages', 'read_at')) {
            $readAt = now()->toIso8601String();
            DB::table('gymies_messages')
                ->where('conversation_id', $conversationId)
                ->where('from_user_id', '!=', $user->id)
                ->whereNull('read_at')
                ->update(['read_at' => now()]);
        }

        if ($readAt !== null && class_exists(\App\Events\Gymies\GymiesChatMessagesRead::class)) {
            $otherUserId = (int) $user->id === (int) $conversation->trainer_user_id
                ? (int) $conversation->client_user_id
                : (int) $conversation->trainer_user_id;
            if ($otherUserId > 0) {
                try {
                    event(new \App\Events\Gymies\GymiesChatMessagesRead($otherUserId, $conversationId, $readAt));
                } catch (\Throwable $e) {
                    // Broadcasting niet geconfigureerd
                }
            }
        }

        return response()->json(['data' => ['message' => 'ok']]);
    }

    /**
     * Trainer meldt dat hij aan het typen is; broadcast naar klant.
     */
    public function typing(Request $request, string $conversationId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where(function ($q) use ($user) {
                $q->where('trainer_user_id', $user->id)
                    ->orWhere(function ($q2) use ($user) {
                        $q2->where('client_user_id', $user->id);
                        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
                            $q2->whereNotNull('support_ticket_id');
                        }
                    });
            })
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $receiverId = (int) $user->id === (int) $conversation->trainer_user_id
            ? (int) $conversation->client_user_id
            : (int) $conversation->trainer_user_id;
        if ($receiverId > 0 && class_exists(\App\Events\Gymies\GymiesChatUserTyping::class)) {
            try {
                $displayName = DB::table('gymies_users')->where('id', $user->id)->value('display_name') ?? 'Trainer';
                event(new \App\Events\Gymies\GymiesChatUserTyping($receiverId, $conversationId, (int) $user->id, $displayName));
            } catch (\Throwable $e) {
                // Broadcasting niet geconfigureerd
            }
        }

        return response()->json(['data' => ['message' => 'ok']]);
    }

    /**
     * Contextuele header voor chat (trainer): resterende strippen, duo-status placeholder.
     * Zelfde bron als sleepingClients — packages + package_id op boekingen.
     */
    public function conversationContext(Request $request, string $conversationId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $trainerId = (int) $user->id;

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where(function ($q) use ($trainerId) {
                $q->where('trainer_user_id', $trainerId)
                    ->orWhere(function ($q2) use ($trainerId) {
                        $q2->where('client_user_id', $trainerId);
                        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
                            $q2->whereNotNull('support_ticket_id');
                        }
                    });
            })
            ->first(['id', 'client_user_id', 'booking_id', 'support_ticket_id']);
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        if (!empty($conversation->support_ticket_id)) {
            $ticketStatus = null;
            if (Schema::hasTable('gymies_support_tickets')) {
                $ticket = DB::table('gymies_support_tickets')
                    ->where('id', (int) $conversation->support_ticket_id)
                    ->first(['status']);
                $ticketStatus = $ticket ? (string) ($ticket->status ?? '') : null;
            }
            return response()->json(['data' => [
                'conversation_id' => $conversationId,
                'client_user_id' => (string) $conversation->client_user_id,
                'booking_id' => $conversation->booking_id ? (string) $conversation->booking_id : null,
                'sessions_remaining_total' => 0,
                'duo_state' => 'none',
                'duo_state_label' => null,
                'next_booking' => null,
                'support_ticket_id' => (string) $conversation->support_ticket_id,
                'support_ticket_status' => $ticketStatus ?? '',
            ]]);
        }

        $clientUserId = (int) $conversation->client_user_id;
        $sessionsRemaining = 0;
        if (Schema::hasTable('gymies_packages') && Schema::hasColumn('gymies_bookings', 'package_id')) {
            $packages = DB::table('gymies_packages')
                ->where('trainer_user_id', $trainerId)
                ->get(['id', 'sessions_count']);
            foreach ($packages as $pkg) {
                $sessionsCount = (int) ($pkg->sessions_count ?? 0);
                if ($sessionsCount <= 0) {
                    continue;
                }
                $used = (int) DB::table('gymies_bookings')
                    ->where('client_user_id', $clientUserId)
                    ->where('package_id', (int) $pkg->id)
                    ->whereNotIn('status', ['cancelled'])
                    ->count();
                $sessionsRemaining += max(0, $sessionsCount - $used);
            }
        }

        // Placeholder tot duo-voorstel entiteit bestaat (WebSocket + kaart in UI)
        $duoState = 'none';
        // Optioneel: prefs key gymies_buddy_searching_{userId} — alleen indicatie, geen PII
        // $duoState = ...;

        return response()->json([
            'data' => [
                'conversation_id' => (string) $conversationId,
                'client_user_id' => (string) $clientUserId,
                'booking_id' => $conversation->booking_id ? (string) $conversation->booking_id : null,
                'sessions_remaining_total' => $sessionsRemaining,
                'duo_state' => $duoState,
                'duo_state_label' => $duoState === 'waiting_match' ? 'Wacht op Duo-match' : null,
            ],
        ]);
    }

    public function sendMessage(Request $request, string $conversationId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $request->validate([
            'body' => 'required|string|max:5000',
        ]);

        $conversation = DB::table('gymies_conversations')
            ->where('id', $conversationId)
            ->where(function ($q) use ($user) {
                $q->where('trainer_user_id', $user->id)
                    ->orWhere(function ($q2) use ($user) {
                        $q2->where('client_user_id', $user->id);
                        if (Schema::hasColumn('gymies_conversations', 'support_ticket_id')) {
                            $q2->whereNotNull('support_ticket_id');
                        }
                    });
            })
            ->first();
        if (!$conversation) {
            return response()->json(['message' => 'Conversatie niet gevonden.'], 404);
        }

        $body = trim((string) $request->input('body'));
        $id = DB::table('gymies_messages')->insertGetId([
            'conversation_id' => $conversationId,
            'from_user_id' => $user->id,
            'body' => $body,
            'created_at' => now(),
        ]);
        DB::table('gymies_conversations')->where('id', $conversationId)->update(['updated_at' => now()]);

        if (class_exists(GymiesChatBroadcast::class)) {
            GymiesChatBroadcast::afterMessageInserted($conversationId, (int) $id, (int) $user->id, $body);
        }

        if (class_exists(\App\Helpers\GymiesSupportSync::class) && !empty($conversation->support_ticket_id)) {
            \App\Helpers\GymiesSupportSync::syncConversationMessageToTicket($conversationId, (int) $user->id, $body);
        }

        return response()->json(['data' => ['id' => (string) $id]], 201);
    }

    public function liveCounters(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $query = DB::table('gymies_bookings')
            ->where('trainer_user_id', $user->id)
            ->where(function ($q) {
                $q->where('status', 'pending');
                if (Schema::hasColumn('gymies_bookings', 'payment_method')) {
                    $q->orWhere(function ($q2) {
                        $q2->where('status', 'reserved')
                            ->where('payment_method', 'cash');
                    });
                }
            });
        $pending = (int) $query->count();

        $unread = (int) DB::table('gymies_conversations as c')
            ->join('gymies_messages as m', 'm.conversation_id', '=', 'c.id')
            ->where('c.trainer_user_id', $user->id)
            ->where('m.from_user_id', '!=', $user->id)
            ->whereNull('m.read_at')
            ->count();

        return response()->json([
            'data' => [
                'pending_requests_count' => $pending,
                'unread_messages_count' => $unread,
                'generated_at' => now()->toIso8601String(),
            ],
        ]);
    }

    public function reportIssue(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }

        $request->validate([
            'message' => 'required|string|max:5000',
            'context' => 'nullable|array',
        ]);
        $context = $this->sanitizeAuditPayload((array) $request->input('context', [])) ?? [];

        if (DB::getSchemaBuilder()->hasTable('gymies_api_error_logs')) {
            DB::table('gymies_api_error_logs')->insert([
                'user_id' => $user->id,
                'endpoint' => 'trainer/report-issue',
                'error_code' => 'TRAINER_REPORTED_ISSUE',
                'message' => mb_substr((string) $request->input('message'), 0, 1000),
                'context_json' => json_encode($context, JSON_UNESCAPED_UNICODE),
                'created_at' => now(),
            ]);
        }
        $this->logAudit(
            (int) $user->id,
            'trainer_reported_issue',
            'support',
            null,
            null,
            ['message' => mb_substr((string) $request->input('message'), 0, 1000), 'context' => $context]
        );

        return response()->json(['ok' => true], 201);
    }

    /**
     * Public Profile CMS (storefront): GET huidige inhoud voor ingelogde trainer.
     */
    public function storefrontCmsGet(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        // T-plan: storefront CMS vereist Pro
        $planCheck = GymiesPlanManager::assertPro((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json(['message' => $planCheck['message'], 'upgrade_hint' => $planCheck['upgrade_hint'], 'code' => 'plan_storefront_locked'], 403);
        }
        if (!Schema::hasTable('gymies_trainer_storefront')) {
            return response()->json([
                'data' => [
                    'success_stories' => [],
                    'video_pitch_url' => null,
                    'specializations_display' => null,
                    'seo_title' => null,
                    'seo_description' => null,
                    'seo_keywords' => null,
                    'layout' => null,
                ],
            ]);
        }
        $row = DB::table('gymies_trainer_storefront')
            ->where('trainer_user_id', (int) $user->id)
            ->first();
        if (!$row) {
            return response()->json([
                'data' => [
                    'success_stories' => [],
                    'video_pitch_url' => null,
                    'specializations_display' => null,
                    'seo_title' => null,
                    'seo_description' => null,
                    'seo_keywords' => null,
                    'layout' => null,
                ],
            ]);
        }
        $stories = [];
        if (!empty($row->success_stories_json)) {
            $decoded = json_decode((string) $row->success_stories_json, true);
            if (is_array($decoded)) {
                $stories = $decoded;
            }
        }
        $layout = null;
        if (!empty($row->layout_json)) {
            $decoded = json_decode((string) $row->layout_json, true);
            if (is_array($decoded)) {
                $layout = $decoded;
            }
        }
        return response()->json([
            'data' => [
                'success_stories' => $stories,
                'video_pitch_url' => $row->video_pitch_url,
                'instagram_handle' => Schema::hasColumn('gymies_trainer_storefront', 'instagram_handle') ? ($row->instagram_handle ?? null) : null,
                'specializations_display' => $row->specializations_display,
                'seo_title' => $row->seo_title,
                'seo_description' => $row->seo_description,
                'seo_keywords' => $row->seo_keywords,
                'layout' => $layout,
            ],
        ]);
    }

    /**
     * Public Profile CMS: PUT — Visual Builder + SEO.
     */
    public function storefrontCmsPut(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        // T-plan: storefront CMS vereist Pro
        $planCheck = GymiesPlanManager::assertPro((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json(['message' => $planCheck['message'], 'upgrade_hint' => $planCheck['upgrade_hint'], 'code' => 'plan_storefront_locked'], 403);
        }
        if (!Schema::hasTable('gymies_trainer_storefront')) {
            return response()->json(['message' => 'Storefront-tabel ontbreekt. Voer alter_gymies_trainer_storefront.sql uit.'], 503);
        }
        $request->validate([
            'success_stories' => 'nullable|array',
            'success_stories.*.title' => 'nullable|string|max:255',
            'success_stories.*.body' => 'nullable|string|max:5000',
            'success_stories.*.quote' => 'nullable|string|max:500',
            'success_stories.*.image_url' => 'nullable|url|max:512',
            'success_stories.*.before_image_url' => 'nullable|url|max:512',
            'success_stories.*.after_image_url' => 'nullable|url|max:512',
            'video_pitch_url' => 'nullable|url|max:512',
            'instagram_handle' => 'nullable|string|max:100',
            'specializations_display' => 'nullable|string|max:10000',
            'seo_title' => 'nullable|string|max:255',
            'seo_description' => 'nullable|string|max:500',
            'seo_keywords' => 'nullable|string|max:500',
            'layout' => 'nullable|array',
        ]);
        $trainerId = (int) $user->id;
        $stories = $request->input('success_stories', []);
        if (!is_array($stories)) {
            $stories = [];
        }
        // T-015 FIXED: success_stories_json structuur validatie
        $stories = array_values(array_filter($stories, static function ($s): bool {
            if (!is_array($s)) {
                return false;
            }
            $url = trim((string) ($s['image_url'] ?? ''));
            $before = trim((string) ($s['before_image_url'] ?? ''));
            $after = trim((string) ($s['after_image_url'] ?? ''));
            $t = trim((string) ($s['title'] ?? ''));
            $b = trim((string) ($s['body'] ?? ''));
            $q = trim((string) ($s['quote'] ?? ''));
            return $url !== '' || $before !== '' || $after !== '' || $t !== '' || $b !== '' || $q !== '';
        }));
        // Begrens aantal entries
        $stories = array_slice($stories, 0, 20);
        // Sanitiseer elke entry
        $stories = array_map(function ($story) {
            return [
                'image_url' => htmlspecialchars(strip_tags((string)($story['image_url'] ?? '')), ENT_QUOTES, 'UTF-8'),
                'before_image_url' => htmlspecialchars(strip_tags((string)($story['before_image_url'] ?? '')), ENT_QUOTES, 'UTF-8'),
                'after_image_url' => htmlspecialchars(strip_tags((string)($story['after_image_url'] ?? '')), ENT_QUOTES, 'UTF-8'),
                'title' => htmlspecialchars(strip_tags((string)($story['title'] ?? '')), ENT_QUOTES, 'UTF-8'),
                'body' => htmlspecialchars(strip_tags((string)($story['body'] ?? '')), ENT_QUOTES, 'UTF-8'),
                'quote' => htmlspecialchars(strip_tags((string)($story['quote'] ?? '')), ENT_QUOTES, 'UTF-8'),
            ];
        }, $stories);
        $storiesJson = json_encode($stories, JSON_UNESCAPED_UNICODE);
        $layout = $request->input('layout');
        $layoutJson = is_array($layout) ? json_encode($layout, JSON_UNESCAPED_UNICODE) : null;

        $ig = $request->input('instagram_handle');
        $igHandle = is_string($ig) ? preg_replace('/^@/', '', trim($ig)) : null;
        $igHandle = $igHandle !== '' ? $igHandle : null;

        $payload = [
            'success_stories_json' => $storiesJson,
            'video_pitch_url' => $request->input('video_pitch_url') ? trim((string) $request->input('video_pitch_url')) : null,
            'specializations_display' => $request->input('specializations_display') ? trim((string) $request->input('specializations_display')) : null,
            'seo_title' => $request->input('seo_title') ? trim((string) $request->input('seo_title')) : null,
            'seo_description' => $request->input('seo_description') ? trim((string) $request->input('seo_description')) : null,
            'seo_keywords' => $request->input('seo_keywords') ? trim((string) $request->input('seo_keywords')) : null,
            'layout_json' => $layoutJson,
            'updated_at' => now(),
        ];
        if (Schema::hasColumn('gymies_trainer_storefront', 'instagram_handle')) {
            $payload['instagram_handle'] = $igHandle;
        }
        $exists = DB::table('gymies_trainer_storefront')->where('trainer_user_id', $trainerId)->exists();
        if ($exists) {
            DB::table('gymies_trainer_storefront')->where('trainer_user_id', $trainerId)->update($payload);
        } else {
            $payload['trainer_user_id'] = $trainerId;
            DB::table('gymies_trainer_storefront')->insert($payload);
        }
        // Optioneel: sync video naar profiel intro_video_url als kolom bestaat
        if ($payload['video_pitch_url'] && Schema::hasColumn('gymies_trainer_profiles', 'intro_video_url')) {
            DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->update([
                'intro_video_url' => $payload['video_pitch_url'],
                'updated_at' => now(),
            ]);
        }
        return $this->storefrontCmsGet($request);
    }

    public function ensureConversation(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $request->validate([
            'client_user_id' => 'required|exists:gymies_users,id',
            'booking_id' => 'nullable|exists:gymies_bookings,id',
        ]);

        $trainerId = (int) $user->id;
        $clientId = (int) $request->input('client_user_id');
        $bookingId = $request->input('booking_id');

        if ($bookingId !== null) {
            $booking = DB::table('gymies_bookings')
                ->where('id', $bookingId)
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->first();
            if (!$booking) {
                return response()->json(['message' => 'Boeking past niet bij trainer/klant.'], 422);
            }
        }

        $existing = DB::table('gymies_conversations')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->when($bookingId !== null, fn ($q) => $q->where('booking_id', $bookingId))
            ->orderByDesc('id')
            ->first();

        if (!$existing && $bookingId !== null) {
            $existing = DB::table('gymies_conversations')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->whereNull('booking_id')
                ->orderByDesc('id')
                ->first();
        }

        if ($existing) {
            return response()->json(['data' => ['id' => (string) $existing->id]]);
        }

        $id = DB::table('gymies_conversations')->insertGetId([
            'client_user_id' => $clientId,
            'trainer_user_id' => $trainerId,
            'booking_id' => $bookingId,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['data' => ['id' => (string) $id]], 201);
    }

    /**
     * Lijst eigen promo codes (alleen rijen met trainer_user_id = ingelogde trainer).
     */
    public function promoCodes(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $planCheck = GymiesPlanManager::assertPro((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json(['message' => $planCheck['message'], 'upgrade_hint' => $planCheck['upgrade_hint'], 'code' => 'plan_promo_codes_locked'], 403);
        }
        if (!Schema::hasTable('gymies_promo_codes')) {
            return response()->json(['data' => []]);
        }
        if (!Schema::hasColumn('gymies_promo_codes', 'trainer_user_id')) {
            return response()->json(['data' => []]);
        }
        $trainerId = (int) $user->id;
        $rows = DB::table('gymies_promo_codes')
            ->where('trainer_user_id', $trainerId)
            ->orderByDesc('id')
            ->get()
            ->map(static fn ($r) => [
                'id' => (string) $r->id,
                'code' => (string) $r->code,
                'discount_type' => (string) $r->discount_type,
                'value_cents' => (int) $r->value_cents,
                'valid_from' => $r->valid_from,
                'valid_until' => $r->valid_until,
                'max_uses' => $r->max_uses !== null ? (int) $r->max_uses : null,
                'use_count' => (int) ($r->use_count ?? 0),
                'created_at' => $r->created_at,
            ])
            ->all();
        return response()->json(['data' => $rows]);
    }

    /**
     * Nieuwe promo code aanmaken (altijd gekoppeld aan deze trainer).
     */
    public function storePromoCode(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $planCheck = GymiesPlanManager::assertPro((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json(['message' => $planCheck['message'], 'upgrade_hint' => $planCheck['upgrade_hint'], 'code' => 'plan_promo_codes_locked'], 403);
        }
        if (!Schema::hasTable('gymies_promo_codes') || !Schema::hasColumn('gymies_promo_codes', 'trainer_user_id')) {
            GymiesSchemaEnsure::promoCodesTrainerColumn();
        }
        if (!Schema::hasTable('gymies_promo_codes') || !Schema::hasColumn('gymies_promo_codes', 'trainer_user_id')) {
            return response()->json(['message' => 'Promo-codes voor trainers zijn nog niet geactiveerd. Voer alter_gymies_promo_codes_trainer.sql uit.'], 503);
        }
        $request->validate([
            'code' => 'required|string|max:64',
            'discount_type' => 'required|string|in:percent,fixed',
            'value_cents' => 'required|integer|min:1',
            'valid_from' => 'nullable|date',
            'valid_until' => 'nullable|date',
            'max_uses' => 'nullable|integer|min:1',
        ]);
        $code = strtoupper(preg_replace('/\s+/', '', (string) $request->input('code')));
        if ($code === '') {
            return response()->json(['message' => 'Voer een code in.'], 422);
        }
        $exists = DB::table('gymies_promo_codes')->where('code', $code)->exists();
        if ($exists) {
            return response()->json(['message' => 'Deze code bestaat al (globaal uniek). Kies een andere.'], 422);
        }
        $valueCents = (int) $request->input('value_cents');
        if ($request->input('discount_type') === 'percent' && ($valueCents < 1 || $valueCents > 100)) {
            return response()->json(['message' => 'Percentage moet tussen 1 en 100 liggen.'], 422);
        }
        $trainerId = (int) $user->id;
        $id = DB::table('gymies_promo_codes')->insertGetId([
            'trainer_user_id' => $trainerId,
            'code' => $code,
            'discount_type' => $request->input('discount_type'),
            'value_cents' => $valueCents,
            'valid_from' => $request->input('valid_from') ?: null,
            'valid_until' => $request->input('valid_until') ?: null,
            'max_uses' => $request->input('max_uses') ? (int) $request->input('max_uses') : null,
            'use_count' => 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $row = DB::table('gymies_promo_codes')->where('id', $id)->first();
        return response()->json([
            'data' => [
                'id' => (string) $row->id,
                'code' => (string) $row->code,
                'discount_type' => (string) $row->discount_type,
                'value_cents' => (int) $row->value_cents,
                'valid_from' => $row->valid_from,
                'valid_until' => $row->valid_until,
                'max_uses' => $row->max_uses ? (int) $row->max_uses : null,
                'use_count' => (int) $row->use_count,
            ],
        ], 201);
    }

    /**
     * Geldigheid / max uses aanpassen (code en type niet wijzigen om misbruik te voorkomen).
     */
    public function updatePromoCode(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $planCheck = GymiesPlanManager::assertPro((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json(['message' => $planCheck['message'], 'upgrade_hint' => $planCheck['upgrade_hint'], 'code' => 'plan_promo_codes_locked'], 403);
        }
        if (!ctype_digit($id) || (int) $id < 1) {
            return response()->json(['message' => 'Ongeldige code.'], 422);
        }
        if (!Schema::hasTable('gymies_promo_codes') || !Schema::hasColumn('gymies_promo_codes', 'trainer_user_id')) {
            GymiesSchemaEnsure::promoCodesTrainerColumn();
        }
        if (!Schema::hasTable('gymies_promo_codes') || !Schema::hasColumn('gymies_promo_codes', 'trainer_user_id')) {
            return response()->json(['message' => 'Promo-codes voor trainers zijn nog niet geactiveerd.'], 503);
        }
        $row = DB::table('gymies_promo_codes')
            ->where('id', (int) $id)
            ->where('trainer_user_id', (int) $user->id)
            ->first();
        if (!$row) {
            return response()->json(['message' => 'Code niet gevonden.'], 404);
        }
        $request->validate([
            'valid_from' => 'nullable|date',
            'valid_until' => 'nullable|date',
            'max_uses' => 'nullable|integer|min:1',
        ]);
        $update = ['updated_at' => now()];
        if ($request->has('valid_from')) {
            $update['valid_from'] = $request->input('valid_from') ?: null;
        }
        if ($request->has('valid_until')) {
            $update['valid_until'] = $request->input('valid_until') ?: null;
        }
        if ($request->has('max_uses')) {
            $update['max_uses'] = $request->input('max_uses') ? (int) $request->input('max_uses') : null;
        }
        DB::table('gymies_promo_codes')->where('id', (int) $id)->update($update);
        $row = DB::table('gymies_promo_codes')->where('id', (int) $id)->first();
        return response()->json([
            'data' => [
                'id' => (string) $row->id,
                'code' => (string) $row->code,
                'discount_type' => (string) $row->discount_type,
                'value_cents' => (int) $row->value_cents,
                'valid_from' => $row->valid_from,
                'valid_until' => $row->valid_until,
                'max_uses' => $row->max_uses !== null ? (int) $row->max_uses : null,
                'use_count' => (int) $row->use_count,
            ],
        ]);
    }

    /**
     * Promo code verwijderen (alleen eigen).
     */
    public function deletePromoCode(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) {
            return $user;
        }
        $planCheck = GymiesPlanManager::assertPro((int) $user->id);
        if (!$planCheck['allowed']) {
            return response()->json(['message' => $planCheck['message'], 'upgrade_hint' => $planCheck['upgrade_hint'], 'code' => 'plan_promo_codes_locked'], 403);
        }
        if (!ctype_digit($id) || (int) $id < 1) {
            return response()->json(['message' => 'Ongeldige code.'], 422);
        }
        if (!Schema::hasTable('gymies_promo_codes') || !Schema::hasColumn('gymies_promo_codes', 'trainer_user_id')) {
            GymiesSchemaEnsure::promoCodesTrainerColumn();
        }
        if (!Schema::hasTable('gymies_promo_codes') || !Schema::hasColumn('gymies_promo_codes', 'trainer_user_id')) {
            return response()->json(['message' => 'Promo-codes voor trainers zijn nog niet geactiveerd.'], 503);
        }
        $deleted = DB::table('gymies_promo_codes')
            ->where('id', (int) $id)
            ->where('trainer_user_id', (int) $user->id)
            ->delete();
        if ($deleted === 0) {
            return response()->json(['message' => 'Code niet gevonden.'], 404);
        }
        return response()->json(['data' => ['deleted' => true]]);
    }

    /**
     * @return list<array<string,mixed>>
     */
    private function buildClientHealthItems(int $trainerId): array
    {
        if (!Schema::hasTable('gymies_bookings')) {
            return [];
        }
        $clientIds = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->distinct()
            ->pluck('client_user_id')
            ->filter()
            ->map(fn ($id) => (int) $id)
            ->values()
            ->all();
        if (empty($clientIds)) {
            return [];
        }

        $now = now();
        $items = [];
        foreach ($clientIds as $clientId) {
            $bookings = DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->orderByDesc('scheduled_at')
                ->limit(30)
                ->get(['status', 'scheduled_at']);
            if ($bookings->isEmpty()) {
                continue;
            }

            $tracked = $bookings->whereIn('status', ['completed', 'confirmed', 'no_show', 'cancelled'])->count();
            $attended = $bookings->whereIn('status', ['completed', 'confirmed'])->count();
            $noShows = $bookings->where('status', 'no_show')->count();
            $cancelled = $bookings->where('status', 'cancelled')->count();

            $attendanceRate = $tracked > 0 ? ($attended / $tracked) : 0.0;
            $noShowRate = $tracked > 0 ? ($noShows / $tracked) : 0.0;
            $cancelRate = $tracked > 0 ? ($cancelled / $tracked) : 0.0;

            $firstCompleted = $bookings
                ->whereIn('status', ['completed', 'confirmed', 'no_show'])
                ->first();
            $lastSessionAt = $firstCompleted !== null ? ($firstCompleted->scheduled_at ?? null) : null;
            $recencyDays = $lastSessionAt ? \Carbon\Carbon::parse((string) $lastSessionAt)->diffInDays($now) : 99;

            $recent30 = $bookings->filter(function ($b) use ($now) {
                $at = \Carbon\Carbon::parse((string) $b->scheduled_at);
                return $at->greaterThanOrEqualTo($now->copy()->subDays(30));
            });
            $prev30 = $bookings->filter(function ($b) use ($now) {
                $at = \Carbon\Carbon::parse((string) $b->scheduled_at);
                return $at->lt($now->copy()->subDays(30)) && $at->greaterThanOrEqualTo($now->copy()->subDays(60));
            });
            $recentTracked = $recent30->whereIn('status', ['completed', 'confirmed', 'no_show', 'cancelled'])->count();
            $prevTracked = $prev30->whereIn('status', ['completed', 'confirmed', 'no_show', 'cancelled'])->count();
            $recentAttendRate = $recentTracked > 0
                ? ($recent30->whereIn('status', ['completed', 'confirmed'])->count() / $recentTracked)
                : null;
            $prevAttendRate = $prevTracked > 0
                ? ($prev30->whereIn('status', ['completed', 'confirmed'])->count() / $prevTracked)
                : null;

            $signals = [];
            $score = 100;
            $score -= (int) round($noShowRate * 40);
            $score -= (int) round($cancelRate * 25);
            if ($recencyDays > 14) {
                $score -= min(30, ($recencyDays - 14) * 2);
                $signals[] = 'inactive_14_plus_days';
            }
            if ($noShows > 0 && $recent30->where('status', 'no_show')->count() > 0) {
                $signals[] = 'recent_no_show';
            }
            if ($prevAttendRate !== null && $recentAttendRate !== null && ($prevAttendRate - $recentAttendRate) >= 0.20) {
                $score -= 15;
                $signals[] = 'attendance_drop';
            }
            if ($cancelRate >= 0.35) {
                $signals[] = 'high_cancel_ratio';
            }
            if ($noShowRate >= 0.20) {
                $signals[] = 'high_no_show_ratio';
            }
            $score = max(0, min(100, $score));

            $retentionRisk = $score < 45 || $recencyDays > 21
                ? 'high'
                : ($score < 70 || $recencyDays > 14 ? 'medium' : 'low');
            $noShowRisk = $noShowRate >= 0.25
                ? 'high'
                : ($noShowRate >= 0.10 ? 'medium' : 'low');
            $churnAlert = $retentionRisk === 'high' || in_array('attendance_drop', $signals, true);

            $clientName = $this->displayNameForClient($clientId);
            $updatedAt = $now->toDateTimeString();

            if (Schema::hasTable('gymies_trainer_client_health_scores')) {
                DB::table('gymies_trainer_client_health_scores')->updateOrInsert(
                    ['trainer_user_id' => $trainerId, 'client_user_id' => $clientId],
                    [
                        'health_score' => $score,
                        'retention_risk' => $retentionRisk,
                        'no_show_risk' => $noShowRisk,
                        'churn_alert' => $churnAlert ? 1 : 0,
                        'signals_json' => json_encode(array_values(array_unique($signals)), JSON_UNESCAPED_UNICODE),
                        'updated_at' => $now,
                    ]
                );
            }

            $items[] = [
                'client_user_id' => (string) $clientId,
                'client_name' => $clientName,
                'health_score' => $score,
                'retention_risk' => $retentionRisk,
                'no_show_risk' => $noShowRisk,
                'churn_alert' => $churnAlert,
                'signals' => array_values(array_unique($signals)),
                'updated_at' => $updatedAt,
            ];
        }

        usort($items, static function (array $a, array $b): int {
            return ($a['health_score'] <=> $b['health_score']);
        });

        return $items;
    }

    /**
     * @return list<array<string,mixed>>
     */
    private function buildUpsellSuggestions(int $trainerId): array
    {
        if (!Schema::hasTable('gymies_trainer_upsell_suggestions')) {
            return [];
        }
        $this->seedUpsellSuggestions($trainerId);

        $rows = DB::table('gymies_trainer_upsell_suggestions')
            ->where('trainer_user_id', $trainerId)
            ->whereIn('status', ['pending', 'sent', 'accepted'])
            ->where(function ($q) {
                $q->whereNull('expires_at')->orWhere('expires_at', '>=', now());
            })
            ->orderByDesc('confidence')
            ->orderByDesc('created_at')
            ->limit(100)
            ->get();
        if ($rows->isEmpty()) {
            return [];
        }
        $clientNameById = DB::table('gymies_users')
            ->whereIn('id', $rows->pluck('client_user_id')->map(fn ($id) => (int) $id)->all())
            ->get(['id', 'display_name', 'email'])
            ->mapWithKeys(fn ($u) => [(int) $u->id => $this->displayNameFromUserRow($u)])
            ->all();
        $packageValueById = [];
        if (Schema::hasTable('gymies_packages')) {
            $packageValueById = DB::table('gymies_packages')
                ->whereIn('id', $rows->pluck('package_id')->map(fn ($id) => (int) $id)->all())
                ->get(['id', 'total_cents'])
                ->mapWithKeys(fn ($p) => [(int) $p->id => (int) ($p->total_cents ?? 0)])
                ->all();
        }

        return $rows->map(fn ($r) => [
            'suggestion_id' => (string) $r->id,
            'client_user_id' => (string) $r->client_user_id,
            'client_name' => (string) ($clientNameById[(int) $r->client_user_id] ?? 'Klant'),
            'package_id' => (string) $r->package_id,
            'reason' => $r->reason,
            'expected_value_cents' => (int) ($packageValueById[(int) $r->package_id] ?? 0),
            'confidence' => $r->confidence !== null ? (float) $r->confidence : null,
            'status' => (string) $r->status,
            'expires_at' => $r->expires_at,
            'sent_at' => $r->sent_at,
        ])->all();
    }

    private function displayNameForClient(int $clientUserId): string
    {
        $u = DB::table('gymies_users')->where('id', $clientUserId)->first(['display_name', 'name', 'email']);
        if (!$u) {
            return 'Klant';
        }
        $name = trim((string) ($u->display_name ?? $u->name ?? ''));
        if ($name !== '') {
            return $name;
        }
        $email = trim((string) ($u->email ?? ''));
        return $email !== '' ? $email : 'Klant';
    }

    private function displayNameFromUserRow(object $u): string
    {
        $name = trim((string) ($u->display_name ?? ''));
        if ($name !== '') {
            return $name;
        }
        $email = trim((string) ($u->email ?? ''));
        return $email !== '' ? $email : 'Klant';
    }

    private function seedUpsellSuggestions(int $trainerId): void
    {
        if (!Schema::hasTable('gymies_trainer_upsell_suggestions') || !Schema::hasTable('gymies_packages')) {
            return;
        }
        $bestPackageId = (int) (DB::table('gymies_packages')
            ->where('trainer_user_id', $trainerId)
            ->orderByDesc('sessions_count')
            ->orderByDesc('total_cents')
            ->value('id') ?? 0);
        if ($bestPackageId < 1) {
            return;
        }
        $health = $this->buildClientHealthItems($trainerId);
        foreach ($health as $h) {
            $clientId = (int) ($h['client_user_id'] ?? 0);
            if ($clientId < 1) {
                continue;
            }
            $reason = null;
            $confidence = null;
            if (($h['retention_risk'] ?? 'low') === 'high') {
                $reason = 'reengage_after_dropoff';
                $confidence = 0.74;
            } elseif (($h['no_show_risk'] ?? 'low') === 'high') {
                $reason = 'stabilize_commitment_plan';
                $confidence = 0.66;
            } elseif ((int) ($h['health_score'] ?? 0) >= 78) {
                $reason = 'upgrade_high_engagement';
                $confidence = 0.82;
            }
            if ($reason === null) {
                continue;
            }
            $exists = DB::table('gymies_trainer_upsell_suggestions')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->where('package_id', $bestPackageId)
                ->whereIn('status', ['pending', 'sent', 'accepted'])
                ->where(function ($q) {
                    $q->whereNull('expires_at')->orWhere('expires_at', '>=', now());
                })
                ->exists();
            if ($exists) {
                continue;
            }
            DB::table('gymies_trainer_upsell_suggestions')->insert([
                'trainer_user_id' => $trainerId,
                'client_user_id' => $clientId,
                'package_id' => $bestPackageId,
                'reason' => $reason,
                'confidence' => $confidence,
                'status' => 'pending',
                'expires_at' => now()->addDays(14),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    private function seedRebookSuggestions(int $trainerId): void
    {
        if (!Schema::hasTable('gymies_trainer_rebook_suggestions') || !Schema::hasTable('gymies_trainer_client_health_scores') || !Schema::hasTable('gymies_bookings')) {
            return;
        }
        $healthRows = DB::table('gymies_trainer_client_health_scores')
            ->where('trainer_user_id', $trainerId)
            ->get(['client_user_id', 'retention_risk', 'no_show_risk']);
        foreach ($healthRows as $h) {
            $clientId = (int) $h->client_user_id;
            if ($clientId < 1) {
                continue;
            }
            $hasUpcoming = DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->whereIn('status', ['pending', 'confirmed', 'reserved'])
                ->where('scheduled_at', '>', now())
                ->exists();
            if ($hasUpcoming) {
                continue;
            }
            $exists = DB::table('gymies_trainer_rebook_suggestions')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->whereIn('status', ['pending', 'sent', 'accepted'])
                ->exists();
            if ($exists) {
                continue;
            }
            $lastBookingId = (int) (DB::table('gymies_bookings')
                ->where('trainer_user_id', $trainerId)
                ->where('client_user_id', $clientId)
                ->orderByDesc('scheduled_at')
                ->value('id') ?? 0);
            $reason = ((string) $h->retention_risk) === 'high'
                ? 'prevent_churn_rebook'
                : (((string) $h->no_show_risk) === 'high' ? 'rebook_after_no_show' : 'keep_momentum');
            $confidence = ((string) $h->retention_risk) === 'high'
                ? 0.78
                : (((string) $h->no_show_risk) === 'high' ? 0.70 : 0.60);
            DB::table('gymies_trainer_rebook_suggestions')->insert([
                'trainer_user_id' => $trainerId,
                'client_user_id' => $clientId,
                'booking_id' => $lastBookingId > 0 ? $lastBookingId : null,
                'next_slot_at' => now()->addDays(3),
                'reason' => $reason,
                'confidence' => $confidence,
                'status' => 'pending',
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }
    }

    /**
     * Pro/Studio mogen pakketten muteren; Starter/Basis krijgen 403 (consistent met Flutter lock).
     */
    private function trainerCanEditPackages(int $trainerUserId): bool
    {
        if (!DB::getSchemaBuilder()->hasTable('gymies_trainer_profiles')) {
            return true;
        }
        if (!DB::getSchemaBuilder()->hasColumn('gymies_trainer_profiles', 'subscription_plan')) {
            return true;
        }
        $plan = DB::table('gymies_trainer_profiles')->where('user_id', $trainerUserId)->value('subscription_plan');
        $p = strtolower(trim((string) ($plan ?? '')));
        if ($p === 'starter' || $p === 'basis') {
            return false;
        }
        // pro, studio, elite of leeg/legacy: toestaan
        return true;
    }

    /**
     * @return array<string,mixed>
     */
    private function sessionEntryToArray(object $row): array
    {
        return [
            'id' => (string) $row->id,
            'trainer_user_id' => (string) $row->trainer_user_id,
            'client_user_id' => (string) $row->client_user_id,
            'booking_id' => $row->booking_id !== null ? (string) $row->booking_id : null,
            'session_at' => $row->session_at,
            'session_type' => $row->session_type,
            'attendance_status' => $row->attendance_status,
            'focus' => $row->focus,
            'positive_notes' => $row->positive_notes,
            'improve_notes' => $row->improve_notes,
            'homework' => $row->homework,
            'energy_score' => $row->energy_score !== null ? (int) $row->energy_score : null,
            'performance_score' => $row->performance_score !== null ? (float) $row->performance_score : null,
            'visibility' => $row->visibility ?? 'internal',
            'created_at' => $row->created_at ?? null,
            'updated_at' => $row->updated_at ?? null,
        ];
    }

    /**
     * @param list<string> $dates yyyy-mm-dd
     */
    private function calculateDateStreakDays(array $dates): int
    {
        if (empty($dates)) {
            return 0;
        }
        rsort($dates);
        $streak = 1;
        $cursor = \Carbon\Carbon::parse($dates[0])->startOfDay();
        for ($i = 1; $i < count($dates); $i++) {
            $d = \Carbon\Carbon::parse($dates[$i])->startOfDay();
            if ($d->equalTo($cursor->copy()->subDay())) {
                $streak++;
                $cursor = $d;
                continue;
            }
            if ($d->equalTo($cursor)) {
                continue;
            }
            break;
        }
        return $streak;
    }

    private function toCanonicalPaymentMethod(string $storedMethod, string $provider): string
    {
        $m = strtolower(trim($storedMethod));
        $p = strtolower(trim($provider));
        if ($m === 'cash' || $p === 'cash') {
            return 'cash';
        }
        return 'mollie';
    }

    private function toCanonicalPaymentStatus(string $rawStatus, string $paymentMethod, string $bookingStatus): string
    {
        $raw = strtolower(trim($rawStatus));
        $booking = strtolower(trim($bookingStatus));
        if ($paymentMethod === 'cash' && in_array($raw, ['paid', 'cash', 'paid_cash'], true)) {
            return 'cash';
        }
        if (in_array($raw, ['paid', 'mollie_paid', 'paid_mollie'], true)) {
            return 'paid';
        }
        if (in_array($raw, ['failed', 'expired', 'cancelled', 'canceled'], true) || $booking === 'cancelled') {
            return 'cancelled';
        }
        if (in_array($raw, ['pending', 'open', 'awaiting_cash', 'unpaid', ''], true)) {
            return 'open';
        }
        return 'open';
    }

    /**
     * @return array<string,mixed>
     */
    private function readPayoutSettings(int $trainerId): array
    {
        if (!DB::getSchemaBuilder()->hasTable('gymies_trainer_bank_accounts')) {
            return $this->defaultPayoutSettings();
        }

        $row = DB::table('gymies_trainer_bank_accounts')
            ->where('trainer_user_id', $trainerId)
            ->first();
        if (!$row) {
            return $this->defaultPayoutSettings();
        }

        $frequency = in_array($row->payout_frequency ?? null, ['weekly', 'biweekly', 'monthly'], true)
            ? (string) $row->payout_frequency
            : 'monthly';

        $out = [
            'account_holder_first_name' => (string) ($row->account_holder_first_name ?? ''),
            'account_holder_last_name' => (string) ($row->account_holder_last_name ?? ''),
            'account_holder_name' => (string) ($row->account_holder_name ?? ''),
            'iban_masked' => (string) ($row->iban_masked ?? ''),
            'iban_last4' => (string) ($row->iban_last4 ?? ''),
            'bank_verification_status' => (string) ($row->status ?? 'pending'),
            'payout_frequency' => $frequency,
            'payout_fee_percent' => $this->payoutFeePercent($frequency),
            'minimum_payout_cents' => (int) ($row->minimum_payout_cents ?? 0),
            'notify_payout_paid' => (bool) ($row->notify_payout_paid ?? true),
            'notify_payout_failed' => (bool) ($row->notify_payout_failed ?? true),
            'next_payout_date' => $this->nextPayoutDate($frequency),
            'updated_at' => $row->updated_at ?? null,
        ];
        if (Schema::hasColumn('gymies_trainer_bank_accounts', 'client_pays_service_fee')) {
            $out['client_pays_service_fee'] = (bool) (int) ($row->client_pays_service_fee ?? 1);
        } else {
            $out['client_pays_service_fee'] = true;
        }
        return $out;
    }

    /**
     * @return array<string,mixed>
     */
    private function defaultPayoutSettings(): array
    {
        $frequency = 'monthly';

        return [
            'account_holder_first_name' => '',
            'account_holder_last_name' => '',
            'account_holder_name' => '',
            'iban_masked' => '',
            'iban_last4' => '',
            'bank_verification_status' => 'pending',
            'payout_frequency' => $frequency,
            'payout_fee_percent' => $this->payoutFeePercent($frequency),
            'minimum_payout_cents' => 0,
            'notify_payout_paid' => true,
            'notify_payout_failed' => true,
            'next_payout_date' => $this->nextPayoutDate($frequency),
            'updated_at' => null,
            'client_pays_service_fee' => true,
        ];
    }

    /**
     * @return array<string,int>
     */
    private function trainerRevenueTotals(int $trainerId): array
    {
        $rows = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->whereNotNull('amount_cents')
            ->get(['id', 'status', 'amount_cents', 'paid_at']);

        $revenueBookingIds = $rows->whereIn('status', ['confirmed', 'completed', 'no_show'])->pluck('id')->all();
        $splitDeduct = [];
        if (!empty($revenueBookingIds) && Schema::hasTable('gymies_admin_refunds')) {
            $splitDeduct = DB::table('gymies_admin_refunds')
                ->where('type', 'split')
                ->whereIn('booking_id', $revenueBookingIds)
                ->pluck('amount_cents', 'booking_id')
                ->map(fn ($c) => (int) $c)
                ->all();
        }

        $total = 0;
        foreach ($rows as $r) {
            if (!in_array((string) $r->status, ['confirmed', 'completed', 'no_show'], true)) {
                continue;
            }
            $amt = (int) ($r->amount_cents ?? 0);
            $total += $amt - ($splitDeduct[(int) $r->id] ?? 0);
        }
        $paid = (int) $rows->whereNotNull('paid_at')->sum('amount_cents');
        $pending = max($total - $paid, 0);
        if (Schema::hasColumn('gymies_users', 'trainer_balance_cents')) {
            $balance = (int) (DB::table('gymies_users')->where('id', $trainerId)->value('trainer_balance_cents') ?? 0);
            if ($balance < 0) {
                $pending = max(0, $pending + $balance);
            }
        }

        return [
            'total_revenue_cents' => $total,
            'paid_revenue_cents' => $paid,
            'pending_payout_cents' => $pending,
        ];
    }

    /**
     * @param array<string,mixed> $settings
     * @return array<string,mixed>
     */
    private function buildPayoutPreview(int $pendingPayoutCents, array $settings): array
    {
        $frequency = (string) ($settings['payout_frequency'] ?? 'monthly');
        $minimum = (int) ($settings['minimum_payout_cents'] ?? 0);
        $feePercent = $this->payoutFeePercent($frequency);
        $feeCents = (int) round($pendingPayoutCents * ($feePercent / 100));
        $netCents = max($pendingPayoutCents - $feeCents, 0);
        $isEligible = $pendingPayoutCents >= $minimum;

        return [
            'gross_cents' => $pendingPayoutCents,
            'fee_cents' => $feeCents,
            'net_cents' => $netCents,
            'fee_percent' => $feePercent,
            'is_eligible' => $isEligible,
            'minimum_payout_cents' => $minimum,
            'remaining_to_minimum_cents' => $isEligible ? 0 : ($minimum - $pendingPayoutCents),
            'next_payout_date' => $this->nextPayoutDate($frequency),
        ];
    }

    private function payoutFeePercent(string $frequency): float
    {
        return self::PAYOUT_FEE_PERCENT[$frequency] ?? 0.0;
    }

    private function looksLikeIban(string $iban): bool
    {
        return (bool) preg_match('/^[A-Z]{2}[0-9A-Z]{6,32}$/', $iban);
    }

    private function maskIban(string $iban): string
    {
        $len = strlen($iban);
        if ($len <= 4) {
            return $iban;
        }
        $start = substr($iban, 0, 4);
        $end = substr($iban, -4);
        $mask = str_repeat('*', max($len - 8, 4));

        return $start . $mask . $end;
    }

    private function nextPayoutDate(string $frequency): string
    {
        $today = CarbonImmutable::now()->startOfDay();

        if ($frequency === 'weekly') {
            return $today->next('monday')->toDateString();
        }

        if ($frequency === 'biweekly') {
            $anchor = CarbonImmutable::create(2025, 1, 6, 0, 0, 0); // maandag
            $candidate = $today->next('monday');
            $weeksFromAnchor = (int) floor($anchor->diffInDays($candidate, false) / 7);
            if ($weeksFromAnchor % 2 !== 0) {
                $candidate = $candidate->addWeek();
            }
            return $candidate->toDateString();
        }

        return $today->addMonthNoOverflow()->startOfMonth()->toDateString();
    }

    /**
     * @return list<string>
     */
    private function nextPayoutDates(string $frequency, int $count): array
    {
        $dates = [];
        $cursor = CarbonImmutable::now()->startOfDay();
        for ($i = 0; $i < $count; $i++) {
            if ($frequency === 'weekly') {
                $cursor = $cursor->next('monday');
            } elseif ($frequency === 'biweekly') {
                $anchor = CarbonImmutable::create(2025, 1, 6, 0, 0, 0);
                $candidate = $cursor->next('monday');
                $weeksFromAnchor = (int) floor($anchor->diffInDays($candidate, false) / 7);
                if ($weeksFromAnchor % 2 !== 0) {
                    $candidate = $candidate->addWeek();
                }
                $cursor = $candidate;
            } else {
                $cursor = $cursor->addMonthNoOverflow()->startOfMonth();
            }
            $dates[] = $cursor->toDateString();
        }

        return $dates;
    }

    private function csvCell(string $value): string
    {
        $escaped = str_replace('"', '""', $value);
        return '"' . $escaped . '"';
    }

    /**
     * @param array<string,mixed>|null $oldValues
     * @param array<string,mixed>|null $newValues
     */
    private function logAudit(int $userId, string $action, string $entityType, ?int $entityId, ?array $oldValues, ?array $newValues): void
    {
        if (!DB::getSchemaBuilder()->hasTable('gymies_audit_log')) {
            return;
        }
        $oldValues = $this->sanitizeAuditPayload($oldValues);
        $newValues = $this->sanitizeAuditPayload($newValues);
        DB::table('gymies_audit_log')->insert([
            'user_id' => $userId,
            'action' => $action,
            'entity_type' => $entityType,
            'entity_id' => $entityId,
            'old_values' => $oldValues ? json_encode($oldValues, JSON_UNESCAPED_UNICODE) : null,
            'new_values' => $newValues ? json_encode($newValues, JSON_UNESCAPED_UNICODE) : null,
            'ip_address' => request()->ip(),
            'created_at' => now(),
        ]);
    }

    /**
     * @param array<string,mixed>|null $payload
     * @return array<string,mixed>|null
     */
    private function sanitizeAuditPayload(?array $payload): ?array
    {
        if ($payload === null) {
            return null;
        }
        $deny = [
            'password',
            'password_hash',
            'token',
            'authorization',
            'iban',
            'iban_masked',
            'iban_last4',
            'context_json',
        ];
        $out = [];
        foreach ($payload as $key => $value) {
            $k = mb_strtolower((string) $key);
            if (in_array($k, $deny, true)) {
                $out[$key] = '[REDACTED]';
                continue;
            }
            if (is_array($value)) {
                $out[$key] = $this->sanitizeAuditPayload($value);
                continue;
            }
            if (is_string($value) && strlen($value) > 500) {
                $out[$key] = mb_substr($value, 0, 500) . '...';
                continue;
            }
            $out[$key] = $value;
        }

        return $out;
    }

    /**
     * @return array<string,mixed>
     */
    private function mediaRowToArray(object $row): array
    {
        $filePath = (string) ($row->file_path ?? '');
        $externalUrl = (string) ($row->external_url ?? '');
        $url = $externalUrl !== '' ? $externalUrl : $filePath;
        if ($filePath !== '' && !str_starts_with($filePath, 'http')) {
            $url = url($filePath);
        }

        return [
            'id' => (string) $row->id,
            'trainer_user_id' => (string) $row->trainer_user_id,
            'media_type' => (string) ($row->media_type ?? 'image'),
            'source_type' => (string) ($row->source_type ?? 'external'),
            'url' => $url,
            'thumbnail_url' => $row->thumbnail_url,
            'caption' => $row->caption,
            'is_public' => (bool) ($row->is_public ?? false),
            'sort_order' => (int) ($row->sort_order ?? 0),
            'created_at' => $row->created_at ?? null,
        ];
    }

    private function saveBase64Image(string $input): ?string
    {
        if ($input === '') {
            return null;
        }

        $mime = null;
        $data = $input;
        if (str_contains($input, ',')) {
            [$prefix, $payload] = explode(',', $input, 2);
            $data = $payload;
            if (preg_match('/^data:(image\\/[a-zA-Z0-9.+-]+);base64$/', $prefix, $m)) {
                $mime = strtolower($m[1]);
            }
        }
        if ($mime !== null && !in_array($mime, ['image/jpeg', 'image/png', 'image/webp'], true)) {
            return null;
        }

        $bin = base64_decode($data, true);
        if ($bin === false) {
            return null;
        }
        if (strlen($bin) > (5 * 1024 * 1024)) { // 5MB
            return null;
        }

        $ext = 'jpg';
        if ($mime === 'image/png') {
            $ext = 'png';
        } elseif ($mime === 'image/webp') {
            $ext = 'webp';
        }

        $dir = public_path('gymies-media');
        if (!is_dir($dir)) {
            @mkdir($dir, 0775, true);
        }
        $name = Str::uuid()->toString() . '.' . $ext;
        $absolute = $dir . DIRECTORY_SEPARATOR . $name;
        if (@file_put_contents($absolute, $bin) === false) {
            return null;
        }

        return '/gymies-media/' . $name;
    }
}

