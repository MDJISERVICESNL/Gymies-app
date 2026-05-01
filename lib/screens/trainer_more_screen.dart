import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/app_version.dart';
import 'shells/gym_shell.dart';
import 'trainer_finance_screen.dart';
import 'trainer_packages_screen.dart';
import 'trainer_profile_screen.dart';
import 'trainer_marketing_hub_screen.dart';
import 'trainer_storefront_hub_screen.dart';
import 'trainer_subscription_screen.dart';
import 'trainer_widget_qr_screen.dart';
import 'client_support_screen.dart';
import 'login_register_screen.dart';
import 'referral_screen.dart';
import 'widgets/gymies_dialog.dart';
import '../utils/haptics.dart';

/// "Meer" tab – trainer Me-tab met business metrics header,
/// quick actions grid, iOS-stijl gegroepeerde tiles en staggered animaties.
class TrainerMoreScreen extends StatefulWidget {
  const TrainerMoreScreen({super.key});

  @override
  State<TrainerMoreScreen> createState() => _TrainerMoreScreenState();
}

class _TrainerMoreScreenState extends State<TrainerMoreScreen> {
  String _versionDisplay = '';
  bool _upgradeDismissed = false;

  // Business metrics uit API
  int _revenueMtdCents = 0;
  int _clientCount = 0;
  int _thisWeekSessions = 0;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadMetrics();
  }

  Future<void> _loadVersion() async {
    final info = await AppVersion.get();
    if (mounted) setState(() => _versionDisplay = info.display);
  }

  Future<void> _loadMetrics() async {
    try {
      final api = context.read<GymiesApi>();
      final summary = await api.getTrainerSummary();
      if (!mounted) return;
      setState(() {
        _revenueMtdCents = summary.revenueCents;
        _thisWeekSessions = summary.thisWeekCount;
        _clientCount = summary.completedCount; // totaal afgeronde sessies als proxy
      });

      // Probeer ook revenue data voor nauwkeuriger MTD omzet
      try {
        final now = DateTime.now();
        final firstOfMonth = DateTime(now.year, now.month, 1);
        final revenue = await api.getTrainerRevenue(from: firstOfMonth, to: now);
        if (mounted) {
          setState(() {
            _revenueMtdCents = revenue.totalRevenueCents;
          });
        }
      } catch (_) {
        // Summary data is voldoende als fallback
      }
    } catch (_) {
      // Metrics zijn optioneel — faal stil
    }
  }

  void _push(Widget screen) {
    Haptics.selection();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _logout() async {
    Haptics.light();
    final confirmed = await GymiesDialog.destructive(
      context,
      title: 'Uitloggen',
      message: 'Weet je zeker dat je wilt uitloggen?',
      confirmLabel: 'Uitloggen',
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<AuthService>().logout();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
      (route) => false,
    );
  }

  String _formatCents(int cents) {
    final euros = cents / 100;
    if (euros >= 1000) {
      return '\u20AC${(euros / 1000).toStringAsFixed(1)}k';
    }
    return '\u20AC${euros.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final ent = Provider.of<SubscriptionEntitlementsService>(context);
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isPro = tierLower.contains('pro') || tierLower == 'studio';
    final isProPlus = tierLower.contains('pro_plus') ||
        tierLower.contains('proplus') ||
        tierLower == 'studio';
    final isStudio = ent.isStudio;
    final tierLabel = TrainerSubscriptionScreen.tierDisplayLabel(ent.tier);
    final showUpgradeBanner = !isPro;

    final auth = context.watch<AuthService>();
    final user = auth.user ?? {};
    final name = user['display_name']?.toString() ??
        user['name']?.toString() ??
        'Trainer';
    final email = user['email']?.toString() ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'T';

    final items = _buildItems(
      name: name,
      email: email,
      initial: initial,
      tierLabel: tierLabel,
      showUpgradeBanner: showUpgradeBanner,
      isPro: isPro,
      isProPlus: isProPlus,
      isStudio: isStudio,
    );

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

  List<Widget> _buildItems({
    required String name,
    required String email,
    required String initial,
    required String tierLabel,
    required bool showUpgradeBanner,
    required bool isPro,
    required bool isProPlus,
    required bool isStudio,
  }) {
    return [
      // ── Profile header met business metrics ──
      _buildProfileHeader(
        name: name,
        email: email,
        initial: initial,
        tierLabel: tierLabel,
      ),
      const SizedBox(height: 16),

      // ── Upgrade CTA banner (alleen als niet Pro) ──
      if (showUpgradeBanner && !_upgradeDismissed) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildUpgradeBanner(),
        ),
        const SizedBox(height: 16),
      ],

      // ── Quick Actions 2×2 grid ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildQuickActionsGrid(isPro: isPro, isProPlus: isProPlus),
      ),
      const SizedBox(height: 24),

      // ── MIJN PROFIEL sectie ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildSectionLabel('MIJN PROFIEL'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildGroupedTiles([
          _GroupedTileData(
            icon: Icons.person_outline,
            title: 'Profiel bewerken',
            onTap: () => _push(const TrainerProfileScreen()),
          ),
          _GroupedTileData(
            icon: Icons.qr_code_2_rounded,
            title: 'Widget & QR',
            locked: !isProPlus,
            lockLabel: 'Pro+',
            onTap: isProPlus
                ? () => _push(const TrainerWidgetQrScreen())
                : null,
          ),
        ]),
      ),
      const SizedBox(height: 20),

      // ── FINANCIEEL sectie ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildSectionLabel('FINANCIEEL'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildGroupedTiles([
          _GroupedTileData(
            icon: Icons.euro_rounded,
            title: 'Financiën',
            onTap: () => _push(const TrainerFinanceScreen()),
          ),
        ]),
      ),
      const SizedBox(height: 20),

      // ── MARKETING & AANBOD sectie ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildSectionLabel('MARKETING & AANBOD'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildGroupedTiles([
          _GroupedTileData(
            icon: Icons.storefront_rounded,
            title: 'Mijn Etalage',
            onTap: () => _push(const TrainerStorefrontHubScreen()),
          ),
          _GroupedTileData(
            icon: Icons.campaign_outlined,
            title: 'Marketing Tools',
            onTap: () => _push(const TrainerMarketingHubScreen()),
          ),
        ]),
      ),
      const SizedBox(height: 20),

      // ── STUDIO sectie (alleen voor Studio tier) ──
      if (isStudio) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildSectionLabel('STUDIO'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildGroupedTiles([
            _GroupedTileData(
              icon: Icons.business_rounded,
              title: 'Gym Dashboard',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GymShell()),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
      ],

      // ── ACCOUNT sectie ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildSectionLabel('ACCOUNT'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildGroupedTiles([
          _GroupedTileData(
            icon: Icons.stars_rounded,
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
                      style: GoogleFonts.sora(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                  )
                : null,
            onTap: () => _push(const TrainerSubscriptionScreen()),
          ),
          _GroupedTileData(
            icon: Icons.card_giftcard_rounded,
            title: 'Vrienden uitnodigen',
            onTap: () => _push(const ReferralScreen()),
          ),
          _GroupedTileData(
            icon: Icons.support_agent_rounded,
            title: 'Support',
            onTap: () => _push(const ClientSupportScreen()),
          ),
        ]),
      ),
      const SizedBox(height: 24),

      // ── Uitloggen knop ──
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextButton.icon(
          onPressed: _logout,
          style: TextButton.styleFrom(
            foregroundColor: Colors.red.shade500,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          icon: const Icon(Icons.logout_rounded, size: 20),
          label: Text(
            'Uitloggen',
            style: GoogleFonts.sora(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),

      // ── Versie ──
      Center(
        child: Text(
          _versionDisplay.isNotEmpty ? _versionDisplay : 'Gymies',
          style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade400),
        ),
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════════
  // PROFILE HEADER met business metrics
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildProfileHeader({
    required String name,
    required String email,
    required String initial,
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
          // Avatar + camera badge
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: GymiesColors.primary,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 3,
                  ),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: GoogleFonts.sora(
                      fontSize: 32,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _push(const TrainerProfileScreen()),
                child: Container(
                  decoration: BoxDecoration(
                    color: GymiesColors.primary,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: GymiesColors.darkBlue, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 14,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: GoogleFonts.sora(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              email,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (tierLabel != 'Starter') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 3,
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
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // UPGRADE CTA BANNER
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildUpgradeBanner() {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => _push(const TrainerSubscriptionScreen()),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [GymiesColors.primary, Color(0xFFF0A500)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('\u{1F680}', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Upgrade naar Pro',
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Krijg etalage, promo codes en meer',
                        style: TextStyle(
                          fontSize: 11,
                          color: GymiesColors.darkBlue.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Bekijk \u{203A}',
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => setState(() => _upgradeDismissed = true),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: GymiesColors.darkBlue.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 14, color: GymiesColors.darkBlue.withValues(alpha: 0.6)),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // QUICK ACTIONS 2×2
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildQuickActionsGrid({
    required bool isPro,
    required bool isProPlus,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.euro_rounded,
                iconBg: Colors.green.shade50,
                iconColor: Colors.green.shade600,
                title: 'Financiën',
                subtitle: _revenueMtdCents > 0
                    ? _formatCents(_revenueMtdCents)
                    : 'Bekijk overzicht',
                onTap: () => _push(const TrainerFinanceScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.inventory_2_outlined,
                iconBg: Colors.blue.shade50,
                iconColor: Colors.blue.shade600,
                title: 'Pakketten',
                subtitle: 'Beheer aanbod',
                onTap: () => _push(const TrainerPackagesScreen()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _QuickActionCard(
                icon: Icons.card_giftcard,
                iconBg: Colors.purple.shade50,
                iconColor: Colors.purple.shade600,
                title: 'Uitnodigen',
                subtitle: 'Verdien beloningen',
                onTap: () => _push(const ReferralScreen()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionCard(
                icon: Icons.headset_mic_rounded,
                iconBg: Colors.orange.shade50,
                iconColor: Colors.orange.shade600,
                title: 'Support',
                subtitle: 'Direct hulp',
                onTap: () => _push(const ClientSupportScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // GROUPED TILES (iOS-stijl)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSectionLabel(String title) {
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

  Widget _buildGroupedTiles(List<_GroupedTileData> tiles) {
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
          final isLocked = t.locked;
          return Column(
            children: [
              GestureDetector(
                onTap: isLocked
                    ? () => _push(const TrainerSubscriptionScreen())
                    : t.onTap,
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
                        color: isLocked
                            ? Colors.grey.shade400
                            : GymiesColors.darkBlue.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                t.title,
                                style: GoogleFonts.sora(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: isLocked
                                      ? Colors.grey.shade500
                                      : GymiesColors.darkBlue,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isLocked && t.lockLabel != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: GymiesColors.primary
                                      .withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  t.lockLabel!,
                                  style: GoogleFonts.sora(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (t.trailing != null)
                        t.trailing!
                      else if (isLocked)
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: Colors.grey.shade400,
                        )
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
}

// ═══════════════════════════════════════════════════════════════════════
// HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════

class _StatItem extends StatelessWidget {
  const _StatItem({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.sora(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: GymiesColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.sora(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.sora(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupedTileData {
  const _GroupedTileData({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
    this.locked = false,
    this.lockLabel,
  });
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool locked;
  final String? lockLabel;
}
