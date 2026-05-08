import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/haptics.dart';
import 'gym_locations_screen.dart';
import 'gym_churn_report_screen.dart';
import 'shells/gym_shell.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';
import '../l10n/generated/app_localizations.dart';

/// Gym (Elite) dashboard – startpunt voor gym-beheerders.
/// Toont KPI's, recente activiteit, omzet, bezetting en snelle acties.
class GymDashboardScreen extends StatefulWidget {
  const GymDashboardScreen({
    super.key,
    this.onTrainersTap,
    this.onBookingsTap,
    this.onClientsTap,
  });

  final VoidCallback? onTrainersTap;
  final VoidCallback? onBookingsTap;
  final VoidCallback? onClientsTap;

  @override
  State<GymDashboardScreen> createState() => _GymDashboardScreenState();
}

class _GymDashboardScreenState extends State<GymDashboardScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _stats = {};
  Map<String, dynamic> _dashboardData = {};
  List<Map<String, dynamic>> _recentBookings = [];

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

      // Graceful degradation: elke call apart zodat partial failures OK zijn
      Map<String, dynamic> dashboardData = {};
      Map<String, dynamic> stats = {};
      List<Map<String, dynamic>> recentBookings = [];

      try {
        dashboardData = await api.getGymDashboard();
      } catch (e) {
        if (kDebugMode) debugPrint('[GymDashboard] Dashboard data laden mislukt: $e');
      }

      try {
        stats = await api.getGymDashboardStats();
      } catch (e) {
        if (kDebugMode) debugPrint('[GymDashboard] Stats laden mislukt: $e');
      }

      // Recente boekingen voor activiteit feed (max 5)
      try {
        final all = await api.getGymBookings();
        recentBookings = all.take(5).toList();
      } catch (e) {
        if (kDebugMode) debugPrint('[GymDashboard] Recente boekingen laden mislukt: $e');
      }

      if (!mounted) return;
      setState(() {
        _dashboardData = dashboardData;
        _stats = stats;
        _recentBookings = recentBookings;
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
        _error = S.of(context).konGymdashboardNietLaden;
        _loading = false;
      });
    }
  }

  String _gymName() {
    final fromDashboard = mapStr(
      _dashboardData,
      ['name', 'gym_name', 'display_name'],
    );
    if (fromDashboard.isNotEmpty) return fromDashboard;
    final user = context.read<AuthService>().user ?? {};
    return mapStr(user, ['name', 'display_name', 'email']);
  }

  String _todayLabel() {
    final now = DateTime.now();
    final l10n = S.of(context);
    const days = [
      'Maandag', 'Dinsdag', 'Woensdag', 'Donderdag',
      'Vrijdag', 'Zaterdag', 'Zondag',
    ];
    const months = [
      'januari', 'februari', 'maart', 'april', 'mei', 'juni',
      'juli', 'augustus', 'september', 'oktober', 'november', 'december',
    ];
    return '${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]}';
  }

  String? _orgId() {
    final user = context.read<AuthService>().user ?? {};
    final orgId = user['organisation_id']?.toString();
    return (orgId != null && orgId.isNotEmpty && orgId != 'null') ? orgId : null;
  }

  String? _gymId() {
    // gymId kan uit dashboard data komen of uit user
    final fromDashboard = _dashboardData['gym_id']?.toString() ??
        _dashboardData['id']?.toString();
    if (fromDashboard != null && fromDashboard.isNotEmpty && fromDashboard != 'null') {
      return fromDashboard;
    }
    return _orgId();
  }

  void _openLocations() {
    final orgId = _orgId();
    if (orgId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).geenOrganisatieGevonden),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GymLocationsScreen(
        orgId: orgId,
        orgName: _gymName(),
      ),
    ));
  }

  void _openChurnReport() {
    final gymId = _gymId();
    if (gymId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).geenOrganisatieGevonden),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GymChurnReportScreen(
        gymId: gymId,
        gymName: _gymName(),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(title: S.of(context).dashboard),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: RefreshIndicator(
          onRefresh: _load,
          color: GymiesColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header ──────────────────────────────────────────────
                Container(
                  decoration: const BoxDecoration(
                    color: GymiesColors.darkBlue,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _gymName().isNotEmpty ? _gymName() : 'Gym Dashboard',
                                  style: GoogleFonts.sora(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _todayLabel(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Welkomst avatar
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: GymiesColors.primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.fitness_center_rounded,
                              color: GymiesColors.primary,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── KPI Stat grid ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              icon: Icons.people_rounded,
                              label: S.of(context).trainers,
                              value: '${mapInt(_stats, ['trainers_count', 'trainers'])}',
                              trend: _trendValue('trainers_trend'),
                              accentColor: Colors.indigo.shade400,
                              backgroundColor: Colors.indigo.shade50,
                              onTap: widget.onTrainersTap,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatCard(
                              icon: Icons.person_rounded,
                              label: S.of(context).klanten,
                              value: '${mapInt(_stats, ['clients_count', 'clients'])}',
                              trend: _trendValue('clients_trend'),
                              accentColor: Colors.green.shade600,
                              backgroundColor: Colors.green.shade50,
                              onTap: widget.onClientsTap,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              icon: Icons.event_available_rounded,
                              label: S.of(context).bookings,
                              value: '${mapInt(_stats, ['bookings_count', 'bookings'])}',
                              trend: _trendValue('bookings_trend'),
                              accentColor: Colors.amber.shade700,
                              backgroundColor: Colors.amber.shade50,
                              onTap: widget.onBookingsTap,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatCard(
                              icon: Icons.today_rounded,
                              label: S.of(context).vandaag,
                              value: '${mapInt(_stats, ['today_bookings', 'bookings_today', 'today'])}',
                              accentColor: GymiesColors.primary,
                              backgroundColor: GymiesColors.primary.withOpacity(0.1),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Omzet + Bezetting ─────────────────────────────────
                if (_hasRevenueOrOccupancy()) ...[
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        if (_stats['revenue_mtd'] != null)
                          Expanded(child: _RevenueCard(stats: _stats)),
                        if (_stats['revenue_mtd'] != null && _stats['occupancy_rate'] != null)
                          const SizedBox(width: 10),
                        if (_stats['occupancy_rate'] != null)
                          Expanded(child: _OccupancyCard(stats: _stats)),
                      ],
                    ),
                  ),
                ],

                // ── Snelle acties ────────────────────────────────────────
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    S.of(context).snelleActies,
                    style: GoogleFonts.sora(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: GymiesColors.darkBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.location_on_rounded,
                          label: S.of(context).locaties,
                          color: Colors.blue.shade600,
                          onTap: _openLocations,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.trending_down_rounded,
                          label: S.of(context).churnRapport,
                          color: Colors.red.shade400,
                          onTap: _openChurnReport,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickActionCard(
                          icon: Icons.settings_rounded,
                          label: S.of(context).instellingen,
                          color: Colors.grey.shade600,
                          onTap: () {
                            // Navigeer naar instellingen tab (index 4)
                            context.gymShell?.jumpToTab(4);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Recente activiteit ───────────────────────────────────
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        S.of(context).recenteActiviteit,
                        style: GoogleFonts.sora(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: GymiesColors.darkBlue,
                        ),
                      ),
                      if (_recentBookings.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            Haptics.selection();
                            widget.onBookingsTap?.call();
                          },
                          child: Text(
                            S.of(context).bekijkAlles,
                            style: TextStyle(
                              fontSize: 13,
                              color: GymiesColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_recentBookings.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.event_note_rounded, size: 40, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            S.of(context).geenRecenteActiviteit,
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        children: [
                          for (int i = 0; i < _recentBookings.length; i++) ...[
                            _RecentBookingTile(booking: _recentBookings[i]),
                            if (i < _recentBookings.length - 1)
                              Divider(height: 1, color: Colors.grey.shade100),
                          ],
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _hasRevenueOrOccupancy() {
    return _stats['revenue_mtd'] != null || _stats['occupancy_rate'] != null;
  }

  /// Pakt trendwaarde uit stats als die beschikbaar is.
  double? _trendValue(String key) {
    final v = _stats[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final parsed = double.tryParse(v.toString());
    return parsed;
  }
}

// ── Snelle actie card ─────────────────────────────────────────────────
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          Haptics.selection();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Omzet card ──────────────────────────────────────────────────────
class _RevenueCard extends StatelessWidget {
  const _RevenueCard({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final revenue = (stats['revenue_mtd'] is num)
        ? (stats['revenue_mtd'] as num).toDouble()
        : double.tryParse(stats['revenue_mtd']?.toString() ?? '') ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.euro_rounded, color: Colors.green.shade600, size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                S.of(context).omzetMtd,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '€ ${revenue.toStringAsFixed(0)}',
            style: GoogleFonts.sora(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: GymiesColors.darkBlue,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bezettingsgraad card ────────────────────────────────────────────
class _OccupancyCard extends StatelessWidget {
  const _OccupancyCard({required this.stats});
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final occupancy = (stats['occupancy_rate'] is num)
        ? (stats['occupancy_rate'] as num).toDouble()
        : double.tryParse(stats['occupancy_rate']?.toString() ?? '') ?? 0.0;
    final clamped = occupancy.clamp(0.0, 100.0);
    final color = clamped > 75
        ? Colors.green.shade600
        : clamped > 50
            ? Colors.amber.shade700
            : Colors.red.shade400;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.show_chart_rounded, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  S.of(context).bezetting,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${clamped.toStringAsFixed(0)}%',
            style: GoogleFonts.sora(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: GymiesColors.darkBlue,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: clamped / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat card met optionele trend ────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
    required this.backgroundColor,
    this.onTap,
    this.trend,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final double? trend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap != null
            ? () {
                Haptics.selection();
                onTap!();
              }
            : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accentColor, size: 20),
                  ),
                  if (trend != null) _TrendBadge(trend: trend!),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: GoogleFonts.sora(
                  fontSize: 26,
                  color: GymiesColors.darkBlue,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      S.of(context).bekijk,
                      style: TextStyle(
                        fontSize: 12,
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: accentColor),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Trend badge (pijl omhoog/omlaag met percentage) ─────────────────
class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});
  final double trend;

  @override
  Widget build(BuildContext context) {
    final isUp = trend >= 0;
    final color = isUp ? Colors.green.shade600 : Colors.red.shade500;
    final bgColor = isUp ? Colors.green.shade50 : Colors.red.shade50;
    final icon = isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 2),
          Text(
            '${trend.abs().toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Recente boeking tile ────────────────────────────────────────────
class _RecentBookingTile extends StatelessWidget {
  const _RecentBookingTile({required this.booking});
  final Map<String, dynamic> booking;

  @override
  Widget build(BuildContext context) {
    final clientName = mapStr(booking, ['client_name', 'client']);
    final trainerName = mapStr(booking, ['trainer_name', 'trainer']);
    final status = mapStr(booking, ['status']).toLowerCase();
    final rawDate = mapStr(booking, ['scheduled_at', 'scheduledAt', 'date']);
    final dt = DateTime.tryParse(rawDate);
    final timeStr = dt != null
        ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'confirmed':
      case 'bevestigd':
        statusColor = Colors.green.shade600;
        statusLabel = S.of(context).bevestigd;
        break;
      case 'pending':
      case 'in_afwachting':
        statusColor = Colors.amber.shade700;
        statusLabel = S.of(context).inAfwachting;
        break;
      case 'cancelled':
      case 'geannuleerd':
        statusColor = Colors.red.shade500;
        statusLabel = S.of(context).geannuleerd;
        break;
      case 'completed':
      case 'afgerond':
        statusColor = Colors.blue.shade600;
        statusLabel = S.of(context).afgerond;
        break;
      default:
        statusColor = Colors.grey.shade500;
        statusLabel = status.isNotEmpty ? status : '-';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Tijd indicator
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: GymiesColors.darkBlue.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              timeStr.isNotEmpty ? timeStr : '--:--',
              textAlign: TextAlign.center,
              style: GoogleFonts.sora(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: GymiesColors.darkBlue,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Namen
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  clientName.isNotEmpty ? clientName : '-',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: GymiesColors.darkBlue,
                  ),
                ),
                if (trainerName.isNotEmpty)
                  Text(
                    '${S.of(context).bij} $trainerName',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
