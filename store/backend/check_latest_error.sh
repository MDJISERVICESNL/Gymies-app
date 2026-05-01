#!/bin/bash
set -e
ssh gymies << 'REMOTE'
cd /var/www/gymies
echo "=== Laatste 5 minuten Laravel errors ==="
LOG=$(ls -t storage/logs/laravel*.log 2>/dev/null | head -1)
if [ -n "$LOG" ]; then
    # Zoek errors van vandaag
    grep -A 30 "$(date -u +'%Y-%m-%d 17:')" "$LOG" | tail -80
    echo ""
    echo "=== Laatste entry ==="
    tail -40 "$LOG"
fi
REMOTE
