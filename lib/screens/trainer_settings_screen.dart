import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/calendar_service.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'login_register_screen.dart';
import 'action_history_screen.dart';
import 'trainer_documents_screen.dart';
import 'trainer_profile_screen.dart';
import 'trainer_promo_codes_screen.dart';
import 'trainer_subscription_screen.dart';
import 'trainer_verification_screen.dart';
import 'widgets/gymies_dialog.dart';

/// Instellingen-scherm met navy header, iOS-stijl grouped tiles en
/// staggered entrance animaties.
class TrainerSettingsScreen extends StatelessWidget {
  const TrainerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ent = context.watch<SubscriptionEntitlementsService>();
    final hasDossier = ent.coachToolsEnabled;
    final hasProHub = ent.proHubEnabled;
    final hasSuite = ent.suiteEnabled;
    final tierLabel = TrainerSubscriptionScreen.tierDisplayLabel(ent.tier);

    String userName() {
      try {
        final user = context.read<AuthService>().user;
        return user?['display_name']?.toString() ??
            user?['name']?.toString() ??
            'Trainer';
      } catch (_) {
        return 'Trainer';
      }
    }

    String userEmail() {
      try {
        final user = context.read<AuthService>().user;
        return user?['email']?.toString() ?? '';
      } catch (_) {
        return '';
      }
    }

