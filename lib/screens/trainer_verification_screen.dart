import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';

/// Trainer ID-verificatie scherm: documenten uploaden voor verificatie.
///
/// Ondersteunde categorieën:
/// - KvK-uittreksel
/// - ID-document (paspoort/rijbewijs)
/// - Certificering/diploma
/// - VOG (Verklaring Omtrent Gedrag)
class TrainerVerificationScreen extends StatefulWidget {
  const TrainerVerificationScreen({super.key});

  @override
  State<TrainerVerificationScreen> createState() =>
      _TrainerVerificationScreenState();
}

class _TrainerVerificationScreenState extends State<TrainerVerificationScreen> {
  bool _loading = true;
  Map<String, dynamic> _status = {};
  Map<String, bool> _uploading = {};

  static const _categories = [
    _DocCategory(
      key: 'kvk_extract',
      title: 'KvK-uittreksel',
      subtitle: 'Upload je recente KvK-uittreksel (max 6 maanden oud)',
      icon: Icons.business_center_rounded,
      color: Colors.blue,
    ),
    _DocCategory(
      key: 'id_document',
      title: 'ID-verificatie',
      subtitle: 'Paspoort, rijbewijs of ID-kaart',
      icon: Icons.badge_rounded,
      color: Colors.teal,
    ),
    _DocCategory(
      key: 'certification',
      title: 'Certificering / Diploma',
      subtitle: 'Upload je fitness-certificering of diploma',
      icon: Icons.school_rounded,
      color: Colors.purple,
    ),
    _DocCategory(
      key: 'vog',
      title: 'VOG',
      subtitle: 'Verklaring Omtrent het Gedrag',
      icon: Icons.verified_user_rounded,
      color: Colors.green,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    try {
      final api = context.read<GymiesApi>();
      final onboarding = await api.getOnboardingStatus();
      if (!mounted) return;
      setState(() {
        _status = onboarding;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _isUploaded(String category) {
    final docs = _status['documents'] as Map<String, dynamic>? ?? {};
    final doc = docs[category];
    if (doc == null) return false;
    if (doc is Map) {
      return (doc['uploaded'] == true) || (doc['file_path'] != null);
    }
    if (doc is bool) return doc;
    return false;
  }

  String? _docStatus(String category) {
    final docs = _status['documents'] as Map<String, dynamic>? ?? {};
    final doc = docs[category];
    if (doc is Map) {
      if (doc['rejected_at'] != null) return 'rejected';
      if (doc['verified_at'] != null || doc['approved'] == true) return 'verified';
      if (doc['uploaded'] == true || doc['file_path'] != null) return 'pending';
    }
    if (doc == true) return 'pending';
    return null;
  }

  Future<void> _upload(String category) async {
    if (_uploading[category] == true) return;

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) return;

    setState(() => _uploading[category] = true);
    try {
      final api = context.read<GymiesApi>();
      await api.uploadOnboardingDocument(
        category: category,
        fileBytes: file.bytes!,
        fileName: file.name.isNotEmpty ? file.name : 'document.pdf',
      );
      Haptics.success();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Document geüpload! We controleren het zo snel mogelijk.'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload mislukt: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading[category] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: GymiesColors.darkBlue,
        foregroundColor: Colors.white,
        title: Text(
          'Verificatie',
          style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: GymiesColors.primary))
          : RefreshIndicator(
              color: GymiesColors.primary,
              onRefresh: _loadStatus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  ..._categories.map(_buildDocCard),
                  const SizedBox(height: 24),
                  _buildInfoBox(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    // Bereken verificatie voortgang
    int uploaded = 0;
    for (final cat in _categories) {
      if (_isUploaded(cat.key)) uploaded++;
    }
    final progress = uploaded / _categories.length;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [GymiesColors.darkBlue, GymiesColors.darkBlue.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: GymiesColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.verified_rounded, color: GymiesColors.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verificatie status',
                      style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$uploaded van ${_categories.length} documenten',
                      style: GoogleFonts.sora(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor: const AlwaysStoppedAnimation(GymiesColors.primary),
              minHeight: 8,
            ),
          ),
          if (uploaded == _categories.length) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: Colors.greenAccent),
                  const SizedBox(width: 6),
                  Text(
                    'Alle documenten ingediend!',
                    style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.greenAccent),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocCard(_DocCategory cat) {
    final uploaded = _isUploaded(cat.key);
    final status = _docStatus(cat.key);
    final isUploading = _uploading[cat.key] == true;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case 'verified':
        statusColor = Colors.green.shade600;
        statusLabel = 'Geverifieerd';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'rejected':
        statusColor = Colors.red.shade600;
        statusLabel = 'Afgekeurd';
        statusIcon = Icons.cancel_rounded;
        break;
      case 'pending':
        statusColor = Colors.orange.shade600;
        statusLabel = 'In behandeling';
        statusIcon = Icons.hourglass_top_rounded;
        break;
      default:
        statusColor = Colors.grey.shade500;
        statusLabel = 'Niet geüpload';
        statusIcon = Icons.upload_file_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: cat.color.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(cat.icon, color: cat.color.shade600, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.title,
                          style: GoogleFonts.sora(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: GymiesColors.darkBlue,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cat.subtitle,
                          style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isUploading ? null : () => _upload(cat.key),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GymiesColors.darkBlue,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: isUploading
                      ? SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: GymiesColors.darkBlue),
                        )
                      : Icon(
                          uploaded ? Icons.refresh_rounded : Icons.cloud_upload_outlined,
                          size: 18,
                        ),
                  label: Text(
                    isUploading
                        ? 'Uploaden...'
                        : uploaded
                            ? 'Opnieuw uploaden'
                            : 'Document uploaden',
                    style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (status == 'rejected') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 14, color: Colors.red.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dit document is afgekeurd. Upload een nieuw document.',
                          style: GoogleFonts.sora(fontSize: 11, color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Waarom verificatie?',
                  style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.blue.shade800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Geverifieerde trainers krijgen een badge op hun profiel, '
            'worden hoger getoond in zoekresultaten en winnen meer vertrouwen bij klanten. '
            'Documenten worden vertrouwelijk behandeld en alleen door ons team bekeken.',
            style: GoogleFonts.sora(fontSize: 12, color: Colors.blue.shade900, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            'Toegestane formaten: PDF, JPG, PNG (max 10MB per bestand)',
            style: GoogleFonts.sora(fontSize: 11, color: Colors.blue.shade600),
          ),
        ],
      ),
    );
  }
}

class _DocCategory {
  const _DocCategory({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final MaterialColor color;
}
