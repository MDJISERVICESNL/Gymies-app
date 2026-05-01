#!/bin/bash

# Voeg null check toe vóór het gebruik van next! (regel 640)
sed -i '' '640a\
    if (next == null) {\
      return const SizedBox.shrink();\
    }' lib/screens/client_home_screen.dart

echo "✅ Null safety guard toegevoegd"
echo ""
echo "=== Gecorrigeerd ==="
sed -n '640,648p' lib/screens/client_home_screen.dart
