import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';

/// Live activity heatmap — OpenStreetMap met gekleurde cirkels per regio.
/// Drukte-score: groen (rustig) → oranje → rood → paars (piek).
/// Auto-refresh elke 60 seconden.
/// Gebruikt flutter_map + OpenStreetMap — gratis, geen API key nodig.
class StaffActivityHeatmapScreen extends StatefulWidget {
  const StaffActivityHeatmapScreen({super.key});

  @override
  State<StaffActivityHeatmapScreen> createState() => _StaffActivityHeatmapScreenState();
}

class _StaffActivityHeatmapScreenState extends State<StaffActivityHeatmapScreen>
    with SingleTickerProviderStateMixin {

  final MapController _mapController = MapController();
  Timer? _refreshTimer;
  late AnimationController _pulseController;

  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _regions = [];
  bool _loading = true;
  String? _error;

  // Nederland center
  static final LatLng _nlCenter = LatLng(52.1326, 5.2913);

  // Color scale
  static const Color _greenColor  = Color(0xFF4CAF50);
  static const Color _orangeColor = Color(0xFFFF9800);
  static const Color _redColor    = Color(0xFFF44336);
  static const Color _purpleColor = Color(0xFF9C27B0);
  static const Color _grayColor   = Color(0xFF9E9E9E);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadData());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getActivityHeatmap();
      if (!mounted) return;
      final rawRegions = res['regions'];
      final regionsList = <Map<String, dynamic>>[];
      if (rawRegions is List) {
        for (final r in rawRegions) {
          if (r is Map) regionsList.add(Map<String, dynamic>.from(r));
        }
      }
      setState(() {
        _data = res;
        _regions = regionsList;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Color _scoreToColor(double score) {
    if (score > 0.75) return _purpleColor;
    if (score > 0.50) return _redColor;
    if (score > 0.25) return _orangeColor;
    return _greenColor;
  }

  String _scoreToDutchLabel(double score) {
    if (score > 0.75) return 'Piek';
    if (score > 0.50) return 'Druk';
    if (score > 0.25) return 'Beetje druk';
    return 'Rustig';
  }

  IconData _scoreToIcon(double score) {
    if (score > 0.75) return Icons.whatshot;
    if (score > 0.50) return Icons.local_fire_department;
    if (score > 0.25) return Icons.trending_up;
    return Icons.check_circle_outline;
  }

  List<CircleMarker> _buildCircles() {
    final circles = <CircleMarker>[];
    for (final region in _regions) {
      final lat = (region['latitude'] as num?)?.toDouble();
      final lng = (region['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final score = (region['current_score'] as num?)?.toDouble() ?? 0.0;
      final color = region['status'] == 'closed' ? _grayColor : _scoreToColor(score);
      final radius = _scoreToRadius(score);

      circles.add(CircleMarker(
        point: LatLng(lat, lng),
        radius: radius,
        useRadiusInMeter: true,
        color: color.withOpacity(0.35),
        borderColor: color.withOpacity(0.8),
        borderStrokeWidth: 3,
      ));
    }
    return circles;
  }

  double _scoreToRadius(double score) {
    return 4000 + (score * 8000);
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    for (final region in _regions) {
      final lat = (region['latitude'] as num?)?.toDouble();
      final lng = (region['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final score = (region['current_score'] as num?)?.toDouble() ?? 0.0;
      final color = region['status'] == 'closed' ? _grayColor : _scoreToColor(score);

      markers.add(Marker(
        point: LatLng(lat, lng),
        width: 36,
        height: 36,
        child: GestureDetector(
          onTap: () => _showRegionDetail(region),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 6, spreadRadius: 1)],
            ),
            child: Center(
              child: Text(
                '${(score * 100).toInt()}',
                style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  void _showRegionDetail(Map<String, dynamic> region) {
    final score = (region['current_score'] as num?)?.toDouble() ?? 0.0;
    final color = _scoreToColor(score);
    final hourlyScores = region['hourly_scores'] as List? ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RegionDetailSheet(
        region: region,
        color: color,
        hourlyScores: hourlyScores,
        label: _scoreToDutchLabel(score),
        icon: _scoreToIcon(score),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Live Activiteit', style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: GymiesColors.darkBlue),
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadData,
          ),
        ],
      ),
      body: _loading && _regions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _regions.isEmpty
              ? _buildError()
              : Column(
                  children: [
                    _buildLiveTicker(),
                    Expanded(child: _buildMap()),
                    _buildLegend(),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text('Kon data niet laden', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_error ?? '', style: GoogleFonts.sora(fontSize: 13, color: Colors.grey), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Opnieuw proberen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveTicker() {
    final totals = _data['totals'] as Map<String, dynamic>? ?? {};
    final isLive = _data['is_live'] == true;
    final currentHour = (_data['current_hour'] as int?) ?? DateTime.now().hour;
    final totalBookings = totals['total_bookings'] ?? 0;
    final totalPayments = totals['total_payments'] ?? 0;
    final activeRegions = totals['active_regions'] ?? 0;
    final totalRegions = totals['total_regions'] ?? _regions.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: GymiesColors.darkBlue,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLive
                    ? Color.lerp(Colors.green, Colors.greenAccent, _pulseController.value)
                    : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isLive ? 'LIVE' : 'HISTORISCH',
            style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1),
          ),
          const SizedBox(width: 6),
          Text(
            '${currentHour.toString().padLeft(2, '0')}:00',
            style: GoogleFonts.sora(fontSize: 11, color: Colors.white.withOpacity(0.7)),
          ),
          const Spacer(),
          _tickerChip(Icons.event, '$totalBookings', 'boekingen'),
          const SizedBox(width: 12),
          _tickerChip(Icons.payment, '$totalPayments', 'betalingen'),
          const SizedBox(width: 12),
          _tickerChip(Icons.map, '$activeRegions/$totalRegions', 'actief'),
        ],
      ),
    );
  }

  Widget _tickerChip(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white.withOpacity(0.7)),
        const SizedBox(width: 4),
        Text(value, style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(width: 2),
        Text(label, style: GoogleFonts.sora(fontSize: 10, color: Colors.white.withOpacity(0.6))),
      ],
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _nlCenter,
        initialZoom: 7.5,
        minZoom: 6.5,
        maxZoom: 14,
        // Begrens camera tot Nederland
        cameraConstraint: CameraConstraint.contain(
          bounds: LatLngBounds(
            LatLng(50.75, 3.35),
            LatLng(53.55, 7.22),
          ),
        ),
      ),
      children: [
        // OpenStreetMap tiles — gratis, geen API key
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.Gymies.nl',
        ),
        // Activity circles
        CircleLayer(circles: _buildCircles()),
        // City markers met score
        MarkerLayer(markers: _buildMarkers()),
      ],
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _legendItem(_greenColor, 'Rustig', '0-25%'),
            _legendItem(_orangeColor, 'Beetje druk', '25-50%'),
            _legendItem(_redColor, 'Druk', '50-75%'),
            _legendItem(_purpleColor, 'Piek', '75-100%'),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label, String range) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.35),
            border: Border.all(color: color, width: 2),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
        Text(range, style: GoogleFonts.sora(fontSize: 9, color: Colors.grey)),
      ],
    );
  }
}

