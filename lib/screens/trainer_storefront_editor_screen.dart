import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../services/storefront_cms_provider.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import '../utils/trainer_badges.dart';
import 'widgets/trainer_media_section.dart';
import 'widgets/trainer_state_views.dart';

/// Etalage Editor — alles-in-één beheer van het openbare trainerprofiel.
/// Bevat: branding, bio, social, tarieven, logistiek, annulering, media, SEO.
class TrainerStorefrontEditorScreen extends StatefulWidget {
  const TrainerStorefrontEditorScreen({super.key});

  @override
  State<TrainerStorefrontEditorScreen> createState() =>
      _TrainerStorefrontEditorScreenState();
}

class _TrainerStorefrontEditorScreenState
    extends State<TrainerStorefrontEditorScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  // ── Stories ──
  // ignore: unused_field
  bool _loadingStories = false;
  // ignore: unused_field
  int _activeStoryCount = 0;

  // ── Branding (voorheen apart scherm) ──
  String _brandColor = '#FEBE23';
  String? _logoUrl;
  String? _bannerUrl;
  String? _newLogoPath;
  String? _newBannerPath;
  bool _verifiedBadge = false;
  final _videoController = TextEditingController();

  // ── Bio & Specialisaties ──
  final _bioController = TextEditingController();
  List<String> _specTags = [];
  final _newTagController = TextEditingController();

  // ── Social media ──
  final _instagramController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _facebookController = TextEditingController();

  // ── Tarieven & betaling ──
  final _hourlyRateController = TextEditingController();
  String _paymentMethod = 'transfer_and_cash';

  // ── Logistiek ──
  bool _hasOwnLocation = false;
  bool _offersDuoTraining = false;
  bool _hasIntroOffer = false;
  final _introOfferController = TextEditingController();
  final _bookingDaysController = TextEditingController();

  // ── Annuleringsbeleid ──
  int? _cancellationHours;
  int? _cancellationRefundPercent;
  final _cancellationExceptionsController = TextEditingController();

  // ── Badge voorkeuren ──
  Set<String> _visibleBadgeIds = {};
  bool _badgesChanged = false;

  // ── SEO ──
  final _metaTitleController = TextEditingController();
  final _metaDescriptionController = TextEditingController();
  final _seoSlugController = TextEditingController();

  // ── Trainer info (voor preview) ──
  String _trainerName = '';
  String _trainerCity = '';
  double? _avgRating;
  int _reviewCount = 0;

  static const _presetColors = [
    '#FEBE23', '#FF6B6B', '#4ECDC4', '#45B7D1',
    '#96CEB4', '#DDA0DD', '#98D8C8', '#F7DC6F',
    '#BB8FCE', '#85C1E9', '#F0B27A', '#1E3A5F',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _newTagController.dispose();
    _instagramController.dispose();
    _tiktokController.dispose();
    _facebookController.dispose();
    _hourlyRateController.dispose();
    _introOfferController.dispose();
    _bookingDaysController.dispose();
    _cancellationExceptionsController.dispose();
    _metaTitleController.dispose();
    _metaDescriptionController.dispose();
    _seoSlugController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cmsProvider = context.read<StorefrontCmsProvider>();
      final api = context.read<GymiesApi>();

      // Laad CMS via shared provider + branding (Pro+)
      final results = await Future.wait([
        cmsProvider.ensureLoaded(),
        api.getProPlusSettings().catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;

      final cms = cmsProvider.data ?? <String, dynamic>{};
      final branding = results[1] as Map<String, dynamic>;

      // ── Trainer info ──
      _trainerName = mapStr(cms, [S.of(context).trainername, S.of(context).trainername2, 'name']);
      _trainerCity = mapStr(cms, ['city', 'location', 'stad']);
      final rating = cms['avg_rating'] ?? cms['avgRating'] ?? cms['rating'];
      _avgRating = rating is num ? rating.toDouble() : double.tryParse(rating?.toString() ?? '');
      final rc = cms['review_count'] ?? cms['reviewCount'] ?? cms['reviews_count'];
      _reviewCount = rc is int ? rc : int.tryParse(rc?.toString() ?? '') ?? 0;

      // ── Bio ──
      _bioController.text = mapStr(cms, ['bio', 'about', 'intro']);

      // ── Specialisaties ──
      final rawTags = cms['specializations_tags'] ?? cms['specializationsTags'];
      _specTags = rawTags is List
          ? rawTags.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
          : [];

      // ── Social ──
      _instagramController.text = mapStr(cms, ['instagram_url', 'instagramUrl']);
      _tiktokController.text = mapStr(cms, ['tiktok_url', 'tiktokUrl', 'tiktok_username']);
      _facebookController.text = mapStr(cms, ['facebook_url', 'facebookUrl']);

      // ── Tarieven ──
      final rateCents = cms['hourly_rate_cents'] ?? cms['hourlyRateCents'];
      _hourlyRateController.text = (rateCents is int && rateCents > 0)
          ? (rateCents / 100).toStringAsFixed(0) : '';
      _paymentMethod = mapStr(cms, ['payment_method', 'paymentMethod']);
      if (_paymentMethod.isEmpty) _paymentMethod = 'transfer_and_cash';

      // ── Logistiek ──
      _hasOwnLocation = cms['has_own_location'] == true;
      _offersDuoTraining = cms['offers_duo_training'] == true;
      _hasIntroOffer = cms['has_intro_offer'] == true;
      _introOfferController.text = mapStr(cms, ['intro_offer_description', 'introOfferDescription']);
      final bookDays = cms['booking_advance_days'] ?? cms['bookingAdvanceDays'];
      _bookingDaysController.text = bookDays != null ? bookDays.toString() : '';

      // ── Annulering ──
      final cH = cms['cancellation_hours'] ?? cms['cancellationHours'];
      _cancellationHours = cH is int ? cH : int.tryParse(cH?.toString() ?? '');
      final cR = cms['cancellation_refund_percent'] ?? cms['cancellationRefundPercent'];
      _cancellationRefundPercent = cR is int ? cR : int.tryParse(cR?.toString() ?? '');
      _cancellationExceptionsController.text = mapStr(cms, ['cancellation_exceptions', 'cancellationExceptions']);

      // ── Badge voorkeuren ──
      final badgesRaw = cms['visible_badges'] ?? cms['visible_badge_ids'] ?? cms['visibleBadgeIds'];
      if (badgesRaw is List) {
        _visibleBadgeIds = badgesRaw.map((e) => e.toString()).toSet();
      }
      _badgesChanged = false;

      // ── SEO ──
      _metaTitleController.text = mapStr(cms, ['seo_title', 'metaTitle', 'meta_title']);
      _metaDescriptionController.text = mapStr(cms, ['seo_description', 'metaDescription', 'meta_description']);
      _seoSlugController.text = mapStr(cms, ['profile_slug', 'profileSlug', 'slug']);

      // ── Branding ──
      _brandColor = (branding['brand_color'] as String?) ?? '#FEBE23';
      _logoUrl = branding['brand_logo_url'] as String?;
      _bannerUrl = branding['brand_banner_url'] as String?;
      _videoController.text = (branding['intro_video_url'] as String?) ?? '';
      _verifiedBadge = branding['verified_badge'] == true;

      setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = S.of(context).konEtalageNietLaden; _loading = false; });
    }
  }

  Future<void> _save() async {
    Haptics.light();
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final api = context.read<GymiesApi>();

      // Upload branding-bestanden
      if (_newLogoPath != null) {
        final res = await api.uploadProPlusLogo(_newLogoPath!);
        if (!mounted) return;
        _logoUrl = res['url'] as String? ?? _logoUrl;
        _newLogoPath = null;
      }
      if (_newBannerPath != null) {
        final res = await api.uploadProPlusBanner(_newBannerPath!);
        if (!mounted) return;
        _bannerUrl = res['url'] as String? ?? _bannerUrl;
        _newBannerPath = null;
      }

      // Uurtarief: euro → centen
      int? rateCents;
      final rateText = _hourlyRateController.text.trim();
      if (rateText.isNotEmpty) {
        final parsed = double.tryParse(rateText);
        if (parsed != null) rateCents = (parsed * 100).round();
      }

      // Storefront CMS opslaan
      await api.updateTrainerStorefrontCms({
        'bio': _bioController.text.trim(),
        'specializations_tags': _specTags,
        'instagram_url': _instagramController.text.trim(),
        'tiktok_url': _tiktokController.text.trim(),
        'facebook_url': _facebookController.text.trim(),
        'hourly_rate_cents': rateCents,
        'payment_method': _paymentMethod,
        'has_own_location': _hasOwnLocation,
        'offers_duo_training': _offersDuoTraining,
        'has_intro_offer': _hasIntroOffer,
        'intro_offer_description': _introOfferController.text.trim(),
        'booking_advance_days': _bookingDaysController.text.trim().isNotEmpty
            ? int.tryParse(_bookingDaysController.text.trim()) : null,
        'cancellation_hours': _cancellationHours,
        'cancellation_refund_percent': _cancellationRefundPercent,
        'cancellation_exceptions': _cancellationExceptionsController.text.trim(),
        'seo_title': _metaTitleController.text.trim(),
        'seo_description': _metaDescriptionController.text.trim(),
        'profile_slug': _seoSlugController.text.trim(),
        if (_badgesChanged) 'visible_badges': _visibleBadgeIds.toList(),
      });
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      context.read<StorefrontCmsProvider>().invalidate();

      // Branding opslaan
      final slug = _seoSlugController.text.trim().toLowerCase();
      final videoUrl = _videoController.text.trim();
      await api.updateProPlusSettings({
        if (slug.isNotEmpty) 'custom_slug': slug,
        'brand_color': _brandColor,
        'intro_video_url': videoUrl.isEmpty ? null : videoUrl,
      }).catchError((_) => <String, dynamic>{});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(S.of(context).etalageOpgeslagen, style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
            ],
          ),
          backgroundColor: GymiesColors.darkBlue,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage({required bool isLogo}) async {
    Haptics.selection();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: isLogo ? 512 : 1920,
      maxHeight: isLogo ? 512 : 1080,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isLogo) { _newLogoPath = picked.path; }
      else { _newBannerPath = picked.path; }
    });
  }

  void _addTag() {
    Haptics.light();
    final tag = _newTagController.text.trim();
    if (tag.isEmpty || _specTags.contains(tag) || _specTags.length >= 20) return;
    setState(() { _specTags.add(tag); _newTagController.clear(); });
  }

  void _removeTag(String tag) {
    Haptics.heavy();
    setState(() => _specTags.remove(tag));
  }

  Color _parseHex(String hex) {
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return GymiesColors.primary;
    return Color(int.parse('FF$clean', radix: 16));
  }

  // ═══════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════

  // ignore: unused_element
  Future<void> _uploadStory() async {
    final tier = context.read<SubscriptionEntitlementsService>().tier?.toLowerCase() ?? 'starter';
    if (!['pro', 'pro_plus'].contains(tier)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.of(context).storiesIsEenProFeatureUpgradeJeAbonnement)),
        );
      }
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1080);
    if (picked == null) return;
    if (!mounted) return;
    try {
      Haptics.light();
      // ignore: use_build_context_synchronously
      await context.read<GymiesApi>().uploadStory(picked.path);
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.of(context).storyGeplaatstZichtbaarVoor24Uur)),
        );
        _loadStoryCount();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).uploadMisluktMsg(e.message ?? ''))),
        );
      }
    }
  }

  Future<void> _loadStoryCount() async {
    setState(() => _loadingStories = true);
    try {
      final user = context.read<AuthService>().user;
      final hasStories = await context.read<GymiesApi>().hasActiveStories(user?['id']?.toString() ?? '');
      if (!mounted) return;
      setState(() => _activeStoryCount = hasStories ? 1 : 0);
    } catch (_) {
      setState(() => _activeStoryCount = 0);
    } finally {
      if (mounted) setState(() => _loadingStories = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Get tier info ──
    final ent = Provider.of<SubscriptionEntitlementsService>(context);
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isPro = tierLower.contains('pro') || tierLower == 'studio';
    final isProPlus = tierLower.contains('pro_plus') || tierLower.contains('proplus') || tierLower == 'studio';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: GymiesListBody(
          loading: _loading,
          error: _error,
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
            // ── Collapsing header met live preview ──
            _buildSliverHeader(),

            // ── Content ──
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // 1. BRANDING
                  if (isProPlus) ...[
                    _buildSection(
                      icon: Icons.palette_outlined,
                      title: S.of(context).branding,
                      subtitle: S.of(context).maakJeProfielHerkenbaar,
                      badge: 'PRO+',
                      children: [
                        _buildBrandingContent(),
                      ],
                    ),
                  ] else ...[
                    _buildUpgradeHint('Branding', 'Pro+'),
                  ],
                  const SizedBox(height: 16),

                  // 2. OVER MIJ
                  _buildSection(
                    icon: Icons.person_outline,
                    title: 'Over mij',
                    subtitle: S.of(context).stelJezelfVoorAanKlanten,
                    children: [
                      TextField(
                        controller: _bioController,
                        maxLines: 5,
                        maxLength: 5000,
                        style: GoogleFonts.sora(fontSize: 14),
                        decoration: _inputDecoration(
                          hint: S.of(context).vertelWieJeBentWatJe,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSpecTags(),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 3. INTRO VIDEO
                  if (isProPlus) ...[
                    _buildSection(
                      icon: Icons.videocam_outlined,
                      title: 'Intro video',
                      subtitle: S.of(context).toonEenYoutubeOfVimeoVideo,
                      badge: 'PRO+',
                      children: [
                        TextField(
                          controller: _videoController,
                          style: GoogleFonts.sora(fontSize: 14),
                          decoration: _inputDecoration(
                            hint: 'https://youtube.com/watch?v=...',
                            prefix: Icons.link_rounded,
                          ),
                          keyboardType: TextInputType.url,
                        ),
                      ],
                    ),
                  ] else ...[
                    _buildUpgradeHint('Intro video', 'Pro+'),
                  ],
                  const SizedBox(height: 16),

                  // 4. SOCIAL MEDIA
                  if (isPro) ...[
                    _buildSection(
                      icon: Icons.share_outlined,
                      title: 'Social media',
                      subtitle: S.of(context).toonJeSocialsOpJeProfiel,
                      children: [
                        _buildSocialField(
                          controller: _instagramController,
                          label: 'Instagram',
                          hint: S.of(context).jouwhandleOfUrl,
                          icon: Icons.camera_alt_rounded,
                          iconColor: const Color(0xFFE1306C),
                        ),
                        const SizedBox(height: 12),
                        _buildSocialField(
                          controller: _tiktokController,
                          label: 'TikTok',
                          hint: '@jouwhandle',
                          icon: Icons.music_note_rounded,
                          iconColor: const Color(0xFF010101),
                        ),
                        const SizedBox(height: 12),
                        _buildSocialField(
                          controller: _facebookController,
                          label: 'Facebook',
                          hint: 'facebook.com/jouwpagina',
                          icon: Icons.facebook_rounded,
                          iconColor: const Color(0xFF1877F2),
                        ),
                      ],
                    ),
                  ] else ...[
                    _buildUpgradeHint('Social media', 'Pro'),
                  ],
                  const SizedBox(height: 16),

                  // 5. TARIEVEN & BETALING
                  _buildSection(
                    icon: Icons.euro_outlined,
                    title: S.of(context).tarievenBetaling,
                    subtitle: S.of(context).watKostEenSessieEnHoe,
                    children: [
                      TextField(
                        controller: _hourlyRateController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.sora(fontSize: 14),
                        decoration: _inputDecoration(
                          label: S.of(context).prijsPerSessie,
                          hint: 'bijv. 50',
                          prefixText: '€ ',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        S.of(context).betaalmethode,
                        style: GoogleFonts.sora(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildPaymentMethodCards(),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 6. LOGISTIEK
                  _buildSection(
                    icon: Icons.location_on_outlined,
                    title: 'Logistiek',
                    subtitle: S.of(context).locatieDuotrainingEnAanbiedingen,
                    children: [
                      _buildToggleRow(
                        label: 'Eigen trainingslocatie',
                        subtitle: S.of(context).jeHebtEenVastePlekVoor,
                        value: _hasOwnLocation,
                        onChanged: (v) => setState(() => _hasOwnLocation = v),
                      ),
                      const Divider(height: 24),
                      _buildToggleRow(
                        label: 'Duo-training',
                        subtitle: S.of(context).trainingVoor2PersonenTegelijk,
                        value: _offersDuoTraining,
                        onChanged: (v) => setState(() => _offersDuoTraining = v),
                      ),
                      const Divider(height: 24),
                      _buildToggleRow(
                        label: 'Introductiekorting',
                        subtitle: S.of(context).nieuweKlantenKrijgenKorting,
                        value: _hasIntroOffer,
                        onChanged: (v) => setState(() => _hasIntroOffer = v),
                      ),
                      if (_hasIntroOffer) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _introOfferController,
                          maxLength: 500,
                          maxLines: 2,
                          style: GoogleFonts.sora(fontSize: 14),
                          decoration: _inputDecoration(
                            hint: S.of(context).bijvEersteSessie50Korting,
                          ),
                        ),
                      ],
                      const Divider(height: 24),
                      TextField(
                        controller: _bookingDaysController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.sora(fontSize: 14),
                        decoration: _inputDecoration(
                          label: S.of(context).boekingstermijndagen,
                          hint: S.of(context).hoeVerVooruitGeboektKanWorden,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 7. ANNULERINGSBELEID
                  _buildSection(
                    icon: Icons.event_busy_outlined,
                    title: 'Annuleringsbeleid',
                    subtitle: S.of(context).annuleringsEnRestitutieregels,
                    children: [
                      _buildCancellationContent(),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 8. BADGE VOORKEUREN
                  _buildSection(
                    icon: Icons.badge_outlined,
                    title: 'Badge voorkeuren',
                    subtitle: 'Kies welke badges zichtbaar zijn op je profiel (max $kMaxProfileBadges)',
                    children: [_buildBadgeContent()],
                  ),
                  const SizedBox(height: 16),

                  // 9. STORIES & GALLERY
                  if (isPro) ...[
                    _buildSection(
                      icon: Icons.photo_library_outlined,
                      title: 'Stories & Gallery',
                      subtitle: S.of(context).fotosEnVideosOpJeProfiel,
                      children: [
                        const TrainerMediaSection(),
                      ],
                    ),
                  ] else ...[
                    _buildUpgradeHint('Stories & Gallery', 'Pro'),
                  ],
                  const SizedBox(height: 16),

                  // 9. VERIFICATIE BADGE
                  if (isProPlus) ...[
                    _buildSection(
                      icon: Icons.verified_outlined,
                      title: 'Verificatie badge',
                      subtitle: S.of(context).krijgEenBlauwVinkjeOpJe,
                      badge: 'PRO+',
                      children: [
                        _buildVerificationContent(),
                      ],
                    ),
                  ] else ...[
                    _buildUpgradeHint('Verificatie badge', 'Pro+'),
                  ],
                  const SizedBox(height: 16),

                  // 10. SEO
                  if (isProPlus) ...[
                    _buildSection(
                      icon: Icons.search_outlined,
                      title: S.of(context).seoinstellingen,
                      subtitle: S.of(context).verbeterJeVindbaarheid,
                      children: [
                        _buildSeoContent(),
                      ],
                    ),
                  ] else ...[
                    _buildUpgradeHint(S.of(context).seoinstellingen, 'Pro+'),
                  ],
                  const SizedBox(height: 24),

                  // ── OPSLAAN ──
                  _buildSaveButton(),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SLIVER HEADER — Live preview van het openbare profiel
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSliverHeader() {
    final brandCol = _parseHex(_brandColor);
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: GymiesColors.darkBlue,
      leading: IconButton(
        onPressed: () {
          Haptics.selection();
          Navigator.of(context).pop();
        },
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
      ),
      actions: [
        TextButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: GymiesColors.primary),
                )
              : const Icon(Icons.save_rounded, color: GymiesColors.primary, size: 18),
          label: Text(
            S.of(context).opslaan,
            style: GoogleFonts.sora(
              fontWeight: FontWeight.w600,
              color: GymiesColors.primary,
              fontSize: 13,
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Banner
            if (_newBannerPath != null)
              Image.file(File(_newBannerPath!), fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(color: brandCol.withOpacity(0.3)))
            else if (_bannerUrl != null && _bannerUrl!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: _bannerUrl!,
                fit: BoxFit.cover,
                cacheWidth: 800,
                cacheHeight: 400,
                errorWidget: (_, _, _) => Container(color: brandCol.withOpacity(0.3)),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [GymiesColors.darkBlue, brandCol.withOpacity(0.6)],
                  ),
                ),
              ),

            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),

            // Trainer info
            Positioned(
              left: 20,
              bottom: 20,
              right: 20,
              child: Row(
                children: [
                  // Logo/avatar
                  GestureDetector(
                    onTap: () => _pickImage(isLogo: true),
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: brandCol, width: 3),
                        color: Colors.grey.shade800,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: _newLogoPath != null
                            ? Image.file(File(_newLogoPath!), fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => _logoPlaceholder())
                            : _logoUrl != null && _logoUrl!.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: _logoUrl!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 144,
                                    cacheHeight: 144,
                                    errorWidget: (_, _, _) => _logoPlaceholder(),
                                  )
                                : _logoPlaceholder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Name + city + rating
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _trainerName.isNotEmpty ? _trainerName : 'Jouw naam',
                                style: GoogleFonts.sora(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_verifiedBadge) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.verified, color: brandCol, size: 20),
                            ],
                          ],
                        ),
                        if (_trainerCity.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(Icons.location_on_outlined, color: Colors.white70, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  _trainerCity,
                                  style: GoogleFonts.sora(fontSize: 13, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        if (_avgRating != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                ...List.generate(5, (i) => Icon(
                                  i < _avgRating!.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                                  color: brandCol,
                                  size: 16,
                                )),
                                const SizedBox(width: 6),
                                Text(
                                  '${_avgRating!.toStringAsFixed(1)} ($_reviewCount reviews)',
                                  style: GoogleFonts.sora(fontSize: 12, color: Colors.white60),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tap-to-change banner hint
            Positioned(
              top: 80,
              right: 16,
              child: GestureDetector(
                onTap: () => _pickImage(isLogo: false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt_outlined, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(S.of(context).banner, style: GoogleFonts.sora(fontSize: 11, color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoPlaceholder() => Container(
        color: GymiesColors.darkBlue,
        child: const Icon(Icons.add_a_photo_rounded, color: Colors.white38, size: 28),
      );

  // ═══════════════════════════════════════════════════════════════════
  // SECTION CARD
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSection({
    required IconData icon,
    required String title,
    required String subtitle,
    String? badge,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: GymiesColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: GymiesColors.darkBlue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.sora(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: GymiesColors.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.sora(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // BRANDING CONTENT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildBrandingContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Profiel-URL
        TextField(
          controller: _seoSlugController,
          style: GoogleFonts.sora(fontSize: 14),
          decoration: _inputDecoration(
            label: S.of(context).profielurl,
            hint: 'jouwnaam',
            prefixText: 'gymies.nl/t/',
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9\-]')),
          ],
        ),
        const SizedBox(height: 16),

        // Brand kleur
        Text(
          S.of(context).brandKleur,
          style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _presetColors.map((hex) {
            final selected = _brandColor.toLowerCase() == hex.toLowerCase();
            return GestureDetector(
              onTap: () {
                Haptics.selection();
                setState(() => _brandColor = hex);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _parseHex(hex),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected ? GymiesColors.darkBlue : Colors.grey.shade300,
                    width: selected ? 3 : 1,
                  ),
                  boxShadow: selected
                      ? [BoxShadow(color: _parseHex(hex).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 2))]
                      : null,
                ),
                child: selected
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SPEC TAGS
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSpecTags() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.of(context).specialisaties,
          style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
        ),
        const SizedBox(height: 10),
        if (_specTags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _specTags.map((tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: GymiesColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tag,
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _removeTag(tag),
                    child: Icon(Icons.close_rounded, size: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
            )).toList(),
          ),
        if (_specTags.isNotEmpty) const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newTagController,
                style: GoogleFonts.sora(fontSize: 14),
                decoration: _inputDecoration(
                  hint: 'bijv. Afvallen, Krachttraining...',
                ),
                onSubmitted: (_) => _addTag(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _addTag,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: GymiesColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_rounded, color: GymiesColors.darkBlue),
              ),
            ),
          ],
        ),
        if (_specTags.length >= 20)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              S.of(context).maximumVan20SpecialisatiesBereikt,
              style: GoogleFonts.sora(fontSize: 12, color: Colors.orange.shade700),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // PAYMENT METHOD CARDS (i.p.v. RadioListTiles)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildPaymentMethodCards() {
    const methods = [
      ('transfer_and_cash', S.of(context).overboekingenCash, Icons.account_balance_wallet_outlined),
      ('transfer_only', S.of(context).alleenOverboekingen, Icons.account_balance_outlined),
      ('cash_only', S.of(context).alleenCash, Icons.payments_outlined),
    ];
    return Column(
      children: methods.map((m) {
        final selected = _paymentMethod == m.$1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () {
              Haptics.selection();
              setState(() => _paymentMethod = m.$1);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? GymiesColors.primary.withOpacity(0.12)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? GymiesColors.primary : Colors.grey.shade200,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(m.$3, size: 22, color: selected ? GymiesColors.darkBlue : Colors.grey.shade500),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      m.$2,
                      style: GoogleFonts.sora(
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle_rounded, color: GymiesColors.primary, size: 22),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // CANCELLATION CONTENT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildCancellationContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.of(context).annuleringstermijn,
            style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          initialValue: _cancellationHours,
          decoration: _inputDecoration(hint: 'Selecteer termijn'),
          style: GoogleFonts.sora(fontSize: 14, color: GymiesColors.darkBlue),
          items: const [
            DropdownMenuItem(value: null, child: Text(S.of(context).nietIngesteld)),
            DropdownMenuItem(value: 0, child: Text(S.of(context).altijdAnnuleerbaar)),
            DropdownMenuItem(value: 12, child: Text(S.of(context).12UurVanTevoren)),
            DropdownMenuItem(value: 24, child: Text(S.of(context).24UurVanTevoren)),
            DropdownMenuItem(value: 48, child: Text(S.of(context).48Uur2Dagen)),
            DropdownMenuItem(value: 72, child: Text(S.of(context).72Uur3Dagen)),
            DropdownMenuItem(value: 168, child: Text(S.of(context).1WeekVanTevoren)),
          ],
          onChanged: (v) => setState(() => _cancellationHours = v),
        ),
        const SizedBox(height: 16),
        Text(S.of(context).restitutiepercentage,
            style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          initialValue: _cancellationRefundPercent,
          decoration: _inputDecoration(hint: S.of(context).hoeveelKrijgtDeKlantTerug),
          style: GoogleFonts.sora(fontSize: 14, color: GymiesColors.darkBlue),
          items: const [
            DropdownMenuItem(value: null, child: Text(S.of(context).nietIngesteld)),
            DropdownMenuItem(value: 100, child: Text(S.of(context).100VolledigeRestitutie)),
            DropdownMenuItem(value: 75, child: Text(S.of(context).75Restitutie)),
            DropdownMenuItem(value: 50, child: Text(S.of(context).50Restitutie)),
            DropdownMenuItem(value: 25, child: Text(S.of(context).25Restitutie)),
            DropdownMenuItem(value: 0, child: Text(S.of(context).0GeenRestitutie)),
          ],
          onChanged: (v) => setState(() => _cancellationRefundPercent = v),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cancellationExceptionsController,
          maxLines: 3,
          maxLength: 1000,
          style: GoogleFonts.sora(fontSize: 14),
          decoration: _inputDecoration(
            label: 'Uitzonderingen (optioneel)',
            hint: S.of(context).bijvBijZiekteMetBewijsIs,
          ),
        ),
        if (_cancellationHours != null && _cancellationRefundPercent != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF), // Light blue
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)), // Light blue border
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Color(0xFF3B82F6)), // Blue
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _buildCancellationPreview(),
                    style: GoogleFonts.sora(fontSize: 12, color: const Color(0xFF1E40AF)), // Dark blue
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SEO CONTENT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSeoContent() {
    final seoScore = _calculateSeoScore();
    final titleLen = _metaTitleController.text.length;
    final descLen = _metaDescriptionController.text.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SEO Score Indicator
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _seoScoreColor(seoScore).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _seoScoreColor(seoScore).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _seoScoreColor(seoScore),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        seoScore.toString(),
                        style: GoogleFonts.sora(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '/100',
                        style: GoogleFonts.sora(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.of(context).seoScore,
                      style: GoogleFonts.sora(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: GymiesColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _seoScoreLabel(seoScore),
                      style: GoogleFonts.sora(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _seoScoreColor(seoScore),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Meta Title
        Text(
          S.of(context).metaTitel,
          style: GoogleFonts.sora(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _metaTitleController,
          style: GoogleFonts.sora(fontSize: 14),
          decoration: _inputDecoration(
            label: S.of(context).metaTitel,
            hint: S.of(context).bijvPersonalTrainerAmsterdam,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          '$titleLen/60 tekens (ideaal: 50-60)',
          style: GoogleFonts.sora(
            fontSize: 12,
            color: _charCountColor(titleLen, 50, 60),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),

        // Meta Description
        Text(
          S.of(context).metaBeschrijving,
          style: GoogleFonts.sora(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _metaDescriptionController,
          maxLines: 3,
          maxLength: 160,
          style: GoogleFonts.sora(fontSize: 14),
          decoration: _inputDecoration(
            label: S.of(context).metaBeschrijving,
            hint: S.of(context).korteBeschrijvingVoorZoekmachines,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          '$descLen/160 tekens (ideaal: 120-160)',
          style: GoogleFonts.sora(
            fontSize: 12,
            color: _charCountColor(descLen, 120, 160),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),

        // Google Preview
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.of(context).googlePreview,
                style: GoogleFonts.sora(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),
              // Title (blue)
              Text(
                titleLen > 0 ? _metaTitleController.text : S.of(context).personalTrainerAmsterdam,
                style: GoogleFonts.sora(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1F2937),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              // URL (green)
              Text(
                'gymies.nl/t/${_seoSlugController.text.isNotEmpty ? _seoSlugController.text : "jouwnaam"}',
                style: GoogleFonts.sora(
                  fontSize: 13,
                  color: const Color(0xFF059669),
                ),
              ),
              const SizedBox(height: 6),
              // Description (grey)
              Text(
                descLen > 0
                    ? _metaDescriptionController.text
                    : S.of(context).korteBeschrijvingVoorZoekmachines2,
                style: GoogleFonts.sora(
                  fontSize: 13,
                  color: const Color(0xFF6B7280),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SEO HELPERS
  // ═══════════════════════════════════════════════════════════════════

  int _calculateSeoScore() {
    int score = 0;
    final titleLen = _metaTitleController.text.length;
    final descLen = _metaDescriptionController.text.length;
    final slugLen = _seoSlugController.text.length;

    // Title score (50-60 chars = 30 points)
    if (titleLen >= 50 && titleLen <= 60) {
      score += 30;
    } else if ((titleLen > 0 && titleLen < 30) || titleLen > 70) {
      score += 0;
    } else {
      score += 20; // OK but not ideal
    }

    // Description score (120-160 chars = 40 points)
    if (descLen >= 120 && descLen <= 160) {
      score += 40;
    } else if ((descLen > 0 && descLen < 80) || descLen > 200) {
      score += 0;
    } else {
      score += 25; // OK but not ideal
    }

    // Slug score (20 points if filled)
    if (slugLen > 0) {
      score += 20;
    }

    return score.clamp(0, 100);
  }

  Color _seoScoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  String _seoScoreLabel(int score) {
    if (score >= 80) return 'Uitstekend';
    if (score >= 60) return 'Goed';
    if (score >= 40) return 'Matig';
    return 'Slecht';
  }

  Color _charCountColor(int current, int min, int max) {
    if (current >= min && current <= max) return Colors.green;
    if (current > 0 && (current < min || current > max)) return Colors.red;
    return Colors.grey;
  }

  // ═══════════════════════════════════════════════════════════════════
  // VERIFICATION CONTENT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildVerificationContent() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _verifiedBadge ? const Color(0xFFEFF6FF) : Colors.grey.shade100, // Light blue
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            _verifiedBadge ? Icons.verified : Icons.verified_outlined,
            color: _verifiedBadge ? const Color(0xFF1E40AF) : Colors.grey.shade400, // Dark blue
            size: 26,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _verifiedBadge ? 'Geverifieerd' : S.of(context).nogNietGeverifieerd,
                style: GoogleFonts.sora(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: _verifiedBadge ? const Color(0xFF1E40AF) : GymiesColors.darkBlue, // Dark blue
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _verifiedBadge
                    ? S.of(context).jeProfielHeeftEenBlauwVinkje
                    : S.of(context).vraagVerificatieAanVoorEenBlauw,
                style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        if (!_verifiedBadge)
          FilledButton(
            onPressed: _saving ? null : () async {
              Haptics.light();
              setState(() => _saving = true);
              try {
                await context.read<GymiesApi>().updateProPlusSettings({'verified_badge': true});
                if (!mounted) return;
                setState(() { _verifiedBadge = true; _saving = false; });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(S.of(context).verificatieAangevraagd), backgroundColor: GymiesColors.darkBlue),
                );
              } catch (_) {
                if (mounted) setState(() => _saving = false);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(S.of(context).aanvragen, style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // UPGRADE HINT
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildUpgradeHint(String feature, String requiredTier) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: Colors.grey.shade400, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feature, style: GoogleFonts.sora(fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                Text(S.of(context).beschikbaarVanaf(requiredTier), style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade400)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: GymiesColors.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(requiredTier, style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SAVE BUTTON
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildSaveButton() {
    return GestureDetector(
      onTap: _saving ? null : _save,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: GymiesColors.primary,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: GymiesColors.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_saving)
              const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: GymiesColors.darkBlue),
              )
            else
              const Icon(Icons.save_rounded, color: GymiesColors.darkBlue, size: 22),
            const SizedBox(width: 10),
            Text(
              _saving ? S.of(context).opslaan2 : 'Etalage opslaan',
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: GymiesColors.darkBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // SHARED HELPERS
  // ═══════════════════════════════════════════════════════════════════

  InputDecoration _inputDecoration({
    String? label,
    String? hint,
    String? prefixText,
    IconData? prefix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefixText,
      prefixIcon: prefix != null ? Icon(prefix, size: 20) : null,
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: GymiesColors.primary, width: 2),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600),
      hintStyle: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade400),
    );
  }

  Widget _buildSocialField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            style: GoogleFonts.sora(fontSize: 14),
            decoration: _inputDecoration(label: label, hint: hint),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleRow({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
              const SizedBox(height: 2),
              Text(subtitle, style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: (v) {
            Haptics.selection();
            onChanged(v);
          },
          activeThumbColor: GymiesColors.primary,
        ),
      ],
    );
  }

  Widget _buildBadgeContent() {
    final alwaysVisible = kAlwaysVisibleBadgeIds;
    final toggleable = TrainerBadges.toggleableOptions();

    // Groepeer toggleable badges per categorie
    final trustIds = {'top_rated', 'favorite', 'fast_responder', 'returning_clients', 'top_booked', 'free_trial'};
    final expertiseIds = {'diploma', 'specialist', 'sessions_100', 'sessions_500', 'senioren', 'revalidatie', 'zwangerschap', 'jeugd', 'afvallen', 'krachttraining'};
    final serviceIds = {'own_location', 'duo_training', 'intro_offer', 'online_sessions', 'flexible_hours', 'same_day', 'free_cancellation'};
    // Rest = status + activity

    List<({String id, String label})> filterGroup(Set<String> ids) =>
        toggleable.where((o) => ids.contains(o.id)).toList();

    final statusBadges = toggleable.where((o) =>
        !trustIds.contains(o.id) &&
        !expertiseIds.contains(o.id) &&
        !serviceIds.contains(o.id)).toList();
    final trustBadges = filterGroup(trustIds);
    final expertiseBadges = filterGroup(expertiseIds);
    final serviceBadges = filterGroup(serviceIds);

    final activeCount = alwaysVisible.length + _visibleBadgeIds.length;

    Widget buildGroupHeader(String title, IconData icon) {
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: GymiesColors.darkBlue),
            const SizedBox(width: 6),
            Text(title, style: GoogleFonts.sora(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: GymiesColors.darkBlue,
            )),
          ],
        ),
      );
    }

    Widget buildBadgeToggle(String id, String label) {
      final isAlways = alwaysVisible.contains(id);
      final isOn = isAlways || _visibleBadgeIds.contains(id);
      final atLimit = activeCount >= kMaxProfileBadges && !isOn;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOn ? GymiesColors.primary : Colors.grey.shade300,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: GoogleFonts.sora(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isAlways ? Colors.grey.shade500 : GymiesColors.darkBlue,
              )),
            ),
            if (isAlways)
              Text('Altijd aan', style: GoogleFonts.sora(
                fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic,
              ))
            else
              Switch(
                value: isOn,
                onChanged: atLimit && !isOn ? null : (v) {
                  Haptics.selection();
                  setState(() {
                    _badgesChanged = true;
                    if (v) {
                      _visibleBadgeIds.add(id);
                    } else {
                      _visibleBadgeIds.remove(id);
                    }
                  });
                },
                activeThumbColor: GymiesColors.primary,
              ),
          ],
        ),
      );
    }

    Widget buildGroup(String title, IconData icon, List<({String id, String label})> badges) {
      if (badges.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildGroupHeader(title, icon),
          ...badges.map((b) => buildBadgeToggle(b.id, b.label)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Counter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: activeCount >= kMaxProfileBadges
                ? Colors.orange.shade50
                : GymiesColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                activeCount >= kMaxProfileBadges ? Icons.warning_amber_rounded : Icons.info_outline,
                size: 16,
                color: activeCount >= kMaxProfileBadges ? Colors.orange.shade700 : GymiesColors.darkBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$activeCount / $kMaxProfileBadges badges actief',
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: activeCount >= kMaxProfileBadges ? Colors.orange.shade700 : GymiesColors.darkBlue,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Altijd zichtbaar
        buildGroupHeader('Altijd zichtbaar', Icons.lock_outline),
        ...alwaysVisible.map((id) {
          final matches = TrainerBadges.availableOptions()
              .where((o) => o.id == id)
              .map((o) => o.label);
          final label = matches.isNotEmpty ? matches.first : id;
          return buildBadgeToggle(id, label);
        }),

        // Categorieën
        buildGroup('Status & Tier', Icons.star_outline, statusBadges),
        buildGroup('Vertrouwen & Bewijs', Icons.verified_user_outlined, trustBadges),
        buildGroup('Expertise & Specialisatie', Icons.school_outlined, expertiseBadges),
        buildGroup('Service & Beschikbaarheid', Icons.schedule_outlined, serviceBadges),

        const SizedBox(height: 8),
        Text(
          'Badges worden alleen getoond als je aan de voorwaarden voldoet.',
          style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  String _buildCancellationPreview() {
    final hours = _cancellationHours ?? 0;
    final refund = _cancellationRefundPercent ?? 100;
    final termijn = hours == 0
        ? 'op elk moment'
        : hours >= 48
            ? 'tot ${hours ~/ 24} dagen van tevoren'
            : 'tot $hours uur van tevoren';
    return 'Klanten kunnen $termijn annuleren en krijgen $refund% terug.';
  }
}
