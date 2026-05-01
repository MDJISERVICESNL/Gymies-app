#!/bin/bash
set -e

##############################################
# GYMIES PROMOTIE-SYSTEEM DEPLOY SCRIPT
# Draai dit op je server vanuit /var/www/gymies
#
# Gebruik:
#   ssh amazonekey
#   cd /var/www/gymies
#   bash deploy-promotions.sh
##############################################

PROJECT_DIR="/var/www/gymies"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo ""
echo "============================================"
echo "  GYMIES PROMOTIE-SYSTEEM DEPLOY"
echo "  $(date)"
echo "============================================"
echo ""

cd "$PROJECT_DIR"

# ─── STAP 1: Check dat we in het juiste project zitten ───
if [ ! -f "artisan" ]; then
    echo "❌ FOUT: artisan niet gevonden in $PROJECT_DIR"
    echo "   Zorg dat je in de Laravel project-map zit."
    exit 1
fi
echo "✅ Laravel project gevonden"

# ─── STAP 2: Database backup ───
echo ""
echo "📦 Database backup maken..."
DB_HOST=$(php artisan tinker --execute="echo config('database.connections.mysql.host');" 2>/dev/null | tail -1)
DB_NAME=$(php artisan tinker --execute="echo config('database.connections.mysql.database');" 2>/dev/null | tail -1)
DB_USER=$(php artisan tinker --execute="echo config('database.connections.mysql.username');" 2>/dev/null | tail -1)
DB_PASS=$(php artisan tinker --execute="echo config('database.connections.mysql.password');" 2>/dev/null | tail -1)

BACKUP_FILE="$HOME/gymies_backup_${TIMESTAMP}.sql"
mysqldump -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" "$DB_NAME" > "$BACKUP_FILE" 2>/dev/null

