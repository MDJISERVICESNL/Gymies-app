# Dashboard screen - voeg rode stip toe
with open('lib/screens/dashboard_screen.dart', 'r') as f:
    content = f.read()

# Zoek naar CircleAvatar en voeg een rode stip toe
if 'storyIndicator' not in content:
    # Eerste vervanging - voeg Stack toe rond CircleAvatar
    content = content.replace(
        'child: CircleAvatar(',
        'child: Stack(\n              children: [\n                CircleAvatar('
    )
    
    # Tweede vervanging - voeg de rode stip toe
    content = content.replace(
        'radius: 24,',
        'radius: 24,\n                ),\n                Positioned(\n                  right: 0,\n                  bottom: 0,\n                  child: Container(\n                    width: 12,\n                    height: 12,\n                    decoration: BoxDecoration(\n                      color: Colors.red,\n                      shape: BoxShape.circle,\n                      border: Border.all(color: Colors.white, width: 1.5),\n                    ),\n                  ),\n                ),\n              ],\n            ),'
    )
    print("✅ Story indicator toegevoegd aan dashboard")
else:
    print("ℹ️ Story indicator bestaat al")

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.write(content)
