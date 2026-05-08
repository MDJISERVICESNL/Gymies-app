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

/// SEO & Verificatie — meta tags, Google preview, SEO score en blauw vinkje.
class TrainerStorefrontSeoScreen extends StatefulWidget {
  const TrainerStorefrontSeoScreen({super.key});

  @override
  State<TrainerStorefrontSeoScreen> createState() =>
      _TrainerStorefrontSeoScreenState();
}

class _TrainerStorefrontSeoScreenState
    extends State<TrainerStorefrontSeoScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _metaTitleController = TextEditingController();
  final _metaDescController = TextEditingController();
  String _slug = '';
  bool _verified = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _metaTitleController.dispose();
    _metaDescController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
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

      _metaTitleController.text = mapStr(cms, ['seo_title', 'metaTitle', 'meta_title']);
      _metaDescController.text = mapStr(cms, ['seo_description', 'metaDescription', 'meta_description']);
      _slug = mapStr(cms, ['profile_slug', 'profileSlug', 'slug']);
      _verified = branding['verified_badge'] == true;

      setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = S.of(context).konSeogegevensNietLaden; _loading = false; });
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
        'seo_title': _metaTitleController.text.trim(),
        'seo_description': _metaDescController.text.trim(),
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
            Text(S.of(context).seoOpgeslagen, style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
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

  Future<void> _requestVerification() async {
    Haptics.light();
    setState(() => _saving = true);
    try {
      await context.read<GymiesApi>().updateProPlusSettings({'verified_badge': true});
      if (!mounted) return;
      setState(() { _verified = true; _saving = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(S.of(context).verificatieAangevraagd),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── SEO score berekening ──
  int _calcScore() {
    int score = 0;
    final tl = _metaTitleController.text.length;
    final dl = _metaDescController.text.length;
    if (tl >= 50 && tl <= 60) { score += 30; } else if (tl > 0) { score += 20; }
    if (dl >= 120 && dl <= 160) { score += 40; } else if (dl > 0) { score += 25; }
    if (_slug.isNotEmpty) score += 20;
    return score.clamp(0, 100);
  }

  Color _scoreColor(int s) {
    if (s >= 80) return const Color(0xFF10B981); // Green
    if (s >= 60) return const Color(0xFFF59E0B); // Orange
    return const Color(0xFFEF4444); // Red
  }

  String _scoreLabel(int s) {
    if (s >= 80) return 'Uitstekend';
    if (s >= 60) return 'Goed';
    if (s >= 40) return 'Matig';
    return 'Slecht';
  }

  Color _charColor(int cur, int min, int max) {
    if (cur >= min && cur <= max) return const Color(0xFF10B981); // Green
    if (cur > 0) return const Color(0xFFEF4444); // Red
    return Colors.grey;
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
    final score = _calcScore();
    final tl = _metaTitleController.text.length;
    final dl = _metaDescController.text.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'SEO & Verificatie'),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: GymiesListBody(
          loading: _loading,
          error: _error,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
            // ── SEO Score ──
            _sectionCard(
              icon: Icons.speed_outlined,
              title: S.of(context).seoScore,
              subtitle: S.of(context).hoeGoedVindbaarBenJe,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _scoreColor(score).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _scoreColor(score).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _scoreColor(score),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(score.toString(),
                                  style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                              Text('/100',
                                  style: GoogleFonts.sora(fontSize: 10, color: Colors.white70)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(S.of(context).seoScore,
                                style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                            const SizedBox(height: 4),
                            Text(_scoreLabel(score),
                                style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w700, color: _scoreColor(score))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Meta titel & beschrijving ──
            _sectionCard(
              icon: Icons.title_rounded,
              title: 'Meta tags',
              subtitle: S.of(context).titelEnBeschrijvingVoorZoekmachines,
              children: [
                Text(S.of(context).metaTitel,
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                const SizedBox(height: 8),
                TextField(
                  controller: _metaTitleController,
                  style: GoogleFonts.sora(fontSize: 14),
                  decoration: _inputDecoration(hint: S.of(context).bijvPersonalTrainerAmsterdam),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Text('$tl/60 tekens (ideaal: 50-60)',
                    style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w500, color: _charColor(tl, 50, 60))),
                const SizedBox(height: 20),

                Text(S.of(context).metaBeschrijving,
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                const SizedBox(height: 8),
                TextField(
                  controller: _metaDescController,
                  maxLines: 3,
                  maxLength: 160,
                  style: GoogleFonts.sora(fontSize: 14),
                  decoration: _inputDecoration(hint: S.of(context).korteBeschrijvingVoorZoekmachines),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Text('$dl/160 tekens (ideaal: 120-160)',
                    style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w500, color: _charColor(dl, 120, 160))),
              ],
            ),
            const SizedBox(height: 16),

            // ── Google Preview ──
            _sectionCard(
              icon: Icons.search_outlined,
              title: 'Google Preview',
              subtitle: S.of(context).zoZienMensenJouInZoekresultaten,
              children: [
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
                        tl > 0 ? _metaTitleController.text : S.of(context).personalTrainerAmsterdam,
                        style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF1F2937)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'gymies.nl/t/${_slug.isNotEmpty ? _slug : "jouwnaam"}',
                        style: GoogleFonts.sora(fontSize: 13, color: const Color(0xFF059669)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dl > 0 ? _metaDescController.text : S.of(context).korteBeschrijvingVoorZoekmachines2,
                        style: GoogleFonts.sora(fontSize: 13, color: const Color(0xFF6B7280)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Verificatie badge ──
            _sectionCard(
              icon: Icons.verified_outlined,
              title: 'Verificatie badge',
              subtitle: S.of(context).krijgEenBlauwVinkjeOpJe,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _verified ? const Color(0xFFEFF6FF) : Colors.grey.shade100, // Light blue
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _verified ? Icons.verified : Icons.verified_outlined,
                        color: _verified ? const Color(0xFF1E40AF) : Colors.grey.shade400, // Dark blue
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _verified ? 'Geverifieerd' : S.of(context).nogNietGeverifieerd,
                            style: GoogleFonts.sora(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: _verified ? const Color(0xFF1E40AF) : GymiesColors.darkBlue, // Dark blue
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _verified
                                ? S.of(context).jeProfielHeeftEenBlauwVinkje
                                : S.of(context).vraagVerificatieAanVoorEenBlauw,
                            style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    if (!_verified)
                      FilledButton(
                        onPressed: _saving ? null : _requestVerification,
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(S.of(context).aanvragen,
                            style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
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
                      _saving ? S.of(context).opslaan2 : 'SEO opslaan',
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
}
