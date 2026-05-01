#!/bin/bash

# Vervang de grote Expanded knoppen door compacte icon-knoppen
sed -i '' '2286,2317c\
            if (isUpcomingTab \&\& (onCancel != null || onReschedule != null)) ...[\
              const SizedBox(height: 12),\
              Row(\
                children: [\
                  const Spacer(),\
                  if (onReschedule != null)\
                    IconButton(\
                      onPressed: busy ? null : onReschedule,\
                      icon: const Icon(Icons.event_outlined, size: 20),\
                      tooltip: '\''Verplaatsen'\'',\
                      style: IconButton.styleFrom(\
                        foregroundColor: GymiesColors.darkBlue,\
                        backgroundColor: GymiesColors.primary.withValues(alpha: 0.15),\
                      ),\
                    ),\
                  if (onReschedule != null \&\& onCancel != null)\
                    const SizedBox(width: 8),\
                  if (onCancel != null)\
                    IconButton(\
                      onPressed: busy ? null : onCancel,\
                      icon: const Icon(Icons.close_rounded, size: 20),\
                      tooltip: '\''Annuleren'\'',\
                      style: IconButton.styleFrom(\
                        foregroundColor: Colors.red.shade600,\
                        backgroundColor: Colors.red.shade50,\
                      ),\
                    ),\
                ],\
              ),\
            ],' lib/screens/trainer_sessions_screen.dart

echo "✅ Knoppen compact gemaakt"
echo ""
echo "=== Nieuwe knoppen ==="
sed -n '2286,2317p' lib/screens/trainer_sessions_screen.dart
