<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Symfony\Component\HttpFoundation\Response;

final class GymiesAdminIpAllowlistMiddleware
{
    public function handle(Request $request, Closure $next): Response
    {
        $ip = $this->getClientIp($request);
        if ($ip === '') {
            return response()->json(['message' => 'IP adres ontbreekt.'], 403);
        }

        if (!$this->isAllowed($ip)) {
            return response()->json(['message' => 'IP niet toegestaan voor admin toegang.'], 403);
        }

        return $next($request);
    }

    /**
     * Bepaal client-IP; achter nginx/reverse proxy of Cloudflare gebruiken we
     * X-Forwarded-For / X-Real-IP / CF-Connecting-IP zodat de allowlist op het
     * echte client-IP werkt in plaats van 127.0.0.1 of proxy-IP.
     */
    private function getClientIp(Request $request): string
    {
        $candidates = [
            $request->header('X-Forwarded-For'),
            $request->header('CF-Connecting-IP'),
            $request->header('X-Real-IP'),
        ];
        foreach ($candidates as $value) {
            if ($value === null || $value === '') {
                continue;
            }
            $value = trim($value);
            if (str_contains($value, ',')) {
                $value = trim(explode(',', $value)[0]);
            }
            if ($value !== '' && filter_var($value, FILTER_VALIDATE_IP)) {
                return $value;
            }
        }
        return (string) ($request->ip() ?? '');
    }

    private function isAllowed(string $ip): bool
    {
        if (filter_var(env('TRAINMAAT_ADMIN_SKIP_IP_CHECK', ''), FILTER_VALIDATE_BOOLEAN)) {
            return true;
        }

        $envList = trim((string) env('TRAINMAAT_ADMIN_ALLOWED_IPS', ''));
        if ($envList !== '' && $envList !== '*') {
            $patterns = array_values(array_filter(array_map('trim', explode(',', $envList))));
            foreach ($patterns as $pattern) {
                if ($this->ipMatches($ip, $pattern)) {
                    return true;
                }
            }
        }
        if ($envList === '*') {
            return true;
        }

        if (!DB::getSchemaBuilder()->hasTable('gymies_admin_ip_allowlist')) {
            return $envList === '';
        }

        $dbPatterns = DB::table('gymies_admin_ip_allowlist')
            ->where('status', 'active')
            ->pluck('ip_pattern')
            ->map(static fn ($x) => (string) $x)
            ->all();
        if (empty($dbPatterns)) {
            return $envList === '';
        }
        foreach ($dbPatterns as $pattern) {
            if ($this->ipMatches($ip, $pattern)) {
                return true;
            }
        }

        return false;
    }

    private function ipMatches(string $ip, string $pattern): bool
    {
        $pattern = trim($pattern);
        if ($pattern === '') {
            return false;
        }
        if ($pattern === $ip) {
            return true;
        }
        if (str_contains($pattern, '/')) {
            return $this->cidrMatch($ip, $pattern);
        }

        return false;
    }

    private function cidrMatch(string $ip, string $cidr): bool
    {
        [$subnet, $mask] = array_pad(explode('/', $cidr, 2), 2, null);
        if ($subnet === null || $mask === null || !is_numeric($mask)) {
            return false;
        }
        $ipLong = ip2long($ip);
        $subnetLong = ip2long($subnet);
        if ($ipLong === false || $subnetLong === false) {
            return false;
        }
        $maskInt = (int) $mask;
        if ($maskInt < 0 || $maskInt > 32) {
            return false;
        }
        $maskBin = -1 << (32 - $maskInt);
        $subnetMasked = $subnetLong & $maskBin;
        $ipMasked = $ipLong & $maskBin;

        return $subnetMasked === $ipMasked;
    }
}

