import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_upgrade_prompt.dart';
import 'widgets/trainer_state_views.dart';

/// Klant Analytics – Pro+ trainers zien een overzicht van klantactiviteit:
/// actieve, risico- en inactieve klanten met sessie- en omzetdata.
class TrainerClientAnalyticsScreen extends StatefulWidget {
  const TrainerClientAnalyticsScreen({super.key});

  @override
  State<TrainerClientAnalyticsScreen> createState() =>
      _TrainerClientAnalyticsScreenState();
}

class _TrainerClientAnalyticsScreenState
    extends State<TrainerClientAnalyticsScreen> {
  bool _loading = true;
  String? _error;

  // Summary data
  int _activeCount = 0;
  int _riskCount = 0;
  int _inactiveCount = 0;
  double _totalRevenue = 0;
  int _totalSessions = 0;

  // Client list
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _filteredClients = [];

  // Filter
  String _activeFilter = 'all'; // all, active, risk, inactive

  // Pro+ Features
  String _trendPeriod = '30d'; // 7d, 30d, 90d, all
  Map<String, dynamic> _trends = {};
  Map<String, dynamic> _revenueBreakdown = {};
  List<Map<String, dynamic>> _topClients = [];
  bool _exporting = false;

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
      final data = await api.getClientAnalytics();
      if (!mounted) return;

      // Parse summary
      final summary = data['summary'] as Map<String, dynamic>? ?? {};

      // Parse clients list
      final clientsRaw = data['clients'];
      final clients = (clientsRaw is List)
          ? List<Map<String, dynamic>>.from(
              clientsRaw.map((c) => c is Map<String, dynamic>
                  ? c
                  : (c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{})),
            )
          : <Map<String, dynamic>>[];

      // Parse Pro+ features
      final trends = data['trends'] as Map<String, dynamic>? ?? {};
      final revenueBreakdown = data['revenue_breakdown'] as Map<String, dynamic>? ?? {};
      final topClientsRaw = data['top_clients'] as List? ?? [];
      final topClients = List<Map<String, dynamic>>.from(
        topClientsRaw.map((c) => c is Map<String, dynamic>
            ? c
            : (c is Map ? Map<String, dynamic>.from(c) : <String, dynamic>{})),
      );

      setState(() {
        _activeCount = (summary['active'] as num?)?.toInt() ??
            (summary['active_count'] as num?)?.toInt() ??
            0;
        _riskCount = (summary['risk'] as num?)?.toInt() ??
            (summary['risk_count'] as num?)?.toInt() ??
            (summary['at_risk'] as num?)?.toInt() ??
            0;
        _inactiveCount = (summary['inactive'] as num?)?.toInt() ??
            (summary['inactive_count'] as num?)?.toInt() ??
            0;
        _totalRevenue = (summary['total_revenue'] as num?)?.toDouble() ??
            (summary['revenue'] as num?)?.toDouble() ??
            0;
        _totalSessions = (summary['total_sessions'] as num?)?.toInt() ??
            (summary['sessions'] as num?)?.toInt() ??
            0;
        _clients = clients;
        _trends = trends;
        _revenueBreakdown = revenueBreakdown;
        _topClients = topClients;
        _applyFilter();
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
        _error = S.of(context).konKlantAnalyticsNietLaden;
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    if (_activeFilter == 'all') {
      _filteredClients = List.from(_clients);
    } else {
      _filteredClients = _clients.where((c) {
        final status = mapStr(c, ['status', 'client_status']).toLowerCase();
        if (_activeFilter == 'active') return status == 'active' || status == S.of(context).actiefLower;
        if (_activeFilter == 'risk') {
          return status == 'risk' || status == 'at_risk' || status == 'risico';
        }
        if (_activeFilter == 'inactive') {
          return status == 'inactive' || status == S.of(context).inactiefLower;
        }
        return true;
      }).toList();
    }
  }

  void _setFilter(String filter) {
    Haptics.selection();
    setState(() {
      _activeFilter = filter;
      _applyFilter();
    });
  }

  void _setTrendPeriod(String period) {
    Haptics.selection();
    setState(() {
      _trendPeriod = period;
    });
  }

  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final api = context.read<GymiesApi>();
      // ignore: unused_local_variable
      final csv = await api.exportClientAnalyticsCsv();
      if (!mounted) return;

      // Show success snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(S.of(context).csvGexporteerd),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
        ),
      );
      Haptics.success();
    } catch (e) {
      if (!mounted) return;
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).exportMisluktMsg(e.toString())),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s == 'active' || s == S.of(context).actiefLower) return Colors.green.shade700;
    if (s == 'risk' || s == 'at_risk' || s == 'risico') {
      return Colors.orange.shade800;
    }
    return Colors.red.shade700;
  }

  String _statusLabel(String status) {
    final s = status.toLowerCase();
    if (s == 'active' || s == S.of(context).actiefLower) return S.of(context).actief;
    if (s == 'risk' || s == 'at_risk' || s == 'risico') return 'Risico';
    if (s == 'inactive' || s == S.of(context).inactiefLower) return S.of(context).inactief;
    return status;
  }

  @override
  Widget build(BuildContext context) {
    final ent = context.watch<SubscriptionEntitlementsService>();
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isProPlus = tierLower.contains('pro_plus') ||
        tierLower.contains('proplus') ||
        tierLower == 'studio';

    if (!isProPlus) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: const GymiesAppBar(title: S.of(context).klantAnalytics2),
        body: const GymiesUpgradePrompt(
          icon: Icons.analytics_outlined,
          feature: S.of(context).klantAnalytics2,
          tier: 'Pro+',
          description: S.of(context).bekijkTrendsOmzetverdelingEnExporteerData,
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: S.of(context).klantAnalytics2,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.download_rounded, size: 20),
              color: Colors.white,
              onPressed: _exporting ? null : _exportCsv,
              tooltip: 'Exporteer CSV',
              padding: EdgeInsets.zero,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: ['7d', '30d', '90d', S.of(context).allLabel].map((label) {
                final value = label == S.of(context).allLabel ? 'all' : label;
                final selected = _trendPeriod == value;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _setTrendPeriod(value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? GymiesColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          label,
                          style: GoogleFonts.sora(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected
                                ? GymiesColors.darkBlue
                                : Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ── Summary Cards ─────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryCard(
                              label: S.of(context).actief,
                              value: '$_activeCount',
                              color: Colors.green.shade700,
                              icon: Icons.person_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SummaryCard(
                              label: 'Risico',
                              value: '$_riskCount',
                              color: Colors.orange.shade800,
                              icon: Icons.warning_amber_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SummaryCard(
                              label: S.of(context).inactief,
                              value: '$_inactiveCount',
                              color: Colors.red.shade700,
                              icon: Icons.person_off_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryCard(
                              label: S.of(context).sessionsCountLabel,
                              value: '$_totalSessions',
                              color: GymiesColors.darkBlue,
                              icon: Icons.fitness_center_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SummaryCard(
                              label: 'Omzet',
                              value: '€${_totalRevenue.toStringAsFixed(0)}',
                              color: GymiesColors.darkBlue,
                              icon: Icons.euro_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // ── Trends Section ───────────────────────────
                      if (_trends.isNotEmpty)
                        _buildTrendsSection(),

                      // ── Revenue Breakdown ────────────────────────
                      if (_revenueBreakdown.isNotEmpty)
                        _buildRevenueBreakdownSection(),

                      // ── Top Clients ──────────────────────────────
                      if (_topClients.isNotEmpty)
                        _buildTopClientsSection(),

                      // ── Filter Chips ──────────────────────────────
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip('Alle', 'all'),
                            const SizedBox(width: 8),
                            _filterChip(S.of(context).actief, 'active'),
                            const SizedBox(width: 8),
                            _filterChip('Risico', 'risk'),
                            const SizedBox(width: 8),
                            _filterChip(S.of(context).inactief, 'inactive'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Client count ──────────────────────────────
                      Text(
                        '${_filteredClients.length} klant${_filteredClients.length == 1 ? '' : 'en'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ── Client List ───────────────────────────────
                      if (_filteredClients.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              S.of(context).geenKlantenGevondenVoorDitFilter,
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      else
                        ..._filteredClients.map((client) {
                          final name =
                              mapStr(client, ['name', 'client_name', 'full_name']);
                          final status =
                              mapStr(client, ['status', 'client_status']);
                          final sessions =
                              mapInt(client, ['session_count', 'sessions', 'total_sessions']);
                          final revenue = (client['revenue'] as num?)?.toDouble() ??
                              (client['total_revenue'] as num?)?.toDouble() ??
                              0;
                          final lastSession =
                              mapStr(client, ['last_session_at', 'last_session', 'lastSessionAt']);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // Status indicator
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: _statusColor(status)
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: _statusColor(status),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Client info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                name.isNotEmpty ? name : S.of(context).clientSingle,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _statusColor(status)
                                                    .withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                _statusLabel(status),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: _statusColor(status),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$sessions sessies · €${revenue.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        if (lastSession.isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              'Laatst: $lastSession',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 32),
                    ],
                  ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _activeFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setFilter(value),
      selectedColor: GymiesColors.primary.withOpacity(0.25),
      checkmarkColor: GymiesColors.darkBlue,
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? GymiesColors.darkBlue : Colors.grey.shade700,
        fontSize: 13,
      ),
      side: BorderSide(
        color: selected ? GymiesColors.primary : Colors.grey.shade300,
      ),
    );
  }

  Widget _buildTrendsSection() {
    final newCustomers = ((_trends['new_customers'] as num?)?.toInt() ?? 0);
    final prevNewCustomers = ((_trends['prev_customers'] as num?)?.toInt() ?? 0);
    final newCustomersDelta = newCustomers - prevNewCustomers;

    final sessions = ((_trends['sessions'] as num?)?.toInt() ?? 0);
    final prevSessions = ((_trends['prev_sessions'] as num?)?.toInt() ?? 0);
    final sessionsDelta = sessions - prevSessions;

    final revenue = ((_trends['revenue'] as num?)?.toDouble() ?? 0);
    final prevRevenue = ((_trends['prev_revenue'] as num?)?.toDouble() ?? 0);
    final revenueDelta = revenue - prevRevenue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: GymiesColors.darkBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.trending_up_rounded, size: 16, color: GymiesColors.darkBlue),
            ),
            const SizedBox(width: 10),
            Text(
              S.of(context).trends,
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TrendCard(
                label: S.of(context).nieuweKlanten,
                value: '$newCustomers',
                delta: newCustomersDelta,
                icon: Icons.person_add_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TrendCard(
                label: S.of(context).sessionsCountLabel,
                value: '$sessions',
                delta: sessionsDelta,
                icon: Icons.fitness_center_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TrendCard(
                label: 'Omzet',
                value: '€${revenue.toStringAsFixed(0)}',
                delta: revenueDelta,
                icon: Icons.euro_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildRevenueBreakdownSection() {
    final total = _revenueBreakdown.values
        .map((v) => (v as num?)?.toDouble() ?? 0)
        .fold(0.0, (a, b) => a + b);

    if (total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.green.shade700.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.pie_chart_rounded, size: 16, color: Colors.green.shade700),
            ),
            const SizedBox(width: 10),
            Text(
              S.of(context).omzetVerdeling,
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _revenueBreakdown.entries.map((entry) {
                final category = entry.key;
                final value = (entry.value as num?)?.toDouble() ?? 0;
                final percentage = (value / total * 100).toStringAsFixed(1);
                final colors = [
                  GymiesColors.darkBlue,
                  Colors.green.shade700,
                  Colors.orange.shade800,
                ];
                final colorIndex =
                    _revenueBreakdown.keys.toList().indexOf(category) %
                        colors.length;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            category,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            '$percentage%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors[colorIndex],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: value / total,
                          minHeight: 8,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colors[colorIndex],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildTopClientsSection() {
    final maxRevenue = _topClients
        .map((c) => (c['revenue'] as num?)?.toDouble() ?? 0)
        .fold(0.0, (a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: GymiesColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.emoji_events_rounded, size: 16, color: GymiesColors.darkBlue),
            ),
            const SizedBox(width: 10),
            Text(
              S.of(context).topKlanten,
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._topClients.asMap().entries.map((entry) {
          final idx = entry.key;
          final client = entry.value;
          final name = mapStr(client, ['name', 'client_name', 'full_name']);
          final sessions =
              mapInt(client, ['session_count', 'sessions', 'total_sessions']);
          final revenue = (client['revenue'] as num?)?.toDouble() ?? 0;
          final progress = maxRevenue > 0 ? revenue / maxRevenue : 0;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: GymiesColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${idx + 1}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isNotEmpty ? name : S.of(context).clientSingle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$sessions sessies · €${revenue.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress.toDouble(),
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          GymiesColors.darkBlue,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(icon, color: color, size: 13),
                ),
                const SizedBox(width: 8),
                Text(
                  value,
                  style: GoogleFonts.sora(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.label,
    required this.value,
    required this.delta,
    required this.icon,
  });

  final String label;
  final String value;
  final num delta;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isPositive = delta >= 0;
    final deltaColor = isPositive ? Colors.green.shade700 : Colors.red.shade700;
    final deltaSign = isPositive ? '+' : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: GymiesColors.darkBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: GymiesColors.darkBlue, size: 15),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: deltaColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                        size: 10,
                        color: deltaColor,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '$deltaSign$delta',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: deltaColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.sora(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
