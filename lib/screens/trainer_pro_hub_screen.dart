import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/gymies_segment_tab_bar.dart';
import 'widgets/trainer_state_views.dart';
import '../utils/haptics.dart';
import '../l10n/generated/app_localizations.dart';

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
        _health = List<Map<String, dynamic>>.from(results[0] as List);
        _upsell = List<Map<String, dynamic>>.from(results[1] as List);
        _rebook = List<Map<String, dynamic>>.from(results[2] as List);
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
        _error = S.of(context).konProHubNietLaden;
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
    Haptics.light();
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
          content: Text(S.of(context).upsellVoorstelVerstuurd),
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
    Haptics.light();
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
            S.of(context).weMissenJePlanJeVolgende,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(S.of(context).weMissenJeberichtVerstuurd),
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
    Haptics.selection();
    final issueCtrl = TextEditingController();
    final bookingCtrl = TextEditingController();
    final submit = await GymiesDialog.custom<bool>(
      context,
      title: S.of(context).prioritySupportLane,
      icon: Icons.priority_high_rounded,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: issueCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: S.of(context).issue,
              hintText: S.of(context).beschrijfKortHetUrgenteProbleem,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: bookingCtrl,
            decoration: const InputDecoration(
              labelText: S.of(context).bookingReferenceoptioneel,
            ),
          ),
        ],
      ),
      actions: [
        GymiesDialogAction(
          label: S.of(context).annuleren,
          returnValue: false,
        ),
        GymiesDialogAction(
          label: S.of(context).verstuur,
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
        subject: S.of(context).prioritySupportLane,
        message:
            'Priority issue: ${issueCtrl.text.trim()}\nBookingRef: ${bookingCtrl.text.trim().isEmpty ? '-' : bookingCtrl.text.trim()}\nSource: TrainerProHub',
        bookingId: bookingCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(S.of(context).prioritySupportTicketVerstuurd),
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
        child: Text(S.of(context).nogGeenHealthScoreDataBeschikbaar),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _health.length,
      itemBuilder: (_, i) {
        final item = _health[i];
        final name = mapStr(item, ['client_name', 'name', 'full_name']).isEmpty
            ? S.of(context).clientSingle
            : mapStr(item, ['client_name', 'name', 'full_name']);
        final score = mapInt(item, ['health_score', 'score']);
        final retentionRisk = mapStr(item, [
          'retention_risk',
          'risk_label',
          'risk',
        ]);
        final noShowRisk = mapStr(item, ['no_show_risk', 'noshow_risk']);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _healthColor(score).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '$score',
                      style: TextStyle(
                        color: _healthColor(score),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: GoogleFonts.sora(fontWeight: FontWeight.w600, color: GymiesColors.darkBlue)),
                      const SizedBox(height: 4),
                      Text(
                        'Retention: ${retentionRisk.isEmpty ? '-' : retentionRisk} · No-show: ${noShowRisk.isEmpty ? '-' : noShowRisk}',
                        style: GoogleFonts.sora(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _upsellTab() {
    if (_upsell.isEmpty) {
      return const Center(
        child: Text(S.of(context).nogGeenUpsellSuggestiesBeschikbaar),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _upsell.length,
      itemBuilder: (_, i) {
        final item = _upsell[i];
        final name = mapStr(item, ['client_name', 'name']).isEmpty
            ? S.of(context).clientSingle
            : mapStr(item, ['client_name', 'name']);
        final reason = mapStr(item, ['reason', 'explanation']);
        final packageName = mapStr(item, [
          'package_name',
          'offer',
          'target_package',
        ]);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))]),
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
                    label: const Text(S.of(context).stuurVoorstel),
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
          S.of(context).geenSmartRebookAlertsnklantenVerschijnenHierAlsZeLangerDan7DagenGeenSessieHadden,
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
            ? S.of(context).clientSingle
            : mapStr(item, ['client_name', 'name']);
        final daysSince = mapInt(item, ['days_since_last', 'daysSinceLast']);
        final lastAt = mapStr(item, ['last_session_at', 'lastSessionAt']);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  daysSince > 0
                      ? '${daysSince == 1 ? '1 dag' : '$daysSince dagen'} geleden laatste sessie'
                      : (lastAt.isEmpty
                          ? S.of(context).laatsteSessieMeerDan7Dagen
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
                    label: const Text(S.of(context).weMissenJe),
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
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context).prioritySupportLane,
                  style: GoogleFonts.sora(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: GymiesColors.darkBlue,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  S.of(context).voorUrgenteOperationeleIssuesMetContextpakketissueBookingRefs,
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
                    label: const Text(S.of(context).openPriorityLane),
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
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: 'Pro Hub',
        bottom: GymiesSegmentTabBar(
          controller: _tabController,
          tabs: const ['Health', 'Upsell', 'Herboek', 'Priority'],
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
