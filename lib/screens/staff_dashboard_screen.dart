import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/gymies_theme.dart';
import '../services/gymies_api.dart';
import '../utils/haptics.dart';
import 'gym_churn_report_screen.dart';
import 'gym_locations_screen.dart';
import 'staff_activity_heatmap_screen.dart';
import 'staff_region_dashboard_screen.dart';
import 'widgets/gymies_app_bar.dart';

/// ─── Staff Dashboard (Fase C + E + G + H + I) ──────────────
///
/// Tabs:
///   0 Overzicht    — stats + pending reviews + warnings (H.10)
///   1 Trials       — trial overzicht + verlenging
///   2 Codes        — uitnodigingscodes beheer
///   3 Audit        — audit trail viewer
///   4 Flags        — feature flags beheer (Fase E + H.12)
///   5 Support      — ticket beheer (G + H.5 canned + I.2/I.12)
///   6 Chat         — intern staff chat (G + H.9 unread)
///   7 Trainers     — zoeken & filteren (H.2 + I.5/I.6/I.7/I.8)
///   8 Bookings     — monitor (H.3 + I.3/I.4)
///   9 Pipeline     — onboarding pipeline (H.4)
///  10 Geschillen   — disputes (H.6 + I.1)
///  11 Groepslessen — group sessions monitor (I.9)
///  12 Betalingen   — payments overview (I.10)
///  13 Gyms         — gym/studio overzicht (I.13)
class StaffDashboardScreen extends StatefulWidget {
  final int initialTab;
  const StaffDashboardScreen({super.key, this.initialTab = 0});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;
  Map<String, dynamic> _stats = {};
  List<dynamic> _pendingReviews = [];
  List<dynamic> _trials = [];
  List<dynamic> _codes = [];
  List<dynamic> _auditEntries = [];
  List<dynamic> _featureFlags = [];

  // ── Support Ticket state ──
  Map<String, dynamic> _ticketStats = {};
  List<dynamic> _tickets = [];
  int _ticketTotal = 0;
  String _ticketStatusFilter = '';
  String _ticketPriorityFilter = '';
  String _ticketSearch = '';
  bool _ticketAssignedToMe = false;

  // ── Staff Chat state ──
  List<dynamic> _chatMessages = [];
  List<dynamic> _chatChannels = [];
  String _chatChannel = 'general';
  bool _chatHasMore = false;
  final _chatMsgCtrl = TextEditingController();
  final _chatScrollCtrl = ScrollController();
  final _ticketSearchCtrl = TextEditingController();
  Map<String, int> _chatUnreadCounts = {};

  // ── Fase H: Trainers / Bookings / Pipeline / Disputes state ──
  List<dynamic> _allTrainers = [];
  int _trainerTotal = 0;
  String _trainerSearch = '';
  String _trainerStatusFilter = '';
  final _trainerSearchCtrl = TextEditingController();

  Map<String, dynamic> _bookingsMonitor = {};
  Map<String, dynamic> _pipelineData = {};
  List<dynamic> _disputes = [];
  int _disputeTotal = 0;
  String _disputeStatusFilter = '';

  // ── H.5: Canned responses ──
  List<dynamic> _cannedResponses = [];

  // ── H.10: Dashboard extended ──
  Map<String, dynamic> _dashboardExtended = {};

