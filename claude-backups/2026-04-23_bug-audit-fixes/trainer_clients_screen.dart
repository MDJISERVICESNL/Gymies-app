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
import 'widgets/gymies_section_header.dart';
import 'widgets/gymies_upgrade_prompt.dart';
import 'widgets/trainer_state_views.dart';

/// Klanten CRM-centrum: Overzicht, Inzichten (Pro), Analytics (Pro+), Communicatie (Pro+).
class TrainerClientsScreen extends StatefulWidget {
  const TrainerClientsScreen({
    super.key,
    this.onAvatarTap,
    this.avatarLabel,
  });

  final VoidCallback? onAvatarTap;
  final String? avatarLabel;

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
    _tabController = TabController(length: 4, vsync: this);
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
    if (s == 'risk' || s == 'at_risk' || s == 'risico') return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  String _statusLabel(String status) {
    final s = status.toLowerCase();
    if (s == 'active' || s == 'actief') return 'Actief';
    if (s == 'risk' || s == 'at_risk' || s == 'risico') return 'Risico';
    if (s == 'inactive' || s == 'inactief') return 'Inactief';
    return status;
  }

  Future<void> _openClient(Map<String, dynamic> client) async {
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

  Future<void> _bulkMessage() async {
    if (_clients.isEmpty) return;
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var sending = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Bulk bericht'),
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
              TextButton(
                onPressed: sending ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Annuleren'),
              ),
              FilledButton(
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
                          debugPrint('[TrainerClients] Bulk bericht fout: $e');
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: GymiesColors.primary,
                  foregroundColor: GymiesColors.darkBlue,
                ),
                child: Text(sending ? 'Bezig…' : 'Versturen'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openPrioritySupportComposer() async {
    final issueCtrl = TextEditingController();
    final bookingCtrl = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Priority support lane'),
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: GymiesColors.primary,
              foregroundColor: GymiesColors.darkBlue,
            ),
            child: const Text('Verstuur'),
          ),
        ],
      ),
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
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Klanten',
        onAvatarTap: widget.onAvatarTap,
        avatarLabel: widget.avatarLabel,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GymiesColors.primary,
          labelColor: GymiesColors.primary,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Overzicht'),
            Tab(text: 'Inzichten'),
            Tab(text: 'Analytics'),
            Tab(text: 'Communicatie'),
          ],
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
              ? _buildAnalyticsTab()
              : GymiesUpgradePrompt(
                  icon: Icons.analytics_outlined,
                  feature: 'Klant Analytics',
                  tier: isPro ? 'Pro+' : 'Pro',
                  description: 'Segmenteer je klanten op activiteit en omzet. Zie precies waar je groei zit.',
                ),
          isProPlus
              ? _buildCommunicationTab()
              : GymiesUpgradePrompt(
                  icon: Icons.campaign_outlined,
                  feature: 'Klant Communicatie',
                  tier: isPro ? 'Pro+' : 'Pro',
                  description: 'Stuur bulk berichten naar je klanten en gebruik de priority support lane.',
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
              decoration: InputDecoration(
                hintText: 'Zoek op naam...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
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
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: GymiesColors.primary.withValues(alpha: 0.2),
                            child: Text(
                              name[0].toUpperCase(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: GymiesColors.darkBlue,
                              ),
                            ),
                          ),
                          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            mapStr(c, ['email', 'email_address']),
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                          trailing: const Icon(Icons.chevron_right, color: GymiesColors.darkBlue),
                          onTap: () => _openClient(c),
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
  Widget _buildInsightsTab() {
    if (_insightsLoading && _health.isEmpty) {
      // Eerste keer laden
      if (_health.isEmpty && _upsell.isEmpty && _rebook.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _insightsLoading && _health.isEmpty) _loadInsights();
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
          const GymiesSectionHeader('Health Scores'),
          if (_health.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Nog geen health score data beschikbaar.'),
            )
          else
            ..._health.map((item) {
              final name = mapStr(item, ['client_name', 'name', 'full_name']).isEmpty
                  ? 'Klant'
                  : mapStr(item, ['client_name', 'name', 'full_name']);
              final score = mapInt(item, ['health_score', 'score']);
              final retentionRisk = mapStr(item, ['retention_risk', 'risk_label', 'risk']);
              final noShowRisk = mapStr(item, ['no_show_risk', 'noshow_risk']);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _healthColor(score).withValues(alpha: 0.15),
                    child: Text(
                      '$score',
                      style: TextStyle(color: _healthColor(score), fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(name),
                  subtitle: Text(
                    'Retention: ${retentionRisk.isEmpty ? '-' : retentionRisk} · No-show: ${noShowRisk.isEmpty ? '-' : noShowRisk}',
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),

          // ── Upsell Suggesties ──
          const GymiesSectionHeader('Upsell suggesties'),
          if (_upsell.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Nog geen upsell suggesties beschikbaar.'),
            )
          else
            ..._upsell.map((item) {
              final name = mapStr(item, ['client_name', 'name']).isEmpty
                  ? 'Klant'
                  : mapStr(item, ['client_name', 'name']);
              final reason = mapStr(item, ['reason', 'explanation']);
              final packageName = mapStr(item, ['package_name', 'offer', 'target_package']);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(packageName.isEmpty ? 'Aanbeveling: pakket-upgrade' : 'Aanbeveling: $packageName'),
                      if (reason.isNotEmpty) ...[const SizedBox(height: 4), Text(reason)],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _insightsBusy ? null : () => _sendUpsell(item),
                          style: FilledButton.styleFrom(
                            backgroundColor: GymiesColors.primary,
                            foregroundColor: GymiesColors.darkBlue,
                          ),
                          icon: const Icon(Icons.trending_up_rounded),
                          label: const Text('Stuur voorstel'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 20),

          // ── Smart Rebook ──
          const GymiesSectionHeader('Smart Rebook'),
          if (_rebook.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Geen herboek-alerts.\nKlanten verschijnen hier als ze langer dan 7 dagen geen sessie hadden.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            )
          else
            ..._rebook.map((item) {
              final name = mapStr(item, ['client_name', 'name']).isEmpty
                  ? 'Klant'
                  : mapStr(item, ['client_name', 'name']);
              final daysSince = mapInt(item, ['days_since_last', 'daysSinceLast']);
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(daysSince > 0
                          ? '$daysSince dagen geleden laatste sessie'
                          : 'Laatste sessie meer dan 7 dagen geleden'),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _insightsBusy ? null : () => _sendRebook(item),
                          style: FilledButton.styleFrom(
                            backgroundColor: GymiesColors.primary,
                            foregroundColor: GymiesColors.darkBlue,
                          ),
                          icon: const Icon(Icons.favorite_rounded),
                          label: const Text('We missen je'),
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
          // Summary cards
          Row(
            children: [
              Expanded(child: _SummaryCard(label: 'Actief', value: '$_activeCount', color: Colors.green.shade700, icon: Icons.person_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _SummaryCard(label: 'Risico', value: '$_riskCount', color: Colors.orange.shade800, icon: Icons.warning_amber_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _SummaryCard(label: 'Inactief', value: '$_inactiveCount', color: Colors.red.shade700, icon: Icons.person_off_rounded)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _SummaryCard(label: 'Sessies', value: '$_totalSessions', color: GymiesColors.darkBlue, icon: Icons.fitness_center_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _SummaryCard(label: 'Omzet', value: '€${_totalRevenue.toStringAsFixed(0)}', color: GymiesColors.darkBlue, icon: Icons.euro_rounded)),
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
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _statusColor(status)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name.isNotEmpty ? name : 'Klant',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _statusLabel(status),
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(status)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$sessions sessies · €${revenue.toStringAsFixed(0)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            if (lastSession.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text('Laatst: $lastSession', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
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
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _analyticsFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setAnalyticsFilter(value),
      selectedColor: GymiesColors.primary.withValues(alpha: 0.25),
      checkmarkColor: GymiesColors.darkBlue,
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        color: selected ? GymiesColors.darkBlue : Colors.grey.shade700,
        fontSize: 13,
      ),
      side: BorderSide(color: selected ? GymiesColors.primary : Colors.grey.shade300),
    );
  }

  // ── Tab 3: Communicatie (Pro+) ──
  Widget _buildCommunicationTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Bulk bericht
        const GymiesSectionHeader('Bulk bericht'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stuur een bericht naar al je klanten tegelijk.',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _bulkMessage,
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                    ),
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('Bulk bericht versturen'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Priority support
        const GymiesSectionHeader('Priority support lane'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voor urgente operationele issues met contextpakket (issue + booking refs).',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openPrioritySupportComposer,
                    style: FilledButton.styleFrom(
                      backgroundColor: GymiesColors.primary,
                      foregroundColor: GymiesColors.darkBlue,
                    ),
                    icon: const Icon(Icons.priority_high_rounded),
                    label: const Text('Open priority lane'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Summary Card (Analytics tab) ──
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
              style: GoogleFonts.fjallaOne(fontSize: 20, fontWeight: FontWeight.w700, color: color),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
