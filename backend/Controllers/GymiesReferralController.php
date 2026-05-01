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
        $codeNorm = strtoupper($code);
        $row = DB::table('gymies_referrals')->where('referral_code', $codeNorm)->first();
        if (!$row) {
            $row = DB::table('gymies_referrals')
                ->whereRaw('LOWER(referral_code) = ?', [mb_strtolower($code)])
                ->first();
        }
        if (!$row) {
            return response()->json([
                'valid' => false,
                'already_used' => false,
                'message' => 'Deze code bestaat niet. Controleer de spelling.',
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
     * Referralcode voor de ingelogde gebruiker (aanmaken indien nog geen ongebruikte code).
     * Inclusief lijst uitgenodigden (referred_user_id gezet) zodat de eigenaar ziet wie er via hen binnenkwam.
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

        $row = DB::table('gymies_referrals')
            ->where('referrer_user_id', (int) $user->id)
            ->whereNull('referred_user_id')
            ->where('status', 'pending')
            ->first();

        if (!$row) {
            $code = strtoupper($this->generateUniqueCode((int) $user->id));
            DB::table('gymies_referrals')->insert([
                'referrer_user_id' => (int) $user->id,
                'referral_code' => $code,
                'status' => 'pending',
                'created_at' => now(),
            ]);
            $row = (object) ['referral_code' => $code];
        }

        $code = $row->referral_code ?? $this->generateUniqueCode((int) $user->id);
        $baseUrl = rtrim($request->root() ?? '', '/');
        $shareUrl = $baseUrl . '/gymies#/register?ref=' . urlencode($code);

        // Alle referrals waar deze gebruiker uitnodiger is en iemand al gekoppeld is
        $invites = DB::table('gymies_referrals as r')
            ->leftJoin('gymies_users as u', 'u.id', '=', 'r.referred_user_id')
            ->where('r.referrer_user_id', (int) $user->id)
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

    private function generateUniqueCode(int $userId): string
    {
        $attempts = 0;
        do {
            $code = 'REF' . strtoupper(substr(md5((string) $userId . bin2hex(random_bytes(4))), 0, 8));
            $exists = DB::table('gymies_referrals')->where('referral_code', $code)->exists();
            $attempts++;
        } while ($exists && $attempts < 10);
        return $code;
    }
}