// ─── Region Detail Bottom Sheet ──────────────────────────────────

class _RegionDetailSheet extends StatelessWidget {
  final Map<String, dynamic> region;
  final Color color;
  final List hourlyScores;
  final String label;
  final IconData icon;

  const _RegionDetailSheet({
    required this.region,
    required this.color,
    required this.hourlyScores,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final score = (region['current_score'] as num?)?.toDouble() ?? 0.0;
    final city = region['city'] ?? '';
    final status = region['status'] ?? '';
    final trainers = region['trainers_count'] ?? 0;
    final clients = region['clients_count'] ?? 0;
    final currentBookings = region['current_bookings'] ?? 0;
    final currentPayments = region['current_payments'] ?? 0;
    final currentHour = region['current_hour'] ?? DateTime.now().hour;
    final utilization = (region['trainer_utilization'] as num?)?.toDouble() ?? 0.0;
    final peakHour = region['peak_hour'] ?? 0;
    final peakScore = (region['peak_score'] as num?)?.toDouble() ?? 0.0;
    final dayBookings = region['day_bookings_total'] ?? 0;
    final dayPayments = region['day_payments_total'] ?? 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(city, style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(label, style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                          ),
                          const SizedBox(width: 8),
                          Text('${(score * 100).toInt()}%', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                          const Spacer(),
                          _statusBadge(status),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Nu (${currentHour.toString().padLeft(2, '0')}:00)', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
            const SizedBox(height: 8),
            Row(
              children: [
                _statBox('Boekingen', '$currentBookings', Icons.event, color),
                const SizedBox(width: 8),
                _statBox('Betalingen', '$currentPayments', Icons.payment, color),
                const SizedBox(width: 8),
                _statBox('Bezetting', '${(utilization * 100).toInt()}%', Icons.people, color),
              ],
            ),
            const SizedBox(height: 16),
            Text('Vandaag totaal', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
            const SizedBox(height: 8),
            Row(
              children: [
                _statBox('Boekingen', '$dayBookings', Icons.calendar_month, GymiesColors.darkBlue),
                const SizedBox(width: 8),
                _statBox('Betalingen', '$dayPayments', Icons.receipt_long, GymiesColors.darkBlue),
                const SizedBox(width: 8),
                _statBox('Piek', '${peakHour.toString().padLeft(2, '0')}:00', Icons.whatshot, _peakColor(peakScore)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _statBox('Trainers', '$trainers', Icons.fitness_center, GymiesColors.primary),
                const SizedBox(width: 8),
                _statBox('Klanten', '$clients', Icons.person, GymiesColors.primary),
                const SizedBox(width: 8),
                _statBox('Actief nu', '${region['current_active_trainers'] ?? 0}', Icons.flash_on, Colors.amber),
              ],
            ),
            const SizedBox(height: 20),
            Text('24-uurs overzicht', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: _HourlyChart(hourlyScores: hourlyScores, currentHour: currentHour),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color bg;
    switch (status) {
      case 'open':
        bg = const Color(0xFF4CAF50);
        break;
      case 'invite_only':
        bg = Colors.orange;
        break;
      case 'waitlist':
        bg = Colors.blue;
        break;
      default:
        bg = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(status, style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: bg)),
    );
  }

  Widget _statBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
            Text(label, style: GoogleFonts.sora(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Color _peakColor(double s) {
    if (s > 0.75) return const Color(0xFF9C27B0);
    if (s > 0.50) return const Color(0xFFF44336);
    if (s > 0.25) return const Color(0xFFFF9800);
    return const Color(0xFF4CAF50);
  }
}

// ─── 24h Bar Chart ──────────────────────────────────────────────

class _HourlyChart extends StatelessWidget {
  final List hourlyScores;
  final int currentHour;

  const _HourlyChart({required this.hourlyScores, required this.currentHour});

  Color _barColor(double score) {
    if (score > 0.75) return const Color(0xFF9C27B0);
    if (score > 0.50) return const Color(0xFFF44336);
    if (score > 0.25) return const Color(0xFFFF9800);
    return const Color(0xFF4CAF50);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(24, (h) {
            final entry = h < hourlyScores.length ? hourlyScores[h] : null;
            final score = entry is Map ? (entry['score'] as num?)?.toDouble() ?? 0.0 : 0.0;
            final isCurrent = h == currentHour;
            final maxHeight = constraints.maxHeight - 16;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: (score * maxHeight).clamp(2.0, maxHeight),
                      decoration: BoxDecoration(
                        color: _barColor(score).withOpacity(isCurrent ? 1.0 : 0.5),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                        border: isCurrent ? Border.all(color: GymiesColors.darkBlue, width: 1.5) : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (h % 4 == 0)
                      Text('${h.toString().padLeft(2, '0')}', style: GoogleFonts.sora(fontSize: 8, color: Colors.grey))
                    else
                      const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
