import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import 'shells/gym_shell.dart';
import 'trainer_finance_screen.dart';
import 'trainer_group_sessions_screen.dart';
import 'trainer_income_screen.dart';
import 'trainer_packages_screen.dart';
import 'trainer_branding_screen.dart';
import 'trainer_client_analytics_screen.dart';
import 'trainer_newsletter_screen.dart';
import 'trainer_pro_hub_screen.dart';
import 'trainer_promo_codes_screen.dart';
import 'trainer_storefront_editor_screen.dart';
import 'trainer_studio_screen.dart';
import 'trainer_widget_qr_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_section_header.dart';

/// Hub-scherm voor zakelijke trainer-functies:
/// Financiën, Pakketten, Promo codes, Etalage, Studio, Pro Hub.
class TrainerBusinessHubScreen extends StatelessWidget {
  const TrainerBusinessHubScreen({super.key, this.onAvatarTap});
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final ent = Provider.of<SubscriptionEntitlementsService>(context);
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isPro = tierLower.contains('pro') || tierLower == 'studio';
    final isProPlus = tierLower.contains('pro_plus') || tierLower.contains('proplus') || tierLower == 'studio';
    final isStudio = ent.isStudio;

    void push(Widget screen) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Business',
        onAvatarTap: onAvatarTap,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GymiesSectionHeader('Financiën'),
          _HubTile(
            icon: Icons.euro_rounded,
            title: 'Inkomsten',
            subtitle: 'Overzicht van je verdiensten en facturen',
            onTap: () => push(const TrainerIncomeScreen()),
          ),
          _HubTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Financiën+',
            subtitle: 'Forecast, uitbetalingen en instellingen',
            onTap: () => push(const TrainerFinanceScreen()),
          ),
          const SizedBox(height: 16),
          GymiesSectionHeader('Aanbod'),
          _HubTile(
            icon: Icons.inventory_2_outlined,
            title: 'Pakketten',
            subtitle: 'Beheer je trainingsabonnementen en strippenkaarten',
            onTap: () => push(const TrainerPackagesScreen()),
          ),
          _HubTile(
            icon: Icons.groups_rounded,
            title: 'Groepslessen',
            subtitle: 'Plan en beheer groepssessies',
            locked: !isPro,
            lockLabel: 'Pro',
            onTap: isPro ? () => push(const TrainerGroupSessionsScreen()) : null,
          ),
          _HubTile(
            icon: Icons.local_offer_outlined,
            title: 'Promo codes',
            subtitle: 'Maak kortingscodes voor klanten',
            locked: !isPro,
            lockLabel: 'Pro',
            onTap: isPro ? () => push(const TrainerPromoCodesScreen()) : null,
          ),
          const SizedBox(height: 16),
          GymiesSectionHeader('Presentatie'),
          _HubTile(
            icon: Icons.storefront_rounded,
            title: 'Etalage-editor',
            subtitle: 'Pas je publieke trainerspagina aan',
            locked: !isPro,
            lockLabel: 'Pro',
            onTap: isPro
                ? () => push(const TrainerStorefrontEditorScreen())
                : null,
          ),
          _HubTile(
            icon: Icons.palette_outlined,
            title: 'Mijn Branding',
            subtitle: 'Logo, banner, kleur en profiel-URL aanpassen',
            locked: !isProPlus,
            lockLabel: 'Pro+',
            onTap: isProPlus
                ? () => push(const TrainerBrandingScreen())
                : null,
          ),
          if (isStudio)
            _HubTile(
              icon: Icons.hub_outlined,
              title: 'Studio & Onboarding',
              subtitle: 'Team, locaties en onboarding-instellingen',
              onTap: () => push(const TrainerStudioScreen()),
            ),
          const SizedBox(height: 16),
          GymiesSectionHeader('Marketing'),
          _HubTile(
            icon: Icons.newspaper_rounded,
            title: 'Nieuwsbrief',
            subtitle: 'Stuur nieuwsbrieven naar je actieve klanten',
            locked: !isProPlus,
            lockLabel: 'Pro+',
            onTap: isProPlus
                ? () => push(const TrainerNewsletterScreen())
                : null,
          ),
          _HubTile(
            icon: Icons.qr_code_2_rounded,
            title: 'Widget & QR',
            subtitle: 'Booking widget en QR-code voor je profiel',
            locked: !isProPlus,
            lockLabel: 'Pro+',
            onTap: isProPlus
                ? () => push(const TrainerWidgetQrScreen())
                : null,
          ),
          const SizedBox(height: 16),
          GymiesSectionHeader('Groei'),
          _HubTile(
            icon: Icons.insights_rounded,
            title: 'Pro Hub',
            subtitle: 'Inzichten, upsell en herboek-tools',
            locked: !isPro,
            lockLabel: 'Pro',
            onTap: isPro ? () => push(const TrainerProHubScreen()) : null,
          ),
          _HubTile(
            icon: Icons.analytics_outlined,
            title: 'Klant Analytics',
            subtitle: 'Activiteit, retentie en omzet per klant',
            locked: !isProPlus,
            lockLabel: 'Pro+',
            onTap: isProPlus
                ? () => push(const TrainerClientAnalyticsScreen())
                : null,
          ),
          if (isStudio) ...[
            const SizedBox(height: 16),
            GymiesSectionHeader('Gym'),
            _HubTile(
              icon: Icons.business_rounded,
              title: 'Gym Dashboard',
              subtitle: 'Beheer trainers, boekingen en klanten van je gym',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GymShell()),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
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
      margin: const EdgeInsets.only(bottom: 10),
      color: locked ? Colors.grey.shade100 : Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: locked
              ? Colors.grey.shade300
              : GymiesColors.primary.withValues(alpha: 0.2),
          child: Icon(
            icon,
            color: locked ? Colors.grey.shade500 : GymiesColors.darkBlue,
            size: 22,
          ),
        ),
        title: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: locked ? Colors.grey.shade500 : GymiesColors.darkBlue,
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
            ? const Icon(Icons.lock_outline_rounded,
                size: 18, color: Colors.grey)
            : const Icon(Icons.chevron_right, color: GymiesColors.darkBlue),
        onTap: onTap,
      ),
    );
  }
}
