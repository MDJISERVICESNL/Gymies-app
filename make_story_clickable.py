with open('lib/screens/dashboard_screen.dart', 'r') as f:
    content = f.read()

# Voeg een onTap functie toe aan de story ring
old_story_ring = '''if (true)  // hasActiveStory tijdelijk geforceerd
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),'''

new_story_ring = '''if (true)  // hasActiveStory tijdelijk geforceerd
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: GestureDetector(
                            onTap: () {
                              // Toon story popup
                              showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.play_circle_filled, size: 48, color: Colors.red),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Story van ${trainer.nameOrEmail}',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text('Hier komt de story video/image'),
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(_),
                                        child: const Text('Sluiten'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ),'''

if 'GestureDetector' not in content:
    content = content.replace(old_story_ring, new_story_ring)
    print("✅ Story ring klikbaar gemaakt")
else:
    print("ℹ️ Story ring is al klikbaar")

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.write(content)
