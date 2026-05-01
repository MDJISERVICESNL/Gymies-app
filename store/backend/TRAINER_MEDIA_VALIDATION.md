# Trainer Media – Video validatie (max 30 sec)

## Overzicht
Videos op het trainerprofiel mogen maximaal **30 seconden** duren. Validatie vindt plaats:
- **Client**: Flutter app controleert duur vóór upload
- **Backend**: Laravel valideert bij ontvangst (dubbel-check)

## Backend-integratie

### 1. Trait gebruiken in GymiesTrainerOpsController

Voeg de trait toe aan je controller:

```php
use App\Http\Controllers\Gymies\TrainerMediaValidationTrait;

class GymiesTrainerOpsController extends Controller
{
    use TrainerMediaValidationTrait;
    // ...
}
```

### 2. storeMedia aanroepen

In je `storeMedia`-methode, vóór het opslaan van het videobestand:

```php
public function storeMedia(Request $request)
{
    $file = $request->file('file'); // of $request->file('video')
    if (!$file) {
        return response()->json(['message' => 'Geen bestand ontvangen.'], 422);
    }

    $mime = $file->getMimeType();
    if (str_starts_with($mime, 'video/')) {
        $this->validateVideoDurationOrFail($file->getRealPath(), 30);
    }

    // ... rest van je upload-logica
}
```

### 3. FFprobe (aanbevolen)

Voor betrouwbare duurcontrole moet **ffprobe** (onderdeel van FFmpeg) op de server beschikbaar zijn:

```bash
# Ubuntu/Debian
sudo apt install ffmpeg

# macOS
brew install ffmpeg
```

Zonder ffprobe wordt validatie overgeslagen en vertrouwt de backend op de client-check.

## Limieten
| Locatie       | Max duur |
|---------------|----------|
| Story         | 30 sec   |
| Media Gallery | 30 sec   |
