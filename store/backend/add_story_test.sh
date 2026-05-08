#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# GYMIES: Voeg story-kolommen toe + insert test story
# Gebruikt MySQL credentials uit Laravel .env (externe DB)
# ═══════════════════════════════════════════════════════════════

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo ""
echo "═══ Story kolommen + test data toevoegen ═══"
echo ""

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'

LARAVEL_PATH="/var/www/gymies"

# Lees DB credentials uit .env
DB_HOST=$(grep '^DB_HOST=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_PORT=$(grep '^DB_PORT=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_DATABASE=$(grep '^DB_DATABASE=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_USERNAME=$(grep '^DB_USERNAME=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_PASSWORD=$(grep '^DB_PASSWORD=' "$LARAVEL_PATH/.env" | cut -d= -f2-)

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"

# Maak tijdelijk MySQL config bestand (veilig voor speciale tekens in wachtwoord)
MYCNF=$(mktemp)
cat > "$MYCNF" << CNFEOF
[client]
host=$DB_HOST
port=$DB_PORT
user=$DB_USERNAME
password=$DB_PASSWORD
CNFEOF
chmod 600 "$MYCNF"

echo "Database: $DB_DATABASE @ $DB_HOST:$DB_PORT"
echo ""

echo "1. Kolommen toevoegen..."
mysql --defaults-extra-file="$MYCNF" "$DB_DATABASE" -e "ALTER TABLE gymies_trainer_media ADD COLUMN \`usage\` VARCHAR(20) DEFAULT 'gallery';" 2>&1 && echo "   ✓ usage kolom toegevoegd" || echo "   ℹ️  usage kolom bestaat al (of andere fout)"
mysql --defaults-extra-file="$MYCNF" "$DB_DATABASE" -e "ALTER TABLE gymies_trainer_media ADD COLUMN expires_at TIMESTAMP NULL DEFAULT NULL;" 2>&1 && echo "   ✓ expires_at kolom toegevoegd" || echo "   ℹ️  expires_at kolom bestaat al (of andere fout)"

echo ""
echo "2. Kolommen verifiëren..."
mysql --defaults-extra-file="$MYCNF" "$DB_DATABASE" -e "DESCRIBE gymies_trainer_media;" 2>&1 | grep -E 'usage|expires_at'

echo ""
echo "3. Test story invoegen voor trainer user_id=2..."
mysql --defaults-extra-file="$MYCNF" "$DB_DATABASE" -e "
INSERT INTO gymies_trainer_media
    (trainer_user_id, media_type, source_type, external_url, caption, is_public, \`usage\`, expires_at, created_at, updated_at)
VALUES
    (2, 'image', 'external', 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=800&q=80', 'Vandaag hard getraind! 💪', 1, 'story', NOW() + INTERVAL 24 HOUR, NOW(), NOW());
" 2>&1 && echo "   ✓ Test story ingevoegd" || echo "   ❌ Insert mislukt"

echo ""
echo "4. Verificatie..."
mysql --defaults-extra-file="$MYCNF" "$DB_DATABASE" -e "SELECT id, trainer_user_id, \`usage\`, expires_at, external_url FROM gymies_trainer_media WHERE \`usage\`='story' ORDER BY id DESC LIMIT 5;" 2>&1

# Opruimen
rm -f "$MYCNF"

echo ""
echo "═══ Klaar! Story ring zou nu zichtbaar moeten zijn voor trainer 2 ═══"

REMOTE
