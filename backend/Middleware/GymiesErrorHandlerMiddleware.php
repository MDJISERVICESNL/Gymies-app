<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Symfony\Component\HttpFoundation\Response;
use Throwable;

/**
 * GymiesErrorHandlerMiddleware
 *
 * Centralized error handling for API responses.
 * - Logs unhandled exceptions
 * - Sanitizes error messages in production
 * - Tracks errors to database for monitoring
 * - Integrates with Sentry for critical errors
 *
 * Exceptions are caught and logged before throwing to allow consistent
 * response formatting across the API.
 */
final class GymiesErrorHandlerMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        try {
            /** @var Response $response */
            $response = $next($request);

            // Log server errors
            if ($response->getStatusCode() >= 500) {
                $this->logServerError(
                    $request,
                    $response->getStatusCode(),
                    'Server error response',
                    null
                );
            }

            return $response;
        } catch (Throwable $e) {
            return $this->handleException($request, $e);
        }
    }

    private function handleException(Request $request, Throwable $e): Response
    {
        $statusCode = 500;

        // Determine status code from exception if applicable
        if (method_exists($e, 'getStatusCode')) {
            $statusCode = $e->getStatusCode();
        } elseif ($e instanceof \Illuminate\Database\QueryException) {
            $statusCode = 500;
        } elseif ($e instanceof \Illuminate\Validation\ValidationException) {
            $statusCode = 422;
        } elseif ($e instanceof \Symfony\Component\HttpKernel\Exception\HttpException) {
            $statusCode = $e->getStatusCode();
        }

        $this->logServerError($request, $statusCode, $e->getMessage(), $e);

        // Sanitize message for production
        $message = app()->environment('production')
            ? 'An error occurred processing your request.'
            : $e->getMessage();

        $response = [
            'status' => 'error',
            'message' => $message,
            'timestamp' => now()->toIso8601String(),
        ];

        // Include trace in development
        if (app()->environment('local', 'development', 'testing')) {
            $response['trace'] = [
                'file' => $e->getFile(),
                'line' => $e->getLine(),
                'class' => $e::class,
            ];
            if (config('app.debug')) {
                $response['full_trace'] = $e->getTraceAsString();
            }
        }

        return response()->json($response, $statusCode, [
            'Cache-Control' => 'no-store, no-cache',
        ]);
    }

    private function logServerError(
        Request $request,
        int $statusCode,
        string $message,
        ?Throwable $exception = null
    ): void {
        $context = [
            'method' => $request->method(),
            'path' => $request->path(),
            'status' => $statusCode,
            'user_id' => $request->attributes->get('gymies_user')?->id,
            'ip' => $request->ip(),
        ];

        if ($exception) {
            $context['exception'] = $exception::class;
            $context['exception_message'] = $exception->getMessage();
            $context['file'] = $exception->getFile();
            $context['line'] = $exception->getLine();
        }

        // Log to Laravel logs
        if ($statusCode >= 500) {
            Log::error("API Error {$statusCode}: {$message}", $context);
        } else {
            Log::warning("API {$statusCode}: {$message}", $context);
        }

        // Store in database
        if (DB::getSchemaBuilder()->hasTable('gymies_api_error_logs')) {
            try {
                DB::table('gymies_api_error_logs')->insert([
                    'user_id' => $context['user_id'],
                    'endpoint' => $request->method() . ' ' . $request->path(),
                    'error_code' => 'HTTP_' . $statusCode,
                    'message' => mb_substr($this->redactMessage($message), 0, 4000),
                    'context_json' => json_encode($this->redactContext($context), JSON_UNESCAPED_UNICODE),
                    'ip_address' => $context['ip'],
                    'created_at' => now(),
                ]);
            } catch (\Throwable $e) {
                // Silently fail to avoid infinite loops
            }
        }

        // Alert Sentry for critical errors
        if ($statusCode >= 500 && function_exists('\\Sentry\\captureException')) {
            \Sentry\captureException($exception ?? new \Exception($message), ['extra' => $context]);
        }
    }

    private function redactMessage(string $message): string
    {
        $result = $message;
        $result = (string) preg_replace('/Bearer\s+[A-Za-z0-9\-\._~\+\/]+=*/i', 'Bearer [REDACTED]', $result);
        $result = (string) preg_replace('/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/', '[REDACTED_EMAIL]', $result);
        $result = (string) preg_replace('/\bNL[0-9A-Z]{8,30}\b/i', '[REDACTED_IBAN]', $result);
        $result = (string) preg_replace('/password["\']?\s*[:=]\s*["\']?[^"\']*["\']?/i', 'password: [REDACTED]', $result);

        return $result;
    }

    /**
     * @param array<string,mixed> $context
     * @return array<string,mixed>
     */
    private function redactContext(array $context): array
    {
        $deny = ['authorization', 'token', 'password', 'password_hash', 'iban', 'iban_masked', 'api_key', 'secret'];
        $out = [];

        foreach ($context as $key => $value) {
            $lower = mb_strtolower((string) $key);
            if (in_array($lower, $deny, true)) {
                $out[$key] = '[REDACTED]';
                continue;
            }
            if (is_array($value)) {
                $out[$key] = $this->redactContext($value);
                continue;
            }
            if (is_string($value)) {
                $out[$key] = $this->redactMessage($value);
                continue;
            }
            $out[$key] = $value;
        }

        return $out;
    }
}
