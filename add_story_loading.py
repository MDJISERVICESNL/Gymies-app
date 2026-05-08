with open('lib/screens/dashboard_screen.dart', 'r') as f:
    content = f.read()

# Zoek naar de plek waar trainers worden geladen
old_code = '''    final trainers = await _api.getTrainers(
      query: _searchController.text.isNotEmpty ? _searchController.text : null,
      lat: _currentLocation?.latitude,
      lng: _currentLocation?.longitude,
    );'''

new_code = '''    final trainers = await _api.getTrainers(
      query: _searchController.text.isNotEmpty ? _searchController.text : null,
      lat: _currentLocation?.latitude,
      lng: _currentLocation?.longitude,
    );
    
    // Load story status for each trainer
    for (var i = 0; i < trainers.length; i++) {
      final hasStory = await _api.hasStories(trainers[i].id);
      // Update de trainer met de story status
      trainers[i] = Trainer(
        id: trainers[i].id,
        name: trainers[i].name,
        avatarUrl: trainers[i].avatarUrl,
        hasActiveStory: hasStory,
      );
    }'''

if old_code in content:
    content = content.replace(old_code, new_code)
    print("✅ Story loading toegevoegd")
else:
    print("⚠️ Code niet gevonden, probeer alternatief")
    
    # Alternatief: zoek naar een andere variatie
    import re
    pattern = r'final trainers = await _api\.getTrainers\([^;]+\);'
    if re.search(pattern, content):
        print("⚠️ Pattern gevonden maar niet vervangen - handmatige aanpassing nodig")

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.write(content)
