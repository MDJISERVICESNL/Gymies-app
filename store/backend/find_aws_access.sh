#!/bin/bash
echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Find AWS server access                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

AWS_IP="18.159.130.187"

# 1. Check what kind of AWS resource this is
echo "=== 1. What is 18.159.130.187? ==="
echo "Reverse DNS:"
host "$AWS_IP" 2>/dev/null || dig +short -x "$AWS_IP" 2>/dev/null || nslookup "$AWS_IP" 2>/dev/null | grep name || echo "  No reverse DNS found"
echo ""

echo "Check HTTP headers (reveals if ALB/CloudFront/nginx):"
curl -sI --max-time 5 "https://www.gymiesapp.nl/" 2>/dev/null | grep -iE "server:|x-amz|x-cache|via:|cf-|x-powered|x-forwarded" || echo "  No revealing headers"
echo ""

echo "Full response headers:"
curl -sI --max-time 5 "https://www.gymiesapp.nl/" 2>/dev/null
echo ""

# 2. Try ALL SSH keys with common AWS users
echo "=== 2. Try all SSH keys ==="
KEYS=(
    "$HOME/.ssh/id_ed25519_gymies"
    "$HOME/.ssh/id_ed25519_backend"
    "$HOME/.ssh/id_ed25519"
    "$HOME/.ssh/id_ed25519_mdjiservices"
    "$HOME/.ssh/id_ed25519_raptor"
    "$HOME/.ssh/id_ed25519_raptorappstore"
)

USERS=("ubuntu" "ec2-user" "admin" "Gymiesagent" "gymies" "www-data" "deploy" "sara")

for KEY in "${KEYS[@]}"; do
    KEYNAME=$(basename "$KEY")
    for USER in "${USERS[@]}"; do
        RESULT=$(ssh -i "$KEY" -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=yes "$USER@$AWS_IP" "echo SUCCESS" 2>&1)
        if echo "$RESULT" | grep -q "SUCCESS"; then
            echo "  ✓ FOUND! Key=$KEYNAME User=$USER"
            echo "    Running: hostname && whoami && ls /var/www/"
            ssh -i "$KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$USER@$AWS_IP" "hostname; whoami; ls /var/www/ 2>/dev/null; cat /etc/os-release 2>/dev/null | head -3"
            echo ""
            echo "  === Use this in SSH config: ==="
            echo "  Host gymies-aws"
            echo "      HostName $AWS_IP"
            echo "      User $USER"
            echo "      IdentityFile $KEY"
            echo "      IdentitiesOnly yes"
            exit 0
        fi
    done
done
echo "  ✗ No working key/user combination found"

echo ""
echo "=== 3. Check port 22 accessibility ==="
nc -z -w3 "$AWS_IP" 22 2>/dev/null && echo "  Port 22 is OPEN" || echo "  Port 22 is CLOSED — this might be a load balancer/CDN"

echo ""
echo "=== 4. Check if there's an AWS CLI configured ==="
which aws 2>/dev/null && echo "  AWS CLI found" && aws sts get-caller-identity 2>/dev/null || echo "  No AWS CLI or not configured"

echo ""
echo "=== 5. Check for .pem key files ==="
find "$HOME/.ssh" "$HOME/Downloads" "$HOME/Desktop" -name "*.pem" -maxdepth 2 2>/dev/null | head -10 || echo "  No .pem files found"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  Als geen key werkt: je moet de SSH key toevoegen    ║"
echo "║  aan de AWS server via AWS Console (EC2 → Connect)   ║"
echo "║  of via een andere bestaande toegangsmethode.        ║"
echo "╚══════════════════════════════════════════════════════╝"
