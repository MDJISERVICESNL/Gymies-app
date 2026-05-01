<?php

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class GymiesIntakeController extends Controller
{
    /**
     * GET me/intake — klant haalt eigen intake op.
     */
    public function getMyIntake(Request $request): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user) {
            return response()->json(["message" => "Unauthorized"], 401);
        }
        if (!Schema::hasTable("gymies_client_intake_forms")) {
            return response()->json(["data" => null]);
        }
        $row = DB::table("gymies_client_intake_forms")
            ->where("client_user_id", (int) $user->id)
            ->first();
        if (!$row) {
            return response()->json(["data" => null]);
        }
        return response()->json(["data" => (array) $row]);
    }

    /**
     * PUT me/intake — klant vult intake in of update.
     */
    public function updateMyIntake(Request $request): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user) {
            return response()->json(["message" => "Unauthorized"], 401);
        }
        if (!Schema::hasTable("gymies_client_intake_forms")) {
            return response()->json(["message" => "Intake niet beschikbaar."], 503);
        }

        $fields = [
            "fitness_level" => in_array($request->input("fitness_level"), ["beginner", "intermediate", "advanced"], true)
                ? $request->input("fitness_level") : null,
            "goals_text" => mb_substr(trim((string) $request->input("goals_text", "")), 0, 2000) ?: null,
            "injuries_text" => mb_substr(trim((string) $request->input("injuries_text", "")), 0, 2000) ?: null,
            "medical_conditions_text" => mb_substr(trim((string) $request->input("medical_conditions_text", "")), 0, 2000) ?: null,
            "training_frequency_preferred" => is_numeric($request->input("training_frequency_preferred"))
                ? min(max((int) $request->input("training_frequency_preferred"), 0), 14) : null,
            "experience_description" => mb_substr(trim((string) $request->input("experience_description", "")), 0, 2000) ?: null,
            "availability_notes" => mb_substr(trim((string) $request->input("availability_notes", "")), 0, 1000) ?: null,
            "emergency_contact_name" => mb_substr(trim((string) $request->input("emergency_contact_name", "")), 0, 255) ?: null,
            "emergency_contact_phone" => mb_substr(trim((string) $request->input("emergency_contact_phone", "")), 0, 50) ?: null,
        ];

        // Check of intake al bestaat
        $existing = DB::table("gymies_client_intake_forms")
            ->where("client_user_id", (int) $user->id)
            ->first();

        if ($existing) {
            $fields["updated_at"] = now();
            // Als alle velden gevuld zijn, markeer als voltooid
            if ($fields["fitness_level"] && $fields["goals_text"]) {
                $fields["completed_at"] = $existing->completed_at ?? now();
            }
            DB::table("gymies_client_intake_forms")
                ->where("id", $existing->id)
                ->update($fields);
        } else {
            $fields["client_user_id"] = (int) $user->id;
            $fields["created_at"] = now();
            if ($fields["fitness_level"] && $fields["goals_text"]) {
                $fields["completed_at"] = now();
            }
            DB::table("gymies_client_intake_forms")->insert($fields);
        }

        return response()->json(["data" => ["saved" => true]]);
    }

    /**
     * GET trainer/clients/{clientUserId}/intake — trainer leest intake van klant.
     */
    public function getClientIntake(Request $request, string $clientUserId): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user || $user->role !== "trainer") {
            return response()->json(["message" => "Unauthorized"], 403);
        }
        if (!ctype_digit($clientUserId) || (int) $clientUserId < 1) {
            return response()->json(["message" => "Ongeldig klant-ID."], 422);
        }
        if (!Schema::hasTable("gymies_client_intake_forms")) {
            return response()->json(["data" => null]);
        }

        // Verify trainer-client relatie
        $hasBooking = Schema::hasTable("gymies_bookings") && DB::table("gymies_bookings")
            ->where("trainer_user_id", (int) $user->id)
            ->where("client_user_id", (int) $clientUserId)
            ->exists();
        if (!$hasBooking) {
            return response()->json(["message" => "Geen trainer-klant relatie."], 403);
        }

        $row = DB::table("gymies_client_intake_forms")
            ->where("client_user_id", (int) $clientUserId)
            ->first();
        if (!$row) {
            return response()->json(["data" => null]);
        }
        return response()->json(["data" => (array) $row]);
    }
}
