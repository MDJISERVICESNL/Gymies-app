import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/storefront_cms_provider.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';
import 'widgets/trainer_media_section.dart';

/// Social Media & Gallery — social links + media gallerij. Pro tier.
class TrainerStorefrontSocialScreen extends StatefulWidget {
  const TrainerStorefrontSocialScreen({super.key});

  @override
  State<TrainerStorefrontSocialScreen> createState() =>
      _TrainerStorefrontSocialScreenState();
}

class _TrainerStorefrontSocialScreenState
    extends State<TrainerStorefrontSocialScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _instagramController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _facebookController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _instagramController.dispose();
    _tiktokController.dispose();
    _facebookController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final cmsProvider = context.read<StorefrontCmsProvider>();
      await cmsProvider.ensureLoaded();
      if (!mounted) return;
      final cms = cmsProvider.data ?? <String, dynamic>{};

      _instagramController.text = mapStr(cms, ['instagram_url', 'instagramUrl']);
      _tiktokController.text = mapStr(cms, ['tiktok_url', 'tiktokUrl', 'tiktok_username']);
      _facebookController.text = mapStr(cms, ['facebook_url', 'facebookUrl']);

      setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = S.of(context).konSocialMediaNietLaden; _loading = false; });
    }
  }

  Future<void> _save() async {
    Haptics.light();
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // ignore: use_build_context_synchronously
      final api = context.read<GymiesApi>();
      await api.updateTrainerStorefrontCms({
        'instagram_url': _instagramController.text.trim(),
        'tiktok_url': _tiktokController.text.trim(),
        'facebook_url': _facebookController.text.trim(),
      });
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      context.read<StorefrontCmsProvider>().invalidate();
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(S.of(context).socialMediaOpgeslagen, style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
          ]),
          backgroundColor: GymiesColors.darkBlue,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _inputDecoration({String? label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Social Media & Gallery'),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: GymiesListBody(
          loading: _loading,
          error: _error,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
            // ── Social Media ──
            _sectionCard(
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
            const SizedBox(height: 16),

            // ── Gallery ──
            _sectionCard(
              icon: Icons.photo_library_outlined,
              title: 'Stories & Gallery',
              subtitle: S.of(context).fotosEnVideosOpJeProfiel,
              children: [
                const TrainerMediaSection(),
              ],
            ),
            const SizedBox(height: 24),

            // ── Opslaan ──
            GestureDetector(
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
                      _saving ? S.of(context).opslaan2 : 'Social media opslaan',
                      style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
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
                    Text(title,
                        style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                    Text(subtitle,
                        style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600)),
                  ],
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
}
