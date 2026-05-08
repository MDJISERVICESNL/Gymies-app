with open('lib/screens/dashboard_screen.dart', 'r') as f:
    content = f.read()

# Verwijder alle hardcoded true/false voor hasActiveStory
content = content.replace(
    'hasActiveStory = true',
    'hasActiveStory = trainer.hasActiveStory ?? false'
)

content = content.replace(
    'if (true)  // hasActiveStory tijdelijk geforceerd',
    'if (trainer.hasActiveStory ?? false)'
)

content = content.replace(
    'if (true)',
    'if (trainer.hasActiveStory ?? false)'
)

print("✅ Alle hardcoded waarden verwijderd")

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.write(content)