  // ── Fase I: Groepslessen / Betalingen / Gyms state ──
  Map<String, dynamic> _groupSessionsData = {};
  Map<String, dynamic> _paymentsData = {};
  Map<String, dynamic> _gymsData = {};
  String _gymsSearch = '';
  final _gymsSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 15, vsync: this, initialIndex: widget.initialTab.clamp(0, 14));
    _tabCtrl.addListener(() {
      // Lazy load bij eerste tab switch
      try {
        // BUG FIX #6: Check _tickets.isEmpty instead of _ticketStats since we now load both in _loadAll
        if (_tabCtrl.index == 5 && _tickets.isEmpty) {
          _loadTickets();
          _loadCannedResponses();
        }
        if (_tabCtrl.index == 6 && _chatMessages.isEmpty) {
          _loadChat();
        }
        if (_tabCtrl.index == 7 && _allTrainers.isEmpty) {
          _loadTrainers();
        }
        if (_tabCtrl.index == 8 && _bookingsMonitor.isEmpty) {
          _loadBookingsMonitor();
        }
        if (_tabCtrl.index == 9 && _pipelineData.isEmpty) {
          _loadPipeline();
        }
        if (_tabCtrl.index == 10 && _disputes.isEmpty) {
          _loadDisputes();
        }
        if (_tabCtrl.index == 11 && _groupSessionsData.isEmpty) {
          _loadGroupSessions();
        }
        if (_tabCtrl.index == 12 && _paymentsData.isEmpty) {
          _loadPayments();
        }
        if (_tabCtrl.index == 13 && _gymsData.isEmpty) {
          _loadGyms();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tab laden mislukt: $e'), backgroundColor: Colors.red),
          );
        }
      }
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _chatMsgCtrl.dispose();
    _chatScrollCtrl.dispose();
    _ticketSearchCtrl.dispose();
    _trainerSearchCtrl.dispose();
    _gymsSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final api = context.read<GymiesApi>();
      // BUG FIX #1: Load ticket stats + chat unread counts for badges
      final results = await Future.wait([
        api.getStaffDashboard(),
        api.getStaffPendingReviews(),
        api.getStaffTrialOverview(),
        api.getStaffInvitationCodes(),
        api.getStaffAuditLog(),
        api.getStaffFeatureFlags(),
        api.getStaffTicketStats(),
        api.getStaffChatUnreadCounts(),
      ]);

      if (!mounted) return;
      final ticketStats = (results[6] as Map<String, dynamic>?) ?? {};
      final chatUnreadRes = (results[7] as Map<String, dynamic>?) ?? {};
      final chatUnreadRaw = (chatUnreadRes['counts'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as int?) ?? 0)) ?? {};

      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _pendingReviews = (results[1] as Map)['data'] as List? ?? [];
        _trials = (results[2] as Map)['data'] as List? ?? [];
        _codes = (results[3] as Map)['data'] as List? ?? [];
        _auditEntries = (results[4] as Map)['data'] as List? ?? [];
        _featureFlags = (results[5] as Map)['data'] as List? ?? [];
        _ticketStats = ticketStats;
        _chatUnreadCounts = chatUnreadRaw;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GymiesAppBar(
        title: 'Medewerkers Dashboard',
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                TabBar(
                  controller: _tabCtrl,
                  labelColor: GymiesColors.darkBlue,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: GymiesColors.darkBlue,
                  labelStyle: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Overzicht', icon: _badge(Icons.dashboard, _stats['pending_reviews'] ?? 0)),
                    Tab(text: 'Trials', icon: _badge(Icons.timer, _stats['trials_expiring_soon'] ?? 0)),
                    const Tab(text: 'Codes', icon: Icon(Icons.vpn_key)),
                    const Tab(text: 'Audit', icon: Icon(Icons.history)),
                    const Tab(text: 'Flags', icon: Icon(Icons.toggle_on)),
                    Tab(text: 'Support', icon: _badge(Icons.support_agent, (_ticketStats['new'] as int?) ?? 0)),
                    Tab(text: 'Chat', icon: _badge(Icons.chat, _chatUnreadCounts.values.fold(0, (a, b) => a + b))),
                    const Tab(text: 'Trainers', icon: Icon(Icons.people)),
                    const Tab(text: 'Bookings', icon: Icon(Icons.calendar_today)),
                    const Tab(text: 'Pipeline', icon: Icon(Icons.linear_scale)),
                    const Tab(text: 'Geschillen', icon: Icon(Icons.gavel)),
                    const Tab(text: 'Groepslessen', icon: Icon(Icons.groups)),
                    const Tab(text: 'Betalingen', icon: Icon(Icons.payment)),
                    const Tab(text: 'Gyms', icon: Icon(Icons.fitness_center)),
                    const Tab(text: 'Regio\'s', icon: Icon(Icons.map)),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildOverviewTab(),
                      _buildTrialsTab(),
                      _buildCodesTab(),
                      _buildAuditTab(),
                      _buildFlagsTab(),
                      _buildSupportTab(),
                      _buildChatTab(),
                      _buildTrainersTab(),
                      _buildBookingsTab(),
                      _buildPipelineTab(),
                      _buildDisputesTab(),
                      _buildGroupSessionsTab(),
                      _buildPaymentsTab(),
                      _buildGymsTab(),
                      const StaffRegionDashboardTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _badge(IconData icon, int count) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count', style: const TextStyle(fontSize: 10)),
      child: Icon(icon),
    );
  }

  // ─── Tab 0: Overzicht ────────────────────────────────────────
  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Stats cards
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statCard('Wacht op review', _stats['pending_reviews'] ?? 0, Icons.pending_actions, Colors.orange),
              _statCard('Actieve trainers', _stats['active_trainers'] ?? 0, Icons.people, Colors.green),
              _statCard('Trials bijna afgelopen', _stats['trials_expiring_soon'] ?? 0, Icons.timer_off, Colors.red),
              _statCard('Geschorst', _stats['suspended_trainers'] ?? 0, Icons.block, Colors.grey),
              _statCard('Actieve codes', _stats['invitation_codes_active'] ?? 0, Icons.vpn_key, Colors.blue),
              _statCard('Open tickets', _stats['open_tickets'] ?? 0, Icons.support_agent, Colors.purple),
            ],
          ),
          const SizedBox(height: 16),
          // Live activity heatmap button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffActivityHeatmapScreen())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF2C5282)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.map, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Live Activiteit Kaart', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                          Text('Bekijk drukte per regio op de kaart', style: GoogleFonts.sora(fontSize: 11, color: Colors.white.withOpacity(0.7))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.greenAccent.withOpacity(0.25), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.greenAccent)),
                          const SizedBox(width: 4),
                          Text('LIVE', style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.greenAccent, letterSpacing: 1)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.5), size: 14),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Pending reviews
          Text('Wacht op review',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_pendingReviews.isEmpty)
            _emptyState('Geen openstaande reviews')
          else
            ..._pendingReviews.map((r) => _reviewCard(r as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _statCard(String label, int value, IconData icon, Color color) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 48) / 2,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: color, width: 3)),
          color: color.withOpacity(0.05),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text('$value', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700)),
            Text(label, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _reviewCard(Map<String, dynamic> review) {
    final name = review['user_name'] as String? ?? 'Onbekend';
    final email = review['user_email'] as String? ?? '';
    final company = review['company_name'] as String? ?? '';
    final trainerId = review['id'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: GymiesColors.darkBlue.withOpacity(0.1),
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(company.isNotEmpty ? company : email,
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showFraudCheck(trainerId, name),
                    icon: const Icon(Icons.shield, size: 16),
                    label: const Text('Fraud Check'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade700,
                      side: BorderSide(color: Colors.orange.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      textStyle: GoogleFonts.poppins(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green),
                  tooltip: 'Goedkeuren',
                  onPressed: () => _showReviewDialog(trainerId, name, 'approve'),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red),
                  tooltip: 'Afwijzen',
                  onPressed: () => _showReviewDialog(trainerId, name, 'reject'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFraudCheck(int trainerId, String trainerName) async {
    // Toon loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Fraud check uitvoeren...'),
          ],
        ),
      ),
    );

    try {
      final api = context.read<GymiesApi>();
      final result = await api.getStaffFraudCheck(trainerId);
      if (!mounted) return;
      Navigator.of(context).pop(); // Sluit loading

      final passed = result['passed'] == true;
      final riskLevel = result['risk_level'] as String? ?? 'none';
      final blocks = result['blocks'] as List? ?? [];
      final warnings = result['warnings'] as List? ?? [];
      final skipped = result['skipped'] == true;

      final riskColor = switch (riskLevel) {
        'high' => Colors.red,
        'medium' => Colors.orange,
        'low' => Colors.amber,
        _ => Colors.green,
      };

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                skipped ? Icons.shield_outlined
                    : passed ? Icons.verified_user : Icons.gpp_bad,
                color: skipped ? Colors.grey : riskColor,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('Fraud Check: $trainerName',
                  style: GoogleFonts.poppins(fontSize: 15))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (skipped) ...[
                  Text('Fraud detectie is uitgeschakeld via feature flags.',
                      style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey)),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: riskColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text('Risico: ', style: GoogleFonts.poppins(fontSize: 13)),
                        Text(riskLevel.toUpperCase(),
                            style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w700, color: riskColor)),
                      ],
                    ),
                  ),
                  if (blocks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Blokkades:', style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w700, color: Colors.red)),
                    ...blocks.map((b) {
                      final block = b as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.block, size: 16, color: Colors.red),
                            const SizedBox(width: 6),
                            Expanded(child: Text(block['message'] as String? ?? '',
                                style: GoogleFonts.poppins(fontSize: 12))),
                          ],
                        ),
                      );
                    }),
                  ],
                  if (warnings.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Waarschuwingen:', style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w700, color: Colors.orange)),
                    ...warnings.map((w) {
                      final warning = w as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                            const SizedBox(width: 6),
                            Expanded(child: Text(warning['message'] as String? ?? '',
                                style: GoogleFonts.poppins(fontSize: 12))),
                          ],
                        ),
                      );
                    }),
                  ],
                  if (blocks.isEmpty && warnings.isEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text('Geen problemen gevonden',
                            style: GoogleFonts.poppins(fontSize: 13, color: Colors.green)),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Sluiten')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Sluit loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fraud check mislukt: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showReviewDialog(int trainerId, String name, String action) async {
    final reasonCtrl = TextEditingController();
    final isReject = action == 'reject';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isReject ? 'Trainer afwijzen' : 'Trainer goedkeuren'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name ${isReject ? "afwijzen" : "goedkeuren"}?'),
            if (isReject) ...[
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reden (verplicht)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () {
              if (isReject && reasonCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Reden is verplicht'), backgroundColor: Colors.orange),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Text(isReject ? 'Afwijzen' : 'Goedkeuren'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<GymiesApi>();
      await api.reviewTrainer(
        trainerId: trainerId,
        action: action,
        reason: reasonCtrl.text.trim(),
      );
      GymiesHaptics.success();
      _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Tab 1: Trials ───────────────────────────────────────────
  Widget _buildTrialsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_trials.isEmpty)
            _emptyState('Geen actieve trials')
          else
            ..._trials.map((t) => _trialCard(t as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _trialCard(Map<String, dynamic> trial) {
    final trainerId = trial['id'] as int? ?? 0;
    final daysRemaining = trial['days_remaining'] as int? ?? 0;
    final urgency = trial['urgency'] as String? ?? 'ok';
    final expired = trial['trial_expired'] == true;
    final userName = (trial['user_name'] as String? ?? '').trim();
    final activityScore = trial['activity_score'] as int? ?? 0;

    final urgencyColor = switch (urgency) {
      'expired' => Colors.red,
      'critical' => Colors.orange,
      'warning' => Colors.amber,
      _ => Colors.green,
    };

    final scoreColor = activityScore >= 70 ? Colors.green
        : activityScore >= 40 ? Colors.orange
        : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: urgencyColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userName.isNotEmpty ? userName : 'Trainer #$trainerId',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                      if (userName.isNotEmpty)
                        Text('#$trainerId',
                            style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
                // Activity score badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: scoreColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.trending_up, size: 12, color: scoreColor),
                      const SizedBox(width: 2),
                      Text('$activityScore',
                          style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: scoreColor)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: urgencyColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    expired ? 'Verlopen' : '$daysRemaining dagen',
                    style: GoogleFonts.poppins(
                        fontSize: 12, fontWeight: FontWeight.w600, color: urgencyColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _extendButton(trainerId, 7),
                const SizedBox(width: 8),
                _extendButton(trainerId, 14),
                const SizedBox(width: 8),
                _extendButton(trainerId, 30),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _extendButton(int trainerId, int days) {
    return OutlinedButton(
      onPressed: () => _showExtendDialog(trainerId, days),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        textStyle: GoogleFonts.poppins(fontSize: 12),
      ),
      child: Text('+$days dagen'),
    );
  }

  Future<void> _showExtendDialog(int trainerId, int days) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Trial verlengen met $days dagen'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reden (optioneel)',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Verleng $days dagen'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<GymiesApi>();
      final result = await api.extendTrial(
        trainerId: trainerId,
        days: days,
        reason: reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : null,
      );
      GymiesHaptics.success();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trial verlengd tot ${result['new_trial_end'] ?? '?'}'),
            backgroundColor: Colors.green,
          ),
        );
        _loadAll();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Tab 2: Codes ────────────────────────────────────────────
  Widget _buildCodesTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _createCode,
            icon: const Icon(Icons.add),
            label: const Text('Nieuwe code'),
          ),
          const SizedBox(height: 16),
          if (_codes.isEmpty)
            _emptyState('Geen uitnodigingscodes')
          else
            ..._codes.map((c) => _codeCard(c as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _codeCard(Map<String, dynamic> code) {
    final codeStr = code['code'] as String? ?? '???';
    final source = code['source'] as String? ?? 'staff';
    final usedCount = code['used_count'] as int? ?? 0;
    final maxUses = code['max_uses'] as int? ?? 1;
    final isActive = code['is_active'] == true || code['is_active'] == 1;
    final codeId = code['id'] as int? ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          source == 'referral' ? Icons.people : Icons.vpn_key,
          color: isActive ? GymiesColors.darkBlue : Colors.grey,
        ),
        title: Text(codeStr,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: isActive ? null : Colors.grey)),
        subtitle: Text('$source — $usedCount/$maxUses gebruikt',
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Kopieer code',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: codeStr));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Code gekopieerd: $codeStr'), duration: const Duration(seconds: 1)),
                );
              },
            ),
            if (isActive)
              IconButton(
                icon: const Icon(Icons.block, color: Colors.red, size: 20),
                tooltip: 'Deactiveren',
                onPressed: () => _deactivateCode(codeId),
              )
            else
              const Icon(Icons.cancel, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _createCode() async {
    String source = 'staff';
    int maxUses = 1;
    int? expiryDays;
    final maxUsesCtrl = TextEditingController(text: '1');
    final expiryCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDlgState) => AlertDialog(
          title: Text('Nieuwe code', style: GoogleFonts.poppins(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bron', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'staff', label: Text('Staff')),
                  ButtonSegment(value: 'promo', label: Text('Promo')),
                  ButtonSegment(value: 'partner', label: Text('Partner')),
                ],
                selected: {source},
                onSelectionChanged: (s) => setDlgState(() => source = s.first),
                style: ButtonStyle(
                  textStyle: WidgetStatePropertyAll(GoogleFonts.poppins(fontSize: 12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxUsesCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Max aantal keer te gebruiken',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: expiryCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Verloopt na (dagen, leeg = nooit)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
            FilledButton(
              onPressed: () {
                maxUses = int.tryParse(maxUsesCtrl.text) ?? 1;
                expiryDays = int.tryParse(expiryCtrl.text);
                Navigator.pop(ctx, true);
              },
              child: const Text('Aanmaken'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<GymiesApi>();
      final result = await api.createInvitationCode(
        source: source,
        maxUses: maxUses,
        expiryDays: expiryDays,
      );
      GymiesHaptics.success();
      if (mounted) {
        final code = result['code'] ?? '?';
        Clipboard.setData(ClipboardData(text: code.toString()));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Code aangemaakt en gekopieerd: $code'),
            backgroundColor: Colors.green,
          ),
        );
        _loadAll();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deactivateCode(int codeId) async {
    try {
      final api = context.read<GymiesApi>();
      await api.deactivateInvitationCode(codeId);
      GymiesHaptics.success();
      _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Tab 3: Audit ────────────────────────────────────────────
  Widget _buildAuditTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_auditEntries.isEmpty)
            _emptyState('Geen audit entries')
          else
            ..._auditEntries.map((a) => _auditCard(a as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _auditCard(Map<String, dynamic> entry) {
    final action = entry['action'] as String? ?? '';
    final staffName = entry['staff_name'] as String? ?? 'Systeem';
    final createdAt = entry['created_at'] as String? ?? '';
    final metadata = entry['metadata'] as Map<String, dynamic>? ?? {};

    final actionIcon = switch (action) {
      String a when a.contains('approved') => Icons.check_circle,
      String a when a.contains('rejected') => Icons.cancel,
      String a when a.contains('suspended') => Icons.block,
      String a when a.contains('extended') => Icons.timer,
      String a when a.contains('code') => Icons.vpn_key,
      String a when a.contains('fraud') => Icons.warning,
      _ => Icons.history,
    };

    final actionColor = switch (action) {
      String a when a.contains('approved') || a.contains('reactivated') => Colors.green,
      String a when a.contains('rejected') || a.contains('suspended') => Colors.red,
      String a when a.contains('fraud') => Colors.orange,
      _ => Colors.blue,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(actionIcon, color: actionColor, size: 20),
        title: Text(action, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('$staffName — ${_formatDate(createdAt)}',
            style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey)),
        trailing: metadata.isNotEmpty
            ? const Icon(Icons.info_outline, size: 16, color: Colors.grey)
            : null,
        onTap: metadata.isNotEmpty
            ? () => _showMetadataDialog(action, metadata)
            : null,
      ),
    );
  }

  void _showMetadataDialog(String action, Map<String, dynamic> metadata) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action, style: GoogleFonts.poppins(fontSize: 16)),
        content: SingleChildScrollView(
          child: Text(
            metadata.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            style: GoogleFonts.poppins(fontSize: 13),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Sluiten')),
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day}-${dt.month}-${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  Widget _emptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.inbox, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(message, style: GoogleFonts.poppins(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // ─── Tab 4: Feature Flags (Fase E) ──────────────────────────
  Widget _buildFlagsTab() {
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Feature Flags',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Configureer instellingen zonder deploy. Alleen admins kunnen wijzigingen doorvoeren.',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          if (_featureFlags.isEmpty)
            _emptyState('Geen feature flags gevonden')
          else
            ..._buildFlagsByCategory(),
        ],
      ),
    );
  }

  List<Widget> _buildFlagsByCategory() {
    final categories = <String, List<Map<String, dynamic>>>{};
    for (final f in _featureFlags) {
      final flag = Map<String, dynamic>.from(f as Map);
      final cat = flag['category'] as String? ?? 'general';
      categories.putIfAbsent(cat, () => []);
      categories[cat]!.add(flag);
    }

    final categoryLabels = {
      'onboarding': 'Onboarding',
      'billing': 'Billing & Betalingen',
      'security': 'Security',
      'general': 'Algemeen',
    };

    final sortedKeys = categories.keys.toList()
      ..sort((a, b) => (categoryLabels[a] ?? a).compareTo(categoryLabels[b] ?? b));

    final widgets = <Widget>[];
    for (final cat in sortedKeys) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(
          categoryLabels[cat] ?? cat.toUpperCase(),
          style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
        ),
      ));
      for (final flag in categories[cat]!) {
        widgets.add(_flagCard(flag));
      }
    }
    return widgets;
  }

  Widget _flagCard(Map<String, dynamic> flag) {
    final key = flag['key'] as String? ?? '';
    final name = flag['name'] as String? ?? key;
    final desc = flag['description'] as String? ?? '';
    final enabled = flag['enabled'] == true;
    final value = flag['value'] as String?;
    final valueType = flag['value_type'] as String? ?? 'boolean';
    final rollout = (flag['rollout_percentage'] as num?)?.toDouble() ?? 100;

    final isConfigurable = valueType != 'boolean' && value != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(name,
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Switch(
                  value: enabled,
                  activeColor: GymiesColors.darkBlue,
                  onChanged: (val) => _toggleFlag(key, val),
                ),
              ],
            ),
            if (desc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(desc,
                    style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
              ),
            if (isConfigurable) ...[
              Row(
                children: [
                  Text('Waarde: ',
                      style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: GymiesColors.darkBlue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(value ?? '-',
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => _editFlagValue(key, name, value ?? '', valueType),
                    child: Icon(Icons.edit, size: 16, color: GymiesColors.darkBlue),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],
            if (rollout < 100)
              Row(
                children: [
                  Icon(Icons.pie_chart, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  Text('Rollout: ${rollout.toStringAsFixed(0)}%',
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFlag(String key, bool enabled) async {
    final action = enabled ? 'inschakelen' : 'uitschakelen';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Feature flag $action', style: GoogleFonts.poppins(fontSize: 15)),
        content: Text('Weet je zeker dat je "$key" wilt $action?',
            style: GoogleFonts.poppins(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: enabled ? Colors.green : Colors.red,
            ),
            child: Text(enabled ? 'Inschakelen' : 'Uitschakelen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final api = context.read<GymiesApi>();
      await api.updateFeatureFlag(key, enabled: enabled);
      GymiesHaptics.success();
      _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Tab 5: Support Tickets (Fase G) ─────────────────────────

  Future<void> _loadTickets() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffTickets(
        status: _ticketStatusFilter.isNotEmpty ? _ticketStatusFilter : null,
        priority: _ticketPriorityFilter.isNotEmpty ? _ticketPriorityFilter : null,
        q: _ticketSearch.isNotEmpty ? _ticketSearch : null,
        assignedToMe: _ticketAssignedToMe ? true : null,
      );
      if (!mounted) return;
      setState(() {
        _tickets = res['data'] as List? ?? [];
        _ticketTotal = res['total'] as int? ?? 0;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tickets laden mislukt: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadTicketStats() async {
    try {
      final api = context.read<GymiesApi>();
      final stats = await api.getStaffTicketStats();
      if (mounted) setState(() => _ticketStats = stats);
    } catch (_) {}
  }

  Widget _buildSupportTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadTickets();
        await _loadTicketStats();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Stats bar
          if (_ticketStats.isNotEmpty) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _miniStat('Nieuw', _ticketStats['new'] ?? 0, Colors.blue),
                  _miniStat('In behandeling', _ticketStats['in_progress'] ?? 0, Colors.orange),
                  _miniStat('Wacht op klant', _ticketStats['waiting_customer'] ?? 0, Colors.amber),
                  _miniStat('Mijn tickets', _ticketStats['assigned_to_me'] ?? 0, GymiesColors.darkBlue),
                  _miniStat('SLA overschreden', _ticketStats['sla_breached'] ?? 0, Colors.red),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Fase I: Actieknoppen
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('Nieuw Ticket', style: TextStyle(fontSize: 11)), onPressed: _showCreateTicket),
                const SizedBox(width: 6),
                ActionChip(avatar: const Icon(Icons.merge, size: 16), label: const Text('Samenvoegen', style: TextStyle(fontSize: 11)), onPressed: _showMergeTickets),
                const SizedBox(width: 6),
                ActionChip(avatar: const Icon(Icons.auto_fix_high, size: 16), label: const Text('Auto-assign', style: TextStyle(fontSize: 11)), onPressed: _autoAssignTickets),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Search + filters
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ticketSearchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Zoek tickets...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  style: GoogleFonts.poppins(fontSize: 13),
                  onSubmitted: (val) {
                    _ticketSearch = val.trim();
                    _loadTickets();
                  },
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: Icon(Icons.filter_list,
                    color: _ticketStatusFilter.isNotEmpty ? GymiesColors.darkBlue : Colors.grey),
                tooltip: 'Filter op status',
                onSelected: (val) {
                  setState(() => _ticketStatusFilter = val == 'all' ? '' : val);
                  _loadTickets();
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'all', child: Text('Alle')),
                  const PopupMenuItem(value: 'new', child: Text('Nieuw')),
                  const PopupMenuItem(value: 'in_progress', child: Text('In behandeling')),
                  const PopupMenuItem(value: 'waiting_customer', child: Text('Wacht op klant')),
                  const PopupMenuItem(value: 'resolved', child: Text('Opgelost')),
                ],
              ),
              IconButton(
                icon: Icon(Icons.person,
                    color: _ticketAssignedToMe ? GymiesColors.darkBlue : Colors.grey, size: 20),
                tooltip: 'Mijn tickets',
                onPressed: () {
                  setState(() => _ticketAssignedToMe = !_ticketAssignedToMe);
                  _loadTickets();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('$_ticketTotal tickets',
              style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          if (_tickets.isEmpty)
            _emptyState('Geen tickets gevonden')
          else
            ..._tickets.map((t) => _ticketCard(t as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _miniStat(String label, int count, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text('$count',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          Text(label, style: GoogleFonts.poppins(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  Widget _ticketCard(Map<String, dynamic> ticket) {
    final id = ticket['id'] as int? ?? 0;
    final subject = ticket['subject'] as String? ?? 'Geen onderwerp';
    final status = ticket['status'] as String? ?? 'new';
    final priority = ticket['priority'] as String? ?? 'medium';
    final userName = (ticket['user_name'] as String? ?? '').trim();
    final userEmail = ticket['user_email'] as String? ?? '';
    final assignedName = (ticket['assigned_name'] as String? ?? '').trim();
    final slaBreached = ticket['sla_breached'] == true;
    final createdAt = ticket['created_at'] as String? ?? '';

    final statusColor = switch (status) {
      'new' => Colors.blue,
      'in_progress' => Colors.orange,
      'waiting_customer' => Colors.amber,
      'resolved' => Colors.green,
      _ => Colors.grey,
    };

    final priorityIcon = switch (priority) {
      'critical' => Icons.priority_high,
      'high' => Icons.arrow_upward,
      'low' => Icons.arrow_downward,
      _ => Icons.remove,
    };

    final priorityColor = switch (priority) {
      'critical' => Colors.red,
      'high' => Colors.orange,
      'low' => Colors.grey,
      _ => Colors.blue,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: slaBreached
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Colors.red, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: () => _openTicketDetail(id),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(priorityIcon, size: 16, color: priorityColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(subject,
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_statusLabel(status),
                        style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(userName.isNotEmpty ? userName : userEmail,
                      style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey.shade600)),
                  const Spacer(),
                  if (assignedName.isNotEmpty)
                    Row(children: [
                      Icon(Icons.person, size: 12, color: Colors.grey.shade400),
                      const SizedBox(width: 2),
                      Text(assignedName.split(' ').first,
                          style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
                    ]),
                  if (slaBreached) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.warning_amber, size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 2),
                    Text('SLA!',
                        style: GoogleFonts.poppins(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(width: 8),
                  Text(_formatDate(createdAt),
                      style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'new' => 'Nieuw',
      'in_progress' => 'In behandeling',
      'waiting_customer' => 'Wacht op klant',
      'resolved' => 'Opgelost',
      _ => status,
    };
  }

  Future<void> _openTicketDetail(int ticketId) async {
    // Laad detail + berichten
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffTicketDetail(ticketId);
      if (!mounted) return;
      Navigator.of(context).pop(); // Sluit loading

      final ticket = res['data'] as Map<String, dynamic>? ?? {};
      final messages = (res['messages'] as List?) ?? [];

      _showTicketDetailSheet(ticket, messages);
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ticket laden mislukt: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showTicketDetailSheet(Map<String, dynamic> ticket, List<dynamic> messages) {
    final ticketId = ticket['id'] as int? ?? 0;
    final subject = ticket['subject'] as String? ?? '';
    final status = ticket['status'] as String? ?? 'new';
    final priority = ticket['priority'] as String? ?? 'medium';
    final userName = (ticket['user_name'] as String? ?? '').trim();
    final slaBreached = ticket['sla_breached'] == true;
    final replyCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (ctx2, scrollCtrl) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx2).viewInsets.bottom,
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: slaBreached ? Colors.red.shade50 : null,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('#$ticketId: $subject',
                                  style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => Navigator.pop(ctx2),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: [
                            _chipLabel(_statusLabel(status), _statusColor(status)),
                            _chipLabel(priority, _priorityColor(priority)),
                            if (userName.isNotEmpty) _chipLabel(userName, Colors.grey),
                            if (slaBreached) _chipLabel('SLA!', Colors.red),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Quick actions
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _ticketActionBtn('In behandeling', Icons.play_arrow, Colors.orange,
                                  () => _updateTicketStatus(ticketId, 'in_progress', ctx2)),
                              const SizedBox(width: 6),
                              _ticketActionBtn('Wacht op klant', Icons.hourglass_bottom, Colors.amber,
                                  () => _updateTicketStatus(ticketId, 'waiting_customer', ctx2)),
                              const SizedBox(width: 6),
                              _ticketActionBtn('Oplossen', Icons.check_circle, Colors.green,
                                  () => _updateTicketStatus(ticketId, 'resolved', ctx2)),
                              const SizedBox(width: 6),
                              _ticketActionBtn('Claim', Icons.person_add, GymiesColors.darkBlue,
                                  () => _claimTicket(ticketId, ctx2)),
                              const SizedBox(width: 6),
                              _ticketActionBtn('Escaleren', Icons.arrow_upward, Colors.deepOrange,
                                  () { Navigator.pop(ctx2); _escalateTicket(ticketId); }),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Messages
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (ctx3, i) {
                        final msg = messages[i] as Map<String, dynamic>;
                        return _messageBubble(msg);
                      },
                    ),
                  ),
                  // Reply bar
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      border: Border(top: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: replyCtrl,
                            decoration: InputDecoration(
                              hintText: 'Typ een bericht...',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            style: GoogleFonts.poppins(fontSize: 13),
                            maxLines: 3,
                            minLines: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Extern (klant ziet het)
                        IconButton(
                          icon: const Icon(Icons.send, size: 20),
                          color: GymiesColors.darkBlue,
                          tooltip: 'Extern antwoord (klant ziet dit)',
                          onPressed: () async {
                            final text = replyCtrl.text.trim();
                            if (text.isEmpty) return;
                            await _sendTicketReply(ticketId, text, false);
                            replyCtrl.clear();
                            Navigator.pop(ctx2);
                            _openTicketDetail(ticketId); // Heropen met nieuwe berichten
                          },
                        ),
                        // Intern (alleen staff)
                        IconButton(
                          icon: const Icon(Icons.sticky_note_2, size: 20),
                          color: Colors.orange,
                          tooltip: 'Interne notitie (alleen staff)',
                          onPressed: () async {
                            final text = replyCtrl.text.trim();
                            if (text.isEmpty) return;
                            await _sendTicketReply(ticketId, text, true);
                            replyCtrl.clear();
                            Navigator.pop(ctx2);
                            _openTicketDetail(ticketId);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _messageBubble(Map<String, dynamic> msg) {
    final body = msg['message'] as String? ?? '';
    final authorName = (msg['author_name'] as String? ?? '').trim();
    final authorRole = msg['author_role'] as String? ?? '';
    final isInternal = msg['is_internal'] == 1 || msg['is_internal'] == true;
    final createdAt = msg['created_at'] as String? ?? '';
    final isStaff = ['admin', 'staff', 'medewerker'].contains(authorRole);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isInternal
            ? Colors.amber.shade50
            : isStaff
                ? GymiesColors.darkBlue.withOpacity(0.06)
                : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: isInternal ? Border.all(color: Colors.amber.shade200) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(authorName.isNotEmpty ? authorName : 'Onbekend',
                  style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600)),
              if (isInternal) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('INTERN', style: GoogleFonts.poppins(fontSize: 8, fontWeight: FontWeight.w700)),
                ),
              ],
              const Spacer(),
              Text(_formatDate(createdAt),
                  style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 4),
          Text(body, style: GoogleFonts.poppins(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _chipLabel(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'new' => Colors.blue,
      'in_progress' => Colors.orange,
      'waiting_customer' => Colors.amber,
      'resolved' => Colors.green,
      _ => Colors.grey,
    };
  }

  Color _priorityColor(String priority) {
    return switch (priority) {
      'critical' => Colors.red,
      'high' => Colors.orange,
      'low' => Colors.grey,
      _ => Colors.blue,
    };
  }

  Widget _ticketActionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        textStyle: GoogleFonts.poppins(fontSize: 11),
      ),
    );
  }

  Future<void> _updateTicketStatus(int ticketId, String newStatus, BuildContext sheetCtx) async {
    try {
      final api = context.read<GymiesApi>();
      await api.updateStaffTicket(ticketId, {'status': newStatus, 'reason': 'Status gewijzigd via dashboard'});
      GymiesHaptics.success();
      if (mounted) {
        Navigator.pop(sheetCtx);
        _loadTickets();
        _loadTicketStats();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _claimTicket(int ticketId, BuildContext sheetCtx) async {
    try {
      final api = context.read<GymiesApi>();
      // We sturen de user ID niet mee — de backend leest staff.id uit de auth
      // We zetten assigned_to_user_id op een speciale waarde
      // Eigenlijk moeten we het huidige staff ID kennen — we halen het via _stats of direct
      await api.updateStaffTicket(ticketId, {
        'assigned_to_user_id': -1, // Backend interpreteert dit of we sturen separaat
        'reason': 'Ticket geclaimd via dashboard',
      });
      GymiesHaptics.success();
      if (mounted) {
        Navigator.pop(sheetCtx);
        _loadTickets();
        _loadTicketStats();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _sendTicketReply(int ticketId, String message, bool isInternal) async {
    try {
      final api = context.read<GymiesApi>();
      await api.addStaffTicketMessage(ticketId, message: message, isInternal: isInternal);
      GymiesHaptics.success();
      _loadTickets();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bericht versturen mislukt: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ─── Tab 6: Intern Chat (Fase G) ───────────────────────────

  Future<void> _loadChat() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffChatMessages(channel: _chatChannel);
      final channels = await api.getStaffChatChannels();
      if (!mounted) return;
      setState(() {
        _chatMessages = res['data'] as List? ?? [];
        _chatHasMore = res['has_more'] == true;
        _chatChannels = channels;
      });
      _scrollChatToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chat laden mislukt: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollCtrl.hasClients) {
        _chatScrollCtrl.animateTo(
          _chatScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        // Channel selector
        Container(
          height: 44,
          color: Colors.grey.shade50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              // Always show general first
              _channelChip('general'),
              ..._chatChannels
                  .where((c) => (c['channel'] as String? ?? '') != 'general')
                  .map((c) => _channelChip(c['channel'] as String? ?? '')),
              // Add channel button
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('Kanaal'),
                  labelStyle: GoogleFonts.poppins(fontSize: 11),
                  onPressed: _createChannel,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Messages
        Expanded(
          child: _chatMessages.isEmpty
              ? _emptyState('Nog geen berichten in #$_chatChannel')
              : ListView.builder(
                  controller: _chatScrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _chatMessages.length + (_chatHasMore ? 1 : 0),
                  itemBuilder: (ctx, i) {
                    if (_chatHasMore && i == 0) {
                      return Center(
                        child: TextButton(
                          onPressed: _loadOlderMessages,
                          child: const Text('Oudere berichten laden'),
                        ),
                      );
                    }
                    final idx = _chatHasMore ? i - 1 : i;
                    final msg = _chatMessages[idx] as Map<String, dynamic>;
                    return _chatBubble(msg);
                  },
                ),
        ),
        // Input bar
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatMsgCtrl,
                  decoration: InputDecoration(
                    hintText: 'Typ een bericht in #$_chatChannel...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  style: GoogleFonts.poppins(fontSize: 13),
                  maxLines: 3,
                  minLines: 1,
                  onSubmitted: (_) => _sendChatMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send),
                color: GymiesColors.darkBlue,
                onPressed: _sendChatMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _channelChip(String channel) {
    final isActive = channel == _chatChannel;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text('#$channel'),
        labelStyle: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          color: isActive ? Colors.white : Colors.black87,
        ),
        selected: isActive,
        selectedColor: GymiesColors.darkBlue,
        onSelected: (sel) {
          if (sel && channel != _chatChannel) {
            setState(() => _chatChannel = channel);
            _loadChat();
          }
        },
      ),
    );
  }

  Widget _chatBubble(Map<String, dynamic> msg) {
    final senderName = (msg['sender_name'] as String? ?? '').trim();
    final body = msg['message'] as String? ?? '';
    final createdAt = msg['created_at'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: GymiesColors.darkBlue.withOpacity(0.1),
            child: Text(
              senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
              style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(senderName.isNotEmpty ? senderName : 'Onbekend',
                        style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Text(_formatDate(createdAt),
                        style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(body, style: GoogleFonts.poppins(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendChatMessage() async {
    final text = _chatMsgCtrl.text.trim();
    if (text.isEmpty) return;

    try {
      final api = context.read<GymiesApi>();
      final result = await api.sendStaffChatMessage(message: text, channel: _chatChannel);
      GymiesHaptics.success();

      // Voeg direct toe aan lijst voor snelle feedback
      if (mounted) {
        setState(() {
          _chatMessages.add(result);
        });
        _scrollChatToBottom();
      }
      // Clear message input AFTER successful send
      _chatMsgCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Versturen mislukt: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_chatMessages.isEmpty) return;
    final firstId = _chatMessages.first['id'] as int? ?? 0;
    if (firstId <= 0) return;

    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffChatMessages(channel: _chatChannel, before: firstId);
      final older = res['data'] as List? ?? [];
      if (mounted && older.isNotEmpty) {
        setState(() {
          _chatMessages.insertAll(0, older);
          _chatHasMore = res['has_more'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _createChannel() async {
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nieuw kanaal', style: GoogleFonts.poppins(fontSize: 16)),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'Kanaalnaam (kleine letters, geen spaties)',
            hintText: 'bijv. bugs, planning, vragen',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aanmaken'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final channelName = nameCtrl.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-]'), '-');
    if (channelName.isEmpty) return;

    setState(() => _chatChannel = channelName);
    _loadChat();
  }

  Future<void> _editFlagValue(String key, String name, String currentValue, String valueType) async {
    final ctrl = TextEditingController(text: currentValue);
    final inputType = (valueType == 'integer' || valueType == 'float')
        ? TextInputType.numberWithOptions(decimal: valueType == 'float')
        : TextInputType.text;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name, style: GoogleFonts.poppins(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: $valueType',
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: inputType,
              decoration: InputDecoration(
                labelText: 'Waarde',
                border: const OutlineInputBorder(),
                hintText: valueType == 'integer' ? 'bijv. 48' : 'bijv. 0.01',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final newVal = ctrl.text.trim();
    if (newVal == currentValue) return;

    try {
      final api = context.read<GymiesApi>();
      await api.updateFeatureFlag(key, value: newVal);
      GymiesHaptics.success();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name bijgewerkt naar: $newVal'),
            backgroundColor: Colors.green,
          ),
        );
        _loadAll();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── Fase H: Data Loaders ─────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadTrainers() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffTrainers(
        search: _trainerSearch.isEmpty ? null : _trainerSearch,
        status: _trainerStatusFilter.isEmpty ? null : _trainerStatusFilter,
      );
      if (!mounted) return;
      setState(() {
        _allTrainers = (res['data'] as List?) ?? [];
        _trainerTotal = (res['total'] as int?) ?? _allTrainers.length;
      });
    } catch (e) {
      debugPrint('_loadTrainers error: $e');
    }
  }

  Future<void> _loadBookingsMonitor() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffBookingsMonitor();
      if (!mounted) return;
      setState(() => _bookingsMonitor = res);
    } catch (e) {
      debugPrint('_loadBookingsMonitor error: $e');
    }
  }

  Future<void> _loadPipeline() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffOnboardingPipeline();
      if (!mounted) return;
      setState(() => _pipelineData = res);
    } catch (e) {
      debugPrint('_loadPipeline error: $e');
    }
  }

  Future<void> _loadDisputes() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffDisputes(
        status: _disputeStatusFilter.isEmpty ? null : _disputeStatusFilter,
      );
      if (!mounted) return;
      setState(() {
        _disputes = (res['data'] as List?) ?? [];
        _disputeTotal = (res['total'] as int?) ?? _disputes.length;
      });
    } catch (e) {
      debugPrint('_loadDisputes error: $e');
    }
  }

  Future<void> _loadCannedResponses() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffCannedResponses();
      if (!mounted) return;
      setState(() => _cannedResponses = res);
    } catch (e) {
      debugPrint('_loadCannedResponses error: $e');
    }
  }

  Future<void> _loadChatUnreadCounts() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffChatUnreadCounts();
      if (!mounted) return;
      final counts = (res['counts'] as Map?)?.map((k, v) => MapEntry(k.toString(), (v as int?) ?? 0)) ?? {};
      setState(() => _chatUnreadCounts = counts);
    } catch (e) {
      debugPrint('_loadChatUnreadCounts error: $e');
    }
  }

  Future<void> _loadDashboardExtended() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffDashboardExtended();
      if (!mounted) return;
      setState(() => _dashboardExtended = res);
    } catch (e) {
      debugPrint('_loadDashboardExtended error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── H.2: Trainers Tab ────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTrainersTab() {
    return Column(
      children: [
        // Zoekbalk + filters
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _trainerSearchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Zoek trainer (naam, email)...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                  onSubmitted: (v) {
                    _trainerSearch = v;
                    _loadTrainers();
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _trainerStatusFilter.isEmpty ? null : _trainerStatusFilter,
                hint: const Text('Status'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Alle')),
                  DropdownMenuItem(value: 'pending_review', child: Text('Pending')),
                  DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                  DropdownMenuItem(value: 'incomplete', child: Text('Incomplete')),
                ],
                onChanged: (v) {
                  setState(() => _trainerStatusFilter = v ?? '');
                  _loadTrainers();
                },
              ),
            ],
          ),
        ),
        // Totaal label
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$_trainerTotal trainers gevonden',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ),
        const Divider(height: 1),
        // Lijst
        Expanded(
          child: _allTrainers.isEmpty
              ? const Center(child: Text('Geen trainers gevonden'))
              : ListView.builder(
                  itemCount: _allTrainers.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (ctx, i) {
                    final t = _allTrainers[i] as Map<String, dynamic>;
                    final status = t['onboarding_status'] ?? 'unknown';
                    final name = '${t['user_name'] ?? ''}'.trim();
                    final email = t['user_email'] ?? '';
                    final city = t['trainer_city'] ?? '';
                    final actScore = t['activity_score'] ?? 0;

                    Color statusColor;
                    switch (status) {
                      case 'active': statusColor = Colors.green; break;
                      case 'approved': statusColor = Colors.blue; break;
                      case 'suspended': statusColor = Colors.red; break;
                      case 'pending_review': statusColor = Colors.orange; break;
                      default: statusColor = Colors.grey;
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.15),
                          child: Icon(Icons.person, color: statusColor, size: 20),
                        ),
                        title: Text(name.isNotEmpty ? name : 'Trainer #${t['id']}',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (email.isNotEmpty) Text(email, style: const TextStyle(fontSize: 12)),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(status, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
                                ),
                                if (city.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Icon(Icons.location_on, size: 12, color: Colors.grey[500]),
                                  Text(city, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                ],
                                const Spacer(),
                                Text('Score: $actScore', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                              ],
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showTrainerDetail(t['id'] as int),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// H.1: Trainer detail bottom sheet
  void _showTrainerDetail(int trainerId) async {
    try {
      final api = context.read<GymiesApi>();
      final detail = await api.getStaffTrainerDetail(trainerId);
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (ctx, scrollCtrl) {
            final profile = detail['profile'] as Map<String, dynamic>? ?? {};
            final docs = (detail['documents'] as List?) ?? [];
            final subscription = detail['subscription'] as Map<String, dynamic>? ?? {};
            final etalage = detail['etalage_completeness'] as Map<String, dynamic>? ?? {};
            final extensions = (detail['trial_extensions'] as List?) ?? [];
            final activity = detail['activity_snapshot'] as Map<String, dynamic>? ?? {};

            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(16),
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 12),
                Text('Trainer Detail', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${profile['company_name'] ?? 'Geen bedrijfsnaam'}', style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600])),
                const Divider(height: 24),

                // Profiel info
                _detailSection('Profiel', [
                  _detailRow('Status', profile['onboarding_status'] ?? '-'),
                  _detailRow('KvK', profile['kvk_number'] ?? '-'),
                  _detailRow('IBAN', profile['iban'] ?? '-'),
                  _detailRow('Stad', profile['trainer_city'] ?? '-'),
                  _detailRow('Slug', profile['profile_slug'] ?? '-'),
                  _detailRow('Trial eindigt', profile['trial_ends_at'] ?? '-'),
                ]),

                // Etalage completeness
                _detailSection('Etalage Completeness', [
                  _detailRow('Score', '${etalage['total_score'] ?? 0}/100'),
                  ...(etalage['fields'] as Map<String, dynamic>? ?? {}).entries.map(
                    (e) => _detailRow(e.key, e.value == true ? '✓' : '✗'),
                  ),
                ]),

                // Activity snapshot
                _detailSection('Activiteit', [
                  _detailRow('Etalage score', '${activity['etalage_score'] ?? 0}'),
                  _detailRow('Boekingen (30d)', '${activity['bookings_count'] ?? 0}'),
                  _detailRow('Berichten (30d)', '${activity['messages_count'] ?? 0}'),
                  _detailRow('App opens (7d)', '${activity['app_opens_7d'] ?? 0}'),
                  _detailRow('Totaalscore', '${activity['total_score'] ?? 0}'),
                ]),

                // Subscription
                if (subscription.isNotEmpty) _detailSection('Abonnement', [
                  _detailRow('Plan', subscription['plan_name'] ?? '-'),
                  _detailRow('Status', subscription['status'] ?? '-'),
                  _detailRow('Mollie ID', subscription['mollie_subscription_id'] ?? '-'),
                ]),

                // Documenten
                if (docs.isNotEmpty) _detailSection('Documenten (${docs.length})', [
                  ...docs.map((d) {
                    final doc = d as Map<String, dynamic>;
                    return _detailRow(doc['document_type'] ?? 'Doc', doc['status'] ?? '-');
                  }),
                ]),

                // Trial extensions
                if (extensions.isNotEmpty) _detailSection('Trial Verlengingen (${extensions.length})', [
                  ...extensions.map((ext) {
                    final e = ext as Map<String, dynamic>;
                    return _detailRow('+${e['days']} dagen', e['created_at'] ?? '-');
                  }),
                ]),

                // ─── Fase I: Acties op trainer ─────────────────
                const Divider(height: 24),
                Text('Acties', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.note_add, size: 16),
                      label: const Text('Notities', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showTrainerNotes(trainerId);
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.notifications_active, size: 16),
                      label: const Text('Nudge', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showSendNudge(trainerId);
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text('Conversaties', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showUserConversations(trainerId);
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.card_membership, size: 16),
                      label: const Text('Subscription', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showAssignSubscription(trainerId);
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.pause_circle_outline, size: 16),
                      label: const Text('Pauzeer/Hervat Sub', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _toggleSubscription(trainerId);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Document review actions (inline per doc)
                if (docs.isNotEmpty) ...[
                  Text('Documenten Beoordelen', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                  const SizedBox(height: 4),
                  ...docs.map((d) {
                    final doc = d as Map<String, dynamic>;
                    final docStatus = doc['status'] ?? 'pending';
                    final docId = doc['id'] as int? ?? 0;
                    final docType = doc['document_type'] ?? 'doc';
                    return ListTile(
                      dense: true,
                      title: Text(docType, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      subtitle: Text('Status: $docStatus', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      trailing: docStatus == 'pending' || docStatus == 'uploaded'
                          ? TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showReviewDocument(docId, docType);
                              },
                              child: const Text('Beoordelen', style: TextStyle(fontSize: 11)),
                            )
                          : Text(docStatus == 'approved' ? '✓' : '✗', style: TextStyle(color: docStatus == 'approved' ? Colors.green : Colors.red)),
                    );
                  }),
                ],
              ],
            );
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
        const SizedBox(height: 4),
        ...children,
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── H.3: Bookings Monitor Tab ────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBookingsTab() {
    if (_bookingsMonitor.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final today = (_bookingsMonitor['today'] as List?) ?? [];
    final tomorrow = (_bookingsMonitor['tomorrow'] as List?) ?? [];
    final alerts = (_bookingsMonitor['alerts'] as Map<String, dynamic>?) ?? {};
    final noShows = (alerts['no_shows'] as int?) ?? 0;
    final cancellations = (alerts['cancellations'] as int?) ?? 0;
    final paymentFailures = (alerts['payment_failures'] as int?) ?? 0;

    return RefreshIndicator(
      onRefresh: _loadBookingsMonitor,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Alerts bar
          if (noShows > 0 || cancellations > 0 || paymentFailures > 0)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  if (noShows > 0) _alertChip('No-shows: $noShows', Colors.red),
                  if (cancellations > 0) _alertChip('Annuleringen: $cancellations', Colors.orange),
                  if (paymentFailures > 0) _alertChip('Betaal fouten: $paymentFailures', Colors.deepOrange),
                ],
              ),
            ),

          // Vandaag
          Text('Vandaag (${today.length} boekingen)', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (today.isEmpty) const Text('Geen boekingen vandaag', style: TextStyle(color: Colors.grey)),
          ...today.map((b) => _bookingCard(b as Map<String, dynamic>)),

          const SizedBox(height: 20),

          // Morgen
          Text('Morgen (${tomorrow.length} boekingen)', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (tomorrow.isEmpty) const Text('Geen boekingen morgen', style: TextStyle(color: Colors.grey)),
          ...tomorrow.map((b) => _bookingCard(b as Map<String, dynamic>)),
        ],
      ),
    );
  }

  Widget _alertChip(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _bookingCard(Map<String, dynamic> b) {
    final status = b['status'] ?? 'unknown';
    final time = b['scheduled_at'] ?? '';
    final trainer = b['trainer_name'] ?? '';
    final client = b['client_name'] ?? '';
    Color sc;
    switch (status) {
      case 'confirmed': sc = Colors.green; break;
      case 'cancelled': sc = Colors.red; break;
      case 'no_show': sc = Colors.deepOrange; break;
      case 'payment_failed': sc = Colors.red[700]!; break;
      default: sc = Colors.grey;
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.event, color: sc, size: 20),
        title: Text('$trainer → $client', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        subtitle: Text(time, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: sc.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
          child: Text(status, style: TextStyle(fontSize: 10, color: sc, fontWeight: FontWeight.w600)),
        ),
        onTap: b['id'] != null ? () => _showBookingDetail(b['id'] as int) : null,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── H.4: Pipeline Tab ────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPipelineTab() {
    if (_pipelineData.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final stages = (_pipelineData['stages'] as Map<String, dynamic>?) ?? {};
    final totalTrainers = (_pipelineData['total'] as int?) ?? 0;

    final stageOrder = ['incomplete', 'pending_review', 'approved', 'active', 'suspended'];
    final stageLabels = {
      'incomplete': 'Incompleet',
      'pending_review': 'Wacht op review',
      'approved': 'Goedgekeurd',
      'active': 'Actief',
      'suspended': 'Geschorst',
    };
    final stageColors = {
      'incomplete': Colors.grey,
      'pending_review': Colors.orange,
      'approved': Colors.blue,
      'active': Colors.green,
      'suspended': Colors.red,
    };

    return RefreshIndicator(
      onRefresh: _loadPipeline,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Onboarding Pipeline', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
          Text('$totalTrainers trainers totaal', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 16),

          ...stageOrder.map((stage) {
            final stageData = stages[stage] as Map<String, dynamic>? ?? {};
            final count = (stageData['count'] as int?) ?? 0;
            final trainers = (stageData['trainers'] as List?) ?? [];
            final color = stageColors[stage] ?? Colors.grey;
            final pct = totalTrainers > 0 ? (count / totalTrainers * 100) : 0.0;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ExpansionTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withOpacity(0.15),
                  child: Text('$count', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                ),
                title: Text(stageLabels[stage] ?? stage, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: LinearProgressIndicator(
                  value: pct / 100,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation(color),
                ),
                children: trainers.isEmpty
                    ? [const Padding(padding: EdgeInsets.all(16), child: Text('Geen trainers in deze fase'))]
                    : trainers.map((t) {
                        final trainer = t as Map<String, dynamic>;
                        return ListTile(
                          dense: true,
                          title: Text('${trainer['user_name'] ?? 'Trainer #${trainer['id']}'}', style: const TextStyle(fontSize: 13)),
                          subtitle: Text(trainer['user_email'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          trailing: Text('Docs: ${trainer['docs_count'] ?? 0}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                          onTap: () => _showTrainerDetail(trainer['id'] as int),
                        );
                      }).toList(),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── H.6: Disputes Tab ────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDisputesTab() {
    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text('Geschillen', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              DropdownButton<String>(
                value: _disputeStatusFilter.isEmpty ? null : _disputeStatusFilter,
                hint: const Text('Status'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Alle')),
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(value: 'in_progress', child: Text('In behandeling')),
                  DropdownMenuItem(value: 'resolved', child: Text('Opgelost')),
                  DropdownMenuItem(value: 'closed', child: Text('Gesloten')),
                ],
                onChanged: (v) {
                  setState(() => _disputeStatusFilter = v ?? '');
                  _loadDisputes();
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('$_disputeTotal geschillen', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _disputes.isEmpty
              ? const Center(child: Text('Geen geschillen gevonden'))
              : ListView.builder(
                  itemCount: _disputes.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (ctx, i) {
                    final d = _disputes[i] as Map<String, dynamic>;
                    final status = d['status'] ?? 'open';
                    final reason = d['reason'] ?? '';
                    final clientName = d['client_name'] ?? 'Klant';
                    final trainerName = d['trainer_name'] ?? 'Trainer';
                    final createdAt = d['created_at'] ?? '';

                    Color sc;
                    switch (status) {
                      case 'open': sc = Colors.orange; break;
                      case 'in_progress': sc = Colors.blue; break;
                      case 'resolved': sc = Colors.green; break;
                      case 'closed': sc = Colors.grey; break;
                      default: sc = Colors.grey;
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: sc.withOpacity(0.15),
                          child: Icon(Icons.gavel, color: sc, size: 18),
                        ),
                        title: Text('$clientName vs $trainerName',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (reason.isNotEmpty) Text(reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: sc.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                                  child: Text(status, style: TextStyle(fontSize: 10, color: sc, fontWeight: FontWeight.w600)),
                                ),
                                const Spacer(),
                                Text(createdAt, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                              ],
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right, size: 18),
                        onTap: () => _showDisputeDetail(d['id'] as int),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── H.5: Canned Responses Picker (voor Support tab) ─────────
  // ═══════════════════════════════════════════════════════════════

  void _showCannedResponsePicker(TextEditingController targetCtrl) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Standaard Antwoorden', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showCreateCannedResponse();
                  },
                ),
              ],
            ),
            const Divider(),
            if (_cannedResponses.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Geen standaard antwoorden')),
            ..._cannedResponses.map((cr) {
              final r = cr as Map<String, dynamic>;
              return ListTile(
                dense: true,
                title: Text(r['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: Text(r['body'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  onPressed: () async {
                    try {
                      final api = context.read<GymiesApi>();
                      await api.deleteStaffCannedResponse(r['id'] as int);
                      _loadCannedResponses();
                      if (mounted) Navigator.pop(ctx);
                    } catch (e) {
                      debugPrint('Delete canned response error: $e');
                    }
                  },
                ),
                onTap: () {
                  targetCtrl.text = r['body'] ?? '';
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showCreateCannedResponse() {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nieuw Standaard Antwoord', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Titel', isDense: true)),
            const SizedBox(height: 8),
            TextField(controller: bodyCtrl, decoration: const InputDecoration(labelText: 'Tekst', isDense: true), maxLines: 4),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () async {
              if (titleCtrl.text.isEmpty || bodyCtrl.text.isEmpty) return;
              try {
                final api = context.read<GymiesApi>();
                await api.createStaffCannedResponse(title: titleCtrl.text, body: bodyCtrl.text);
                _loadCannedResponses();
                if (mounted) Navigator.pop(ctx);
              } catch (e) {
                debugPrint('Create canned response error: $e');
              }
            },
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── H.7: Auto-assign Tickets actie ───────────────────────────
  // ═══════════════════════════════════════════════════════════════

  Future<void> _autoAssignTickets() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.staffAutoAssignTickets();
      final assigned = res['assigned'] ?? 0;
      if (mounted) {
        GymiesHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$assigned tickets automatisch toegewezen'), backgroundColor: Colors.green),
        );
        _loadTickets();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── FASE I: DATA LOADERS ─────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  Future<void> _loadGroupSessions() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffGroupSessions();
      if (!mounted) return;
      setState(() => _groupSessionsData = res);
    } catch (e) {
      debugPrint('_loadGroupSessions error: $e');
    }
  }

  Future<void> _loadPayments() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffPaymentsOverview();
      if (!mounted) return;
      setState(() => _paymentsData = res);
    } catch (e) {
      debugPrint('_loadPayments error: $e');
    }
  }

  Future<void> _loadGyms() async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffGymsOverview(
        search: _gymsSearch.isEmpty ? null : _gymsSearch,
      );
      if (!mounted) return;
      setState(() => _gymsData = res);
    } catch (e) {
      debugPrint('_loadGyms error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.1: Dispute Detail + Resolve + Berichten ────────────────
  // ═══════════════════════════════════════════════════════════════

  void _showDisputeDetail(int disputeId) async {
    try {
      final api = context.read<GymiesApi>();
      final detail = await api.getStaffDisputeDetail(disputeId);
      if (!mounted) return;

      final dispute = detail['dispute'] as Map<String, dynamic>? ?? detail;
      final messages = (detail['messages'] as List?) ?? [];
      final booking = detail['booking'] as Map<String, dynamic>? ?? {};

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (ctx, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Text('Geschil Detail', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
              const Divider(height: 24),

              _detailSection('Info', [
                _detailRow('Status', dispute['status'] ?? '-'),
                _detailRow('Reden', dispute['reason'] ?? '-'),
                _detailRow('Klant', dispute['client_name'] ?? '-'),
                _detailRow('Trainer', dispute['trainer_name'] ?? '-'),
                _detailRow('Aangemaakt', dispute['created_at'] ?? '-'),
              ]),

              if (booking.isNotEmpty) _detailSection('Booking', [
                _detailRow('ID', '${booking['id'] ?? '-'}'),
                _detailRow('Datum', booking['scheduled_at'] ?? '-'),
                _detailRow('Bedrag', '€${((booking['amount_cents'] ?? 0) / 100).toStringAsFixed(2)}'),
              ]),

              if (messages.isNotEmpty) ...[
                Text('Berichten (${messages.length})', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
                const SizedBox(height: 8),
                ...messages.map((m) {
                  final msg = m as Map<String, dynamic>;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(msg['author_name'] ?? 'Onbekend', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                            const Spacer(),
                            Text(msg['created_at'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                          ]),
                          const SizedBox(height: 4),
                          Text(msg['message'] ?? '', style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              const SizedBox(height: 16),

              // Actieknoppen
              if (dispute['status'] != 'resolved' && dispute['status'] != 'closed') ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.message, size: 16),
                        label: const Text('Bericht', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showAddDisputeMessage(disputeId);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check_circle, size: 16),
                        label: const Text('Oplossen', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showResolveDispute(disputeId);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showAddDisputeMessage(int disputeId) {
    final msgCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Bericht Toevoegen', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(controller: msgCtrl, decoration: const InputDecoration(labelText: 'Bericht', isDense: true), maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () async {
              if (msgCtrl.text.isEmpty) return;
              try {
                final api = context.read<GymiesApi>();
                await api.staffAddDisputeMessage(disputeId, message: msgCtrl.text);
                if (mounted) { Navigator.pop(ctx); GymiesHaptics.success(); _loadDisputes(); }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('Versturen'),
          ),
        ],
      ),
    );
  }

  void _showResolveDispute(int disputeId) {
    String resType = 'client_gelijk';
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text('Geschil Oplossen', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: resType,
                decoration: const InputDecoration(labelText: 'Beslissing', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'client_gelijk', child: Text('Klant gelijk')),
                  DropdownMenuItem(value: 'trainer_gelijk', child: Text('Trainer gelijk')),
                  DropdownMenuItem(value: 'split', child: Text('Compromis (split)')),
                ],
                onChanged: (v) => setLocalState(() => resType = v ?? 'client_gelijk'),
              ),
              const SizedBox(height: 8),
              TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Toelichting', isDense: true), maxLines: 3),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
            FilledButton(
              onPressed: () async {
                if (noteCtrl.text.isEmpty) return;
                try {
                  final api = context.read<GymiesApi>();
                  await api.staffResolveDispute(disputeId, resolutionType: resType, resolutionNote: noteCtrl.text);
                  if (mounted) {
                    Navigator.pop(ctx);
                    GymiesHaptics.success();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geschil opgelost'), backgroundColor: Colors.green));
                    _loadDisputes();
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
                }
              },
              child: const Text('Oplossen'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.2: Ticket Aanmaken ─────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  void _showCreateTicket() {
    final userIdCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = 'normal';
    String category = 'general';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text('Ticket Aanmaken', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: userIdCtrl, decoration: const InputDecoration(labelText: 'Gebruiker ID', isDense: true), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextField(controller: subjectCtrl, decoration: const InputDecoration(labelText: 'Onderwerp', isDense: true)),
                const SizedBox(height: 8),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Beschrijving', isDense: true), maxLines: 3),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: priority,
                  decoration: const InputDecoration(labelText: 'Prioriteit', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Laag')),
                    DropdownMenuItem(value: 'normal', child: Text('Normaal')),
                    DropdownMenuItem(value: 'high', child: Text('Hoog')),
                    DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                  ],
                  onChanged: (v) => setLocalState(() => priority = v ?? 'normal'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Categorie', isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'general', child: Text('Algemeen')),
                    DropdownMenuItem(value: 'billing', child: Text('Facturatie')),
                    DropdownMenuItem(value: 'technical', child: Text('Technisch')),
                    DropdownMenuItem(value: 'onboarding', child: Text('Onboarding')),
                  ],
                  onChanged: (v) => setLocalState(() => category = v ?? 'general'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
            FilledButton(
              onPressed: () async {
                final uid = int.tryParse(userIdCtrl.text);
                if (uid == null || subjectCtrl.text.isEmpty || descCtrl.text.isEmpty) return;
                try {
                  final api = context.read<GymiesApi>();
                  await api.staffCreateTicket(userId: uid, subject: subjectCtrl.text, description: descCtrl.text, priority: priority, category: category);
                  if (mounted) {
                    Navigator.pop(ctx);
                    GymiesHaptics.success();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket aangemaakt'), backgroundColor: Colors.green));
                    _loadTickets();
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
                }
              },
              child: const Text('Aanmaken'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.3: Booking Detail + Cancel + Reschedule ────────────────
  // ═══════════════════════════════════════════════════════════════

  void _showBookingDetail(int bookingId) async {
    try {
      final api = context.read<GymiesApi>();
      final detail = await api.getStaffBookingDetail(bookingId);
      if (!mounted) return;

      final booking = detail['booking'] as Map<String, dynamic>? ?? detail;
      final payments = (detail['payments'] as List?) ?? [];

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (ctx, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Text('Booking Detail', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
              const Divider(height: 24),

              _detailSection('Info', [
                _detailRow('Status', booking['status'] ?? '-'),
                _detailRow('Trainer', booking['trainer_name'] ?? '-'),
                _detailRow('Klant', booking['client_name'] ?? '-'),
                _detailRow('Datum', booking['scheduled_at'] ?? '-'),
                _detailRow('Bedrag', '€${((booking['amount_cents'] ?? 0) / 100).toStringAsFixed(2)}'),
                _detailRow('Type', booking['booking_type'] ?? '-'),
              ]),

              if (payments.isNotEmpty) _detailSection('Betalingen (${payments.length})', [
                ...payments.map((p) {
                  final pay = p as Map<String, dynamic>;
                  return _detailRow('€${((pay['amount_cents'] ?? 0) / 100).toStringAsFixed(2)}', '${pay['status'] ?? '-'} (${pay['created_at'] ?? ''})');
                }),
              ]),

              const SizedBox(height: 16),

              // Actieknoppen
              if (booking['status'] != 'cancelled' && booking['status'] != 'completed') ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule, size: 16),
                        label: const Text('Verplaatsen', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showRescheduleBooking(bookingId);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cancel, size: 16, color: Colors.red),
                        label: const Text('Annuleren', style: TextStyle(fontSize: 12, color: Colors.red)),
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showCancelBooking(bookingId);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.money_off, size: 16),
                    label: const Text('Refund / Credit', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showRefundOrCredit(bookingId);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
    }
  }

  void _showCancelBooking(int bookingId) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Booking Annuleren', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reden', isDense: true), maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Terug')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (reasonCtrl.text.isEmpty) return;
              try {
                final api = context.read<GymiesApi>();
                await api.staffCancelBooking(bookingId, reason: reasonCtrl.text);
                if (mounted) {
                  Navigator.pop(ctx);
                  GymiesHaptics.success();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking geannuleerd'), backgroundColor: Colors.green));
                  _loadBookingsMonitor();
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('Annuleren'),
          ),
        ],
      ),
    );
  }

  void _showRescheduleBooking(int bookingId) {
    final dateCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Booking Verplaatsen', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dateCtrl,
              decoration: const InputDecoration(labelText: 'Nieuwe datum (YYYY-MM-DD HH:MM)', isDense: true),
              onTap: () async {
                final picked = await showDatePicker(context: ctx, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                if (picked != null) {
                  final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
                  if (time != null) {
                    dateCtrl.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                  }
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reden', isDense: true), maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () async {
              if (dateCtrl.text.isEmpty || reasonCtrl.text.isEmpty) return;
              try {
                final api = context.read<GymiesApi>();
                await api.staffRescheduleBooking(bookingId, scheduledAt: dateCtrl.text, reason: reasonCtrl.text);
                if (mounted) {
                  Navigator.pop(ctx);
                  GymiesHaptics.success();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking verplaatst'), backgroundColor: Colors.green));
                  _loadBookingsMonitor();
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('Verplaatsen'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.4: Refund / Credit ─────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  void _showRefundOrCredit(int bookingId) {
    String refundType = 'wallet_credit';
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text('Refund / Credit', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: refundType,
                decoration: const InputDecoration(labelText: 'Type', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'wallet_credit', child: Text('Wallet credit')),
                  DropdownMenuItem(value: 'partial_refund', child: Text('Gedeeltelijke refund')),
                ],
                onChanged: (v) => setLocalState(() => refundType = v ?? 'wallet_credit'),
              ),
              const SizedBox(height: 8),
              TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: 'Bedrag (€, max 50)', isDense: true), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reden', isDense: true), maxLines: 2),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(child: Text('Staff refund limiet: max €50', style: TextStyle(fontSize: 11, color: Colors.orange))),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text);
                if (amount == null || amount <= 0 || reasonCtrl.text.isEmpty) return;
                if (amount > 50) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max €50 voor staff refunds'), backgroundColor: Colors.orange));
                  return;
                }
                try {
                  final api = context.read<GymiesApi>();
                  await api.staffRefundOrCredit(bookingId, type: refundType, amountCents: (amount * 100).round(), reason: reasonCtrl.text);
                  if (mounted) {
                    Navigator.pop(ctx);
                    GymiesHaptics.success();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('€${amount.toStringAsFixed(2)} $refundType verwerkt'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
                }
              },
              child: const Text('Verwerken'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.5: Document Review ─────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  void _showReviewDocument(int documentId, String docType) {
    String decision = 'approved';
    final rejectionCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text('Document Beoordelen', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Type: $docType', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: decision,
                decoration: const InputDecoration(labelText: 'Beslissing', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'approved', child: Text('Goedkeuren')),
                  DropdownMenuItem(value: 'rejected', child: Text('Afkeuren')),
                ],
                onChanged: (v) => setLocalState(() => decision = v ?? 'approved'),
              ),
              if (decision == 'rejected') ...[
                const SizedBox(height: 8),
                TextField(controller: rejectionCtrl, decoration: const InputDecoration(labelText: 'Reden afkeuring', isDense: true), maxLines: 3),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
            FilledButton(
              onPressed: () async {
                try {
                  final api = context.read<GymiesApi>();
                  await api.staffReviewDocument(documentId, decision: decision, rejectionReason: decision == 'rejected' ? rejectionCtrl.text : null);
                  if (mounted) {
                    Navigator.pop(ctx);
                    GymiesHaptics.success();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Document $decision'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
                }
              },
              child: const Text('Bevestigen'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.6: Trainer Notities ────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  void _showTrainerNotes(int userId) async {
    try {
      final api = context.read<GymiesApi>();
      final notes = await api.getStaffTrainerNotes(userId);
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) {
          final noteCtrl = TextEditingController();
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              builder: (ctx, scrollCtrl) => ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 12),
                  Text('Interne Notities', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
                  const Divider(height: 16),

                  // Add note
                  Row(
                    children: [
                      Expanded(
                        child: TextField(controller: noteCtrl, decoration: const InputDecoration(hintText: 'Notitie toevoegen...', isDense: true, border: OutlineInputBorder()), maxLines: 2),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.blue),
                        onPressed: () async {
                          if (noteCtrl.text.isEmpty) return;
                          try {
                            await api.staffAddTrainerNote(userId, note: noteCtrl.text);
                            noteCtrl.clear();
                            if (mounted) {
                              Navigator.pop(ctx);
                              GymiesHaptics.success();
                              _showTrainerNotes(userId); // Refresh
                            }
                          } catch (e) {
                            debugPrint('Add note error: $e');
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (notes.isEmpty)
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Geen notities'))),
                  ...notes.map((n) {
                    final note = n;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Text(note['author_name'] ?? 'Staff', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              if (note['category'] != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4)),
                                  child: Text(note['category'], style: TextStyle(fontSize: 10, color: Colors.blue[700])),
                                ),
                              ],
                              const Spacer(),
                              Text(note['created_at'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                            ]),
                            const SizedBox(height: 4),
                            Text(note['note'] ?? '', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.7: Nudge Push Notificatie ──────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  void _showSendNudge(int userId) {
    String nudgeType = 'complete_onboarding';
    final customMsgCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text('Nudge Versturen', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: nudgeType,
                decoration: const InputDecoration(labelText: 'Type', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'complete_onboarding', child: Text('Onboarding afronden')),
                  DropdownMenuItem(value: 'upload_documents', child: Text('Documenten uploaden')),
                  DropdownMenuItem(value: 'setup_etalage', child: Text('Etalage instellen')),
                  DropdownMenuItem(value: 'payment_reminder', child: Text('Betaalherinnering')),
                  DropdownMenuItem(value: 'custom', child: Text('Custom bericht')),
                ],
                onChanged: (v) => setLocalState(() => nudgeType = v ?? 'complete_onboarding'),
              ),
              if (nudgeType == 'custom') ...[
                const SizedBox(height: 8),
                TextField(controller: customMsgCtrl, decoration: const InputDecoration(labelText: 'Custom bericht', isDense: true), maxLines: 3),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
            FilledButton(
              onPressed: () async {
                try {
                  final api = context.read<GymiesApi>();
                  await api.staffSendNudge(userId: userId, type: nudgeType, customMessage: nudgeType == 'custom' ? customMsgCtrl.text : null);
                  if (mounted) {
                    Navigator.pop(ctx);
                    GymiesHaptics.success();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nudge verstuurd'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
                }
              },
              child: const Text('Versturen'),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.8: Trainer-Klant Chat Inzien ───────────────────────────
  // ═══════════════════════════════════════════════════════════════

  void _showUserConversations(int userId) async {
    try {
      final api = context.read<GymiesApi>();
      final conversations = await api.getStaffUserConversations(userId);
      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (ctx, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Text('Conversaties', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                child: const Row(
                  children: [
                    Icon(Icons.visibility, size: 16, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(child: Text('Alleen-lezen inzage — wordt gelogd', style: TextStyle(fontSize: 11, color: Colors.blue))),
                  ],
                ),
              ),
              const Divider(height: 16),
              if (conversations.isEmpty) const Center(child: Text('Geen conversaties gevonden')),
              ...conversations.map((c) {
                final conv = c;
                return Card(
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.chat_bubble_outline, size: 20),
                    title: Text('${conv['other_user_name'] ?? 'Gebruiker'}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(conv['last_message_preview'] ?? 'Geen berichten', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                    trailing: Text(conv['last_message_at'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showConversationMessages(conv['id'] as int);
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
    }
  }

  void _showConversationMessages(int conversationId) async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.getStaffConversation(conversationId);
      if (!mounted) return;

      final messages = (res['messages'] as List?) ?? [];
      final conversation = res['conversation'] as Map<String, dynamic>? ?? {};

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (ctx, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Text('Chat Berichten (alleen-lezen)', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
              Text('${conversation['user_1_name'] ?? ''} ↔ ${conversation['user_2_name'] ?? ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const Divider(height: 16),
              if (messages.isEmpty) const Center(child: Text('Geen berichten')),
              ...messages.map((m) {
                final msg = m as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(msg['sender_name'] ?? 'Onbekend', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          const Spacer(),
                          Text(msg['created_at'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                        ]),
                        const SizedBox(height: 4),
                        Text(msg['body'] ?? msg['message'] ?? '', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.11: Subscription Toewijzen/Pauzeren ────────────────────
  // ═══════════════════════════════════════════════════════════════

  void _showAssignSubscription(int userId) {
    final planIdCtrl = TextEditingController();
    String billingCycle = 'monthly';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text('Subscription Toewijzen', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: planIdCtrl, decoration: const InputDecoration(labelText: 'Plan ID', isDense: true), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: billingCycle,
                decoration: const InputDecoration(labelText: 'Factuurcyclus', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'monthly', child: Text('Maandelijks')),
                  DropdownMenuItem(value: 'yearly', child: Text('Jaarlijks')),
                ],
                onChanged: (v) => setLocalState(() => billingCycle = v ?? 'monthly'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
            FilledButton(
              onPressed: () async {
                final planId = int.tryParse(planIdCtrl.text);
                if (planId == null) return;
                try {
                  final api = context.read<GymiesApi>();
                  await api.staffAssignSubscription(userId, planId: planId, billingCycle: billingCycle);
                  if (mounted) {
                    Navigator.pop(ctx);
                    GymiesHaptics.success();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Subscription toegewezen'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
                }
              },
              child: const Text('Toewijzen'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleSubscription(int userId) async {
    try {
      final api = context.read<GymiesApi>();
      final res = await api.staffToggleSubscription(userId);
      if (mounted) {
        GymiesHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscription ${res['new_status'] ?? 'gewijzigd'}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.12: Ticket Merge + Escalatie ───────────────────────────
  // ═══════════════════════════════════════════════════════════════

  void _showMergeTickets() {
    final primaryCtrl = TextEditingController();
    final secondaryCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tickets Samenvoegen', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: primaryCtrl, decoration: const InputDecoration(labelText: 'Primair Ticket ID', isDense: true), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            TextField(controller: secondaryCtrl, decoration: const InputDecoration(labelText: 'Secundair Ticket ID (wordt gesloten)', isDense: true), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(
            onPressed: () async {
              final pId = int.tryParse(primaryCtrl.text);
              final sId = int.tryParse(secondaryCtrl.text);
              if (pId == null || sId == null) return;
              try {
                final api = context.read<GymiesApi>();
                await api.staffMergeTickets(primaryTicketId: pId, secondaryTicketId: sId);
                if (mounted) {
                  Navigator.pop(ctx);
                  GymiesHaptics.success();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tickets samengevoegd'), backgroundColor: Colors.green));
                  _loadTickets();
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('Samenvoegen'),
          ),
        ],
      ),
    );
  }

  Future<void> _escalateTicket(int ticketId) async {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ticket Escaleren', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reden escalatie', isDense: true), maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              if (reasonCtrl.text.isEmpty) return;
              try {
                final api = context.read<GymiesApi>();
                await api.staffEscalateTicket(ticketId, reason: reasonCtrl.text);
                if (mounted) {
                  Navigator.pop(ctx);
                  GymiesHaptics.success();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ticket geëscaleerd naar admin'), backgroundColor: Colors.orange));
                  _loadTickets();
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('Escaleren'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.9: Groepslessen Tab ────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  Widget _buildGroupSessionsTab() {
    if (_groupSessionsData.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final sessions = (_groupSessionsData['sessions'] as List?) ?? [];
    final stats = _groupSessionsData['stats'] as Map<String, dynamic>? ?? {};

    return RefreshIndicator(
      onRefresh: _loadGroupSessions,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Groepslessen', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          // Stats row
          Row(
            children: [
              _statCard('Vandaag', '${stats['today'] ?? 0}', Colors.blue),
              const SizedBox(width: 8),
              _statCard('Deze week', '${stats['this_week'] ?? sessions.length}', Colors.green),
              const SizedBox(width: 8),
              _statCard('Lage opkomst', '${stats['low_enrollment'] ?? 0}', Colors.orange),
            ],
          ),
          const SizedBox(height: 16),

          if (sessions.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Geen groepslessen deze week')))
          else
            ...sessions.map((s) {
              final session = s as Map<String, dynamic>;
              final participants = (session['participant_count'] as int?) ?? 0;
              final capacity = (session['capacity'] as int?) ?? 0;
              final fillPct = capacity > 0 ? participants / capacity : 0.0;

              Color fillColor;
              if (fillPct >= 0.8) { fillColor = Colors.green; }
              else if (fillPct >= 0.4) { fillColor = Colors.orange; }
              else { fillColor = Colors.red; }

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: fillColor.withOpacity(0.15),
                    child: Text('$participants', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fillColor)),
                  ),
                  title: Text(session['title'] ?? 'Sessie', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${session['trainer_name'] ?? ''} — ${session['scheduled_at'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      LinearProgressIndicator(
                        value: fillPct,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation(fillColor),
                      ),
                      Text('$participants / $capacity deelnemers', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => _showGroupSessionDetail(session['id'] as int),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
            Text(label, style: TextStyle(fontSize: 10, color: color)),
          ],
        ),
      ),
    );
  }

  void _showGroupSessionDetail(int sessionId) async {
    try {
      final api = context.read<GymiesApi>();
      final detail = await api.getStaffGroupSessionDetail(sessionId);
      if (!mounted) return;

      final session = detail['session'] as Map<String, dynamic>? ?? detail;
      final participants = (detail['participants'] as List?) ?? [];
      final waitlist = (detail['waitlist'] as List?) ?? [];

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (ctx, scrollCtrl) => ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 12),
              Text('Groepsles Detail', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700)),
              const Divider(height: 24),

              _detailSection('Info', [
                _detailRow('Titel', session['title'] ?? '-'),
                _detailRow('Trainer', session['trainer_name'] ?? '-'),
                _detailRow('Datum', session['scheduled_at'] ?? '-'),
                _detailRow('Capaciteit', '${session['capacity'] ?? '-'}'),
                _detailRow('Deelnemers', '${participants.length}'),
                _detailRow('Wachtlijst', '${waitlist.length}'),
              ]),

              if (participants.isNotEmpty) _detailSection('Deelnemers (${participants.length})', [
                ...participants.map((p) {
                  final part = p as Map<String, dynamic>;
                  return _detailRow(part['user_name'] ?? 'Deelnemer', part['status'] ?? 'registered');
                }),
              ]),

              if (waitlist.isNotEmpty) _detailSection('Wachtlijst (${waitlist.length})', [
                ...waitlist.map((w) {
                  final wait = w as Map<String, dynamic>;
                  return _detailRow(wait['user_name'] ?? 'Wachtend', wait['created_at'] ?? '');
                }),
              ]),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fout: $e'), backgroundColor: Colors.red));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.10: Betalingen Tab ─────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPaymentsTab() {
    if (_paymentsData.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final payments = (_paymentsData['data'] as List?) ?? (_paymentsData['payments'] as List?) ?? [];
    final todayStats = _paymentsData['today_stats'] as Map<String, dynamic>? ?? {};
    final todayRevenue = (todayStats['revenue_cents'] as int?) ?? 0;
    final todayCount = (todayStats['count'] as int?) ?? 0;
    final todayFailed = (todayStats['failed'] as int?) ?? 0;

    return RefreshIndicator(
      onRefresh: _loadPayments,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Betalingen', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          // Today stats
          Row(
            children: [
              _statCard('Omzet vandaag', '€${(todayRevenue / 100).toStringAsFixed(2)}', Colors.green),
              const SizedBox(width: 8),
              _statCard('Transacties', '$todayCount', Colors.blue),
              const SizedBox(width: 8),
              _statCard('Mislukt', '$todayFailed', todayFailed > 0 ? Colors.red : Colors.grey),
            ],
          ),
          const SizedBox(height: 16),

          if (payments.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Geen betalingen gevonden')))
          else
            ...payments.map((p) {
              final payment = p as Map<String, dynamic>;
              final status = payment['status'] ?? 'unknown';
              final amountCents = (payment['amount_cents'] as int?) ?? 0;

              Color sc;
              switch (status) {
                case 'paid': sc = Colors.green; break;
                case 'pending': sc = Colors.orange; break;
                case 'failed': sc = Colors.red; break;
                case 'refunded': sc = Colors.purple; break;
                default: sc = Colors.grey;
              }

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  dense: true,
                  leading: Icon(Icons.payment, color: sc, size: 20),
                  title: Text('€${(amountCents / 100).toStringAsFixed(2)}',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('${payment['user_name'] ?? ''} — ${payment['description'] ?? ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: sc.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                        child: Text(status, style: TextStyle(fontSize: 10, color: sc, fontWeight: FontWeight.w600)),
                      ),
                      Text(payment['created_at'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ─── I.13: Gyms Tab ───────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════════

  Widget _buildGymsTab() {
    return Column(
      children: [
        // Zoekbalk
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _gymsSearchCtrl,
            decoration: InputDecoration(
              hintText: 'Zoek gym/studio...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            ),
            onSubmitted: (v) {
              _gymsSearch = v;
              _loadGyms();
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _gymsData.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadGyms,
                  child: Builder(
                    builder: (ctx) {
                      final gyms = (_gymsData['data'] as List?) ?? (_gymsData['organisations'] as List?) ?? [];
                      if (gyms.isEmpty) return const Center(child: Text('Geen gyms gevonden'));

                      return ListView.builder(
                        itemCount: gyms.length,
                        padding: const EdgeInsets.all(8),
                        itemBuilder: (ctx, i) {
                          final gym = gyms[i] as Map<String, dynamic>;
                          final members = (gym['member_count'] as int?) ?? 0;
                          final trainers = (gym['trainer_count'] as int?) ?? 0;

                          final gymId = (gym['id'] ?? '').toString();
                          final gymName = gym['name'] ?? 'Gym #$gymId';

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            child: Column(
                              children: [
                                ListTile(
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: GymiesColors.darkBlue.withOpacity(0.1),
                                    child: const Icon(Icons.fitness_center, size: 18, color: GymiesColors.darkBlue),
                                  ),
                                  title: Text(gymName,
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                                  subtitle: Row(
                                    children: [
                                      Icon(Icons.people, size: 14, color: Colors.grey[500]),
                                      Text(' $members leden', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                      const SizedBox(width: 12),
                                      Icon(Icons.sports, size: 14, color: Colors.grey[500]),
                                      Text(' $trainers trainers', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                    ],
                                  ),
                                  trailing: Text(gym['city'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => Navigator.push(context,
                                            MaterialPageRoute(builder: (_) => GymChurnReportScreen(gymId: gymId, gymName: gymName))),
                                          icon: const Icon(Icons.trending_down, size: 16),
                                          label: const Text('Churn', style: TextStyle(fontSize: 12)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: GymiesColors.darkBlue,
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => Navigator.push(context,
                                            MaterialPageRoute(builder: (_) => GymLocationsScreen(orgId: gymId, orgName: gymName))),
                                          icon: const Icon(Icons.location_on, size: 16),
                                          label: const Text('Locaties', style: TextStyle(fontSize: 12)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: GymiesColors.darkBlue,
                                            padding: const EdgeInsets.symmetric(vertical: 6),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
