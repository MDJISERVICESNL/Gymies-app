#!/bin/bash
# =============================================================================
# Deploy: Client-facing dispute (geschillen) systeem
# =============================================================================
# Voegt toe:
#   1. GymiesDisputeController.php → app/Http/Controllers/Gymies/
#   2. Client dispute routes → gymies_deploy/routes_gymies_full.php (auth groep)
#   3. gymies_disputes + gymies_dispute_messages tabellen (als ze niet bestaan)
#
# Run: ssh gymies "bash -s" < backend/gymies_deploy/deploy_disputes_client.sh
# =============================================================================

set -e
cd /var/www/gymies

echo "============================================"
echo "  GYMIES: Deploy Geschillen (client-side)   "
echo "============================================"
echo ""

# ── Step 1: Controller deployen ────────────────────────────────────
echo "▸ Step 1: GymiesDisputeController deployen..."

CTRL_DIR="/var/www/gymies/app/Http/Controllers/Gymies"
CTRL_FILE="$CTRL_DIR/GymiesDisputeController.php"

if [ -f "$CTRL_FILE" ]; then
    echo "  ⏭️ GymiesDisputeController.php bestaat al — wordt overschreven"
fi

cat > "$CTRL_FILE" << 'CONTROLLEREOF'
<?php

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Client-facing dispute (geschillen) endpoints.
 */
class GymiesDisputeController extends Controller
{
    private function user(Request $request): ?object
    {
        return $request->attributes->get('gymies_user');
    }

    private function unauthorized(): JsonResponse
    {
        return response()->json(['message' => 'Niet ingelogd.'], 401);
    }

    private function tablesMissing(): bool
    {
        return !Schema::hasTable('gymies_disputes');
    }

    /** GET my-disputes */
    public function index(Request $request): JsonResponse
    {
        $user = $this->user($request);
        if (!$user) return $this->unauthorized();

        if ($this->tablesMissing()) {
            return response()->json(['data' => []]);
        }

        $userId = (int) $user->id;

        $disputes = DB::table('gymies_disputes as d')
            ->leftJoin('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->where(function ($q) use ($userId) {
                $q->where('d.raised_by_user_id', $userId)
                  ->orWhere('b.client_user_id', $userId)
                  ->orWhere('b.trainer_user_id', $userId);
            })
            ->orderByDesc('d.created_at')
            ->select([
                'd.id', 'd.booking_id', 'd.reason', 'd.details', 'd.status',
                'd.created_at', 'd.closed_at',
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                DB::raw('COALESCE(c.display_name, c.email) as client_name'),
            ])
            ->limit(50)
            ->get()
            ->map(function ($d) {
                $d->other_party = $d->trainer_name;
                if (Schema::hasColumn('gymies_disputes', 'resolution_type')) {
                    $full = DB::table('gymies_disputes')->where('id', $d->id)->value('resolution_type');
                    $d->resolution_type = $full;
                }
                return $d;
            });

