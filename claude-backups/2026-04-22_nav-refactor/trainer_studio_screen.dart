import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/gymies_api.dart';
import '../theme/gymies_theme.dart';
import '../utils/map_utils.dart';
import 'trainer_onboarding_screen.dart';
import 'widgets/gymies_app_bar.dart';
import 'widgets/trainer_state_views.dart';

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
        _error = 'Kon studio/onboarding niet laden.';
        _loading = false;
      });
    }
  }

  Future<void> _connectMollie() async {
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
    await _runAction(() async {
      await context.read<GymiesApi>().selectOnboardingPlan(planId);
      _success('Plan geselecteerd');
    });
  }

  Future<void> _cancelSubscription() async {
    await _runAction(() async {
      await context.read<GymiesApi>().cancelMySubscription();
      _success('Abonnement opgezegd');
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
    if (value == null) return '-';
    return '€${(value / 100).toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: GymiesAppBar(
        title: 'Studio & Onboarding',
      ),
      body: GymiesListBody(
        loading: _loading,
        error: _error,
        onRefresh: _load,
        child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      title: const Text('Performance summary'),
                      subtitle: Text(
                        'Score: ${mapStr(_performance, ['score', 'health_score']).isNotEmpty ? mapStr(_performance, ['score', 'health_score']) : '-'}\n'
                        'Omzet: ${_money(mapPick(_performance, ['revenue_cents', 'revenueCents']))}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Safety log'),
                  ..._safetyLog.map(
                    (e) => Card(
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
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      title: const Text('Onboarding status'),
                      subtitle: Text(
                        'Status: ${mapStr(_onboarding, ['status', 'phase']).isNotEmpty ? mapStr(_onboarding, ['status', 'phase']) : '-'}',
                      ),
                      trailing: FilledButton(
                        onPressed: _busy ? null : _connectMollie,
                        style: FilledButton.styleFrom(
                          backgroundColor: GymiesColors.primary,
                          foregroundColor: GymiesColors.darkBlue,
                        ),
                        child: const Text('Mollie connect'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      title: const Text('Abonnement'),
                      subtitle: Text(
                        '${mapStr(_subscription, ['plan_name', 'name']).isNotEmpty ? mapStr(_subscription, ['plan_name', 'name']) : 'Onbekend'} · '
                        '${mapStr(_subscription, ['status']).isNotEmpty ? mapStr(_subscription, ['status']) : '-'}',
                      ),
                      trailing: TextButton(
                        onPressed: _busy ? null : _cancelSubscription,
                        child: const Text('Opzeggen'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Beschikbare plannen'),
                  ..._plans.map(
                    (p) => Card(
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
                          child: const Text('Kies'),
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
