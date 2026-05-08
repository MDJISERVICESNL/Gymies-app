import re

# Pas gymies_api.dart aan
with open('lib/services/gymies_api.dart', 'r') as f:
    content = f.read()

# Voeg een methode toe om stories te checken per trainer
if 'Future<bool> hasStories' not in content:
    # Voeg de hasStories methode toe
    content = content.replace(
        'Future<List<Trainer>> getTrainers({',
        '''  Future<bool> hasStories(int trainerId) async {
    try {
      final res = await _api.get('trainers/$trainerId/has-stories');
      return res['has_stories'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<List<Trainer>> getTrainers({'''
    )
    print("✅ hasStories methode toegevoegd")

with open('lib/services/gymies_api.dart', 'w') as f:
    f.write(content)
