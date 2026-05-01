#!/bin/bash
set -e

##############################################
# GYMIES PROMOTIE ANALYTICS — DEPLOY
#
# Gebruik:
#   cd /var/www/gymies
#   sudo bash /tmp/backend-promotions/backend-promotions/deploy-analytics.sh
##############################################

PROJECT_DIR="/var/www/gymies"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
info() { echo -e "  ${BLUE}ℹ️  $1${NC}"; }

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  GYMIES PROMOTIE ANALYTICS DEPLOY${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

cd "$PROJECT_DIR"

# ─── Stap 1: Controller kopiëren ───
echo -e "${BLUE}[1/4] Analytics controller kopiëren...${NC}"
cp "$SCRIPT_DIR/PromotionAnalyticsController.php" app/Http/Controllers/Api/PromotionAnalyticsController.php
ok "PromotionAnalyticsController gekopieerd"

# ─── Stap 2: Routes toevoegen ───
echo ""
echo -e "${BLUE}[2/4] Admin analytics routes toevoegen...${NC}"

if grep -q "PromotionAnalyticsController" routes/api.php 2>/dev/null; then
    warn "Analytics routes bestaan al — overgeslagen"
else
    cat >> routes/api.php << 'ROUTES'

// ── Promotie Analytics (admin) ──
Route::prefix('admin/promo-stats')->middleware('auth:sanctum')->group(function () {
    Route::get('/compare', [\App\Http\Controllers\Api\PromotionAnalyticsController::class, 'compare']);
    Route::get('/{slug}', [\App\Http\Controllers\Api\PromotionAnalyticsController::class, 'detail']);
    Route::get('/', [\App\Http\Controllers\Api\PromotionAnalyticsController::class, 'stats']);
});
ROUTES
    ok "3 analytics routes toegevoegd"
fi

# ─── Stap 3: Syntax check ───
echo ""
echo -e "${BLUE}[3/4] Syntax check...${NC}"
php -l app/Http/Controllers/Api/PromotionAnalyticsController.php > /dev/null 2>&1
ok "Geen syntax errors"

# ─── Stap 4: Cache clearen ───
echo ""
echo -e "${BLUE}[4/4] Cache clearen...${NC}"
php artisan optimize:clear > /dev/null 2>&1
php artisan optimize > /dev/null 2>&1
ok "Cache opgeschoond"

# ─── Klaar ───
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  ✅ ANALYTICS DEPLOY VOLTOOID${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${BLUE}Beschikbare endpoints:${NC}"
echo ""
echo "  GET /api/admin/promo-stats"
echo "      Overzicht alle promoties met conversie + omzet"
echo "      Filters: ?type=campaign  ?from=2026-01-01  ?until=2026-12-31"
echo ""
echo "  GET /api/admin/promo-stats/{slug}"
echo "      Detail van 1 promotie met alle trainers"
echo "      Voorbeeld: /api/admin/promo-stats/zomeractie-2026"
echo ""
echo "  GET /api/admin/promo-stats/compare?slugs=slug1,slug2"
echo "      Vergelijk promoties naast elkaar"
echo "      Voorbeeld: ?slugs=zomeractie-2026,pro-zomer-2026"
echo ""
echo -e "${BLUE}── Quick test ──${NC}"
echo '  curl -s localhost/api/admin/promo-stats | php -r "echo json_encode(json_decode(file_get_contents(\"php://stdin\")), JSON_PRETTY_PRINT);"'
echo ""
