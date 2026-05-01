<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

final class GymiesApiErrorLoggingMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        try {
            /** @var Response $response */
            $response = $next($request);
        } catch (\Throwable $e) {
            $this->logError($request, 500, $e->getMessage(), [
                'exception' => $e::class,
                'method' => $request->method(),
            ]);
            throw $e;
        }

        if ($response->getStatusCode() >= 500) {
            $this->logError($request, $response->getStatusCode(), 'Server error response');
        }

        return $response;
    }

    /**
     * @param array<string,mixed>|null $context
     */
    private function logError(Request $request, int $statusCode, string $message, ?array $context = null): void
    {
        if (!DB::getSchemaBuilder()->hasTable('gymies_api_error_logs')) {
            return;
        }
        $user = $request->attributes->get('gymies_user');
        $userId = $user ? (int) $user->id : null;
        $safeMessage = $this->redactText($message);
        $safeContext = $this->redactPayload($context);

        DB::table('gymies_api_error_logs')->insert([
            'user_id' => $userId,
            'endpoint' => $request->method() . ' ' . (string) $request->path(),
            'error_code' => 'HTTP_' . $statusCode,
            'message' => mb_substr($safeMessage, 0, 4000),
            'context_json' => $safeContext ? json_encode($safeContext, JSON_UNESCAPED_UNICODE) : null,
            'created_at' => now(),
        ]);
    }

    private function redactText(string $value): string
    {
        $result = $value;
        $result = preg_replace('/Bearer\s+[A-Za-z0-9\-\._~\+\/]+=*/i', 'Bearer [REDACTED]', $result) ?? $result;
        $result = preg_replace('/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/', '[REDACTED_EMAIL]', $result) ?? $result;
        $result = preg_replace('/\bNL[0-9A-Z]{8,30}\b/i', '[REDACTED_IBAN]', $result) ?? $result;

        return $result;
    }

    /**
     * @param array<string,mixed>|null $payload
     * @return array<string,mixed>|null
     */
    private function redactPayload(?array $payload): ?array
    {
        if ($payload === null) {
            return null;
        }
        $deny = ['authorization', 'token', 'password', 'password_hash', 'iban', 'iban_masked', 'iban_last4'];
        $out = [];
        foreach ($payload as $key => $value) {
            $lower = mb_strtolower((string) $key);
            if (in_array($lower, $deny, true)) {
                $out[$key] = '[REDACTED]';
                continue;
            }
            if (is_array($value)) {
                $out[$key] = $this->redactPayload($value);
                continue;
            }
            if (is_string($value)) {
                $out[$key] = $this->redactText($value);
                continue;
            }
            $out[$key] = $value;
        }

        return $out;
    }
}
