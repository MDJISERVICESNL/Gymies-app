#!/bin/bash
set -e

echo "╔══════════════════════════════════════════════════════╗"
echo "║  GYMIES — Switch SSH config to AWS server             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Backup current config
cp ~/.ssh/config ~/.ssh/config.bak.$(date +%Y%m%d_%H%M%S)
echo "  ✓ SSH config backed up"

# Replace the gymies entry
# Remove old gymies block and add new one
python3 << 'PYEOF'
import re

with open('/Users/sara/.ssh/config', 'r') as f:
    content = f.read()

# Remove old gymies block (Host gymies + indented lines after it)
# Match "Host gymies\n" followed by lines starting with whitespace, until next "Host " or end
pattern = r'Host gymies\n(?:[ \t]+.*\n)*'
content = re.sub(pattern, '', content)

# Add new gymies block at the top
new_block = """Host gymies
    HostName 18.159.130.187
    User ubuntu
    IdentityFile ~/.ssh/Amazonekey.pem
    IdentitiesOnly yes

"""

content = new_block + content.lstrip('\n')

with open('/Users/sara/.ssh/config', 'w') as f:
    f.write(content)

print("  ✓ SSH config updated: gymies → 18.159.130.187 (ubuntu)")
PYEOF

echo ""
echo "=== Verify new config ==="
grep -A5 "Host gymies" ~/.ssh/config | head -6

echo ""
echo "=== Test SSH connection ==="
ssh -o ConnectTimeout=5 gymies "echo '  ✓ SSH connection OK'; hostname; whoami"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  ✓ SSH config switched to AWS                        ║"
echo "╚══════════════════════════════════════════════════════╝"
