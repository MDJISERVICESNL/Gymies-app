with open('lib/screens/dashboard_screen.dart', 'r') as f:
    content = f.read()

# Voeg een tekst indicator toe na de naam als hasActiveStory true is
old_name_line = 'Text(\n                                trainer.nameOrEmail,'
new_name_line = 'Row(\n                          children: [\n                            Expanded(\n                              child: Text(\n                                trainer.nameOrEmail,\n                              ),\n                            ),\n                            if (hasActiveStory)\n                              Container(\n                                margin: const EdgeInsets.only(left: 8),\n                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),\n                                decoration: BoxDecoration(\n                                  color: Colors.red,\n                                  borderRadius: BorderRadius.circular(12),\n                                ),\n                                child: Text(\n                                  "NEW STORY",\n                                  style: TextStyle(\n                                    color: Colors.white,\n                                    fontSize: 10,\n                                    fontWeight: FontWeight.bold,\n                                  ),\n                                ),\n                              ),\n                          ],\n                        )'

if 'if (hasActiveStory)' not in content:
    content = content.replace(old_name_line, new_name_line)
    print("✅ Tekst indicator toegevoegd")
else:
    print("ℹ️ Indicator bestaat al")

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.write(content)
