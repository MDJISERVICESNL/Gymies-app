import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../services/subscription_entitlements_service.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'trainer_client_dossier_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_segment_tab_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/gymies_upgrade_prompt.dart';
import 'widgets/trainer_state_views.dart';
import '../utils/haptics.dart';

/// Klanten CRM-centrum: Overzicht, Inzichten (Pro), Analytics (Pro+), Communicatie (Pro+).
class TrainerClientsScreen extends StatefulWidget {
  const TrainerClientsScreen({super.key});

  @override
  State<TrainerClientsScreen> createState() => _TrainerClientsScreenState();
}

class _TrainerClientsScreenState extends State<TrainerClientsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // ── Overzicht data ──
  bool _clientsLoading = true;
  String? _clientsError;
  List<Map<String, dynamic>> _clients = [];
  String _searchQuery = '';

  // ── Inzichten data (Pro Hub) ──
  bool _insightsLoading = true;
  String? _insightsError;
  List<Map<String, dynamic>> _health = [];
  List<Map<String, dynamic>> _upsell = [];
  List<Map<String, dynamic>> _rebook = [];
  bool _insightsBusy = false;

  // ── Auto-Rebook settings ──
  bool _autoRebookEnabled = false;
  int _rebookIntervalDays = 7;
  bool _rebookSettingsLoading = false;
  List<Map<String, dynamic>> _packageExpiring = [];

  // ── Analytics data ──
  bool _analyticsLoading = true;
  String? _analyticsError;
  int _activeCount = 0;
  int _riskCount = 0;
  int _inactiveCount = 0;
  double _totalRevenue = 0;
  int _totalSessions = 0;
  List<Map<String, dynamic>> _analyticsClients = [];
  List<Map<String, dynamic>> _filteredAnalyticsClients = [];
  String _analyticsFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadClients();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final ent = context.read<SubscriptionEntitlementsService>();
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isPro = tierLower.contains('pro') || tierLower == 'studio';
    final isProPlus = tierLower.contains('pro_plus') ||
        tierLower.contains('proplus') ||
        tierLower == 'studio';

    if (_tabController.index == 1 && isPro && _health.isEmpty && !_insightsLoading) {
      _loadInsights();
    }
    if (_tabController.index == 2 && isProPlus && _analyticsClients.isEmpty && !_analyticsLoading) {
      _loadAnalytics();
    }
  }

  // ── Load Clients (Overzicht) ──
  Future<void> _loadClients() async {
    setState(() {
      _clientsLoading = true;
      _clientsError = null;
    });
    try {
      final list = await context.read<GymiesApi>().getTrainerSleepingClients();
      if (!mounted) return;
      setState(() {
        _clients = list;
        _clientsLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _clientsError = e.message;
        _clientsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _clientsError = 'Kon klantenoverzicht niet laden.';
        _clientsLoading = false;
      });
    }
  }

  // ── Load Insights (Pro Hub data) ──
  Future<void> _loadInsights() async {
    setState(() {
      _insightsLoading = true;
      _insightsError = null;
    });
    try {
      final api = context.read<GymiesApi>();
      final results = await Future.wait([
        api.getTrainerClientHealthScores(),
        api.getTrainerUpsellSuggestions(),
        api.getTrainerRebookSuggestions(),
      ]);
      if (!mounted) return;
      setState(() {
        _health = (results[0] is List)
            ? List<Map<String, dynamic>>.from(results[0] as List)
            : <Map<String, dynamic>>[];
        _upsell = (results[1] is List)
            ? List<Map<String, dynamic>>.from(results[1] as List)
            : <Map<String, dynamic>>[];
        _rebook = (results[2] is List)
            ? List<Map<String, dynamic>>.from(results[2] as List)
            : <Map<String, dynamic>>[];
        _insightsLoading = false;
      });
      // Also load rebook settings & expiring packages
      _loadRebookSettings();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _insightsError = e.message;
        _insightsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _insightsError = 'Kon inzichten niet laden.';
        _insightsLoading = false;
      });
    }
  }

  // ── Load Analytics (Pro+) ──
  Future<void> _loadAnalytics() async {
    setState(() {
      _analyticsLoading = true;
      _analyticsError = null;
    });
    try {
      final data = await context.read<GymiesApi>().getClientAnalytics();
      if (!mounted) return;
      final summary = data['summary'] as Map<String, dynamic>? ?? {};
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
            (summary['active_count'] as num?)?.toInt() ?? 0;
        _riskCount = (summary['risk'] as num?)?.toInt() ??
            (summary['risk_count'] as num?)?.toInt() ??
            (summary['at_risk'] as num?)?.toInt() ?? 0;
        _inactiveCount = (summary['inactive'] as num?)?.toInt() ??
            (summary['inactive_count'] as num?)?.toInt() ?? 0;
        _totalRevenue = (summary['total_revenue'] as num?)?.toDouble() ??
            (summary['revenue'] as num?)?.toDouble() ?? 0;
        _totalSessions = (summary['total_sessions'] as num?)?.toInt() ??
            (summary['sessions'] as num?)?.toInt() ?? 0;
        _analyticsClients = clients;
        _applyAnalyticsFilter();
        _analyticsLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _analyticsError = e.message;
        _analyticsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _analyticsError = 'Kon analytics niet laden.';
        _analyticsLoading = false;
      });
    }
  }

  // ── Helpers ──
  void _applyAnalyticsFilter() {
    if (_analyticsFilter == 'all') {
      _filteredAnalyticsClients = List.from(_analyticsClients);
    } else {
      _filteredAnalyticsClients = _analyticsClients.where((c) {
        final status = mapStr(c, ['status', 'client_status']).toLowerCase();
        if (_analyticsFilter == 'active') return status == 'active' || status == 'actief';
        if (_analyticsFilter == 'risk') {
          return status == 'risk' || status == 'at_risk' || status == 'risico';
        }
        if (_analyticsFilter == 'inactive') return status == 'inactive' || status == 'inactief';
        return true;
      }).toList();
    }
  }

  void _setAnalyticsFilter(String filter) {
    setState(() {
      _analyticsFilter = filter;
      _applyAnalyticsFilter();
    });
  }

  Color _healthColor(int score) {
    if (score >= 75) return Colors.green.shade700;
    if (score >= 50) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s == 'active' || s == 'actief') return Colors.green.shade700;
    if (s == 'new' || s == 'nieuw') return Colors.blue.shade700;
    if (s == 'risk' || s == 'at_risk' || s == 'risico') return Colors.orange.shade800;
    if (s == 'inactive' || s == 'inactief') return Colors.red.shade700;
    return GymiesColors.darkBlue;
  }

  String _statusLabel(String status) {
    final s = status.toLowerCase();
    if (s == 'active' || s == 'actief') return 'Actief';
    if (s == 'risk' || s == 'at_risk' || s == 'risico') return 'Risico';
    if (s == 'inactive' || s == 'inactief') return 'Inactief';
    if (s == 'new' || s == 'nieuw') return 'Nieuw';
    return status;
  }

  String _formatLastSession(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return dateStr;
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'Vandaag';
    if (diff.inDays == 1) return 'Gisteren';
    if (diff.inDays < 7) return '${diff.inDays} dagen geleden';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weken geleden';
    return '${(diff.inDays / 30).floor()} maanden geleden';
  }

  Future<void> _openClient(Map<String, dynamic> client) async {
    Haptics.selection();
    final clientId = mapStr(client, ['client_user_id', 'clientUserId', 'id']);
    if (clientId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Klant-ID ontbreekt.'), backgroundColor: Colors.red),
      );
      return;
    }
    final name = mapStr(client, ['name', 'full_name']).isNotEmpty
        ? mapStr(client, ['name', 'full_name'])
        : 'Klant';
    final email = mapStr(client, ['email', 'email_address']);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrainerClientDossierScreen(
          clientUserId: clientId,
          clientName: name,
          clientEmail: email,
        ),
      ),
    );
  }

  Future<void> _sendUpsell(Map<String, dynamic> item) async {
    if (_insightsBusy) return;
    Haptics.light();
    final suggestionId = mapStr(item, ['id', 'suggestion_id', 'suggestionId']).trim();
    if (suggestionId.isEmpty) return;
    setState(() => _insightsBusy = true);
    try {
      await context.read<GymiesApi>().sendTrainerUpsellSuggestion(
        suggestionId: suggestionId,
        clientUserId: mapStr(item, ['client_user_id', 'clientUserId']),
        packageId: mapStr(item, ['package_id', 'packageId']),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upsell voorstel verstuurd'), backgroundColor: GymiesColors.darkBlue),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _insightsBusy = false);
    }
  }

  Future<void> _sendRebook(Map<String, dynamic> item) async {
    if (_insightsBusy) return;
    Haptics.light();
    final clientUserId = mapStr(item, ['id', 'client_user_id', 'clientUserId']).trim();
    if (clientUserId.isEmpty) return;
    setState(() => _insightsBusy = true);
    try {
      await context.read<GymiesApi>().sendTrainerBulkMessage(
        clientUserIds: [clientUserId],
        body: 'We missen je! Plan je volgende sessie via Mijn afspraken in de app.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('We missen je-bericht verstuurd'), backgroundColor: GymiesColors.darkBlue),
      );
      _loadInsights();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _insightsBusy = false);
    }
  }

  // ── Auto-Rebook settings ──
  Future<void> _loadRebookSettings() async {
    try {
      final api = context.read<GymiesApi>();
      final settings = await api.getTrainerSettings();
      if (!mounted) return;
      setState(() {
        _autoRebookEnabled = settings['auto_rebook_enabled'] == true;
        _rebookIntervalDays = (settings['rebook_interval_days'] as num?)?.toInt() ?? 7;
      });
    } catch (_) {
      // Graceful: defaults remain
    }
    // Load expiring packages
    try {
      final api = context.read<GymiesApi>();
      final expiring = await api.getTrainerPackageExpiringSoon();
      if (!mounted) return;
      setState(() {
        _packageExpiring = (expiring is List)
            ? List<Map<String, dynamic>>.from(expiring)
            : <Map<String, dynamic>>[];
      });
    } catch (_) {
      // Graceful: empty list
    }
  }

  Future<void> _toggleAutoRebook(bool value) async {
    Haptics.light();
    setState(() {
      _autoRebookEnabled = value;
      _rebookSettingsLoading = true;
    });
    try {
      await context.read<GymiesApi>().updateTrainerSettings({
        'auto_rebook_enabled': value,
        'rebook_interval_days': _rebookIntervalDays,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value
              ? 'Auto-herboekingen ingeschakeld'
              : 'Auto-herboekingen uitgeschakeld'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _autoRebookEnabled = !value);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (mounted) setState(() => _autoRebookEnabled = !value);
    } finally {
      if (mounted) setState(() => _rebookSettingsLoading = false);
    }
  }

  Future<void> _updateRebookInterval(int days) async {
    Haptics.selection();
    final oldDays = _rebookIntervalDays;
    setState(() {
      _rebookIntervalDays = days;
      _rebookSettingsLoading = true;
    });
    try {
      await context.read<GymiesApi>().updateTrainerSettings({
        'auto_rebook_enabled': _autoRebookEnabled,
        'rebook_interval_days': days,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Interval bijgewerkt naar $days dagen'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _rebookIntervalDays = oldDays);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (mounted) setState(() => _rebookIntervalDays = oldDays);
    } finally {
      if (mounted) setState(() => _rebookSettingsLoading = false);
    }
  }

  void _showIntervalPicker() {
    Haptics.selection();
    final options = [3, 5, 7, 10, 14, 21, 30];
    showDialog<void>(
      context: context,
      builder: (ctx) => GymiesDialog(
        title: 'Herboek-interval',
        headerIcon: Icons.timer_outlined,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Na hoeveel dagen inactiviteit ontvangen klanten automatisch een herinnering?',
              style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options.map((d) {
                final selected = d == _rebookIntervalDays;
                return ChoiceChip(
                  label: Text('$d dagen'),
                  selected: selected,
                  onSelected: (_) {
                    Navigator.of(ctx).pop();
                    _updateRebookInterval(d);
                  },
                  selectedColor: GymiesColors.primary.withValues(alpha: 0.25),
                  checkmarkColor: GymiesColors.darkBlue,
                  labelStyle: GoogleFonts.sora(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? GymiesColors.darkBlue : Colors.grey.shade700,
                  ),
                  side: BorderSide(
                    color: selected ? GymiesColors.primary : Colors.grey.shade300,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          GymiesDialogAction(label: 'Sluiten', returnValue: null),
        ],
      ),
    );
  }

  Future<void> _sendRebookAll() async {
    if (_insightsBusy || _rebook.isEmpty) return;
    Haptics.light();
    final confirm = await GymiesDialog.custom<bool>(
      context,
      title: 'Alle herinneringen versturen?',
      icon: Icons.send_rounded,
      content: Text(
        'Er ${_rebook.length == 1 ? 'wordt 1 bericht' : 'worden ${_rebook.length} berichten'} verstuurd naar inactieve klanten.',
        style: GoogleFonts.sora(fontSize: 14),
      ),
      actions: [
        GymiesDialogAction(label: 'Annuleren', returnValue: false),
        GymiesDialogAction(label: 'Versturen', isPrimary: true, returnValue: true),
      ],
    );
    if (confirm != true || !mounted) return;
    setState(() => _insightsBusy = true);
    try {
      final ids = _rebook
          .map((e) => mapStr(e, ['id', 'client_user_id', 'clientUserId']).trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (ids.isEmpty) return;
      await context.read<GymiesApi>().sendTrainerBulkMessage(
        clientUserIds: ids,
        body: 'We missen je! Plan je volgende sessie via Mijn afspraken in de app.',
      );
      if (!mounted) return;
      Haptics.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${ids.length} herinnering${ids.length == 1 ? '' : 'en'} verstuurd'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
      _loadInsights();
    } on ApiException catch (e) {
      if (!mounted) return;
      Haptics.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _insightsBusy = false);
    }
  }

  Future<void> _bulkMessage() async {
    if (_clients.isEmpty) return;
    Haptics.selection();
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var sending = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => GymiesDialog(
            title: 'Bulk bericht',
            headerIcon: Icons.campaign_outlined,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  maxLines: 4,
                  enabled: !sending,
                  decoration: const InputDecoration(labelText: 'Bericht'),
                ),
                if (sending) ...[
                  const SizedBox(height: 16),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Versturen…'),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              GymiesDialogAction(
                label: 'Annuleren',
                returnValue: null,
              ),
              GymiesDialogAction(
                label: sending ? 'Bezig…' : 'Versturen',
                isPrimary: true,
                onPressed: sending
                    ? null
                    : () async {
                        if (controller.text.trim().isEmpty) return;
                        final ids = _clients
                            .map((e) => mapStr(e, ['client_user_id', 'clientUserId', 'id']))
                            .where((e) => e.isNotEmpty)
                            .toList();
                        if (ids.isEmpty) return;
                        setDialogState(() => sending = true);
                        try {
                          await context.read<GymiesApi>().sendTrainerBulkMessage(
                            clientUserIds: ids,
                            body: controller.text.trim(),
                          );
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Bulk bericht verstuurd'), backgroundColor: GymiesColors.darkBlue),
                          );
                        } on ApiException catch (e) {
                          if (ctx.mounted) setDialogState(() => sending = false);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                          );
                        } catch (e) {
                          if (ctx.mounted) setDialogState(() => sending = false);
                          if (kDebugMode) debugPrint('[TrainerClients] Bulk bericht fout: $e');
                        }
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPrioritySupportComposer() async {
    Haptics.selection();
    final issueCtrl = TextEditingController();
    final bookingCtrl = TextEditingController();
    final submit = await GymiesDialog.custom<bool>(
      context,
      title: 'Priority support lane',
      icon: Icons.priority_high_rounded,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: issueCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Issue',
              hintText: 'Beschrijf kort het urgente probleem',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: bookingCtrl,
            decoration: const InputDecoration(
              labelText: 'Booking reference (optioneel)',
            ),
          ),
        ],
      ),
      actions: [
        GymiesDialogAction(
          label: 'Annuleren',
          returnValue: false,
        ),
        GymiesDialogAction(
          label: 'Verstuur',
          isPrimary: true,
          returnValue: true,
        ),
      ],
    );
    if (submit != true || issueCtrl.text.trim().isEmpty) return;
    if (!mounted) return;
    try {
      await context.read<GymiesApi>().createSupportTicket(
        type: 'incident',
        subject: 'Priority support lane',
        message:
            'Priority issue: ${issueCtrl.text.trim()}\nBookingRef: ${bookingCtrl.text.trim().isEmpty ? '-' : bookingCtrl.text.trim()}\nSource: TrainerClients',
        bookingId: bookingCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Priority support ticket verstuurd'), backgroundColor: GymiesColors.darkBlue),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  Widget _sectionHeader(IconData icon, String label, {int? count}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.sora(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: GymiesColors.darkBlue,
              letterSpacing: 0.5,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '· $count',
              style: GoogleFonts.sora(
                fontSize: 11,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Segment Tab Builder ──
  // ──────────────────────────────────────────────
  // BUILD
  // ──────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ent = context.watch<SubscriptionEntitlementsService>();
    final tierLower = ent.tier?.toLowerCase() ?? 'starter';
    final isPro = tierLower.contains('pro') || tierLower == 'studio';
    final isProPlus = tierLower.contains('pro_plus') ||
        tierLower.contains('proplus') ||
        tierLower == 'studio';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: 'Klanten',
        actions: [
          GymiesAppBarAction(
            icon: Icons.search_rounded,
            tooltip: 'Zoek klant',
            onTap: () {
              _tabController.animateTo(0);
              // Focus will go to the search field in the overview tab
            },
          ),
          const SizedBox(width: 8),
          GymiesAppBarAction(
            icon: Icons.person_add_outlined,
            tooltip: 'Klant toevoegen',
            onTap: () {
              // TODO: open add client flow
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: GymiesSegmentTabBar(
          controller: _tabController,
          tabs: const ['Overzicht', 'Inzichten', 'Meer'],
          badges: [_clients.isEmpty ? null : _clients.length, null, null],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          isPro
              ? _buildInsightsTab()
              : const GymiesUpgradePrompt(
                  icon: Icons.insights_rounded,
                  feature: 'Klantinzichten',
                  tier: 'Pro',
                  description: 'Zie welke klanten dreigen af te haken en krijg AI-suggesties voor upsells en herboekingen.',
                ),
          isProPlus
              ? _buildMeerTab(isPro: isPro, isProPlus: isProPlus)
              : GymiesUpgradePrompt(
                  icon: Icons.analytics_outlined,
                  feature: 'Analytics & Communicatie',
                  tier: isPro ? 'Pro+' : 'Pro',
                  description: 'Segmenteer je klanten en stuur bulk berichten.',
                ),
        ],
      ),
    );
  }

  // ── Tab 0: Overzicht ──
  Widget _buildOverviewTab() {
    return GymiesListBody(
      loading: _clientsLoading,
      error: _clientsError,
      onRefresh: _loadClients,
      child: Column(
        children: [
          // Zoekbalk
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              style: GoogleFonts.sora(fontSize: 13, color: GymiesColors.darkBlue),
              decoration: InputDecoration(
                hintText: 'Zoek klant...',
                hintStyle: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade400, size: 20),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '${_filteredClients.length} klanten',
                    style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ),
                suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: GymiesColors.primary, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          // Klantenlijst
          Expanded(
            child: _clients.isEmpty
                ? ListView(
                    children: const [
                      TrainerEmptyState(
                        icon: Icons.people_alt_outlined,
                        title: 'Geen klanten gevonden',
                        subtitle: 'Klanten verschijnen hier zodra ze een sessie boeken.',
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _filteredClients.length,
                    itemBuilder: (_, i) {
                      final c = _filteredClients[i];
                      final name = mapStr(c, ['name', 'full_name']).isNotEmpty
                          ? mapStr(c, ['name', 'full_name'])
                          : 'Klant';
                      final email = mapStr(c, ['email', 'email_address']);
                      final sessionCount = mapInt(c, ['session_count', 'total_sessions', 'sessions']);
                      final status = mapStr(c, ['status', 'client_status']);
                      final statusClr = _statusColor(status);
                      final initials = name.length >= 2
                          ? '${name[0]}${name.split(' ').length > 1 ? name.split(' ').last[0] : name[1]}'.toUpperCase()
                          : (name.isNotEmpty ? name[0].toUpperCase() : '?');
                      final lastSession = mapStr(c, ['last_session_at', 'lastSessionAt', 'last_active']);
                      final lastLabel = lastSession.isNotEmpty
                          ? _formatLastSession(lastSession)
                          : (sessionCount > 0 ? '$sessionCount sessies' : 'Geen sessies');

                      final isInactive = status.toLowerCase() == 'inactive' || status.toLowerCase() == 'inactief';

                      return GestureDetector(
                        onTap: () => _openClient(c),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: IntrinsicHeight(
                            child: Row(
                              children: [
                                // ── 3px Stripe-style left accent ──
                                Container(
                                  width: 3,
                                  decoration: BoxDecoration(
                                    color: statusClr,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(3),
                                      bottomLeft: Radius.circular(3),
                                    ),
                                  ),
                                ),
                                // ── Card body ──
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(color: Colors.grey.shade200, width: 0.5),
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(10),
                                        bottomRight: Radius.circular(10),
                                      ),
                                    ),
                                    child: Opacity(
                                      opacity: isInactive ? 0.7 : 1.0,
                                      child: Row(
                                        children: [
                                          // ── Circle avatar ──
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: isInactive
                                                  ? statusClr
                                                  : GymiesColors.darkBlue,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Center(
                                              child: Text(
                                                initials,
                                                style: GoogleFonts.sora(
                                                  fontWeight: FontWeight.w600,
                                                  color: isInactive
                                                      ? Colors.white
                                                      : GymiesColors.primary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        name,
                                                        style: GoogleFonts.sora(
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 13,
                                                          color: GymiesColors.darkBlue,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                    if (status.isNotEmpty) ...[
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: statusClr.withValues(alpha: 0.08),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Text(
                                                          _statusLabel(status),
                                                          style: GoogleFonts.sora(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w600,
                                                            color: statusClr,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  '$sessionCount sessies · $lastLabel',
                                                  style: GoogleFonts.sora(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade500,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300, size: 18),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredClients {
    if (_searchQuery.isEmpty) return _clients;
    return _clients.where((c) {
      final name = mapStr(c, ['name', 'full_name']).toLowerCase();
      return name.contains(_searchQuery);
    }).toList();
  }

  // ── Tab 1: Inzichten (Pro Hub content) ──
  bool _insightsTriggered = false;

  Widget _buildInsightsTab() {
    if (_insightsLoading && _health.isEmpty) {
      // Eerste keer laden — maar slechts één keer triggeren
      if (!_insightsTriggered && _health.isEmpty && _upsell.isEmpty && _rebook.isEmpty) {
        _insightsTriggered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _health.isEmpty) _loadInsights();
        });
      }
      return const TrainerLoadingView();
    }
    return GymiesListBody(
      loading: _insightsLoading,
      error: _insightsError,
      onRefresh: _loadInsights,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Health Scores ──
          _sectionHeader(Icons.favorite_rounded, 'Health Scores', count: _health.length),
          if (_health.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Nog geen health score data beschikbaar.',
                style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600)),
            )
          else
            ..._health.map((item) {
              final name = mapStr(item, ['client_name', 'name', 'full_name']).isEmpty
                  ? 'Klant'
                  : mapStr(item, ['client_name', 'name', 'full_name']);
              final score = mapInt(item, ['health_score', 'score']);
              final retentionRisk = mapStr(item, ['retention_risk', 'risk_label', 'risk']);
              final noShowRisk = mapStr(item, ['no_show_risk', 'noshow_risk']);
              final hColor = _healthColor(score);
              final healthInitials = name.length >= 2
                  ? '${name[0]}${name.split(' ').length > 1 ? name.split(' ').last[0] : name[1]}'.toUpperCase()
                  : (name.isNotEmpty ? name[0].toUpperCase() : '?');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: hColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            bottomLeft: Radius.circular(3),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade200, width: 0.5),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(10),
                              bottomRight: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                  color: GymiesColors.darkBlue,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    healthInitials,
                                    style: GoogleFonts.sora(
                                      fontWeight: FontWeight.w600,
                                      color: GymiesColors.primary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(name,
                                            style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 13, color: GymiesColors.darkBlue),
                                            overflow: TextOverflow.ellipsis),
                                        ),
                                        Text('$score',
                                          style: GoogleFonts.sora(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: hColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(2),
                                            child: LinearProgressIndicator(
                                              value: (score / 100).clamp(0.0, 1.0),
                                              minHeight: 4,
                                              backgroundColor: Colors.grey.shade200,
                                              valueColor: AlwaysStoppedAnimation<Color>(hColor),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          flex: 3,
                                          child: Text(
                                            'Retention: ${retentionRisk.isEmpty ? '-' : retentionRisk} · No-show: ${noShowRisk.isEmpty ? '-' : noShowRisk}',
                                            style: GoogleFonts.sora(fontSize: 10, color: Colors.grey.shade500),
                                            overflow: TextOverflow.ellipsis,
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
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),

          // ── Upsell Suggesties ──
          _sectionHeader(Icons.trending_up_rounded, 'Upsell suggesties', count: _upsell.length),
          if (_upsell.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Nog geen upsell suggesties beschikbaar.',
                style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600)),
            )
          else
            ..._upsell.map((item) {
              final name = mapStr(item, ['client_name', 'name']).isEmpty
                  ? 'Klant'
                  : mapStr(item, ['client_name', 'name']);
              final reason = mapStr(item, ['reason', 'explanation']);
              final packageName = mapStr(item, ['package_name', 'offer', 'target_package']);
              final upsellInitials = name.length >= 2
                  ? '${name[0]}${name.split(' ').length > 1 ? name.split(' ').last[0] : name[1]}'.toUpperCase()
                  : (name.isNotEmpty ? name[0].toUpperCase() : '?');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: GymiesColors.primary,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            bottomLeft: Radius.circular(3),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade200, width: 0.5),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(10),
                              bottomRight: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                  color: GymiesColors.darkBlue,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    upsellInitials,
                                    style: GoogleFonts.sora(
                                      fontWeight: FontWeight.w600,
                                      color: GymiesColors.primary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 13, color: GymiesColors.darkBlue)),
                                    const SizedBox(height: 2),
                                    Text(
                                      packageName.isEmpty ? 'Pakket-upgrade' : packageName,
                                      style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                    if (reason.isNotEmpty) ...[
                                      const SizedBox(height: 1),
                                      Text(reason,
                                        style: GoogleFonts.sora(fontSize: 10, color: Colors.grey.shade500),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _insightsBusy ? null : () => _sendUpsell(item),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: GymiesColors.darkBlue,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.send_rounded, size: 13, color: GymiesColors.primary),
                                      const SizedBox(width: 4),
                                      Text('Stuur',
                                        style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: GymiesColors.primary)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),

          // ── Smart Rebook ──
          _sectionHeader(Icons.autorenew_rounded, 'Smart Rebook'),

          // Auto-rebook settings card
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200, width: 0.5),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Auto-herboekingen',
                              style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14, color: GymiesColors.darkBlue)),
                            const SizedBox(height: 2),
                            Text(
                              _autoRebookEnabled
                                  ? 'Herinnering na $_rebookIntervalDays dagen inactiviteit'
                                  : 'Schakel in voor automatische herinneringen',
                              style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      if (_rebookSettingsLoading)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Switch.adaptive(
                          value: _autoRebookEnabled,
                          onChanged: _toggleAutoRebook,
                          activeColor: GymiesColors.primary,
                          activeTrackColor: GymiesColors.primary.withValues(alpha: 0.3),
                        ),
                    ],
                  ),
                  if (_autoRebookEnabled) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _showIntervalPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.timer_outlined, size: 18, color: Colors.grey.shade600),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('Interval: $_rebookIntervalDays dagen',
                                style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w500)),
                            ),
                            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, size: 18, color: Colors.green.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Berichten worden automatisch verstuurd. Je kunt dit altijd uitschakelen.',
                              style: GoogleFonts.sora(fontSize: 12, color: Colors.green.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),

          // ── Pakket verloop alerts ──
          if (_packageExpiring.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'PAKKETTEN BIJNA VERLOPEN',
                  style: GoogleFonts.sora(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '· ${_packageExpiring.length}',
                  style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._packageExpiring.map((pkg) {
              final clientName = mapStr(pkg, ['client_name', 'name']).isEmpty
                  ? 'Klant'
                  : mapStr(pkg, ['client_name', 'name']);
              final packageName = mapStr(pkg, ['package_name', 'packageName']);
              final daysLeft = mapInt(pkg, ['days_remaining', 'daysRemaining', 'days_left']);
              final sessionsLeft = mapInt(pkg, ['sessions_remaining', 'sessionsRemaining']);
              final pkgColor = daysLeft <= 3 ? Colors.red.shade700 : Colors.orange.shade800;
              final pkgInitials = clientName.length >= 2
                  ? '${clientName[0]}${clientName.split(' ').length > 1 ? clientName.split(' ').last[0] : clientName[1]}'.toUpperCase()
                  : (clientName.isNotEmpty ? clientName[0].toUpperCase() : '?');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: pkgColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            bottomLeft: Radius.circular(3),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade200, width: 0.5),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(10),
                              bottomRight: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                  color: GymiesColors.darkBlue,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    pkgInitials,
                                    style: GoogleFonts.sora(
                                      fontWeight: FontWeight.w600,
                                      color: GymiesColors.primary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(clientName, style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 13, color: GymiesColors.darkBlue)),
                                    const SizedBox(height: 2),
                                    Text(
                                      packageName.isNotEmpty
                                          ? '$packageName · ${sessionsLeft > 0 ? '$sessionsLeft sessies over' : 'Bijna op'}'
                                          : 'Pakket bijna verlopen',
                                      style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: pkgColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  daysLeft <= 0 ? 'Verlopen' : '$daysLeft d',
                                  style: GoogleFonts.sora(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: pkgColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],

          // ── Inactieve klanten ──
          Row(
            children: [
              Text(
                'INACTIEVE KLANTEN',
                style: GoogleFonts.sora(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: GymiesColors.darkBlue,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '· ${_rebook.length}',
                style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
              ),
              const Spacer(),
              if (_rebook.length > 1)
                GestureDetector(
                  onTap: _insightsBusy ? null : _sendRebookAll,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: GymiesColors.darkBlue,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.send_rounded, size: 12, color: GymiesColors.primary),
                        const SizedBox(width: 4),
                        Text('Alles',
                          style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: GymiesColors.primary)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_rebook.isEmpty)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200, width: 0.5),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline, size: 36, color: Colors.green.shade400),
                  const SizedBox(height: 10),
                  Text('Alle klanten zijn actief!',
                    style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 14, color: GymiesColors.darkBlue)),
                  const SizedBox(height: 4),
                  Text(
                    'Klanten verschijnen hier na $_rebookIntervalDays dagen zonder sessie.',
                    style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ..._rebook.map((item) {
              final name = mapStr(item, ['client_name', 'name']).isEmpty
                  ? 'Klant'
                  : mapStr(item, ['client_name', 'name']);
              final daysSince = mapInt(item, ['days_since_last', 'daysSinceLast']);
              final email = mapStr(item, ['email', 'client_email']);
              final rebookColor = daysSince >= 14 ? Colors.red.shade700 : Colors.orange.shade800;
              final rebookInitials = name.length >= 2
                  ? '${name[0]}${name.split(' ').length > 1 ? name.split(' ').last[0] : name[1]}'.toUpperCase()
                  : (name.isNotEmpty ? name[0].toUpperCase() : '?');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: rebookColor,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            bottomLeft: Radius.circular(3),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade200, width: 0.5),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(10),
                              bottomRight: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                  color: GymiesColors.darkBlue,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    rebookInitials,
                                    style: GoogleFonts.sora(
                                      fontWeight: FontWeight.w600,
                                      color: GymiesColors.primary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(name,
                                            style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 13, color: GymiesColors.darkBlue),
                                            overflow: TextOverflow.ellipsis),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: rebookColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Text(
                                            daysSince > 0 ? '$daysSince d' : '7+ d',
                                            style: GoogleFonts.sora(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: rebookColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      daysSince > 0
                                          ? '${daysSince == 1 ? '1 dag' : '$daysSince dagen'} sinds laatste sessie${email.isNotEmpty ? ' · $email' : ''}'
                                          : 'Langer dan 7 dagen inactief',
                                      style: GoogleFonts.sora(fontSize: 10, color: Colors.grey.shade500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: _insightsBusy ? null : () => _sendRebook(item),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: GymiesColors.darkBlue,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.favorite_rounded, size: 13, color: GymiesColors.primary),
                                      const SizedBox(width: 4),
                                      Text('Herinner',
                                        style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.w600, color: GymiesColors.primary)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
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
    );
  }

  // ── Tab 2: Meer (Analytics + Communicatie merged) ──
  Widget _buildMeerTab({required bool isPro, required bool isProPlus}) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Analytics samenvatting ──
        Row(
          children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(color: GymiesColors.darkBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
              child: const Icon(Icons.analytics_outlined, size: 14, color: GymiesColors.darkBlue),
            ),
            const SizedBox(width: 10),
            Text('Analytics', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _StripeSummaryCard(label: 'Actief', value: '$_activeCount', color: Colors.green.shade700)),
            const SizedBox(width: 8),
            Expanded(child: _StripeSummaryCard(label: 'Risico', value: '$_riskCount', color: Colors.orange.shade800)),
            const SizedBox(width: 8),
            Expanded(child: _StripeSummaryCard(label: 'Inactief', value: '$_inactiveCount', color: Colors.red.shade700)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _StripeSummaryCard(label: 'Sessies', value: '$_totalSessions', color: GymiesColors.darkBlue)),
            const SizedBox(width: 8),
            Expanded(child: _StripeSummaryCard(label: 'Omzet', value: '€${_totalRevenue.toStringAsFixed(0)}', color: GymiesColors.darkBlue)),
          ],
        ),
        const SizedBox(height: 24),

        // ── Communicatie ──
        Row(
          children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(color: GymiesColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(7)),
              child: const Icon(Icons.campaign_outlined, size: 14, color: GymiesColors.darkBlue),
            ),
            const SizedBox(width: 10),
            Text('Communicatie', style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: GymiesColors.darkBlue)),
          ],
        ),
        const SizedBox(height: 10),
        // Bulk bericht
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200, width: 0.5),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Stuur een bericht naar al je klanten tegelijk.',
                style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _bulkMessage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: GymiesColors.darkBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.send_rounded, size: 16, color: GymiesColors.primary),
                        const SizedBox(width: 8),
                        Text('Bulk bericht versturen',
                          style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: GymiesColors.primary)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Priority support
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200, width: 0.5),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Voor urgente operationele issues met contextpakket.',
                style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: _openPrioritySupportComposer,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: GymiesColors.darkBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.support_agent_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Text('Open priority lane',
                          style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Tab 2: Analytics (Pro+) ──
  Widget _buildAnalyticsTab() {
    if (_analyticsLoading && _analyticsClients.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _analyticsLoading && _analyticsClients.isEmpty) _loadAnalytics();
      });
      return const TrainerLoadingView();
    }
    return GymiesListBody(
      loading: _analyticsLoading,
      error: _analyticsError,
      onRefresh: _loadAnalytics,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Summary cards — Stripe style
          Row(
            children: [
              Expanded(child: _StripeSummaryCard(label: 'Actief', value: '$_activeCount', color: Colors.green.shade700)),
              const SizedBox(width: 8),
              Expanded(child: _StripeSummaryCard(label: 'Risico', value: '$_riskCount', color: Colors.orange.shade800)),
              const SizedBox(width: 8),
              Expanded(child: _StripeSummaryCard(label: 'Inactief', value: '$_inactiveCount', color: Colors.red.shade700)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _StripeSummaryCard(label: 'Sessies', value: '$_totalSessions', color: GymiesColors.darkBlue)),
              const SizedBox(width: 8),
              Expanded(child: _StripeSummaryCard(label: 'Omzet', value: '€${_totalRevenue.toStringAsFixed(0)}', color: GymiesColors.darkBlue)),
            ],
          ),
          const SizedBox(height: 20),

          // Filter chips
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

          Text(
            '${_filteredAnalyticsClients.length} klant${_filteredAnalyticsClients.length == 1 ? '' : 'en'}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),

          if (_filteredAnalyticsClients.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('Geen klanten gevonden voor dit filter.', style: TextStyle(color: Colors.grey.shade500)),
              ),
            )
          else
            ..._filteredAnalyticsClients.map((client) {
              final name = mapStr(client, ['name', 'client_name', 'full_name']);
              final status = mapStr(client, ['status', 'client_status']);
              final sessions = mapInt(client, ['session_count', 'sessions', 'total_sessions']);
              final revenue = (client['revenue'] as num?)?.toDouble() ??
                  (client['total_revenue'] as num?)?.toDouble() ?? 0;
              final lastSession = mapStr(client, ['last_session_at', 'last_session', 'lastSessionAt']);
              final aStatusClr = _statusColor(status);
              final aIsInactive = status.toLowerCase() == 'inactive' || status.toLowerCase() == 'inactief';
              final aInitials = name.length >= 2
                  ? '${name[0]}${name.split(' ').length > 1 ? name.split(' ').last[0] : name[1]}'.toUpperCase()
                  : (name.isNotEmpty ? name[0].toUpperCase() : '?');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: aStatusClr,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            bottomLeft: Radius.circular(3),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade200, width: 0.5),
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(10),
                              bottomRight: Radius.circular(10),
                            ),
                          ),
                          child: Opacity(
                            opacity: aIsInactive ? 0.7 : 1.0,
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: aIsInactive ? aStatusClr : GymiesColors.darkBlue,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      aInitials,
                                      style: GoogleFonts.sora(
                                        fontWeight: FontWeight.w600,
                                        color: aIsInactive ? Colors.white : GymiesColors.primary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              name.isNotEmpty ? name : 'Klant',
                                              style: GoogleFonts.sora(fontWeight: FontWeight.w600, fontSize: 13, color: GymiesColors.darkBlue),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: aStatusClr.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(5),
                                            ),
                                            child: Text(
                                              _statusLabel(status),
                                              style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.w600, color: aStatusClr),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '$sessions sessies · €${revenue.toStringAsFixed(0)}${lastSession.isNotEmpty ? ' · $lastSession' : ''}',
                                        style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
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
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _analyticsFilter == value;
    return GestureDetector(
      onTap: () {
        Haptics.selection();
        _setAnalyticsFilter(value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? GymiesColors.primary.withValues(alpha: 0.12)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? GymiesColors.primary : Colors.grey.shade200,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.sora(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? GymiesColors.darkBlue : Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ── Tab 3: Communicatie (Pro+) ──
  Widget _buildCommunicationTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Bulk bericht
        _sectionHeader(Icons.campaign_outlined, 'Bulk bericht'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200, width: 0.5),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Text('Stuur een bericht naar al je klanten tegelijk.',
                  style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _bulkMessage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: GymiesColors.darkBlue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.send_rounded, size: 16, color: GymiesColors.primary),
                          const SizedBox(width: 8),
                          Text('Bulk bericht versturen',
                            style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: GymiesColors.primary)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // Priority support
        _sectionHeader(Icons.priority_high_rounded, 'Priority support'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200, width: 0.5),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Text('Voor urgente operationele issues met contextpakket.',
                  style: GoogleFonts.sora(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _openPrioritySupportComposer,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: GymiesColors.darkBlue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.support_agent_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text('Open priority lane',
                            style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Stripe-style Summary Card (Analytics tab) ──
class _StripeSummaryCard extends StatelessWidget {
  const _StripeSummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.sora(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }
}
