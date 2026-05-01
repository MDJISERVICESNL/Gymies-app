<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Referral: "Nodig een vriend uit" – persoonlijke code ophalen/aanmaken.
 * Ontbrekende tabel wordt automatisch aangemaakt (self-heal) i.p.v. 503.
 * Registratie met code wordt in GymiesAuthController afgehandeld.
 */
final class GymiesReferralController extends Controller
{
    /**
     * Publiek: controleren of een referralcode bestaat en nog niet is gebruikt (voor register-UI).
     * Valideert nu ook expires_at en uses_count vs max_uses.
     */
    public function validateCode(Request $request): JsonResponse
    {
        GymiesSchemaEnsure::referralsTable();
        if (!Schema::hasTable('gymies_referrals')) {
            return response()->json([
                'valid' => false,
                'already_used' => false,
                'message' => 'Referral wordt niet ondersteund.',
            ]);
        }
        $code = trim((string) $request->query('code', $request->input('code', '')));
        if ($code === '') {
            return response()->json([
                'valid' => false,
                'already_used' => false,
                'message' => 'Geen code opgegeven.',
            ]);
        }
        // N-023 FIXED: case-normalisatie voor referral codes
        $referralCode = strtoupper(trim($code));
        $row = DB::table('gymies_referrals')
            ->whereRaw('UPPER(referral_code) = ?', [$referralCode])
            ->first();
        if (!$row) {
            return response()->json([
                'valid' => false,
                'already_used' => false,
                'message' => 'Deze code bestaat niet. Controleer de spelling.',
            ]);
        }

        // Check expires_at: als gezet en in het verleden → verlopen
        if ($row->expires_at !== null) {
            try {
                $expiresAt = \Carbon\Carbon::parse((string) $row->expires_at);
                if ($expiresAt < now()) {
                    return response()->json([
                        'valid' => false,
                        'already_used' => false,
                        'message' => 'Deze uitnodigingslink is verlopen.',
                    ]);
                }
            } catch (\Throwable $e) {
                // Fallback op normaal gedrag
            }
        }

        // Check uses_count >= max_uses
        if ($row->max_uses !== null && (int) ($row->uses_count ?? 0) >= (int) $row->max_uses) {
            return response()->json([
                'valid' => false,
                'already_used' => true,
                'message' => 'Deze link heeft het maximale aantal gebruikers bereikt.',
            ]);
        }

        $used = $row->referred_user_id !== null && $row->referred_user_id !== '';
        $pending = ($row->status ?? 'pending') === 'pending' && !$used;
        return response()->json([
            'valid' => $pending,
            'already_used' => $used,
            'message' => $used
                ? 'Deze code is al gebruikt. Vraag je vriend om een nieuwe uitnodigingslink.'
                : ($pending ? 'Code is geldig. Je wordt gekoppeld na registratie.' : 'Deze code is niet meer geldig.'),
        ]);
    }

    /**
     * Referralcode voor de ingelogde gebruiker (vaste persoonlijke code).
     * Logica: zoek permanent = 1 rij. Als die bestaat → return die. Anders genereer nieuw met permanent = 1.
     * Inclusief lijst gekoppelde registraties (permanent = 0, referred_user_id gezet).
     */
    public function myCode(Request $request): JsonResponse
    {
        $user = $request->attributes->get('gymies_user');
        if (!$user) {
            return response()->json(['message' => 'Unauthorized'], 401);
        }

        GymiesSchemaEnsure::referralsTable();
        if (!Schema::hasTable('gymies_referrals')) {
            return response()->json(['message' => 'Referral wordt niet ondersteund.'], 503);
        }

        // Zoek vaste persoonlijke code: permanent = 1
        $row = DB::table('gymies_referrals')
            ->where('referrer_user_id', (int) $user->id)
            ->where('permanent', 1)
            ->first();

        if (!$row) {
            // Genereer nieuwe permanente code
            $code = $this->generatePermanentCode((int) $user->id);
            DB::table('gymies_referrals')->insert([
                'referrer_user_id' => (int) $user->id,
                'referral_code' => $code,
                'permanent' => 1,
                'max_uses' => 999,
                'uses_count' => 0,
                'status' => 'active',
                'created_at' => now(),
            ]);
            $row = (object) ['referral_code' => $code];
        }

        $code = $row->referral_code ?? $this->generatePermanentCode((int) $user->id);
        $shareUrl = 'https://gymies.nl/voor-trainers?ref=' . urlencode($code);

        // Alle gekoppelde registraties via deze persoonlijke code
        // Zoek rijen waar referrer_user_id = user->id EN permanent = 0 (individuele gekoppelde registraties)
        $invites = DB::table('gymies_referrals as r')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'r.referred_user_id')
            ->where('r.referrer_user_id', (int) $user->id)
            ->where('r.permanent', 0)
            ->whereNotNull('r.referred_user_id')
            ->orderByDesc('r.id')
            ->limit(50)
            ->get(['r.id', 'r.referred_email', 'r.referral_code', 'r.status', 'r.created_at', 'u.display_name as referred_display_name'])
            ->map(static function ($r): array {
                return [
                    'id' => (int) $r->id,
                    'referred_email' => $r->referred_email ? (string) $r->referred_email : null,
                    'referred_display_name' => $r->referred_display_name ? (string) $r->referred_display_name : null,
                    'status' => (string) ($r->status ?? 'completed'),
                    'created_at' => $r->created_at ? (string) $r->created_at : null,
                ];
            })
            ->values()
            ->all();

        return response()->json([
            'data' => [
                'code' => $code,
                'share_url' => $shareUrl,
                'invites' => $invites,
                'invites_count' => count($invites),
            ],
        ]);
    }

    /**
     * Genereert een kortere, vriendelijkere permanente code: GYM + 6 uppercase alfanumeriek.
     * Veel makkelijker te onthouden dan REF+MD5. Gebruikt random_int in plaats van rand.
     */
    private function generatePermanentCode(int $userId): string
    {
        $attempts = 0;
        do {
            // GYM + 6 random chars (A-Z, 0-9)
            $randomPart = '';
            for ($i = 0; $i < 6; $i++) {
                $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
                $randomPart .= $chars[random_int(0, strlen($chars) - 1)];
            }
            $code = 'GYM' . $randomPart;
            $exists = DB::table('gymies_referrals')->where('referral_code', $code)->exists();
            $attempts++;
        } while ($exists && $attempts < 10);
        return $code;
    }
}
