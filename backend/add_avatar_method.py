content = open("GymiesTrainerController.php").read()

method = '''
    /**
     * Upload profielfoto (avatar).
     */
    public function uploadAvatar(Request $request): JsonResponse
    {
        $user = $request->user();
        if (!$user || !$user->id) {
            return response()->json(["message" => "Niet ingelogd."], 401);
        }
        $request->validate([
            "file" => "required|file|max:5120|mimes:jpg,jpeg,png,webp",
        ]);
        $file = $request->file("file");
        $detectedMime = null;
        $allowedMagicMimes = ["image/jpeg", "image/png", "image/webp"];
        if (function_exists("finfo_open")) {
            $finfo = finfo_open(FILEINFO_MIME_TYPE);
            $detectedMime = finfo_file($finfo, $file->getRealPath());
            finfo_close($finfo);
            if (!in_array($detectedMime, $allowedMagicMimes, true)) {
                return response()->json(["message" => "Alleen JPG, PNG of WebP afbeeldingen."], 422);
            }
        }
        $mimeToExt = ["image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp"];
        $safeExt = $mimeToExt[$detectedMime] ?? "bin";
        $safeName = bin2hex(random_bytes(16)) . "." . $safeExt;
        $path = $file->storeAs("gymies/avatars", $safeName, "public");
        $url = "/storage/" . $path;

        if (Schema::hasTable("gymies_trainer_profiles") && Schema::hasColumn("gymies_trainer_profiles", "avatar_url")) {
            $profile = DB::table("gymies_trainer_profiles")->where("user_id", (int) $user->id)->first();
            if ($profile) {
                DB::table("gymies_trainer_profiles")->where("user_id", (int) $user->id)->update(["avatar_url" => $url, "updated_at" => now()]);
            } else {
                DB::table("gymies_trainer_profiles")->insert(["user_id" => (int) $user->id, "avatar_url" => $url, "created_at" => now()]);
            }
        }
        return response()->json(["avatar_url" => $url, "message" => "Profielfoto geupload"]);
    }
'''

content = content.replace("    public function logSearch", method + "\n    public function logSearch")
open("GymiesTrainerController.php","w").write(content)
print("✅ Methode toegevoegd")
