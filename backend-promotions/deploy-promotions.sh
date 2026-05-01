#!/bin/bash
set -e

##############################################
# GYMIES PROMOTIE-SYSTEEM — VOLLEDIGE DEPLOY
#
# Dit script doet ALLES:
#   1. Database backup
#   2. Bestanden kopiëren (migrations, models, service, controller, command)
#   3. Migrations draaien
#   4. Routes toevoegen aan routes/api.php
#   5. PlansController patchen (enrichPlansWithPromotions)
#   6. MollieWebhookController patchen (handleMolliePayment + handleTrialConversion)
#   7. Kernel.php patchen (scheduled command)
#   8. PromotionController validate fix (gymies_promotions table)
#   9. Cache clearen
#  10. Verificatie
#
# Gebruik:
#   ssh amazonekey
#   cd /var/www/gymies
#   bash /tmp/backend-promotions/deploy-promotions.sh
##############################################

PROJECT_DIR="/var/www/gymies"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$PROJECT_DIR/claude-backups/$TIMESTAMP"
ERRORS=0

# ─── Kleuren ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; ERRORS=$((ERRORS + 1)); }
info() { echo -e "  ${BLUE}ℹ️  $1${NC}"; }

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  GYMIES PROMOTIE-SYSTEEM — VOLLEDIGE DEPLOY${NC}"
echo -e "${BLUE}  $(date)${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

cd "$PROJECT_DIR"

# ═══════════════════════════════════════════
#  STAP 0: Pre-flight checks
# ═══════════════════════════════════════════
echo -e "${BLUE}[0/10] Pre-flight checks...${NC}"

if [ ! -f "artisan" ]; then
    fail "artisan niet gevonden in $PROJECT_DIR"
    echo "   Zorg dat je in de Laravel project-map zit."
    exit 1
fi
ok "Laravel project gevonden"

if [ ! -d "$SCRIPT_DIR" ]; then
    fail "Script directory niet gevonden: $SCRIPT_DIR"
    exit 1
fi

# Check of alle bronbestanden aanwezig zijn
REQUIRED_FILES=(
    "2026_04_20_create_promotions_table.php"
    "2026_04_20_create_trainer_promotions_table.php"
    "2026_04_20_add_dynamic_fields_to_plans_and_subscriptions.php"
    "Promotion.php"
    "TrainerPromotion.php"
    "PromotionService.php"
    "PromotionController.php"
    "ExpirePromotionsCommand.php"
)

for f in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$f" ]; then
        fail "Bronbestand ontbreekt: $f"
        exit 1
    fi
done
ok "Alle bronbestanden aanwezig (${#REQUIRED_FILES[@]} bestanden)"

# ═══════════════════════════════════════════
#  STAP 1: Backup van geraakt bestanden
# ═══════════════════════════════════════════
echo ""
echo -e "${BLUE}[1/10] Backups maken...${NC}"

mkdir -p "$BACKUP_DIR"

# Database backup
DB_NAME=$(php artisan tinker --execute="echo config('database.connections.mysql.database');" 2>/dev/null | tail -1)
DB_USER=$(php artisan tinker --execute="echo config('database.connections.mysql.username');" 2>/dev/null | tail -1)
DB_PASS=$(php artisan tinker --execute="echo config('database.connections.mysql.password');" 2>/dev/null | tail -1)
DB_HOST=$(php artisan tinker --execute="echo config('database.connections.mysql.host');" 2>/dev/null | tail -1)

BACKUP_SQL="$BACKUP_DIR/database_${DB_NAME}.sql"
mysqldump -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" "$DB_NAME" > "$BACKUP_SQL" 2>/dev/null

