import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../services/storefront_cms_provider.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_upgrade_prompt.dart';
import 'widgets/trainer_state_views.dart';

/// Widget & QR – Pro+ trainers kunnen hun booking-widget embed code
/// kopiëren en een QR-code genereren naar hun trainersprofiel.
class TrainerWidgetQrScreen extends StatefulWidget {
  const TrainerWidgetQrScreen({super.key});

  @override
  State<TrainerWidgetQrScreen> createState() => _TrainerWidgetQrScreenState();
}

class _TrainerWidgetQrScreenState extends State<TrainerWidgetQrScreen> {
  bool _loading = true;
  String? _error;

  // Widget embed data
  String _embedCode = '';
  String _widgetUrl = '';

  // QR data
  String _profileUrl = '';
  String _slug = '';

  // Widget customization
  late Color _accentColor;
  int _widgetHeight = 600;
  int _borderRadius = 12;
  bool _showPrice = true;
  bool _showReviews = true;
  bool _showAvailability = true;

  // Widget stats
  int _totalViews = 0;
  int _totalBookings = 0;
  double _conversionRate = 0.0;

  @override
  void initState() {
    super.initState();
    _accentColor = GymiesColors.primary;
    _load();
    _loadWidgetStats();
  }

  Future<void> _load() async {
    Haptics.selection();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cmsProvider = context.read<StorefrontCmsProvider>();
      await cmsProvider.ensureLoaded();
      if (!mounted) return;
      final cms = cmsProvider.data ?? <String, dynamic>{};

      final slug = (cms['custom_slug'] as String?) ??
          (cms['slug'] as String?) ??
          '';
      final profileUrl = slug.isNotEmpty
          ? 'https://gymies.nl/t/$slug'
          : '';
      final widgetUrl = slug.isNotEmpty
          ? 'https://gymies.nl/widget/$slug'
          : '';

      setState(() {
        _embedCode = slug.isNotEmpty
            ? '<iframe src="$widgetUrl" width="100%" height="600" '
              'frameborder="0" style="border:none;border-radius:12px;" '
              'loading="lazy"></iframe>'
            : '';
        _widgetUrl = widgetUrl;
        _profileUrl = profileUrl;
        _slug = slug;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // 403 = plan locked → toon lege staat (upgrade prompt al zichtbaar via tier check)
      // 500 = server fout → toon fallback met gegenereerde slug
      if (e.statusCode == 403 || e.statusCode == 500) {
        setState(() {
          _embedCode = '';
          _widgetUrl = '';
          _profileUrl = '';
          _slug = '';
          _loading = false;
          _error = null;
        });
      } else {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _embedCode = '';
        _widgetUrl = '';
        _profileUrl = '';
        _slug = '';
        _loading = false;
        _error = null;
      });
    }
  }

