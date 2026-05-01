#!/bin/bash
set -e
SSH_HOST="gymies"
SSH_KEY="$HOME/.ssh/id_ed25519_gymies"

ssh -i "$SSH_KEY" "$SSH_HOST" << 'REMOTE'
echo "=== FULL gymiesapp nginx config (lines 85-250) ==="
sudo sed -n '85,250p' /etc/nginx/sites-enabled/gymiesapp

echo ""
echo "=== FULL default nginx config (lines 30-120) ==="
sudo sed -n '30,120p' /etc/nginx/sites-enabled/default
REMOTE
