with open('lib/screens/dashboard_screen.dart', 'r') as f:
    content = f.read()

# Hardcode hasActiveStory = true in de build methode
content = content.replace(
    'if (hasActiveStory)',
    'if (true)  // hasActiveStory tijdelijk geforceerd'
)

print("✅ hasActiveStory hardcoded naar true in de build")

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.write(content)
