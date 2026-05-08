#!/bin/bash
# Verleng test story expiry voor trainer user_id=2

SSH_KEY="${SSH_KEY:-$HOME/.ssh/Amazonekey.pem}"
SSH_HOST="${SSH_HOST:-gymies}"

echo "═══ Story verlengen/toevoegen voor trainer 2 ═══"

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'

LARAVEL_PATH="/var/www/gymies"

DB_HOST=$(grep '^DB_HOST=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_PORT=$(grep '^DB_PORT=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_DATABASE=$(grep '^DB_DATABASE=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_USERNAME=$(grep '^DB_USERNAME=' "$LARAVEL_PATH/.env" | cut -d= -f2)
DB_PASSWORD=$(grep '^DB_PASSWORD=' "$LARAVEL_PATH/.env" | cut -d= -f2-)

DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"

MYCNF=$(mktemp)
cat > "$MYCNF" << CNFEOF
[client]
host=$DB_HOST
port=$DB_PORT
user=$DB_USERNAME
password=$DB_PASSWORD
CNFEOF
chmod 600 "$MYCNF"

MYSQL="mysql --defaults-extra-file=$MYCNF $DB_DATABASE"

echo "1. Check bestaande stories..."
$MYSQL -e "SELECT id, trainer_user_id, \`usage\`, expires_at, external_url FROM gymies_trainer_media WHERE \`usage\` = 'story' AND trainer_user_id = 2;"

echo ""
echo "2. Verleng expiry of insert nieuwe story..."

# Update bestaande stories: verleng expiry met 7 dagen
UPDATED=$($MYSQL -N -e "UPDATE gymies_trainer_media SET expires_at = NOW() + INTERVAL 7 DAY WHERE \`usage\` = 'story' AND trainer_user_id = 2; SELECT ROW_COUNT();")

if [ "$UPDATED" = "0" ] || [ -z "$UPDATED" ]; then
    echo "   Geen bestaande stories gevonden, nieuwe invoegen..."
    $MYSQL -e "INSERT INTO gymies_trainer_media (trainer_user_id, media_type, external_url, \`usage\`, expires_at, sort_order, created_at, updated_at)
    VALUES (2, 'image', 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=1080', 'story', NOW() + INTERVAL 7 DAY, 0, NOW(), NOW());"
    echo "   ✓ Nieuwe story ingevoegd"
else
    echo "   ✓ $UPDATED stories verlengd naar +7 dagen"
fi

echo ""
echo "3. Verificatie..."
$MYSQL -e "SELECT id, trainer_user_id, \`usage\`, expires_at, external_url FROM gymies_trainer_media WHERE \`usage\` = 'story' AND trainer_user_id = 2;"

rm -f "$MYCNF"
REMOTE

echo ""
echo "═══ Klaar! Hot restart de app (R) om te testen ═══"
