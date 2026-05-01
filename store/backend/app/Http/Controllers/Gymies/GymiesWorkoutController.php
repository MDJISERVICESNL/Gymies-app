<?php

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Controller;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class GymiesWorkoutController extends Controller
{
    public function exerciseLibrary(): JsonResponse
    {
        if (!Schema::hasTable("gymies_exercise_library")) {
            return response()->json(["data" => []]);
        }
        $exercises = DB::table("gymies_exercise_library")->orderBy("name")->get();
        return response()->json(["data" => $exercises->toArray()]);
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user || $user->role !== "trainer") return response()->json(["message" => "Unauthorized"], 403);
        if (!Schema::hasTable("gymies_workout_templates")) return response()->json(["data" => []]);

        $templates = DB::table("gymies_workout_templates")
            ->where("trainer_user_id", (int) $user->id)
            ->orderByDesc("updated_at")
            ->get();

        $result = [];
        foreach ($templates as $t) {
            $exercises = Schema::hasTable("gymies_workout_exercises")
                ? DB::table("gymies_workout_exercises")->where("workout_template_id", $t->id)->orderBy("sort_order")->get()->toArray()
                : [];
            $row = (array) $t;
            $row["exercises"] = $exercises;
            $row["exercise_count"] = count($exercises);
            $result[] = $row;
        }
        return response()->json(["data" => $result]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user || $user->role !== "trainer") return response()->json(["message" => "Unauthorized"], 403);
        if (!Schema::hasTable("gymies_workout_templates")) return response()->json(["message" => "Niet beschikbaar."], 503);

        $title = mb_substr(trim((string) $request->input("title", "")), 0, 255);
        if (empty($title)) return response()->json(["message" => "Titel is verplicht."], 422);

        $templateId = DB::table("gymies_workout_templates")->insertGetId([
            "trainer_user_id" => (int) $user->id,
            "title" => $title,
            "description" => mb_substr(trim((string) $request->input("description", "")), 0, 2000) ?: null,
            "created_at" => now(),
            "updated_at" => now(),
        ]);

        $exercises = $request->input("exercises", []);
        if (is_array($exercises) && Schema::hasTable("gymies_workout_exercises")) {
            foreach ($exercises as $i => $ex) {
                DB::table("gymies_workout_exercises")->insert([
                    "workout_template_id" => $templateId,
                    "exercise_name" => mb_substr(trim((string) ($ex["name"] ?? $ex["exercise_name"] ?? "")), 0, 255),
                    "sets_count" => min(max((int) ($ex["sets"] ?? $ex["sets_count"] ?? 3), 1), 20),
                    "reps" => mb_substr(trim((string) ($ex["reps"] ?? "10")), 0, 50),
                    "rest_seconds" => min(max((int) ($ex["rest_seconds"] ?? $ex["rest"] ?? 60), 0), 600),
                    "weight_kg" => is_numeric($ex["weight_kg"] ?? null) ? round((float) $ex["weight_kg"], 2) : null,
                    "notes" => mb_substr(trim((string) ($ex["notes"] ?? "")), 0, 500) ?: null,
                    "sort_order" => $i,
                    "created_at" => now(),
                ]);
            }
        }

        return response()->json(["data" => ["id" => $templateId, "title" => $title]]);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user || $user->role !== "trainer") return response()->json(["message" => "Unauthorized"], 403);
        if (!ctype_digit($id)) return response()->json(["message" => "Ongeldig ID."], 422);

        $template = DB::table("gymies_workout_templates")
            ->where("id", (int) $id)->where("trainer_user_id", (int) $user->id)->first();
        if (!$template) return response()->json(["message" => "Niet gevonden."], 404);

        $exercises = Schema::hasTable("gymies_workout_exercises")
            ? DB::table("gymies_workout_exercises")->where("workout_template_id", (int) $id)->orderBy("sort_order")->get()->toArray()
            : [];
        $row = (array) $template;
        $row["exercises"] = $exercises;
        return response()->json(["data" => $row]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user || $user->role !== "trainer") return response()->json(["message" => "Unauthorized"], 403);
        if (!ctype_digit($id)) return response()->json(["message" => "Ongeldig ID."], 422);

        $template = DB::table("gymies_workout_templates")
            ->where("id", (int) $id)->where("trainer_user_id", (int) $user->id)->first();
        if (!$template) return response()->json(["message" => "Niet gevonden."], 404);

        $title = mb_substr(trim((string) $request->input("title", $template->title)), 0, 255);
        DB::table("gymies_workout_templates")->where("id", (int) $id)->update([
            "title" => $title,
            "description" => mb_substr(trim((string) $request->input("description", $template->description ?? "")), 0, 2000) ?: null,
            "updated_at" => now(),
        ]);

        if ($request->has("exercises") && Schema::hasTable("gymies_workout_exercises")) {
            DB::table("gymies_workout_exercises")->where("workout_template_id", (int) $id)->delete();
            $exercises = $request->input("exercises", []);
            if (is_array($exercises)) {
                foreach ($exercises as $i => $ex) {
                    DB::table("gymies_workout_exercises")->insert([
                        "workout_template_id" => (int) $id,
                        "exercise_name" => mb_substr(trim((string) ($ex["name"] ?? $ex["exercise_name"] ?? "")), 0, 255),
                        "sets_count" => min(max((int) ($ex["sets"] ?? $ex["sets_count"] ?? 3), 1), 20),
                        "reps" => mb_substr(trim((string) ($ex["reps"] ?? "10")), 0, 50),
                        "rest_seconds" => min(max((int) ($ex["rest_seconds"] ?? $ex["rest"] ?? 60), 0), 600),
                        "weight_kg" => is_numeric($ex["weight_kg"] ?? null) ? round((float) $ex["weight_kg"], 2) : null,
                        "notes" => mb_substr(trim((string) ($ex["notes"] ?? "")), 0, 500) ?: null,
                        "sort_order" => $i,
                        "created_at" => now(),
                    ]);
                }
            }
        }
        return response()->json(["data" => ["id" => (int) $id, "title" => $title]]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user || $user->role !== "trainer") return response()->json(["message" => "Unauthorized"], 403);
        if (!ctype_digit($id)) return response()->json(["message" => "Ongeldig ID."], 422);

        $deleted = DB::table("gymies_workout_templates")
            ->where("id", (int) $id)->where("trainer_user_id", (int) $user->id)->delete();
        return response()->json(["data" => ["deleted" => $deleted > 0]]);
    }

    public function assign(Request $request, string $id): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user || $user->role !== "trainer") return response()->json(["message" => "Unauthorized"], 403);
        if (!Schema::hasTable("gymies_workout_assignments")) return response()->json(["message" => "Niet beschikbaar."], 503);

        $clientUserId = (int) $request->input("client_user_id", 0);
        if ($clientUserId < 1) return response()->json(["message" => "Klant-ID ontbreekt."], 422);

        $dueDate = $request->input("due_date");
        $assignmentId = DB::table("gymies_workout_assignments")->insertGetId([
            "workout_template_id" => (int) $id,
            "trainer_user_id" => (int) $user->id,
            "client_user_id" => $clientUserId,
            "assigned_at" => now(),
            "due_date" => $dueDate && strtotime($dueDate) ? date("Y-m-d", strtotime($dueDate)) : null,
            "status" => "active",
        ]);
        return response()->json(["data" => ["id" => $assignmentId, "assigned" => true]]);
    }

    public function clientWorkouts(Request $request, string $clientUserId): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user || $user->role !== "trainer") return response()->json(["message" => "Unauthorized"], 403);
        if (!Schema::hasTable("gymies_workout_assignments")) return response()->json(["data" => []]);

        $assignments = DB::table("gymies_workout_assignments as a")
            ->join("gymies_workout_templates as t", "t.id", "=", "a.workout_template_id")
            ->where("a.trainer_user_id", (int) $user->id)
            ->where("a.client_user_id", (int) $clientUserId)
            ->select("a.*", "t.title", "t.description")
            ->orderByDesc("a.assigned_at")
            ->get();
        return response()->json(["data" => $assignments->toArray()]);
    }

    public function myWorkouts(Request $request): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user) return response()->json(["message" => "Unauthorized"], 401);
        if (!Schema::hasTable("gymies_workout_assignments")) return response()->json(["data" => []]);

        $assignments = DB::table("gymies_workout_assignments as a")
            ->join("gymies_workout_templates as t", "t.id", "=", "a.workout_template_id")
            ->leftJoin("gymies_users as tr", "tr.id", "=", "a.trainer_user_id")
            ->where("a.client_user_id", (int) $user->id)
            ->select("a.*", "t.title", "t.description", "tr.display_name as trainer_name")
            ->orderByDesc("a.assigned_at")
            ->get();

        $result = [];
        foreach ($assignments as $a) {
            $row = (array) $a;
            $exercises = Schema::hasTable("gymies_workout_exercises")
                ? DB::table("gymies_workout_exercises")->where("workout_template_id", $a->workout_template_id)->orderBy("sort_order")->get()->toArray()
                : [];
            $row["exercises"] = $exercises;
            $result[] = $row;
        }
        return response()->json(["data" => $result]);
    }

    public function complete(Request $request, string $assignmentId): JsonResponse
    {
        $user = $request->attributes->get("gymies_user");
        if (!$user) return response()->json(["message" => "Unauthorized"], 401);
        if (!ctype_digit($assignmentId)) return response()->json(["message" => "Ongeldig ID."], 422);

        $updated = DB::table("gymies_workout_assignments")
            ->where("id", (int) $assignmentId)
            ->where("client_user_id", (int) $user->id)
            ->update(["status" => "completed", "completed_at" => now()]);

        return response()->json(["data" => ["completed" => $updated > 0]]);
    }
}
