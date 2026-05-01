import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/gymies_api.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'trainer_newsletter_screen.dart';
import 'trainer_packages_screen.dart';
import 'trainer_promo_codes_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_section_header.dart';

class TrainerMarketingHubScreen extends StatefulWidget {
  const TrainerMarketingHubScreen({Key? key}) : super(key: key);

  @override
  State<TrainerMarketingHubScreen> createState() =>
      _TrainerMarketingHubScreenState();
}

class _TrainerMarketingHubScreenState extends State<TrainerMarketingHubScreen> {
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  int _packagesCount = 0;
  int _activePromosCount = 0;
  int _newslettersCount = 0;

  @override
  void initState() {
    super.initState();
    _loadMarketingData();
  }

  Future<void> _loadMarketingData() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      final api = context.read<GymiesApi>();

      // Load packages
      int packagesCount = 0;
      try {
        final packages = await api.getTrainerPackages();
        packagesCount = packages.length;
      } catch (_) {}

      // Load promo codes
      final promoCodes = await api.getTrainerPromoCodes();
      final activePromos = promoCodes
          .where((p) => p['status']?.toLowerCase() == 'active')
          .length;

      // Load newsletter history
      final newsletters = await api.getTrainerNewsletterHistory();

      if (mounted) {
        setState(() {
          _packagesCount = packagesCount;
          _activePromosCount = activePromos;
          _newslettersCount = newsletters.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Fout bij laden van marketinggegevens';
          _isLoading = false;
          _packagesCount = 0;
          _activePromosCount = 0;
          _newslettersCount = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check tier
    final subs = context.read<SubscriptionEntitlementsService>();
    final tier = subs.tier ?? '';
    final tierLower = tier.toLowerCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Marketing Tools'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _errorMessage,
                        style: GoogleFonts.sora(
                          fontSize: 16,
                          color: Colors.grey.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loadMarketingData,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Opnieuw proberen'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stats Row
                      _buildStatsRow(),
                      const SizedBox(height: 32),

                      // Navigation Cards Section
                      _buildNavigationCards(context, tierLower),
                      const SizedBox(height: 32),

                      // Tips Section
                      _buildTipsSection(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            label: 'Pakketten',
            value: _packagesCount.toString(),
            icon: Icons.inventory_2_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            label: 'Actieve promo\'s',
            value: _activePromosCount.toString(),
            icon: Icons.local_offer_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            label: 'Nieuwsbrieven',
            value: _newslettersCount.toString(),
            icon: Icons.email_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({required String label, required String value, required IconData icon}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: GymiesColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: GymiesColors.darkBlue),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.sora(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: GymiesColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.sora(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationCards(BuildContext context, String tierLower) {
    final isPro = tierLower.contains('pro') || tierLower == 'studio';
    final isProPlus = tierLower.contains('pro_plus') ||
        tierLower.contains('proplus') ||
        tierLower == 'studio';

    return Column(
      children: [
        // Pakketten Card
        _buildNavigationCard(
          context: context,
          icon: Icons.inventory_2_outlined,
          title: 'Pakketten',
          subtitle: 'Beheer je sessie-pakketten en strippenkaarten',
          onTap: () {
            Haptics.selection();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TrainerPackagesScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // Promo Codes Card
        _buildNavigationCard(
          context: context,
          icon: Icons.local_offer_outlined,
          title: 'Promo codes',
          subtitle: 'Maak kortingscodes en volg gebruik',
          onTap: () {
            Haptics.selection();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TrainerPromoCodesScreen(),
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // Newsletter Card (Pro+)
        _buildNavigationCard(
          context: context,
          icon: Icons.email_outlined,
          title: 'Nieuwsbrief',
          subtitle: 'Verstuur updates naar je klanten',
          isLocked: !isProPlus,
          lockLabel: isProPlus ? null : 'Pro+',
          onTap: isProPlus
              ? () {
                  Haptics.selection();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TrainerNewsletterScreen(),
                    ),
                  );
                }
              : null,
        ),
      ],
    );
  }

  Widget _buildNavigationCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool isLocked = false,
    String? lockLabel,
  }) {
    return GestureDetector(
      onTap: isLocked ? null : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: isLocked
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: isLocked
                    ? Colors.grey.shade100
                    : GymiesColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(12),
              child: Icon(
                isLocked ? Icons.lock_outlined : icon,
                color: isLocked ? Colors.grey.shade400 : GymiesColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.sora(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isLocked ? Colors.grey.shade400 : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: isLocked ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isLocked && lockLabel != null)
              Container(
                decoration: BoxDecoration(
                  color: GymiesColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  lockLabel,
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.primary,
                  ),
                ),
              )
            else if (!isLocked)
              Icon(
                Icons.chevron_right,
                color: Colors.grey.shade400,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsSection() {
    final tips = [
      'Gebruik promo codes bij seizoenswisselingen voor meer boekingen',
      'Verstuur maandelijks een nieuwsbrief om klanten betrokken te houden',
      'Voeg je social media links toe zodat klanten je kunnen volgen',
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GymiesSectionHeader('Tips'),
          const SizedBox(height: 16),
          Column(
            children: List.generate(
              tips.length,
              (index) => Column(
                children: [
                  _buildTipItem(tips[index]),
                  if (index < tips.length - 1) const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipItem(String tip) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: GymiesColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.tips_and_updates_outlined,
            color: GymiesColors.darkBlue,
            size: 14,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            tip,
            style: GoogleFonts.sora(
              fontSize: 14,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
