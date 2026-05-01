import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/storefront_cms_provider.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';


/// Storefront Branding Screen — Pro+ tier only
/// Handles logo, banner, brand color, profile URL, and intro video
class TrainerStorefrontBrandingScreen extends StatefulWidget {
  const TrainerStorefrontBrandingScreen({super.key});

  @override
  State<TrainerStorefrontBrandingScreen> createState() =>
      _TrainerStorefrontBrandingScreenState();
}

class _TrainerStorefrontBrandingScreenState
    extends State<TrainerStorefrontBrandingScreen> {
  final _profileUrlController = TextEditingController();
  final _videoUrlController = TextEditingController();
  final _profileUrlRegex = RegExp(r'^[a-z0-9\-]*$');

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  // Current backend values
  String _brandColor = '#FEBE23';
  String? _logoUrl;
  String? _bannerUrl;
  String? _introVideoUrl;

  // Locally selected files (not yet uploaded)
  String? _newLogoPath;
  String? _newBannerPath;

  static const _presetColors = [
    '#FEBE23', '#FF6B6B', '#4ECDC4', '#45B7D1', '#96CEB4', '#DDA0DD',
    '#98D8C8', '#F7DC6F', '#BB8FCE', '#85C1E9', '#F0B27A', '#1E3A5F',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _profileUrlController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    Haptics.selection();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final cmsProvider = context.read<StorefrontCmsProvider>();
      final api = context.read<GymiesApi>();

      // Load CMS via shared provider + Pro+ settings in parallel
      final results = await Future.wait([
        cmsProvider.ensureLoaded(),
        api.getProPlusSettings().catchError((_) => {}),
      ]);

      final cmsData = cmsProvider.data;
      final proPlusData = results[1] as Map<String, dynamic>?;

      if (!mounted) return;

      setState(() {
        // Profile slug from CMS (try multiple keys)
        _profileUrlController.text =
            (cmsData?['profile_slug'] ?? cmsData?['profileSlug'] ?? cmsData?['slug'] ?? '') as String;

        // Branding settings from Pro+ tier
        if (proPlusData != null) {
          _brandColor = (proPlusData['brand_color'] as String?) ?? '#FEBE23';
          _logoUrl = proPlusData['brand_logo_url'] as String?;
          _bannerUrl = proPlusData['brand_banner_url'] as String?;
          _introVideoUrl = proPlusData['intro_video_url'] as String?;
        }

        _videoUrlController.text = _introVideoUrl ?? '';
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load branding settings';
        _isLoading = false;
      });
    }
  }

  Color _parseHex(String hex) {
    final cleanHex = hex.replaceFirst('#', '');
    return Color(int.parse('FF$cleanHex', radix: 16));
  }

  Future<void> _pickLogoImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        imageQuality: 85,
      );
      if (file != null) {
        setState(() => _newLogoPath = file.path);
        Haptics.selection();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<void> _pickBannerImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (file != null) {
        setState(() => _newBannerPath = file.path);
        Haptics.selection();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<void> _saveBranding() async {
    Haptics.light();

    // Validate profile URL
    final profileSlug = _profileUrlController.text.trim().toLowerCase();
    if (profileSlug.isNotEmpty && !_profileUrlRegex.hasMatch(profileSlug)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile URL: use only lowercase letters, numbers, and hyphens'),
          ),
        );
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      final api = context.read<GymiesApi>();

      // Upload new logo if selected
      if (_newLogoPath != null) {
        final res = await api.uploadProPlusLogo(_newLogoPath!);
        if (!mounted) return;
        _logoUrl = res['url'] as String? ?? _logoUrl;
        _newLogoPath = null;
      }

      // Upload new banner if selected
      if (_newBannerPath != null) {
        final res = await api.uploadProPlusBanner(_newBannerPath!);
        if (!mounted) return;
        _bannerUrl = res['url'] as String? ?? _bannerUrl;
        _newBannerPath = null;
      }

      // Save profile slug to CMS
      if (profileSlug.isNotEmpty) {
        await api.updateTrainerStorefrontCms({
          'profile_slug': profileSlug,
        });
        context.read<StorefrontCmsProvider>().invalidate();
      }

      // Save branding settings
      final videoUrl = _videoUrlController.text.trim();
      await api.updateProPlusSettings({
        'brand_color': _brandColor,
        'intro_video_url': videoUrl.isEmpty ? null : videoUrl,
        'custom_slug': profileSlug.isEmpty ? null : profileSlug,
      });

      if (!mounted) return;

      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              const Text('Branding opgeslagen'),
            ],
          ),
          backgroundColor: GymiesColors.darkBlue,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.message}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() => _isSaving = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save branding'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Branding'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _error!,
                        style: GoogleFonts.sora(
                          fontSize: 16,
                          color: Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: Text(
                          'Retry',
                          style: GoogleFonts.sora(),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: [
                    // Section 1: Profile URL
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Profiel-URL',
                            style: GoogleFonts.sora(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _profileUrlController,
                            style: GoogleFonts.sora(),
                            inputFormatters: [
                              TextInputFormatter.withFunction(
                                (oldValue, newValue) {
                                  final filtered = newValue.text.replaceAll(RegExp(r'[^a-z0-9\-]'), '');
                                  return newValue.copyWith(text: filtered);
                                },
                              ),
                            ],
                            decoration: InputDecoration(
                              hintText: 'jouwnaam',
                              prefixText: 'gymies.nl/t/',
                              hintStyle: GoogleFonts.sora(
                                color: Colors.grey.shade400,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 2: Brand Color
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Brand kleur',
                            style: GoogleFonts.sora(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: _presetColors.map((color) {
                              final isSelected = _brandColor == color;
                              return GestureDetector(
                                onTap: () {
                                  setState(() => _brandColor = color);
                                  Haptics.selection();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _parseHex(color),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? GymiesColors.darkBlue
                                          : Colors.grey.shade300,
                                      width: isSelected ? 3 : 1,
                                    ),
                                    boxShadow: isSelected
                                        ? [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.1),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: isSelected
                                      ? Icon(
                                          Icons.check,
                                          color: _parseHex(color)
                                                      .computeLuminance() >
                                                  0.5
                                              ? Colors.black
                                              : Colors.white,
                                          size: 20,
                                        )
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 3: Logo & Banner Uploads
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Logo & Banner',
                            style: GoogleFonts.sora(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              // Logo Upload
                              Expanded(
                                child: GestureDetector(
                                  onTap: _pickLogoImage,
                                  child: Container(
                                    height: 120,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                        width: 2,
                                        strokeAlign: BorderSide.strokeAlignOutside,
                                      ),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Dashed border effect
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: CustomPaint(
                                            painter: _DashedBorderPainter(),
                                            child: Container(),
                                          ),
                                        ),
                                        // Content
                                        if (_newLogoPath != null)
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Image.file(
                                              File(_newLogoPath!),
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        else if (_logoUrl != null)
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: CachedNetworkImage(
                                              imageUrl: _logoUrl!,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        else
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.camera_alt_outlined,
                                                size: 32,
                                                color: Colors.grey.shade400,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Logo',
                                                style: GoogleFonts.sora(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade400,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Banner Upload
                              Expanded(
                                child: GestureDetector(
                                  onTap: _pickBannerImage,
                                  child: Container(
                                    height: 120,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                        width: 2,
                                        strokeAlign: BorderSide.strokeAlignOutside,
                                      ),
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // Dashed border effect
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: CustomPaint(
                                            painter: _DashedBorderPainter(),
                                            child: Container(),
                                          ),
                                        ),
                                        // Content
                                        if (_newBannerPath != null)
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Image.file(
                                              File(_newBannerPath!),
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        else if (_bannerUrl != null)
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: CachedNetworkImage(
                                              imageUrl: _bannerUrl!,
                                              fit: BoxFit.cover,
                                            ),
                                          )
                                        else
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.camera_alt_outlined,
                                                size: 32,
                                                color: Colors.grey.shade400,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Banner',
                                                style: GoogleFonts.sora(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade400,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 4: Intro Video
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Intro Video',
                            style: GoogleFonts.sora(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _videoUrlController,
                            style: GoogleFonts.sora(),
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              hintText: 'https://youtube.com/watch?v=...',
                              prefixIcon: Icon(
                                Icons.link_rounded,
                                color: Colors.grey.shade400,
                              ),
                              hintStyle: GoogleFonts.sora(
                                color: Colors.grey.shade400,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveBranding,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSaving
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    GymiesColors.darkBlue,
                                  ),
                                ),
                              )
                            : Text(
                                'Opslaan',
                                style: GoogleFonts.sora(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: GymiesColors.darkBlue,
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

/// Custom painter for dashed border effect
class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashWidth = 5.0;
    const dashSpace = 5.0;
    double distance = 0.0;

    // Top line
    while (distance < size.width) {
      canvas.drawLine(
        Offset(distance, 0),
        Offset(distance + dashWidth, 0),
        paint,
      );
      distance += dashWidth + dashSpace;
    }

    // Right line
    distance = 0.0;
    while (distance < size.height) {
      canvas.drawLine(
        Offset(size.width, distance),
        Offset(size.width, distance + dashWidth),
        paint,
      );
      distance += dashWidth + dashSpace;
    }

    // Bottom line
    distance = 0.0;
    while (distance < size.width) {
      canvas.drawLine(
        Offset(size.width - distance, size.height),
        Offset(size.width - distance - dashWidth, size.height),
        paint,
      );
      distance += dashWidth + dashSpace;
    }

    // Left line
    distance = 0.0;
    while (distance < size.height) {
      canvas.drawLine(
        Offset(0, size.height - distance),
        Offset(0, size.height - distance - dashWidth),
        paint,
      );
      distance += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
