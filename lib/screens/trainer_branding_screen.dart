import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:google_fonts/google_fonts.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_section_header.dart';
import 'widgets/trainer_state_views.dart';

/// Mijn Branding – Pro+ trainers kunnen hun profiel personaliseren:
/// custom slug, brand kleur, logo, banner.
class TrainerBrandingScreen extends StatefulWidget {
  const TrainerBrandingScreen({super.key});

  @override
  State<TrainerBrandingScreen> createState() => _TrainerBrandingScreenState();
}

class _TrainerBrandingScreenState extends State<TrainerBrandingScreen> {
  final _slugController = TextEditingController();
  final _videoController = TextEditingController();
  final _hexColorController = TextEditingController();
  final _slugRegex = RegExp(r'^[a-z0-9][a-z0-9\-]*[a-z0-9]$');
  final _urlRegex = RegExp(
    r'^https?://(www\.)?(youtube\.com|youtu\.be|vimeo\.com)/.+',
    caseSensitive: false,
  );
  final _hexRegex = RegExp(r'^[0-9A-Fa-f]{0,6}$');

  bool _loading = true;
  bool _saving = false;
  String? _error;

  // Huidige waarden van de backend
  String _brandColor = '#C9A84C'; // Gymies gold default
  String? _logoUrl;
  String? _bannerUrl;
  bool _verifiedBadge = false;

  // Lokaal geselecteerde bestanden (nog niet geüpload)
  String? _newLogoPath;
  String? _newBannerPath;