        return response()->json(['data' => $disputes]);
    }

    /** GET my-disputes/{id} */
    public function show(Request $request, string $disputeId): JsonResponse
    {
        $user = $this->user($request);
        if (!$user) return $this->unauthorized();

        if ($this->tablesMissing() || !is_numeric($disputeId)) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        $userId = (int) $user->id;
        $id = (int) $disputeId;

        $d = DB::table('gymies_disputes as d')
            ->leftJoin('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
            ->leftJoin('gymies_users as t', 't.id', '=', 'b.trainer_user_id')
            ->leftJoin('gymies_users as c', 'c.id', '=', 'b.client_user_id')
            ->where('d.id', $id)
            ->where(function ($q) use ($userId) {
                $q->where('d.raised_by_user_id', $userId)
                  ->orWhere('b.client_user_id', $userId)
                  ->orWhere('b.trainer_user_id', $userId);
            })
            ->select(['d.*',
                DB::raw('COALESCE(t.display_name, t.email) as trainer_name'),
                DB::raw('COALESCE(c.display_name, c.email) as client_name'),
                'b.scheduled_at', 'b.amount_cents', 'b.status as booking_status',
            ])
            ->first();

        if (!$d) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        $d->other_party = $d->trainer_name;

        $messages = [];
        if (Schema::hasTable('gymies_dispute_messages')) {
            $messages = DB::table('gymies_dispute_messages as m')
                ->leftJoin('gymies_users as u', 'u.id', '=', 'm.author_user_id')
                ->where('m.dispute_id', $id)
                ->where(function ($q) {
                    $q->where('m.is_internal', false)
                      ->orWhereNull('m.is_internal');
                })
                ->orderBy('m.created_at')
                ->get(['m.id', 'm.author_user_id', 'm.message', 'm.created_at',
                    DB::raw('COALESCE(u.display_name, u.email) as author'),
                ])
                ->map(function ($m) use ($userId) {
                    $m->is_mine = ((int) $m->author_user_id === $userId);
                    return $m;
                })
                ->all();
        }

        return response()->json([
            'data' => array_merge((array) $d, ['messages' => $messages]),
        ]);
    }

    /** POST my-disputes/{id}/message */
    public function addMessage(Request $request, string $disputeId): JsonResponse
    {
        $user = $this->user($request);
        if (!$user) return $this->unauthorized();

        $request->validate([
            'message' => 'required|string|max:2000',
        ]);

        if ($this->tablesMissing() || !is_numeric($disputeId)) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        $userId = (int) $user->id;
        $id = (int) $disputeId;

        $d = DB::table('gymies_disputes as d')
            ->leftJoin('gymies_bookings as b', 'b.id', '=', 'd.booking_id')
            ->where('d.id', $id)
            ->where(function ($q) use ($userId) {
                $q->where('d.raised_by_user_id', $userId)
                  ->orWhere('b.client_user_id', $userId)
                  ->orWhere('b.trainer_user_id', $userId);
            })
            ->first(['d.id', 'd.status']);

        if (!$d) {
            return response()->json(['message' => 'Geschil niet gevonden.'], 404);
        }

        if ($d->status === 'resolved') {
            return response()->json(['message' => 'Dit geschil is al opgelost.'], 422);
        }

        if (!Schema::hasTable('gymies_dispute_messages')) {
            return response()->json(['message' => 'Berichten niet beschikbaar.'], 503);
        }

        $msgId = DB::table('gymies_dispute_messages')->insertGetId([
            'dispute_id'     => $id,
            'author_user_id' => $userId,
            'message'        => mb_substr(trim($request->input('message')), 0, 2000),
            'is_internal'    => false,
            'created_at'     => now(),
        ]);

        return response()->json([
            'data' => [
                'id'         => $msgId,
                'dispute_id' => $id,
                'message'    => trim($request->input('message')),
                'author'     => $user->display_name ?? $user->email ?? 'Jij',
                'is_mine'    => true,
                'created_at' => now()->toISOString(),
            ],
        ]);
    }

    /** POST bookings/{id}/dispute */
    public function raise(Request $request, string $bookingId): JsonResponse
    {
        $user = $this->user($request);
        if (!$user) return $this->unauthorized();

        $request->validate([
            'reason'  => 'required|string|max:500',
            'details' => 'nullable|string|max:2000',
        ]);

        if (!is_numeric($bookingId)) {
            return response()->json(['message' => 'Ongeldige boeking.'], 422);
        }

        $userId = (int) $user->id;
        $bId = (int) $bookingId;

        $booking = DB::table('gymies_bookings')
            ->where('id', $bId)
            ->where(function ($q) use ($userId) {
                $q->where('client_user_id', $userId)
                  ->orWhere('trainer_user_id', $userId);
            })
            ->first();

        if (!$booking) {
            return response()->json(['message' => 'Boeking niet gevonden.'], 404);
        }

        // Maak tabellen aan als ze niet bestaan
        if ($this->tablesMissing()) {
            Schema::create('gymies_disputes', function ($t) {
                $t->bigIncrements('id');
                $t->unsignedBigInteger('booking_id')->index();
                $t->unsignedBigInteger('raised_by_user_id')->index();
                $t->string('reason', 500);
                $t->text('details')->nullable();
                $t->enum('status', ['open', 'in_progress', 'resolved'])->default('open');
                $t->string('resolution_type', 32)->nullable();
                $t->text('resolution_notes')->nullable();
                $t->unsignedBigInteger('resolved_by_user_id')->nullable();
                $t->timestamp('closed_at')->nullable();
                $t->timestamps();
            });
        }

        if (!Schema::hasTable('gymies_dispute_messages')) {
            Schema::create('gymies_dispute_messages', function ($t) {
                $t->bigIncrements('id');
                $t->unsignedBigInteger('dispute_id')->index();
                $t->unsignedBigInteger('author_user_id')->index();
                $t->text('message');
                $t->boolean('is_internal')->default(false);
                $t->timestamp('created_at')->useCurrent();
            });
        }

        // Check of er al een open dispute is
        $existing = DB::table('gymies_disputes')
            ->where('booking_id', $bId)
            ->whereIn('status', ['open', 'in_progress'])
            ->first();

        if ($existing) {
            return response()->json([
                'message' => 'Er is al een lopend geschil voor deze boeking.',
                'data'    => ['id' => $existing->id],
            ], 409);
        }

        $disputeId = DB::table('gymies_disputes')->insertGetId([
            'booking_id'         => $bId,
            'raised_by_user_id'  => $userId,
            'reason'             => mb_substr(trim($request->input('reason')), 0, 500),
            'details'            => $request->input('details') ? mb_substr(trim($request->input('details')), 0, 2000) : null,
            'status'             => 'open',
            'created_at'         => now(),
            'updated_at'         => now(),
        ]);

        return response()->json([
            'data' => [
                'id'         => $disputeId,
                'booking_id' => $bId,
                'status'     => 'open',
                'reason'     => trim($request->input('reason')),
                'created_at' => now()->toISOString(),
            ],
        ], 201);
    }
}
CONTROLLEREOF

