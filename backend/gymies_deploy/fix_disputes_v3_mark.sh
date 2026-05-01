#!/bin/bash
# =============================================================================
# Markeer specifieke support tickets als geschillen + cache legen
# =============================================================================
# Run: ssh gymies "bash -s" < backend/gymies_deploy/fix_disputes_v3_mark.sh
# =============================================================================

set -e
cd /var/www/gymies

echo "▸ Tickets markeren als geschil..."

php artisan tinker --execute='
use Illuminate\Support\Facades\DB;

// Markeer tickets #11 en #12 als geschillen (pas IDs aan indien nodig)
$ids = [11, 12];

$updated = DB::table("gymies_support_tickets")
    ->whereIn("id", $ids)
    ->update(["is_dispute" => true]);

echo "  ✅ {$updated} ticket(s) gemarkeerd als geschil\n";

// Verificatie
$disputes = DB::table("gymies_support_tickets")->where("is_dispute", true)->get(["id", "user_id", "subject", "category", "status"]);
echo "  📊 Geschillen in support_tickets:\n";
foreach ($disputes as $t) {
    echo "  → #{$t->id} | user:{$t->user_id} | {$t->subject} [{$t->status}]\n";
}
'

echo ""
echo "▸ Caches legen..."
php artisan config:clear 2>/dev/null || true
php artisan route:clear 2>/dev/null || true
php artisan cache:clear 2>/dev/null || true
echo "  ✅ Done"

echo ""
echo "============================================"
echo "  Klaar! Test Geschillen in de app.          "
echo "============================================"
