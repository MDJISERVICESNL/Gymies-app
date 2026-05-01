import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

class TrainerProHubScreen extends StatefulWidget {
  const TrainerProHubScreen({super.key});

  @override
  State<TrainerProHubScreen> createState() => _TrainerProHubScreenState();
}

class _TrainerProHubScreenState extends State<TrainerProHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _health = [];
  List<Map<String, dynamic>> _upsell = [];
  List<Map<String, dynamic>> _rebook = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
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
        _error = 'Kon Pro Hub niet laden.';
        _loading = false;
      });
    }
  }

  Color _healthColor(int score) {
    if (score >= 75) return Colors.green.shade700;
    if (score >= 50) return Colors.orange.shade800;
    return Colors.red.shade700;
  }

  Future<void> _sendUpsell(Map<String, dynamic> item) async {
    if (_busy) return;
    final suggestionId = mapStr(item, [
      'id',
      'suggestion_id',
      'suggestionId',
    ]).trim();
    if (suggestionId.isEmpty) return;
    setState(() => _busy = true);
    try {
      await context.read<GymiesApi>().sendTrainerUpsellSuggestion(
        suggestionId: suggestionId,
        clientUserId: mapStr(item, ['client_user_id', 'clientUserId']),
        packageId: mapStr(item, ['package_id', 'packageId']),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upsell voorstel verstuurd'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendRebook(Map<String, dynamic> item) async {
    if (_busy) return;
    final clientUserId = mapStr(item, [
      'id',
      'client_user_id',
      'clientUserId',
    ]).trim();
    if (clientUserId.isEmpty) return;
    setState(() => _busy = true);
    try {
      await context.read<GymiesApi>().sendTrainerBulkMessage(
        clientUserIds: [clientUserId],
        body:
            'We missen je! Plan je volgende sessie via Mijn afspraken in de app.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We missen je-bericht verstuurd'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            'Priority issue: ${issueCtrl.text.trim()}\nBookingRef: ${bookingCtrl.text.trim().isEmpty ? '-' : bookingCtrl.text.trim()}\nSource: TrainerProHub',
        bookingId: bookingCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Priority support ticket verstuurd'),
          backgroundColor: GymiesColors.darkBlue,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    }
  }

  Widget _healthTab() {
    if (_health.isEmpty) {
      return const Center(
        child: Text('Nog geen health score data beschikbaar.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _health.length,
      itemBuilder: (_, i) {
        final item = _health[i];
        final name = mapStr(item, ['client_name', 'name', 'full_name']).isEmpty
            ? 'Klant'
            : mapStr(item, ['client_name', 'name', 'full_name']);
        final score = mapInt(item, ['health_score', 'score']);
        final retentionRisk = mapStr(item, [
          'retention_risk',
          'risk_label',
          'risk',
        ]);
        final noShowRisk = mapStr(item, ['no_show_risk', 'noshow_risk']);
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _healthColor(score).withValues(alpha: 0.15),
              child: Text(
                '$score',
                style: TextStyle(
                  color: _healthColor(score),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            title: Text(name),
            subtitle: Text(
              'Retention: ${retentionRisk.isEmpty ? '-' : retentionRisk} · No-show: ${noShowRisk.isEmpty ? '-' : noShowRisk}',
            ),
          ),
        );
      },
    );
  }

  Widget _upsellTab() {
    if (_upsell.isEmpty) {
      return const Center(
        child: Text('Nog geen upsell suggesties beschikbaar.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _upsell.length,
      itemBuilder: (_, i) {
        final item = _upsell[i];
        final name = mapStr(item, ['client_name', 'name']).isEmpty
            ? 'Klant'
            : mapStr(item, ['client_name', 'name']);
        final reason = mapStr(item, ['reason', 'explanation']);
        final packageName = mapStr(item, [
          'package_name',
          'offer',
          'target_package',
        ]);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  packageName.isEmpty
                      ? 'Aanbeveling: pakket-upgrade'
                      : 'Aanbeveling: $packageName',
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(reason),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _sendUpsell(item),
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
      },
    );
  }

  Widget _rebookTab() {
    if (_rebook.isEmpty) {
      return const Center(
        child: Text(
          'Geen Smart Rebook alerts.\nKlanten verschijnen hier als ze langer dan 7 dagen geen sessie hadden.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _rebook.length,
      itemBuilder: (_, i) {
        final item = _rebook[i];
        final name = mapStr(item, ['client_name', 'name']).isEmpty
            ? 'Klant'
            : mapStr(item, ['client_name', 'name']);
        final daysSince = mapInt(item, ['days_since_last', 'daysSinceLast']);
        final lastAt = mapStr(item, ['last_session_at', 'lastSessionAt']);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  daysSince > 0
                      ? '$daysSince dagen geleden laatste sessie'
                      : (lastAt.isEmpty
                          ? 'Laatste sessie meer dan 7 dagen geleden'
                          : lastAt),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _sendRebook(item),
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
      },
    );
  }

  Widget _supportTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Priority support lane',
                  style: GoogleFonts.fjallaOne(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Voor urgente operationele issues met contextpakket (issue + booking refs).',
                ),
                const SizedBox(height: 10),
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
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Pro Hub',
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GymiesColors.primary,
          labelColor: GymiesColors.primary,
          tabs: const [
            Tab(text: 'Health'),
            Tab(text: 'Upsell'),
            Tab(text: 'Herboek'),
            Tab(text: 'Priority'),
          ],
        ),
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: TabBarView(
              controller: _tabController,
              children: [
                _healthTab(),
                _upsellTab(),
                _rebookTab(),
                _supportTab(),
              ],
            ),
      ),
    );
  }
}
