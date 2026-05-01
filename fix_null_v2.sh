#!/bin/bash

# Stap 1: Herstel backup
cp lib/screens/client_home_screen.dart.backup lib/screens/client_home_screen.dart

# Stap 2: Voeg null check toe op regel 641 (vóór next!.scheduledAt)
# We gebruiken een temporary file approach
python3 -c "
lines = open('lib/screens/client_home_screen.dart').readlines()
# Voeg null check toe voor regel 641 (0-indexed: 640)
lines.insert(640, '    if (next == null) return const SizedBox.shrink();\n')
open('lib/screens/client_home_screen.dart','w').writelines(lines)
print('Null check toegevoegd op regel 641')
"

# Stap 3: Fix alle next. naar next!. 
sed -i '' '
  s/next\.scheduledAt/next!.scheduledAt/g
  s/next\.durationMinutes/next!.durationMinutes/g
  s/next\.trainerName/next!.trainerName/g
  s/next\.sessionType/next!.sessionType/g
  s/next\.sessionsRemaining/next!.sessionsRemaining/g
  s/next\.packageSessionsTotal/next!.packageSessionsTotal/g
  s/next\.packageName/next!.packageName/g
  s/_isWithinCheckInWindow(next)/_isWithinCheckInWindow(next!)/g
  s/_openTrainerProfile(next)/_openTrainerProfile(next!)/g
' lib/screens/client_home_screen.dart

echo "✅ Fix compleet"
echo ""
sed -n '640,650p' lib/screens/client_home_screen.dart
