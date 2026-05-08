

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'client_dispute_detail_screen.dart';
/// Overzicht van alle geschillen van de ingelogde client.
class ClientDisputesScreen extends StatefulWidget {
  const ClientDisputesScreen({super.key});

  @override
  State<ClientDisputesScreen> createState() => _ClientDisputesScreenState();
}

class _ClientDisputesScreenState extends State<ClientDisputesScreen> {
  List<Map<String, dynamic>> _disputes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<GymiesApi>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.getMyDisputes();
      if (!mounted) return;
      setState(() {
        _disputes = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = S.of(context).konGeschillenNietLaden;
        _loading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.orange.shade600;
      case 'in_progress':
        return Colors.blue.shade600;
      case 'resolved':
        return Colors.green.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'open':
        return 'Open';
      case 'in_progress':
        return S.of(context).statusInBehandeling;
      case 'resolved':
        return 'Opgelost';
      default:
        return status;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'open':
        return Icons.error_outline_rounded;
      case 'in_progress':
        return Icons.hourglass_top_rounded;
      case 'resolved':
        return Icons.check_circle_outline_rounded;
      default:
        return Icons.help_outline_rounded;
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
          S.of(context).geschillen,
          style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: GymiesColors.primary))
          : _error != null
              ? _buildError()
              : _disputes.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: GoogleFonts.sora(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(S.of(context).opnieuwProberen, style: GoogleFonts.sora(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: GymiesColors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.gavel_rounded,
                size: 36,
                color: GymiesColors.darkBlue.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              S.of(context).geenGeschillen,
              style: GoogleFonts.sora(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.of(context).mochtJeOoitEenProbleemHebben
              S.of(context).danKunJeHierEenGeschil,
              style: GoogleFonts.sora(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      color: GymiesColors.primary,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _disputes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final d = _disputes[i];
          final status = (d['status'] ?? 'open').toString();
          final reason = (d['reason'] ?? '').toString();
          final otherParty = (d['other_party'] ?? S.of(context).statusOnbekend).toString();
          final createdAt = (d['created_at'] ?? '').toString();
          final id = d['id']?.toString() ?? '';

          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                Haptics.selection();
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ClientDisputeDetailScreen(disputeId: id),
                  ),
                );
                _load(); // Refresh na terugkeer
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status icon
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _statusColor(status).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _statusIcon(status),
                        color: _statusColor(status),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reason,
                            style: GoogleFonts.sora(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: GymiesColors.darkBlue,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Met $otherParty',
                            style: GoogleFonts.sora(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _statusLabel(status),
                                  style: GoogleFonts.sora(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _statusColor(status),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (createdAt.isNotEmpty)
                                Text(
                                  _formatDate(createdAt),
                                  style: GoogleFonts.sora(
                                    fontSize: 11,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes} min geleden';
      if (diff.inHours < 24) return '${diff.inHours} uur geleden';
      if (diff.inDays < 7) return '${diff.inDays} dagen geleden';
      return '${dt.day}-${dt.month}-${dt.year}';
    } catch (_) {
      return raw;
    }
  }
}
