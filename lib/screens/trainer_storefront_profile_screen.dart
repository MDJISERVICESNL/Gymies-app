import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/storefront_cms_provider.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

/// Sub-screen "Profiel & Bio" voor het trainers-etalage (Mijn Etalage hub).
/// Beheerd: bio-tekst en specialisatietags (bijv. "Gewichtheffen", "HIIT").
///
/// Patroon:
/// - Load via api.getTrainerStorefrontCms() (bio, specializations_tags)
/// - Save via api.updateTrainerStorefrontCms({bio, specializations_tags})
/// - Fallback keys: bio → about → intro; specializations_tags → specializationsTags
class TrainerStorefrontProfileScreen extends StatefulWidget {
  const TrainerStorefrontProfileScreen({super.key});

  @override
  State<TrainerStorefrontProfileScreen> createState() =>
      _TrainerStorefrontProfileScreenState();
}

class _TrainerStorefrontProfileScreenState
    extends State<TrainerStorefrontProfileScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _bioController = TextEditingController();
  List<String> _specTags = [];
  final _newTagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cmsProvider = context.read<StorefrontCmsProvider>();
      await cmsProvider.ensureLoaded();
      if (!mounted) return;
      final cms = cmsProvider.data ?? <String, dynamic>{};

      // Bio: primaire sleutel 'bio', fallback 'about', dan 'intro'
      _bioController.text = mapStr(cms, ['bio', 'about', 'intro']);

      // Specialisaties: primaire sleutel 'specializations_tags', fallback 'specializationsTags'
      final rawTags = cms['specializations_tags'] ?? cms['specializationsTags'];
      _specTags = rawTags is List
          ? rawTags
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList()
          : [];

      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiException
              ? 'API fout (${e.statusCode}): ${e.message}'
              : 'Kon profiel niet laden';
        });
      }
    }
  }

  Future<void> _save() async {
    Haptics.light();
    setState(() => _saving = true);

    try {
      final api = context.read<GymiesApi>();

      // Validatie: specialisaties max 20
      if (_specTags.length > 20) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Maximaal 20 specialisaties',
              style: GoogleFonts.sora(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() => _saving = false);
        return;
      }

      await api.updateTrainerStorefrontCms({
        'bio': _bioController.text.trim(),
        'specializations_tags': _specTags,
      });
      context.read<StorefrontCmsProvider>().invalidate();

      if (!mounted) return;

      Haptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                'Profiel opgeslagen',
                style: GoogleFonts.sora(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          backgroundColor: GymiesColors.darkBlue,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );

      setState(() => _saving = false);
    } catch (e) {
      if (!mounted) return;

      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException
                ? 'Fout bij opslaan (${e.statusCode})'
                : 'Kon profiel niet opslaan',
            style: GoogleFonts.sora(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );

      setState(() => _saving = false);
    }
  }

  void _addTag() {
    final tag = _newTagController.text.trim();

    if (tag.isEmpty) {
      Haptics.light();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Voer een specialisatie in',
            style: GoogleFonts.sora(fontSize: 13),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    if (_specTags.contains(tag)) {
      Haptics.light();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deze specialisatie bestaat al',
            style: GoogleFonts.sora(fontSize: 13),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    if (_specTags.length >= 20) {
      Haptics.light();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maximaal 20 specialisaties bereikt',
            style: GoogleFonts.sora(fontSize: 13),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    Haptics.light();
    setState(() {
      _specTags.add(tag);
      _newTagController.clear();
    });
  }

  void _removeTag(String tag) {
    Haptics.light();
    setState(() => _specTags.remove(tag));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Profiel & Bio'),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Section Header: Bio ──
            _buildSectionHeader(
              icon: Icons.person_outline,
              title: 'Bio',
              subtitle: 'Vertel clients over jezelf',
            ),
            const SizedBox(height: 12),

            // ── Bio TextEdit ──
            Container(
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
                  TextField(
                    controller: _bioController,
                    maxLines: 5,
                    maxLength: 5000,
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Bijv. "Ik ben gespecialiseerd in..."',
                      hintStyle: GoogleFonts.sora(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                      counterStyle: GoogleFonts.sora(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Section Header: Specialisaties ──
            _buildSectionHeader(
              icon: Icons.local_offer_outlined,
              title: 'Specialisaties',
              subtitle: 'Toevoegen max 20 tags',
            ),
            const SizedBox(height: 12),

            // ── Add Tag Row ──
            Container(
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
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newTagController,
                      style: GoogleFonts.sora(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Bijv. "Gewichtheffen"',
                        hintStyle: GoogleFonts.sora(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onSubmitted: (_) => _addTag(),
                    ),
                  ),
                  GestureDetector(
                    onTap: _addTag,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: GymiesColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 20,
                        color: GymiesColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ── Tags Display ──
            if (_specTags.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _specTags
                    .map(
                      (tag) => Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: GymiesColors.primary.withValues(alpha: 0.3),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
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
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _removeTag(tag),
                              child: Icon(
                                Icons.clear,
                                size: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Geen specialisaties toegevoegd',
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // ── Save Button ──
            GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: _saving
                      ? GymiesColors.primary.withValues(alpha: 0.6)
                      : GymiesColors.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              GymiesColors.darkBlue.withValues(alpha: 0.5),
                            ),
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.save_rounded,
                              size: 20,
                              color: GymiesColors.darkBlue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Profiel opslaan',
                              style: GoogleFonts.sora(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Bouwt een sectie-header met pictogram, titel en subtitel.
  /// Patroon gebruikt in trainer storefront editor.
  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: GymiesColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 22,
            color: GymiesColors.primary,
          ),
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
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.sora(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
