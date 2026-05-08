with open('lib/screens/dashboard_screen.dart', 'r') as f:
    content = f.read()

# Vervang de hardcoded true door een echte API check
content = content.replace(
    'if (true)  // hasActiveStory tijdelijk geforceerd',
    'if (trainer.hasActiveStory ?? false)'
)

print("✅ Nu gekoppeld aan echte story data uit API")

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.write(content)
