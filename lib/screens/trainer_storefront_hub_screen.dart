import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/gymies_api.dart';
import '../services/storefront_cms_provider.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'trainer_storefront_profile_screen.dart';
import 'trainer_storefront_rates_screen.dart';
import 'trainer_storefront_logistics_screen.dart';
import 'trainer_storefront_social_screen.dart';
import 'trainer_storefront_branding_screen.dart';
import 'trainer_storefront_seo_screen.dart';
import 'widgets/gymies_app_bar.dart';

/// Hub-scherm "Mijn Etalage" — categoriekaarten die elk naar een
/// eigen editor-pagina leiden (Fresha / Shopify patroon).
class TrainerStorefrontHubScreen extends StatefulWidget {
  const TrainerStorefrontHubScreen({super.key});

  @override
  State<TrainerStorefrontHubScreen> createState() =>
      _TrainerStorefrontHubScreenState();
}

class _TrainerStorefrontHubScreenState
    extends State<TrainerStorefrontHubScreen> {
  bool _loading = true;

  // Status-info per kaart
  String _bioSnippet = '';
  int _specCount = 0;
  String _rateDisplay = '';
  String _paymentLabel = '';
  bool _hasOwnLocation = false;
  bool _offersDuo = false;
  int? _cancellationHours;
  int _socialsCount = 0;
  bool _hasGallery = false;
  String _brandColor = '#FEBE23';
  bool _hasLogo = false;
  bool _hasBanner = false;
  int _seoScore = 0;
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cmsProvider = context.read<StorefrontCmsProvider>();
      final api = context.read<GymiesApi>();
      final results = await Future.wait([
        cmsProvider.ensureLoaded(),
        api.getProPlusSettings().catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;

      final cms = cmsProvider.data ?? <String, dynamic>{};
      final branding = results[1] as Map<String, dynamic>;

      // Bio
      final bio = (cms['bio'] ?? cms['about'] ?? cms['intro'] ?? '').toString().trim();
      _bioSnippet = bio.length > 60 ? '${bio.substring(0, 60)}...' : bio;

      // Specialisaties
      final rawTags = cms['specializations_tags'] ?? cms['specializationsTags'];
      _specCount = rawTags is List ? rawTags.where((e) => e.toString().trim().isNotEmpty).length : 0;

      // Tarieven
      final rateCents = cms['hourly_rate_cents'] ?? cms['hourlyRateCents'];
      if (rateCents is int && rateCents > 0) {
        _rateDisplay = '\u20AC${(rateCents / 100).toStringAsFixed(0)}/sessie';
      } else {
        _rateDisplay = '';
      }
      final pm = (cms['payment_method'] ?? cms['paymentMethod'] ?? '').toString();
      _paymentLabel = _paymentMethodLabel(pm);

      // Logistiek
      _hasOwnLocation = cms['has_own_location'] == true;
      _offersDuo = cms['offers_duo_training'] == true;
      final cH = cms['cancellation_hours'] ?? cms['cancellationHours'];
      _cancellationHours = cH is int ? cH : int.tryParse(cH?.toString() ?? '');

      // Social
      int sc = 0;
      for (final key in ['instagram_url', 'tiktok_url', 'facebook_url']) {
        if (cms[key] != null && cms[key].toString().trim().isNotEmpty) sc++;
      }
      _socialsCount = sc;
      _hasGallery = false; // placeholder — gallery count via aparte call indien nodig

      // Branding
      _brandColor = (branding['brand_color'] as String?) ?? '#FEBE23';
      _hasLogo = (branding['brand_logo_url'] as String?)?.isNotEmpty == true;
      _hasBanner = (branding['brand_banner_url'] as String?)?.isNotEmpty == true;
      _verified = branding['verified_badge'] == true;

      // SEO score
      final metaTitle = (cms['seo_title'] ?? cms['meta_title'] ?? '').toString();
      final metaDesc = (cms['seo_description'] ?? cms['meta_description'] ?? '').toString();
      final slug = (cms['profile_slug'] ?? cms['slug'] ?? '').toString();
      _seoScore = _calcSeoScore(metaTitle, metaDesc, slug);

      setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _calcSeoScore(String title, String desc, String slug) {
    int score = 0;
    final tl = title.length;
    final dl = desc.length;
    if (tl >= 50 && tl <= 60) { score += 30; } else if (tl > 0) { score += 20; }
    if (dl >= 120 && dl <= 160) { score += 40; } else if (dl > 0) { score += 25; }
    if (slug.isNotEmpty) score += 20;
    return score.clamp(0, 100);
  }

  String _paymentMethodLabel(String pm) {
    switch (pm) {
      case 'transfer_and_cash': return 'Overboekingen & cash';
      case 'transfer_only': return 'Alleen overboekingen';
      case 'cash_only': return 'Alleen cash';
      default: return '';
    }
  }

  void _pushAndRefresh(Widget screen) {
    Haptics.selection();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final ent = Provider.of<SubscriptionEntitlementsService>(context);
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isPro = tierLower.contains('pro') || tierLower == 'studio';
    final isProPlus = tierLower.contains('pro_plus') ||
        tierLower.contains('proplus') ||
        tierLower == 'studio';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Mijn Etalage'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Intro tekst ──
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: GymiesColors.darkBlue,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: GymiesColors.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.storefront_rounded,
                              color: GymiesColors.primary, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Jouw publieke profiel',
                                style: GoogleFonts.sora(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Beheer hoe klanten jou zien op Gymies',
                                style: GoogleFonts.sora(
                                  fontSize: 12,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── 1. Profiel & Bio ──
                  _buildCategoryCard(
                    icon: Icons.person_outline,
                    title: 'Profiel & Bio',
                    statusLines: [
                      if (_bioSnippet.isNotEmpty) _bioSnippet else 'Nog geen bio ingesteld',
                      if (_specCount > 0) '$_specCount specialisaties',
                    ],
                    onTap: () => _pushAndRefresh(const TrainerStorefrontProfileScreen()),
                  ),
                  const SizedBox(height: 12),

                  // ── 2. Tarieven & Betaling ──
                  _buildCategoryCard(
                    icon: Icons.euro_outlined,
                    title: 'Tarieven & Betaling',
                    statusLines: [
                      if (_rateDisplay.isNotEmpty) _rateDisplay else 'Nog geen tarief ingesteld',
                      if (_paymentLabel.isNotEmpty) _paymentLabel,
                    ],
                    onTap: () => _pushAndRefresh(const TrainerStorefrontRatesScreen()),
                  ),
                  const SizedBox(height: 12),

                  // ── 3. Logistiek & Annulering ──
                  _buildCategoryCard(
                    icon: Icons.location_on_outlined,
                    title: 'Logistiek & Annulering',
                    statusLines: [
                      [
                        if (_hasOwnLocation) 'Eigen locatie',
                        if (_offersDuo) 'Duo-training',
                      ].join(' \u2022 ').isNotEmpty
                          ? [
                              if (_hasOwnLocation) 'Eigen locatie',
                              if (_offersDuo) 'Duo-training',
                            ].join(' \u2022 ')
                          : 'Geen opties ingesteld',
                      if (_cancellationHours != null)
                        'Annulering: ${_cancellationHours}u van tevoren',
                    ],
                    onTap: () => _pushAndRefresh(const TrainerStorefrontLogisticsScreen()),
                  ),
                  const SizedBox(height: 12),

                  // ── 4. Social Media & Gallery (Pro) ──
                  _buildCategoryCard(
                    icon: Icons.share_outlined,
                    title: 'Social Media & Gallery',
                    statusLines: [
                      '$_socialsCount social links ingesteld',
                    ],
                    locked: !isPro,
                    lockLabel: 'Pro',
                    onTap: isPro
                        ? () => _pushAndRefresh(const TrainerStorefrontSocialScreen())
                        : null,
                  ),
                  const SizedBox(height: 12),

                  // ── 5. Branding (Pro+) ──
                  _buildCategoryCard(
                    icon: Icons.palette_outlined,
                    title: 'Branding',
                    statusLines: [
                      [
                        if (_hasLogo) 'Logo',
                        if (_hasBanner) 'Banner',
                      ].join(' \u2022 ').isNotEmpty
                          ? [
                              if (_hasLogo) 'Logo',
                              if (_hasBanner) 'Banner',
                            ].join(' \u2022 ')
                          : 'Nog niet geconfigureerd',
                    ],
                    locked: !isProPlus,
                    lockLabel: 'Pro+',
                    onTap: isProPlus
                        ? () => _pushAndRefresh(const TrainerStorefrontBrandingScreen())
                        : null,
                  ),
                  const SizedBox(height: 12),

                  // ── 6. SEO & Verificatie (Pro+) ──
                  _buildCategoryCard(
                    icon: Icons.search_outlined,
                    title: 'SEO & Verificatie',
                    statusLines: [
                      'SEO score: $_seoScore/100',
                      if (_verified) 'Geverifieerd \u2713',
                    ],
                    locked: !isProPlus,
                    lockLabel: 'Pro+',
                    onTap: isProPlus
                        ? () => _pushAndRefresh(const TrainerStorefrontSeoScreen())
                        : null,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildCategoryCard({
    required IconData icon,
    required String title,
    required List<String> statusLines,
    VoidCallback? onTap,
    bool locked = false,
    String? lockLabel,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: locked ? Colors.grey.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: locked
              ? null
              : [
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: locked
                    ? Colors.grey.shade300
                    : GymiesColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                locked ? Icons.lock_outlined : icon,
                color: locked ? Colors.grey.shade500 : GymiesColors.darkBlue,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.sora(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: locked
                              ? Colors.grey.shade500
                              : GymiesColors.darkBlue,
                        ),
                      ),
                      if (locked && lockLabel != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: GymiesColors.primary.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            lockLabel,
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
                  const SizedBox(height: 4),
                  ...statusLines.where((s) => s.isNotEmpty).map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        line,
                        style: GoogleFonts.sora(
                          fontSize: 12,
                          color: locked
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (locked)
              Icon(Icons.lock_outline_rounded, size: 18, color: Colors.grey.shade400)
            else
              const Icon(Icons.chevron_right, color: GymiesColors.darkBlue),
          ],
        ),
      ),
    );
  }
}
