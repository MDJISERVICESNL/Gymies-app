with open('lib/screens/dashboard_screen.dart', 'r') as f:
    lines = f.readlines()

# Zoek de _TrainerCard constructor en forceer hasActiveStory = true voor test
for i, line in enumerate(lines):
    if 'const _TrainerCard({' in line:
        # Vervang de constructor call om hasActiveStory = true te gebruiken
        lines[i] = line.replace('hasActiveStory = false', 'hasActiveStory = true')
        print(f"✅ hasActiveStory geforceerd op true op regel {i+1}")
        break

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.writelines(lines)
