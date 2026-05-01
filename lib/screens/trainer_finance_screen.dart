import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../models/trainer_models.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_segment_tab_bar.dart';
import 'widgets/trainer_state_views.dart';

/// Financiën scherm — professioneel overzicht van omzet, transacties en facturen.
/// Vervangt het oude Financiën+ (payout-gericht) en Sessie-inkomsten scherm.
class TrainerFinanceScreen extends StatefulWidget {
  const TrainerFinanceScreen({super.key});

  @override
  State<TrainerFinanceScreen> createState() => _TrainerFinanceScreenState();
}

class _TrainerFinanceScreenState extends State<TrainerFinanceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Data ──
  bool _loading = true;
  String? _error;
  TrainerRevenue? _revenue;
  Map<String, String> _liveStatusByItemId = const {};
  List<Map<String, dynamic>> _invoices = [];
  Map<String, dynamic> _forecast = {};

  // ── Filters (Overzicht tab) ──
  String _statusFilter = 'all';
  DateTimeRange? _range;
  int _visibleItems = 20;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
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

      // ── Revenue data (sessie-inkomsten) ──
      TrainerRevenue revenue = TrainerRevenue.fromJson({});
      try {
        revenue = await api.getTrainerRevenue(
          from: _range?.start,
          to: _range?.end,
          status: _statusFilter,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[Financiën] revenue fout: $e');
      }

      // ── Live payment statuses (best effort) ──
      final live = <String, String>{};
      final candidates = revenue.items
          .where((i) => (i.bookingId ?? '').trim().isNotEmpty)
          .take(20)
          .toList();
      await Future.wait(
        candidates.map((item) async {
          try {
            final status = await api
                .getBookingPaymentStatus(item.bookingId!)
                .timeout(const Duration(seconds: 8));
            final resolved = (status['status'] ??
                    status['payment_status'] ??
                    status['mollie_status'])
                ?.toString()
                .trim();
            if (resolved != null && resolved.isNotEmpty) {
              live[item.id] = resolved;
            }
          } catch (_) {}
        }),
        eagerError: false,
      );

      // ── Forecast data (voor weekgrafiek) ──
      Map<String, dynamic> forecast = {};
      try {
        forecast = await api.getTrainerRevenueForecast();
      } catch (e) {
        if (kDebugMode) debugPrint('[Financiën] forecast fout: $e');
      }

      // ── Facturen ──
      List<Map<String, dynamic>> invoices = [];
      try {
        invoices = await api.getTrainerInvoices();
      } catch (e) {
        if (kDebugMode) debugPrint('[Financiën] invoices fout: $e');
      }

      if (!mounted) return;
      setState(() {
        _revenue = revenue;
        _liveStatusByItemId = live;
        _forecast = forecast;
        _invoices = invoices;
        _visibleItems = 20;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (kDebugMode) debugPrint('[Financiën] ApiException: ${e.statusCode}');
      if (!mounted) return;
      if (e.statusCode == 404 || e.statusCode == 500) {
        setState(() {
          _revenue = TrainerRevenue.fromJson({});
          _liveStatusByItemId = const {};
          _forecast = {};
          _invoices = [];
          _loading = false;
          _error = null;
        });
      } else {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Financiën] Error: $e');
      if (!mounted) return;
      setState(() {
        _revenue = TrainerRevenue.fromJson({});
        _liveStatusByItemId = const {};
        _forecast = {};
        _invoices = [];
        _loading = false;
        _error = null;
      });
    }
  }

  // ── Helpers ──

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  String _currency(dynamic cents) {
    final v = _toInt(cents);
    if (v == null) return '€0,00';
    final euros = v / 100.0;
    return '€${euros.toStringAsFixed(2).replaceAll('.', ',')}';
  }

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

  /// Bouw weekdata voor de grafiek uit forecast of monthly_revenue_cents.
  List<_WeekBar> _buildWeekBars() {
    // Probeer weekly_breakdown uit forecast
    final weekly = mapPick(_forecast, ['weekly_breakdown', 'by_week', 'weeks']);
    if (weekly is List && weekly.isNotEmpty) {
      return weekly.asMap().entries.map((e) {
        final map = e.value is Map ? Map<String, dynamic>.from(e.value as Map) : <String, dynamic>{};
        final cents = _toInt(mapPick(map, ['cents', 'amount_cents', 'value'])) ?? 0;
        final label = mapStr(map, ['label', 'week', 'period']) != ''
            ? mapStr(map, ['label', 'week', 'period'])
            : 'W${e.key + 1}';
        return _WeekBar(label: label, cents: cents);
      }).toList();
    }

    // Fallback: verdeel omzet over weken van huidige maand
    if (_revenue != null && _revenue!.items.isNotEmpty) {
      final now = DateTime.now();
      final weekMap = <int, int>{};
      for (final item in _revenue!.items) {
        final date = DateTime.tryParse(item.scheduledAt);
        if (date == null || date.month != now.month || date.year != now.year) continue;
        final weekNum = ((date.day - 1) / 7).floor();
        weekMap[weekNum] = (weekMap[weekNum] ?? 0) + item.amountCents;
      }
      if (weekMap.isNotEmpty) {
        final sorted = weekMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
        return sorted.map((e) => _WeekBar(label: 'Week ${e.key + 1}', cents: e.value)).toList();
      }
    }

    return [];
  }

  Future<void> _loadQuarterZip() async {
    Haptics.light();
    try {
      final data = await context.read<GymiesApi>().getTrainerInvoicesQuarterZip();
      if (!mounted) return;
      final url = data['url']?.toString();
      Haptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(url == null || url.isEmpty ? 'ZIP export gestart' : 'ZIP klaar voor download'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: 'Financiën',
        bottom: GymiesSegmentTabBar(
          controller: _tabController,
          tabs: const ['Overzicht', 'Facturen'],
        ),
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(),
            _buildInvoicesTab(),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════
  // TAB 1: OVERZICHT
  // ══════════════════════════════════════════════════════════════

  Widget _buildOverviewTab() {
    final rev = _revenue;
    final weekBars = _buildWeekBars();

    // Omzet verdeling uit forecast
    final revenueByType = _forecast['revenue_by_type'] ?? {};
    final sessiesCents = _toInt(revenueByType is Map ? (revenueByType['sessies']?['cents'] ?? revenueByType['sessies']?['amount'] ?? 0) : 0) ?? 0;
    final pakkettenCents = _toInt(revenueByType is Map ? (revenueByType['pakketten']?['cents'] ?? revenueByType['pakketten']?['amount'] ?? 0) : 0) ?? 0;
    final groepslessenCents = _toInt(revenueByType is Map ? (revenueByType['groepslessen']?['cents'] ?? revenueByType['groepslessen']?['amount'] ?? 0) : 0) ?? 0;
    final breakdownTotal = sessiesCents + pakkettenCents + groepslessenCents;

    String rangeLabel = 'Alle periodes';
    if (_range != null) {
      final s = _range!.start;
      final e = _range!.end;
      rangeLabel =
          '${s.day.toString().padLeft(2, '0')}/${s.month.toString().padLeft(2, '0')}/${s.year} – ${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}/${e.year}';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Stat cards: 3 kolommen ──
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Omzet',
                value: _currency(rev?.totalRevenueCents ?? 0),
                icon: Icons.account_balance_wallet_rounded,
                color: GymiesColors.darkBlue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'Ontvangen',
                value: _currency(rev?.paidRevenueCents ?? 0),
                icon: Icons.check_circle_rounded,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: 'Openstaand',
                value: _currency(rev?.pendingPayoutCents ?? 0),
                icon: Icons.schedule_rounded,
                color: Colors.orange.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Weekgrafiek ──
        if (weekBars.isNotEmpty) ...[
          _SectionCard(
            icon: Icons.bar_chart_rounded,
            title: 'Omzet deze maand',
            child: _WeekChart(bars: weekBars, currencyFn: _currency),
          ),
          const SizedBox(height: 12),
        ],

        // ── Omzet verdeling ──
        if (breakdownTotal > 0) ...[
          _SectionCard(
            icon: Icons.pie_chart_rounded,
            title: 'Omzet verdeling',
            child: Column(
              children: [
                if (sessiesCents > 0)
                  _BreakdownBar(
                    label: 'Sessies',
                    cents: sessiesCents,
                    total: breakdownTotal,
                    color: const Color(0xFF3B82F6),
                    currencyFn: _currency,
                  ),
                if (pakkettenCents > 0) ...[
                  const SizedBox(height: 10),
                  _BreakdownBar(
                    label: 'Pakketten',
                    cents: pakkettenCents,
                    total: breakdownTotal,
                    color: Colors.green.shade600,
                    currencyFn: _currency,
                  ),
                ],
                if (groepslessenCents > 0) ...[
                  const SizedBox(height: 10),
                  _BreakdownBar(
                    label: 'Groepslessen',
                    cents: groepslessenCents,
                    total: breakdownTotal,
                    color: Colors.orange.shade600,
                    currencyFn: _currency,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Filters ──
        _SectionCard(
          icon: Icons.filter_list_rounded,
          title: 'Transacties',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _statusFilter,
                          isExpanded: true,
                          style: GoogleFonts.sora(fontSize: 13, color: GymiesColors.darkBlue),
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('Alle statussen')),
                            DropdownMenuItem(value: 'paid', child: Text('Betaald (online)')),
                            DropdownMenuItem(value: 'cash', child: Text('Contant')),
                            DropdownMenuItem(value: 'open', child: Text('Openstaand')),
                            DropdownMenuItem(value: 'cancelled', child: Text('Geannuleerd')),
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
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      Haptics.selection();
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2022),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDateRange: _range,
                      );
                      if (picked == null) return;
                      Haptics.light();
                      setState(() => _range = picked);
                      _load();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F8FA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.date_range_rounded, size: 16, color: GymiesColors.darkBlue),
                          const SizedBox(width: 4),
                          Text('Periode', style: GoogleFonts.sora(fontSize: 13, color: GymiesColors.darkBlue)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_range != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(rangeLabel, style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade600)),
                    ),
                    GestureDetector(
                      onTap: () {
                        Haptics.light();
                        setState(() {
                          _range = null;
                          _visibleItems = 20;
                        });
                        _load();
                      },
                      child: Text('Wis', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: GymiesColors.primary)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Transactielijst ──
        if (_filteredItems.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: TrainerEmptyState(
              icon: Icons.payments_outlined,
              title: 'Geen transacties',
              subtitle: _statusFilter == 'all'
                  ? 'Transacties verschijnen na bevestigde sessies.'
                  : 'Geen transacties met deze status.',
              actionLabel: 'Ververs',
              onAction: _load,
              padding: EdgeInsets.zero,
            ),
          )
        else
          ..._filteredItems.take(_visibleItems).map(
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _TransactionCard(
                item: i,
                resolvedStatus: _liveStatusByItemId[i.id] ?? i.paymentStatus ?? i.status,
                currencyFn: _currency,
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
                  _visibleItems = (_visibleItems + 20).clamp(20, _filteredItems.length);
                });
              },
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('Toon meer'),
            ),
          ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // TAB 2: FACTUREN
  // ══════════════════════════════════════════════════════════════

  Widget _buildInvoicesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Kwartaal ZIP export ──
        GestureDetector(
          onTap: _loadQuarterZip,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: GymiesColors.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.archive_outlined, size: 18, color: GymiesColors.darkBlue),
                const SizedBox(width: 8),
                Text(
                  'Kwartaal ZIP export',
                  style: GoogleFonts.sora(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (_invoices.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: TrainerEmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'Geen facturen',
              subtitle: 'Facturen worden automatisch aangemaakt bij voltooide sessies.',
              padding: EdgeInsets.zero,
            ),
          )
        else
          ..._invoices.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.receipt_outlined, size: 18, color: GymiesColors.darkBlue),
                  ),
                  title: Text(
                    mapStr(e, ['number', 'invoice_number']).isNotEmpty
                        ? mapStr(e, ['number', 'invoice_number'])
                        : 'Factuur',
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
                  ),
                  subtitle: Text(
                    mapStr(e, ['date', 'issued_at']).isNotEmpty
                        ? mapStr(e, ['date', 'issued_at'])
                        : '-',
                    style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  trailing: Text(
                    _currency(mapPick(e, ['total_cents', 'totalCents', 'total'])),
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ══════════════════════════════════════════════════════════════

/// Compacte stat card (Omzet / Ontvangen / Openstaand).
class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Icon(icon, size: 12, color: color),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Card wrapper met sectie-titel.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: GymiesColors.darkBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 14, color: GymiesColors.darkBlue),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── Week Chart (bar grafiek) ──

class _WeekBar {
  const _WeekBar({required this.label, required this.cents});
  final String label;
  final int cents;
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.bars, required this.currencyFn});
  final List<_WeekBar> bars;
  final String Function(dynamic) currencyFn;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return const SizedBox.shrink();
    final maxCents = bars.map((b) => b.cents).reduce(math.max);
    final safeMax = maxCents <= 0 ? 1 : maxCents;

    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars.asMap().entries.map((entry) {
          final bar = entry.value;
          final normalized = (bar.cents / safeMax).clamp(0.06, 1.0);
          final isHighest = bar.cents == maxCents && bar.cents > 0;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    currencyFn(bar.cents),
                    style: GoogleFonts.sora(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isHighest ? GymiesColors.darkBlue : Colors.grey.shade500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    height: 100 * normalized,
                    decoration: BoxDecoration(
                      color: isHighest ? GymiesColors.primary : GymiesColors.primary.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bar.label,
                    style: GoogleFonts.sora(fontSize: 10, color: Colors.grey.shade600),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Omzet breakdown bar ──

class _BreakdownBar extends StatelessWidget {
  const _BreakdownBar({
    required this.label,
    required this.cents,
    required this.total,
    required this.color,
    required this.currencyFn,
  });
  final String label;
  final int cents;
  final int total;
  final Color color;
  final String Function(dynamic) currencyFn;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (cents / total * 100) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
            Row(
              children: [
                Text('${pct.toStringAsFixed(0)}%', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                const SizedBox(width: 8),
                Text(currencyFn(cents), style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct / 100,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

// ── Transactie card ──

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.item,
    required this.resolvedStatus,
    required this.currencyFn,
  });
  final TrainerRevenueItem item;
  final String resolvedStatus;
  final String Function(dynamic) currencyFn;

  @override
  Widget build(BuildContext context) {
    final parsedDate = DateTime.tryParse(item.scheduledAt);
    final dateLabel = parsedDate != null
        ? '${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year}'
        : item.scheduledAt;
    final color = _statusColor(resolvedStatus);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(_statusIcon(resolvedStatus), size: 18, color: color),
        ),
        title: Text(
          dateLabel,
          style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _statusLabel(resolvedStatus),
              style: GoogleFonts.sora(fontSize: 11, color: color),
            ),
            if (_contextLabel(item).isNotEmpty)
              Text(
                _contextLabel(item),
                style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade600),
              ),
          ],
        ),
        trailing: Text(
          currencyFn(item.amountCents),
          style: GoogleFonts.sora(fontWeight: FontWeight.w700, fontSize: 14, color: GymiesColors.darkBlue),
        ),
      ),
    );
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'paid_mollie':
      case 'mollie_paid':
        return Icons.check_circle_rounded;
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

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'paid_mollie':
      case 'mollie_paid':
      case 'succeeded':
      case 'completed':
        return 'Ontvangen via Mollie';
      case 'cash':
      case 'paid_cash':
        return 'Contant ontvangen';
      case 'pending':
      case 'open':
      case 'unpaid':
        return 'Openstaand';
      case 'cancelled':
      case 'canceled':
        return 'Geannuleerd';
      case 'refunded':
        return 'Terugbetaald';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
      case 'paid_mollie':
      case 'mollie_paid':
      case 'succeeded':
      case 'completed':
        return Colors.green.shade700;
      case 'cash':
      case 'paid_cash':
        return Colors.teal.shade700;
      case 'pending':
      case 'open':
      case 'unpaid':
        return Colors.orange.shade700;
      case 'cancelled':
      case 'canceled':
      case 'refunded':
        return Colors.red.shade700;
      default:
        return GymiesColors.darkBlue;
    }
  }

  String _contextLabel(TrainerRevenueItem item) {
    final parts = <String>[];
    if ((item.paymentMethod ?? '').trim().isNotEmpty) {
      final method = item.paymentMethod!.trim().toLowerCase();
      parts.add(method == 'cash' ? 'Contant' : method == 'ideal' ? 'iDEAL' : method.toUpperCase());
    }
    if ((item.paymentReference ?? '').trim().isNotEmpty) {
      parts.add('Ref ${item.paymentReference}');
    }
    return parts.join(' · ');
  }
}
