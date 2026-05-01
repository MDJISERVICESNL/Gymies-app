import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import 'shells/gym_shell.dart';
import 'trainer_branding_screen.dart';
import 'trainer_finance_screen.dart';
import 'trainer_income_screen.dart';
import 'trainer_packages_screen.dart';
import 'trainer_profile_screen.dart';
import 'trainer_promo_codes_screen.dart';
import 'trainer_settings_screen.dart';
import 'trainer_storefront_editor_screen.dart';
import 'trainer_studio_screen.dart';
import 'trainer_subscription_screen.dart';
import 'trainer_widget_qr_screen.dart';
import 'client_support_screen.dart';
import 'login_register_screen.dart';
import 'referral_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_section_header.dart';

/// "Meer" tab – vervangt de oude Business Hub.
/// Clean settings-stijl menu met secties: Profiel, Financieel, Aanbod, Account.
class TrainerMoreScreen extends StatelessWidget {
  const TrainerMoreScreen({super.key, this.onAvatarTap});
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final ent = Provider.of<SubscriptionEntitlementsService>(context);
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isPro = tierLower.contains('pro') || tierLower == 'studio';
    final isProPlus = tierLower.contains('pro_plus') ||
        tierLower.contains('proplus') ||
        tierLower == 'studio';
    final isStudio = ent.isStudio;
    final tierLabel =
        TrainerSubscriptionScreen.tierDisplayLabel(ent.tier);

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

    String userInitial() {
      final name = userName();
      return name.isNotEmpty ? name[0].toUpperCase() : 'T';
    }

    void push(Widget screen) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      );
    }

    Future<void> logout() async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Uitloggen'),
          content: const Text('Weet je zeker dat je wilt uitloggen?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
              ),
              child: const Text('Uitloggen'),
            ),
          ],
        ),
      );
      if (confirm != true || !context.mounted) return;
      await context.read<AuthService>().logout();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginRegisterScreen()),
        (route) => false,
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Meer',
        onAvatarTap: onAvatarTap,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Profielkaart ──────────────────────────────
          Card(
            child: InkWell(
              onTap: () => push(const TrainerProfileScreen()),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor:
                          GymiesColors.primary.withValues(alpha: 0.3),
                      child: Text(
                        userInitial(),
                        style: GoogleFonts.fjallaOne(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName(),
                            style: GoogleFonts.fjallaOne(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: GymiesColors.darkBlue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (tierLabel != 'Starter')
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: GymiesColors.primary
                                        .withValues(alpha: 0.85),
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
                                ),
                              Text(
                                'Profiel bewerken',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: GymiesColors.darkBlue),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Mijn Profiel ──────────────────────────────
          const GymiesSectionHeader('Mijn profiel'),
          _MoreTile(
            icon: Icons.storefront_rounded,
            title: 'Etalage-editor',
            subtitle: 'Pas je publieke pagina aan',
            locked: !isPro,
            lockLabel: 'Pro',
            onTap: isPro
                ? () => push(const TrainerStorefrontEditorScreen())
                : null,
          ),
          _MoreTile(
            icon: Icons.palette_outlined,
            title: 'Mijn Branding',
            subtitle: 'Logo, kleur, URL en video',
            locked: !isProPlus,
            lockLabel: 'Pro+',
            onTap:
                isProPlus ? () => push(const TrainerBrandingScreen()) : null,
          ),
          _MoreTile(
            icon: Icons.qr_code_2_rounded,
            title: 'Widget & QR',
            subtitle: 'Booking widget en QR-code',
            locked: !isProPlus,
            lockLabel: 'Pro+',
            onTap:
                isProPlus ? () => push(const TrainerWidgetQrScreen()) : null,
          ),
          const SizedBox(height: 20),

          // ── Financieel ────────────────────────────────
          const GymiesSectionHeader('Financieel'),
          _MoreTile(
            icon: Icons.euro_rounded,
            title: 'Inkomsten',
            subtitle: 'Overzicht verdiensten',
            onTap: () => push(const TrainerIncomeScreen()),
          ),
          _MoreTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Financiën+',
            subtitle: 'Forecast, payouts, facturen',
            onTap: () => push(const TrainerFinanceScreen()),
          ),
          const SizedBox(height: 20),

          // ── Aanbod ────────────────────────────────────
          const GymiesSectionHeader('Aanbod'),
          _MoreTile(
            icon: Icons.inventory_2_outlined,
            title: 'Pakketten',
            subtitle: 'Trainingsabonnementen beheren',
            onTap: () => push(const TrainerPackagesScreen()),
          ),
          _MoreTile(
            icon: Icons.local_offer_outlined,
            title: 'Promo codes',
            subtitle: 'Kortingscodes voor klanten',
            locked: !isPro,
            lockLabel: 'Pro',
            onTap: isPro ? () => push(const TrainerPromoCodesScreen()) : null,
          ),
          const SizedBox(height: 20),

          // ── Studio (alleen voor Studio tier) ──────────
          if (isStudio) ...[
            const GymiesSectionHeader('Studio'),
            _MoreTile(
              icon: Icons.hub_outlined,
              title: 'Studio & Onboarding',
              subtitle: 'Team, locaties en onboarding',
              onTap: () => push(const TrainerStudioScreen()),
            ),
            _MoreTile(
              icon: Icons.business_rounded,
              title: 'Gym Dashboard',
              subtitle: 'Beheer trainers en klanten',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GymShell()),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Account ───────────────────────────────────
          const GymiesSectionHeader('Account'),
          _MoreTile(
            icon: Icons.stars_rounded,
            title: 'Abonnement',
            subtitle: tierLabel != 'Starter'
                ? 'Huidig plan: $tierLabel'
                : 'Upgrade je plan',
            onTap: () => push(const TrainerSubscriptionScreen()),
          ),
          _MoreTile(
            icon: Icons.settings_rounded,
            title: 'Instellingen',
            subtitle: 'Account en voorkeuren',
            onTap: () => push(const TrainerSettingsScreen()),
          ),
          _MoreTile(
            icon: Icons.card_giftcard_rounded,
            title: 'Vrienden uitnodigen',
            subtitle: 'Deel GYMIES en verdien beloningen',
            onTap: () => push(const ReferralScreen()),
          ),
          _MoreTile(
            icon: Icons.support_agent_rounded,
            title: 'Support',
            subtitle: 'Hulp nodig? Neem contact op',
            onTap: () => push(const ClientSupportScreen()),
          ),
          const SizedBox(height: 16),

          // ── Uitloggen ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TextButton.icon(
              onPressed: logout,
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade400,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: Text(
                'Uitloggen',
                style: GoogleFonts.fjallaOne(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Eenvoudige ListTile voor het Meer-scherm.
/// Optioneel locked met tier-label.
class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.locked = false,
    this.lockLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool locked;
  final String? lockLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: locked ? Colors.grey.shade100 : Colors.white,
      child: ListTile(
        leading: Icon(
          icon,
          color: locked ? Colors.grey.shade400 : GymiesColors.darkBlue,
          size: 24,
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: locked ? Colors.grey.shade500 : GymiesColors.darkBlue,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (locked && lockLabel != null) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: GymiesColors.primary.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  lockLabel!,
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
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: locked ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
        trailing: locked
            ? Icon(Icons.lock_outline_rounded,
                size: 18, color: Colors.grey.shade400)
            : const Icon(Icons.chevron_right, color: GymiesColors.darkBlue),
        onTap: locked
            ? () {
                // Bij locked tile: toon upgrade prompt via subscription scherm
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TrainerSubscriptionScreen(),
                  ),
                );
              }
            : onTap,
      ),
    );
  }
}
