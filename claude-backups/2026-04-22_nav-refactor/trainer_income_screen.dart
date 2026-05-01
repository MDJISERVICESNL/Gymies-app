import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/gymies_theme.dart';
import '../models/trainer_models.dart';
import '../services/gymies_api.dart';
import '../services/api_client.dart';
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
      final r = await api.getTrainerRevenue(
        from: _range?.start,
        to: _range?.end,
        status: _statusFilter,
      );
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
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Kon inkomsten niet laden.';
          _loading = false;
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
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Sessie-inkomsten',
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(_statusFilter),
                          initialValue: _statusFilter,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('Alle')),
                            DropdownMenuItem(
                              value: 'paid',
                              child: Text('Betaald (online)'),
                            ),
                            DropdownMenuItem(
                              value: 'cash',
                              child: Text('Contant betaald'),
                            ),
                            DropdownMenuItem(
                              value: 'open',
                              child: Text('Openstaand'),
                            ),
                            DropdownMenuItem(
                              value: 'cancelled',
                              child: Text('Geannuleerd'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
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
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2022),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                            initialDateRange: _range,
                          );
                          if (picked == null) return;
                          setState(() => _range = picked);
                          _load();
                        },
                        icon: const Icon(Icons.date_range_rounded),
                        label: const Text('Periode'),
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
                            setState(() {
                              _range = null;
                              _visibleItems = 20;
                            });
                            _load();
                          },
                          child: const Text('Wis'),
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
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryCard(
                          label: 'Betaald',
                          amountCents: _revenue!.paidRevenueCents,
                          color: Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _SummaryCard(
                          label: 'Openstaand',
                          amountCents: _revenue!.pendingPayoutCents,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Recent',
                    style: GoogleFonts.fjallaOne(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_filteredItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: TrainerEmptyState(
                        icon: Icons.payments_outlined,
                        title: 'Geen transacties',
                        subtitle: _statusFilter == 'all'
                            ? 'Transacties verschijnen na bevestigde en afgeronde sessies.'
                            : 'Geen transacties met deze status.',
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
                          setState(() {
                            _visibleItems = (_visibleItems + 20).clamp(
                              20,
                              _filteredItems.length,
                            );
                          });
                        },
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('Toon meer'),
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
  });

  final String label;
  final int amountCents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: GymiesColors.primary.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.fjallaOne(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '€${(amountCents / 100).toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueItemCard extends StatelessWidget {
  const _RevenueItemCard({required this.item, required this.resolvedStatus});

  final TrainerRevenueItem item;
  final String resolvedStatus;

  @override
  Widget build(BuildContext context) {
    final parsedDate = DateTime.tryParse(item.scheduledAt);
    final dateLabel = parsedDate != null
        ? '${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year}'
        : item.scheduledAt;
    return Material(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          dateLabel,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
          '€${(item.amountCents / 100).toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'paid_mollie':
      case 'mollie_paid':
        return 'Betaald (online)';
      case 'cash':
      case 'paid_cash':
        return 'Contant betaald';
      case 'pending':
      case 'open':
      case 'unpaid':
        return 'Openstaand';
      case 'cancelled':
        return 'Geannuleerd';
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
    if (parts.isEmpty) return 'Geen extra details';
    return parts.join(' · ');
  }
}
