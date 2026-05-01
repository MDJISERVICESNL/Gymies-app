<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use App\Http\Controllers\Gymies\Traits\TrainerRevenueTrait;
use App\Http\Controllers\Gymies\Traits\TrainerMessagingTrait;
use App\Http\Controllers\Gymies\Traits\TrainerClientsTrait;
use App\Http\Controllers\Gymies\Traits\TrainerSessionsTrait;
use App\Http\Traits\GymiesSchemaCacheTrait;
use App\Traits\GymiesRequireTrainerTrait;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use App\Helpers\GymiesChatBroadcast;

/**
 * Trainer operationele endpoints: inkomsten en berichten.
 */
final class GymiesTrainerOpsController extends Controller
{
    use GymiesSchemaCacheTrait;
    use GymiesRequireTrainerTrait;
    use TrainerRevenueTrait;
    use TrainerMessagingTrait;
    use TrainerClientsTrait;
    use TrainerSessionsTrait;

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

    /**
     * Transformation Log: nieuwe meting toevoegen.
     */

    /**
     * Klantenbestand: alle klanten met minstens één boeking bij deze trainer.
     * Zoek op naam/e-mail; filter op datum: session_date (YYYY-MM-DD) = klanten die op die datum hebben getraind.
     */

    /**
     * CRM: klanten met resterende strippenkaart-sessies bij deze trainer maar X dagen niet geboekt.
     * Bron: gymies_packages + boekingen met package_id (geen wallet).
     */

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
        if (!$this->tableExists('trainer_upsell_suggestions')) {
            return response()->json(['message' => 'Upsell suggesties tabel ontbreekt.'], 503);
        }
        if (!ctype_digit($suggestionId)) {
            return response()->json(['message' => 'Ongeldige suggestie.'], 422);
        }
        $id = (int) $suggestionId;
        $target = DB::table('trainer_upsell_suggestions')
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
            DB::table('trainer_upsell_suggestions')->where('id', $id)->update([
                'status' => 'sent',
                'sent_at' => now(),
                'updated_at' => now(),
            ]);
        }

        if ($this->tableExists('gymies_trainer_upsell_suggestion_sends') && !$alreadySent) {
            DB::table('gymies_trainer_upsell_suggestion_sends')->insert([
                'suggestion_id' => (string) $id,
                'trainer_user_id' => $trainerId,
                'client_user_id' => $clientUserId,
                'package_id' => $packageId,
                'reason' => (string) ($target->reason ?? ''),
                'created_at' => now(),
            ]);
        }

        if ($this->tableExists('gymies_notification_queue') && !$alreadySent) {
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
        if (!$this->tableExists('trainer_rebook_suggestions')) {
            return response()->json(['data' => []]);
        }
        $this->seedRebookSuggestions($trainerId);
        $rows = DB::table('trainer_rebook_suggestions')
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
        if (!$this->tableExists('trainer_rebook_suggestions')) {
            return response()->json(['message' => 'Rebook suggesties tabel ontbreekt.'], 503);
        }
        if (!ctype_digit($suggestionId)) {
            return response()->json(['message' => 'Ongeldige suggestie.'], 422);
        }
        $id = (int) $suggestionId;
        $row = DB::table('trainer_rebook_suggestions')
            ->where('id', $id)
            ->where('trainer_user_id', $trainerId)
            ->first();
        if (!$row) {
            return response()->json(['message' => 'Suggestie niet gevonden.'], 404);
        }
        $alreadySent = ((string) ($row->status ?? '')) === 'sent' && $row->sent_at !== null;
        if (!$alreadySent) {
            DB::table('trainer_rebook_suggestions')->where('id', $id)->update([
                'status' => 'sent',
                'sent_at' => now(),
                'updated_at' => now(),
            ]);
            if ($this->tableExists('gymies_notification_queue')) {
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

    /**
     * CRM dossier: PUT — upsert notities (max lengte beperkt tegen abuse).
     */

    /**
     * Session Entry timeline per klant (first-class resource).
     */

    /**
     * Bulk in-app bericht naar geselecteerde klanten (queue). Alleen klanten met boeking bij deze trainer.
     * Max 25 per request. Payload message wordt in notificatie getoond (trainer_personal_nudge).
     */

    /**
     * Stuur aanbieding/promo naar alle klanten die jou als favoriet hebben.
     * POST /trainer/promo-to-favorites { message, discount_code? }
     */

    /**
     * Sessienotitie na afloop: upsert op booking_id (één note per boeking).
     */

    /**
     * Lijst sessienotities voor klant (laatste eerst), alleen boekingen van deze trainer.
     */

    /**
     * Fee Switcher alleen (geen volledige bankpayload nodig).
     */

    /**
     * @deprecated Payouts verlopen nu volledig via Mollie Connect (application fees + automatic splits).
     * Dit endpoint is behouden zodat oudere app-versies niet crashen (410 Gone).
     */

    /**
     * Trainer meldt dat hij aan het typen is; broadcast naar klant.
     */

    /**
     * Contextuele header voor chat (trainer): resterende strippen, duo-status placeholder.
     * Zelfde bron als sleepingClients — packages + package_id op boekingen.
     */

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
                if ($this->columnExists('gymies_bookings', 'payment_method')) {
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
        if (!$this->tableExists('gymies_trainer_storefront')) {
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
                'instagram_handle' => $this->columnExists('gymies_trainer_storefront', 'instagram_handle') ? ($row->instagram_handle ?? null) : null,
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
        if (!$this->tableExists('gymies_trainer_storefront')) {
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
        if ($this->columnExists('gymies_trainer_storefront', 'instagram_handle')) {
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
        if ($payload['video_pitch_url'] && $this->columnExists('gymies_trainer_profiles', 'intro_video_url')) {
            DB::table('gymies_trainer_profiles')->where('user_id', $trainerId)->update([
                'intro_video_url' => $payload['video_pitch_url'],
                'updated_at' => now(),
            ]);
        }
        return $this->storefrontCmsGet($request);
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
        if (!$this->tableExists('gymies_promo_codes')) {
            return response()->json(['data' => []]);
        }
        if (!$this->columnExists('gymies_promo_codes', 'trainer_user_id')) {
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
        if (!$this->tableExists('gymies_promo_codes') || !$this->columnExists('gymies_promo_codes', 'trainer_user_id')) {
            GymiesSchemaEnsure::promoCodesTrainerColumn();
        }
        if (!$this->tableExists('gymies_promo_codes') || !$this->columnExists('gymies_promo_codes', 'trainer_user_id')) {
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
        if (!ctype_digit($id) || (int) $id < 1) {
            return response()->json(['message' => 'Ongeldige code.'], 422);
        }
        if (!$this->tableExists('gymies_promo_codes') || !$this->columnExists('gymies_promo_codes', 'trainer_user_id')) {
            GymiesSchemaEnsure::promoCodesTrainerColumn();
        }
        if (!$this->tableExists('gymies_promo_codes') || !$this->columnExists('gymies_promo_codes', 'trainer_user_id')) {
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
        if (!ctype_digit($id) || (int) $id < 1) {
            return response()->json(['message' => 'Ongeldige code.'], 422);
        }
        if (!$this->tableExists('gymies_promo_codes') || !$this->columnExists('gymies_promo_codes', 'trainer_user_id')) {
            GymiesSchemaEnsure::promoCodesTrainerColumn();
        }
        if (!$this->tableExists('gymies_promo_codes') || !$this->columnExists('gymies_promo_codes', 'trainer_user_id')) {
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
        if (!$this->tableExists('gymies_bookings')) {
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

            if ($this->tableExists('trainer_client_health_scores')) {
                DB::table('trainer_client_health_scores')->updateOrInsert(
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
        if (!$this->tableExists('trainer_upsell_suggestions')) {
            return [];
        }
        $this->seedUpsellSuggestions($trainerId);

        $rows = DB::table('trainer_upsell_suggestions')
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
        if ($this->tableExists('gymies_packages')) {
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

    private function seedUpsellSuggestions(int $trainerId): void
    {
        if (!$this->tableExists('trainer_upsell_suggestions') || !$this->tableExists('gymies_packages')) {
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
            $exists = DB::table('trainer_upsell_suggestions')
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
            DB::table('trainer_upsell_suggestions')->insert([
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
        if (!$this->tableExists('trainer_rebook_suggestions') || !$this->tableExists('trainer_client_health_scores') || !$this->tableExists('gymies_bookings')) {
            return;
        }
        $healthRows = DB::table('trainer_client_health_scores')
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
            $exists = DB::table('trainer_rebook_suggestions')
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
            DB::table('trainer_rebook_suggestions')->insert([
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

    /**
     * @param list<string> $dates yyyy-mm-dd
     */

    /**
     * @return array<string,mixed>
     */

    /**
     * @return array<string,mixed>
     */

    /**
     * @return array<string,int>
     */

    /**
     * @param array<string,mixed> $settings
     * @return array<string,mixed>
     */

    /**
     * @return list<string>
     */

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
            \Log::debug('saveBase64Image: lege input');
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
            \Log::warning('saveBase64Image: ongeldig MIME-type', ['mime' => $mime]);
            return null;
        }

        $bin = base64_decode($data, true);
        if ($bin === false) {
            \Log::warning('saveBase64Image: base64 decode mislukt');
            return null;
        }
        if (strlen($bin) > (5 * 1024 * 1024)) { // 5MB
            \Log::warning('saveBase64Image: bestand te groot', ['bytes' => strlen($bin)]);
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
            \Log::error('saveBase64Image: schrijven naar disk mislukt', ['path' => $absolute]);
            return null;
        }

        return '/gymies-media/' . $name;
    }

    public function setMediaFeatured(Request $request, string $mediaId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) return $user;
        if (!$this->tableExists('gymies_trainer_media')) {
            return response()->json(['message' => 'Media niet beschikbaar.'], 404);
        }
        // Unset all featured first
        DB::table('gymies_trainer_media')
            ->where('trainer_user_id', $user->id)
            ->update(['is_featured' => false]);
        // Set this one as featured
        $updated = DB::table('gymies_trainer_media')
            ->where('id', $mediaId)
            ->where('trainer_user_id', $user->id)
            ->update(['is_featured' => true, 'updated_at' => now()]);
        if (!$updated) {
            return response()->json(['message' => 'Media niet gevonden.'], 404);
        }
        return response()->json(['ok' => true, 'message' => 'Media ingesteld als uitgelicht.']);
    }

    public function bulkDeleteMedia(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) return $user;
        $ids = $request->input('media_ids', []);
        if (empty($ids) || !is_array($ids)) {
            return response()->json(['message' => 'Geen media_ids opgegeven.'], 422);
        }
        if (!$this->tableExists('gymies_trainer_media')) {
            return response()->json(['message' => 'Media niet beschikbaar.'], 404);
        }
        $deleted = DB::table('gymies_trainer_media')
            ->whereIn('id', $ids)
            ->where('trainer_user_id', $user->id)
            ->delete();
        return response()->json(['ok' => true, 'deleted_count' => $deleted]);
    }

    public function promoCodeStats(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) return $user;
        if (!$this->tableExists('gymies_promo_codes')) {
            return response()->json(['data' => []]);
        }
        $stats = DB::table('gymies_promo_codes')
            ->where('trainer_user_id', $user->id)
            ->select(
                DB::raw('COUNT(*) as total_codes'),
                DB::raw('SUM(COALESCE(redemption_count, 0)) as total_redemptions'),
                DB::raw('SUM(CASE WHEN valid_until IS NOT NULL AND valid_until < NOW() THEN 1 ELSE 0 END) as expired_codes')
            )
            ->first();
        return response()->json(['data' => $stats ?? (object)['total_codes' => 0, 'total_redemptions' => 0, 'expired_codes' => 0]]);
    }

    public function packagesExpiringSoon(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) return $user;
        if (!$this->tableExists('gymies_client_packages')) {
            return response()->json(['data' => []]);
        }
        $hasExpiresAt = $this->columnExists('gymies_client_packages', 'expires_at');
        if (!$hasExpiresAt) {
            return response()->json(['data' => []]);
        }
        $items = DB::table('gymies_client_packages as cp')
            ->join('gymies_users as u', 'u.id', '=', 'cp.client_user_id')
            ->where('cp.trainer_user_id', $user->id)
            ->where('cp.expires_at', '<=', now()->addDays(14))
            ->where('cp.expires_at', '>', now())
            ->whereRaw('cp.sessions_remaining > 0')
            ->select('cp.*', 'u.display_name as client_name')
            ->orderBy('cp.expires_at')
            ->limit(50)
            ->get();
        return response()->json(['data' => $items]);
    }

    public function clientSessionNotesStore(Request $request, string $clientUserId): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) return $user;
        $validated = $request->validate([
            'body' => 'required|string|max:5000',
            'title' => 'nullable|string|max:255',
            'booking_id' => 'nullable|integer',
        ]);
        if (!$this->tableExists('gymies_session_notes')) {
            return response()->json(['message' => 'Sessienotities niet beschikbaar.'], 404);
        }
        $noteData = [
            'trainer_user_id' => (int) $user->id,
            'client_user_id' => (int) $clientUserId,
            'body' => $validated['body'],
            'created_at' => now(),
            'updated_at' => now(),
        ];
        if ($this->columnExists('gymies_session_notes', 'title')) {
            $noteData['title'] = $validated['title'] ?? null;
        }
        if (isset($validated['booking_id']) && $this->columnExists('gymies_session_notes', 'booking_id')) {
            $noteData['booking_id'] = $validated['booking_id'];
        }
        $id = DB::table('gymies_session_notes')->insertGetId($noteData);
        $note = DB::table('gymies_session_notes')->where('id', $id)->first();
        return response()->json(['data' => $note], 201);
    }

    // ── Annuleringsbeleid CRUD ──────────────────────────────────────────

    /**
     * GET trainer/cancellation-policies — toon alle annuleringsregels van de trainer.
     */
    public function cancellationPolicies(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) return $user;
        if (!$this->tableExists('gymies_cancellation_policies')) {
            return response()->json(['data' => []]);
        }
        $policies = DB::table('gymies_cancellation_policies')
            ->where('trainer_user_id', $user->id)
            ->orderBy('hours_before', 'desc')
            ->get();
        return response()->json(['data' => $policies]);
    }

    /**
     * POST trainer/cancellation-policies — maak een nieuwe annuleringsregel aan.
     */
    public function storeCancellationPolicy(Request $request): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) return $user;
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'hours_before' => 'required|integer|min:0|max:720',
            'refund_percent' => 'required|integer|min:0|max:100',
        ]);
        if (!$this->tableExists('gymies_cancellation_policies')) {
            return response()->json(['message' => 'Annuleringsbeleid niet beschikbaar.'], 500);
        }
        // Max 5 regels per trainer
        $count = DB::table('gymies_cancellation_policies')->where('trainer_user_id', $user->id)->count();
        if ($count >= 5) {
            return response()->json(['message' => 'Maximaal 5 annuleringsregels toegestaan.'], 422);
        }
        // Geen duplicate hours_before voor dezelfde trainer
        $exists = DB::table('gymies_cancellation_policies')
            ->where('trainer_user_id', $user->id)
            ->where('hours_before', $validated['hours_before'])
            ->exists();
        if ($exists) {
            return response()->json(['message' => "Er bestaat al een regel voor {$validated['hours_before']} uur."], 422);
        }
        $id = DB::table('gymies_cancellation_policies')->insertGetId([
            'trainer_user_id' => (int) $user->id,
            'name' => $validated['name'],
            'hours_before' => $validated['hours_before'],
            'refund_percent' => $validated['refund_percent'],
            'created_at' => now(),
            'updated_at' => now(),
        ]);
        $policy = DB::table('gymies_cancellation_policies')->where('id', $id)->first();
        return response()->json(['data' => $policy], 201);
    }

    /**
     * PUT trainer/cancellation-policies/{id} — wijzig een bestaande annuleringsregel.
     */
    public function updateCancellationPolicy(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) return $user;
        $validated = $request->validate([
            'name' => 'sometimes|string|max:255',
            'hours_before' => 'sometimes|integer|min:0|max:720',
            'refund_percent' => 'sometimes|integer|min:0|max:100',
        ]);
        if (!$this->tableExists('gymies_cancellation_policies')) {
            return response()->json(['message' => 'Annuleringsbeleid niet beschikbaar.'], 500);
        }
        $policy = DB::table('gymies_cancellation_policies')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->first();
        if (!$policy) {
            return response()->json(['message' => 'Regel niet gevonden.'], 404);
        }
        // Check duplicate hours_before (exclude self)
        if (isset($validated['hours_before'])) {
            $exists = DB::table('gymies_cancellation_policies')
                ->where('trainer_user_id', $user->id)
                ->where('hours_before', $validated['hours_before'])
                ->where('id', '!=', $id)
                ->exists();
            if ($exists) {
                return response()->json(['message' => "Er bestaat al een regel voor {$validated['hours_before']} uur."], 422);
            }
        }
        $validated['updated_at'] = now();
        DB::table('gymies_cancellation_policies')->where('id', $id)->update($validated);
        $updated = DB::table('gymies_cancellation_policies')->where('id', $id)->first();
        return response()->json(['data' => $updated]);
    }

    /**
     * DELETE trainer/cancellation-policies/{id} — verwijder een annuleringsregel.
     */
    public function deleteCancellationPolicy(Request $request, string $id): JsonResponse
    {
        $user = $this->requireTrainer($request);
        if ($user instanceof JsonResponse) return $user;
        if (!$this->tableExists('gymies_cancellation_policies')) {
            return response()->json(['message' => 'Annuleringsbeleid niet beschikbaar.'], 500);
        }
        $deleted = DB::table('gymies_cancellation_policies')
            ->where('id', $id)
            ->where('trainer_user_id', $user->id)
            ->delete();
        if (!$deleted) {
            return response()->json(['message' => 'Regel niet gevonden.'], 404);
        }
        return response()->json(['ok' => true, 'message' => 'Regel verwijderd.']);
    }

    // ─── Revenue Dashboard ───────────────────────────────────────────

    /**
     * Trainer omzetoverzicht: bruto, fees, netto, refunds per periode.
     * Optioneel: ?period=month|week|year (default: month)
     */
    public function revenue(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user || $user->role !== 'trainer') {
            return response()->json(['message' => 'Alleen trainers.'], 403);
        }

        $period = $request->query('period', 'month');
        $startDate = match ($period) {
            'week' => now()->startOfWeek(),
            'year' => now()->startOfYear(),
            default => now()->startOfMonth(),
        };

        $trainerUserId = (int) $user->id;

        // Booking transacties
        $bookingRevenue = ['count' => 0, 'gross_cents' => 0, 'refunded_cents' => 0];
        if (Schema::hasTable('gymies_payment_transactions')) {
            $bookingTx = DB::table('gymies_payment_transactions')
                ->where('counterparty_user_id', $trainerUserId)
                ->where('status', 'paid')
                ->where('created_at', '>=', $startDate)
                ->selectRaw('COUNT(*) as cnt, COALESCE(SUM(amount_cents), 0) as total')
                ->first();
            $bookingRevenue['count'] = (int) ($bookingTx->cnt ?? 0);
            $bookingRevenue['gross_cents'] = (int) ($bookingTx->total ?? 0);

            // Refunds in deze periode
            if (Schema::hasTable('gymies_refunds')) {
                $refundTotal = (int) DB::table('gymies_refunds')
                    ->where('trainer_user_id', $trainerUserId)
                    ->whereIn('status', ['completed', 'processing'])
                    ->where('created_at', '>=', $startDate)
                    ->sum('refund_amount_cents');
                $bookingRevenue['refunded_cents'] = $refundTotal;
            }
        }

        // Groepssessie revenue
        $groupRevenue = ['count' => 0, 'gross_cents' => 0];
        if (Schema::hasTable('gymies_payment_transactions')) {
            $groupTx = DB::table('gymies_payment_transactions')
                ->where('counterparty_user_id', $trainerUserId)
                ->where('status', 'paid')
                ->whereNotNull('group_participant_id')
                ->where('created_at', '>=', $startDate)
                ->selectRaw('COUNT(*) as cnt, COALESCE(SUM(amount_cents), 0) as total')
                ->first();
            $groupRevenue['count'] = (int) ($groupTx->cnt ?? 0);
            $groupRevenue['gross_cents'] = (int) ($groupTx->total ?? 0);
        }

        // Fee berekening (geschat: we weten de fee config)
        $feeConfig = $this->getTrainerFeeConfig($trainerUserId);
        $totalGross = $bookingRevenue['gross_cents'];
        $estimatedFees = 0;
        if ($feeConfig['type'] === 'percent') {
            $estimatedFees = (int) round($totalGross * $feeConfig['value'] / 10000);
        } else {
            $estimatedFees = $bookingRevenue['count'] * $feeConfig['value'];
        }

        $netRevenue = $totalGross - $estimatedFees - $bookingRevenue['refunded_cents'];

        return response()->json([
            'data' => [
                'period' => $period,
                'start_date' => $startDate->toDateString(),
                'bookings' => $bookingRevenue,
                'group_sessions' => $groupRevenue,
                'fees' => [
                    'type' => $feeConfig['type'],
                    'value' => $feeConfig['value'],
                    'estimated_total_cents' => $estimatedFees,
                    'client_pays' => $feeConfig['client_pays'],
                ],
                'totals' => [
                    'gross_cents' => $totalGross,
                    'fees_cents' => $estimatedFees,
                    'refunded_cents' => $bookingRevenue['refunded_cents'],
                    'net_cents' => max(0, $netRevenue),
                ],
            ],
        ]);
    }

    /**
     * Haal fee configuratie op voor trainer.
     */
    private function getTrainerFeeConfig(int $trainerUserId): array
    {
        $default = ['type' => 'fixed', 'value' => (int) config('gymies.service_fee_cents', 49), 'client_pays' => true];

        GymiesSchemaEnsure::feeSettingsTable();
        if (!Schema::hasTable('gymies_fee_settings')) {
            return $default;
        }

        $setting = DB::table('gymies_fee_settings')
            ->where('trainer_user_id', $trainerUserId)
            ->where('is_active', 1)
            ->first();

        if (!$setting) {
            // Check plan-based
            $planSlug = null;
            if (Schema::hasTable('gymies_subscriptions') && Schema::hasTable('gymies_plans')) {
                $planSlug = DB::table('gymies_subscriptions as s')
                    ->join('gymies_plans as p', 'p.id', '=', 's.plan_id')
                    ->where('s.trainer_user_id', $trainerUserId)
                    ->whereIn('s.status', ['active', 'trialing'])
                    ->value('p.slug');
            }
            if ($planSlug) {
                $setting = DB::table('gymies_fee_settings')
                    ->whereNull('trainer_user_id')
                    ->where('plan_slug', $planSlug)
                    ->where('is_active', 1)
                    ->first();
            }
        }

        if (!$setting) {
            return $default;
        }

        return [
            'type' => $setting->fee_type,
            'value' => (int) $setting->fee_value,
            'client_pays' => (int) $setting->client_pays === 1,
        ];
    }
}

