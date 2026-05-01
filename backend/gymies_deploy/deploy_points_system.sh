#!/bin/bash
# =============================================================================
# Deploy: Gymies Punten systeem — routes + tabellen + regels
# =============================================================================
# Run: ssh gymies "bash -s" < backend/gymies_deploy/deploy_points_system.sh
# =============================================================================

set -e
cd /var/www/gymies

echo "============================================"
echo "  GYMIES: Deploy Punten Systeem             "
echo "============================================"
echo ""

# ── Step 1: Voeg points routes toe aan routes/web.php ───────────────────
echo "▸ Step 1: Points routes toevoegen..."

ROUTES_FILE="/var/www/gymies/routes/web.php"

if grep -q "points/balance" "$ROUTES_FILE" 2>/dev/null; then
    echo "  ⏭️ Points routes bestaan al"
else
    # Zoek de referral/my-code regel en voeg points routes erna toe
    cat > /tmp/patch_points_routes.php << 'PATCHEOF'
<?php
$file = $argv[1];
$content = file_get_contents($file);

$marker = "Route::get('referral/my-code',";

$pointsRoutes = <<<'ROUTES'

        // Gymies Punten: saldo, geschiedenis, inwisselen
        Route::get('points/balance', [\App\Http\Controllers\Gymies\GymiesPointsController::class, 'balance'])->name('points.balance');
        Route::get('points/history', [\App\Http\Controllers\Gymies\GymiesPointsController::class, 'history'])->name('points.history');
        Route::post('points/redeem', [\App\Http\Controllers\Gymies\GymiesPointsController::class, 'redeem'])->name('points.redeem');
ROUTES;

// Zoek de referral/my-code regel en voeg points routes toe na de volledige regel
$pos = strpos($content, $marker);
if ($pos !== false) {
    // Vind het einde van de regel (na de ;)
    $lineEnd = strpos($content, "\n", $pos);
    if ($lineEnd !== false) {
        $content = substr($content, 0, $lineEnd + 1) . $pointsRoutes . substr($content, $lineEnd + 1);
        file_put_contents($file, $content);
        echo "  ✅ Points routes toegevoegd na referral/my-code\n";
    } else {
        echo "  ⚠️ Kon einde van regel niet vinden\n";
    }
} else {
    echo "  ⚠️ Marker 'referral/my-code' niet gevonden — voeg routes handmatig toe\n";
}
PATCHEOF

    php /tmp/patch_points_routes.php "$ROUTES_FILE"
    rm -f /tmp/patch_points_routes.php
fi

echo ""

# ── Step 2: Controller bestanden deployen ───────────────────────────────
echo "▸ Step 2: Controllers deployen..."

CTRL_DIR="/var/www/gymies/app/Http/Controllers/Gymies"

# GymiesPointsController.php
if [ -f "$CTRL_DIR/GymiesPointsController.php" ]; then
    echo "  ⏭️ GymiesPointsController.php bestaat al"
else
    echo "  ⚠️ GymiesPointsController.php ontbreekt — kopieer handmatig"
fi

# GymiesPointsService.php
if [ -f "$CTRL_DIR/GymiesPointsService.php" ]; then
    echo "  ⏭️ GymiesPointsService.php bestaat al"
else
    echo "  ⚠️ GymiesPointsService.php ontbreekt — kopieer handmatig"
fi

echo ""

# ── Step 3: Database tabellen + kolom aanmaken ──────────────────────────
echo "▸ Step 3: Database tabellen aanmaken..."

php artisan tinker --execute="
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;
use Illuminate\Database\Schema\Blueprint;

// 1. gymies_users.gymies_points kolom
if (!Schema::hasColumn('gymies_users', 'gymies_points')) {
    Schema::table('gymies_users', function (Blueprint \$t) {
        \$t->unsignedInteger('gymies_points')->default(0)->after('email');
    });
    echo \"  ✅ gymies_users.gymies_points kolom toegevoegd\n\";
} else {
    echo \"  ⏭️ gymies_users.gymies_points bestaat al\n\";
}

// 2. gymies_points_rules tabel
if (!Schema::hasTable('gymies_points_rules')) {
    Schema::create('gymies_points_rules', function (Blueprint \$t) {
        \$t->bigIncrements('id');
        \$t->string('event_type', 64)->unique();
        \$t->integer('points_awarded')->default(0);
        \$t->json('conditions_json')->nullable();
        \$t->string('label', 128)->nullable();
        \$t->string('description', 255)->nullable();
        \$t->boolean('is_active')->default(true);
        \$t->timestamps();
    });
    echo \"  ✅ gymies_points_rules tabel aangemaakt\n\";
} else {
    echo \"  ⏭️ gymies_points_rules bestaat al\n\";
}

