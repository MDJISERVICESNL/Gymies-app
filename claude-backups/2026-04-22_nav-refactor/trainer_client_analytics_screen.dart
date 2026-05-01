import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
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
        _error = 'Kon klant analytics niet laden.';
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
        if (_activeFilter == 'active') return status == 'active' || status == 'actief';
        if (_activeFilter == 'risk') {
          return status == 'risk' || status == 'at_risk' || status == 'risico';
        }
        if (_activeFilter == 'inactive') {
          return status == 'inactive' || status == 'inactief';
        }
        return true;
      }).toList();
    }
  }

  void _setFilter(String filter) {
    setState(() {
      _activeFilter = filter;
      _applyFilter();
    });
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s == 'active' || s == 'actief') return Colors.green.shade700;
    if (s == 'risk' || s == 'at_risk' || s == 'risico') {
      return Colors.orange.shade800;
    }
    return Colors.red.shade700;
  }

  String _statusLabel(String status) {
    final s = status.toLowerCase();
    if (s == 'active' || s == 'actief') return 'Actief';
    if (s == 'risk' || s == 'at_risk' || s == 'risico') return 'Risico';
    if (s == 'inactive' || s == 'inactief') return 'Inactief';
    return status;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(title: 'Klant Analytics'),
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
                              label: 'Actief',
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
                              label: 'Inactief',
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
                              label: 'Sessies',
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

                      // ── Filter Chips ──────────────────────────────
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip('Alle', 'all'),
                            const SizedBox(width: 8),
                            _filterChip('Actief', 'active'),
                            const SizedBox(width: 8),
                            _filterChip('Risico', 'risk'),
                            const SizedBox(width: 8),
                            _filterChip('Inactief', 'inactive'),
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
                              'Geen klanten gevonden voor dit filter.',
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

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
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
                                          .withValues(alpha: 0.12),
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
                                                name.isNotEmpty ? name : 'Klant',
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
                                                    .withValues(alpha: 0.12),
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
      selectedColor: GymiesColors.primary.withValues(alpha: 0.25),
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
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.fjallaOne(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
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
