<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\UploadedFile;
use Illuminate\Validation\ValidationException;

/**
 * Valideert video-uploads voor trainer profiel-media.
 * Video's mogen max. 30 seconden zijn.
 *
 * Gebruik in storeMedia():
 *   $this->validateVideoDuration($uploadedFile);
 *
 * SECURITY: Geen shell_exec/system/exec calls — alles via pure PHP.
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
     * Haalt de videoduur in seconden op via pure PHP (getID3 of MP4 header parsing).
     * Geen shell commands — veilig tegen command injection.
     *
     * @return float|null Duur in seconden, of null als niet te bepalen
     */
    protected function getVideoDurationSeconds(string $path): ?float
    {
        if (! is_file($path) || ! is_readable($path)) {
            return null;
        }

        // 1. Probeer getID3 (pure PHP library)
        if (class_exists(\getID3::class)) {
            return $this->getDurationViaGetId3($path);
        }

        // 2. Fallback: MP4 header parsing (pure PHP)
        return $this->getDurationViaMp4Header($path);
    }

    /**
     * Duur via getID3 library (pure PHP, geen shell commands).
     */
    private function getDurationViaGetId3(string $path): ?float
    {
        try {
            $getID3 = new \getID3();
            $info = $getID3->analyze($path);

            if (isset($info['playtime_seconds']) && is_numeric($info['playtime_seconds'])) {
                return (float) $info['playtime_seconds'];
            }
        } catch (\Throwable) {
            // ignore
        }

        return null;
    }

    /**
     * Simpele MP4/MOV duur-extractie via moov/mvhd atom parsing (pure PHP).
     * Werkt voor de meeste MP4/MOV bestanden zonder externe dependencies.
     */
    private function getDurationViaMp4Header(string $path): ?float
    {
        try {
            $handle = fopen($path, 'rb');
            if ($handle === false) {
                return null;
            }

            $fileSize = filesize($path);
            $offset = 0;

            // Zoek de moov atom in de MP4 container
            while ($offset < $fileSize) {
                fseek($handle, $offset);
                $header = fread($handle, 8);

                if (strlen($header) < 8) {
                    break;
                }

                $size = unpack('N', substr($header, 0, 4))[1];
                $type = substr($header, 4, 4);

                if ($size === 0) {
                    break; // Atom loopt tot einde bestand
                }

                if ($size === 1) {
                    // Extended size (64-bit)
                    $extHeader = fread($handle, 8);
                    if (strlen($extHeader) < 8) {
                        break;
                    }
                    $size = unpack('J', $extHeader)[1];
                }

                if ($type === 'moov') {
                    // Zoek mvhd atom binnen moov
                    $moovEnd = $offset + $size;
                    $innerOffset = $offset + 8;

                    while ($innerOffset < $moovEnd) {
                        fseek($handle, $innerOffset);
                        $innerHeader = fread($handle, 8);

                        if (strlen($innerHeader) < 8) {
                            break;
                        }

                        $innerSize = unpack('N', substr($innerHeader, 0, 4))[1];
                        $innerType = substr($innerHeader, 4, 4);

                        if ($innerSize <= 0) {
                            break;
                        }

                        if ($innerType === 'mvhd') {
                            // Parse mvhd atom voor duur
                            $version = ord(fread($handle, 1));

                            if ($version === 0) {
                                fread($handle, 3); // flags
                                fread($handle, 8); // creation_time + modification_time
                                $timescaleData = fread($handle, 4);
                                $durationData = fread($handle, 4);

                                $timescale = unpack('N', $timescaleData)[1];
                                $duration = unpack('N', $durationData)[1];
                            } elseif ($version === 1) {
                                fread($handle, 3); // flags
                                fread($handle, 16); // creation_time + modification_time (64-bit)
                                $timescaleData = fread($handle, 4);
                                $durationData = fread($handle, 8);

                                $timescale = unpack('N', $timescaleData)[1];
                                $duration = unpack('J', $durationData)[1];
                            } else {
                                fclose($handle);
                                return null;
                            }

                            fclose($handle);

                            if ($timescale > 0) {
                                return (float) ($duration / $timescale);
                            }
                            return null;
                        }

                        $innerOffset += $innerSize;
                    }
                }

                $offset += $size;
            }

            fclose($handle);
        } catch (\Throwable) {
            // ignore
        }

        return null;
    }
}