// 3. gymies_points_ledger tabel
if (!Schema::hasTable('gymies_points_ledger')) {
    Schema::create('gymies_points_ledger', function (Blueprint \$t) {
        \$t->bigIncrements('id');
        \$t->unsignedBigInteger('user_id')->index();
        \$t->integer('delta');
        \$t->unsignedInteger('balance_after')->default(0);
        \$t->string('event_type', 64)->index();
        \$t->unsignedBigInteger('ref_id')->nullable();
        \$t->string('ref_table', 64)->nullable();
        \$t->string('description', 255)->nullable();
        \$t->timestamp('created_at')->useCurrent()->index();
    });
    echo \"  ✅ gymies_points_ledger tabel aangemaakt\n\";
} else {
    echo \"  ⏭️ gymies_points_ledger bestaat al\n\";
}

// 4. gymies_points_redemptions tabel
if (!Schema::hasTable('gymies_points_redemptions')) {
    Schema::create('gymies_points_redemptions', function (Blueprint \$t) {
        \$t->bigIncrements('id');
        \$t->unsignedBigInteger('user_id')->index();
        \$t->unsignedInteger('points_spent')->default(0);
        \$t->enum('reward_type', ['session_credit', 'subscription_discount', 'free_session', 'custom'])->default('session_credit');
        \$t->unsignedInteger('reward_cents')->default(0);
        \$t->json('reward_meta')->nullable();
        \$t->enum('status', ['pending', 'applied', 'expired', 'cancelled'])->default('pending');
        \$t->timestamp('applied_at')->nullable();
        \$t->timestamp('expires_at')->nullable();
        \$t->timestamp('created_at')->useCurrent();
    });
    echo \"  ✅ gymies_points_redemptions tabel aangemaakt\n\";
} else {
    echo \"  ⏭️ gymies_points_redemptions bestaat al\n\";
}

echo \"\n\";

// 5. Default puntenregels inserten
\$rules = [
    ['event_type' => 'session_completed',    'points_awarded' => 10, 'label' => 'Sessie voltooid',     'description' => '+10 punten voor een voltooide sessie'],
    ['event_type' => 'review_placed',        'points_awarded' => 5,  'label' => 'Review geplaatst',    'description' => '+5 punten voor het plaatsen van een review'],
    ['event_type' => 'referral_signup',       'points_awarded' => 25, 'label' => 'Vriend uitgenodigd',  'description' => '+25 punten wanneer een vriend zich aanmeldt'],
    ['event_type' => 'referral_first_session','points_awarded' => 15, 'label' => 'Vriend eerste sessie','description' => '+15 punten wanneer je vriend de eerste sessie voltooit'],
];

\$inserted = 0;
foreach (\$rules as \$rule) {
    \$exists = DB::table('gymies_points_rules')->where('event_type', \$rule['event_type'])->exists();
    if (!\$exists) {
        DB::table('gymies_points_rules')->insert(array_merge(\$rule, [
            'is_active' => true,
            'created_at' => now(),
            'updated_at' => now(),
        ]));
        \$inserted++;
        echo \"  ✅ Regel: {\$rule['event_type']} (+{\$rule['points_awarded']})\n\";
    } else {
        echo \"  ⏭️ Regel {\$rule['event_type']} bestaat al\n\";
    }
}
echo \"  → \$inserted regels toegevoegd\n\";
"

echo ""

# ── Step 4: Cache leegmaken ─────────────────────────────────────────────
echo "▸ Step 4: Caches legen..."
php artisan config:clear 2>/dev/null || true
php artisan route:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true
echo "  ✅ Done"

echo ""

# ── Step 5: Verificatie ─────────────────────────────────────────────────
echo "▸ Step 5: Verificatie..."

php artisan tinker --execute="
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

\$checks = [
    'gymies_users.gymies_points' => Schema::hasColumn('gymies_users', 'gymies_points'),
    'gymies_points_rules' => Schema::hasTable('gymies_points_rules'),
    'gymies_points_ledger' => Schema::hasTable('gymies_points_ledger'),
    'gymies_points_redemptions' => Schema::hasTable('gymies_points_redemptions'),
];
\$allOk = true;
foreach (\$checks as \$name => \$ok) {
    if (!\$ok) \$allOk = false;
    echo (\$ok ? '  ✅' : '  ❌') . \" \$name\n\";
}

// Check route
\$routeExists = \Illuminate\Support\Facades\Route::has('api.gymies.points.balance');
echo (\$routeExists ? '  ✅' : '  ❌') . \" Route: points/balance\n\";
if (!\$routeExists) \$allOk = false;

\$rulesCount = DB::table('gymies_points_rules')->count();
echo \"  📊 Actieve regels: \$rulesCount\n\";

echo \$allOk ? \"\n🎉 Punten systeem actief!\n\" : \"\n⚠️ Sommige onderdelen missen!\n\";
"

echo ""
echo "============================================"
echo "  Deploy complete!                          "
echo "============================================"
