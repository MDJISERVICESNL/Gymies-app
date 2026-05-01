<?php

declare(strict_types=1);

namespace App\Http\Resources;

use Illuminate\Http\JsonResponse;

/**
 * GymiesApiResponse
 * ─────────────────
 * Standaard response envelope voor alle Gymies API endpoints.
 * Zorgt voor een consistent contract dat de Flutter client kan vertrouwen.
 *
 * Standaard envelope:
 *   {
 *     "data": { ... },               // altijd aanwezig
 *     "meta": { ... },               // optioneel (paginering etc.)
 *     "message": "...",              // optioneel
 *   }
 *
 * Fout envelope:
 *   {
 *     "message": "...",              // altijd aanwezig bij fouten
 *     "errors": { ... },            // optioneel (validatie)
 *     "error_code": "...",          // optioneel (machine-readable)
 *   }
 *
 * Gebruik:
 *   return GymiesApiResponse::success($data);
 *   return GymiesApiResponse::created($data, 'Boeking aangemaakt.');
 *   return GymiesApiResponse::paginated($query, BookingResource::class);
 *   return GymiesApiResponse::error('Niet gevonden.', 404);
 *   return GymiesApiResponse::validationError($validator);
 */
final class GymiesApiResponse
{
    /**
     * Succesvolle response met data.
     */
    public static function success(mixed $data, ?string $message = null, int $status = 200): JsonResponse
    {
        $response = ['data' => $data];
        if ($message !== null) {
            $response['message'] = $message;
        }

        return response()->json($response, $status, [
            'X-API-Version' => config('gymies.api_version', '1.0'),
        ]);
    }

    /**
     * Resource aangemaakt (201).
     */
    public static function created(mixed $data, ?string $message = null): JsonResponse
    {
        return self::success($data, $message, 201);
    }

    /**
     * Gepagineerde response.
     *
     * @param \Illuminate\Database\Query\Builder|\Illuminate\Database\Eloquent\Builder $query
     * @param class-string<\Illuminate\Http\Resources\Json\JsonResource>|null $resourceClass
     */
    public static function paginated($query, ?string $resourceClass = null, int $perPage = 20): JsonResponse
    {
        $paginator = $query->paginate($perPage);
        $items = $paginator->items();

        if ($resourceClass !== null && class_exists($resourceClass)) {
            $items = $resourceClass::collection($items)->resolve();
        }

        return response()->json([
            'data' => $items,
            'meta' => [
                'current_page' => $paginator->currentPage(),
                'last_page'    => $paginator->lastPage(),
                'per_page'     => $paginator->perPage(),
                'total'        => $paginator->total(),
            ],
        ], 200, [
            'X-API-Version' => config('gymies.api_version', '1.0'),
        ]);
    }

    /**
     * Fout response.
     */
    public static function error(string $message, int $status = 400, ?string $errorCode = null): JsonResponse
    {
        $response = ['message' => $message];
        if ($errorCode !== null) {
            $response['error_code'] = $errorCode;
        }

        return response()->json($response, $status, [
            'X-API-Version' => config('gymies.api_version', '1.0'),
        ]);
    }

    /**
     * Validatie-fout response (422).
     *
     * @param \Illuminate\Contracts\Validation\Validator|\Illuminate\Support\MessageBag|array $errors
     */
    public static function validationError($errors, string $message = 'Validatie mislukt.'): JsonResponse
    {
        if ($errors instanceof \Illuminate\Contracts\Validation\Validator) {
            $errors = $errors->errors()->toArray();
        } elseif ($errors instanceof \Illuminate\Support\MessageBag) {
            $errors = $errors->toArray();
        }

        return response()->json([
            'message' => $message,
            'errors'  => $errors,
        ], 422, [
            'X-API-Version' => config('gymies.api_version', '1.0'),
        ]);
    }

    /**
     * Niet gevonden (404).
     */
    public static function notFound(string $message = 'Niet gevonden.'): JsonResponse
    {
        return self::error($message, 404, 'not_found');
    }

    /**
     * Niet geautoriseerd (403).
     */
    public static function forbidden(string $message = 'Geen toegang.'): JsonResponse
    {
        return self::error($message, 403, 'forbidden');
    }

    /**
     * Niet ingelogd (401).
     */
    public static function unauthorized(string $message = 'Niet ingelogd.'): JsonResponse
    {
        return self::error($message, 401, 'unauthorized');
    }
}
