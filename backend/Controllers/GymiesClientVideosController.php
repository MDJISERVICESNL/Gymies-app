<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;

/**
 * Per-klant instructievideo's (Pro/Elite).
 * GET  trainer/clients/{clientUserId}/videos – lijst
 * POST trainer/clients/{clientUserId}/videos – upload
 * DELETE trainer/clients/{clientUserId}/videos/{id} – verwijderen
 * GET  me/client-videos – voor klant (alle video's van zijn trainers)
 */
class GymiesClientVideosController
{
    public function index(Request $request, string $clientUserId): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        if (!Schema::hasTable('gymies_client_videos')) {
            return response()->json(['data' => []]);
        }

        $videos = DB::table('gymies_client_videos')
            ->where('trainer_user_id', (int) $user->id)
            ->where('client_user_id', (int) $clientUserId)
            ->orderBy('created_at', 'desc')
            ->get()
            ->map(fn ($r) => [
                'id' => (string) $r->id,
                'url' => $r->url,
                'title' => $r->title ?? 'Video',
                'created_at' => $r->created_at,
            ])
            ->all();

        return response()->json(['data' => $videos]);
    }

    public function store(Request $request, string $clientUserId): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        $file = $request->file('file');
        if (!$file || !$file->isValid()) {
            return response()->json(['message' => 'Geen geldig videobestand ontvangen.'], 422);
        }

        $mime = $file->getMimeType();
        if (!str_starts_with($mime, 'video/')) {
            return response()->json(['message' => 'Alleen video-bestanden zijn toegestaan.'], 422);
        }

        if (!Schema::hasTable('gymies_client_videos')) {
            return response()->json(['message' => 'Client videos tabel ontbreekt.'], 500);
        }

        $trainerId = (int) $user->id;
        $clientId = (int) $clientUserId;

        // FIX-SEC-001: Verify trainer has working relationship with this client before allowing video upload
        if (!Schema::hasTable('gymies_bookings')) {
            return response()->json(['message' => 'Geen relatie met deze klant.'], 403);
        }

        $hasRelation = DB::table('gymies_bookings')
            ->where('trainer_user_id', $trainerId)
            ->where('client_user_id', $clientId)
            ->exists();

        if (!$hasRelation) {
            return response()->json(['message' => 'Geen relatie met deze klant.'], 403);
        }

        $title = trim((string) ($request->input('title') ?? 'Video'));

        $path = $file->store(
            "client-videos/{$trainerId}/{$clientId}",
            'public'
        );

        if (!$path) {
            return response()->json(['message' => 'Upload mislukt.'], 500);
        }

        $url = Storage::disk('public')->url($path);

        $id = DB::table('gymies_client_videos')->insertGetId([
            'trainer_user_id' => $trainerId,
            'client_user_id' => $clientId,
            'url' => $url,
            'title' => $title ?: 'Video',
            'storage_path' => $path,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $row = DB::table('gymies_client_videos')->where('id', $id)->first();

        return response()->json([
            'data' => [
                'id' => (string) $id,
                'url' => $row->url,
                'title' => $row->title ?? 'Video',
                'created_at' => $row->created_at,
            ],
        ], 201);
    }

    public function destroy(Request $request, string $clientUserId, string $id): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        if (!Schema::hasTable('gymies_client_videos')) {
            return response()->json(['message' => 'Client videos tabel ontbreekt.'], 500);
        }

        $row = DB::table('gymies_client_videos')
            ->where('id', (int) $id)
            ->where('trainer_user_id', (int) $user->id)
            ->where('client_user_id', (int) $clientUserId)
            ->first();

        if (!$row) {
            return response()->json(['message' => 'Video niet gevonden.'], 404);
        }

        if ($row->storage_path && Storage::disk('public')->exists($row->storage_path)) {
            Storage::disk('public')->delete($row->storage_path);
        }

        DB::table('gymies_client_videos')->where('id', (int) $id)->delete();

        return response()->json(['message' => 'Video verwijderd.']);
    }

    /** Client: GET me/client-videos – video's van alle trainers van deze klant. */
    public function clientIndex(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        if (!Schema::hasTable('gymies_client_videos')) {
            return response()->json(['data' => []]);
        }

        $videos = DB::table('gymies_client_videos')
            ->where('client_user_id', (int) $user->id)
            ->orderBy('created_at', 'desc')
            ->get()
            ->map(fn ($r) => [
                'id' => (string) $r->id,
                'url' => $r->url,
                'title' => $r->title ?? 'Video',
                'created_at' => $r->created_at,
            ])
            ->all();

        return response()->json(['data' => $videos]);
    }
}
