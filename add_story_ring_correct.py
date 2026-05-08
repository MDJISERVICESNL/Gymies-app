with open('lib/screens/dashboard_screen.dart', 'r') as f:
    content = f.read()

# Zoek naar de avatar container en voeg een story ring toe
old_avatar = '''                  // Rounded-square avatar (72px)
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: _accentLight,
                      image: trainer.avatarUrl != null && trainer.avatarUrl!.isNotEmpty
                          ? DecorationImage(
                              image: CachedNetworkImageProvider(trainer.avatarUrl!, errorListener: (_) {}),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: trainer.avatarUrl == null || trainer.avatarUrl!.isEmpty
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

new_avatar = '''                  // Rounded-square avatar (72px) with story ring
                  Stack(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: _accentLight,
                          image: trainer.avatarUrl != null && trainer.avatarUrl!.isNotEmpty
                              ? DecorationImage(
                                  image: CachedNetworkImageProvider(trainer.avatarUrl!, errorListener: (_) {}),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: trainer.avatarUrl == null || trainer.avatarUrl!.isEmpty
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

if 'hasActiveStory' in content:
    content = content.replace(old_avatar, new_avatar)
    print("✅ Story ring toegevoegd rond de avatar container")
else:
    print("⚠️ hasActiveStory niet gevonden in de code")

with open('lib/screens/dashboard_screen.dart', 'w') as f:
    f.write(content)
