with open('lib/screens/dashboard_screen.dart', 'r') as f:
    content = f.read()

# Zoek de avatar container en voeg story ring toe
if 'hasActiveStory' not in content:
    print("⚠️ hasActiveStory niet gevonden, voeg eerst de property toe")
else:
    # Voeg de story ring toe rond de avatar
    old_avatar = '''Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: _accentLight,'''

    new_avatar = '''Stack(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: _accentLight,'''

    old_close = '''child: trainer.avatarUrl == null || trainer.avatarUrl!.isEmpty
                        ? Center(
                            child: Text(
                              trainer.nameOrEmail.isNotEmpty
                                  ? trainer.nameOrEmail[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.sora(
                                fontSize: 24,
                                color: _accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : null,
                  ),'''

    new_close = '''child: trainer.avatarUrl == null || trainer.avatarUrl!.isEmpty
                        ? Center(
                            child: Text(
                              trainer.nameOrEmail.isNotEmpty
                                  ? trainer.nameOrEmail[0].toUpperCase()
                                  : '?',
                              style: GoogleFonts.sora(
                                fontSize: 24,
                                color: _accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        : null,
                  ),
                      if (hasActiveStory)
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
                        ),
                    ],
                  ),'''

    content = content.replace(old_avatar, new_avatar)
    content = content.replace(old_close, new_close)
    print("✅ Story ring toegevoegd")

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.write(content)
