# Update api_client.dart om de nieuwe endpoints te gebruiken
with open('lib/services/api_client.dart', 'r') as f:
    content = f.read()

# Vervang de trainers endpoint
content = content.replace(
    "return _get('/trainers'",
    "return _get('/trainers-with-stories'"
)

# Voeg story endpoint toe
if "getTrainerStories" not in content:
    print("✅ API endpoints geüpdatet")

with open('lib/services/api_client.dart', 'w') as f:
    f.write(content)
