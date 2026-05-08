import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/currency_format.dart';
import '../l10n/generated/app_localizations.dart';

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
  List<Map<String, dynamic>> _payoutInvoices = [];
  Map<String, dynamic> _forecast = {};
  int? _downloadingInvoiceId;

  // ── Payout request state ──
  bool _requestingPayout = false;
  bool _hasPendingPayout = false;
  Map<String, dynamic> _payoutBalance = {};

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
          } catch (e) {
            // Fail-open: Payout status resolution optional
            if (kDebugMode) debugPrint('[TrainerFinance] Resolve payout failed: $e');
          }
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

      // ── Sessie-facturen ──
      List<Map<String, dynamic>> invoices = [];
      try {
        invoices = await api.getTrainerInvoices();
      } catch (e) {
        if (kDebugMode) debugPrint('[Financiën] invoices fout: $e');
      }

      // ── Payout (self-billing) facturen ──
      List<Map<String, dynamic>> payoutInvoices = [];
      try {
        final res = await api.getPayoutInvoices();
        final raw = res['invoices'];
        if (raw is List) {
          payoutInvoices = raw.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Financiën] payout invoices fout: $e');
      }

      // ── Payout saldo + pending check ──
      Map<String, dynamic> payoutBalance = {};
      bool hasPending = false;
      try {
        payoutBalance = await api.getPayoutBalance();
        // Check of er al een pending payout request is
        final requests = await api.getPayoutRequests();
        hasPending = requests.any((r) => (r['status'] ?? '') == 'pending');
      } catch (e) {
        if (kDebugMode) debugPrint('[Financiën] payout balance fout: $e');
      }

      if (!mounted) return;
      setState(() {
        _revenue = revenue;
        _liveStatusByItemId = live;
        _forecast = forecast;
        _invoices = invoices;
        _payoutInvoices = payoutInvoices;
        _payoutBalance = payoutBalance;
        _hasPendingPayout = hasPending;
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
          _payoutInvoices = [];
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
        _payoutInvoices = [];
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
    return formatEuroAlways(cents);
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
          content: Text(url == null || url.isEmpty ? 'ZIP export gestart' : S.of(context).zipKlaarVoorDownload),
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
          tabs: const ['Overzicht', S.of(context).payouts],
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
    final sessiesCents = _toInt(revenueByType is Map ? (revenueByType[S.of(context).sessies]?['cents'] ?? revenueByType[S.of(context).sessies]?['amount'] ?? 0) : 0) ?? 0;
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
                label: S.of(context).ontvangen2,
                value: _currency(rev?.paidRevenueCents ?? 0),
                icon: Icons.check_circle_rounded,
                color: Colors.green.shade700,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: S.of(context).openstaand,
                value: _currency(rev?.pendingPayoutCents ?? 0),
                icon: Icons.schedule_rounded,
                color: Colors.orange.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Uitbetaling aanvragen knop ──
        _buildPayoutRequestCard(),
        const SizedBox(height: 16),

        // ── Weekgrafiek ──
        if (weekBars.isNotEmpty) ...[
          _SectionCard(
            icon: Icons.bar_chart_rounded,
            title: S.of(context).omzetDezeMaand,
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
                    label: S.of(context).sessionsCountLabel,
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
                    label: S.of(context).groepslessen,
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
          title: S.of(context).transacties,
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
                            DropdownMenuItem(value: 'all', child: Text(S.of(context).alleStatussen)),
                            DropdownMenuItem(value: 'paid', child: Text(S.of(context).betaaldonline)),
                            DropdownMenuItem(value: 'cash', child: Text(S.of(context).contant)),
                            DropdownMenuItem(value: 'open', child: Text(S.of(context).openstaand)),
                            DropdownMenuItem(value: 'cancelled', child: Text(S.of(context).geannuleerd)),
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
                      if (!mounted) return;
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
                          Text(S.of(context).periode, style: GoogleFonts.sora(fontSize: 13, color: GymiesColors.darkBlue)),
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
                      child: Text(S.of(context).wis, style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: GymiesColors.primary)),
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
              title: S.of(context).geenTransacties,
              subtitle: _statusFilter == 'all'
                  ? S.of(context).transactiesVerschijnenNaBevestigdeSessies
                  : S.of(context).geenTransactiesMetDezeStatus,
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
              label: const Text(S.of(context).toonMeer),
            ),
          ),

        const SizedBox(height: 24),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════
  // TAB 2: FACTUREN
  // ══════════════════════════════════════════════════════════════

  // ══════════════════════════════════════════════════════════════
  // PAYOUT REQUEST
  // ══════════════════════════════════════════════════════════════

  Widget _buildPayoutRequestCard() {
    final balanceCents = _toInt(_payoutBalance['balance_cents']) ?? 0;
    final frequency = (_payoutBalance['payout_frequency'] ?? 'monthly').toString();
    final mode = (_payoutBalance['payout_mode'] ?? 'gymies').toString();

    // Niet tonen als trainer eigen Mollie gebruikt
    if (mode != 'gymies') return const SizedBox.shrink();

    // Fee berekenen
    int feeCents = 0;
    if (frequency == 'daily') {
      feeCents = 149;
    } else if (frequency == 'weekly') {
      feeCents = 99;
    }
    final netCents = balanceCents - feeCents;
    final isEligible = netCents > 0 && balanceCents >= 500; // minimum €5

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_rounded, size: 20, color: GymiesColors.darkBlue),
              const SizedBox(width: 8),
              Text(
                'Uitbetaling',
                style: GoogleFonts.sora(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
              ),
              const Spacer(),
              if (_hasPendingPayout)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'In behandeling',
                    style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Beschikbaar saldo:', style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600)),
              const Spacer(),
              Text(
                _currency(balanceCents),
                style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
              ),
            ],
          ),
          if (feeCents > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Uitbetaalfee ($frequency):', style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade500)),
                const Spacer(),
                Text('- ${_currency(feeCents)}', style: GoogleFonts.sora(fontSize: 12, color: Colors.red.shade400)),
              ],
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (!isEligible || _hasPendingPayout || _requestingPayout)
                  ? null
                  : () => _showPayoutConfirmation(balanceCents, feeCents, netCents, frequency),
              style: ElevatedButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.grey.shade200,
                disabledForegroundColor: Colors.grey.shade500,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              icon: _requestingPayout
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _hasPendingPayout
                    ? 'Uitbetaling in behandeling'
                    : !isEligible
                        ? 'Minimum saldo niet bereikt (€5,00)'
                        : 'Uitbetaling aanvragen',
                style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (!_hasPendingPayout && isEligible) ...[
            const SizedBox(height: 6),
            Text(
              'Wordt de volgende werkdag op je rekening gestort',
              style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showPayoutConfirmation(int balanceCents, int feeCents, int netCents, String frequency) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.account_balance_rounded, color: GymiesColors.darkBlue, size: 22),
            const SizedBox(width: 8),
            Text('Uitbetaling bevestigen', style: GoogleFonts.sora(fontSize: 17, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _confirmRow('Saldo', _currency(balanceCents)),
            if (feeCents > 0) _confirmRow('Fee ($frequency)', '- ${_currency(feeCents)}'),
            const Divider(height: 20),
            _confirmRow('Netto uitbetaling', _currency(netCents), bold: true),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Het bedrag wordt de volgende werkdag op je IBAN gestort.',
                      style: GoogleFonts.sora(fontSize: 12, color: Colors.blue.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Annuleren', style: GoogleFonts.sora(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: GymiesColors.primary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text('Bevestigen', style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _requestingPayout = true);
    try {
      final api = context.read<GymiesApi>();
      await api.requestTrainerPayoutNow();
      Haptics.success();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uitbetaling van ${_currency(netCents)} aangevraagd!'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      _load(); // Refresh data
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Fout bij aanvragen uitbetaling. Probeer het opnieuw.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _requestingPayout = false);
    }
  }

  Widget _confirmRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.sora(fontSize: 14, color: Colors.grey.shade700)),
          Text(
            value,
            style: GoogleFonts.sora(
              fontSize: bold ? 16 : 14,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: GymiesColors.darkBlue,
            ),
          ),
        ],
      ),
    );
  }

  /// Download payout factuur PDF en deel via share sheet.
  Future<void> _downloadPayoutInvoice(Map<String, dynamic> inv) async {
    final id = inv['id'];
    if (id == null) return;
    final invoiceId = id is int ? id : int.tryParse(id.toString());
    if (invoiceId == null) return;

    setState(() => _downloadingInvoiceId = invoiceId);
    try {
      final api = context.read<GymiesApi>();
      final bytes = await api.downloadPayoutInvoiceBytes(invoiceId);

      // Opslaan in temp directory
      final dir = await getTemporaryDirectory();
      final invoiceNumber = (inv['invoice_number'] ?? 'factuur-$invoiceId').toString();
      // Detecteer of het HTML is (fallback) of PDF
      final isHtml = bytes.length > 5 &&
          (String.fromCharCodes(bytes.take(20)).trimLeft().startsWith('<!DOC') ||
           String.fromCharCodes(bytes.take(20)).trimLeft().startsWith('<html'));
      final ext = isHtml ? 'html' : 'pdf';
      final file = File('${dir.path}/$invoiceNumber.$ext');
      await file.writeAsBytes(bytes);

      if (!mounted) return;

      // Deel via share sheet (iOS/Android)
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'Factuur $invoiceNumber',
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download mislukt: $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _downloadingInvoiceId = null);
    }
  }

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
                  S.of(context).kwartaalZipExport,
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
        const SizedBox(height: 20),

        // ════════════════════════════════════════════════════
        // UITBETALINGSFACTUREN (self-billing payout invoices)
        // ════════════════════════════════════════════════════
        Text(
          'Uitbetalingsfacturen',
          style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
        ),
        const SizedBox(height: 4),
        Text(
          'Facturen van uitbetaalde bedragen door Gymies (self-billing).',
          style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),

        if (_payoutInvoices.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: TrainerEmptyState(
              icon: Icons.description_outlined,
              title: 'Nog geen uitbetalingsfacturen',
              subtitle: 'Zodra je een uitbetaling hebt ontvangen verschijnt hier de factuur.',
              padding: EdgeInsets.zero,
            ),
          )
        else
          ..._payoutInvoices.map((inv) {
            final invoiceId = inv['id'] is int ? inv['id'] as int : int.tryParse(inv['id']?.toString() ?? '') ?? 0;
            final isDownloading = _downloadingInvoiceId == invoiceId;
            final hasPdf = inv['has_pdf'] == true;
            final invoiceNumber = (inv['invoice_number'] ?? '').toString();
            final paidAt = (inv['paid_at'] ?? '').toString();
            final totalFormatted = (inv['net_amount_formatted'] ?? '').toString();
            final feeFormatted = (inv['fee_formatted'] ?? '').toString();
            final frequency = (inv['frequency'] ?? '').toString();

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2d8a4e).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined, size: 20, color: Color(0xFF2d8a4e)),
                  ),
                  title: Text(
                    invoiceNumber.isNotEmpty ? invoiceNumber : 'Factuur #$invoiceId',
                    style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (paidAt.isNotEmpty)
                        Text(paidAt, style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade600)),
                      Row(
                        children: [
                          Text(totalFormatted, style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF2d8a4e))),
                          if (feeFormatted.isNotEmpty && feeFormatted != '€0,00') ...[
                            const SizedBox(width: 6),
                            Text('fee: $feeFormatted', style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500)),
                          ],
                          if (frequency.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: GymiesColors.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                frequency == 'monthly' ? 'maandelijks' : frequency == 'weekly' ? 'wekelijks' : frequency == 'daily' ? 'dagelijks' : frequency,
                                style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  trailing: hasPdf
                      ? IconButton(
                          onPressed: isDownloading ? null : () => _downloadPayoutInvoice(inv),
                          icon: isDownloading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download_rounded, color: GymiesColors.darkBlue),
                          tooltip: 'Download PDF',
                        )
                      : const Icon(Icons.hourglass_empty_rounded, size: 18, color: Colors.grey),
                ),
              ),
            );
          }),

        const SizedBox(height: 24),

        // ════════════════════════════════════════════════════
        // SESSIE-FACTUREN (trainer → client invoices)
        // ════════════════════════════════════════════════════
        Text(
          'Sessiefacturen',
          style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
        ),
        const SizedBox(height: 4),
        Text(
          'Facturen voor voltooide sessies.',
          style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),

        if (_invoices.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: TrainerEmptyState(
              icon: Icons.receipt_long_rounded,
              title: S.of(context).geenFacturen,
              subtitle: S.of(context).facturenWordenAutomatischAangemaaktBijVoltooide,
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
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: GymiesColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.receipt_outlined, size: 18, color: GymiesColors.darkBlue),
                  ),
                  title: Text(
                    mapStr(e, ['number', 'invoice_number']).isNotEmpty
                        ? mapStr(e, ['number', 'invoice_number'])
                        : S.of(context).factuur2,
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
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
                  color: GymiesColors.darkBlue.withOpacity(0.1),
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
                      color: isHighest ? GymiesColors.primary : GymiesColors.primary.withOpacity(0.4),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
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
        return S.of(context).openstaand;
      case 'cancelled':
      case 'canceled':
        return S.of(context).geannuleerd;
      case 'refunded':
        return S.of(context).terugbetaald;
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
      parts.add(method == 'cash' ? S.of(context).contant : method == 'ideal' ? 'iDEAL' : method.toUpperCase());
    }
    if ((item.paymentReference ?? '').trim().isNotEmpty) {
      parts.add('Ref ${item.paymentReference}');
    }
    return parts.join(' · ');
  }
}
