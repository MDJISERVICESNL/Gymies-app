with open('lib/screens/dashboard_screen.dart', 'r') as f:
    content = f.read()

# Zoek naar waar de avatar wordt gebouwd in _TrainerCard
# We voegen een rode ring toe rond de avatar als hasActiveStory true is

# Eerst, zoek naar de avatar container
old_avatar = '''child: ClipOval(
                  child: CachedNetworkImage('''

new_avatar = '''child: Stack(
                  children: [
                    ClipOval(
                      child: CachedNetworkImage('''

old_close = '''fit: BoxFit.cover,
                    ),
                  ),'''

new_close = '''fit: BoxFit.cover,
                    ),
                    ),
                    if (hasActiveStory)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),'''

if 'hasActiveStory' in content and 'Positioned' not in content:
    content = content.replace(old_avatar, new_avatar)
    content = content.replace(old_close, new_close)
    print("✅ Story ring toegevoegd rond avatar")
else:
    print("ℹ️ Story ring bestaat mogelijk al of structuur is anders")

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.write(content)
