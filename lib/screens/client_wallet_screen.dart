

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import 'widgets/trainer_state_views.dart';
/// Wallet/Tegoed scherm: puntenbalans, geschiedenis, inwisselen.
class ClientWalletScreen extends StatefulWidget {
  const ClientWalletScreen({super.key});

  @override
  State<ClientWalletScreen> createState() => _ClientWalletScreenState();
}

class _ClientWalletScreenState extends State<ClientWalletScreen> {
  bool _loading = true;
  String? _error;
  int _balance = 0;
  List<Map<String, dynamic>> _recent = [];
  List<Map<String, dynamic>> _history = [];
  int _historyPage = 1;
  int _totalPages = 1;
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final api = context.read<GymiesApi>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await api.getPointsBalance();
      if (!mounted) return;
      setState(() {
        _balance = (data['current_balance'] ?? 0) as int;
        final recent = data['recent_transactions'];
        _recent = recent is List
            ? recent.map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{}).toList()
            : [];
        _loading = false;
      });
      // Laad ook volledige historie
      await _loadHistory(page: 1);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = S.of(context).konTegoedNietLaden;
        _loading = false;
      });
    }
  }

  Future<void> _loadHistory({required int page}) async {
    if (_historyLoading) return;
    setState(() => _historyLoading = true);
    try {
      final api = context.read<GymiesApi>();
      final data = await api.getPointsHistory(page: page);
      if (!mounted) return;
      final items = data['data'] as List? ?? [];
      final pag = data['pagination'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      setState(() {
        if (page == 1) {
          _history = items.cast<Map<String, dynamic>>();
        } else {
          _history.addAll(items.cast<Map<String, dynamic>>());
        }
        _historyPage = page;
        _totalPages = (pag['total_pages'] ?? 1) as int;
        _historyLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _showRedeemDialog() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RedeemSheet(balance: _balance),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<GymiesApi>().redeemPoints(
            rewardType: result['reward_type'] as String,
            pointsToSpend: result['points'] as int,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).puntenIngewisseld, style: GoogleFonts.sora()),
            backgroundColor: Colors.green.shade600,
          ),
        );
        await _load();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message, style: GoogleFonts.sora()),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          // ── Header ──
          Container(
            decoration: const BoxDecoration(color: GymiesColors.darkBlue),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        Haptics.selection();
                        Navigator.of(context).pop();
                      },
                      child: const Icon(Icons.arrow_back_ios_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        S.of(context).mijnTegoed,
                        style: GoogleFonts.sora(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: GymiesListBody(
              loading: _loading,
              error: _error,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Balance card ──
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [GymiesColors.darkBlue, Color(0xFF2A4F7F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: GymiesColors.primary.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.account_balance_wallet_rounded,
                                    size: 26, color: GymiesColors.primary),
                              ),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    S.of(context).huidigSaldo,
                                    style: GoogleFonts.sora(
                                      fontSize: 13,
                                      color: Colors.white.withOpacity(0.6),
                                    ),
                                  ),
                                  Text(
                                    '$_balance punten',
                                    style: GoogleFonts.sora(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _balance > 0 ? _showRedeemDialog : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: GymiesColors.primary,
                                foregroundColor: GymiesColors.darkBlue,
                                disabledBackgroundColor:
                                    Colors.white.withOpacity(0.1),
                                disabledForegroundColor:
                                    Colors.white.withOpacity(0.3),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: GoogleFonts.sora(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: const Text(S.of(context).puntenInwisselen),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Hoe punten verdienen ──
                  Text(
                    S.of(context).hoeVerdienJePunten,
                    style: GoogleFonts.sora(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                      icon: Icons.fitness_center_rounded,
                      label: S.of(context).sessieVoltooid,
                      points: '+10'),
                  _InfoRow(
                      icon: Icons.star_rounded,
                      label: 'Review geplaatst',
                      points: '+5'),
                  _InfoRow(
                      icon: Icons.person_add_rounded,
                      label: 'Vriend uitgenodigd',
                      points: '+25'),
                  const SizedBox(height: 24),

                  // ── Geschiedenis ──
                  Text(
                    S.of(context).geschiedenis,
                    style: GoogleFonts.sora(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_history.isEmpty && _recent.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          S.of(context).nogGeenTransacties,
                          style: GoogleFonts.sora(
                              fontSize: 13, color: Colors.grey.shade400),
                        ),
                      ),
                    )
                  else ...[
                    ...(_history.isNotEmpty ? _history : _recent)
                        .map((tx) => _TransactionTile(tx: tx)),
                    if (_historyPage < _totalPages)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: _historyLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : TextButton(
                                  onPressed: () =>
                                      _loadHistory(page: _historyPage + 1),
                                  child: Text(
                                    S.of(context).meerLaden,
                                    style: GoogleFonts.sora(
                                      color: GymiesColors.darkBlue,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.points,
  });
  final IconData icon;
  final String label;
  final String points;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: GymiesColors.darkBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.sora(fontSize: 13, color: GymiesColors.darkBlue)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                points,
                style: GoogleFonts.sora(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});
  final Map<String, dynamic> tx;

  @override
  Widget build(BuildContext context) {
    final delta = (tx['delta'] ?? 0) as int;
    final isPositive = delta >= 0;
    final eventType = (tx['event_type'] ?? '') as String;
    final description = (tx['description'] ?? eventType) as String;
    final createdAt = (tx['created_at'] ?? '') as String;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isPositive
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isPositive
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 18,
                color: isPositive ? Colors.green.shade600 : Colors.red.shade600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _eventLabel(eventType, description),
                    style: GoogleFonts.sora(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: GymiesColors.darkBlue,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (createdAt.isNotEmpty)
                    Text(
                      _formatDate(createdAt),
                      style: GoogleFonts.sora(
                          fontSize: 11, color: Colors.grey.shade500),
                    ),
                ],
              ),
            ),
            Text(
              '${isPositive ? '+' : ''}$delta',
              style: GoogleFonts.sora(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isPositive ? Colors.green.shade600 : Colors.red.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _eventLabel(String type, String desc) {
    if (desc.isNotEmpty && desc != type) return desc;
    switch (type) {
      case 'session_completed':
        return S.of(context).sessieVoltooid;
      case 'review_placed':
        return 'Review geplaatst';
      case 'referral_completed':
        return 'Vriend uitgenodigd';
      case 'redemption':
        return 'Punten ingewisseld';
      default:
        return type.replaceAll('_', ' ');
    }
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.length > 10 ? raw.substring(0, 10) : raw;
    return '${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year}';
  }
}

// ─── Redeem bottom sheet ──────────────────────────────────

class _RedeemSheet extends StatefulWidget {
  const _RedeemSheet({required this.balance});
  final int balance;

  @override
  State<_RedeemSheet> createState() => _RedeemSheetState();
}

class _RedeemSheetState extends State<_RedeemSheet> {
  String _rewardType = 'session_credit';

  int get _cost => _rewardType == 'session_credit' ? 50 : 100;
  bool get _canAfford => widget.balance >= _cost;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              S.of(context).puntenInwisselen,
              style: GoogleFonts.sora(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: GymiesColors.darkBlue,
              ),
            ),
            Text(
              'Je hebt ${widget.balance} punten',
              style: GoogleFonts.sora(
                  fontSize: 13, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 20),

            // Opties
            _RewardOption(
              title: S.of(context).sessieTegoed,
              subtitle: '50 punten → €5 korting',
              cost: 50,
              isSelected: _rewardType == 'session_credit',
              canAfford: widget.balance >= 50,
              onTap: () => setState(() => _rewardType = 'session_credit'),
            ),
            const SizedBox(height: 8),
            _RewardOption(
              title: S.of(context).gratisSessie,
              subtitle: S.of(context).n100Punten1GratisSessie,
              cost: 100,
              isSelected: _rewardType == 'free_session',
              canAfford: widget.balance >= 100,
              onTap: () => setState(() => _rewardType = 'free_session'),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _canAfford
                    ? () {
                        Haptics.selection();
                        Navigator.of(context).pop({
                          'reward_type': _rewardType,
                          'points': _cost,
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: GymiesColors.primary,
                  foregroundColor: GymiesColors.darkBlue,
                  disabledBackgroundColor: Colors.grey.shade200,
                  disabledForegroundColor: Colors.grey.shade400,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: GoogleFonts.sora(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(_canAfford
                    ? 'Inwisselen ($_cost punten)'
                    : 'Niet genoeg punten'),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }
}

class _RewardOption extends StatelessWidget {
  const _RewardOption({
    required this.title,
    required this.subtitle,
    required this.cost,
    required this.isSelected,
    required this.canAfford,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final int cost;
  final bool isSelected;
  final bool canAfford;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: canAfford ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? GymiesColors.darkBlue.withOpacity(0.05)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? GymiesColors.darkBlue : Colors.grey.shade200,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.sora(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: canAfford
                          ? GymiesColors.darkBlue
                          : Colors.grey.shade400,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.sora(
                      fontSize: 12,
                      color: canAfford
                          ? Colors.grey.shade500
                          : Colors.grey.shade300,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded,
                  size: 22, color: GymiesColors.darkBlue),
          ],
        ),
      ),
    );
  }
}
