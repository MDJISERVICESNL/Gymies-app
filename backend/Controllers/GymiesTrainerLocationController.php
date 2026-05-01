<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Trainer locatie endpoints — stub.
 * Voorkomt ClassNotFound error in route compilation.
 */
final class GymiesTrainerLocationController extends Controller
{
    public function index(Request $request, string $id): JsonResponse
    {
        return response()->json(['data' => ['locations' => []]]);
    }

    public function store(Request $request): JsonResponse
    {
        return response()->json(['message' => 'Niet geïmplementeerd.'], 501);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        return response()->json(['message' => 'Niet geïmplementeerd.'], 501);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        return response()->json(['message' => 'Niet geïmplementeerd.'], 501);
    }
}