    void push(Widget screen) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      );
    }

    final items = <Widget>[
      // ── Navy header ──
      _buildHeader(
        name: userName(),
        email: userEmail(),
        tierLabel: tierLabel,
      ),
      const SizedBox(height: 16),

      // ── ACCOUNT sectie ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildSectionLabel('ACCOUNT'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildGroupedTiles([
          _GroupedTileData(
            icon: Icons.person_outline_rounded,
            title: 'Mijn profiel',
            onTap: () => push(const TrainerProfileScreen()),
          ),
          _GroupedTileData(
            icon: Icons.workspace_premium_outlined,
            title: 'Abonnement',
            trailing: tierLabel != 'Starter'
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      tierLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                  )
                : null,
            onTap: () => push(const TrainerSubscriptionScreen()),
          ),
          _GroupedTileData(
            icon: Icons.folder_outlined,
            title: 'Documenten',
            onTap: () => push(const TrainerDocumentsScreen()),
          ),
          _GroupedTileData(
            icon: Icons.verified_rounded,
            title: 'Verificatie',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Nieuw',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.green.shade700,
                ),
              ),
            ),
            onTap: () => push(const TrainerVerificationScreen()),
          ),
        ]),
      ),
      const SizedBox(height: 20),

      // ── TOOLS sectie ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildSectionLabel('TOOLS'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildGroupedTiles([
          if (hasSuite) ...[
            _GroupedTileData(
              icon: Icons.local_offer_outlined,
              title: 'Promocodes',
              onTap: () => push(const TrainerPromoCodesScreen()),
            ),
          ],
          if (kDebugMode)
            _GroupedTileData(
              icon: Icons.history_rounded,
              title: 'Actiegeschiedenis',
              onTap: () => push(const ActionHistoryScreen()),
            ),
        ]),
      ),
      const SizedBox(height: 20),

      // ── VOORKEUREN sectie (agenda sync toggle) ──
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: _TrainerCalendarSyncSection(),
      ),

      // ── BEVEILIGING sectie (biometric toggle) ──
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: _TrainerBiometricSection(),
      ),

      // ── PRIVACY & VEILIGHEID sectie ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildSectionLabel('PRIVACY & VEILIGHEID'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildGroupedTiles([
          _GroupedTileData(
            icon: Icons.privacy_tip_rounded,
            title: 'Privacy & gegevens',
            onTap: () => _showPrivacySheet(context),
          ),
        ]),
      ),
      const SizedBox(height: 32),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 40),
          itemCount: items.length,
          itemBuilder: (context, index) {
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 80 + (index * 40)),
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 16),
                  child: child,
                ),
              ),
              child: items[index],
            );
          },
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // NAVY HEADER
  // ═══════════════════════════════════════════════════════════════════

  static Widget _buildHeader({
    required String name,
    required String email,
    required String tierLabel,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: GymiesColors.darkBlue,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          // Terug-knop + titel
          Row(
            children: [
              Builder(
                builder: (ctx) => GestureDetector(
                  onTap: () {
                    Haptics.selection();
                    Navigator.of(ctx).pop();
                  },
                  child: const Icon(
                    Icons.arrow_back_ios_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Instellingen',
                style: GoogleFonts.sora(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Account info
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: GymiesColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'T',
                    style: GoogleFonts.sora(
                      fontSize: 22,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (tierLabel != 'Starter')
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tierLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // GROUPED TILES (iOS-stijl)
  // ═══════════════════════════════════════════════════════════════════

  static Widget _buildSectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title,
        style: GoogleFonts.sora(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  static Widget _buildGroupedTiles(List<_GroupedTileData> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: List.generate(tiles.length, (i) {
          final t = tiles[i];
          final isLast = i == tiles.length - 1;
          return Column(
            children: [
              GestureDetector(
                onTap: () {
                  Haptics.selection();
                  t.onTap?.call();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        t.icon,
                        size: 20,
                        color: GymiesColors.darkBlue.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          t.title,
                          style: GoogleFonts.sora(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                      ),
                      if (t.trailing != null)
                        t.trailing!
                      else if (t.onTap != null)
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: Colors.grey.shade400,
                        ),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 50,
                  color: Colors.grey.shade200,
                ),
            ],
          );
        }),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // PRIVACY DIALOG (ongewijzigd)
  // ═══════════════════════════════════════════════════════════════════

  void _showPrivacySheet(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.privacy_tip, color: Colors.teal.shade600, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Privacy & gegevens',
                    style: GoogleFonts.sora(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade900,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      Haptics.selection();
                      Navigator.pop(ctx);
                    },
                    icon: Icon(Icons.close, color: Colors.grey.shade400, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade100),
                ),
                child: Text(
                  'GYMIES verwerkt je persoonsgegevens conform de AVG (GDPR). '
                  'Je data wordt niet met derden gedeeld en uitsluitend gebruikt '
                  'voor het leveren van onze diensten. Je hebt te allen tijde '
                  'het recht je gegevens in te zien, te corrigeren of te verwijderen.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.teal.shade800,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _PrivacyTile(
                icon: Icons.download_outlined,
                iconColor: Colors.cyan.shade600,
                title: 'Mijn gegevens opvragen',
                subtitle: 'Ontvang een export van alle data die wij over je hebben',
                onTap: () {
                  Haptics.light();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Gegevensexport aangevraagd — je ontvangt een e-mail'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _PrivacyTile(
                icon: Icons.delete_forever_outlined,
                iconColor: Colors.red.shade600,
                title: 'Account verwijderen',
                subtitle: 'Verwijder permanent je account en al je gegevens (AVG Art. 17)',
                danger: true,
                onTap: () async {
                  Haptics.selection();
                  Navigator.pop(ctx);
                  final confirmed = await GymiesDialog.destructive(
                    context,
                    title: 'Account verwijderen',
                    message:
                        'Dit verwijdert je account en alle bijbehorende gegevens permanent. '
                        'Deze actie kan niet ongedaan worden gemaakt.',
                    confirmLabel: 'Verwijderen',
                    cancelLabel: 'Annuleren',
                  );
                  if (confirmed == true && context.mounted) {
                    Haptics.heavy();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Account verwijderaanvraag ingediend'),
                      ),
                    );
                    await context.read<AuthService>().logout();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) => const LoginRegisterScreen(),
                        ),
                        (route) => false,
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════

/// Agenda sync toggle sectie — StatefulWidget zodat async state kan worden geladen.
/// Stelt de trainer in staat om nieuwe boekingen automatisch aan de device-kalender
/// toe te voegen wanneer een klant een sessie boekt.
class _TrainerCalendarSyncSection extends StatefulWidget {
  const _TrainerCalendarSyncSection();

  @override
  State<_TrainerCalendarSyncSection> createState() =>
      _TrainerCalendarSyncSectionState();
}

class _TrainerCalendarSyncSectionState
    extends State<_TrainerCalendarSyncSection> {
  bool _loading = true;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled =
        await CalendarService.instance.isTrainerAutoSyncEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    Haptics.selection();
    setState(() => _enabled = value);
    await CalendarService.instance.setTrainerAutoSync(value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrainerSettingsScreen._buildSectionLabel('VOORKEUREN'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : SwitchListTile(
                  secondary: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      size: 20,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  title: Text(
                    'Agenda sync',
                    style: GoogleFonts.sora(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    'Nieuwe boekingen automatisch aan je kalender toevoegen',
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  value: _enabled,
                  onChanged: _toggle,
                  activeColor: GymiesColors.primary,
                ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Biometric toggle sectie — StatefulWidget zodat async state kan worden geladen
/// terwijl de rest van TrainerSettingsScreen stateless blijft.
class _TrainerBiometricSection extends StatefulWidget {
  const _TrainerBiometricSection();

  @override
  State<_TrainerBiometricSection> createState() =>
      _TrainerBiometricSectionState();
}

class _TrainerBiometricSectionState extends State<_TrainerBiometricSection> {
  bool _available = false;
  bool _enabled = false;
  String _label = 'Biometrie';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bio = BiometricAuthService.instance;
    final available = await bio.isAvailable;
    final enabled = await bio.isEnabled;
    final label = await bio.biometricLabel;
    if (!mounted) return;
    setState(() {
      _available = available;
      _enabled = enabled;
      _label = label;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    Haptics.selection();
    final bio = BiometricAuthService.instance;
    if (value) {
      final verified = await bio.authenticate(
        reason: 'Bevestig $_label om het in te schakelen',
      );
      if (!verified) return;
      await bio.setEnabled(true);
      await bio.markAsked();
    } else {
      await bio.setEnabled(false);
    }
    if (!mounted) return;
    setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || !_available) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            'BEVEILIGING',
            style: GoogleFonts.sora(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade500,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(
                  _label == 'Face ID'
                      ? Icons.face
                      : _label == 'Touch ID'
                          ? Icons.fingerprint
                          : Icons.lock_outline_rounded,
                  size: 20,
                  color: GymiesColors.darkBlue.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      Text(
                        _enabled
                            ? 'Ingeschakeld — log snel in'
                            : 'Schakel in voor snelle toegang',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _enabled,
                  onChanged: _toggle,
                  activeColor: GymiesColors.primary,
                  activeTrackColor: GymiesColors.darkBlue,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _GroupedTileData {
  const _GroupedTileData({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
}

class _PrivacyTile extends StatelessWidget {
  const _PrivacyTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: danger ? Colors.red.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: danger ? Colors.red.shade700 : Colors.grey.shade900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      color: danger ? Colors.red.shade400 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: danger ? Colors.red.shade300 : Colors.grey.shade400,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
