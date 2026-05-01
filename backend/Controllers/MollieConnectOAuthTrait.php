<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Trait voor correcte Mollie Connect OAuth state handling.
 * Voorkomt "State verlopen of ongeldig" door state in DB op te slaan i.p.v. session.
 *
 * Gebruik in GymiesOnboardingController:
 *   use MollieConnectOAuthTrait;
 *
 *   public function startMollieConnect(Request $request): JsonResponse
 *   {
 *       return $this->mollieConnectStart($request);
 *   }
 *   public function mollieConnectCallback(Request $request): JsonResponse
 *   {
 *       return $this->mollieConnectCallbackHandle($request);
 *   }
 */
trait MollieConnectOAuthTrait
{
    private const STATE_TTL_MINUTES = 30;
    private const MOLLIE_AUTH_URL = 'https://my.mollie.com/oauth2/authorize';
    private const MOLLIE_TOKEN_URL = 'https://api.mollie.com/oauth2/tokens';
    private const MOLLIE_ORG_ME_URL = 'https://api.mollie.com/v2/organizations/me';
    private const SCOPE = 'organizations.read profiles.read payments.read payments.write customers.read';

    private function mollieConnectStart(Request $request): JsonResponse
    {
        $clientId = config('services.mollie.client_id') ?? env('MOLLIE_CLIENT_ID');
        $baseUrl = rtrim(config('app.url') ?? env('APP_URL', 'https://www.gymies.nl'), '/');
        $redirectUri = $baseUrl . '/api/gymies/onboarding/mollie-connect/callback';

        if (empty($clientId)) {
            return response()->json([
                'message' => 'Geen Mollie-link ontvangen. Configureer MOLLIE_CLIENT_ID op de server.',
            ], 422);
        }

        $user = $request->user();
        if (!$user) {
            return response()->json(['message' => 'Niet ingelogd.'], 401);
        }

        if (!Schema::hasTable('gymies_mollie_oauth_states')) {
            return response()->json([
                'message' => 'OAuth state-tabel ontbreekt. Draai de migratie: php artisan migrate',
            ], 500);
        }

        $state = Str::random(40);
        $expiresAt = now()->addMinutes(self::STATE_TTL_MINUTES);

        DB::table('gymies_mollie_oauth_states')->insert([
            'state' => $state,
            'user_id' => $user->id,
            'expires_at' => $expiresAt,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $authUrl = self::MOLLIE_AUTH_URL . '?' . http_build_query([
            'client_id' => $clientId,
            'redirect_uri' => $redirectUri,
            'state' => $state,
            'scope' => self::SCOPE,
            'response_type' => 'code',
        ]);

        return response()->json(['redirect_url' => $authUrl]);
    }

    private function mollieConnectCallbackHandle(Request $request): JsonResponse
    {
        $state = $request->query('state');
        $code = $request->query('code');
        $error = $request->query('error');

        if ($error) {
            $desc = $request->query('error_description', $error);
            return response()->json([
                'message' => 'Mollie autorisatie afgewezen: ' . $desc,
            ], 400);
        }

        if (empty($state) || empty($code)) {
            return response()->json([
                'message' => 'Ongeldige callback: code en state zijn verplicht.',
            ], 400);
        }

        if (!Schema::hasTable('gymies_mollie_oauth_states')) {
            return response()->json([
                'message' => 'State verlopen of ongeldig. Start Mollie Connect opnieuw vanuit de app (binnen 30 minuten na start). '
                    . 'Zorg dat de migratie gymies_mollie_oauth_states is gedraaid als dit blijft gebeuren.',
            ], 400);
        }

        $row = DB::table('gymies_mollie_oauth_states')
            ->where('state', $state)
            ->first();

        if (!$row) {
            return response()->json([
                'message' => 'State verlopen of ongeldig. Start Mollie Connect opnieuw vanuit de app (binnen 30 minuten na start). '
                    . 'Zorg dat de migratie gymies_mollie_oauth_states is gedraaid als dit blijft gebeuren.',
            ], 400);
        }

        if (now()->isAfter($row->expires_at)) {
            DB::table('gymies_mollie_oauth_states')->where('state', $state)->delete();
            return response()->json([
                'message' => 'State verlopen of ongeldig. Start Mollie Connect opnieuw vanuit de app (binnen 30 minuten na start).',
            ], 400);
        }

        $userId = (int) $row->user_id;
        DB::table('gymies_mollie_oauth_states')->where('state', $state)->delete();

        $baseUrl = rtrim(config('app.url') ?? env('APP_URL', 'https://www.gymies.nl'), '/');
        $redirectUri = $baseUrl . '/api/gymies/onboarding/mollie-connect/callback';

        $clientId = config('services.mollie.client_id') ?? env('MOLLIE_CLIENT_ID');
        $clientSecret = config('services.mollie.client_secret') ?? env('MOLLIE_CLIENT_SECRET');

        if (empty($clientId) || empty($clientSecret)) {
            return response()->json(['message' => 'Mollie OAuth niet geconfigureerd (client_id/client_secret).'], 500);
        }

        $tokenRes = Http::asForm()
            ->withBasicAuth($clientId, $clientSecret)
            ->post(self::MOLLIE_TOKEN_URL, [
                'grant_type' => 'authorization_code',
                'code' => $code,
                'redirect_uri' => $redirectUri,
            ]);

        if (!$tokenRes->successful()) {
            $body = $tokenRes->json();
            $msg = $body['error_description'] ?? $body['error'] ?? $tokenRes->body();
            return response()->json(['message' => 'Mollie token exchange mislukt: ' . $msg], 400);
        }

        $data = $tokenRes->json();
        $accessToken = $data['access_token'] ?? null;

        if (!$accessToken) {
            return response()->json(['message' => 'Geen access token ontvangen van Mollie.'], 500);
        }

        $orgRes = Http::withToken($accessToken)->get(self::MOLLIE_ORG_ME_URL);
        if (!$orgRes->successful()) {
            return response()->json(['message' => 'Kon Mollie-organisatie niet ophalen.'], 500);
        }

        $org = $orgRes->json();
        $orgId = $org['id'] ?? null;

        if (!$orgId) {
            return response()->json(['message' => 'Geen organisatie-ID van Mollie.'], 500);
        }

        if (Schema::hasTable('gymies_trainer_profiles')) {
            $profile = DB::table('gymies_trainer_profiles')->where('user_id', $userId)->first();
            $columns = Schema::getColumnListing('gymies_trainer_profiles');

            if ($profile) {
                $update = ['updated_at' => now()];
                if (in_array('mollie_connect_id', $columns)) {
                    $update['mollie_connect_id'] = $orgId;
                }
                if (in_array('mollie_organization_id', $columns)) {
                    $update['mollie_organization_id'] = $orgId;
                }
                if (in_array('mollie_access_token', $columns)) {
                    $update['mollie_access_token'] = encrypt($accessToken);
                }
                if (in_array('mollie_refresh_token', $columns)) {
                    $refreshToken = $data['refresh_token'] ?? null;
                    $update['mollie_refresh_token'] = $refreshToken ? encrypt($refreshToken) : null;
                }
                if (in_array('mollie_token_expires_at', $columns)) {
                    $expiresIn = (int) ($data['expires_in'] ?? 3600);
                    $update['mollie_token_expires_at'] = now()->addSeconds($expiresIn);
                }
                DB::table('gymies_trainer_profiles')
                    ->where('user_id', $userId)
                    ->update($update);
            }
        }

        // Redirect naar app via deep link – WebView onderschept dit en sluit.
        return redirect()->away('gymies://mollie-connect/success');
    }
}
