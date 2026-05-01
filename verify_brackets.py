#!/usr/bin/env python3
"""
Verify bracket balance in all modified Dart files.
"""
import sys
from pathlib import Path

files_to_check = [
    "lib/screens/client_settings_screen.dart",
    "lib/screens/client_trainer_reviews_screen.dart",
    "lib/screens/client_home_screen.dart",
    "lib/screens/client_favorites_standalone_screen.dart",
    "lib/screens/client_waitlist_screen.dart",
    "lib/screens/client_profile_screen.dart",
    "lib/screens/client_onboarding_screen.dart",
    "lib/screens/client_notifications_screen.dart",
    "lib/screens/client_messages_screen.dart",
    "lib/screens/client_group_sessions_screen.dart",
    "lib/screens/client_favorites_screen.dart",
    "lib/screens/client_my_group_sessions_screen.dart",
    "lib/screens/client_invoices_screen.dart",
    "lib/screens/client_check_in_qr_screen.dart",
    "lib/screens/client_group_session_detail_screen.dart",
]

base_dir = Path("/Users/sara/Desktop/GYMIES - APP")
errors = []

for file in files_to_check:
    filepath = base_dir / file
    if not filepath.exists():
        errors.append(f"FILE NOT FOUND: {filepath}")
        continue

    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Count brackets
    depth = 0
    line_num = 1
    for i, char in enumerate(content):
        if char == '\n':
            line_num += 1
        elif char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            if depth < 0:
                errors.append(f"{file}:{line_num} - Closing brace without opening")

    if depth != 0:
        errors.append(f"{file} - Bracket mismatch: depth={depth}")

if errors:
    print("BRACKET VERIFICATION FAILED:")
    for error in errors:
        print(f"  {error}")
    sys.exit(1)
else:
    print(f"SUCCESS: All {len(files_to_check)} files have balanced brackets")
    sys.exit(0)