if [ -f "$BACKUP_SQL" ] && [ -s "$BACKUP_SQL" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_SQL" | cut -f1)
    ok "Database backup: $BACKUP_SQL ($BACKUP_SIZE)"
else
    warn "Database backup mogelijk mislukt — ga verder (bestanden worden ook gebackupt)"
fi

# Backup bestaande bestanden die we gaan patchen
FILES_TO_BACKUP=(
    "routes/api.php"
    "app/Console/Kernel.php"
)

# Zoek PlansController
PLANS_CTRL=$(find app/Http/Controllers -name "PlansController.php" -o -name "PlanController.php" 2>/dev/null | head -1)
if [ -n "$PLANS_CTRL" ]; then
    FILES_TO_BACKUP+=("$PLANS_CTRL")
fi

# Zoek MollieWebhookController
MOLLIE_CTRL=$(find app/Http/Controllers -name "*ollie*Controller.php" -o -name "*Webhook*Controller.php" -o -name "*webhook*Controller.php" 2>/dev/null | head -3)
if [ -n "$MOLLIE_CTRL" ]; then
    while IFS= read -r line; do
        FILES_TO_BACKUP+=("$line")
    done <<< "$MOLLIE_CTRL"
fi

# Zoek SubscriptionController
SUB_CTRL=$(find app/Http/Controllers -name "*Subscription*Controller.php" 2>/dev/null | head -1)
if [ -n "$SUB_CTRL" ]; then
    FILES_TO_BACKUP+=("$SUB_CTRL")
fi

for f in "${FILES_TO_BACKUP[@]}"; do
    if [ -f "$f" ]; then
        mkdir -p "$BACKUP_DIR/$(dirname "$f")"
        cp "$f" "$BACKUP_DIR/$f"
        ok "Backup: $f"
    fi
done

# ═══════════════════════════════════════════
#  STAP 2: Mappen aanmaken
# ═══════════════════════════════════════════
echo ""
echo -e "${BLUE}[2/10] Mappen controleren...${NC}"
mkdir -p app/Models
mkdir -p app/Services
mkdir -p app/Http/Controllers/Api
mkdir -p app/Console/Commands
mkdir -p database/migrations
ok "Alle mappen bestaan"

# ═══════════════════════════════════════════
#  STAP 3: Bestanden kopiëren
# ═══════════════════════════════════════════
echo ""
echo -e "${BLUE}[3/10] Bestanden kopiëren...${NC}"

# Migrations
cp "$SCRIPT_DIR/2026_04_20_create_promotions_table.php" \
   database/migrations/2026_04_20_000001_create_gymies_promotions_table.php
cp "$SCRIPT_DIR/2026_04_20_create_trainer_promotions_table.php" \
   database/migrations/2026_04_20_000002_create_gymies_trainer_promotions_table.php
cp "$SCRIPT_DIR/2026_04_20_add_dynamic_fields_to_plans_and_subscriptions.php" \
   database/migrations/2026_04_20_000003_add_dynamic_fields_to_plans_and_subscriptions.php
ok "3 migrations gekopieerd"

# Models
cp "$SCRIPT_DIR/Promotion.php" app/Models/Promotion.php
cp "$SCRIPT_DIR/TrainerPromotion.php" app/Models/TrainerPromotion.php
ok "2 models gekopieerd"

# Service
cp "$SCRIPT_DIR/PromotionService.php" app/Services/PromotionService.php
ok "1 service gekopieerd"

# Controller
cp "$SCRIPT_DIR/PromotionController.php" app/Http/Controllers/Api/PromotionController.php
ok "1 controller gekopieerd"

# Command
cp "$SCRIPT_DIR/ExpirePromotionsCommand.php" app/Console/Commands/ExpirePromotionsCommand.php
ok "1 command gekopieerd"

# ═══════════════════════════════════════════
#  STAP 4: Fix PromotionController validate rule
# ═══════════════════════════════════════════
echo ""
echo -e "${BLUE}[4/10] PromotionController fixen...${NC}"

# De 'exists:promotions,id' moet 'exists:gymies_promotions,id' zijn
PROMO_CTRL="app/Http/Controllers/Api/PromotionController.php"
if grep -q "exists:promotions,id" "$PROMO_CTRL" 2>/dev/null; then
    sed -i "s/exists:promotions,id/exists:gymies_promotions,id/g" "$PROMO_CTRL"
    ok "Validation rule gefixed: exists:gymies_promotions,id"
else
    ok "Validation rule is al correct"
fi

# ═══════════════════════════════════════════
#  STAP 5: Routes toevoegen
# ═══════════════════════════════════════════
echo ""
echo -e "${BLUE}[5/10] Routes toevoegen aan routes/api.php...${NC}"

if grep -q "PromotionController" routes/api.php 2>/dev/null; then
    warn "PromotionController routes bestaan al — overgeslagen"
else
    cat >> routes/api.php << 'ROUTES'

// ── Promotie routes (Gymies platform promoties) ──
Route::prefix('promo')->middleware('auth:sanctum')->group(function () {
    Route::post('/validate', [\App\Http\Controllers\Api\PromotionController::class, 'validate']);
    Route::get('/active', [\App\Http\Controllers\Api\PromotionController::class, 'active']);
    Route::post('/activate', [\App\Http\Controllers\Api\PromotionController::class, 'activate']);
});
ROUTES
    ok "3 promo routes toegevoegd aan routes/api.php"
fi

# ═══════════════════════════════════════════
#  STAP 6: PlansController patchen
# ═══════════════════════════════════════════
echo ""
echo -e "${BLUE}[6/10] PlansController patchen...${NC}"

if [ -z "$PLANS_CTRL" ]; then
    PLANS_CTRL=$(find app/Http/Controllers -name "Plan*Controller.php" 2>/dev/null | head -1)
fi

if [ -z "$PLANS_CTRL" ]; then
    warn "Geen PlansController gevonden — handmatig toevoegen nodig"
    info "Zoek je PlansController en voeg dit toe na het ophalen van plans:"
    info '  $promotionService = app(\App\Services\PromotionService::class);'
    info '  $plans = $promotionService->enrichPlansWithPromotions($plans, auth()->id());'
else
    info "Gevonden: $PLANS_CTRL"

    # Check of al gepatcht
    if grep -q "PromotionService" "$PLANS_CTRL" 2>/dev/null; then
        warn "PlansController bevat al PromotionService — overgeslagen"
    else
        # Voeg use-statement toe bovenaan (na laatste use-statement)
        LAST_USE_LINE=$(grep -n "^use " "$PLANS_CTRL" | tail -1 | cut -d: -f1)
        if [ -n "$LAST_USE_LINE" ]; then
            sed -i "${LAST_USE_LINE}a use App\\\\Services\\\\PromotionService;" "$PLANS_CTRL"
            ok "use PromotionService toegevoegd aan $PLANS_CTRL"
        fi

        # Zoek de return-response in de plans method
        # We zoeken naar een return met json/plans data
        # Voeg de enrichment toe vóór de return
        RETURN_LINE=$(grep -n "return.*response\|return.*json\|return.*plans\|return.*Plan::" "$PLANS_CTRL" | tail -1 | cut -d: -f1)

        if [ -n "$RETURN_LINE" ]; then
            # Voeg promotie-enrichment toe 2 regels boven de return
            INJECT_LINE=$((RETURN_LINE - 1))
            sed -i "${INJECT_LINE}a\\
\\
        // ── Promotie-systeem: verrijk plans met actieve promoties ──\\
        \$promotionService = app(\\\\App\\\\Services\\\\PromotionService::class);\\
        \$plans = \$promotionService->enrichPlansWithPromotions(\\
            is_array(\$plans) ? \$plans : \$plans->toArray(),\\
            auth()->id()\\
        );" "$PLANS_CTRL"
            ok "enrichPlansWithPromotions() geïnjecteerd in $PLANS_CTRL"
        else
            warn "Kon geen return-statement vinden in PlansController"
            info "Voeg handmatig toe vóór je return:"
            info '  $promotionService = app(PromotionService::class);'
            info '  $plans = $promotionService->enrichPlansWithPromotions($plans, auth()->id());'
        fi
    fi
fi

# ═══════════════════════════════════════════
#  STAP 7: MollieWebhookController patchen
# ═══════════════════════════════════════════
echo ""
echo -e "${BLUE}[7/10] MollieWebhookController patchen...${NC}"

# Zoek alle mogelijke webhook controllers
WEBHOOK_CTRL=""
for pattern in "*ollie*ebhook*" "*ollie*ontroller*" "*ebhook*ontroller*"; do
    FOUND=$(find app/Http/Controllers -iname "${pattern}.php" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        WEBHOOK_CTRL="$FOUND"
        break
    fi
done

if [ -z "$WEBHOOK_CTRL" ]; then
    # Probeer grep op inhoud
    WEBHOOK_CTRL=$(grep -rl "mollie\|Mollie\|webhook\|payment.*callback" app/Http/Controllers/ 2>/dev/null | head -1)
fi

if [ -z "$WEBHOOK_CTRL" ]; then
    warn "Geen MollieWebhookController gevonden — handmatig toevoegen nodig"
    info "Zoek je Mollie webhook handler en voeg toe na succesvolle betaling:"
    info '  app(\App\Services\PromotionService::class)->handleMolliePayment($trainerUserId);'
    info "En bij trial → betaald conversie:"
    info '  app(\App\Services\PromotionService::class)->handleTrialConversion($trainerUserId);'
else
    info "Gevonden: $WEBHOOK_CTRL"

    if grep -q "PromotionService" "$WEBHOOK_CTRL" 2>/dev/null; then
        warn "MollieWebhookController bevat al PromotionService — overgeslagen"
    else
        # Voeg use-statement toe
        LAST_USE_LINE=$(grep -n "^use " "$WEBHOOK_CTRL" | tail -1 | cut -d: -f1)
        if [ -n "$LAST_USE_LINE" ]; then
            sed -i "${LAST_USE_LINE}a use App\\\\Services\\\\PromotionService;" "$WEBHOOK_CTRL"
        fi

        # Zoek naar de plek waar een betaling als 'paid'/'succeeded' wordt gemarkeerd
        # Typische patronen: 'paid', 'isPaid', 'status.*paid', 'payment.*paid'
        PAID_LINE=$(grep -n "isPaid\|'paid'\|\"paid\"\|status.*=.*'paid'\|payment.*success\|succeeded" "$WEBHOOK_CTRL" | head -1 | cut -d: -f1)

        if [ -n "$PAID_LINE" ]; then
            # Zoek het einde van het if-block (volgende lege regel of volgende if/return)
            # We injecteren na de paid-check
            INJECT_AFTER=$((PAID_LINE + 2))
            sed -i "${INJECT_AFTER}a\\
\\
            // ── Promotie-systeem: verwerk maandelijkse korting bij betaling ──\\
            try {\\
                \$promotionService = app(\\\\App\\\\Services\\\\PromotionService::class);\\
                \$promotionService->handleMolliePayment(\$subscription->trainer_user_id ?? \$payment->metadata->trainer_user_id ?? null);\\
            } catch (\\\\Throwable \$e) {\\
                \\\\Log::warning('Promo handleMolliePayment gefaald: ' . \$e->getMessage());\\
            }" "$WEBHOOK_CTRL"
            ok "handleMolliePayment() geïnjecteerd in $WEBHOOK_CTRL"
        else
            warn "Kon geen 'paid' status check vinden in webhook controller"
            info "Voeg handmatig toe bij succesvolle betaling:"
            info '  app(PromotionService::class)->handleMolliePayment($trainerUserId);'
        fi

        # Zoek naar trial conversion punt
        TRIAL_LINE=$(grep -n "trial\|first.*payment\|mandate.*valid\|firstPayment\|isFirstPayment" "$WEBHOOK_CTRL" | head -1 | cut -d: -f1)

        if [ -n "$TRIAL_LINE" ]; then
            INJECT_AFTER=$((TRIAL_LINE + 2))
            sed -i "${INJECT_AFTER}a\\
\\
            // ── Promotie-systeem: trial → betaald conversie ──\\
            try {\\
                \$promotionService = app(\\\\App\\\\Services\\\\PromotionService::class);\\
                \$promotionService->handleTrialConversion(\$subscription->trainer_user_id ?? null);\\
            } catch (\\\\Throwable \$e) {\\
                \\\\Log::warning('Promo handleTrialConversion gefaald: ' . \$e->getMessage());\\
            }" "$WEBHOOK_CTRL"
            ok "handleTrialConversion() geïnjecteerd in $WEBHOOK_CTRL"
        else
            info "Geen trial-specifieke code gevonden (wordt later geïntegreerd indien nodig)"
        fi
    fi
fi

# ═══════════════════════════════════════════
#  STAP 8: Kernel.php patchen (scheduler)
# ═══════════════════════════════════════════
echo ""
echo -e "${BLUE}[8/10] Kernel.php patchen...${NC}"

KERNEL_FILE="app/Console/Kernel.php"
if [ ! -f "$KERNEL_FILE" ]; then
    warn "Kernel.php niet gevonden op standaard locatie"
    KERNEL_FILE=$(find app -name "Kernel.php" -path "*/Console/*" 2>/dev/null | head -1)
fi

if [ -z "$KERNEL_FILE" ] || [ ! -f "$KERNEL_FILE" ]; then
    warn "Kernel.php niet gevonden — handmatig toevoegen nodig"
    info 'Voeg toe aan de schedule() method in app/Console/Kernel.php:'
    info '  $schedule->command("promotions:expire")->dailyAt("02:00");'
else
    info "Gevonden: $KERNEL_FILE"

    if grep -q "promotions:expire" "$KERNEL_FILE" 2>/dev/null; then
        warn "promotions:expire staat al in Kernel.php — overgeslagen"
    else
        # Zoek de schedule method
        SCHEDULE_LINE=$(grep -n "function schedule" "$KERNEL_FILE" | head -1 | cut -d: -f1)

        if [ -n "$SCHEDULE_LINE" ]; then
            # Zoek de opening brace na de schedule method
            BRACE_LINE=$(tail -n +"$SCHEDULE_LINE" "$KERNEL_FILE" | grep -n "{" | head -1 | cut -d: -f1)
            INJECT_LINE=$((SCHEDULE_LINE + BRACE_LINE - 1))

            sed -i "${INJECT_LINE}a\\
\\
        // ── Promotie-systeem: verlopen promoties dagelijks opschonen ──\\
        \$schedule->command('promotions:expire')->dailyAt('02:00');" "$KERNEL_FILE"
            ok "promotions:expire toegevoegd aan Kernel.php scheduler"
        else
            # Misschien gebruikt Laravel 11+ bootstrap/app.php stijl
            warn "Geen schedule() method gevonden in Kernel.php"
            info "Laravel 11+ detected? Voeg toe aan bootstrap/app.php of routes/console.php:"
            info '  Schedule::command("promotions:expire")->dailyAt("02:00");'
        fi
    fi
fi

# ═══════════════════════════════════════════
#  STAP 9: PHP syntax check + Migrations + cache
# ═══════════════════════════════════════════
echo ""
echo -e "${BLUE}[9/10] Syntax check, migrations, cache...${NC}"

# PHP syntax check op alle gewijzigde bestanden
SYNTAX_OK=true
for f in \
    "app/Models/Promotion.php" \
    "app/Models/TrainerPromotion.php" \
    "app/Services/PromotionService.php" \
    "app/Http/Controllers/Api/PromotionController.php" \
    "app/Console/Commands/ExpirePromotionsCommand.php" \
    "routes/api.php"; do
    if [ -f "$f" ]; then
        if ! php -l "$f" > /dev/null 2>&1; then
            fail "PHP syntax error in $f"
            SYNTAX_OK=false
        fi
    fi
done

# Check ook gepatche bestanden
if [ -n "$PLANS_CTRL" ] && [ -f "$PLANS_CTRL" ]; then
    if ! php -l "$PLANS_CTRL" > /dev/null 2>&1; then
        fail "PHP syntax error in $PLANS_CTRL — rollback!"
        cp "$BACKUP_DIR/$PLANS_CTRL" "$PLANS_CTRL"
        warn "PlansController teruggerold naar backup"
        SYNTAX_OK=false
    fi
fi

if [ -n "$WEBHOOK_CTRL" ] && [ -f "$WEBHOOK_CTRL" ]; then
    if ! php -l "$WEBHOOK_CTRL" > /dev/null 2>&1; then
        fail "PHP syntax error in $WEBHOOK_CTRL — rollback!"
        cp "$BACKUP_DIR/$WEBHOOK_CTRL" "$WEBHOOK_CTRL"
        warn "WebhookController teruggerold naar backup"
        SYNTAX_OK=false
    fi
fi

if [ "$SYNTAX_OK" = true ]; then
    ok "Alle PHP bestanden zijn syntax-correct"
else
    warn "Er waren syntax errors — gepatche bestanden zijn teruggerold"
fi

# Migrations
php artisan migrate --force
ok "Migrations voltooid"

php artisan config:clear
php artisan route:clear
php artisan cache:clear
php artisan optimize
ok "Cache opgeschoond + geoptimaliseerd"

# ═══════════════════════════════════════════
#  STAP 10: Verificatie
# ═══════════════════════════════════════════
echo ""
echo -e "${BLUE}[10/10] Verificatie...${NC}"

# Check tabellen
PROMO_TABLE=$(php artisan tinker --execute="echo Schema::hasTable('gymies_promotions') ? 'YES' : 'NO';" 2>/dev/null | tail -1)
TRAINER_PROMO_TABLE=$(php artisan tinker --execute="echo Schema::hasTable('gymies_trainer_promotions') ? 'YES' : 'NO';" 2>/dev/null | tail -1)

if [ "$PROMO_TABLE" = "YES" ]; then
    ok "Tabel gymies_promotions aangemaakt"
else
    fail "Tabel gymies_promotions NIET gevonden"
fi

if [ "$TRAINER_PROMO_TABLE" = "YES" ]; then
    ok "Tabel gymies_trainer_promotions aangemaakt"
else
    fail "Tabel gymies_trainer_promotions NIET gevonden"
fi

# Check nieuwe kolommen
PLANS_SUB=$(php artisan tinker --execute="echo Schema::hasColumn('gymies_plans', 'subtitle') ? 'YES' : 'NO';" 2>/dev/null | tail -1)
if [ "$PLANS_SUB" = "YES" ]; then
    ok "gymies_plans dynamische velden toegevoegd"
else
    fail "gymies_plans dynamische velden NIET gevonden"
fi

SUB_PROMO=$(php artisan tinker --execute="echo Schema::hasColumn('gymies_subscriptions', 'promotion_id') ? 'YES' : 'NO';" 2>/dev/null | tail -1)
if [ "$SUB_PROMO" = "YES" ]; then
    ok "gymies_subscriptions promotion_id kolom toegevoegd"
else
    fail "gymies_subscriptions promotion_id kolom NIET gevonden"
fi

# Check routes
echo ""
info "Geregistreerde promo routes:"
php artisan route:list --name=promo 2>/dev/null | head -10 || warn "Route check niet beschikbaar"

# Check bestanden op hun plek
echo ""
info "Bestanden check:"
for f in \
    "app/Models/Promotion.php" \
    "app/Models/TrainerPromotion.php" \
    "app/Services/PromotionService.php" \
    "app/Http/Controllers/Api/PromotionController.php" \
    "app/Console/Commands/ExpirePromotionsCommand.php"; do
    if [ -f "$f" ]; then
        ok "$f"
    else
        fail "$f NIET gevonden"
    fi
done

# Check of patches zijn doorgekomen
echo ""
info "Integratie check:"

if [ -n "$PLANS_CTRL" ] && grep -q "enrichPlansWithPromotions" "$PLANS_CTRL" 2>/dev/null; then
    ok "PlansController gepatcht met enrichPlansWithPromotions"
else
    warn "PlansController — handmatige patch nodig"
fi

if [ -n "$WEBHOOK_CTRL" ] && grep -q "handleMolliePayment" "$WEBHOOK_CTRL" 2>/dev/null; then
    ok "WebhookController gepatcht met handleMolliePayment"
else
    warn "WebhookController — handmatige patch nodig"
fi

if [ -n "$KERNEL_FILE" ] && grep -q "promotions:expire" "$KERNEL_FILE" 2>/dev/null; then
    ok "Kernel.php gepatcht met promotions:expire"
else
    warn "Kernel.php — handmatige patch nodig"
fi

# ═══════════════════════════════════════════
#  RESULTAAT
# ═══════════════════════════════════════════
echo ""
echo -e "${BLUE}============================================${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}  ✅ DEPLOY SUCCESVOL VOLTOOID${NC}"
else
    echo -e "${YELLOW}  ⚠️  DEPLOY VOLTOOID MET $ERRORS WAARSCHUWING(EN)${NC}"
fi
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "Backups staan in: ${GREEN}$BACKUP_DIR${NC}"
echo ""
echo -e "${BLUE}── Quick test ──${NC}"
echo "  php artisan tinker"
echo "  > App\Models\Promotion::count();"
echo ""
echo -e "${BLUE}── Maak eerste promotie ──${NC}"
echo '  > App\Models\Promotion::create(['
echo "  >   'name' => 'Zomeractie 2026',"
echo "  >   'slug' => 'zomeractie-2026',"
echo "  >   'type' => 'campaign',"
echo "  >   'discount_type' => 'percent',"
echo "  >   'value_cents' => 50,"
echo "  >   'display_label' => '50% korting deze zomer!',"
echo "  >   'display_badge' => 'ZOMERACTIE',"
echo "  >   'is_active' => true,"
echo "  >   'valid_until' => '2026-09-01',"
echo '  > ]);'
echo ""
echo -e "${BLUE}── Rollback als iets misgaat ──${NC}"
echo "  Restore database:"
echo "  mysql -u \"\$DB_USER\" -p -h \"\$DB_HOST\" \"\$DB_NAME\" < \"$BACKUP_SQL\""
echo ""
echo "  Restore bestanden:"
echo "  cp $BACKUP_DIR/routes/api.php routes/api.php"
if [ -n "$PLANS_CTRL" ]; then
echo "  cp $BACKUP_DIR/$PLANS_CTRL $PLANS_CTRL"
fi
if [ -n "$KERNEL_FILE" ]; then
echo "  cp $BACKUP_DIR/$KERNEL_FILE $KERNEL_FILE"
fi
echo ""
