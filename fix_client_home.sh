#!/bin/bash

# Stap 1: Voeg de dismiss state variabele toe (na regel 42)
sed -i '' '42a\
  bool _noSessionDismissed = false;' lib/screens/client_home_screen.dart

# Stap 2: Pas de check aan
sed -i '' 's/    if (next == null) {/    if (next == null \&\& !_noSessionDismissed) {/' lib/screens/client_home_screen.dart

# Stap 3: Voeg kruisje toe vóór de Expanded in de "Geen sessies" sectie
# Zoek de regel met het kalender icoon en voeg het kruisje toe in de Row
sed -i '' '/Icons.calendar_today_rounded/,/Expanded(/ {
  /Expanded(/ i\
                    const SizedBox(width: 12),
}' lib/screens/client_home_screen.dart

echo "✅ Fix doorgevoerd"
echo ""
echo "=== State variabele ==="
sed -n '40,44p' lib/screens/client_home_screen.dart
echo ""
echo "=== BuildNextSessionCard check ==="
sed -n '537,538p' lib/screens/client_home_screen.dart