if [ -f "$BACKUP_FILE" ] && [ -s "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "✅ Backup gemaakt: $BACKUP_FILE ($BACKUP_SIZE)"
else
    echo "⚠️  Backup mogelijk mislukt. Wil je doorgaan? (y/n)"
    read -r response
    if [ "$response" != "y" ]; then
        echo "Deploy afgebroken."
        exit 1
    fi
fi

# ─── STAP 3: Mappen aanmaken als ze niet bestaan ───
echo ""
echo "📁 Mappen controleren..."
mkdir -p app/Models
mkdir -p app/Services
mkdir -p app/Http/Controllers/Api
mkdir -p app/Console/Commands
mkdir -p database/migrations
echo "✅ Alle mappen bestaan"

# ─── STAP 4: Bestanden kopiëren ───
echo ""
echo "📄 Bestanden kopiëren..."

# Migrations
cp "$SCRIPT_DIR/2026_04_20_create_promotions_table.php" \
   database/migrations/2026_04_20_000001_create_gymies_promotions_table.php
cp "$SCRIPT_DIR/2026_04_20_create_trainer_promotions_table.php" \
   database/migrations/2026_04_20_000002_create_gymies_trainer_promotions_table.php
cp "$SCRIPT_DIR/2026_04_20_add_dynamic_fields_to_plans_and_subscriptions.php" \
   database/migrations/2026_04_20_000003_add_dynamic_fields_to_plans_and_subscriptions.php
echo "  ✅ 3 migrations gekopieerd"

# Models
cp "$SCRIPT_DIR/Promotion.php" app/Models/Promotion.php
cp "$SCRIPT_DIR/TrainerPromotion.php" app/Models/TrainerPromotion.php
echo "  ✅ 2 models gekopieerd"

# Service
cp "$SCRIPT_DIR/PromotionService.php" app/Services/PromotionService.php
echo "  ✅ 1 service gekopieerd"

# Controller
cp "$SCRIPT_DIR/PromotionController.php" app/Http/Controllers/Api/PromotionController.php
echo "  ✅ 1 controller gekopieerd"

# Command
cp "$SCRIPT_DIR/ExpirePromotionsCommand.php" app/Console/Commands/ExpirePromotionsCommand.php
echo "  ✅ 1 command gekopieerd"

# ─── STAP 5: Routes toevoegen ───
echo ""
echo "🔗 Routes controleren..."
if grep -q "PromotionController" routes/api.php 2>/dev/null; then
    echo "  ⚠️  PromotionController routes bestaan al in routes/api.php — overgeslagen"
else
    cat >> routes/api.php << 'ROUTES'

// ── Promotie routes (Gymies platform promoties) ──
Route::prefix('promo')->middleware('auth:sanctum')->group(function () {
    Route::post('/validate', [\App\Http\Controllers\Api\PromotionController::class, 'validate']);
    Route::get('/active', [\App\Http\Controllers\Api\PromotionController::class, 'active']);
    Route::post('/activate', [\App\Http\Controllers\Api\PromotionController::class, 'activate']);
});
ROUTES
    echo "  ✅ Routes toegevoegd aan routes/api.php"
fi

# ─── STAP 6: Migrations draaien ───
echo ""
echo "🗄️  Migrations draaien..."
php artisan migrate --force
echo "✅ Migrations voltooid"

# ─── STAP 7: Cache clearen ───
echo ""
echo "🧹 Cache opschonen..."
php artisan config:clear
php artisan route:clear
php artisan cache:clear
echo "✅ Cache opgeschoond"

# ─── STAP 8: Verificatie ───
echo ""
echo "🔍 Verificatie..."

# Check tabellen
PROMO_TABLE=$(php artisan tinker --execute="echo Schema::hasTable('gymies_promotions') ? 'YES' : 'NO';" 2>/dev/null | tail -1)
TRAINER_PROMO_TABLE=$(php artisan tinker --execute="echo Schema::hasTable('gymies_trainer_promotions') ? 'YES' : 'NO';" 2>/dev/null | tail -1)

if [ "$PROMO_TABLE" = "YES" ]; then
    echo "  ✅ gymies_promotions tabel aangemaakt"
else
    echo "  ❌ gymies_promotions tabel NIET gevonden"
fi

if [ "$TRAINER_PROMO_TABLE" = "YES" ]; then
    echo "  ✅ gymies_trainer_promotions tabel aangemaakt"
else
    echo "  ❌ gymies_trainer_promotions tabel NIET gevonden"
fi

# Check nieuwe kolommen op gymies_plans
PLANS_SUBTITLE=$(php artisan tinker --execute="echo Schema::hasColumn('gymies_plans', 'subtitle') ? 'YES' : 'NO';" 2>/dev/null | tail -1)
if [ "$PLANS_SUBTITLE" = "YES" ]; then
    echo "  ✅ gymies_plans dynamische velden toegevoegd"
else
    echo "  ❌ gymies_plans dynamische velden NIET gevonden"
fi

# Check nieuwe kolom op gymies_subscriptions
SUB_PROMO=$(php artisan tinker --execute="echo Schema::hasColumn('gymies_subscriptions', 'promotion_id') ? 'YES' : 'NO';" 2>/dev/null | tail -1)
if [ "$SUB_PROMO" = "YES" ]; then
    echo "  ✅ gymies_subscriptions promotion_id kolom toegevoegd"
else
    echo "  ❌ gymies_subscriptions promotion_id kolom NIET gevonden"
fi

# Check routes
echo ""
php artisan route:list --name=promo 2>/dev/null | head -10 || echo "  ⚠️  Route check niet beschikbaar"

# ─── KLAAR ───
echo ""
echo "============================================"
echo "  ✅ DEPLOY VOLTOOID"
echo "============================================"
echo ""
echo "Volgende stappen:"
echo "  1. Test: php artisan tinker"
echo "     > App\Models\Promotion::count();"
echo ""
echo "  2. Maak je eerste promotie:"
echo "     > App\Models\Promotion::create(["
echo "     >   'name' => 'Test promotie',"
echo "     >   'slug' => 'test-2026',"
echo "     >   'type' => 'campaign',"
echo "     >   'discount_type' => 'percent',"
echo "     >   'value_cents' => 50,"
echo "     >   'display_label' => '50% korting!',"
echo "     >   'display_badge' => 'TEST',"
echo "     >   'is_active' => true,"
echo "     > ]);"
echo ""
echo "  3. Voeg aan app/Console/Kernel.php toe:"
echo "     \$schedule->command('promotions:expire')->dailyAt('02:00');"
echo ""
echo "  4. Update je PlansController (GET /api/plans):"
echo "     \$promotionService = app(PromotionService::class);"
echo "     \$plans = \$promotionService->enrichPlansWithPromotions(\$plans, auth()->id());"
echo ""
echo "Backup staat in: $BACKUP_FILE"
echo ""
