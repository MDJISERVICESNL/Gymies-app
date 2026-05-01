#!/bin/bash

# Fix: toon alleen countdown timer als sessie < 24 uur weg is
sed -i '' '1109,1124c\
    // Live timer string — alleen tonen bij < 24 uur\
    String timer;\
    final secsLeft = diff.inSeconds;\
    if (diff.isNegative) {\
      timer = '\''Nu'\'';\
    } else if (diff.inHours < 24) {\
      final h = diff.inHours;\
      final m = diff.inMinutes % 60;\
      final s = diff.inSeconds % 60;\
      timer = h > 0\
          ? '\''${h}:'\'' + '\''${m.toString().padLeft(2, '\''0'\'')}:'\'' + '\''${s.toString().padLeft(2, '\''0'\'')}'\''\
          : '\''${m}:'\'' + '\''${s.toString().padLeft(2, '\''0'\'')}'\'';\
    } else {\
      timer = '\''over ${diff.inDays} dag'\'' + (diff.inDays == 1 ? '\'''\'' : '\''en'\'');\
    }' lib/screens/trainer_dashboard_screen.dart

echo "✅ Countdown gefixt"
echo ""
echo "=== Nieuwe countdown logica ==="
sed -n '1109,1124p' lib/screens/trainer_dashboard_screen.dart