  static const _presetColors = [
    '#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4',
    '#FFEAA7', '#DDA0DD', '#98D8C8', '#F7DC6F',
    '#BB8FCE', '#85C1E9', '#F0B27A', '#000000',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _slugController.dispose();
    _videoController.dispose();
    _hexColorController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    Haptics.selection();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final data = await api.getProPlusSettings();
      if (!mounted) return;
      setState(() {
        _slugController.text = (data['custom_slug'] as String?) ?? '';
        _brandColor = (data['brand_color'] as String?) ?? '#C9A84C';
        _logoUrl = data['brand_logo_url'] as String?;
        _bannerUrl = data['brand_banner_url'] as String?;
        _videoController.text = (data['intro_video_url'] as String?) ?? '';
        _verifiedBadge = data['verified_badge'] == true;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon branding-instellingen niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    Haptics.light();
    final slug = _slugController.text.trim().toLowerCase();
    if (slug.isNotEmpty && slug.length >= 3 && !_slugRegex.hasMatch(slug)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ongeldige slug. Gebruik kleine letters, cijfers en streepjes.')),
      );
      return;
    }

    final videoUrl = _videoController.text.trim();
    if (videoUrl.isNotEmpty && !_urlRegex.hasMatch(videoUrl)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voer een geldige YouTube of Vimeo URL in.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final api = context.read<GymiesApi>();

      // Upload nieuwe bestanden als die geselecteerd zijn
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

      // Sla instellingen op
      await api.updateProPlusSettings({
        if (slug.isNotEmpty) 'custom_slug': slug,
        'brand_color': _brandColor,
        'intro_video_url': videoUrl.isEmpty ? null : videoUrl,
      });
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branding opgeslagen!')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opslaan mislukt. Probeer het opnieuw.')),
      );
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
      if (isLogo) {
        _newLogoPath = picked.path;
      } else {
        _newBannerPath = picked.path;
      }
    });
  }

  Future<void> _requestVerification() async {
    Haptics.light();
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await context.read<GymiesApi>().updateProPlusSettings({
        'verified_badge': true,
      });
      if (!mounted) return;
      setState(() {
        _verifiedBadge = true;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verificatie-aanvraag verstuurd! Gymies beoordeelt je profiel.'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verificatie aanvragen mislukt. Probeer het later opnieuw.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Color _parseHex(String hex) {
    final clean = hex.replaceFirst('#', '');
    if (clean.length != 6) return GymiesColors.primary;
    return Color(int.parse('FF$clean', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Mijn Branding'),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Custom Slug ────────────────────────────────��─
                    _sectionHeader(Icons.link_rounded, 'Profiel URL'),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _slugController,
                              decoration: const InputDecoration(
                                labelText: 'Jouw slug',
                                hintText: 'bijv. john-fitness',
                                prefixText: 'gymies.nl/t/',
                                border: OutlineInputBorder(),
                              ),
                              textInputAction: TextInputAction.done,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Min. 3 tekens. Kleine letters, cijfers en streepjes.',
                              style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // ── Brand Kleur ──────────────────────────────────
                    _sectionHeader(Icons.palette_outlined, 'Brand kleur'),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                  decoration: BoxDecoration(
                                    color: _parseHex(_brandColor),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(_brandColor.toUpperCase(),
                                    style: GoogleFonts.sora(fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _presetColors.map((hex) {
                                final selected = _brandColor.toLowerCase() == hex.toLowerCase();
                                return GestureDetector(
                                  onTap: () {
                                    Haptics.selection();
                                    setState(() {
                                      _brandColor = hex;
                                      _hexColorController.clear();
                                    });
                                  },
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: _parseHex(hex),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: selected ? GymiesColors.darkBlue : Colors.grey.shade300,
                                        width: selected ? 3 : 1,
                                      ),
                                    ),
                                    child: selected
                                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                                        : null,
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Of voer je eigen kleur in:',
                              style: GoogleFonts.sora(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _hexColorController,
                                    decoration: const InputDecoration(
                                      prefixText: '#',
                                      hintText: 'e.g. FF6B6B',
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                    ),
                                    textCapitalization: TextCapitalization.characters,
                                    maxLength: 6,
                                    onChanged: (value) {
                                      if (_hexRegex.hasMatch(value)) {
                                        if (value.length == 6) {
                                          setState(() {
                                            _brandColor = '#${value.toUpperCase()}';
                                          });
                                        }
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: _brandColor.isNotEmpty
                                        ? _parseHex(_brandColor)
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // ── Logo ─────────────────────────────────────────
                    _sectionHeader(Icons.camera_alt_outlined, 'Logo'),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                        children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _newLogoPath != null
                                  ? Image.file(File(_newLogoPath!),
                                      width: 120, height: 120, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _imagePlaceholder(120, Icons.image))
                                  : _logoUrl != null && _logoUrl!.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: _logoUrl!,
                                          width: 120,
                                          height: 120,
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) =>
                                              _imagePlaceholder(120, Icons.image),
                                          errorWidget: (_, __, ___) =>
                                              _imagePlaceholder(120, Icons.broken_image),
                                        )
                                      : _imagePlaceholder(120, Icons.add_photo_alternate),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => _pickImage(isLogo: true),
                              icon: const Icon(Icons.upload_rounded),
                              label: Text(_logoUrl != null ? 'Wijzig logo' : 'Upload logo'),
                            ),
                            const SizedBox(height: 4),
                            Text('Max 10MB · JPG, PNG, GIF, WebP',
                                style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // ── Banner ────────────────────────────────────────
                    _sectionHeader(Icons.panorama_outlined, 'Banner'),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                        children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _newBannerPath != null
                                  ? Image.file(File(_newBannerPath!),
                                      width: double.infinity,
                                      height: 160,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _bannerPlaceholder())
                                  : _bannerUrl != null && _bannerUrl!.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: _bannerUrl!,
                                          width: double.infinity,
                                          height: 160,
                                          fit: BoxFit.cover,
                                          placeholder: (_, __) => _bannerPlaceholder(),
                                          errorWidget: (_, __, ___) => _bannerPlaceholder(),
                                        )
                                      : _bannerPlaceholder(),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => _pickImage(isLogo: false),
                              icon: const Icon(Icons.upload_rounded),
                              label: Text(_bannerUrl != null ? 'Wijzig banner' : 'Upload banner'),
                            ),
                            const SizedBox(height: 4),
                            Text('Max 20MB · JPG, PNG, GIF, WebP',
                                style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // ── Intro Video ─────────────────────────────────
                    _sectionHeader(Icons.videocam_outlined, 'Intro video'),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.videocam_outlined,
                                    color: GymiesColors.darkBlue, size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  'YouTube of Vimeo URL',
                                  style: GoogleFonts.sora(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _videoController,
                              decoration: const InputDecoration(
                                hintText: 'https://youtube.com/watch?v=...',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.link_rounded),
                              ),
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.done,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Toon een introductievideo op je profiel. Ondersteunt YouTube en Vimeo.',
                              style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),

                    // ── Geverifieerd Badge ───────────────────────────
                    _sectionHeader(Icons.verified_outlined, 'Geverifieerd badge'),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: _verifiedBadge
                                    ? Colors.blue.shade50
                                    : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                _verifiedBadge
                                    ? Icons.verified
                                    : Icons.verified_outlined,
                                color: _verifiedBadge
                                    ? Colors.blue.shade800
                                    : Colors.grey.shade400,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _verifiedBadge
                                        ? 'Geverifieerd'
                                        : 'Nog niet geverifieerd',
                                    style: GoogleFonts.sora(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: _verifiedBadge
                                          ? Colors.blue.shade800
                                          : GymiesColors.darkBlue,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _verifiedBadge
                                        ? 'Je profiel heeft een blauw verificatievinkje.'
                                        : 'Vraag verificatie aan om een blauw vinkje op je profiel te krijgen. Gymies beoordeelt je aanvraag.',
                                    style: GoogleFonts.sora(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!_verifiedBadge)
                              FilledButton(
                                onPressed: _saving ? null : _requestVerification,
                                style: FilledButton.styleFrom(
                                  backgroundColor: GymiesColors.primary,
                                  foregroundColor: GymiesColors.darkBlue,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                ),
                                child: Text('Aanvragen',
                                    style: GoogleFonts.sora(
                                        fontSize: 13, fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 32),

                    // ── Opslaan ──────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text('Opslaan', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
      ),
    );
  }

  Widget _imagePlaceholder(double size, IconData icon) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 40, color: Colors.grey.shade400),
      );

  Widget _sectionHeader(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
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
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.sora(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: GymiesColors.darkBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bannerPlaceholder() => Container(
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.panorama_outlined, size: 48, color: Colors.grey.shade400),
      );
}
