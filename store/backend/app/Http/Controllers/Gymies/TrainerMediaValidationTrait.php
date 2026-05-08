<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;

/**
 * Valideert video-uploads voor trainer profiel-media.
 * Video's mogen max. 30 seconden zijn.
 *
 * Gebruik in storeMedia():
 *   $this->validateVideoDuration($uploadedFile);
 */
trait TrainerMediaValidationTrait
{
    /** Max videoduur in seconden voor profiel-media. */
    protected int $trainerMediaMaxVideoSeconds = 30;

    /**
     * Gooit ValidationException als de video langer is dan toegestaan.
     *
     * @param  UploadedFile  $file  Het geüploade videobestand
     * @throws ValidationException
     */
    protected function validateVideoDuration(UploadedFile $file): void
    {
        $mime = $file->getMimeType();
        $isVideo = str_starts_with($mime, 'video/') || in_array(
            strtolower($file->getClientOriginalExtension()),
            ['mp4', 'mov', 'webm', 'mkv', 'avi', 'm4v']
        );

        if (! $isVideo) {
            return; // Geen video, skip validatie
        }

        $duration = $this->getVideoDurationSeconds($file->getRealPath());

        if ($duration !== null && $duration > $this->trainerMediaMaxVideoSeconds) {
            throw ValidationException::withMessages([
                'file' => [
                    "Video mag maximaal {$this->trainerMediaMaxVideoSeconds} seconden zijn op je profiel.",
                ],
            ]);
        }
    }

    /**
     * Haalt de videoduur in seconden op via ffprobe of getID3.
     *
     * @return float|null Duur in seconden, of null als niet te bepalen
     */
    protected function getVideoDurationSeconds(string $path): ?float
    {
        if (! is_file($path) || ! is_readable($path)) {
            return null;
        }

        // 1. Probeer ffprobe (van ffmpeg)
        $duration = $this->getDurationViaFfprobe($path);
        if ($duration !== null) {
            return $duration;
        }

        // 2. Fallback: getID3 indien beschikbaar
        if (class_exists(\getID3::class)) {
            return $this->getDurationViaGetId3($path);
        }

        return null;
    }

    private function getDurationViaFfprobe(string $path): ?float
    {
        $escaped = escapeshellarg($path);
        $cmd = "ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 {$escaped} 2>/dev/null";

        $output = @shell_exec($cmd);
        if ($output === null || $output === '') {
            return null;
        }

        $trimmed = trim($output);
        $value = filter_var($trimmed, FILTER_VALIDATE_FLOAT);

        return $value !== false ? (float) $value : null;
    }

    private function getDurationViaGetId3(string $path): ?float
    {
        try {
            $getID3 = new \getID3();
            $info = $getID3->analyze($path);

            if (isset($info['playtime_seconds']) && is_numeric($info['playtime_seconds'])) {
                return (float) $info['playtime_seconds'];
            }
        } catch (\Throwable $e) {
            // ignore
            Log::warning('Failed to get video duration via getID3 for ' . basename($path) . ': ' . $e->getMessage());
        }

        return null;
    }
}
