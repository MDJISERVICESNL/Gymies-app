#!/bin/bash
echo "=== Current SSH config for gymies ==="
grep -A5 "Host gymies" ~/.ssh/config 2>/dev/null || echo "No gymies entry found"
echo ""
echo "=== All SSH keys ==="
ls -la ~/.ssh/id_* 2>/dev/null || echo "No keys found"
echo ""
echo "=== Test SSH to AWS server (18.159.130.187) ==="
echo "Trying with existing key..."
ssh -i "$HOME/.ssh/id_ed25519_gymies" -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@18.159.130.187 "echo 'SSH OK'; hostname; whoami; ls /var/www/gymies/public/index.php 2>/dev/null && echo 'Laravel found' || echo 'No Laravel at /var/www/gymies'" 2>&1 || echo "SSH failed with ubuntu@"

echo ""
echo "Trying with root..."
ssh -i "$HOME/.ssh/id_ed25519_gymies" -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@18.159.130.187 "echo 'SSH OK'; hostname; whoami" 2>&1 || echo "SSH failed with root@"

echo ""
echo "Trying with current gymies config user..."
GYMIES_USER=$(grep -A5 "Host gymies" ~/.ssh/config 2>/dev/null | grep User | awk '{print $2}')
if [ -n "$GYMIES_USER" ]; then
    echo "Found user: $GYMIES_USER"
    ssh -i "$HOME/.ssh/id_ed25519_gymies" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$GYMIES_USER@18.159.130.187" "echo 'SSH OK'; hostname; whoami" 2>&1 || echo "SSH failed"
else
    echo "No user found in config"
fi