  void _copyToClipboard(String text, String label) {
    Haptics.light();
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label gekopieerd!'),
        backgroundColor: GymiesColors.darkBlue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _loadWidgetStats() async {
    try {
      final api = context.read<GymiesApi>();
      final stats = await api.getWidgetStats();
      if (!mounted) return;
      setState(() {
        _totalViews = stats['total_views'] as int? ?? 0;
        _totalBookings = stats['total_bookings'] as int? ?? 0;
        _conversionRate = (stats['conversion_rate'] as num? ?? 0).toDouble();
      });
    } catch (e) {
      // Graceful fallback with zeros if API not ready
      if (mounted) {
        setState(() {
          _totalViews = 0;
          _totalBookings = 0;
          _conversionRate = 0.0;
        });
      }
    }
  }

  Future<void> _saveWidgetSettings() async {
    Haptics.light();
    try {
      final api = context.read<GymiesApi>();
      await api.updateWidgetSettings({
        'accent_color': _accentColor.value.toRadixString(16),
        'widget_height': _widgetHeight,
        'border_radius': _borderRadius,
        'show_price': _showPrice,
        'show_reviews': _showReviews,
        'show_availability': _showAvailability,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Widget instellingen opgeslagen!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fout bij opslaan: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _updateEmbedCode() {
    if (_slug.isEmpty) return;
    final h = _widgetHeight.toString();
    final r = _borderRadius.toString();
    final hex = _accentColor.value.toRadixString(16).padLeft(8, '0').substring(2);
    // Widget URL met customization parameters
    final customUrl = '$_widgetUrl?color=$hex&h=$h&r=$r'
        '&price=${_showPrice ? 1 : 0}'
        '&reviews=${_showReviews ? 1 : 0}'
        '&avail=${_showAvailability ? 1 : 0}';
    setState(() {
      _widgetUrl = _slug.isNotEmpty
          ? 'https://gymies.nl/widget/$_slug'
          : '';
      _embedCode = '<iframe src="$customUrl" width="100%" height="$h" '
          'frameborder="0" style="border:none;border-radius:${r}px;" '
          'loading="lazy"></iframe>';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ent = context.watch<SubscriptionEntitlementsService>();
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isProPlus = tierLower.contains('pro_plus') ||
        tierLower.contains('proplus') ||
        tierLower == 'studio';

    if (!isProPlus) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: const GymiesAppBar(title: 'Widget & QR'),
        body: const GymiesUpgradePrompt(
          icon: Icons.widgets_outlined,
          feature: 'Booking Widget & QR',
          tier: 'Pro+',
          description: 'Pas je booking widget aan en deel je profiel met een QR-code.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Widget & QR'),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Booking Widget ──────────────────────────────
                    Padding(
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
                            child: Icon(Icons.code_rounded, size: 14, color: GymiesColors.darkBlue),
                          ),
                          const SizedBox(width: 8),
                          Text('Booking Widget', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.code_rounded,
                                    color: GymiesColors.darkBlue, size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  'Embed code',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: GymiesColors.darkBlue,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Plak deze code op je website om klanten '
                              'direct vanuit jouw site te laten boeken.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: SelectableText(
                                _embedCode.isNotEmpty
                                    ? _embedCode
                                    : 'Embed code niet beschikbaar',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: _embedCode.isNotEmpty
                                      ? GymiesColors.darkBlue
                                      : Colors.grey.shade500,
                                ),
                                maxLines: 8,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _embedCode.isNotEmpty
                                    ? () => _copyToClipboard(
                                        _embedCode, 'Embed code')
                                    : null,
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                label: const Text('Kopieer embed code'),
                              ),
                            ),
                            if (_widgetUrl.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _copyToClipboard(
                                      _widgetUrl, 'Widget URL'),
                                  icon: const Icon(Icons.link_rounded,
                                      size: 18),
                                  label: const Text('Kopieer widget URL'),
                                ),
                              ),
                            ],
                          ],
                        ),
                    ),
                    const SizedBox(height: 24),

                    // ── Widget Aanpassen ───────────────────────────
                    Padding(
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
                            child: Icon(Icons.tune_rounded, size: 14, color: GymiesColors.darkBlue),
                          ),
                          const SizedBox(width: 8),
                          Text('Widget aanpassen', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Color picker
                          Text(
                            'Accentkleur',
                              style: GoogleFonts.sora(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildColorChip(
                                    GymiesColors.primary,
                                    'Goud',
                                  ),
                                  const SizedBox(width: 10),
                                  _buildColorChip(
                                    GymiesColors.darkBlue,
                                    'Blauw',
                                  ),
                                  const SizedBox(width: 10),
                                  _buildColorChip(
                                    Colors.green,
                                    'Groen',
                                  ),
                                  const SizedBox(width: 10),
                                  _buildColorChip(
                                    Colors.red,
                                    'Rood',
                                  ),
                                  const SizedBox(width: 10),
                                  _buildColorChip(
                                    Colors.purple,
                                    'Paars',
                                  ),
                                  const SizedBox(width: 10),
                                  _buildColorChip(
                                    Colors.grey.shade800,
                                    'Donker',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Height selector
                            Text(
                              'Widget hoogte',
                              style: GoogleFonts.sora(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [400, 500, 600, 700, 800].map((h) {
                                return FilterChip(
                                  label: Text('${h}px',
                                      style: GoogleFonts.sora(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      )),
                                  selected: _widgetHeight == h,
                                  onSelected: (selected) {
                                    Haptics.light();
                                    setState(() {
                                      _widgetHeight = h;
                                      _updateEmbedCode();
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 20),

                            // Border radius
                            Text(
                              'Hoekafronding',
                              style: GoogleFonts.sora(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [0, 8, 12, 16].map((r) {
                                return FilterChip(
                                  label: Text('${r}px',
                                      style: GoogleFonts.sora(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      )),
                                  selected: _borderRadius == r,
                                  onSelected: (selected) {
                                    Haptics.light();
                                    setState(() {
                                      _borderRadius = r;
                                      _updateEmbedCode();
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 20),

                            // Toggles
                            Text(
                              'Zichtbaarheid elementen',
                              style: GoogleFonts.sora(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                            const SizedBox(height: 12),
                            CheckboxListTile(
                              title: Text(
                                'Toon prijs',
                                style: GoogleFonts.sora(fontSize: 13),
                              ),
                              value: _showPrice,
                              onChanged: (val) {
                                Haptics.light();
                                setState(() {
                                  _showPrice = val ?? true;
                                });
                                _updateEmbedCode();
                              },
                              contentPadding: EdgeInsets.zero,
                            ),
                            CheckboxListTile(
                              title: Text(
                                'Toon reviews',
                                style: GoogleFonts.sora(fontSize: 13),
                              ),
                              value: _showReviews,
                              onChanged: (val) {
                                Haptics.light();
                                setState(() {
                                  _showReviews = val ?? true;
                                });
                                _updateEmbedCode();
                              },
                              contentPadding: EdgeInsets.zero,
                            ),
                            CheckboxListTile(
                              title: Text(
                                'Toon beschikbaarheid',
                                style: GoogleFonts.sora(fontSize: 13),
                              ),
                              value: _showAvailability,
                              onChanged: (val) {
                                Haptics.light();
                                setState(() {
                                  _showAvailability = val ?? true;
                                });
                                _updateEmbedCode();
                              },
                              contentPadding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _saveWidgetSettings,
                                icon: const Icon(Icons.save_rounded, size: 18),
                                label: Text('Instellingen opslaan',
                                    style: GoogleFonts.sora()),
                              ),
                            ),
                          ],
                        ),
                    ),
                    const SizedBox(height: 24),

                    // ── Preview ────────────────────────────────────
                    Padding(
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
                            child: Icon(Icons.preview_outlined, size: 14, color: GymiesColors.darkBlue),
                          ),
                          const SizedBox(width: 8),
                          Text('Voorbeeld', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Widget preview',
                            style: GoogleFonts.sora(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            height: 200,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _accentColor,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(
                                _borderRadius.toDouble(),
                              ),
                              color: Colors.grey.shade50,
                            ),
                            child: Center(
                              child: Builder(
                                builder: (ctx) {
                                  final user = ctx.read<AuthService>().user;
                                  final name = user?['display_name'] ?? user?['name'] ?? 'jouw naam';
                                  return Text(
                                    'Boek nu bij $name',
                                    style: GoogleFonts.sora(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: _accentColor,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── QR Code ─────────────────────────────────────
                    Padding(
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
                            child: Icon(Icons.qr_code_rounded, size: 14, color: GymiesColors.darkBlue),
                          ),
                          const SizedBox(width: 8),
                          Text('QR Code', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Deel deze QR-code op flyers, visitekaartjes '
                            'of in je sportschool.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            if (_profileUrl.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: QrImageView(
                                  data: _profileUrl,
                                  version: QrVersions.auto,
                                  size: 200,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: GymiesColors.darkBlue,
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: GymiesColors.darkBlue,
                                  ),
                                  backgroundColor: Colors.white,
                                ),
                              )
                            else
                              Container(
                                width: 200,
                                height: 200,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: Text(
                                    'QR code niet beschikbaar',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            if (_profileUrl.isNotEmpty) ...[
                              Text(
                                _profileUrl,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () => _copyToClipboard(
                                      _profileUrl, 'Profiel URL'),
                                  icon: const Icon(Icons.copy_rounded,
                                      size: 18),
                                  label: const Text('Kopieer profiel URL'),
                                ),
                              ),
                            ],
                          ],
                        ),
                    ),
                    const SizedBox(height: 24),

                    // ── Widget Statistieken ────────────────────────
                    Padding(
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
                            child: Icon(Icons.analytics_outlined, size: 14, color: GymiesColors.darkBlue),
                          ),
                          const SizedBox(width: 8),
                          Text('Widget statistieken', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatCard(
                            label: 'Totale weergaven',
                            value: _totalViews.toString(),
                            icon: Icons.visibility_outlined,
                          ),
                          _buildStatCard(
                            label: 'Boekingen via widget',
                            value: _totalBookings.toString(),
                            icon: Icons.calendar_today_outlined,
                          ),
                          _buildStatCard(
                            label: 'Conversie rate',
                            value: '${_conversionRate.toStringAsFixed(1)}%',
                            icon: Icons.trending_up_rounded,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Share Options ───────────────────────────────
                    Padding(
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
                            child: Icon(Icons.share_outlined, size: 14, color: GymiesColors.darkBlue),
                          ),
                          const SizedBox(width: 8),
                          Text('Delen', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            child: OutlinedButton.icon(
                                onPressed: () => _copyToClipboard(
                                  _widgetUrl,
                                  'Widget link',
                                ),
                                icon:
                                    const Icon(Icons.copy_rounded, size: 18),
                                label: Text('Kopieer link',
                                    style: GoogleFonts.sora()),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              child: OutlinedButton.icon(
                                onPressed: () => _copyToClipboard(
                                  _embedCode,
                                  'Embed code',
                                ),
                                icon:
                                    const Icon(Icons.copy_rounded, size: 18),
                                label: Text('Kopieer embed',
                                    style: GoogleFonts.sora()),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              child: OutlinedButton.icon(
                                onPressed: _profileUrl.isNotEmpty
                                    ? () {
                                        Haptics.light();
                                        // QR code download placeholder
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'QR-code download komende versie',
                                            ),
                                            duration:
                                                Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    : null,
                                icon: const Icon(Icons.download_rounded,
                                    size: 18),
                                label: Text('Download QR',
                                    style: GoogleFonts.sora()),
                              ),
                            ),
                          ],
                        ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
      ),
    );
  }

  Widget _buildColorChip(Color color, String label) {
    final isSelected = _accentColor == color;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        setState(() {
          _accentColor = color;
        });
        _updateEmbedCode();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.sora(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: GymiesColors.darkBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
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
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: GymiesColors.darkBlue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.sora(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
