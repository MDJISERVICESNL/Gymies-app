import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/currency_format.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

/// Gym Finance Screen — Mollie integration, payout settings, and settlements overview.
class GymFinanceScreen extends StatefulWidget {
  const GymFinanceScreen({super.key});

  @override
  State<GymFinanceScreen> createState() => _GymFinanceScreenState();
}

class _GymFinanceScreenState extends State<GymFinanceScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _mollieStatus = {};
  Map<String, dynamic> _payoutSettings = {};
  List<Map<String, dynamic>> _settlements = [];

  // Form state
  final _ibanController = TextEditingController();
  final _ibanNameController = TextEditingController();
  String _payoutFrequency = 'monthly';
  String _payoutMode = 'mollie';
  bool _saving = false;
  String? _downloadingSettlementId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ibanController.dispose();
    _ibanNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();

      // Load Mollie status
      final mollie = await api.getGymMollieStatus();

      // Load payout settings
      final settings = await api.getGymPayoutSettings();

      // Load settlements
      final settlementsRes = await api.getGymSettlementsData();
      final raw = settlementsRes['settlements'] ?? [];
      final settlementsList = raw is List
          ? raw.map((e) => e is Map ? Map<String, dynamic>.from(e as Map) : <String, dynamic>{}).toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;

      // Populate form fields
      _ibanController.text = settings['iban']?.toString() ?? '';
      _ibanNameController.text = settings['iban_name']?.toString() ?? '';
      _payoutFrequency = settings['payout_frequency']?.toString() ?? 'monthly';
      _payoutMode = settings['payout_mode']?.toString() ?? 'mollie';

      setState(() {
        _mollieStatus = mollie;
        _payoutSettings = settings;
        _settlements = settlementsList;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kon instellingen niet laden';
        _loading = false;
      });
    }
  }

  Future<void> _connectMollie() async {
    // For now, show a message that Mollie is connected via the OAuth flow
    // The gym owner uses the same OAuth flow as trainers
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mollie-verbinding gebeurt via het onboarding-proces'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Future<void> _disconnectMollie() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mollie verbreken?'),
        content: const Text('Dit zal de Mollie-koppeling verwijderen. U kunt later opnieuw verbinding maken.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verbreken', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      Haptics.light();
      await context.read<GymiesApi>().disconnectGymMollie();
      if (!mounted) return;
      Haptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mollie-koppeling verwijderd'),
          backgroundColor: Colors.green,
        ),
      );
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _savePayoutSettings() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      Haptics.light();
      await context.read<GymiesApi>().updateGymPayoutSettings(
        iban: _ibanController.text.trim(),
        ibanName: _ibanNameController.text.trim(),
        payoutFrequency: _payoutFrequency,
        payoutMode: _payoutMode,
      );
      if (!mounted) return;
      Haptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uitbetalingsinstellingen opgeslagen'),
          backgroundColor: Colors.green,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _downloadSettlement(Map<String, dynamic> settlement) async {
    final id = settlement['id'];
    if (id == null) return;

    final settlementId = id.toString();
    setState(() => _downloadingSettlementId = settlementId);

    try {
      Haptics.light();
      final bytes = await context.read<GymiesApi>().downloadGymSettlementInvoice(settlementId);

      // Opslaan in temp directory
      final dir = await getTemporaryDirectory();
      final invoiceNumber = (settlement['invoice_number'] ?? 'settlement-$settlementId').toString();

      // Detect HTML or PDF
      final isHtml = bytes.length > 5 &&
          (String.fromCharCodes(bytes.take(20)).trimLeft().startsWith('<!DOC') ||
           String.fromCharCodes(bytes.take(20)).trimLeft().startsWith('<html'));
      final ext = isHtml ? 'html' : 'pdf';
      final file = File('${dir.path}/$invoiceNumber.$ext');
      await file.writeAsBytes(bytes);

      if (!mounted) return;

      Haptics.success();
      // Share via share sheet
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Afrekening $invoiceNumber',
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download mislukt: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _downloadingSettlementId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: const GymiesAppBar(title: 'Financiën & Mollie'),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Mollie Status Section ──
          _buildMollieSection(),
          const SizedBox(height: 32),

          // ── Payout Settings Section ──
          _buildPayoutSettingsSection(),
          const SizedBox(height: 32),

          // ── Settlements Section ──
          _buildSettlementsSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMollieSection() {
    final isConnected = _mollieStatus['connected'] == true;
    final mollieOrgId = _mollieStatus['mollie_organization_id']?.toString() ?? '—';
    final canReceivePayments = _mollieStatus['can_receive_payments'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'Mollie Koppeling', icon: Icons.payment_rounded),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status indicator
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected ? Colors.green : Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isConnected ? 'Verbonden' : 'Niet verbonden',
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isConnected ? Colors.green : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              if (isConnected) ...[
                const SizedBox(height: 12),
                Text(
                  'Organisatie-ID',
                  style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 4),
                Text(
                  mollieOrgId,
                  style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      canReceivePayments ? Icons.check_circle : Icons.cancel,
                      size: 18,
                      color: canReceivePayments ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      canReceivePayments ? 'Kan betalingen ontvangen' : 'Account onvolledig',
                      style: GoogleFonts.sora(fontSize: 13),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  if (isConnected)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text('Verbreken'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          foregroundColor: Colors.red,
                        ),
                        onPressed: _disconnectMollie,
                      ),
                    )
                  else
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.link, size: 18),
                        label: const Text('Verbinden'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                        ),
                        onPressed: _connectMollie,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPayoutSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Uitbetalingsinstellingen',
          icon: Icons.account_balance_rounded,
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // IBAN field
              Text(
                'IBAN',
                style: GoogleFonts.sora(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ibanController,
                decoration: InputDecoration(
                  hintText: 'NL91ABNA0417164300',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: GoogleFonts.sora(fontSize: 14),
              ),
              const SizedBox(height: 16),

              // IBAN Name field
              Text(
                'Naam op bankrekening',
                style: GoogleFonts.sora(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ibanNameController,
                decoration: InputDecoration(
                  hintText: 'Naam van eigenaar',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: GoogleFonts.sora(fontSize: 14),
              ),
              const SizedBox(height: 16),

              // Payout frequency
              Text(
                'Uitbetalingsfrequentie',
                style: GoogleFonts.sora(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _payoutFrequency,
                items: [
                  DropdownMenuItem(value: 'weekly', child: Text('Wekelijks', style: GoogleFonts.sora())),
                  DropdownMenuItem(value: 'monthly', child: Text('Maandelijks', style: GoogleFonts.sora())),
                  DropdownMenuItem(value: 'quarterly', child: Text('Driemaandelijks', style: GoogleFonts.sora())),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _payoutFrequency = val);
                },
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 20),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GymiesColors.primary,
                    foregroundColor: GymiesColors.darkBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _saving ? null : _savePayoutSettings,
                  child: _saving
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(GymiesColors.darkBlue),
                          ),
                        )
                      : Text(
                          'Opslaan',
                          style: GoogleFonts.sora(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettlementsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Afleveringen & Facturen',
          icon: Icons.receipt_long_rounded,
        ),
        const SizedBox(height: 12),
        if (_settlements.isEmpty)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Center(
              child: Text(
                'Nog geen afleveringen',
                style: GoogleFonts.sora(color: Colors.grey.shade500),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _settlements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final s = _settlements[i];
              final id = s['id'].toString();
              final status = s['status']?.toString() ?? 'unknown';
              final net = s['net_cents'] as int? ?? 0;
              final gross = s['gross_cents'] as int? ?? 0;
              final fee = s['fee_cents'] as int? ?? 0;
              final periodStart = s['period_start']?.toString() ?? '—';
              final periodEnd = s['period_end']?.toString() ?? '—';
              final invoiceNum = s['invoice_number']?.toString() ?? id;
              final isDownloading = _downloadingSettlementId == id;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                invoiceNum,
                                style: GoogleFonts.sora(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: GymiesColors.darkBlue,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  status,
                                  style: GoogleFonts.sora(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: _getStatusColor(status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$periodStart → $periodEnd',
                            style: GoogleFonts.sora(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                'Bedrag: ${formatEuro(net)}',
                                style: GoogleFonts.sora(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green.shade700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Kosten: €${(fee / 100.0).toStringAsFixed(2)}',
                                style: GoogleFonts.sora(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: Icon(
                        Icons.download_rounded,
                        color: isDownloading ? Colors.grey : GymiesColors.primary,
                        size: 20,
                      ),
                      onPressed: isDownloading ? null : () => _downloadSettlement(s),
                      tooltip: 'Download factuur',
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'open':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

// ── Section header ──────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: GymiesColors.darkBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.sora(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: GymiesColors.darkBlue,
          ),
        ),
      ],
    );
  }
}
