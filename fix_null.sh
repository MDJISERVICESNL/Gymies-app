#!/bin/bash

# Fix alle next. naar next!. in client_home_screen.dart
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

echo "✅ Null checks gefixt"
echo ""
echo "=== Gecorrigeerd ==="
grep -n "next\." lib/screens/client_home_screen.dart | head -5
grep -n "next!" lib/screens/client_home_screen.dart | head -5
