#!/bin/bash

# Stap 1: Fix de samengevoegde regel (bool ... Timer)
sed -i '' 's/bool _noSessionDismissed = false;  Timer? _countdownTimer;/bool _noSessionDismissed = false;\
  Timer? _countdownTimer;/' lib/screens/client_home_screen.dart

# Stap 2: Vind het regelnummer van 'Geen sessies gepland'
LINE=$(grep -n "Geen sessies gepland" lib/screens/client_home_screen.dart | head -1 | cut -d: -f1)

# Stap 3: Vind de sluitende ] van de Row (einde van de kalender-icon sectie)
# We zoeken vanaf de "Geen sessies" regel naar de Expanded die eindigt met ],
# en voegen het kruisje toe vóór die sluitende ]
ENDLINE=$((LINE + 40))

# Vind de sluitende ] van de Row children (regel met alleen '                ],')
CLOSELINE=$(sed -n "$LINE,${ENDLINE}p" lib/screens/client_home_screen.dart | grep -n "^                ],$" | head -1 | cut -d: -f1)
CLOSELINE=$((LINE + CLOSELINE - 1))

# Voeg het kruisje toe vóór de sluitende ]
sed -i '' "${CLOSELINE}i\\
                    GestureDetector(\\
                      onTap: () {\\
                        Haptics.selection();\\
                        setState(() => _noSessionDismissed = true);\\
                      },\\
                      child: Padding(\\
                        padding: const EdgeInsets.all(8),\\
                        child: Icon(\\
                          Icons.close_rounded,\\
                          size: 18,\\
                          color: Colors.grey.shade400,\\
                        ),\\
                      ),\\
                    )," lib/screens/client_home_screen.dart

echo "✅ Fix compleet"
echo ""
echo "=== State variabele ==="
sed -n '40,46p' lib/screens/client_home_screen.dart
echo ""
echo "=== Banner check ==="
grep -n "if (next == null" lib/screens/client_home_screen.dart
echo ""
echo "=== Kruisje toegevoegd ==="
grep -n "Icons.close_rounded" lib/screens/client_home_screen.dart
