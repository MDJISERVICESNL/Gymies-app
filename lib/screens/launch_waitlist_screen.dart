import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/haptics.dart';

/// Wachtlijst scherm — toont positie, regio status, en optie om met invite code te activeren.
/// Wordt getoond na registratie als de regio nog niet open is.
class LaunchWaitlistScreen extends StatefulWidget {
  /// Als [onActivated] meegegeven: callback bij succesvolle activatie (bijv. navigeer naar dashboard).
  final VoidCallback? onActivated;

  const LaunchWaitlistScreen({super.key, this.onActivated});

  @override
  State<LaunchWaitlistScreen> createState() => _LaunchWaitlistScreenState();
}

class _LaunchWaitlistScreenState extends State<LaunchWaitlistScreen> {
  bool _loading = true;
  String? _error;
  bool _onWaitlist = false;
  List<Map<String, dynamic>> _entries = [];

  // Invite code input
  final _codeCtrl = TextEditingController();
  bool _activating = false;
  String? _codeError;
  String? _codeSuccess;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getWaitlistStatus();
      if (!mounted) return;
      final onWaitlist = res['on_waitlist'] == true;
      final rawEntries = res['entries'];
      List<Map<String, dynamic>> entries = [];
      if (rawEntries is List) {
        entries = rawEntries.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      setState(() {
        _onWaitlist = onWaitlist;
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _activateWithCode() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _codeError = 'Voer een invite code in');
      return;
    }
    setState(() { _activating = true; _codeError = null; _codeSuccess = null; });
    try {
      final api = context.read<GymiesApi>();
      final res = await api.activateWithInviteCode(code);
      if (!mounted) return;
      if (res['ok'] == true) {
        Haptics.success();
        setState(() {
          _codeSuccess = res['message'] as String? ?? 'Je bent geactiveerd!';
          _activating = false;
        });
        // Wacht kort zodat user het succesbericht ziet
        await Future.delayed(const Duration(milliseconds: 1200));
        if (widget.onActivated != null) {
          widget.onActivated!();
        }
      } else {
        setState(() {
          _codeError = res['message'] as String? ?? 'Code kon niet worden gebruikt.';
          _activating = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _codeError = 'Fout: $e';
        _activating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildErrorState()
                : !_onWaitlist
                    ? _buildNotOnWaitlist()
                    : _buildWaitlistView(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 60, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text('Kon wachtlijststatus niet ophalen', style: GoogleFonts.sora(fontSize: 16, color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadStatus, child: const Text('Opnieuw proberen')),
          ],
        ),
      ),
    );
  }

  Widget _buildNotOnWaitlist() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 80, color: Colors.green[400]),
            const SizedBox(height: 16),
            Text(
              'Je staat niet op de wachtlijst',
              style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue),
            ),
            const SizedBox(height: 8),
            Text(
              'Je hebt volledige toegang tot het platform.',
              textAlign: TextAlign.center,
              style: GoogleFonts.sora(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            if (widget.onActivated != null)
              ElevatedButton(
                onPressed: widget.onActivated,
                style: ElevatedButton.styleFrom(backgroundColor: GymiesColors.primary, foregroundColor: GymiesColors.darkBlue),
                child: const Text('Ga verder'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitlistView() {
    return RefreshIndicator(
      onRefresh: _loadStatus,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 20),
          // Header
          Center(child: Icon(Icons.hourglass_top, size: 64, color: GymiesColors.primary)),
          const SizedBox(height: 16),
          Text(
            'Je staat op de wachtlijst',
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.bold, color: GymiesColors.darkBlue),
          ),
          const SizedBox(height: 8),
          Text(
            'GYMIES is momenteel in beperkte lancering. Zodra jouw regio opengaat, word je automatisch geactiveerd.',
            textAlign: TextAlign.center,
            style: GoogleFonts.sora(fontSize: 14, color: Colors.grey[600], height: 1.5),
          ),
          const SizedBox(height: 24),

          // Waitlist entries
          ..._entries.map(_buildEntryCard),

          const SizedBox(height: 24),

          // Invite code section
          _buildInviteCodeSection(),

          const SizedBox(height: 32),

          // Info box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: GymiesColors.accentLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: GymiesColors.primary.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline, size: 18, color: GymiesColors.darkBlue),
                    const SizedBox(width: 8),
                    Text('Sneller toegang?', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Vraag een trainer in jouw regio om een invite code. Met een geldige code krijg je direct toegang!',
                  style: GoogleFonts.sora(fontSize: 13, color: Colors.grey[700], height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(Map<String, dynamic> entry) {
    final regionName = (entry['region_name'] ?? 'Onbekend') as String;
    final role = (entry['role'] ?? '') as String;
    final regionStatus = entry['region_status'] as Map<String, dynamic>?;
    final regStatus = (regionStatus?['status'] ?? 'closed') as String;

    // Progress data from backend (vague indicators, no exact numbers)
    final regionProgress = entry['region_progress'] as Map<String, dynamic>?;
    final progressPct = (regionProgress?['progress_pct'] as num?)?.toDouble() ?? 0;
    final progressMessage = (regionProgress?['message'] as String?) ?? 'We werken aan jouw regio';
    final progressLevel = (regionProgress?['progress_level'] as String?) ?? 'early';

    Color statusColor;
    String statusLabel;
    switch (regStatus) {
      case 'open':
        statusColor = Colors.green;
        statusLabel = 'Open';
        break;
      case 'invite_only':
        statusColor = Colors.orange;
        statusLabel = 'Invite only';
        break;
      case 'waitlist':
        statusColor = Colors.blue;
        statusLabel = 'Wachtlijst';
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = 'Gesloten';
    }

    // Progress bar color based on level
    Color progressColor;
    IconData progressIcon;
    switch (progressLevel) {
      case 'nearly_ready':
        progressColor = Colors.green;
        progressIcon = Icons.rocket_launch;
        break;
      case 'almost':
        progressColor = Colors.lightGreen;
        progressIcon = Icons.trending_up;
        break;
      case 'growing':
        progressColor = GymiesColors.primary;
        progressIcon = Icons.show_chart;
        break;
      default: // early
        progressColor = Colors.blue;
        progressIcon = Icons.schedule;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Region name + status badge
            Row(
              children: [
                Icon(Icons.location_city, color: GymiesColors.darkBlue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(regionName, style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel, style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Progress bar section
            Row(
              children: [
                Icon(progressIcon, size: 18, color: progressColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    progressMessage,
                    style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w500, color: GymiesColors.darkBlue),
                  ),
                ),
                Icon(
                  role == 'trainer' ? Icons.fitness_center : Icons.person,
                  size: 18,
                  color: GymiesColors.darkBlue.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  role == 'trainer' ? 'Trainer' : 'Sporter',
                  style: GoogleFonts.sora(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Animated progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (progressPct / 100).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 6),

            // Subtle progress hint
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _progressHint(progressLevel),
                style: GoogleFonts.sora(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _progressHint(String level) {
    switch (level) {
      case 'nearly_ready':
        return 'Bijna zover!';
      case 'almost':
        return 'Nog even geduld';
      case 'growing':
        return 'Het groeit!';
      default:
        return 'We zijn bezig';
    }
  }

  Widget _buildInviteCodeSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Heb je een invite code?', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
          const SizedBox(height: 8),
          Text(
            'Voer de code in om direct geactiveerd te worden.',
            style: GoogleFonts.sora(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _codeCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'GYM-XXXXXX',
              hintStyle: GoogleFonts.sora(color: Colors.grey[400]),
              prefixIcon: const Icon(Icons.vpn_key, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: GymiesColors.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            style: GoogleFonts.sora(fontSize: 16, letterSpacing: 2, fontWeight: FontWeight.w600),
          ),
          if (_codeError != null) ...[
            const SizedBox(height: 8),
            Text(_codeError!, style: GoogleFonts.sora(fontSize: 13, color: Colors.red)),
          ],
          if (_codeSuccess != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(child: Text(_codeSuccess!, style: GoogleFonts.sora(fontSize: 13, color: Colors.green[700]))),
              ],
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _activating ? null : _activateWithCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: GymiesColors.primary,
                foregroundColor: GymiesColors.darkBlue,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _activating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Activeer met code', style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
