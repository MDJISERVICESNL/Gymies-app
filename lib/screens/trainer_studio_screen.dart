import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import '../utils/currency_format.dart';
import 'trainer_onboarding_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/gymies_dialog.dart';
import 'widgets/trainer_state_views.dart';
import '../utils/haptics.dart';

class TrainerStudioScreen extends StatefulWidget {
  const TrainerStudioScreen({super.key});

  @override
  State<TrainerStudioScreen> createState() => _TrainerStudioScreenState();
}

class _TrainerStudioScreenState extends State<TrainerStudioScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _performance = {};
  List<Map<String, dynamic>> _safetyLog = [];
  Map<String, dynamic> _onboarding = {};
  Map<String, dynamic> _subscription = {};
  List<Map<String, dynamic>> _plans = [];

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
      final performance = await api.getTrainerStudioPerformanceSummary();
      final safety = await api.getTrainerStudioSafetyLog();
      final onboarding = await api.getOnboardingStatus();
      final subscription = await api.getMySubscription();
      final plans = await api.getPlans();
      if (!mounted) return;
      setState(() {
        _performance = performance;
        _safetyLog = safety;
        _onboarding = onboarding;
        _subscription = subscription;
        _plans = plans;
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
        _error = S.of(context).konStudioonboardingNietLaden;
        _loading = false;
      });
    }
  }

  Future<void> _connectMollie() async {
    Haptics.selection();
    if (_busy) return;
    setState(() => _busy = true);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TrainerOnboardingScreen(initialStep: 4),
      ),
    );
    if (!mounted) return;
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _selectPlan(String planId) async {
    Haptics.light();
    await _runAction(() async {
      await context.read<GymiesApi>().selectOnboardingPlan(planId);
      _success('Plan geselecteerd');
    });
  }

  Future<void> _cancelSubscription() async {
    Haptics.heavy();
    final confirmed = await GymiesDialog.destructive(
      context,
      title: S.of(context).abonnementOpzeggen,
      message: S.of(context).weetJeZekerDatJeJe2,
      icon: Icons.warning_amber_rounded,
      confirmLabel: S.of(context).opzeggen,
    );
    if (confirmed != true || !mounted) return;
    await _runAction(() async {
      await context.read<GymiesApi>().cancelMySubscription();
      _success(S.of(context).abonnementOpgezegd);
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _success(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: GymiesColors.darkBlue),
    );
  }

  int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  String _money(dynamic cents) {
    final value = _toInt(cents);
    return formatEuro(value, fallback: '-');
  }

  Widget _sectionHeader(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: GymiesColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: GymiesColors.darkBlue),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.sora(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: GymiesColors.darkBlue,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: GymiesAppBar(
        title: S.of(context).studioEnOnboarding,
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionHeader(Icons.analytics_outlined, 'Performance'),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: ListTile(
                      title: Text(S.of(context).performanceSummary, style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'Score: ${mapStr(_performance, ['score', 'health_score']).isNotEmpty ? mapStr(_performance, ['score', 'health_score']) : '-'}\n'
                        'Omzet: ${_money(mapPick(_performance, ['revenue_cents', 'revenueCents']))}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _sectionHeader(Icons.shield_outlined, 'Safety log'),
                  ..._safetyLog.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: ListTile(
                          title: Text(
                            mapStr(e, ['title', 'event', 'type']).isNotEmpty
                                ? mapStr(e, ['title', 'event', 'type'])
                                : 'Log',
                          ),
                          subtitle: Text(
                            mapStr(e, [
                                  'created_at',
                                  'createdAt',
                                  'date',
                                ]).isNotEmpty
                                ? mapStr(e, ['created_at', 'createdAt', 'date'])
                                : e.toString(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _sectionHeader(Icons.rocket_launch_outlined, 'Onboarding'),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: ListTile(
                      title: Text(S.of(context).onboardingStatus, style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'Status: ${mapStr(_onboarding, ['status', 'phase']).isNotEmpty ? mapStr(_onboarding, ['status', 'phase']) : '-'}',
                      ),
                      trailing: FilledButton(
                        onPressed: _busy ? null : _connectMollie,
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                        ),
                        child: const Text(S.of(context).mollieConnect),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _sectionHeader(Icons.credit_card_outlined, S.of(context).abonnement),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: ListTile(
                      title: Text(S.of(context).abonnement, style: GoogleFonts.sora(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${mapStr(_subscription, ['plan_name', 'name']).isNotEmpty ? mapStr(_subscription, ['plan_name', 'name']) : S.of(context).statusOnbekend} · '
                        '${mapStr(_subscription, ['status']).isNotEmpty ? mapStr(_subscription, ['status']) : '-'}',
                      ),
                      trailing: TextButton(
                        onPressed: _busy ? null : _cancelSubscription,
                        child: const Text(S.of(context).opzeggen),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _sectionHeader(Icons.card_membership_outlined, S.of(context).beschikbarePlannen),
                  ..._plans.map(
                    (p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: ListTile(
                          title: Text(
                            mapStr(p, ['name', 'title']).isNotEmpty
                                ? mapStr(p, ['name', 'title'])
                                : 'Plan',
                          ),
                          subtitle: Text(
                            mapStr(p, ['price']).isNotEmpty
                                ? mapStr(p, ['price'])
                                : _money(mapPick(p, ['price_cents', 'priceCents'])),
                          ),
                          trailing: FilledButton(
                            onPressed: _busy
                                ? null
                                : () => _selectPlan(mapStr(p, ['id', 'plan_id'])),
                            style: FilledButton.styleFrom(
                              backgroundColor: GymiesColors.primary,
                              foregroundColor: GymiesColors.darkBlue,
                            ),
                            child: const Text(S.of(context).kies),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
