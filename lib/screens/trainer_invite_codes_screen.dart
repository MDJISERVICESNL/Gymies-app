import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';

/// Scherm waar trainers hun invite codes beheren, delen (share_plus) en als QR tonen.
class TrainerInviteCodesScreen extends StatefulWidget {
  const TrainerInviteCodesScreen({super.key});

  @override
  State<TrainerInviteCodesScreen> createState() => _TrainerInviteCodesScreenState();
}

class _TrainerInviteCodesScreenState extends State<TrainerInviteCodesScreen> {
  bool _loading = true;
  bool _generating = false;
  String? _error;
  List<Map<String, dynamic>> _codes = [];

  @override
  void initState() {
    super.initState();
    _loadCodes();
  }

  Future<void> _loadCodes() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final api = context.read<GymiesApi>();
      final codes = await api.getMyInviteCodes();
      if (!mounted) return;
      setState(() { _codes = codes; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _generateCodes() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final api = context.read<GymiesApi>();
      await api.generateInviteCodes(count: 5, maxUses: 1);
      Haptics.light();
      await _loadCodes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fout bij genereren: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _shareCode(String code) {
    final text = 'Gebruik mijn GYMIES invite code: $code\n'
        'Download de app en vul de code in bij registratie!';
    SharePlus.instance.share(ShareParams(text: text));
    Haptics.light();
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    Haptics.light();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Code gekopieerd!'), duration: Duration(seconds: 1)),
    );
  }

  void _showQrDialog(String code) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Invite Code', style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: GymiesColors.darkBlue)),
              const SizedBox(height: 8),
              Text(code, style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w700, color: GymiesColors.primary, letterSpacing: 2)),
              const SizedBox(height: 16),
              QrImageView(
                data: code,
                version: QrVersions.auto,
                size: 200,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.roundedOuter, color: Color(0xFF1E3A5F)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.roundedOutsideCorners, color: Color(0xFF1E3A5F)),
              ),
              const SizedBox(height: 16),
              Text('Laat klanten deze QR scannen', style: GoogleFonts.sora(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: () { _copyCode(code); Navigator.pop(ctx); },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Kopieer'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () { _shareCode(code); Navigator.pop(ctx); },
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Deel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GymiesAppBar(title: 'Mijn Invite Codes'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: GoogleFonts.sora(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _loadCodes, child: const Text('Opnieuw proberen')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadCodes,
                  child: _codes.isEmpty ? _buildEmptyState() : _buildCodesList(),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generating ? null : _generateCodes,
        backgroundColor: GymiesColors.primary,
        foregroundColor: GymiesColors.darkBlue,
        icon: _generating
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: Text(_generating ? 'Genereren...' : '5 codes genereren', style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.card_giftcard, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(
          'Nog geen invite codes',
          textAlign: TextAlign.center,
          style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
        ),
        const SizedBox(height: 8),
        Text(
          'Genereer codes en deel ze met potentiele klanten om ze uit te nodigen voor GYMIES.',
          textAlign: TextAlign.center,
          style: GoogleFonts.sora(fontSize: 14, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildCodesList() {
    final active = _codes.where((c) => (c['status'] ?? '') == 'active').toList();
    final used = _codes.where((c) => (c['status'] ?? '') != 'active').toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // Stats card
        _buildStatsCard(),
        const SizedBox(height: 16),
        if (active.isNotEmpty) ...[
          Text('Actieve codes', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
          const SizedBox(height: 8),
          ...active.map(_buildCodeCard),
        ],
        if (used.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Gebruikte / verlopen codes', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.grey[600])),
          const SizedBox(height: 8),
          ...used.map(_buildCodeCard),
        ],
      ],
    );
  }

  Widget _buildStatsCard() {
    final total = _codes.length;
    final totalUsed = _codes.fold<int>(0, (sum, c) => sum + ((c['uses_count'] as int?) ?? 0));
    final active = _codes.where((c) => (c['status'] ?? '') == 'active').length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF2A5298)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statColumn('Totaal', '$total', Icons.vpn_key),
          _statColumn('Actief', '$active', Icons.check_circle_outline),
          _statColumn('Gebruikt', '$totalUsed', Icons.people),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: GymiesColors.primary, size: 24),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: GoogleFonts.sora(fontSize: 12, color: Colors.white70)),
      ],
    );
  }

  Widget _buildCodeCard(Map<String, dynamic> code) {
    final codeStr = (code['code'] ?? '') as String;
    final status = (code['status'] ?? 'active') as String;
    final usesCount = (code['uses_count'] as int?) ?? 0;
    final maxUses = (code['max_uses'] as int?) ?? 1;
    final isActive = status == 'active';
    final uses = (code['uses'] as List?) ?? [];
    final validUntil = code['valid_until'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isActive ? 2 : 0,
      color: isActive ? Colors.white : Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isActive ? () => _showQrDialog(codeStr) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      codeStr,
                      style: GoogleFonts.sora(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: isActive ? GymiesColors.darkBlue : Colors.grey,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isActive ? 'Actief' : status == 'exhausted' ? 'Vol' : 'Verlopen',
                      style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? Colors.green[700] : Colors.grey),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.people_outline, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text('$usesCount / $maxUses gebruikt', style: GoogleFonts.sora(fontSize: 12, color: Colors.grey[600])),
                  if (validUntil != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.schedule, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text('Geldig t/m ${validUntil.substring(0, 10)}', style: GoogleFonts.sora(fontSize: 12, color: Colors.grey[600])),
                  ],
                ],
              ),
              if (isActive) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    _actionChip(Icons.qr_code, 'QR', () => _showQrDialog(codeStr)),
                    const SizedBox(width: 8),
                    _actionChip(Icons.share, 'Deel', () => _shareCode(codeStr)),
                    const SizedBox(width: 8),
                    _actionChip(Icons.copy, 'Kopieer', () => _copyCode(codeStr)),
                  ],
                ),
              ],
              if (uses.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Gebruikt door:', style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[500])),
                const SizedBox(height: 4),
                ...uses.take(3).map((u) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    'User #${u['user_id']} - ${(u['created_at'] ?? '').toString().substring(0, 10)}',
                    style: GoogleFonts.sora(fontSize: 11, color: Colors.grey[500]),
                  ),
                )),
                if (uses.length > 3)
                  Text('+ ${uses.length - 3} meer', style: GoogleFonts.sora(fontSize: 11, color: GymiesColors.darkBlue)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: GymiesColors.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: GymiesColors.darkBlue),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
          ],
        ),
      ),
    );
  }
}
