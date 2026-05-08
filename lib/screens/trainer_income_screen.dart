import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/gymies_theme.dart';
import '../models/trainer_models.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
import '../utils/haptics.dart';
import '../utils/currency_format.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

/// Inkomstenoverzicht voor trainer.
class TrainerIncomeScreen extends StatefulWidget {
  const TrainerIncomeScreen({super.key});

  @override
  State<TrainerIncomeScreen> createState() => _TrainerIncomeScreenState();
}

class _TrainerIncomeScreenState extends State<TrainerIncomeScreen> {
  TrainerRevenue? _revenue;
  bool _loading = true;
  String? _error;
  String _statusFilter = 'all';
  DateTimeRange? _range;
  Map<String, String> _liveStatusByItemId = const {};
  int _visibleItems = 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<GymiesApi>();
      if (kDebugMode) debugPrint('[TrainerIncome] Inkomsten laden (filter=$_statusFilter, range=$_range)...');
      final r = await api.getTrainerRevenue(
        from: _range?.start,
        to: _range?.end,
        status: _statusFilter,
      );
      if (kDebugMode) debugPrint('[TrainerIncome] OK – ${r.items.length} items, totaal=${r.totalRevenueCents}c');
      final live = <String, String>{};
      final candidates = r.items
          .where((i) => (i.bookingId ?? '').trim().isNotEmpty)
          .take(20)
          .toList();
      await Future.wait(
        candidates.map((item) async {
          try {
            final status = await api
                .getBookingPaymentStatus(item.bookingId!)
                .timeout(const Duration(seconds: 8));
            final resolved =
                (status['status'] ??
                        status['payment_status'] ??
                        status['mollie_status'])
                    ?.toString()
                    .trim();
            if (resolved != null && resolved.isNotEmpty) {
              live[item.id] = resolved;
            }
          } catch (_) {
            // Best effort only: keep revenue endpoint status if call fails.
          }
        }),
        eagerError: false,
      );
      if (mounted) {
        setState(() {
          _revenue = r;
          _liveStatusByItemId = live;
          _visibleItems = 20;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[TrainerIncome] ApiException: ${e.statusCode} – ${e.message}');
      if (mounted) {
        // Bij 404/500: toon leeg overzicht i.p.v. foutmelding
        if (e.statusCode == 404 || e.statusCode == 500) {
          if (kDebugMode) debugPrint(S.of(context).trainerincomeFallbackLeegOverzicht);
          setState(() {
            _revenue = TrainerRevenue.fromJson({});
            _liveStatusByItemId = const {};
            _visibleItems = 20;
            _loading = false;
            _error = null;
          });
        } else {
          setState(() {
            _error = e.message;
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[TrainerIncome] Error: $e');
      if (mounted) {
        setState(() {
          _revenue = TrainerRevenue.fromJson({});
          _liveStatusByItemId = const {};
          _visibleItems = 20;
          _loading = false;
          _error = null;
        });
      }
    }
  }

  /// Client-side filtering: fallback als backend status niet ondersteunt.
  bool _matchesStatusFilter(String resolvedStatus) {
    if (_statusFilter == 'all') return true;
    final s = resolvedStatus.toLowerCase();
    switch (_statusFilter) {
      case 'paid':
        return s == 'paid' || s == 'paid_mollie' || s == 'mollie_paid' || s == 'succeeded' || s == 'completed';
      case 'cash':
        return s == 'cash' || s == 'paid_cash';
      case 'open':
        return s == 'pending' || s == 'open' || s == 'unpaid' || s == 'due';
      case 'cancelled':
        return s == 'cancelled' || s == 'canceled' || s == 'refunded';
      default:
        return true;
    }
  }

  List<TrainerRevenueItem> get _filteredItems {
    if (_revenue == null) return [];
    if (_statusFilter == 'all') return _revenue!.items;
    return _revenue!.items.where((i) {
      final status = _liveStatusByItemId[i.id] ?? i.paymentStatus ?? i.status;
      return _matchesStatusFilter(status);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    String rangeLabel = 'Periode: alles';
    if (_range != null) {
      final s = _range!.start;
      final e = _range!.end;
      rangeLabel =
          'Periode: ${s.day}/${s.month}/${s.year} - ${e.day}/${e.month}/${e.year}';
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: S.of(context).sessieinkomsten,
      ),
      body: GymiesListBody(
        loading: _loading || _revenue == null,
        error: _error,
        onRefresh: _load,
        child: _revenue == null
            ? const SizedBox.shrink()
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(_statusFilter),
                          initialValue: _statusFilter,
                          decoration: const InputDecoration(
                            labelText: S.of(context).status,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text(S.of(context).alle)),
                            DropdownMenuItem(
                              value: 'paid',
                              child: Text(S.of(context).betaaldonline),
                            ),
                            DropdownMenuItem(
                              value: 'cash',
                              child: Text(S.of(context).contantBetaald),
                            ),
                            DropdownMenuItem(
                              value: 'open',
                              child: Text(S.of(context).openstaand),
                            ),
                            DropdownMenuItem(
                              value: 'cancelled',
                              child: Text(S.of(context).geannuleerd),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            Haptics.selection();
                            setState(() {
                              _statusFilter = v;
                              _visibleItems = 20;
                            });
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          Haptics.selection();
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2022),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            initialDateRange: _range,
                          );
                          if (picked == null) return;
                          if (!mounted) return;
                          Haptics.light();
                          setState(() => _range = picked);
                          _load();
                        },
                        icon: const Icon(Icons.date_range_rounded),
                        label: const Text(S.of(context).periode),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          rangeLabel,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (_range != null)
                        TextButton(
                          onPressed: () {
                            Haptics.light();
                            setState(() {
                              _range = null;
                              _visibleItems = 20;
                            });
                            _load();
                          },
                          child: const Text(S.of(context).wis),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          label: 'Omzet',
                          amountCents: _revenue!.totalRevenueCents,
                          color: GymiesColors.darkBlue,
                          icon: Icons.account_balance_wallet_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryCard(
                          label: S.of(context).betaald,
                          amountCents: _revenue!.paidRevenueCents,
                          color: Colors.green.shade700,
                          icon: Icons.check_circle_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryCard(
                          label: S.of(context).openstaand,
                          amountCents: _revenue!.pendingPayoutCents,
                          color: Colors.orange.shade700,
                          icon: Icons.schedule_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: GymiesColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.history_rounded, size: 15, color: GymiesColors.darkBlue),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        S.of(context).recent,
                        style: GoogleFonts.sora(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_filteredItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: TrainerEmptyState(
                        icon: Icons.payments_outlined,
                        title: S.of(context).geenTransacties,
                        subtitle: _statusFilter == 'all'
                            ? S.of(context).transactiesVerschijnenNaBevestigdeEnAfgeronde
                            : S.of(context).geenTransactiesMetDezeStatus,
                        actionLabel: 'Ververs inkomsten',
                        onAction: _load,
                        padding: EdgeInsets.zero,
                      ),
                    )
                  else
                    ..._filteredItems
                        .take(_visibleItems)
                        .map(
                          (i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _RevenueItemCard(
                              item: i,
                              resolvedStatus:
                                  _liveStatusByItemId[i.id] ??
                                  i.paymentStatus ??
                                  i.status,
                            ),
                          ),
                        ),
                  if (_filteredItems.length > _visibleItems)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          Haptics.light();
                          setState(() {
                            _visibleItems = (_visibleItems + 20).clamp(
                              20,
                              _filteredItems.length,
                            );
                          });
                        },
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text(S.of(context).toonMeer),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.amountCents,
    required this.color,
    required this.icon,
  });

  final String label;
  final int amountCents;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 12, color: color),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            formatEuro(amountCents),
            style: GoogleFonts.sora(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _RevenueItemCard extends StatelessWidget {
  const _RevenueItemCard({required this.item, required this.resolvedStatus});

  final TrainerRevenueItem item;
  final String resolvedStatus;

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'paid_mollie':
      case 'mollie_paid':
        return Icons.credit_card_rounded;
      case 'cash':
      case 'paid_cash':
        return Icons.payments_rounded;
      case 'pending':
      case 'open':
      case 'unpaid':
        return Icons.schedule_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.receipt_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsedDate = DateTime.tryParse(item.scheduledAt);
    final dateLabel = parsedDate != null
        ? '${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year}'
        : item.scheduledAt;
    final iconColor = _statusColor(resolvedStatus);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(_statusIcon(resolvedStatus), size: 18, color: iconColor),
        ),
        title: Text(
          dateLabel,
          style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _statusLabel(resolvedStatus),
              style: TextStyle(
                color: _statusColor(resolvedStatus),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _contextLabel(item),
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
          ],
        ),
        trailing: Text(
          formatEuro(item.amountCents),
          style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'paid_mollie':
      case 'mollie_paid':
        return S.of(context).betaaldonline;
      case 'cash':
      case 'paid_cash':
        return S.of(context).contantBetaald;
      case 'pending':
      case 'open':
      case 'unpaid':
        return S.of(context).openstaand;
      case 'cancelled':
        return S.of(context).geannuleerd;
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'paid_mollie':
      case 'mollie_paid':
        return Colors.green.shade700;
      case 'cash':
      case 'paid_cash':
        return Colors.teal.shade700;
      case 'pending':
      case 'open':
      case 'unpaid':
        return Colors.orange.shade700;
      case 'cancelled':
        return Colors.red.shade700;
      default:
        return GymiesColors.darkBlue;
    }
  }

  String _contextLabel(TrainerRevenueItem item) {
    final parts = <String>[];
    if ((item.bookingId ?? '').trim().isNotEmpty) {
      parts.add('Boeking ${item.bookingId}');
    }
    if ((item.paymentMethod ?? '').trim().isNotEmpty) {
      final method = item.paymentMethod!.trim().toLowerCase();
      parts.add(method == 'cash' ? 'Contant' : method.toUpperCase());
    }
    if ((item.paymentReference ?? '').trim().isNotEmpty) {
      parts.add('Ref ${item.paymentReference}');
    }
    if (parts.isEmpty) return S.of(context).geenExtraDetails;
    return parts.join(' · ');
  }
}
