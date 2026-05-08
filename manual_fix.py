with open('lib/screens/dashboard_screen.dart', 'r') as f:
    lines = f.readlines()

# Zoek naar de regel met "trainers = await api.getTrainers"
new_lines = []
for i, line in enumerate(lines):
    new_lines.append(line)
    if 'trainers = await api.getTrainers' in line and 'query:' in line:
        # Voeg de story loading toe na deze regel
        indent = ' ' * (len(line) - len(line.lstrip()))
        new_lines.append(f'{indent}// Load story status for each trainer\n')
        new_lines.append(f'{indent}for (int i = 0; i < trainers.length; i++) {{\n')
        new_lines.append(f'{indent}  final hasStory = await api.hasStories(trainers[i].id);\n')
        new_lines.append(f'{indent}  trainers[i] = Trainer(\n')
        new_lines.append(f'{indent}    id: trainers[i].id,\n')
        new_lines.append(f'{indent}    name: trainers[i].name,\n')
        new_lines.append(f'{indent}    avatarUrl: trainers[i].avatarUrl,\n')
        new_lines.append(f'{indent}    hasActiveStory: hasStory,\n')
        new_lines.append(f'{indent}  );\n')
        new_lines.append(f'{indent}}}\n')
        print(f"✅ Story loading toegevoegd op regel {i+1}")
        break

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.writelines(new_lines)
