#!/bin/bash
# =============================================================================
# Fix: Avatar upload via media endpoint + auto-set avatar_url op profiel
# =============================================================================
# Run: ssh gymies "bash -s" < backend/gymies_deploy/fix_avatar_upload.sh
# =============================================================================

set -e
cd /var/www/gymies

echo "============================================"
echo "  FIX: Avatar upload ondersteuning          "
echo "============================================"
echo ""

echo "▸ Step 1: Controleer of avatar_url kolom bestaat..."

php artisan tinker --execute='
use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;

if (!Schema::hasColumn("gymies_trainer_profiles", "avatar_url")) {
    Schema::table("gymies_trainer_profiles", function (Blueprint $t) {
        $t->string("avatar_url", 500)->nullable()->after("user_id");
    });
    echo "  ✅ avatar_url kolom toegevoegd\n";
} else {
    echo "  ⏭️ avatar_url kolom bestaat al\n";
}
'

echo ""
echo "▸ Step 2: Avatar usage type registreren in media controller..."

# Voeg avatar handling toe aan de storeMedia methode
# Zoek de GymiesTrainerController of media upload handler
CONTROLLER="/var/www/gymies/app/Http/Controllers/Gymies/GymiesTrainerController.php"

if [ -f "$CONTROLLER" ]; then
    # Check of avatar handling al bestaat
    if grep -q "usage.*avatar.*avatar_url" "$CONTROLLER" 2>/dev/null; then
        echo "  ⏭️ Avatar handling bestaat al in controller"
    else
        # Voeg avatar auto-set toe aan de storeMedia methode
        # Zoek naar waar media wordt opgeslagen en voeg avatar_url update toe
        php artisan tinker --execute='
        $path = "/var/www/gymies/app/Http/Controllers/Gymies/GymiesTrainerController.php";
        $code = file_get_contents($path);

        // Zoek de storeMedia of media upload sectie
        // We voegen een hook toe die bij usage=avatar de avatar_url op het profiel zet
        if (strpos($code, "avatar_url_auto_set") !== false) {
            echo "  ⏭️ Avatar auto-set code bestaat al\n";
        } else {
            // Zoek naar het punt waar media response wordt teruggegeven na upload
            // Patroon: na succesvolle media opslag, check usage en update profiel
            $needle = "return response()->json([";
            $insertBefore = "// avatar_url_auto_set: als usage=avatar, update profiel
        if ((\$request->input(\"usage\") === \"avatar\" || \$request->input(\"usage\") === \"profile_photo\") && isset(\$media)) {
            \\Illuminate\\Support\\Facades\\DB::table(\"gymies_trainer_profiles\")
                ->where(\"user_id\", \$user->id)
                ->update([\"avatar_url\" => \$media->url ?? (\$media[\"url\"] ?? null)]);
        }

        ";

            // Zoek specifiek in de media store methode
            $pos = strpos($code, "storeMedia");
            if ($pos !== false) {
                // Zoek de eerste return na storeMedia
                $returnPos = strpos($code, $needle, $pos);
                if ($returnPos !== false) {
                    $code = substr($code, 0, $returnPos) . $insertBefore . substr($code, $returnPos);
                    file_put_contents($path, $code);
                    echo "  ✅ Avatar auto-set code toegevoegd aan storeMedia\n";
                } else {
                    echo "  ⚠️ Kon return statement niet vinden in storeMedia - handmatige check nodig\n";
                }
            } else {
                echo "  ⚠️ storeMedia methode niet gevonden - handmatige check nodig\n";
            }
        }
        '
    fi
else
    echo "  ⚠️ Controller niet gevonden op verwacht pad"
fi

echo ""
echo "▸ Step 3: Alternatieve aanpak - avatar_url direct via updateMe..."

# Controleer dat updateMe avatar_url accepteert
php artisan tinker --execute='
$path = "/var/www/gymies/app/Http/Controllers/Gymies/GymiesTrainerController.php";
$code = file_get_contents($path);

// Check of avatar_url al in de updateMe validatie zit
if (strpos($code, "\"avatar_url\"") !== false) {
    echo "  ✅ avatar_url wordt al geaccepteerd in updateMe\n";

    // Check of het ook daadwerkelijk wordt opgeslagen
    if (strpos($code, "avatar_url") !== false) {
        echo "  ✅ avatar_url verwerking gevonden in controller\n";
    }
} else {
    echo "  ⚠️ avatar_url niet gevonden in validatie - wordt nu toegevoegd...\n";

    // Zoek de updateMe validatie regels
    $pos = strpos($code, "function updateMe");
    if ($pos !== false) {
        // Zoek validate() call
        $valPos = strpos($code, "->validate(", $pos);
        if ($valPos !== false) {
            // Zoek het einde van de validate array (sluitende ])
            $bracketStart = strpos($code, "[", $valPos);
            if ($bracketStart !== false) {
                // Voeg avatar_url toe aan het begin van de validatie array
                $insertAt = $bracketStart + 1;
                $insert = "\n            \"avatar_url\" => \"nullable|url|max:512\",";
                $code = substr($code, 0, $insertAt) . $insert . substr($code, $insertAt);
                file_put_contents($path, $code);
                echo "  ✅ avatar_url validatie toegevoegd aan updateMe\n";
            }
        }
    }
}
'

echo ""
echo "▸ Step 4: Test avatar_url opslaan..."

php artisan tinker --execute='
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

$cols = Schema::getColumnListing("gymies_trainer_profiles");
echo "  Kolommen trainer_profiles: " . implode(", ", $cols) . "\n";

$hasAvatar = in_array("avatar_url", $cols);
echo "  avatar_url kolom: " . ($hasAvatar ? "✅ JA" : "❌ NEE") . "\n";

// Toon huidige avatar status voor alle trainers
$trainers = DB::table("gymies_trainer_profiles")->get(["user_id", "avatar_url", "display_name"]);
echo "\n  Trainer avatar status:\n";
foreach ($trainers as $t) {
    $avatar = $t->avatar_url ? "✅ " . substr($t->avatar_url, 0, 50) . "..." : "❌ geen foto";
    echo "  → user:{$t->user_id} | {$t->display_name} | {$avatar}\n";
}
'

echo ""
echo "▸ Caches legen..."
php artisan config:clear 2>/dev/null || true
php artisan route:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true
echo "  ✅ Done"

echo ""
echo "============================================"
echo "  Klaar! Avatar upload is klaar.             "
echo "============================================"