echo "  ✅ GymiesDisputeController.php gedeployed"

echo ""

# ── Step 2: Routes toevoegen ───────────────────────────────────────
echo "▸ Step 2: Client dispute routes toevoegen..."

ROUTES="/var/www/gymies/gymies_deploy/routes_gymies_full.php"

if grep -q "my-disputes" "$ROUTES" 2>/dev/null; then
    echo "  ⏭️ Dispute routes bestaan al"
else
    sudo cp "$ROUTES" "${ROUTES}.bak_disputes_$(date +%Y%m%d_%H%M%S)"

    cp "$ROUTES" /tmp/routes_disputes_fix.php

    php -r "
\$file = '/tmp/routes_disputes_fix.php';
\$content = file_get_contents(\$file);

\$marker = \"referral/my-code\";
\$pos = strpos(\$content, \$marker);

if (\$pos === false) {
    echo \"  ❌ Marker 'referral/my-code' niet gevonden\\n\";
    exit(1);
}

\$lineEnd = strpos(\$content, \"\\n\", \$pos);
if (\$lineEnd === false) {
    echo \"  ❌ Einde van regel niet gevonden\\n\";
    exit(1);
}

\$routes = \"\\n\" .
    \"\\n\" .
    \"        // Geschillen (disputes) – klant-zijde\\n\" .
    \"        Route::get('my-disputes', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesDisputeController::class, 'index'])->name('disputes.my');\\n\" .
    \"        Route::get('my-disputes/{id}', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesDisputeController::class, 'show'])->name('disputes.my.show');\\n\" .
    \"        Route::post('my-disputes/{id}/message', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesDisputeController::class, 'addMessage'])->name('disputes.my.message');\\n\" .
    \"        Route::post('bookings/{id}/dispute', [\\\\App\\\\Http\\\\Controllers\\\\Gymies\\\\GymiesDisputeController::class, 'raise'])->name('disputes.raise');\";

\$content = substr(\$content, 0, \$lineEnd) . \$routes . substr(\$content, \$lineEnd);
file_put_contents(\$file, \$content);
echo \"  ✅ Dispute routes toegevoegd na 'referral/my-code' (auth groep)\\n\";
"

    sudo cp /tmp/routes_disputes_fix.php "$ROUTES"
    sudo chown www-data:www-data "$ROUTES" 2>/dev/null || true
    rm -f /tmp/routes_disputes_fix.php
    echo "  ✅ Routes bestand opgeslagen"
fi

echo ""

# ── Step 3: Database tabellen aanmaken ─────────────────────────────
echo "▸ Step 3: Database tabellen aanmaken..."

php artisan tinker --execute="
use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;

if (!Schema::hasTable('gymies_disputes')) {
    Schema::create('gymies_disputes', function (Blueprint \$t) {
        \$t->bigIncrements('id');
        \$t->unsignedBigInteger('booking_id')->index();
        \$t->unsignedBigInteger('raised_by_user_id')->index();
        \$t->string('reason', 500);
        \$t->text('details')->nullable();
        \$t->enum('status', ['open', 'in_progress', 'resolved'])->default('open');
        \$t->string('resolution_type', 32)->nullable();
        \$t->text('resolution_notes')->nullable();
        \$t->unsignedBigInteger('resolved_by_user_id')->nullable();
        \$t->timestamp('closed_at')->nullable();
        \$t->timestamps();
    });
    echo \"  ✅ gymies_disputes tabel aangemaakt\n\";
} else {
    echo \"  ⏭️ gymies_disputes bestaat al\n\";
    // Voeg ontbrekende kolommen toe
    if (!Schema::hasColumn('gymies_disputes', 'resolution_type')) {
        Schema::table('gymies_disputes', function (Blueprint \$t) {
            \$t->string('resolution_type', 32)->nullable()->after('status');
        });
        echo \"  ✅ resolution_type kolom toegevoegd\n\";
    }
    if (!Schema::hasColumn('gymies_disputes', 'resolved_by_user_id')) {
        Schema::table('gymies_disputes', function (Blueprint \$t) {
            \$t->unsignedBigInteger('resolved_by_user_id')->nullable()->after('resolution_notes');
        });
        echo \"  ✅ resolved_by_user_id kolom toegevoegd\n\";
    }
}

if (!Schema::hasTable('gymies_dispute_messages')) {
    Schema::create('gymies_dispute_messages', function (Blueprint \$t) {
        \$t->bigIncrements('id');
        \$t->unsignedBigInteger('dispute_id')->index();
        \$t->unsignedBigInteger('author_user_id')->index();
        \$t->text('message');
        \$t->boolean('is_internal')->default(false);
        \$t->timestamp('created_at')->useCurrent();
    });
    echo \"  ✅ gymies_dispute_messages tabel aangemaakt\n\";
} else {
    echo \"  ⏭️ gymies_dispute_messages bestaat al\n\";
}
"

echo ""

# ── Step 4: Cache legen ────────────────────────────────────────────
echo "▸ Step 4: Caches legen..."
php artisan config:clear 2>/dev/null || true
php artisan route:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true
echo "  ✅ Done"

echo ""

# ── Step 5: Verificatie ────────────────────────────────────────────
echo "▸ Step 5: Verificatie..."

php artisan tinker --execute="
use Illuminate\Support\Facades\Route;
use Illuminate\Support\Facades\Schema;

// Check tabellen
\$tables = ['gymies_disputes', 'gymies_dispute_messages'];
foreach (\$tables as \$t) {
    \$ok = Schema::hasTable(\$t);
    echo (\$ok ? '  ✅' : '  ❌') . \" Tabel: \$t\n\";
}

// Check routes
\$routeNames = ['disputes.my', 'disputes.my.show', 'disputes.my.message', 'disputes.raise'];
foreach (\$routeNames as \$name) {
    \$exists = Route::has('api.gymies.' . \$name);
    echo (\$exists ? '  ✅' : '  ❌') . \" Route: \$name\n\";
}

// Check middleware
\$routes = collect(Route::getRoutes())->filter(fn(\$r) => str_contains(\$r->uri(), 'my-disputes'));
foreach (\$routes as \$r) {
    \$mw = implode(', ', \$r->middleware());
    \$hasAuth = str_contains(\$mw, 'GymiesAuthMiddleware');
    echo (\$hasAuth ? '  ✅' : '  ❌') . ' ' . \$r->methods()[0] . ' ' . \$r->uri() . \" [auth: \" . (\$hasAuth ? 'ja' : 'NEE') . \"]\n\";
}
"

echo ""
echo "============================================"
echo "  Deploy complete!                          "
echo "  Test: open 'Geschillen' in de app         "
echo "============================================"
