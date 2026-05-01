import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_section_header.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final results = await Future.wait([
        api.getWidgetCode(),
        api.getQRCode(),
      ]);
      if (!mounted) return;

      final widgetData = results[0];
      final qrData = results[1];

      setState(() {
        _embedCode = (widgetData['embed_code'] as String?) ??
            (widgetData['html'] as String?) ??
            '';
        _widgetUrl = (widgetData['widget_url'] as String?) ??
            (widgetData['url'] as String?) ??
            '';
        _profileUrl = (qrData['profile_url'] as String?) ??
            (qrData['url'] as String?) ??
            '';
        _slug = (qrData['slug'] as String?) ??
            (qrData['custom_slug'] as String?) ??
            '';
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
        _error = 'Kon widget & QR data niet laden.';
        _loading = false;
      });
    }
  }

  void _copyToClipboard(String text, String label) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(title: 'Widget & QR'),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── Booking Widget ──────────────────────────────
                    const GymiesSectionHeader('Booking Widget'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
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
                    ),
                    const SizedBox(height: 24),

                    // ── QR Code ─────────────────────────────────────
                    const GymiesSectionHeader('QR Code'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
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
                                    eyeShape: QrEyeShape.roundedRect,
                                    color: GymiesColors.darkBlue,
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.roundedRect,
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
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
      ),
    );
  }
}
