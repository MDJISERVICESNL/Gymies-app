#!/bin/bash
AWS_IP="18.159.130.187"

echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Try .pem keys for AWS server               ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

KEYS=(
    "$HOME/.ssh/Amazonekey.pem"
    "$HOME/Desktop/GYMIES - APP/Amazonekey.pem"
    "$HOME/Downloads/LightsailDefaultKey-eu-central-1.pem"
)

USERS=("ubuntu" "ec2-user" "admin" "bitnami" "Gymiesagent" "gymies" "deploy" "root" "lightsail")

for KEY in "${KEYS[@]}"; do
    KEYNAME=$(basename "$KEY")
    echo "--- Trying key: $KEYNAME ---"
    for USER in "${USERS[@]}"; do
        RESULT=$(ssh -i "$KEY" -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=yes "$USER@$AWS_IP" "echo SUCCESS" 2>&1)
        if echo "$RESULT" | grep -q "SUCCESS"; then
            echo "  ✓✓✓ FOUND! Key=$KEYNAME User=$USER ✓✓✓"
            echo ""
            echo "  Server info:"
            ssh -i "$KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$USER@$AWS_IP" "
                echo 'Hostname:' \$(hostname)
                echo 'User:' \$(whoami)
                echo 'OS:' \$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2)
                echo ''
                echo 'Web root:'
                ls -la /var/www/ 2>/dev/null || echo '  /var/www/ not found'
                echo ''
                echo 'Laravel check:'
                ls /var/www/gymies/public/index.php 2>/dev/null && echo '  ✓ Laravel found' || echo '  ✗ No Laravel at /var/www/gymies'
                ls /var/www/gymies/artisan 2>/dev/null && echo '  ✓ artisan found' || echo '  ✗ No artisan'
                echo ''
                echo 'Nginx sites:'
                ls /etc/nginx/sites-enabled/ 2>/dev/null || echo '  No nginx sites'
                echo ''
                echo 'PHP version:'
                php -v 2>/dev/null | head -1 || echo '  PHP not found'
                echo ''
                echo 'PHP-FPM sock:'
                ls /run/php/*.sock 2>/dev/null || echo '  No FPM socks'
            "
            echo ""
            echo "╔══════════════════════════════════════════════════════╗"
            echo "║  SSH Config voor AWS server:                         ║"
            echo "║                                                      ║"
            echo "║  Host gymies                                         ║"
            echo "║      HostName $AWS_IP                        ║"
            echo "║      User $USER                                   ║"
            echo "║      IdentityFile $KEY"
            echo "║      IdentitiesOnly yes                              ║"
            echo "╚══════════════════════════════════════════════════════╝"
            exit 0
        fi
    done
    echo "  No user worked with this key"
    echo ""
done

echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✗ Geen werkende combinatie gevonden                 ║"
echo "║  Je moet de SSH key handmatig toevoegen via          ║"
echo "║  AWS Console → EC2/Lightsail → Connect               ║"
echo "╚══════════════════════════════════════════════════════╝"
