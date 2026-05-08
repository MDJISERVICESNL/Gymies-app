import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';

/// Tab widget voor de Regio's tab in StaffDashboardScreen.
class StaffRegionDashboardTab extends StatefulWidget {
  const StaffRegionDashboardTab({super.key});

  @override
  State<StaffRegionDashboardTab> createState() => _StaffRegionDashboardTabState();
}

class _StaffRegionDashboardTabState extends State<StaffRegionDashboardTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _regions = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final api = context.read<GymiesApi>();
      final regions = await api.getStaffRegions();
      if (!mounted) return;
      setState(() { _regions = regions; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showCreateDialog() {
    final cityCtrl = TextEditingController();
    final provinceCtrl = TextEditingController();
    final minTrainersCtrl = TextEditingController(text: '3');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nieuwe regio', style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'Stad', hintText: 'bijv. Amsterdam')),
            const SizedBox(height: 8),
            TextField(controller: provinceCtrl, decoration: const InputDecoration(labelText: 'Provincie', hintText: 'bijv. Noord-Holland')),
            const SizedBox(height: 8),
            TextField(controller: minTrainersCtrl, decoration: const InputDecoration(labelText: 'Min. trainers om te openen'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleer')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final api = context.read<GymiesApi>();
                await api.createStaffRegion({
                  'city': cityCtrl.text.trim(),
                  'province': provinceCtrl.text.trim(),
                  'min_trainers_to_open': int.tryParse(minTrainersCtrl.text) ?? 3,
                });
                Haptics.success();
                _loadRegions();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: GymiesColors.primary, foregroundColor: GymiesColors.darkBlue),
            child: const Text('Aanmaken'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: GoogleFonts.sora(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadRegions, child: const Text('Opnieuw')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRegions,
      child: _regions.isEmpty
          ? ListView(children: [
              const SizedBox(height: 100),
              Center(child: Icon(Icons.map_outlined, size: 80, color: Colors.grey[300])),
              const SizedBox(height: 16),
              Center(child: Text('Nog geen regio\'s', style: GoogleFonts.sora(fontSize: 16, color: Colors.grey))),
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _showCreateDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Regio toevoegen'),
                  style: ElevatedButton.styleFrom(backgroundColor: GymiesColors.primary, foregroundColor: GymiesColors.darkBlue),
                ),
              ),
            ])
          : Column(
              children: [
                // Summary bar
                _buildSummaryBar(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                    itemCount: _regions.length,
                    itemBuilder: (_, i) => _buildRegionCard(_regions[i]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryBar() {
    final open = _regions.where((r) => r['status'] == 'open').length;
    final inviteOnly = _regions.where((r) => r['status'] == 'invite_only').length;
    final waitlist = _regions.where((r) => r['status'] == 'waitlist').length;
    final closed = _regions.where((r) => r['status'] == 'closed').length;
    final totalTrainers = _regions.fold<int>(0, (s, r) => s + ((r['trainers_count'] as int?) ?? 0));
    final totalClients = _regions.fold<int>(0, (s, r) => s + ((r['clients_count'] as int?) ?? 0));

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF2A5298)]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('$open', 'Open', Colors.green),
          _summaryItem('$inviteOnly', 'Invite', Colors.orange),
          _summaryItem('$waitlist', 'Wachtlijst', Colors.blue),
          _summaryItem('$closed', 'Gesloten', Colors.grey),
          _summaryItem('$totalTrainers', 'Trainers', GymiesColors.primary),
          _summaryItem('$totalClients', 'Klanten', Colors.white),
        ],
      ),
    );
  }

  Widget _summaryItem(String value, String label, Color color) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: GoogleFonts.sora(fontSize: 10, color: Colors.white70)),
      ],
    );
  }

  Widget _buildRegionCard(Map<String, dynamic> region) {
    final city = (region['city'] ?? '') as String;
    final slug = (region['slug'] ?? '') as String;
    final province = (region['province'] ?? '') as String;
    final status = (region['status'] ?? 'closed') as String;
    final trainers = (region['trainers_count'] as int?) ?? 0;
    final clients = (region['clients_count'] as int?) ?? 0;
    final waitlistCount = (region['waitlist_count'] as int?) ?? 0;
    final bookingsWeek = (region['bookings_this_week'] as int?) ?? 0;
    final ratio = (region['ratio'] is num) ? (region['ratio'] as num).toDouble() : 0.0;
    final readiness = region['readiness'] as Map<String, dynamic>?;
    final isReady = readiness?['ready'] == true;
    final recommendation = (readiness?['recommendation'] ?? '') as String;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'open':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'invite_only':
        statusColor = Colors.orange;
        statusIcon = Icons.vpn_key;
        break;
      case 'waitlist':
        statusColor = Colors.blue;
        statusIcon = Icons.hourglass_top;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.lock;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(slug, city),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(city, style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                        if (province.isNotEmpty)
                          Text(province, style: GoogleFonts.sora(fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                  _statusBadge(status, statusColor),
                ],
              ),
              const SizedBox(height: 10),
              // Stats row
              Row(
                children: [
                  _miniStat(Icons.fitness_center, '$trainers', 'trainers'),
                  _miniStat(Icons.people, '$clients', 'klanten'),
                  _miniStat(Icons.hourglass_bottom, '$waitlistCount', 'wachtlijst'),
                  _miniStat(Icons.calendar_today, '$bookingsWeek', 'boekingen/wk'),
                  _miniStat(Icons.balance, ratio.toStringAsFixed(1), 'ratio'),
                ],
              ),
              // Readiness
              if (readiness != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isReady ? Colors.green.withOpacity(0.08) : Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(isReady ? Icons.rocket_launch : Icons.info_outline, size: 14, color: isReady ? Colors.green[700] : Colors.orange[700]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isReady ? 'Klaar om te openen!' : recommendation,
                          style: GoogleFonts.sora(fontSize: 11, color: isReady ? Colors.green[700] : Colors.orange[700]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status, Color color) {
    String label;
    switch (status) {
      case 'open': label = 'Open'; break;
      case 'invite_only': label = 'Invite'; break;
      case 'waitlist': label = 'Wachtlijst'; break;
      default: label = 'Gesloten';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _miniStat(IconData icon, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 14, color: Colors.grey[500]),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
          Text(label, style: GoogleFonts.sora(fontSize: 9, color: Colors.grey[500])),
        ],
      ),
    );
  }

  void _openDetail(String slug, String city) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StaffRegionDetailScreen(slug: slug, city: city)),
    );
  }
}

