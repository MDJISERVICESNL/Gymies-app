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
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

/// Gym (Elite) dashboard – startpunt voor gym-beheerders.
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
      dynamic dashboardData;
      dynamic stats;

      try {
        dashboardData = await api.getGymDashboard();
      } catch (e) {
        if (kDebugMode) debugPrint('[GymDashboard] Dashboard data laden mislukt: $e');
        dashboardData = <String, dynamic>{};
      }

      try {
        stats = await api.getGymDashboardStats();
      } catch (e) {
        if (kDebugMode) debugPrint('[GymDashboard] Stats laden mislukt: $e');
        stats = <String, dynamic>{};
      }

      if (!mounted) return;
      setState(() {
        _dashboardData = dashboardData;
        _stats = stats;
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
        _error = 'Kon gym-dashboard niet laden.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: const GymiesAppBar(title: 'Dashboard'),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────
            Container(
              color: GymiesColors.darkBlue,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _gymName().isNotEmpty ? _gymName() : 'Gym Dashboard',
                    style: GoogleFonts.sora(
                      fontSize: 26,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _todayLabel(),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),

            // ── Stat grid ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.people_rounded,
                          label: 'Trainers',
                          value: '${mapInt(_stats, ['trainers_count', 'trainers'])}',
                          accentColor: Colors.indigo.shade400,
                          backgroundColor: Colors.indigo.shade50,
                          onTap: widget.onTrainersTap,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.person_rounded,
                          label: 'Klanten',
                          value: '${mapInt(_stats, ['clients_count', 'clients'])}',
                          accentColor: Colors.green.shade600,
                          backgroundColor: Colors.green.shade50,
                          onTap: widget.onClientsTap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          icon: Icons.event_available_rounded,
                          label: 'Boekingen',
                          value: '${mapInt(_stats, ['bookings_count', 'bookings'])}',
                          accentColor: Colors.amber.shade700,
                          backgroundColor: Colors.amber.shade50,
                          onTap: widget.onBookingsTap,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          icon: Icons.today_rounded,
                          label: 'Vandaag',
                          value: '${mapInt(_stats, ['today_bookings', 'bookings_today', 'today'])}',
                          accentColor: GymiesColors.primary,
                          backgroundColor: GymiesColors.primary.withValues(alpha: 0.1),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
    required this.backgroundColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;
  final Color backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap != null ? () {
          Haptics.selection();
          onTap!();
        } : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: GoogleFonts.sora(
                  fontSize: 28,
                  color: GymiesColors.darkBlue,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Bekijk',
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
