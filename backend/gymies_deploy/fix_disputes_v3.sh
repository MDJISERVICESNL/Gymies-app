#!/bin/bash
# =============================================================================
# Fix: is_dispute kolom toevoegen + bestaande dispute-tickets markeren
# =============================================================================
# Run: ssh gymies "bash -s" < backend/gymies_deploy/fix_disputes_v3.sh
# =============================================================================

set -e
cd /var/www/gymies

echo "============================================"
echo "  FIX: is_dispute kolom + markering          "
echo "============================================"
echo ""

echo "▸ Step 1: is_dispute kolom toevoegen..."

php artisan tinker --execute='
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;
use Illuminate\Database\Schema\Blueprint;

if (!Schema::hasColumn("gymies_support_tickets", "is_dispute")) {
    Schema::table("gymies_support_tickets", function (Blueprint $t) {
        $t->boolean("is_dispute")->default(false)->after("status");
    });
    echo "  ✅ is_dispute kolom toegevoegd\n";
} else {
    echo "  ⏭️ is_dispute kolom bestaat al\n";
}
'

echo ""
echo "▸ Step 2: Bestaande tickets tonen..."

php artisan tinker --execute='
use Illuminate\Support\Facades\DB;

$tickets = DB::table("gymies_support_tickets")->orderByDesc("created_at")->get(["id", "user_id", "subject", "category", "status", "is_dispute"]);
echo "  Alle tickets:\n";
foreach ($tickets as $t) {
    $disp = $t->is_dispute ? "YES" : "no";
    echo "  #{$t->id} | user:{$t->user_id} | cat:{$t->category} | status:{$t->status} | dispute:{$disp} | {$t->subject}\n";
}
echo "\n  Welke tickets moeten als geschil gemarkeerd worden?\n";
echo "  → Run fix_disputes_v3_mark.sh met de juiste IDs\n";
'

echo ""
echo "============================================"
echo "  Kolom toegevoegd! Markeer nu de tickets.   "
echo "============================================"