// ─── Region Detail Screen ──────────────────────────────────────

class StaffRegionDetailScreen extends StatefulWidget {
  final String slug;
  final String city;

  const StaffRegionDetailScreen({super.key, required this.slug, required this.city});

  @override
  State<StaffRegionDetailScreen> createState() => _StaffRegionDetailScreenState();
}

class _StaffRegionDetailScreenState extends State<StaffRegionDetailScreen> {
  bool _loading = true;
  bool _updating = false;
  String? _error;
  Map<String, dynamic> _detail = {};

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final api = context.read<GymiesApi>();
      final detail = await api.getStaffRegionDetail(widget.slug);
      if (!mounted) return;
      setState(() { _detail = detail; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Status wijzigen', style: GoogleFonts.sora(fontWeight: FontWeight.w700)),
        content: Text('Regio "${widget.city}" wijzigen naar "$newStatus"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleer')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: GymiesColors.primary, foregroundColor: GymiesColors.darkBlue),
            child: const Text('Bevestig'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _updating = true);
    try {
      final api = context.read<GymiesApi>();
      await api.updateStaffRegion(widget.slug, {'status': newStatus});
      Haptics.success();
      await _loadDetail();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.city, style: GoogleFonts.sora(fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
        backgroundColor: Colors.white,
        foregroundColor: GymiesColors.darkBlue,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadDetail),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: GoogleFonts.sora(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _loadDetail,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildStatusSection(),
                      const SizedBox(height: 16),
                      _buildStatsGrid(),
                      const SizedBox(height: 16),
                      _buildBookingTrend(),
                      const SizedBox(height: 16),
                      _buildTopTrainers(),
                      const SizedBox(height: 16),
                      _buildWaitlistByRole(),
                      const SizedBox(height: 16),
                      _buildInviteStats(),
                      const SizedBox(height: 16),
                      _buildGrowthData(),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _buildStatusSection() {
    final status = (_detail['status'] ?? 'closed') as String;
    final statuses = ['closed', 'waitlist', 'invite_only', 'open'];

    Color statusColor;
    switch (status) {
      case 'open': statusColor = Colors.green; break;
      case 'invite_only': statusColor = Colors.orange; break;
      case 'waitlist': statusColor = Colors.blue; break;
      default: statusColor = Colors.grey;
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Status: ', style: GoogleFonts.sora(fontSize: 14, color: Colors.grey[600])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text(status.toUpperCase(), style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: statusColor)),
                ),
                const Spacer(),
                if (_updating)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Wijzig status:', style: GoogleFonts.sora(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: statuses.map((s) {
                final isCurrent = s == status;
                Color c;
                switch (s) {
                  case 'open': c = Colors.green; break;
                  case 'invite_only': c = Colors.orange; break;
                  case 'waitlist': c = Colors.blue; break;
                  default: c = Colors.grey;
                }
                return ChoiceChip(
                  label: Text(s, style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w600, color: isCurrent ? Colors.white : c)),
                  selected: isCurrent,
                  selectedColor: c,
                  backgroundColor: c.withOpacity(0.08),
                  onSelected: isCurrent || _updating ? null : (_) => _updateStatus(s),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final trainers = (_detail['trainers_count'] as int?) ?? 0;
    final clients = (_detail['clients_count'] as int?) ?? 0;
    final waitlist = (_detail['waitlist_count'] as int?) ?? 0;
    final bookings = (_detail['bookings_this_week'] as int?) ?? 0;
    final ratio = (_detail['ratio'] is num) ? (_detail['ratio'] as num).toDouble() : 0.0;
    final minTrainers = (_detail['min_trainers_to_open'] as int?) ?? 3;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Statistieken', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.6,
              children: [
                _statTile('Trainers', '$trainers', Icons.fitness_center, GymiesColors.darkBlue),
                _statTile('Klanten', '$clients', Icons.people, Colors.blue),
                _statTile('Wachtlijst', '$waitlist', Icons.hourglass_top, Colors.orange),
                _statTile('Boekingen/wk', '$bookings', Icons.calendar_today, Colors.green),
                _statTile('Ratio', ratio.toStringAsFixed(1), Icons.balance, Colors.purple),
                _statTile('Min. trainers', '$minTrainers', Icons.flag, Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: GymiesColors.darkBlue)),
        Text(label, style: GoogleFonts.sora(fontSize: 10, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildBookingTrend() {
    final trend = (_detail['booking_trend_7d'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (trend.isEmpty) return const SizedBox.shrink();

    final maxCount = trend.fold<int>(1, (m, t) => ((t['count'] as int?) ?? 0) > m ? ((t['count'] as int?) ?? 0) : m);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Boekingen afgelopen 7 dagen', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: trend.map((t) {
                  final count = (t['count'] as int?) ?? 0;
                  final date = (t['date'] ?? '') as String;
                  final dayLabel = date.length >= 10 ? date.substring(8, 10) : '';
                  final fraction = maxCount > 0 ? count / maxCount : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('$count', style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                          const SizedBox(height: 2),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            height: 80 * fraction,
                            decoration: BoxDecoration(
                              color: GymiesColors.primary.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(dayLabel, style: GoogleFonts.sora(fontSize: 10, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopTrainers() {
    final trainers = (_detail['top_trainers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (trainers.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Top trainers', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
              const SizedBox(height: 8),
              Text('Nog geen trainers in deze regio', style: GoogleFonts.sora(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top 10 trainers', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
            const SizedBox(height: 8),
            ...trainers.asMap().entries.map((entry) {
              final i = entry.key;
              final t = entry.value;
              final name = (t['name'] ?? 'Onbekend') as String;
              final bookings = (t['bookings_count'] as int?) ?? 0;
              final rating = t['rating'];
              final ratingStr = rating != null ? (rating as num).toStringAsFixed(1) : '-';

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text('${i + 1}', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w700, color: i < 3 ? GymiesColors.primary : Colors.grey)),
                    ),
                    Expanded(child: Text(name, style: GoogleFonts.sora(fontSize: 13, color: GymiesColors.darkBlue))),
                    Text('$bookings boekingen', style: GoogleFonts.sora(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(width: 12),
                    Icon(Icons.star, size: 14, color: Colors.amber[600]),
                    const SizedBox(width: 2),
                    Text(ratingStr, style: GoogleFonts.sora(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitlistByRole() {
    final waitlistMap = _detail['waitlist_by_role'] as Map<String, dynamic>? ?? {};
    if (waitlistMap.isEmpty) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wachtlijst per rol', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
            const SizedBox(height: 12),
            ...waitlistMap.entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(e.key == 'trainer' ? Icons.fitness_center : Icons.person, size: 16, color: GymiesColors.darkBlue),
                  const SizedBox(width: 8),
                  Text(e.key == 'trainer' ? 'Trainers' : 'Sporters', style: GoogleFonts.sora(fontSize: 13)),
                  const Spacer(),
                  Text('${e.value}', style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteStats() {
    final stats = _detail['invite_codes_stats'] as Map<String, dynamic>? ?? {};
    final generated = (stats['total_generated'] as int?) ?? 0;
    final used = (stats['total_used'] as int?) ?? 0;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invite codes', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _codeStat('Gegenereerd', '$generated', Icons.vpn_key, GymiesColors.darkBlue)),
                Expanded(child: _codeStat('Gebruikt', '$used', Icons.check, Colors.green)),
                Expanded(child: _codeStat('Conversie', generated > 0 ? '${(used / generated * 100).toStringAsFixed(0)}%' : '-', Icons.trending_up, Colors.orange)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(value, style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: GymiesColors.darkBlue)),
        Text(label, style: GoogleFonts.sora(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }

  Widget _buildGrowthData() {
    final growth = (_detail['growth_4w'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (growth.isEmpty) return const SizedBox.shrink();

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Groei (4 weken)', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
            const SizedBox(height: 12),
            // Header
            Row(
              children: [
                Expanded(flex: 2, child: Text('Week', style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[500]))),
                Expanded(child: Text('Trainers', textAlign: TextAlign.center, style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[500]))),
                Expanded(child: Text('Klanten', textAlign: TextAlign.center, style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[500]))),
              ],
            ),
            const Divider(),
            ...growth.map((g) {
              final week = (g['week'] ?? '') as String;
              final nt = (g['new_trainers'] as int?) ?? 0;
              final nc = (g['new_clients'] as int?) ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(week, style: GoogleFonts.sora(fontSize: 12, color: GymiesColors.darkBlue))),
                    Expanded(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: nt > 0 ? Colors.green.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                          child: Text('+$nt', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: nt > 0 ? Colors.green[700] : Colors.grey)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: nc > 0 ? Colors.blue.withOpacity(0.1) : Colors.transparent, borderRadius: BorderRadius.circular(6)),
                          child: Text('+$nc', style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: nc > 0 ? Colors.blue[700] : Colors.grey)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
